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
			Section {
                Picker("Preset", selection: display.presetBinding) {
                    ForEach(DisplayPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

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

                SettingsInlineHeaderRow(title: "Listenstil")

                Picker("Stil", selection: display.entitiesHomeBinding(\.listStyle)) {
                    ForEach(EntitiesHomeListStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Picker("Zeilenstil", selection: display.entitiesHomeBinding(\.rowStyle)) {
                    ForEach(EntitiesHomeRowStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Picker("Zeilenabstand", selection: display.entitiesHomeBinding(\.density)) {
                    ForEach(EntitiesHomeRowDensity.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Toggle("Separatoren", isOn: display.entitiesHomeBinding(\.showSeparators))

                Picker("Badges", selection: display.entitiesHomeBinding(\.badgeStyle)) {
                    ForEach(EntitiesHomeBadgeStyle.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Picker("Meta-Zeile", selection: display.entitiesHomeBinding(\.metaLine)) {
                    ForEach(EntitiesHomeMetaLine.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                SettingsInlineHeaderRow(title: "Meta")

                Toggle("Attribut-Count anzeigen", isOn: showEntityAttributeCountBinding)
                Toggle("Link-Count anzeigen", isOn: showEntityLinkCountBinding)
                Toggle("Notiz-Preview anzeigen", isOn: showEntityNotesPreviewBinding)
                Toggle("Bild-Thumbnail statt Icon", isOn: preferEntityThumbnailBinding)

                Button {
                    display.resetEntitiesHome()
                } label: {
                    Text("Entitäten-Übersicht auf Preset zurücksetzen")
                }
            } header: {
                DisplaySettingsSectionHeader(title: "Entitäten-Übersicht", isCustomized: display.state.entitiesHomeOverride != nil)
            } footer: {
                Text("Diese Einstellungen betreffen die Übersichtsliste/-grid. Hinweis: Link-Counts können bei sehr großen Graphen minimal teurer sein.")
            }

            Section {
                Picker("Header-Bild", selection: display.entityDetailBinding(\.heroImageStyle)) {
                    ForEach(EntityDetailHeroImageStyle.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Toggle("Hero-Pills anzeigen", isOn: display.entityDetailBinding(\.showHeroPills))

                Stepper(value: heroPillLimitBinding, in: 0...10) {
                    HStack {
                        Text("Max. Pills")
                        Spacer(minLength: 0)
                        Text("\(display.entityDetail.heroPillLimit)")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!display.entityDetail.showHeroPills)

                NavigationLink {
                    EntityDetailSectionsEditorView()
                } label: {
                    HStack {
                        Text("Sektionen")
                        Spacer(minLength: 0)
                        Text(entityDetailSectionsSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    display.resetEntityDetail()
                } label: {
                    Text("Entity-Detail auf Preset zurücksetzen")
                }
            } header: {
                DisplaySettingsSectionHeader(title: "Entity-Detail", isCustomized: display.state.entityDetailOverride != nil)
            } footer: {
                Text("Hier stellst du ein, wie Entity-Detailseiten grundsätzlich aufgebaut sind (Header + Sektionen).")
            }

            Section {
                Picker("Fokusmodus", selection: display.attributeDetailBinding(\.focusMode)) {
                    ForEach(AttributeDetailFocusMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Picker("Details-Layout", selection: display.attributeDetailBinding(\.detailsLayout)) {
                    ForEach(AttributeDetailDetailsLayout.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Toggle("Leere Felder ausblenden", isOn: display.attributeDetailBinding(\.hideEmptyDetails))

                NavigationLink {
                    AttributeDetailSectionsEditorView()
                } label: {
                    HStack {
                        Text("Sektionen")
                        Spacer(minLength: 0)
                        Text(attributeDetailSectionsSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    display.resetAttributeDetail()
                } label: {
                    Text("Attribute-Detail auf Preset zurücksetzen")
                }
            } header: {
                DisplaySettingsSectionHeader(title: "Attribute-Detail", isCustomized: display.state.attributeDetailOverride != nil)
            } footer: {
                Text("Diese Optionen betreffen die Detailansicht eines Attributs (Fokus + Layout + Sektionen).")
            }

            Section {
                Picker("Dichte", selection: display.attributesAllListBinding(\.rowDensity)) {
                    ForEach(AttributesAllRowDensity.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Picker("Icons", selection: display.attributesAllListBinding(\.iconPolicy)) {
                    ForEach(AttributesAllIconPolicy.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Picker("Notiz-Preview", selection: display.attributesAllListBinding(\.notesPreviewLines)) {
                    Text("Aus").tag(0)
                    Text("1 Zeile").tag(1)
                    Text("2 Zeilen").tag(2)
                }

                Picker("Pinned-Details", selection: display.attributesAllListBinding(\.pinnedDetailsStyle)) {
                    ForEach(AttributesAllPinnedDetailsStyle.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Picker("Gruppierung", selection: display.attributesAllListBinding(\.grouping)) {
                    ForEach(AttributesAllGrouping.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Toggle("Sticky Header", isOn: display.attributesAllListBinding(\.stickyHeadersEnabled))

                Button {
                    display.resetAttributesAllList()
                } label: {
                    Text("Alle Attribute auf Preset zurücksetzen")
                }
            } header: {
                DisplaySettingsSectionHeader(title: "Alle Attribute", isCustomized: display.state.attributesAllListOverride != nil)
            } footer: {
                Text("Diese Einstellungen gelten für die \"Alle Attribute\"-Liste innerhalb einer Entity.")
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

    // MARK: - Summaries

    private var entityDetailSectionsSummary: String {
        let hidden = display.entityDetail.hiddenSections.count
        let collapsed = display.entityDetail.collapsedSections.count
        if hidden == 0 && collapsed == 0 { return "Standard" }
        if hidden == 0 { return "\(collapsed) eingeklappt" }
        if collapsed == 0 { return "\(hidden) verborgen" }
        return "\(hidden) verborgen, \(collapsed) eingeklappt"
    }

    private var attributeDetailSectionsSummary: String {
        let hidden = display.attributeDetail.hiddenSections.count
        let collapsed = display.attributeDetail.collapsedSections.count
        if hidden == 0 && collapsed == 0 { return "Standard" }
        if hidden == 0 { return "\(collapsed) eingeklappt" }
        if collapsed == 0 { return "\(hidden) verborgen" }
        return "\(hidden) verborgen, \(collapsed) eingeklappt"
    }

    // MARK: - Bindings

    private var heroPillLimitBinding: Binding<Int> {
        Binding(
            get: { display.entityDetail.heroPillLimit },
            set: { newValue in
                display.updateEntityDetail { settings in
                    settings.heroPillLimit = max(0, min(10, newValue))
                }
            }
        )
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
            .environmentObject(DisplaySettingsStore())
    }
}
