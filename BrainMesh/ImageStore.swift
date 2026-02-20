//
//  ImageStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 14.12.25.
//

import Foundation
import UIKit

/// Local image cache for main entity/attribute photos.
///
/// Storage layers:
/// - Memory cache (NSCache)
/// - Disk cache (Application Support / BrainMeshImages)
///
/// Notes:
/// - `loadUIImage(path:)` is synchronous and should not be called from SwiftUI `body`.
/// - Prefer `loadUIImageAsync(path:)` for UI, which de-duplicates concurrent loads and performs disk I/O off-main.
nonisolated enum ImageStore {
    private static let folderName = "BrainMeshImages"

    // MARK: - Memory cache

    private static let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()

    private static let inFlight = InFlightLoader()

    private static func cacheKey(_ path: String) -> NSString {
        path as NSString
    }

    static func cacheUIImage(_ image: UIImage, path: String) {
        memoryCache.setObject(image, forKey: cacheKey(path))
    }

    static func removeCachedUIImage(path: String?) {
        guard let path, !path.isEmpty else { return }
        memoryCache.removeObject(forKey: cacheKey(path))
    }

    static func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    // MARK: - Disk

    private static func folderURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func fileURL(for relativePath: String) throws -> URL {
        try folderURL().appendingPathComponent(relativePath)
    }

    static func fileExists(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        do {
            let url = try fileURL(for: path)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            return false
        }
    }

    /// Stores JPEG in Application Support.
    /// If `preferredName` is set, that name will be used.
    static func saveJPEG(_ jpegData: Data, preferredName: String? = nil) throws -> String {
        let name = (preferredName?.isEmpty == false) ? preferredName! : (UUID().uuidString + ".jpg")
        let url = try fileURL(for: name)
        try jpegData.write(to: url, options: [.atomic])

        // Avoid stale in-memory images.
        removeCachedUIImage(path: name)
        return name
    }

    /// Async wrapper for `saveJPEG` that performs disk I/O off-main.
    @discardableResult
    static func saveJPEGAsync(_ jpegData: Data, preferredName: String? = nil) async throws -> String {
        let dataCopy = jpegData
        let nameCopy = preferredName

        return try await Task.detached(priority: .utility) {
            try saveJPEG(dataCopy, preferredName: nameCopy)
        }.value
    }

    /// Synchronous load. Do not call this from SwiftUI `body`.
    static func loadUIImage(path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }

        let key = cacheKey(path)
        if let hit = memoryCache.object(forKey: key) {
            return hit
        }

        do {
            let url = try fileURL(for: path)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            let image: UIImage? = autoreleasepool {
                // `UIImage(contentsOfFile:)` avoids creating a separate Data buffer.
                UIImage(contentsOfFile: url.path)
            }

            if let image {
                memoryCache.setObject(image, forKey: key)
            }

            return image
        } catch {
            return nil
        }
    }

    /// Async load for UI usage.
    /// - De-duplicates concurrent loads per path.
    /// - Performs disk I/O off-main.
    static func loadUIImageAsync(path: String?) async -> UIImage? {
        guard let path, !path.isEmpty else { return nil }

        let key = cacheKey(path)
        if let hit = memoryCache.object(forKey: key) {
            return hit
        }

        return await inFlight.image(path: path)
    }

    static func delete(path: String?) {
        guard let path, !path.isEmpty else { return }

        removeCachedUIImage(path: path)

        do {
            let url = try fileURL(for: path)
            try? FileManager.default.removeItem(at: url)
        } catch {
            // ignore
        }
    }

    static func deleteAsync(path: String?) async {
        let p = path
        await Task.detached(priority: .utility) {
            delete(path: p)
        }.value
    }

    // MARK: - Cache metrics

    /// Returns the allocated size (bytes) of the local image cache folder.
    /// Note: This is *local cache only* (Application Support), not the synced imageData.
    static func cacheSizeBytes() throws -> Int64 {
        let dir = try folderURL()
        return directorySizeBytes(dir)
    }

    private static func directorySizeBytes(_ directoryURL: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .fileSizeKey
        ]

        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys) else { continue }
            guard values.isRegularFile == true else { continue }

            if let allocated = values.fileAllocatedSize {
                total += Int64(allocated)
            } else if let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

// MARK: - In-flight de-duplication

private actor InFlightLoader {
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(path: String) async -> UIImage? {
        if let existing = inFlight[path] {
            return await existing.value
        }

        let p = path
        let task = Task<UIImage?, Never> {
            await Task.detached(priority: .userInitiated) {
                ImageStore.loadUIImage(path: p)
            }.value
        }

        inFlight[path] = task
        let image = await task.value
        inFlight.removeValue(forKey: path)
        return image
    }
}
