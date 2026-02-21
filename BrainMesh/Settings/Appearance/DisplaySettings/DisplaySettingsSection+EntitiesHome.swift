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
            Picker("Darstellung", selection: display.entitiesHomeBinding(\.layout)) {
                ForEach(EntitiesHomeLayoutMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Dichte", selection: display.entitiesHomeBinding(\.density)) {
                ForEach(EntitiesHomeRowDensity.allCases) { item in
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

            Toggle("Attribut-Count anzeigen", isOn: display.entitiesHomeBinding(\.showAttributeCount))
            Toggle("Link-Count anzeigen", isOn: display.entitiesHomeBinding(\.showLinkCount))
            Toggle("Notiz-Preview anzeigen", isOn: display.entitiesHomeBinding(\.showNotesPreview))
            Toggle("Bild-Thumbnail statt Icon", isOn: display.entitiesHomeBinding(\.preferThumbnailOverIcon))

            Button {
                display.resetEntitiesHome()
            } label: {
                Text("Entitäten-Ansicht zurücksetzen")
            }
        } header: {
            DisplaySettingsSectionHeader(title: "Entitäten-Übersicht", isCustomized: display.state.entitiesHomeOverride != nil)
        } footer: {
            Text("Diese Einstellungen betreffen die Übersichtsliste/-grid. Hinweis: Counts und Thumbnails können bei sehr großen Graphen minimal teurer sein.")
        }
    }

    // MARK: - Bindings

    private var entitiesIconSizeBinding: Binding<EntitiesHomeIconSize> {
        Binding(
            get: { appearance.settings.entitiesHome.iconSize },
            set: { appearance.setEntitiesHomeIconSize($0) }
        )
    }
}
