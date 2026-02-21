//
//  AttachmentThumbnailStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import Foundation
import UIKit
import QuickLookThumbnailing
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Thumbnail pipeline:
/// - Memory cache (NSCache)
/// - Disk cache (Application Support / BrainMeshAttachments / thumb_<id>.jpg)
/// - Images: Generate via ImageIO downscaling (CGImageSourceCreateThumbnailAtIndex) to guarantee small bitmaps.
/// - Other types: Generate via QuickLookThumbnailing; fallback for videos via AVAssetImageGenerator.
actor AttachmentThumbnailStore {

    static let shared = AttachmentThumbnailStore()

    /// Patch 2 (real throttling): limit the number of concurrent thumbnail generations.
    /// Without this, a large grid/list can trigger dozens/hundreds of QuickLook/AV jobs at once.
    private let generationLimiter = AsyncLimiter(maxConcurrent: 3)

    private let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 250
        return c
    }()

    private var inFlight: [UUID: Task<UIImage?, Never>] = [:]

    // MARK: - Public

    func thumbnail(
        attachmentID: UUID,
        fileURL: URL,
        isVideo: Bool,
        requestSize: CGSize,
        scale: CGFloat
    ) async -> UIImage? {

        let key = cacheKey(for: attachmentID)
        if let hit = memoryCache.object(forKey: key) {
            return hit
        }

        if let disk = Self.loadFromDisk(attachmentID: attachmentID) {
            memoryCache.setObject(disk, forKey: key)
            return disk
        }

        if let existingTask = inFlight[attachmentID] {
            return await existingTask.value
        }

        let task = Task<UIImage?, Never> {
            await self.generationLimiter.withPermit {
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

                let maxPixelSize = Self.maxPixelSize(for: requestSize, scale: scale)

                // Root fix: images are downscaled via ImageIO to guarantee small bitmaps.
                if !isVideo, Self.isImageFile(fileURL: fileURL) {
                    if let img = await Self.generateImageIOThumbnail(
                        fileURL: fileURL,
                        maxPixelSize: maxPixelSize,
                        scale: scale
                    ) {
                        return img
                    }
                }

                // QuickLook thumbnail (works for PDFs, docs, many videos, etc.)
                if let ql = await Self.generateQuickLookThumbnail(
                    fileURL: fileURL,
                    size: requestSize,
                    scale: scale
                ) {
                    return ql
                }

                // Fallback: Videos (first frame), bounded by maximumSize.
                if isVideo, let frame = await Self.generateVideoFrameThumbnail(
                    fileURL: fileURL,
                    maxPixelSize: maxPixelSize,
                    scale: scale
                ) {
                    return frame
                }

                return nil
            }
        }

        inFlight[attachmentID] = task
        let image = await task.value
        inFlight[attachmentID] = nil

        if let image {
            memoryCache.setObject(image, forKey: key)
            Self.persistToDisk(image: image, attachmentID: attachmentID)
        }

        return image
    }

    // MARK: - Disk Cache Helpers

    static func thumbnailFilename(attachmentID: UUID) -> String {
        "thumb_v2_\(attachmentID.uuidString).jpg"
    }

    static func deleteCachedThumbnail(attachmentID: UUID) {
        guard let url = AttachmentStore.url(forLocalPath: thumbnailFilename(attachmentID: attachmentID)) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func loadFromDisk(attachmentID: UUID) -> UIImage? {
        guard let url = AttachmentStore.url(forLocalPath: thumbnailFilename(attachmentID: attachmentID)) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private static func persistToDisk(image: UIImage, attachmentID: UUID) {
        guard let url = AttachmentStore.url(forLocalPath: thumbnailFilename(attachmentID: attachmentID)) else { return }
        guard let data = image.jpegData(compressionQuality: 0.86) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: - Generators

    private static func isImageFile(fileURL: URL) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        guard !ext.isEmpty else { return false }
        guard let type = UTType(filenameExtension: ext) else { return false }
        if type.conforms(to: .pdf) { return false }
        return type.conforms(to: .image)
    }

    private static func maxPixelSize(for requestSize: CGSize, scale: CGFloat) -> Int {
        let maxPoints = max(requestSize.width, requestSize.height)
        let px = Int((maxPoints * scale).rounded(.up))
        return max(64, min(px, 4096))
    }

    private static func generateImageIOThumbnail(fileURL: URL, maxPixelSize: Int, scale: CGFloat) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else {
                return nil
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]

            guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                return nil
            }

            return UIImage(cgImage: cgThumb, scale: scale, orientation: .up)
        }.value
    }

    private static func generateQuickLookThumbnail(fileURL: URL, size: CGSize, scale: CGFloat) async -> UIImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                cont.resume(returning: representation?.uiImage)
            }
        }
    }

    private static func generateVideoFrameThumbnail(fileURL: URL, maxPixelSize: Int, scale: CGFloat) async -> UIImage? {
        await Task.detached(priority: .utility) {
			let asset = AVURLAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: CGFloat(maxPixelSize), height: CGFloat(maxPixelSize))

			let time = CMTime(seconds: 0.0, preferredTimescale: 600)
			let cg: CGImage? = await withCheckedContinuation { cont in
				var didResume = false
				func resumeOnce(_ image: CGImage?) {
					guard !didResume else { return }
					didResume = true
					cont.resume(returning: image)
				}

				generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, _ in
					guard result == .succeeded, let cgImage else {
						resumeOnce(nil)
						return
					}
					resumeOnce(cgImage)
				}
			}

			guard let cg else { return nil }
			return UIImage(cgImage: cg, scale: scale, orientation: .up)
        }.value
    }

    // MARK: - Private

    private func cacheKey(for attachmentID: UUID) -> NSString {
        attachmentID.uuidString as NSString
    }
}

