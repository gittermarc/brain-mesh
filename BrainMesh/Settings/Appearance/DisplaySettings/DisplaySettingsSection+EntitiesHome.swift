//
//  DisplaySettingsSection+EntitiesHome.swift
//  BrainMesh
//
//  PR 03: Split DisplaySettingsView into section files.
//

import SwiftUI

struct DisplaySettingsEntitiesHomeSection: View {
    @EnvironmentObject private var appearance: AppearanceStore
    @EnvironmentObject private var display: DisplaySettingsStore

    var body: some View {
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
    }

    // MARK: - Bindings

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
}
