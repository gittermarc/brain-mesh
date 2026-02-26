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

    @State private var showImportSettings: Bool = false

    var body: some View {
        List {
            hubSection
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showImportSettings) {
            NavigationStack {
                ImportSettingsView()
            }
        }
    }

    private var hubSection: some View {
        Section {
            displayCard

            Button {
                showImportSettings = true
            } label: {
                SettingsHubCardRow(
                    systemImage: "square.and.arrow.down",
                    title: "Import",
                    subtitle: "Bild- und Video-Kompression"
                )
            }
            .buttonStyle(.plain)
            .settingsHubCardStyle(showsAccessoryChevron: true)

            NavigationLink {
                SyncMaintenanceView()
            } label: {
                SettingsHubCardRow(
                    systemImage: "arrow.triangle.2.circlepath",
                    title: "Sync & Wartung",
                    subtitle: "iCloud-Status und lokale Caches"
                )
            }
            .settingsHubCardStyle(showsAccessoryChevron: false)

            NavigationLink {
                HelpSupportView()
            } label: {
                SettingsHubCardRow(
                    systemImage: "lifepreserver",
                    title: "Hilfe & Support",
                    subtitle: "Onboarding, Version & Infos"
                )
            }
            .settingsHubCardStyle(showsAccessoryChevron: false)
        } header: {
            EmptyView()
        }
    }

}

#Preview {
    NavigationStack {
        SettingsView(showDoneButton: false)
    }
}
