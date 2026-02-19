//
//  NodeDetailsValuesCard.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import SwiftUI

struct NodeDetailsValuesCard: View {
    let attribute: MetaAttribute
    let owner: MetaEntity

    let onConfigureSchema: () -> Void
    let onEditValue: (MetaDetailFieldDefinition) -> Void

    private var fields: [MetaDetailFieldDefinition] {
        owner.detailFieldsList
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Details", systemImage: "info.circle")

            if fields.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Felder definiert.",
                    ctaTitle: "Felder für \"\(owner.name.isEmpty ? "Entität" : owner.name)\" anlegen",
                    ctaSystemImage: "slider.horizontal.3",
                    ctaAction: onConfigureSchema
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(fields) { field in
                        Button {
                            onEditValue(field)
                        } label: {
                            DetailsKeyValueRow(
                                name: field.name,
                                value: DetailsFormatting.displayValue(for: field, on: attribute),
                                isPinned: field.isPinned
                            )
                        }
                        .buttonStyle(.plain)

                        if field.id != fields.last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .padding(12)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

private struct DetailsKeyValueRow: View {
    let name: String
    let value: String?
    let isPinned: Bool

    private var displayName: String {
        name.isEmpty ? "Feld" : name
    }

    private var displayValue: String {
        let s = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "Hinzufügen" : s
    }

    private var isEmpty: Bool {
        let s = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                if !isEmpty {
                    Text(displayValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if isEmpty {
                Text(displayValue)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tint)
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }
}
