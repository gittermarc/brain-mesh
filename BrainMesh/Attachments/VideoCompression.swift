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
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let candidates = choosePresets(compatiblePresets: compatible, quality: quality)

        let filenameBase: String
        let fileTypeAndExt: (AVFileType, String, String)

        // Determine file type once using the first viable export session.
        // (supportedFileTypes can vary slightly per preset, but mp4/mov usually overlap.)
        guard let probePreset = candidates.first,
              let probeSession = AVAssetExportSession(asset: asset, presetName: probePreset) else {
            throw VideoCompressionError.exportSessionCreationFailed
        }

        let (fileType, fileExtension, typeID) = chooseFileType(for: probeSession)
        fileTypeAndExt = (fileType, fileExtension, typeID)

        filenameBase = AttachmentStore.makeLocalFilename(attachmentID: attachmentID, fileExtension: fileExtension)
        let dir = try AttachmentStore.directoryURL()
        let outputURL = dir.appendingPathComponent(filenameBase, isDirectory: false)

        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) {
            try? fm.removeItem(at: outputURL)
        }

        var lastError: Error? = nil
        var lastByteCount: Int = 0

        for preset in candidates {
            if fm.fileExists(atPath: outputURL.path) {
                try? fm.removeItem(at: outputURL)
            }

            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                lastError = VideoCompressionError.exportSessionCreationFailed
                continue
            }

            session.outputURL = outputURL
            session.outputFileType = fileTypeAndExt.0
            session.shouldOptimizeForNetworkUse = true

            do {
                try await export(session)
            } catch {
                lastError = error
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
                    localFilename: filenameBase,
                    outputURL: outputURL,
                    fileExtension: fileTypeAndExt.1,
                    contentTypeIdentifier: fileTypeAndExt.2,
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

        throw lastError ?? VideoCompressionError.exportFailed
    }

    private static func choosePresets(compatiblePresets: [String], quality: Quality) -> [String] {
        func filtered(_ order: [String]) -> [String] {
            let usable = order.filter { compatiblePresets.contains($0) }
            if !usable.isEmpty { return usable }
            return compatiblePresets
        }

        switch quality {
        case .high:
            return filtered([
                AVAssetExportPreset1920x1080,
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset640x480,
                AVAssetExportPresetLowQuality
            ])
        case .standard:
            return filtered([
                AVAssetExportPreset1280x720,
                AVAssetExportPresetMediumQuality,
                AVAssetExportPreset640x480,
                AVAssetExportPresetLowQuality
            ])
        case .small:
            return filtered([
                AVAssetExportPreset640x480,
                AVAssetExportPresetLowQuality,
                AVAssetExportPresetMediumQuality
            ])
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

    private static func export(_ session: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed:
                    continuation.resume(throwing: session.error ?? VideoCompressionError.exportFailed)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: VideoCompressionError.exportFailed)
                }
            }
        }
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
