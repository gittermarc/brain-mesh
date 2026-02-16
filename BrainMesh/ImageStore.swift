//
//  ImageStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 14.12.25.
//

import Foundation
import UIKit
import ImageIO

enum ImageStore {
    private static let folderName = "BrainMeshImages"

    // Small in-memory cache for already downsampled images.
    // This avoids repeated disk reads + decodes during SwiftUI body re-evaluations.
    private static let memoryCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 80
        c.totalCostLimit = 160 * 1024 * 1024
        return c
    }()

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

    /// Speichert JPEG in AppSupport. Wenn `preferredName` gesetzt ist, wird der verwendet.
    static func saveJPEG(_ jpegData: Data, preferredName: String? = nil) throws -> String {
        let name = (preferredName?.isEmpty == false) ? preferredName! : (UUID().uuidString + ".jpg")
        let url = try fileURL(for: name)
        try jpegData.write(to: url, options: [.atomic])
        return name
    }

    static func loadUIImage(path: String?) -> UIImage? {
        // Default: safe downsample for UI (prevents huge decodes from blowing memory).
        loadUIImage(path: path, maxPixelSize: 2600)
    }

    /// Loads a UIImage from the local image cache folder.
    /// - Important: Prefer this overload for UI rendering; it downsamples large images.
    /// - Parameter maxPixelSize: Maximum pixel size for the longer side.
    static func loadUIImage(path: String?, maxPixelSize: Int) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }

        do {
            let url = try fileURL(for: path)
            let key = cacheKey(path: path, maxPixelSize: maxPixelSize)

            // Guard against stale cache entries if the file was deleted.
            guard FileManager.default.fileExists(atPath: url.path) else {
                memoryCache.removeObject(forKey: key)
                return nil
            }

            if let hit = memoryCache.object(forKey: key) {
                return hit
            }

            // Downsample directly from URL to avoid loading full Data into RAM.
            let img = downsampledImage(from: url, maxPixelSize: maxPixelSize)
            if let img {
                memoryCache.setObject(img, forKey: key, cost: imageCostBytes(img))
            }
            return img
        } catch {
            return nil
        }
    }

    /// Downsamples image data (e.g. synced `imageData`) for UI display.
    static func loadUIImage(data: Data?, maxPixelSize: Int) -> UIImage? {
        guard let data, !data.isEmpty else { return nil }
        return downsampledImage(from: data, maxPixelSize: maxPixelSize)
    }

    static func delete(path: String?) {
        guard let path, !path.isEmpty else { return }
        do {
            let url = try fileURL(for: path)
            try? FileManager.default.removeItem(at: url)
            // We cannot enumerate NSCache keys, so clear it to avoid showing stale images.
            memoryCache.removeAllObjects()
        } catch {
            // ignore
        }
    }

    // MARK: - ImageIO downsampling

    private static func downsampledImage(from url: URL, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let src = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cg)
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let src = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cg)
    }

    private static func cacheKey(path: String, maxPixelSize: Int) -> NSString {
        "\(path)|\(maxPixelSize)" as NSString
    }

    private static func imageCostBytes(_ image: UIImage) -> Int {
        let pxW = Int(image.size.width * image.scale)
        let pxH = Int(image.size.height * image.scale)
        let bytes = max(1, pxW) * max(1, pxH) * 4
        return bytes
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
