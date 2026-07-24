//
//  AttachmentImportPipeline.swift
//  BrainMesh
//
//  Shared import helpers for files and videos.
//  Keeps UI files small and allows running I/O off the main thread.
//

import Foundation
import UniformTypeIdentifiers
import UIKit

nonisolated struct PreparedAttachmentImport: Equatable, Sendable {
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

/// Small cache seam used by the import pipeline and its deterministic error tests.
/// Every closure is value-only and safe to execute outside the MainActor.
nonisolated struct AttachmentImportCacheOperations: Sendable {
    let writeToCache: @Sendable (Data, UUID, String) throws -> String
    let copyIntoCache: @Sendable (URL, UUID, String) throws -> String
    let resolveURL: @Sendable (String) -> URL?
    let readData: @Sendable (URL) throws -> Data
    let delete: @Sendable (String?) -> Void

    static let live = AttachmentImportCacheOperations(
        writeToCache: { data, attachmentID, fileExtension in
            try AttachmentStore.writeToCache(
                data: data,
                attachmentID: attachmentID,
                fileExtension: fileExtension
            )
        },
        copyIntoCache: { sourceURL, attachmentID, fileExtension in
            try AttachmentStore.copyIntoCache(
                from: sourceURL,
                attachmentID: attachmentID,
                fileExtension: fileExtension
            )
        },
        resolveURL: { localPath in
            AttachmentStore.url(forLocalPath: localPath)
        },
        readData: { url in
            try Data(contentsOf: url, options: [.mappedIfSafe])
        },
        delete: { localPath in
            AttachmentStore.delete(localPath: localPath)
        }
    )
}

nonisolated enum AttachmentImportPipeline {

    /// Prepares an attachment import from a security-scoped file URL.
    /// - Important: performs file I/O and image/video preparation; call from a detached task.
    static func prepareFileImport(
        from url: URL,
        attachmentID: UUID,
        maxBytes: Int,
        cacheOperations: AttachmentImportCacheOperations = .live
    ) async throws -> PreparedAttachmentImport {

        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let fileName = url.lastPathComponent
        let ext = url.pathExtension

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        let inferredKind = inferKind(
            contentTypeIdentifier: contentType,
            fileExtension: ext
        )

        let compressionEnabled = VideoImportPreferences.isCompressionEnabled()
        let compressionQuality = VideoImportPreferences.compressionQuality()

        // App-wide rule: gallery images imported through the file importer are normalized through
        // the configured JPEG gallery preset so this entry point cannot bypass image size policy.
        if inferredKind == .galleryImage {
            let preset = ImageGalleryImportPreferences.compressionPreset()
            let raw = try Data(contentsOf: url, options: [.mappedIfSafe])

            if let decoded = ImageImportPipeline.decodeImageSafely(
                from: raw,
                maxPixelSize: preset.maxDecodePixelSize
            ),
               let jpeg = ImageImportPipeline.prepareJPEGForGallery(
                decoded,
                targetBytes: preset.targetBytes
               ) {

                guard jpeg.count <= maxBytes else {
                    throw AttachmentImportPipelineError.tooLarge(
                        bytes: jpeg.count,
                        maxBytes: maxBytes
                    )
                }

                let baseTitle = url.deletingPathExtension().lastPathComponent
                let normalizedTitle = baseTitle.isEmpty ? "Foto" : baseTitle
                let normalizedOriginal = baseTitle.isEmpty ? "Foto.jpg" : "\(baseTitle).jpg"

                let localFilename = try writePreparedData(
                    jpeg,
                    attachmentID: attachmentID,
                    fileExtension: "jpg",
                    cacheOperations: cacheOperations
                )

                return PreparedAttachmentImport(
                    id: attachmentID,
                    title: normalizedTitle,
                    originalFilename: normalizedOriginal,
                    contentTypeIdentifier: UTType.jpeg.identifier,
                    fileExtension: "jpg",
                    byteCount: jpeg.count,
                    inferredKind: .galleryImage,
                    localPath: localFilename,
                    fileData: jpeg
                )
            }

            // Recompression failed. Keep the source format only when the original is within limit.
            guard raw.count <= maxBytes else {
                throw AttachmentImportPipelineError.tooLarge(
                    bytes: raw.count,
                    maxBytes: maxBytes
                )
            }

            let cachedFilename = try copyPreparedFile(
                from: url,
                attachmentID: attachmentID,
                fileExtension: ext,
                cacheOperations: cacheOperations
            )
            let data = try readPreparedCache(
                localPath: cachedFilename,
                maxBytes: maxBytes,
                oversizedError: .attachment,
                cacheOperations: cacheOperations
            )
            let title = url.deletingPathExtension().lastPathComponent

            return PreparedAttachmentImport(
                id: attachmentID,
                title: title.isEmpty ? "Foto" : title,
                originalFilename: fileName,
                contentTypeIdentifier: contentType,
                fileExtension: ext,
                byteCount: data.count,
                inferredKind: inferredKind,
                localPath: cachedFilename,
                fileData: data
            )
        }

        // App-wide rule: an oversized video is compressed when the preference is enabled.
        if fileSize > maxBytes {
            guard inferredKind == .video, compressionEnabled else {
                throw AttachmentImportPipelineError.tooLarge(
                    bytes: fileSize,
                    maxBytes: maxBytes
                )
            }

            let compressed = try await VideoCompression.compressToCache(
                sourceURL: url,
                attachmentID: attachmentID,
                maxBytes: maxBytes,
                quality: compressionQuality
            )
            let data = try readPreparedCache(
                localPath: compressed.localFilename,
                maxBytes: maxBytes,
                oversizedError: .compressedVideo,
                cacheOperations: cacheOperations
            )

            let baseTitle = url.deletingPathExtension().lastPathComponent
            let normalizedOriginal = baseTitle.isEmpty
                ? "Video.\(compressed.fileExtension)"
                : "\(baseTitle).\(compressed.fileExtension)"

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

        let cachedFilename = try copyPreparedFile(
            from: url,
            attachmentID: attachmentID,
            fileExtension: ext,
            cacheOperations: cacheOperations
        )
        let data = try readPreparedCache(
            localPath: cachedFilename,
            maxBytes: maxBytes,
            oversizedError: .attachment,
            cacheOperations: cacheOperations
        )
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

    /// Prepares a video import from a temporary URL produced by the photo picker.
    /// - Important: performs AVFoundation export and file I/O; call from a detached task.
    static func prepareVideoImport(
        from url: URL,
        attachmentID: UUID,
        suggestedFilename: String,
        contentTypeIdentifier: String,
        fileExtension: String,
        maxBytes: Int,
        cacheOperations: AttachmentImportCacheOperations = .live
    ) async throws -> PreparedAttachmentImport {

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let trimmed = fileExtension.trimmingCharacters(
            in: CharacterSet(charactersIn: ".")
        )
        let inputExt = trimmed.isEmpty ? "mov" : trimmed

        let titleBase = URL(fileURLWithPath: suggestedFilename)
            .deletingPathExtension()
            .lastPathComponent
        let fallbackName = suggestedFilename.isEmpty
            ? "Video.\(inputExt)"
            : suggestedFilename

        let compressionEnabled = VideoImportPreferences.isCompressionEnabled()
        let compressionQuality = VideoImportPreferences.compressionQuality()

        if fileSize > maxBytes {
            guard compressionEnabled else {
                throw AttachmentImportPipelineError.tooLarge(
                    bytes: fileSize,
                    maxBytes: maxBytes
                )
            }

            let compressed = try await VideoCompression.compressToCache(
                sourceURL: url,
                attachmentID: attachmentID,
                maxBytes: maxBytes,
                quality: compressionQuality
            )
            let data = try readPreparedCache(
                localPath: compressed.localFilename,
                maxBytes: maxBytes,
                oversizedError: .compressedVideo,
                cacheOperations: cacheOperations
            )

            let normalizedTitle = titleBase.isEmpty ? "Video" : titleBase
            let normalizedOriginal = URL(fileURLWithPath: fallbackName)
                .deletingPathExtension()
                .lastPathComponent
            let originalName = normalizedOriginal.isEmpty
                ? "Video.\(compressed.fileExtension)"
                : "\(normalizedOriginal).\(compressed.fileExtension)"

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

        let cachedFilename = try copyPreparedFile(
            from: url,
            attachmentID: attachmentID,
            fileExtension: inputExt,
            cacheOperations: cacheOperations
        )
        let data = try readPreparedCache(
            localPath: cachedFilename,
            maxBytes: maxBytes,
            oversizedError: .attachment,
            cacheOperations: cacheOperations
        )

        let typeID: String
        if contentTypeIdentifier.isEmpty == false {
            typeID = contentTypeIdentifier
        } else if let inferredType = UTType(filenameExtension: inputExt)?.identifier {
            typeID = inferredType
        } else {
            typeID = UTType.movie.identifier
        }

        return PreparedAttachmentImport(
            id: attachmentID,
            title: titleBase.isEmpty ? "Video" : titleBase,
            originalFilename: fallbackName,
            contentTypeIdentifier: typeID,
            fileExtension: inputExt,
            byteCount: data.count,
            inferredKind: .video,
            localPath: cachedFilename,
            fileData: data
        )
    }

    static func inferKind(
        contentTypeIdentifier: String,
        fileExtension: String
    ) -> AttachmentContentKind {
        if let type = UTType(contentTypeIdentifier) {
            if type.conforms(to: .image) {
                return .galleryImage
            }
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            }
            return .file
        }

        if let type = UTType(filenameExtension: fileExtension) {
            if type.conforms(to: .image) {
                return .galleryImage
            }
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            }
        }

        return .file
    }

    private enum OversizedErrorStyle {
        case attachment
        case compressedVideo
    }

    private static func writePreparedData(
        _ data: Data,
        attachmentID: UUID,
        fileExtension: String,
        cacheOperations: AttachmentImportCacheOperations
    ) throws -> String {
        let expectedLocalPath = AttachmentStore.makeLocalFilename(
            attachmentID: attachmentID,
            fileExtension: fileExtension
        )

        let localPath: String
        do {
            localPath = try cacheOperations.writeToCache(
                data,
                attachmentID,
                fileExtension
            )
        } catch {
            cacheOperations.delete(expectedLocalPath)
            throw AttachmentImportPipelineError.cacheWriteFailed
        }

        guard cacheOperations.resolveURL(localPath) != nil else {
            cacheOperations.delete(localPath)
            throw AttachmentImportPipelineError.cacheWriteFailed
        }
        return localPath
    }

    private static func copyPreparedFile(
        from sourceURL: URL,
        attachmentID: UUID,
        fileExtension: String,
        cacheOperations: AttachmentImportCacheOperations
    ) throws -> String {
        let expectedLocalPath = AttachmentStore.makeLocalFilename(
            attachmentID: attachmentID,
            fileExtension: fileExtension
        )

        do {
            return try cacheOperations.copyIntoCache(
                sourceURL,
                attachmentID,
                fileExtension
            )
        } catch {
            cacheOperations.delete(expectedLocalPath)
            throw AttachmentImportPipelineError.cacheWriteFailed
        }
    }

    /// Reads a cache entry while the pipeline still owns it. Every failure removes that entry;
    /// a successful return transfers ownership to the resulting PreparedAttachmentImport.
    private static func readPreparedCache(
        localPath: String,
        maxBytes: Int,
        oversizedError: OversizedErrorStyle,
        cacheOperations: AttachmentImportCacheOperations
    ) throws -> Data {
        guard let cachedURL = cacheOperations.resolveURL(localPath) else {
            cacheOperations.delete(localPath)
            throw AttachmentImportPipelineError.cacheWriteFailed
        }

        let data: Data
        do {
            data = try cacheOperations.readData(cachedURL)
        } catch {
            cacheOperations.delete(localPath)
            throw AttachmentImportPipelineError.cacheReadFailed
        }

        guard data.count <= maxBytes else {
            cacheOperations.delete(localPath)
            switch oversizedError {
            case .attachment:
                throw AttachmentImportPipelineError.tooLarge(
                    bytes: data.count,
                    maxBytes: maxBytes
                )
            case .compressedVideo:
                throw VideoCompressionError.tooLargeAfterCompression(
                    bytes: data.count,
                    maxBytes: maxBytes
                )
            }
        }

        return data
    }
}

nonisolated enum AttachmentImportPipelineError: LocalizedError, Equatable, Sendable {
    case tooLarge(bytes: Int, maxBytes: Int)
    case cacheWriteFailed
    case cacheReadFailed

    var errorDescription: String? {
        switch self {
        case .tooLarge(let bytes, let maxBytes):
            let size = ByteCountFormatter.string(
                fromByteCount: Int64(bytes),
                countStyle: .file
            )
            let max = ByteCountFormatter.string(
                fromByteCount: Int64(maxBytes),
                countStyle: .file
            )
            return "Datei ist zu groß (\(size)). Bitte nur kleine Anhänge hinzufügen (max. \(max))."
        case .cacheWriteFailed:
            return "Lokale Datei konnte nicht erstellt werden."
        case .cacheReadFailed:
            return "Lokale Datei konnte nicht gelesen werden."
        }
    }
}
