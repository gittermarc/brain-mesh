//
//  EntityDetailView+AttributesSection.swift
//  BrainMesh
//
//  P0.3 Split: Attributes card + appearance card + attributes all view
//

import SwiftUI
import SwiftData

struct NodeEntityAttributesCard: View {
    let entity: MetaEntity

    private var preview: [MetaAttribute] {
        Array(entity.attributesList.sorted(by: { $0.nameFolded < $1.nameFolded }).prefix(12))
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Attribute", systemImage: "tag")

            if entity.attributesList.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Attribute.",
                    ctaTitle: "Attribute ansehen",
                    ctaSystemImage: "tag",
                    ctaAction: {}
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(preview) { attr in
                        NavigationLink {
                            AttributeDetailView(attribute: attr)
                        } label: {
                            Label(attr.name.isEmpty ? "Attribut" : attr.name, systemImage: attr.iconSymbolName ?? "tag")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    EntityAttributesAllView(entity: entity)
                } label: {
                    Label("Alle", systemImage: "chevron.right")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}


struct EntityAttributesAllView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity

    @State private var searchText: String = ""

    @AppStorage("BMEntityAttributesAllSort") private var sortSelectionRaw: String = EntityAttributesAllSortSelection.default.rawValue
    @AppStorage("BMEntityAttributesAllShowPinnedDetails") private var showPinnedDetails: Bool = false
    @AppStorage("BMEntityAttributesAllShowNotesPreview") private var showNotesPreview: Bool = false

    @StateObject private var listModel: EntityAttributesAllListModel = EntityAttributesAllListModel()

    private var sortSelection: EntityAttributesAllSortSelection {
        EntityAttributesAllSortSelection(rawValue: sortSelectionRaw)
    }

    var body: some View {
        let visible = listModel.visibleRows

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

            Section {
                ForEach(visible) { attr in
                    NavigationLink {
                        AttributeDetailView(attribute: attr.attribute)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: attr.iconSymbolName)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 22)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(attr.title)

                                if let note = attr.notePreview {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                if showPinnedDetails, !attr.pinnedChips.isEmpty {
                                    FlowLayout(spacing: 6, lineSpacing: 6) {
                                        ForEach(attr.pinnedChips) { chip in
                                            EntityAttributesAllPinnedChipView(
                                                title: chip.title,
                                                systemImage: chip.systemImage
                                            )
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    deleteAttributes(at: offsets, visible: visible)
                }
            } header: {
                Text("Alle Attribute")
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Attribut suchen…")
        .navigationTitle("Attribute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Anzeige") {
                        Toggle(isOn: $showPinnedDetails) {
                            Label("Pinned Details anzeigen", systemImage: "pin")
                        }

                        Toggle(isOn: $showNotesPreview) {
                            Label("Notizen-Vorschau", systemImage: "note.text")
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
        .onChange(of: showPinnedDetails) { _, _ in
            rebuild(debounce: false)
        }
        .onChange(of: showNotesPreview) { _, _ in
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
        listModel.scheduleRebuild(
            context: modelContext,
            entity: entity,
            searchText: searchText,
            showPinnedDetails: showPinnedDetails,
            showNotesPreview: showNotesPreview,
            sortSelection: sortSelection,
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

    private func deleteAttributes(at offsets: IndexSet, visible: [EntityAttributesAllListModel.Row]) {
        for index in offsets {
            guard visible.indices.contains(index) else { continue }
            let attr = visible[index].attribute

            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            LinkCleanup.deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID, in: modelContext)

            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
        rebuild(debounce: false)
    }
}

private struct EntityAttributesAllPinnedChipView: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private struct EntityAttributesAllSortChipsBar: View {
    let selection: EntityAttributesAllSortSelection
    let pinnedFields: [MetaDetailFieldDefinition]
    let onSelect: (EntityAttributesAllSortSelection) -> Void

    var body: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            sortChip(
                title: "Name",
                systemImage: "textformat.abc",
                isSelected: isNameSelected,
                accessory: nameAccessory
            ) {
                if case .base(let mode) = selection {
                    if mode == .nameAZ {
                        onSelect(.base(.nameZA))
                    } else {
                        onSelect(.base(.nameAZ))
                    }
                } else {
                    onSelect(.base(.nameAZ))
                }
            }

            sortChip(
                title: "Notizen",
                systemImage: "note.text",
                isSelected: isNotesSelected,
                accessory: nil
            ) {
                onSelect(.base(.notesFirst))
            }

            sortChip(
                title: "Fotos",
                systemImage: "photo",
                isSelected: isPhotosSelected,
                accessory: nil
            ) {
                onSelect(.base(.photosFirst))
            }

            ForEach(pinnedFields) { field in
                let chipTitle = field.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Feld" : field.name
                let sys = DetailsFormatting.systemImage(for: field)

                sortChip(
                    title: chipTitle,
                    systemImage: sys,
                    isSelected: isPinnedSelected(field.id),
                    accessory: pinnedAccessory(field.id)
                ) {
                    handlePinnedTap(field)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var isNameSelected: Bool {
        if case .base(let mode) = selection {
            return mode == .nameAZ || mode == .nameZA
        }
        return false
    }

    private var nameAccessory: String? {
        if case .base(let mode) = selection {
            return mode == .nameZA ? "arrow.down" : "arrow.up"
        }
        return nil
    }

    private var isNotesSelected: Bool {
        if case .base(let mode) = selection {
            return mode == .notesFirst
        }
        return false
    }

    private var isPhotosSelected: Bool {
        if case .base(let mode) = selection {
            return mode == .photosFirst
        }
        return false
    }

    private func isPinnedSelected(_ fieldID: UUID) -> Bool {
        if case .pinned(let id, _) = selection {
            return id == fieldID
        }
        return false
    }

    private func pinnedAccessory(_ fieldID: UUID) -> String? {
        if case .pinned(let id, let dir) = selection, id == fieldID {
            return dir == .descending ? "arrow.down" : "arrow.up"
        }
        return nil
    }

    private func handlePinnedTap(_ field: MetaDetailFieldDefinition) {
        if case .pinned(let id, var dir) = selection, id == field.id {
            dir.toggle()
            onSelect(.pinned(fieldID: field.id, direction: dir))
        } else {
            // Sensible default per type.
            switch field.type {
            case .toggle:
                onSelect(.pinned(fieldID: field.id, direction: .descending))
            default:
                onSelect(.pinned(fieldID: field.id, direction: .ascending))
            }
        }
    }

    @ViewBuilder
    private func sortChip(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessory: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)

                Text(title)
                    .lineLimit(1)

                if let accessory {
                    Image(systemName: accessory)
                        .imageScale(.small)
                }
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Color(uiColor: isSelected ? .secondarySystemGroupedBackground : .tertiarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(Color.secondary.opacity(isSelected ? 0.28 : 0.12))
            )
        }
        .buttonStyle(.plain)
    }
}


