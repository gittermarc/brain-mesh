//
//  EntitiesHomeDisplaySheet.swift
//  BrainMesh
//
//  PR 04/05: Quick "Ansicht" controls directly in Entities Home.
//

import SwiftUI

struct EntitiesHomeDisplaySheet: View {
    @EnvironmentObject private var display: DisplaySettingsStore
    @EnvironmentObject private var appearance: AppearanceStore

    @Binding var isPresented: Bool

    private var settings: EntitiesHomeDisplaySettings { display.entitiesHome }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Layout", selection: display.entitiesHomeBinding(\.layout)) {
                        ForEach(EntitiesHomeLayoutMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    Picker("Liste", selection: display.entitiesHomeBinding(\.listStyle)) {
                        ForEach(EntitiesHomeListStyle.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .disabled(settings.layout == .grid)

                    Picker("Row", selection: display.entitiesHomeBinding(\.rowStyle)) {
                        ForEach(EntitiesHomeRowStyle.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    Picker("Dichte", selection: display.entitiesHomeBinding(\.density)) {
                        ForEach(EntitiesHomeRowDensity.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                } header: {
                    Text("Grundlayout")
                }

                Section {
                    Toggle("Separatoren", isOn: display.entitiesHomeBinding(\.showSeparators))
                        .disabled(settings.layout == .grid || settings.listStyle == .cards)

                    Picker("Badges", selection: display.entitiesHomeBinding(\.badgeStyle)) {
                        ForEach(EntitiesHomeBadgeStyle.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .disabled(settings.rowStyle != .titleWithBadges)

                    Picker("Unterzeile", selection: display.entitiesHomeBinding(\.metaLine)) {
                        ForEach(EntitiesHomeMetaLine.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .disabled(settings.rowStyle != .titleWithSubtitle)
                } header: {
                    Text("Stil")
                } footer: {
                    Text("Badges gelten nur für \"Titel + Badges\". Unterzeile gilt nur für \"Titel + Unterzeile\".")
                }

                Section {
                    Toggle(isOn: display.entitiesHomeBinding(\.showAttributeCount)) {
                        HStack {
                            Text("Attribut-Count")
                            Spacer(minLength: 0)
                            LightningLabel(meta: EntitiesHomeDisplaySettings.optionMeta[.showAttributeCount])
                        }
                    }

                    Toggle(isOn: display.entitiesHomeBinding(\.showLinkCount)) {
                        HStack {
                            Text("Link-Count")
                            Spacer(minLength: 0)
                            LightningLabel(meta: EntitiesHomeDisplaySettings.optionMeta[.showLinkCount])
                        }
                    }

                    Toggle("Notiz-Preview", isOn: display.entitiesHomeBinding(\.showNotesPreview))

                    Toggle(isOn: display.entitiesHomeBinding(\.preferThumbnailOverIcon)) {
                        HStack {
                            Text("Thumbnail statt Icon")
                            Spacer(minLength: 0)
                            LightningLabel(meta: EntitiesHomeDisplaySettings.optionMeta[.preferThumbnailOverIcon])
                        }
                    }

                    Picker("Icon-Größe", selection: iconSizeBinding) {
                        ForEach(EntitiesHomeIconSize.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                } header: {
                    Text("Inhalt")
                } footer: {
                    Text("⚡️ Counts können bei sehr großen Graphen das Laden/Scrollen minimal verlangsamen.")
                }

                Section {
                    Button(role: .destructive) {
                        display.resetEntitiesHome()
                    } label: {
                        Text("Entitäten-Ansicht zurücksetzen")
                    }
                }
            }
            .navigationTitle("Ansicht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { isPresented = false }
                }
            }
        }
    }

    private var iconSizeBinding: Binding<EntitiesHomeIconSize> {
        Binding(
            get: { appearance.settings.entitiesHome.iconSize },
            set: { appearance.setEntitiesHomeIconSize($0) }
        )
    }
}

private struct LightningLabel: View {
    let meta: DisplayOptionMeta?

    var body: some View {
        if let meta, meta.impact.showsLightning {
            Text(meta.impact.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else {
            EmptyView()
        }
    }
}
