//
//  EntityAttributesSectionView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData

struct EntityAttributesSectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity
    @Binding var showAddAttribute: Bool

    @AppStorage("BMEntityAttributeSortMode") private var sortModeRaw: String = AttributeSortMode.nameAZ.rawValue
    @State private var filterText: String = ""

    private var currentSortMode: AttributeSortMode {
        AttributeSortMode(rawValue: sortModeRaw) ?? .nameAZ
    }

    private var sortModeBinding: Binding<AttributeSortMode> {
        Binding(
            get: { AttributeSortMode(rawValue: sortModeRaw) ?? .nameAZ },
            set: { sortModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        let base = entity.attributesList

        let filteredAttributes: [MetaAttribute] = {
            let needle = BMSearch.fold(filterText)
            guard !needle.isEmpty else { return base }

            return base.filter { attr in
                if attr.nameFolded.contains(needle) { return true }
                if !attr.notes.isEmpty {
                    return BMSearch.fold(attr.notes).contains(needle)
                }
                return false
            }
        }()

        let sortedAttributes = currentSortMode.sort(filteredAttributes)

        Section {
            if base.count >= 8 {
                attributeSearchRow
            }

            if sortedAttributes.isEmpty {
                Text(filterText.isEmpty ? "Noch keine Attribute." : "Keine Treffer.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedAttributes) { attr in
                    NavigationLink { AttributeDetailView(attribute: attr) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: attr.iconSymbolName ?? "tag")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 22)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(attr.name)
                                if let note = attr.notes.isEmpty ? nil : attr.notes {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    deleteAttributes(at: offsets, sorted: sortedAttributes)
                }
            }

            Button { showAddAttribute = true } label: {
                Label("Attribut hinzufügen", systemImage: "plus")
            }
        } header: {
            DetailSectionHeader(
                title: "Attribute",
                systemImage: "tag",
                subtitle: "Attribute gehören zur Entität und können selbst Links/Bilder/Anhänge haben."
            ) {
                Menu {
                    Picker("Sortieren", selection: sortModeBinding) {
                        ForEach(AttributeSortMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }

                    if !filterText.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            filterText = ""
                        } label: {
                            Label("Suche zurücksetzen", systemImage: "xmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
            }
        }
    }

    private var attributeSearchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Attribut suchen…", text: $filterText)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(true)

            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche löschen")
            }
        }
        .padding(.vertical, 6)
    }

    private func deleteAttributes(at offsets: IndexSet, sorted: [MetaAttribute]) {
        for index in offsets {
            guard sorted.indices.contains(index) else { continue }
            let attr = sorted[index]

            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            LinkCleanup.deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID, in: modelContext)

            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
    }
}

private enum AttributeSortMode: String, CaseIterable, Identifiable {
    case nameAZ
    case nameZA
    case notesFirst
    case photosFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nameAZ: return "Name (A–Z)"
        case .nameZA: return "Name (Z–A)"
        case .notesFirst: return "Notizen zuerst"
        case .photosFirst: return "Bilder zuerst"
        }
    }

    var systemImage: String {
        switch self {
        case .nameAZ: return "textformat.abc"
        case .nameZA: return "textformat.abc.dottedunderline"
        case .notesFirst: return "note.text"
        case .photosFirst: return "photo"
        }
    }

    func sort(_ attrs: [MetaAttribute]) -> [MetaAttribute] {
        switch self {
        case .nameAZ:
            return attrs.sorted { $0.nameFolded < $1.nameFolded }
        case .nameZA:
            return attrs.sorted { $0.nameFolded > $1.nameFolded }
        case .notesFirst:
            return attrs.sorted { lhs, rhs in
                let ln = lhs.notes.isEmpty ? 1 : 0
                let rn = rhs.notes.isEmpty ? 1 : 0
                if ln != rn { return ln < rn }
                return lhs.nameFolded < rhs.nameFolded
            }
        case .photosFirst:
            return attrs.sorted { lhs, rhs in
                let lp = (lhs.imageData != nil || (lhs.imagePath?.isEmpty == false)) ? 0 : 1
                let rp = (rhs.imageData != nil || (rhs.imagePath?.isEmpty == false)) ? 0 : 1
                if lp != rp { return lp < rp }
                return lhs.nameFolded < rhs.nameFolded
            }
        }
    }
}
