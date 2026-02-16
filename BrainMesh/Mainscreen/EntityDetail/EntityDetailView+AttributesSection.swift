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

struct NodeAppearanceCard: View {
    @Binding var iconSymbolName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Darstellung", systemImage: "paintbrush")

            IconPickerRow(title: "Icon", symbolName: $iconSymbolName)
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}

struct NodeCardHeader: View {
    let title: String
    let systemImage: String

    var trailingTitle: String? = nil
    var trailingSystemImage: String? = nil
    var trailingAction: (() -> Void)? = nil

    init(
        title: String,
        systemImage: String,
        trailingTitle: String? = nil,
        trailingSystemImage: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingTitle = trailingTitle
        self.trailingSystemImage = trailingSystemImage
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)

            Text(title)
                .font(.headline)

            Spacer(minLength: 0)

            if let trailingTitle, let trailingSystemImage, let trailingAction {
                Button(action: trailingAction) {
                    Label(trailingTitle, systemImage: trailingSystemImage)
                        .font(.callout.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct NodeEmptyStateRow: View {
    let text: String
    let ctaTitle: String
    let ctaSystemImage: String
    let ctaAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .foregroundStyle(.secondary)

            Button(action: ctaAction) {
                Label(ctaTitle, systemImage: ctaSystemImage)
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}


struct EntityAttributesAllView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity

    @State private var searchText: String = ""

    var body: some View {
        List {
            if !searchText.isEmpty {
                Section {
                    Text("Suche: \(searchText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(filteredAttributes) { attr in
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
                .onDelete(perform: deleteAttributes)
            } header: {
                Text("Alle Attribute")
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Attribut suchen…")
        .navigationTitle("Attribute")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filteredAttributes: [MetaAttribute] {
        let base = entity.attributesList
        let needle = BMSearch.fold(searchText)
        guard !needle.isEmpty else {
            return base.sorted { $0.nameFolded < $1.nameFolded }
        }
        return base.filter { a in
            if a.nameFolded.contains(needle) { return true }
            if !a.notes.isEmpty {
                return BMSearch.fold(a.notes).contains(needle)
            }
            return false
        }
        .sorted { $0.nameFolded < $1.nameFolded }
    }

    private func deleteAttributes(at offsets: IndexSet) {
        for index in offsets {
            guard filteredAttributes.indices.contains(index) else { continue }
            let attr = filteredAttributes[index]

            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            LinkCleanup.deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID, in: modelContext)

            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
    }
}

