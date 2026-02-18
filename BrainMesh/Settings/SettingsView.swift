//
//  SettingsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import Foundation
import SwiftUI
import SwiftData

struct SettingsView: View {
    let showDoneButton: Bool

    init(showDoneButton: Bool = false) {
        self.showDoneButton = showDoneButton
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var onboarding: OnboardingCoordinator

    @AppStorage(VideoImportPreferences.compressVideosOnImportKey)
    var compressVideosOnImport: Bool = VideoImportPreferences.defaultCompressVideosOnImport

    @AppStorage(VideoImportPreferences.videoCompressionQualityKey)
    var videoCompressionQualityRaw: String = VideoImportPreferences.defaultQuality.rawValue

    @State var isRebuildingImageCache: Bool = false
    @State var isClearingAttachmentCache: Bool = false

    @State var imageCacheSizeText: String = "—"
    @State var attachmentCacheSizeText: String = "—"

    @State var alertState: AlertState? = nil

    var body: some View {
        List {
            helpSection
            maintenanceSection
            importSection
            appearanceSection
            infoSection
            SettingsAboutSection()
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshCacheSizes()
        }
        .alert(item: $alertState) { state in
            Alert(
                title: Text(state.title),
                message: Text(state.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .toolbar {
            if showDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

}

#Preview {
    NavigationStack {
        SettingsView(showDoneButton: false)
            .environmentObject(OnboardingCoordinator())
    }
}
