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

/// Thumbnail pipeline:
/// - Memory cache (NSCache)
/// - Disk cache (Application Support / BrainMeshAttachments / thumb_<id>.jpg)
/// - Generate via QuickLookThumbnailing; fallback for videos via AVAssetImageGenerator.
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

                // Try QuickLook thumbnail first (works for PDFs, docs, many videos, etc.)
                if let ql = await Self.generateQuickLookThumbnail(
                    fileURL: fileURL,
                    size: requestSize,
                    scale: scale
                ) {
                    return ql
                }

                // Fallback: Videos (first frame)
                if isVideo, let frame = await Self.generateVideoFrameThumbnail(fileURL: fileURL) {
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
        "thumb_\(attachmentID.uuidString).jpg"
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

    private static func generateVideoFrameThumbnail(fileURL: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true

            let time = CMTime(seconds: 0.0, preferredTimescale: 600)
            do {
                let cg = try generator.copyCGImage(at: time, actualTime: nil)
                return UIImage(cgImage: cg)
            } catch {
                return nil
            }
        }.value
    }

    // MARK: - Private

    private func cacheKey(for attachmentID: UUID) -> NSString {
        attachmentID.uuidString as NSString
    }
}

// MARK: - Concurrency limiter

/// A tiny async semaphore.
///
/// - `withPermit` suspends until a permit is available, runs the operation, then releases.
/// - FIFO fairness is "good enough" for UI thumbnail work.
actor AsyncLimiter {

    private let maxConcurrent: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.available = max(1, maxConcurrent)
    }

    func withPermit<T>(_ operation: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    private func release() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
            return
        }
        available = min(maxConcurrent, available + 1)
    }
}
