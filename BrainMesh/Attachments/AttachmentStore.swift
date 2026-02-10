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

    /// Ensures we have a file URL for preview.
    /// - If `localPath` exists, returns that.
    /// - Else, writes `fileData` to cache for preview.
    static func ensurePreviewURL(for attachment: MetaAttachment) -> URL? {
        if let lp = attachment.localPath, let url = url(forLocalPath: lp), FileManager.default.fileExists(atPath: url.path) {
            return url
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
}
