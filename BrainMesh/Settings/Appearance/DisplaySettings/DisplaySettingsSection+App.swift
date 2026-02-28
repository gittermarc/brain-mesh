//
//  DisplaySettingsSection+App.swift
//  BrainMesh
//
//  PR 03: Split DisplaySettingsView into section files.
//

import SwiftUI

struct DisplaySettingsPresetSection: View {
    @EnvironmentObject private var display: DisplaySettingsStore

    @Binding var showDisplayResetConfirm: Bool

    @State private var selection: DisplayPreset = .clean
    @State private var pendingPreset: DisplayPreset?
    @State private var showPresetApplyDialog: Bool = false

    var body: some View {
        Section {
            Picker("Preset", selection: $selection) {
                ForEach(DisplayPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onAppear {
                selection = display.preset
            }
            .onChange(of: display.preset) { newValue in
                // Keep the segmented control in sync with external changes.
                guard pendingPreset == nil else { return }
                if selection != newValue {
                    selection = newValue
                }
            }
            .onChange(of: selection) { newValue in
                handlePresetSelection(newValue)
            }
            .confirmationDialog("Preset anwenden?", isPresented: $showPresetApplyDialog, titleVisibility: .visible) {
                Button("Anpassungen behalten") {
                    commitPendingPreset(applyToAllScreens: false)
                }
                Button("Preset auf alles anwenden", role: .destructive) {
                    commitPendingPreset(applyToAllScreens: true)
                }
                Button("Abbrechen", role: .cancel) {
                    cancelPendingPreset()
                }
            } message: {
                Text(presetApplyMessage)
            }

            Button(role: .destructive) {
                showDisplayResetConfirm = true
            } label: {
                Text("Ansicht zurücksetzen")
            }
        } header: {
            Text("Ansichts-Preset")
        } footer: {
            Text("Dieses Preset setzt die Standardwerte für die Darstellung (Listen/Detailansichten). Pro Bereich kannst du feinjustieren – und jederzeit wieder auf das Preset zurückspringen.")
        }
    }

    private func handlePresetSelection(_ newPreset: DisplayPreset) {
        // Ignore programmatic sync updates.
        guard newPreset != display.preset else { return }

        // If there are per-screen overrides, changing the preset would appear to “do nothing” for those screens.
        // Ask the user whether the preset should overwrite customizations.
        if display.hasAnyOverrides {
            pendingPreset = newPreset
            showPresetApplyDialog = true
        } else {
            display.applyPreset(newPreset, applyToAllScreens: false)
        }
    }

    private func commitPendingPreset(applyToAllScreens: Bool) {
        guard let pendingPreset else {
            selection = display.preset
            return
        }
        display.applyPreset(pendingPreset, applyToAllScreens: applyToAllScreens)
        self.pendingPreset = nil
        selection = display.preset
    }

    private func cancelPendingPreset() {
        pendingPreset = nil
        selection = display.preset
    }

    private var presetApplyMessage: String {
        let count = display.overrideCount
        if count == 1 {
            return "Du hast bereits 1 Bereich feinjustiert. Soll das Preset nur die Standardwerte ändern – oder auch deine Anpassung überschreiben?"
        } else {
            return "Du hast bereits \(count) Bereiche feinjustiert. Soll das Preset nur die Standardwerte ändern – oder auch deine Anpassungen überschreiben?"
        }
    }
}

struct DisplaySettingsPreviewSection: View {
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        Section("Vorschau") {
            GraphAppearancePreview(theme: GraphTheme(settings: appearance.settings.graph))
                .frame(height: 150)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        }
    }
}

struct DisplaySettingsAppSection: View {
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        Section("App") {
            ColorPicker("Akzentfarbe", selection: tintBinding, supportsOpacity: false)

            Picker("Farbschema", selection: colorSchemeBinding) {
                ForEach(AppColorSchemePreference.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
        }
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.app.tint.color },
            set: { appearance.setTint($0) }
        )
    }

    private var colorSchemeBinding: Binding<AppColorSchemePreference> {
        Binding(
            get: { appearance.settings.app.colorScheme },
            set: { appearance.setColorScheme($0) }
        )
    }
}

struct DisplaySettingsColorPresetsSection: View {
    @EnvironmentObject private var appearance: AppearanceStore

    var body: some View {
        Section("Farb-Presets") {
            ForEach(AppearancePreset.allCases) { preset in
                Button {
                    appearance.applyPreset(preset)
                } label: {
                    PresetRow(preset: preset)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DisplaySettingsColorsResetSection: View {
    @Binding var showResetConfirm: Bool

    var body: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Text("Farben zurücksetzen")
            }
        } footer: {
            Text("Tipp: Presets ändern App- und Graph-Farben gemeinsam. Wenn du nur am Graph schrauben willst, stell danach einfach deine Wunsch-Akzentfarbe wieder ein.")
        }
    }
}

// MARK: - Shared components

struct SettingsInlineHeaderRow: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct PresetRow: View {
    let preset: AppearancePreset

    var body: some View {
        let s = preset.makeSettings()
        let t = GraphTheme(settings: s.graph)

        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(s.app.tint.color).frame(width: 10, height: 10)
                Circle().fill(t.entityColor).frame(width: 10, height: 10)
                Circle().fill(t.attributeColor).frame(width: 10, height: 10)
                Circle().fill(t.highlightColor).frame(width: 10, height: 10)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title)
                    .font(.body.weight(.semibold))
                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
                .imageScale(.small)
        }
        .contentShape(Rectangle())
    }
}
