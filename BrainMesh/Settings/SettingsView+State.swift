//
//  SettingsView+State.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import SwiftUI

extension SettingsView {
    struct AlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
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

    func refreshCacheSizes() {
        Task.detached(priority: .utility) {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file

            let imageBytes = (try? ImageStore.cacheSizeBytes()) ?? 0
            let attachmentBytes = (try? AttachmentStore.cacheSizeBytes()) ?? 0

            let imageText = formatter.string(fromByteCount: imageBytes)
            let attachmentText = formatter.string(fromByteCount: attachmentBytes)

            await MainActor.run {
                imageCacheSizeText = imageText
                attachmentCacheSizeText = attachmentText
            }
        }
    }
}
