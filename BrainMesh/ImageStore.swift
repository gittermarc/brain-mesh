//
//  ImageStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 14.12.25.
//

import Foundation
import UIKit

enum ImageStore {
    private static let folderName = "BrainMeshImages"

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
        guard let path, !path.isEmpty else { return nil }
        do {
            let url = try fileURL(for: path)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    static func delete(path: String?) {
        guard let path, !path.isEmpty else { return }
        do {
            let url = try fileURL(for: path)
            try? FileManager.default.removeItem(at: url)
        } catch {
            // ignore
        }
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
