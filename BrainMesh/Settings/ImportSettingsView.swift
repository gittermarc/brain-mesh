//
//  ImportSettingsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 23.02.26.
//

import SwiftUI

struct ImportSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(VideoImportPreferences.compressVideosOnImportKey)
    var compressVideosOnImport: Bool = VideoImportPreferences.defaultCompressVideosOnImport

    @AppStorage(VideoImportPreferences.videoCompressionQualityKey)
    var videoCompressionQualityRaw: String = VideoImportPreferences.defaultQuality.rawValue

    @AppStorage(ImageGalleryImportPreferences.galleryImageCompressionPresetKey)
    var galleryImageCompressionPresetRaw: String = ImageGalleryImportPreferences.defaultPreset.rawValue

    var body: some View {
        List {
            importSection
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }
            }
        }
    }

    var qualityBinding: Binding<VideoCompression.Quality> {
        Binding(
            get: {
                VideoCompression.Quality(rawValue: videoCompressionQualityRaw) ?? VideoImportPreferences.defaultQuality
            },
            set: { newValue in
                videoCompressionQualityRaw = newValue.rawValue
            }
        )
    }

    var galleryImageCompressionPresetBinding: Binding<ImageGalleryCompressionPreset> {
        Binding(
            get: {
                ImageGalleryCompressionPreset(rawValue: galleryImageCompressionPresetRaw)
                    ?? ImageGalleryImportPreferences.defaultPreset
            },
            set: { newValue in
                galleryImageCompressionPresetRaw = newValue.rawValue
            }
        )
    }
}

#Preview {
    NavigationStack {
        ImportSettingsView()
    }
}
