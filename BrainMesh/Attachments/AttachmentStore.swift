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
        existingCachedFileURL(
            localPath: attachment.localPath,
            attachmentID: attachment.id,
            fileExtension: attachment.fileExtension
        )
    }

    /// Same as `existingCachedFileURL(for:)`, but without needing a SwiftData model instance.
    static func existingCachedFileURL(localPath: String?, attachmentID: UUID, fileExtension: String) -> URL? {
        if let lp = localPath,
           let url = url(forLocalPath: lp),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let fallback = makeLocalFilename(attachmentID: attachmentID, fileExtension: fileExtension)
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

    
    /// Async + throttled materialization for thumbnailing in UI grids/lists.
    ///
    /// This avoids the classic "open a big grid -> spawn 30 disk writes & image decodes at once" meltdown.
    static func materializeFileURLForThumbnailIfNeededAsync(for attachment: MetaAttachment) async -> URL? {
        await AttachmentThumbnailMaterializer.shared.materialize(for: attachment)
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


// MARK: - Throttled thumbnail materialization

/// Materializes attachment bytes into a local cache file, but throttles concurrent work to avoid memory spikes.
/// This is used by thumbnail loaders (grids/lists) before handing URLs to thumbnail generators.
fileprivate actor AttachmentThumbnailMaterializer {

    static let shared = AttachmentThumbnailMaterializer()

    private let maxConcurrent: Int = 1
    private var active: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private var inFlight: [UUID: [CheckedContinuation<URL?, Never>]] = [:]

    private struct Snapshot: Sendable {
        let id: UUID
        let fileExtension: String
        let localPath: String?
    }

    private func acquire() async {
        if active < maxConcurrent {
            active += 1
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
        active = max(0, active - 1)
    }

    func materialize(for attachment: MetaAttachment) async -> URL? {
        let snap = await MainActor.run {
            Snapshot(
                id: attachment.id,
                fileExtension: attachment.fileExtension,
                localPath: attachment.localPath
            )
        }

        if let existing = AttachmentStore.existingCachedFileURL(
            localPath: snap.localPath,
            attachmentID: snap.id,
            fileExtension: snap.fileExtension
        ) {
            return existing
        }

        if inFlight[snap.id] != nil {
            return await withCheckedContinuation { cont in
                inFlight[snap.id, default: []].append(cont)
            }
        }

        inFlight[snap.id] = []
        await acquire()
        defer { release() }

        // Re-check after acquiring the permit (another call might have materialized meanwhile).
        var result: URL? = AttachmentStore.existingCachedFileURL(
            localPath: snap.localPath,
            attachmentID: snap.id,
            fileExtension: snap.fileExtension
        )

        if result == nil {
            let data = await MainActor.run { attachment.fileData }
            if let data {
                do {
                    let local = try AttachmentStore.writeToCache(
                        data: data,
                        attachmentID: snap.id,
                        fileExtension: snap.fileExtension
                    )
                    result = AttachmentStore.url(forLocalPath: local)
                } catch {
                    result = nil
                }
            }
        }

        let conts = inFlight.removeValue(forKey: snap.id) ?? []
        for cont in conts {
            cont.resume(returning: result)
        }

        return result
    }
}
