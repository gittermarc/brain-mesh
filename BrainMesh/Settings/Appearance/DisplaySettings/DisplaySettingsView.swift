//
//  DisplaySettingsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct DisplaySettingsView: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var display: DisplaySettingsStore

    @State private var showResetConfirm: Bool = false
    @State private var showDisplayResetConfirm: Bool = false

    var body: some View {
        List {

            DisplaySettingsPresetSection(showDisplayResetConfirm: $showDisplayResetConfirm)
            DisplaySettingsAppSection()

            DisplaySettingsEntitiesHomeSection()
            DisplaySettingsEntityDetailSection()
            DisplaySettingsAttributeDetailSection()
            DisplaySettingsAttributesAllListSection()
            DisplaySettingsStatsSection()

            // Keep the Graph preview close to the Graph-specific options.
            DisplaySettingsPreviewSection()
            DisplaySettingsGraphSection()
            DisplaySettingsColorPresetsSection()
            DisplaySettingsColorsResetSection(showResetConfirm: $showResetConfirm)
        }
        .navigationTitle("Darstellung")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Darstellung zurücksetzen?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) {
                appearance.resetToDefaults()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Alle Farb- und Graph-Darstellungs-Einstellungen werden auf die Standardwerte zurückgesetzt.")
        }
        .confirmationDialog("Ansicht zurücksetzen?", isPresented: $showDisplayResetConfirm, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) {
                display.resetAll()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Alle Ansichts-Einstellungen (Listen/Detailansichten) werden auf die Preset-Defaults zurückgesetzt.")
        }
    }
}

#Preview {
    NavigationStack {
        DisplaySettingsView()
            .environmentObject(AppearanceStore())
            .environmentObject(DisplaySettingsStore())
    }
}
