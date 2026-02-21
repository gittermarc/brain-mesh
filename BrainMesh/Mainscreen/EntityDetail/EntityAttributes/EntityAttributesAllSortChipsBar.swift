//
//  EntityAttributesAllSortChipsBar.swift
//  BrainMesh
//
//  P0.4: Extracted from EntityDetailView+AttributesSection.swift
//

import Foundation
import SwiftUI

struct EntityAttributesAllPinnedChipView: View {
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

struct EntityAttributesAllSortChipsBar: View {
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
