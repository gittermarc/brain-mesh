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
    ) async throws -> PreparedAttachmentImport {

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let fileName = url.lastPathComponent
        let ext = url.pathExtension

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        let inferredKind = inferKind(contentTypeIdentifier: contentType, fileExtension: ext)

        let compressionEnabled = VideoImportPreferences.isCompressionEnabled()
        let compressionQuality = VideoImportPreferences.compressionQuality()

        // If a video is larger than our max, try to compress it instead of rejecting.
        if fileSize > maxBytes {
            if inferredKind == .video, compressionEnabled {
                let compressed = try await VideoCompression.compressToCache(
                    sourceURL: url,
                    attachmentID: attachmentID,
                    maxBytes: maxBytes,
                    quality: compressionQuality
                )

                let data = try Data(contentsOf: compressed.outputURL, options: [.mappedIfSafe])
                if data.count > maxBytes {
                    AttachmentStore.delete(localPath: compressed.localFilename)
                    throw VideoCompressionError.tooLargeAfterCompression(bytes: data.count, maxBytes: maxBytes)
                }

                let baseTitle = url.deletingPathExtension().lastPathComponent
                let normalizedOriginal = baseTitle.isEmpty ? "Video.\(compressed.fileExtension)" : "\(baseTitle).\(compressed.fileExtension)"

                return PreparedAttachmentImport(
                    id: attachmentID,
                    title: baseTitle.isEmpty ? "Video" : baseTitle,
                    originalFilename: normalizedOriginal,
                    contentTypeIdentifier: compressed.contentTypeIdentifier,
                    fileExtension: compressed.fileExtension,
                    byteCount: data.count,
                    inferredKind: .video,
                    localPath: compressed.localFilename,
                    fileData: data
                )
            }

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
    /// - Important: performs AVFoundation export + file I/O; call from a background task.
    static func prepareVideoImport(
        from url: URL,
        attachmentID: UUID,
        suggestedFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String,
        maxBytes: Int
    ) async throws -> PreparedAttachmentImport {

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let trimmed = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let inputExt = trimmed.isEmpty ? "mov" : trimmed

        let titleBase = URL(fileURLWithPath: suggestedFilename).deletingPathExtension().lastPathComponent
        let fallbackName = suggestedFilename.isEmpty ? "Video.\(inputExt)" : suggestedFilename

        let compressionEnabled = VideoImportPreferences.isCompressionEnabled()
        let compressionQuality = VideoImportPreferences.compressionQuality()

        // If the picked video is larger than our max, compress it into cache.
        if fileSize > maxBytes {
            if compressionEnabled {
                let compressed = try await VideoCompression.compressToCache(
                    sourceURL: url,
                    attachmentID: attachmentID,
                    maxBytes: maxBytes,
                    quality: compressionQuality
                )

                // The picker hands us a temp URL; we don't need it after exporting.
                try? FileManager.default.removeItem(at: url)

                let data = try Data(contentsOf: compressed.outputURL, options: [.mappedIfSafe])
                if data.count > maxBytes {
                    AttachmentStore.delete(localPath: compressed.localFilename)
                    throw VideoCompressionError.tooLargeAfterCompression(bytes: data.count, maxBytes: maxBytes)
                }

                let normalizedTitle = titleBase.isEmpty ? "Video" : titleBase
                let normalizedOriginal = URL(fileURLWithPath: fallbackName).deletingPathExtension().lastPathComponent
                let originalName = normalizedOriginal.isEmpty ? "Video.\(compressed.fileExtension)" : "\(normalizedOriginal).\(compressed.fileExtension)"

                return PreparedAttachmentImport(
                    id: attachmentID,
                    title: normalizedTitle,
                    originalFilename: originalName,
                    contentTypeIdentifier: compressed.contentTypeIdentifier,
                    fileExtension: compressed.fileExtension,
                    byteCount: data.count,
                    inferredKind: .video,
                    localPath: compressed.localFilename,
                    fileData: data
                )
            }

            throw AttachmentImportPipelineError.tooLarge(bytes: fileSize, maxBytes: maxBytes)
        }

        // Otherwise: copy the temp file into cache as-is.
        let cachedFilename = try AttachmentStore.copyIntoCache(from: url, attachmentID: attachmentID, fileExtension: inputExt)
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

        let typeID: String
        if !contentTypeIdentifier.isEmpty {
            typeID = contentTypeIdentifier
        } else if let t = UTType(filenameExtension: inputExt)?.identifier {
            typeID = t
        } else {
            typeID = UTType.movie.identifier
        }

        let title = titleBase
        let originalName = fallbackName

        return PreparedAttachmentImport(
            id: attachmentID,
            title: title.isEmpty ? "Video" : title,
            originalFilename: originalName,
            contentTypeIdentifier: typeID,
            fileExtension: inputExt,
            byteCount: data.count,
            inferredKind: .video,
            localPath: cachedFilename,
            fileData: data
        )
    }

    static func inferKind(contentTypeIdentifier: String, fileExtension: String) -> AttachmentContentKind {
        if let t = UTType(contentTypeIdentifier) {
            if t.conforms(to: .image) {
                return .galleryImage
            }
            if t.conforms(to: .movie) || t.conforms(to: .video) {
                return .video
            }
            return .file
        }

        if let t = UTType(filenameExtension: fileExtension) {
            if t.conforms(to: .image) {
                return .galleryImage
            }
            if t.conforms(to: .movie) || t.conforms(to: .video) {
                return .video
            }
        }

        return .file
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
