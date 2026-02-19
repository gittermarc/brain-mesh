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

    @AppStorage("BMEntityAttributeSortMode") private var sortModeRaw: String = EntityAttributeSortMode.nameAZ.rawValue

    private var currentSortMode: EntityAttributeSortMode {
        EntityAttributeSortMode(rawValue: sortModeRaw) ?? .nameAZ
    }

    private var sortModeBinding: Binding<EntityAttributeSortMode> {
        Binding(
            get: { EntityAttributeSortMode(rawValue: sortModeRaw) ?? .nameAZ },
            set: { sortModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        let visible = visibleAttributes

        List {
            if !searchText.isEmpty || currentSortMode != .nameAZ {
                Section {
                    if !searchText.isEmpty {
                        Text("Suche: \(searchText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if currentSortMode != .nameAZ {
                        Text("Sortierung: \(currentSortMode.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(visible) { attr in
                    NavigationLink {
                        AttributeDetailView(attribute: attr)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: attr.iconSymbolName ?? "tag")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 22)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(attr.name.isEmpty ? "Attribut" : attr.name)
                                if !attr.notes.isEmpty {
                                    Text(attr.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
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
                    Picker("Sortieren", selection: sortModeBinding) {
                        ForEach(EntityAttributeSortMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
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
    }

    private var visibleAttributes: [MetaAttribute] {
        let base = entity.attributesList
        let needle = BMSearch.fold(searchText)
        let filtered: [MetaAttribute]

        if needle.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { a in
                if a.nameFolded.contains(needle) { return true }
                if !a.notes.isEmpty { return BMSearch.fold(a.notes).contains(needle) }
                return false
            }
        }

        return currentSortMode.sort(filtered)
    }

    private func deleteAttributes(at offsets: IndexSet, visible: [MetaAttribute]) {
        for index in offsets {
            guard visible.indices.contains(index) else { continue }
            let attr = visible[index]

            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            LinkCleanup.deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID, in: modelContext)

            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
    }
}


