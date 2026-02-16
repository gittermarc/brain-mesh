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
import UniformTypeIdentifiers
import ImageIO

/// Thumbnail pipeline:
/// - Memory cache (NSCache) with cost limit
/// - Disk cache (Application Support / BrainMeshAttachments / thumb_<id>_<bucket>.jpg)
/// - Efficient image downsampling via ImageIO (for images)
/// - Fast video first-frame via AVAssetImageGenerator (for videos)
/// - QuickLookThumbnailing for everything else (PDF, docs, etc.)
///
/// Why this exists:
/// Opening "Medien -> Alle" can create many thumbnails quickly.
/// If we spawn too many generators at once (especially QuickLook), CPU+Energy can explode and memory can spike.
/// This store therefore:
/// - Buckets thumbnail sizes
/// - Limits concurrent generation work
/// - Deduplicates in-flight work per (attachmentID + bucket)
actor AttachmentThumbnailStore {

    static let shared = AttachmentThumbnailStore()

    // MARK: - Caches

    private let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 240
        c.totalCostLimit = 96 * 1024 * 1024
        return c
    }()

    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    // MARK: - Concurrency limiter

    private let maxConcurrentGenerations: Int = 2
    private var activeGenerations: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquirePermit() async {
        if activeGenerations < maxConcurrentGenerations {
            activeGenerations += 1
            return
        }

        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
        // Slot is handed off from releasePermit; activeGenerations stays at maxConcurrentGenerations.
    }

    private func releasePermit() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
            return
        }
        activeGenerations = max(0, activeGenerations - 1)
    }

    // MARK: - Public

    func thumbnail(
        attachmentID: UUID,
        fileURL: URL,
        contentTypeIdentifier: String,
        fileExtension: String,
        isVideo: Bool,
        requestSize: CGSize,
        scale: CGFloat
    ) async -> UIImage? {

        let bucket = Self.sizeBucketPixels(for: requestSize, scale: scale, isVideo: isVideo)
        let cacheKey = Self.cacheKey(attachmentID: attachmentID, bucketPixels: bucket)

        if let hit = memoryCache.object(forKey: cacheKey) {
            return hit
        }

        if let disk = Self.loadFromDisk(attachmentID: attachmentID, bucketPixels: bucket) {
            setCache(disk, forKey: cacheKey)
            return disk
        }

        let inFlightKey = Self.inFlightKey(attachmentID: attachmentID, bucketPixels: bucket)
        if let existingTask = inFlight[inFlightKey] {
            return await existingTask.value
        }

        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            if Task.isCancelled { return nil }

            await self.acquirePermit()

            var generated: UIImage? = nil

            if !Task.isCancelled {
                if isVideo {
                    generated = await Self.generateVideoFrameThumbnail(
                        fileURL: fileURL,
                        maxPixelSize: bucket
                    )
                } else if Self.isImage(contentTypeIdentifier: contentTypeIdentifier, fileExtension: fileExtension) {
                    // Downsampling can be CPU-heavy; keep it off the actor thread.
                    generated = await Task.detached(priority: .utility) {
                        Self.downsampledImage(from: fileURL, maxPixelSize: bucket)
                    }.value
                } else {
                    generated = await Self.generateQuickLookThumbnail(
                        fileURL: fileURL,
                        size: requestSize,
                        scale: scale
                    )
                }
            }

            await self.releasePermit()

            if Task.isCancelled { return nil }

            if let generated {
                // Clamp oversized outputs defensively (QuickLook can sometimes ignore size hints).
                return Self.resizeIfNeeded(generated, maxPixelSize: bucket)
            }

            return nil
        }

        inFlight[inFlightKey] = task
        let image = await task.value
        inFlight[inFlightKey] = nil

        if let image {
            setCache(image, forKey: cacheKey)
            Self.persistToDisk(image: image, attachmentID: attachmentID, bucketPixels: bucket)
        }

        return image
    }

    // MARK: - Cache helpers

    private func setCache(_ image: UIImage, forKey key: NSString) {
        let pxW = Int(image.size.width * image.scale)
        let pxH = Int(image.size.height * image.scale)
        let cost = max(1, pxW * pxH * 4)
        memoryCache.setObject(image, forKey: key, cost: cost)
    }

    private static func cacheKey(attachmentID: UUID, bucketPixels: Int) -> NSString {
        "\(attachmentID.uuidString)_\(bucketPixels)" as NSString
    }

    private static func inFlightKey(attachmentID: UUID, bucketPixels: Int) -> String {
        "\(attachmentID.uuidString)|\(bucketPixels)"
    }

    // MARK: - Disk cache

    private static func thumbnailFilename(attachmentID: UUID, bucketPixels: Int) -> String {
        "thumb_\(attachmentID.uuidString)_\(bucketPixels).jpg"
    }

        static func deleteCachedThumbnail(attachmentID: UUID) {
        deleteCachedThumbnails(attachmentID: attachmentID)
    }

