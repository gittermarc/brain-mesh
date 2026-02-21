//
//  EntityAttributesAllListSection.swift
//  BrainMesh
//
//  P0.4: Extracted from EntityDetailView+AttributesSection.swift
//

import Foundation
import SwiftUI
import SwiftData

struct EntityAttributesAllListSection: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity
    let rows: [EntityAttributesAllListModel.Row]
    let settings: AttributesAllListDisplaySettings
    let onMutate: () -> Void

    var body: some View {
        let groups = EntityAttributesAllGrouping.makeGroups(rows: rows, settings: settings)

        Group {
            if groups.count == 1, groups.first?.title == "Alle Attribute" {
                let allRows = groups.first?.rows ?? []
                if settings.stickyHeadersEnabled {
                    Section(header: Text("Alle Attribute")) {
                        rowsForEach(allRows)
                    }
                } else {
                    EntityAttributesAllGrouping.inlineHeaderRow(title: "Alle Attribute")
                    rowsForEach(allRows)
                }
            } else {
                ForEach(groups) { group in
                    if settings.stickyHeadersEnabled {
                        Section {
                            rowsForEach(group.rows)
                        } header: {
                            EntityAttributesAllGrouping.groupHeader(title: group.title, systemImage: group.systemImage)
                        }
                    } else {
                        EntityAttributesAllGrouping.inlineHeaderRow(title: group.title, systemImage: group.systemImage)
                        rowsForEach(group.rows)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowsForEach(_ rows: [EntityAttributesAllListModel.Row]) -> some View {
        ForEach(rows) { row in
            attributeRow(row)
        }
        .onDelete { offsets in
            deleteAttributes(at: offsets, rows: rows)
        }
    }

    @ViewBuilder
    private func attributeRow(_ row: EntityAttributesAllListModel.Row) -> some View {
        NavigationLink {
            AttributeDetailView(attribute: row.attribute)
        } label: {
            HStack(spacing: 12) {
                if shouldShowIcon(row: row) {
                    attributeIconView(row: row)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)

                    if settings.notesPreviewLines > 0, let note = row.notePreview {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(settings.notesPreviewLines)
                    }

                    if settings.showPinnedDetails, !row.pinnedChips.isEmpty {
                        pinnedDetailsView(row: row, style: settings.pinnedDetailsStyle)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.vertical, rowVerticalPadding(settings.rowDensity))
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    private func shouldShowIcon(row: EntityAttributesAllListModel.Row) -> Bool {
        switch settings.iconPolicy {
        case .always:
            return true
        case .onlyIfSet:
            return row.isIconSet
        case .never:
            return false
        }
    }

    private func attributeIconView(row: EntityAttributesAllListModel.Row) -> some View {
        Image(systemName: row.iconSymbolName)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 22)
            .foregroundStyle(.tint)
    }

    private func rowVerticalPadding(_ density: AttributesAllRowDensity) -> CGFloat {
        switch density {
        case .compact: return 6
        case .standard: return 10
        case .comfortable: return 14
        }
    }

    @ViewBuilder
    private func pinnedDetailsView(
        row: EntityAttributesAllListModel.Row,
        style: AttributesAllPinnedDetailsStyle
    ) -> some View {
        switch style {
        case .chips:
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(row.pinnedChips) { chip in
                    EntityAttributesAllPinnedChipView(title: chip.title, systemImage: chip.systemImage)
                }
            }

        case .inline:
            Text(row.pinnedChips.map { $0.title }.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

        case .twoColumns:
            let cols: [GridItem] = [
                GridItem(.flexible(minimum: 80), spacing: 8),
                GridItem(.flexible(minimum: 80), spacing: 8)
            ]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                ForEach(row.pinnedChips) { chip in
                    Label(chip.title, systemImage: chip.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func deleteAttributes(at offsets: IndexSet, rows: [EntityAttributesAllListModel.Row]) {
        for index in offsets {
            guard rows.indices.contains(index) else { continue }
            let attr = rows[index].attribute

            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            LinkCleanup.deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID, in: modelContext)

            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
        onMutate()
    }
}
