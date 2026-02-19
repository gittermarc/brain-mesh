//
//  DisplaySettingsView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct DisplaySettingsView: View {
    @EnvironmentObject private var appearance: AppearanceStore

    @State private var showResetConfirm: Bool = false

    var body: some View {
        List {
            Section("Vorschau") {
                GraphAppearancePreview(theme: GraphTheme(settings: appearance.settings.graph))
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }

            Section("App") {
                ColorPicker("Akzentfarbe", selection: tintBinding, supportsOpacity: false)

                Picker("Farbschema", selection: colorSchemeBinding) {
                    ForEach(AppColorSchemePreference.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }

            Section {
                Picker("Darstellung", selection: entitiesLayoutBinding) {
                    ForEach(EntitiesHomeLayoutStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Picker("Dichte", selection: entitiesDensityBinding) {
                    ForEach(EntitiesHomeDensity.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Picker("Icon-Größe", selection: entitiesIconSizeBinding) {
                    ForEach(EntitiesHomeIconSize.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Toggle("Attribut-Count anzeigen", isOn: showEntityAttributeCountBinding)
                Toggle("Link-Count anzeigen", isOn: showEntityLinkCountBinding)
                Toggle("Notiz-Preview anzeigen", isOn: showEntityNotesPreviewBinding)
                Toggle("Bild-Thumbnail statt Icon", isOn: preferEntityThumbnailBinding)
            } header: {
                Text("Entitäten")
            } footer: {
                Text("Diese Einstellungen beeinflussen die Darstellung im Entitäten-Tab. Link-Counts können bei sehr großen Graphen minimal teurer sein.")
            }

            Section("Graph") {
                Picker("Hintergrund", selection: backgroundStyleBinding) {
                    ForEach(GraphBackgroundStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                if appearance.settings.graph.backgroundStyle.needsPrimaryColor {
                    ColorPicker("Hintergrund (Primär)", selection: backgroundPrimaryBinding)
                }
                if appearance.settings.graph.backgroundStyle.needsSecondaryColor {
                    ColorPicker("Hintergrund (Sekundär)", selection: backgroundSecondaryBinding)
                }

                SettingsInlineHeaderRow(title: "Knotenfarben")
                ColorPicker("Entitäten", selection: entityColorBinding)
                ColorPicker("Attribute", selection: attributeColorBinding)

                SettingsInlineHeaderRow(title: "Kantenfarben")
                ColorPicker("Links", selection: linkColorBinding)
                ColorPicker("Containment", selection: containmentColorBinding)

                SettingsInlineHeaderRow(title: "Interaktion")
                ColorPicker("Highlight / Auswahl", selection: highlightColorBinding)
                Toggle("Label-Halo", isOn: labelHaloBinding)
            }

            Section("Presets") {
                ForEach(AppearancePreset.allCases) { preset in
                    Button {
                        appearance.applyPreset(preset)
                    } label: {
                        PresetRow(preset: preset)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text("Auf Standard zurücksetzen")
                }
            } footer: {
                Text("Tipp: Presets ändern App- und Graph-Farben gemeinsam. Wenn du nur am Graph schrauben willst, stell danach einfach deine Wunsch-Akzentfarbe wieder ein.")
            }
        }
        .navigationTitle("Darstellung")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Darstellung zurücksetzen?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) {
                appearance.resetToDefaults()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Alle Darstellungs-Einstellungen werden auf die Standardwerte zurückgesetzt.")
        }
    }

    // MARK: - Bindings

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

    private var entitiesLayoutBinding: Binding<EntitiesHomeLayoutStyle> {
        Binding(
            get: { appearance.settings.entitiesHome.layout },
            set: { appearance.setEntitiesHomeLayout($0) }
        )
    }

    private var entitiesDensityBinding: Binding<EntitiesHomeDensity> {
        Binding(
            get: { appearance.settings.entitiesHome.density },
            set: { appearance.setEntitiesHomeDensity($0) }
        )
    }

    private var entitiesIconSizeBinding: Binding<EntitiesHomeIconSize> {
        Binding(
            get: { appearance.settings.entitiesHome.iconSize },
            set: { appearance.setEntitiesHomeIconSize($0) }
        )
    }

    private var showEntityAttributeCountBinding: Binding<Bool> {
        Binding(
            get: { appearance.settings.entitiesHome.showAttributeCount },
            set: { appearance.setShowEntityAttributeCount($0) }
        )
    }

    private var showEntityLinkCountBinding: Binding<Bool> {
        Binding(
            get: { appearance.settings.entitiesHome.showLinkCount },
            set: { appearance.setShowEntityLinkCount($0) }
        )
    }

    private var showEntityNotesPreviewBinding: Binding<Bool> {
        Binding(
            get: { appearance.settings.entitiesHome.showNotesPreview },
            set: { appearance.setShowEntityNotesPreview($0) }
        )
    }

    private var preferEntityThumbnailBinding: Binding<Bool> {
        Binding(
            get: { appearance.settings.entitiesHome.preferThumbnailOverIcon },
            set: { appearance.setPreferEntityThumbnailOverIcon($0) }
        )
    }

    private var backgroundStyleBinding: Binding<GraphBackgroundStyle> {
        Binding(
            get: { appearance.settings.graph.backgroundStyle },
            set: { appearance.setGraphBackgroundStyle($0) }
        )
    }

    private var backgroundPrimaryBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.backgroundPrimary.color },
            set: { appearance.setGraphBackgroundPrimary($0) }
        )
    }

    private var backgroundSecondaryBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.backgroundSecondary.color },
            set: { appearance.setGraphBackgroundSecondary($0) }
        )
    }

    private var entityColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.entityColor.color },
            set: { appearance.setEntityColor($0) }
        )
    }

    private var attributeColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.attributeColor.color },
            set: { appearance.setAttributeColor($0) }
        )
    }

    private var linkColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.linkColor.color },
            set: { appearance.setLinkColor($0) }
        )
    }

    private var containmentColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.containmentColor.color },
            set: { appearance.setContainmentColor($0) }
        )
    }

    private var highlightColorBinding: Binding<Color> {
        Binding(
            get: { appearance.settings.graph.highlightColor.color },
            set: { appearance.setHighlightColor($0) }
        )
    }

    private var labelHaloBinding: Binding<Bool> {
        Binding(
            get: { appearance.settings.graph.labelHaloEnabled },
            set: { appearance.setLabelHaloEnabled($0) }
        )
    }
}

private struct SettingsInlineHeaderRow: View {
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

#Preview {
    NavigationStack {
        DisplaySettingsView()
            .environmentObject(AppearanceStore())
    }
}