static func deleteCachedThumbnails(attachmentID: UUID) {
        // Remove common buckets. (Cheap and deterministic)
        for bucket in [128, 256, 512, 768, 1024] {
            guard let url = AttachmentStore.url(forLocalPath: thumbnailFilename(attachmentID: attachmentID, bucketPixels: bucket)) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func loadFromDisk(attachmentID: UUID, bucketPixels: Int) -> UIImage? {
        // Current, size-bucketed cache.
        if let url = AttachmentStore.url(forLocalPath: thumbnailFilename(attachmentID: attachmentID, bucketPixels: bucketPixels)),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }

        // Legacy fallback (older builds wrote a single "thumb_<id>.jpg" with unknown sizing).
        // We downsample it into the new bucket to avoid re-generating everything (and to keep RAM safe).
        let legacyName = "thumb_\(attachmentID.uuidString).jpg"
        if let legacyURL = AttachmentStore.url(forLocalPath: legacyName),
           FileManager.default.fileExists(atPath: legacyURL.path),
           let down = downsampledImage(from: legacyURL, maxPixelSize: bucketPixels) {
            persistToDisk(image: down, attachmentID: attachmentID, bucketPixels: bucketPixels)
            return down
        }

        return nil
    }

    private static func persistToDisk(image: UIImage, attachmentID: UUID, bucketPixels: Int) {
        guard let url = AttachmentStore.url(forLocalPath: thumbnailFilename(attachmentID: attachmentID, bucketPixels: bucketPixels)) else { return }
        guard let data = image.jpegData(compressionQuality: 0.84) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: - Type / bucket logic

    private static func sizeBucketPixels(for requestSize: CGSize, scale: CGFloat, isVideo: Bool) -> Int {
        let maxSidePoints = max(requestSize.width, requestSize.height)
        let maxSidePixels = Int((maxSidePoints * scale).rounded(.up))
        let target = max(64, maxSidePixels)

        // Buckets keep caches stable and prevent "first big request wins" memory bloat.
        if target <= 140 { return 128 }
        if target <= 320 { return 256 }
        if target <= 700 { return 512 }
        return 768
    }

    private static func isImage(contentTypeIdentifier: String, fileExtension: String) -> Bool {
        if let type = UTType(contentTypeIdentifier), type.conforms(to: .image) {
            return true
        }
        let ext = fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"].contains(ext)
    }

    // MARK: - Generators

    private static func downsampledImage(from url: URL, maxPixelSize: Int) -> UIImage? {
        autoreleasepool {
            let srcOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let src = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]

            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }
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

    private static func generateVideoFrameThumbnail(fileURL: URL, maxPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

            let time = CMTime(seconds: 0.0, preferredTimescale: 600)
            do {
                let cg = try generator.copyCGImage(at: time, actualTime: nil)
                return UIImage(cgImage: cg)
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - Defensive resize

    private static func resizeIfNeeded(_ image: UIImage, maxPixelSize: Int) -> UIImage {
        let pxW = image.size.width * image.scale
        let pxH = image.size.height * image.scale
        let maxPx = max(pxW, pxH)
        guard maxPx.isFinite, maxPx > CGFloat(maxPixelSize) else { return image }

        let factor = CGFloat(maxPixelSize) / maxPx
        let newSize = CGSize(width: image.size.width * factor, height: image.size.height * factor)

        // Renderer creates a new, smaller backing store (reduces memory pressure).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
