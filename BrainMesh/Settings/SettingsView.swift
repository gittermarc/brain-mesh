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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVGrid(columns: hubGridColumns, spacing: 12) {
                proTile
                    .gridCellColumns(hubGridColumns.count)

                displayTile

                Button {
                    showImportSettings = true
                } label: {
                    SettingsHubTile(
                        systemImage: "square.and.arrow.down",
                        title: "Import",
                        subtitle: "Bild- und Video-Kompression",
                        showsAccessoryIndicator: true
                    )
                }
                .buttonStyle(SettingsHubTileButtonStyle())

                NavigationLink {
                    SyncMaintenanceView()
                } label: {
                    SettingsHubTile(
                        systemImage: "arrow.triangle.2.circlepath",
                        title: "Sync & Wartung",
                        subtitle: "iCloud-Status und lokale Caches",
                        showsAccessoryIndicator: false
                    )
                }
                .buttonStyle(SettingsHubTileButtonStyle())

                NavigationLink {
                    HelpSupportView()
                } label: {
                    SettingsHubTile(
                        systemImage: "lifepreserver",
                        title: "Hilfe & Support",
                        subtitle: "Onboarding, Version & Infos",
                        showsAccessoryIndicator: false
                    )
                }
                .buttonStyle(SettingsHubTileButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
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

    private var hubGridColumns: [GridItem] {
        let columnCount: Int = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }

}

#Preview {
    NavigationStack {
        SettingsView(showDoneButton: false)
    }
    .environmentObject(ProEntitlementStore())
}
