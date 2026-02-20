//
//  VideoCompression.swift
//  BrainMesh
//
//  Compresses large video files during import so they fit within the app's attachment size limits.
//  Runs off-main (call from a background task).
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers

enum VideoCompression {

    enum Quality: String, CaseIterable, Identifiable, Sendable {
        case high
        case standard
        case small

        var id: String { rawValue }

        var title: String {
            switch self {
            case .high: return "Hoch"
            case .standard: return "Standard"
            case .small: return "Klein"
            }
        }

        var detail: String {
            switch self {
            case .high: return "Bessere Qualität, größere Dateien"
            case .standard: return "Empfohlen"
            case .small: return "Starke Komprimierung, kleinere Dateien"
            }
        }
    }

    struct Output: Sendable {
        let localFilename: String
        let outputURL: URL
        let fileExtension: String
        let contentTypeIdentifier: String
        let byteCount: Int
        let usedPreset: String
    }

    /// Compresses the given `sourceURL` into the attachment cache and returns the cached file metadata.
    ///
    /// - Important: performs AVFoundation export and file I/O; call from a background task.
    static func compressToCache(
        sourceURL: URL,
        attachmentID: UUID,
        maxBytes: Int,
        quality: Quality = .standard
    ) async throws -> Output {

        let asset = AVURLAsset(url: sourceURL)
        let dir = try AttachmentStore.directoryURL()
        let candidates = choosePresets(quality: quality)

        let fm = FileManager.default

        var lastError: Error? = nil
        var lastByteCount: Int = 0
        var lastOutputURL: URL? = nil

        for preset in candidates {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                lastError = VideoCompressionError.exportSessionCreationFailed
                continue
            }

            let (fileType, fileExtension, typeID) = chooseFileType(for: session)
            let filename = AttachmentStore.makeLocalFilename(attachmentID: attachmentID, fileExtension: fileExtension)
            let outputURL = dir.appendingPathComponent(filename, isDirectory: false)
            lastOutputURL = outputURL

            if fm.fileExists(atPath: outputURL.path) {
                try? fm.removeItem(at: outputURL)
            }

            session.shouldOptimizeForNetworkUse = true

            do {
                try await session.export(to: outputURL, as: fileType)
            } catch {
                lastError = error
                try? fm.removeItem(at: outputURL)
                continue
            }

            let byteCount = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            lastByteCount = byteCount

            if byteCount <= 0 {
                lastError = VideoCompressionError.exportProducedEmptyFile
                try? fm.removeItem(at: outputURL)
                continue
            }

            if byteCount <= maxBytes {
                return Output(
                    localFilename: filename,
                    outputURL: outputURL,
                    fileExtension: fileExtension,
                    contentTypeIdentifier: typeID,
                    byteCount: byteCount,
                    usedPreset: preset
                )
            }

            // Too large → remove and try a stronger preset.
            try? fm.removeItem(at: outputURL)
        }

        // If we get here, we couldn't fit the file under maxBytes.
        if lastByteCount > maxBytes {
            throw VideoCompressionError.tooLargeAfterCompression(bytes: lastByteCount, maxBytes: maxBytes)
        }

        if let lastOutputURL, fm.fileExists(atPath: lastOutputURL.path) {
            try? fm.removeItem(at: lastOutputURL)
        }

        throw lastError ?? VideoCompressionError.exportFailed
    }

    private static func choosePresets(quality: Quality) -> [String] {
        switch quality {
        case .high:
            return [
                AVAssetExportPreset1920x1080,
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset640x480,
                AVAssetExportPresetLowQuality
            ]
        case .standard:
            return [
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset640x480,
                AVAssetExportPresetLowQuality
            ]
        case .small:
            return [
                AVAssetExportPreset640x480,
                AVAssetExportPresetLowQuality,
                AVAssetExportPresetMediumQuality
            ]
        }
    }

    private static func chooseFileType(for session: AVAssetExportSession) -> (AVFileType, String, String) {
        let supported = session.supportedFileTypes

        if supported.contains(.mp4) {
            return (.mp4, "mp4", UTType.mpeg4Movie.identifier)
        }

        if supported.contains(.mov) {
            return (.mov, "mov", UTType.quickTimeMovie.identifier)
        }

        if let first = supported.first {
            switch first {
            case .mp4:
                return (.mp4, "mp4", UTType.mpeg4Movie.identifier)
            case .mov:
                return (.mov, "mov", UTType.quickTimeMovie.identifier)
            default:
                return (first, "mov", UTType.quickTimeMovie.identifier)
            }
        }

        return (.mov, "mov", UTType.quickTimeMovie.identifier)
    }

}

enum VideoCompressionError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed
    case exportProducedEmptyFile
    case tooLargeAfterCompression(bytes: Int, maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed:
            return "Video konnte nicht für die Komprimierung vorbereitet werden."
        case .exportFailed:
            return "Video konnte nicht komprimiert werden."
        case .exportProducedEmptyFile:
            return "Komprimierung ist fehlgeschlagen (leere Datei)."
        case .tooLargeAfterCompression(let bytes, let maxBytes):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let max = ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
            return "Video ist zu groß (\(size)) — auch nach Komprimierung. Bitte kürzen (max. \(max))."
        }
    }
}
