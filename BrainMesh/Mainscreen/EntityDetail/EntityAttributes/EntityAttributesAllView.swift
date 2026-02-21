//
//  EntityAttributesAllView.swift
//  BrainMesh
//
//  P0.4: Extracted from EntityDetailView+AttributesSection.swift
//

import Foundation
import SwiftUI
import SwiftData

struct EntityAttributesAllView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var display: DisplaySettingsStore

    @Bindable var entity: MetaEntity

    @State private var searchText: String = ""

    @AppStorage(BMAppStorageKeys.entityAttributesAllSort) private var sortSelectionRaw: String = EntityAttributesAllSortSelection.default.rawValue

    @StateObject private var listModel: EntityAttributesAllListModel = EntityAttributesAllListModel()

    private var sortSelection: EntityAttributesAllSortSelection {
        EntityAttributesAllSortSelection(rawValue: sortSelectionRaw)
    }

    var body: some View {
        let visible = listModel.visibleRows
        let settings = display.attributesAllList
        let showPinnedDetails = settings.showPinnedDetails

        List {
            if showPinnedDetails {
                Section {
                    EntityAttributesAllSortChipsBar(
                        selection: sortSelection,
                        pinnedFields: listModel.pinnedSortableFields
                    ) { newSelection in
                        sortSelectionRaw = newSelection.rawValue
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }

            if !searchText.isEmpty || !sortSelection.isDefault {
                Section {
                    if !searchText.isEmpty {
                        Text("Suche: \(searchText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !sortSelection.isDefault {
                        Text("Sortierung: \(sortTitle(for: sortSelection))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            EntityAttributesAllListSection(
                entity: entity,
                rows: visible,
                settings: settings
            ) {
                rebuild(debounce: false)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Attribut suchen…")
        .navigationTitle("Attribute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Anzeige") {
                        Toggle(isOn: display.attributesAllListBinding(\.showPinnedDetails)) {
                            Label("Pinned Details anzeigen", systemImage: "pin")
                        }

                        Picker("Notiz-Preview", selection: display.attributesAllListBinding(\.notesPreviewLines)) {
                            Text("Aus").tag(0)
                            Text("1 Zeile").tag(1)
                            Text("2 Zeilen").tag(2)
                        }
                    }

                    Section("Sortieren") {
                        Picker("Sortieren", selection: baseSortBinding) {
                            ForEach(EntityAttributeSortMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage)
                                    .tag(mode)
                            }
                        }

                        if !listModel.pinnedSortMenuOptions.isEmpty {
                            Divider()
                            Text("Gepinnte Felder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(listModel.pinnedSortMenuOptions) { option in
                                Button {
                                    sortSelectionRaw = option.selection.rawValue
                                } label: {
                                    Label(option.title, systemImage: option.systemImage)
                                }
                            }
                        }
                    }

                    if !searchText.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            searchText = ""
                        } label: {
                            Label("Suche zurücksetzen", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Sortieren")
            }
        }
        .onAppear {
            rebuild(debounce: false)
        }
        .onChange(of: searchText) { _, _ in
            rebuild(debounce: true)
        }
        .onChange(of: sortSelectionRaw) { _, _ in
            rebuild(debounce: false)
        }
        .onChange(of: settings) { _, _ in
            rebuild(debounce: false)
        }
    }

    private var baseSortBinding: Binding<EntityAttributeSortMode> {
        Binding(
            get: { sortSelection.baseModeOrDefault },
            set: { sortSelectionRaw = EntityAttributesAllSortSelection.base($0).rawValue }
        )
    }

    private func rebuild(debounce: Bool) {
        let settings = display.attributesAllList
        listModel.scheduleRebuild(
            context: modelContext,
            entity: entity,
            searchText: searchText,
            showPinnedDetails: settings.showPinnedDetails,
            includeNotesPreview: settings.notesPreviewLines > 0,
            sortSelection: sortSelection,
            grouping: settings.grouping,
            debounce: debounce
        )
    }

    private func sortTitle(for selection: EntityAttributesAllSortSelection) -> String {
        switch selection {
        case .base(let mode):
            return mode.title

        case .pinned(let fieldID, let direction):
            if let field = listModel.pinnedSortableFields.first(where: { $0.id == fieldID })
                ?? listModel.pinnedFields.first(where: { $0.id == fieldID }) {
                let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Feld" : field.name
                switch field.type {
                case .toggle:
                    return "\(name) (\(direction == .descending ? "Ja zuerst" : "Nein zuerst"))"
                case .singleChoice:
                    return "\(name) (\(direction == .descending ? "umgekehrt" : "Optionen"))"
                case .numberInt, .numberDouble, .date:
                    return "\(name) (\(direction == .descending ? "absteigend" : "aufsteigend"))"
                case .singleLineText, .multiLineText:
                    return name
                }
            }
            return "Gepinntes Feld"
        }
    }
}
