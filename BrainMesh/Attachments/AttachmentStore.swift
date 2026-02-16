//
//  AttachmentStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import UniformTypeIdentifiers

enum AttachmentStore {

    private static let folderName = "BrainMeshAttachments"

    // Patch 3: throttle expensive cache materialization (externalStorage load + disk write).
    // This prevents UI freezes when many thumbnails are requested at once.
    private static let materializeLimiter = AsyncLimiter(maxConcurrent: 2)


    static func directoryURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    static func url(forLocalPath filename: String) -> URL? {
        do {
            let dir = try directoryURL()
            return dir.appendingPathComponent(filename, isDirectory: false)
        } catch {
            return nil
        }
    }

    static func fileExists(localPath: String?) -> Bool {
        guard let localPath, let url = url(forLocalPath: localPath) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func delete(localPath: String?) {
        guard let localPath, let url = url(forLocalPath: localPath) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes all cached attachment files in Application Support.
    /// This does not delete the SwiftData records; it only clears the local preview/cache.
    static func clearCache() throws {
        let fm = FileManager.default
        let dir = try directoryURL()
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in items {
            try? fm.removeItem(at: url)
        }
    }

    /// Deterministic local filename based on attachment id + file extension.
    static func makeLocalFilename(attachmentID: UUID, fileExtension: String) -> String {
        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if ext.isEmpty { return "\(attachmentID.uuidString)" }
        return "\(attachmentID.uuidString).\(ext)"
    }

    /// Writes `data` to local cache and returns the cache filename.
    static func writeToCache(data: Data, attachmentID: UUID, fileExtension: String) throws -> String {
        let filename = makeLocalFilename(attachmentID: attachmentID, fileExtension: fileExtension)
        guard let url = url(forLocalPath: filename) else { return filename }
        try data.write(to: url, options: [.atomic])
        return filename
    }

    /// Copies a selected file URL into cache.
    /// Returns the cache filename.
    static func copyIntoCache(from sourceURL: URL, attachmentID: UUID, fileExtension: String) throws -> String {
        let filename = makeLocalFilename(attachmentID: attachmentID, fileExtension: fileExtension)
        guard let destURL = url(forLocalPath: filename) else { return filename }

        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: sourceURL, to: destURL)
        return filename
    }

    /// Returns an existing local file URL if present on disk (localPath or deterministic filename).
    static func existingCachedFileURL(for attachment: MetaAttachment) -> URL? {
        if let lp = attachment.localPath,
           let url = url(forLocalPath: lp),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let fallback = makeLocalFilename(attachmentID: attachment.id, fileExtension: attachment.fileExtension)
        if let url = url(forLocalPath: fallback),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        return nil
    }

    /// Ensures a local file exists on disk for thumbnailing.
    /// Important: does NOT mutate the SwiftData model (no localPath writes).
    static func materializeFileURLForThumbnailIfNeeded(for attachment: MetaAttachment) -> URL? {
        if let existing = existingCachedFileURL(for: attachment) {
            return existing
        }

        guard let data = attachment.fileData else { return nil }

        do {
            let filename = try writeToCache(data: data, attachmentID: attachment.id, fileExtension: attachment.fileExtension)
            return url(forLocalPath: filename)
        } catch {
            return nil
        }
    }

    /// Async variant for thumbnailing:
    /// - Reads SwiftData properties on the MainActor (safe).
    /// - Moves disk writes off the MainActor.
    /// - Throttles concurrent materialization to avoid IO storms.
    @MainActor
    static func materializeFileURLForThumbnailIfNeededAsync(for attachment: MetaAttachment) async -> URL? {
        // Fast path: already cached.
        if let existing = existingCachedFileURL(for: attachment) {
            return existing
        }

        // Throttle the expensive path (externalStorage load + disk write).
        return await materializeLimiter.withPermit {
            // Re-check inside the permit (another task might have written it).
            if let existing = existingCachedFileURL(for: attachment) {
                return existing
            }

            guard let data = attachment.fileData else { return nil }

            let filename = makeLocalFilename(attachmentID: attachment.id, fileExtension: attachment.fileExtension)

            return await Task.detached(priority: .utility) {
                if Task.isCancelled { return nil }
                guard let url = url(forLocalPath: filename) else { return nil }

                let fm = FileManager.default
                if fm.fileExists(atPath: url.path) {
                    return url
                }

                do {
                    try data.write(to: url, options: [.atomic])
                    return url
                } catch {
                    return nil
                }
            }.value
        }
    }


    /// Ensures we have a file URL for preview.
    /// - If `localPath` exists, returns that.
    /// - Else, tries the deterministic filename (id + extension) if it exists on disk.
    /// - Else, writes `fileData` to cache for preview and persists `localPath`.
    static func ensurePreviewURL(for attachment: MetaAttachment) -> URL? {
        if let existing = existingCachedFileURL(for: attachment) {
            // If we found it via deterministic fallback and localPath is nil/stale, normalize it.
            let normalized = makeLocalFilename(attachmentID: attachment.id, fileExtension: attachment.fileExtension)
            if attachment.localPath != normalized {
                // This mutation is expected on the UI/main path (preview).
                attachment.localPath = normalized
            }
            return existing
        }

        guard let data = attachment.fileData else { return nil }
        let ext = attachment.fileExtension

        do {
            let filename = try writeToCache(data: data, attachmentID: attachment.id, fileExtension: ext)
            attachment.localPath = filename
            return url(forLocalPath: filename)
        } catch {
            return nil
        }
    }

    static func isVideo(contentTypeIdentifier: String) -> Bool {
        guard let type = UTType(contentTypeIdentifier) else { return false }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    static func iconName(contentTypeIdentifier: String, fileExtension: String) -> String {
        if let type = UTType(contentTypeIdentifier) {
            if type.conforms(to: .pdf) { return "doc.richtext" }
            if type.conforms(to: .image) { return "photo" }
            if type.conforms(to: .audio) { return "waveform" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "video" }
            if type.conforms(to: .text) { return "doc.text" }
            if type.conforms(to: .archive) { return "doc.zipper" }
        }

        let ext = fileExtension.lowercased()
        if ["zip", "rar", "7z"].contains(ext) { return "doc.zipper" }
        if ["pdf"].contains(ext) { return "doc.richtext" }
        if ["mov", "mp4", "m4v"].contains(ext) { return "video" }
        if ["mp3", "m4a", "wav"].contains(ext) { return "waveform" }
        return "paperclip"
    }

    // MARK: - Cache metrics

    /// Returns the allocated size (bytes) of the local attachment cache folder.
    /// Note: This is *local cache only* (Application Support), not the synced byteCount/fileData.
    static func cacheSizeBytes() throws -> Int64 {
        let dir = try directoryURL()
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
