//
//  EntitiesHomeViewOptionsSheet.swift
//  BrainMesh
//
//  PR 04: Quick in-screen view options for Entities Home.
//

import SwiftUI

struct EntitiesHomeViewOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var displaySettings: DisplaySettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Layout", selection: displaySettings.entitiesHomeBinding(\.layout)) {
                        ForEach(EntitiesHomeLayoutMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Layout")
                }

                Section {
                    Picker("Dichte", selection: displaySettings.entitiesHomeBinding(\.density)) {
                        ForEach(EntitiesHomeRowDensity.allCases) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Separatoren", isOn: displaySettings.entitiesHomeBinding(\.showSeparators))
                } header: {
                    Text("Liste")
                }

                Section {
                    Picker("Badges", selection: displaySettings.entitiesHomeBinding(\.badgeStyle)) {
                        ForEach(EntitiesHomeBadgeStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Attribute zählen", isOn: displaySettings.entitiesHomeBinding(\.showAttributeCount))
                    Toggle("Links zählen", isOn: displaySettings.entitiesHomeBinding(\.showLinkCount))
                } header: {
                    Text("Badges")
                }

                Section {
                    Toggle("Notizvorschau", isOn: displaySettings.entitiesHomeBinding(\.showNotesPreview))
                    Toggle("Thumbnail statt Icon", isOn: displaySettings.entitiesHomeBinding(\.preferThumbnailOverIcon))
                } header: {
                    Text("Zusätze")
                }
            }
            .navigationTitle("Ansicht")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
