//
//  AttachmentImportPipeline.swift
//  BrainMesh
//
//  Shared import helpers for files and videos.
//  Keeps UI files small and allows running I/O off the main thread.
//

import Foundation
import UniformTypeIdentifiers

struct PreparedAttachmentImport: Sendable {
    let id: UUID
    let title: String
    let originalFilename: String
    let contentTypeIdentifier: String
    let fileExtension: String
    let byteCount: Int
    let inferredKind: AttachmentContentKind
    let localPath: String
    let fileData: Data

    var isGalleryImage: Bool { inferredKind == .galleryImage }
}

enum AttachmentImportPipeline {

    /// Prepares an attachment import from a security-scoped file URL.
    /// - Important: performs file I/O; call from a background task.
    static func prepareFileImport(
        from url: URL,
        attachmentID: UUID,
        maxBytes: Int
    ) throws -> PreparedAttachmentImport {

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let fileName = url.lastPathComponent
        let ext = url.pathExtension

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        if fileSize > maxBytes {
            throw AttachmentImportPipelineError.tooLarge(bytes: fileSize, maxBytes: maxBytes)
        }

        // Copy to sandbox first (security scoped URLs are not stable).
        let cachedFilename = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
        guard let cachedURL = AttachmentStore.url(forLocalPath: cachedFilename) else {
            throw AttachmentImportPipelineError.cacheWriteFailed
        }

        let data = try Data(contentsOf: cachedURL, options: [.mappedIfSafe])
        if data.count > maxBytes {
            AttachmentStore.delete(localPath: cachedFilename)
            throw AttachmentImportPipelineError.tooLarge(bytes: data.count, maxBytes: maxBytes)
        }

        let title = url.deletingPathExtension().lastPathComponent

        let inferredKind: AttachmentContentKind
        if let t = UTType(contentType) {
            if t.conforms(to: .image) {
                inferredKind = .galleryImage
            } else if t.conforms(to: .movie) || t.conforms(to: .video) {
                inferredKind = .video
            } else {
                inferredKind = .file
            }
        } else {
            inferredKind = .file
        }

        return PreparedAttachmentImport(
            id: attachmentID,
            title: title,
            originalFilename: fileName,
            contentTypeIdentifier: contentType,
            fileExtension: ext,
            byteCount: data.count,
            inferredKind: inferredKind,
            localPath: cachedFilename,
            fileData: data
        )
    }

    /// Prepares a video import from a temp URL produced by the photo picker.
    /// - Important: performs file I/O; call from a background task.
    static func prepareVideoImport(
        from url: URL,
        attachmentID: UUID,
        suggestedFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String,
        maxBytes: Int
    ) throws -> PreparedAttachmentImport {

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if fileSize > maxBytes {
            throw AttachmentImportPipelineError.tooLarge(bytes: fileSize, maxBytes: maxBytes)
        }

        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty ? "mov" : fileExtension

        let cachedFilename = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: ext)
        guard let cachedURL = AttachmentStore.url(forLocalPath: cachedFilename) else {
            throw AttachmentImportPipelineError.cacheWriteFailed
        }

        // The picker hands us a temp URL; we don't need it after copying.
        try? FileManager.default.removeItem(at: url)

        let data = try Data(contentsOf: cachedURL, options: [.mappedIfSafe])
        if data.count > maxBytes {
            AttachmentStore.delete(localPath: cachedFilename)
            throw AttachmentImportPipelineError.tooLarge(bytes: data.count, maxBytes: maxBytes)
        }

        let title = URL(fileURLWithPath: suggestedFilename).deletingPathExtension().lastPathComponent
        let originalName = suggestedFilename.isEmpty ? "Video.\(ext)" : suggestedFilename

        let typeID: String
        if !contentTypeIdentifier.isEmpty {
            typeID = contentTypeIdentifier
        } else if let t = UTType(filenameExtension: ext)?.identifier {
            typeID = t
        } else {
            typeID = UTType.movie.identifier
        }

        return PreparedAttachmentImport(
            id: attachmentID,
            title: title.isEmpty ? "Video" : title,
            originalFilename: originalName,
            contentTypeIdentifier: typeID,
            fileExtension: ext,
            byteCount: data.count,
            inferredKind: .video,
            localPath: cachedFilename,
            fileData: data
        )
    }
}

enum AttachmentImportPipelineError: LocalizedError {
    case tooLarge(bytes: Int, maxBytes: Int)
    case cacheWriteFailed

    var errorDescription: String? {
        switch self {
        case .tooLarge(let bytes, let maxBytes):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let max = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
            return "Datei ist zu groß (\(size)). Bitte nur kleine Anhänge hinzufügen (max. \(max))."
        case .cacheWriteFailed:
            return "Lokale Datei konnte nicht erstellt werden."
        }
    }
}
