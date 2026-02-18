//
//  VideoImportPreferences.swift
//  BrainMesh
//
//  Lightweight UserDefaults-backed preferences for video import compression.
//  Used by both Settings UI and the attachment import pipeline.
//

import Foundation

enum VideoImportPreferences {

    // MARK: - UserDefaults Keys

    static let compressVideosOnImportKey = "BMCompressVideosOnImport"
    static let videoCompressionQualityKey = "BMVideoCompressionQuality"

    // MARK: - Defaults

    static let defaultCompressVideosOnImport: Bool = true
    static let defaultQuality: VideoCompression.Quality = .standard

    // MARK: - Read

    static func isCompressionEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        // If the key was never written, we want the recommended default = true.
        guard userDefaults.object(forKey: compressVideosOnImportKey) != nil else {
            return defaultCompressVideosOnImport
        }
        return userDefaults.bool(forKey: compressVideosOnImportKey)
    }

    static func compressionQuality(userDefaults: UserDefaults = .standard) -> VideoCompression.Quality {
        guard let raw = userDefaults.string(forKey: videoCompressionQualityKey),
              let q = VideoCompression.Quality(rawValue: raw) else {
            return defaultQuality
        }
        return q
    }
}
