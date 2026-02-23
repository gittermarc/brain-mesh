//
//  SettingsView+ImportSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension SettingsView {
    var importSection: some View {
        Section {
            Toggle("Videos beim Import komprimieren", isOn: $compressVideosOnImport)

            Picker("Qualität", selection: qualityBinding) {
                ForEach(VideoCompression.Quality.allCases) { q in
                    Text(q.title).tag(q)
                }
            }
            .disabled(!compressVideosOnImport)

            Picker("Bilder (Galerie) – Qualität", selection: galleryImageCompressionPresetBinding) {
                ForEach(ImageGalleryCompressionPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            if galleryImageCompressionPresetBinding.wrappedValue == .original {
                Text("Hinweis: \"Original\" kann iCloud-Speicher & Sync-Zeit deutlich erhöhen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Wenn aktiv, werden Videos nur dann komprimiert, wenn sie größer als 25 MB sind. Kleinere Videos bleiben unverändert. \n\nTipp: \"Hoch\" behält mehr Qualität (kann aber eher scheitern, wenn das Video selbst nach Komprimierung nicht unter 25 MB passt). \"Klein\" ist am sparsamsten.")
        }
    }
}
