//
//  ImageGalleryImportPreferences.swift
//  BrainMesh
//
//  Lightweight UserDefaults-backed preferences for photo gallery image import.
//  Used by both Settings UI and the gallery import pipeline.
//

import Foundation

enum ImageGalleryCompressionPreset: String, CaseIterable, Identifiable, Sendable {
    case original
    case highQuality
    case lowQuality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "Original"
        case .highQuality:
            return "Hohe Qualität (≈ 1,5 MB)"
        case .lowQuality:
            return "Niedrige Qualität (≈ 800 KB)"
        }
    }

    /// Target maximum size for the prepared JPEG.
    /// - nil means: no target size enforcement ("Original").
    var targetBytes: Int? {
        switch self {
        case .original:
            return nil
        case .highQuality:
            return 1_500_000
        case .lowQuality:
            return 800_000
        }
    }

    /// Safety belt for decode: avoid importing extremely large images that would cause
    /// memory and sync pressure. This does not enforce a byte cap, only decode scale.
    var maxDecodePixelSize: Int {
        switch self {
        case .original:
            return 4096
        case .highQuality, .lowQuality:
            return 3200
        }
    }
}

enum ImageGalleryImportPreferences {

    // MARK: - UserDefaults Key

    static let galleryImageCompressionPresetKey = BMAppStorageKeys.galleryImageCompressionPreset

    // MARK: - Default

    static let defaultPreset: ImageGalleryCompressionPreset = .highQuality

    // MARK: - Read

    static func compressionPreset(userDefaults: UserDefaults = .standard) -> ImageGalleryCompressionPreset {
        guard let raw = userDefaults.string(forKey: galleryImageCompressionPresetKey),
              let preset = ImageGalleryCompressionPreset(rawValue: raw) else {
            return defaultPreset
        }
        return preset
    }
}
