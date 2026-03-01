//
//  NodeDetailsValuesCard+Components.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import SwiftUI

struct NodeDetailsValuesContent: View {
    let rows: [NodeDetailsValuesCard.FieldRow]
    let emptyRows: [NodeDetailsValuesCard.FieldRow]

    let layout: AttributeDetailDetailsLayout
    let hideEmpty: Bool

    @Binding var showEmptyFields: Bool

    let onEditValue: (MetaDetailFieldDefinition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hideEmpty, rows.isEmpty, !emptyRows.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Werte gesetzt.",
                    ctaTitle: "Leere Felder anzeigen",
                    ctaSystemImage: "chevron.down"
                ) {
                    withAnimation(.snappy) {
                        showEmptyFields = true
                    }
                }
            } else {
                contentBody(rows: rows)
            }

            if hideEmpty, !emptyRows.isEmpty {
                Divider().opacity(0.25)

                DisclosureGroup(
                    isExpanded: $showEmptyFields,
                    content: {
                        VStack(spacing: 0) {
                            ForEach(emptyRows) { row in
                                Button {
                                    onEditValue(row.field)
                                } label: {
                                    DetailsKeyValueRow(
                                        name: row.field.name,
                                        value: row.value,
                                        isPinned: row.field.isPinned
                                    )
                                }
                                .buttonStyle(.plain)

                                if row.id != emptyRows.last?.id {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                        .padding(.top, 8)
                    },
                    label: {
                        HStack(spacing: 10) {
                            Image(systemName: "rectangle.stack")
                                .foregroundStyle(.secondary)
                            Text("Leere Felder (\(emptyRows.count))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                )
                .tint(.primary)
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func contentBody(rows: [NodeDetailsValuesCard.FieldRow]) -> some View {
        switch layout {
        case .list:
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    Button {
                        onEditValue(row.field)
                    } label: {
                        DetailsKeyValueRow(
                            name: row.field.name,
                            value: row.value,
                            isPinned: row.field.isPinned
                        )
                    }
                    .buttonStyle(.plain)

                    if row.id != rows.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }

        case .cards:
            LazyVStack(spacing: 10) {
                ForEach(rows) { row in
                    Button {
                        onEditValue(row.field)
                    } label: {
                        DetailsFieldCard(
                            name: row.field.name,
                            value: row.value,
                            isPinned: row.field.isPinned
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

        case .twoColumns:
            LazyVGrid(
                columns: [GridItem(.flexible(minimum: 120), spacing: 12), GridItem(.flexible(minimum: 120), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(rows) { row in
                    Button {
                        onEditValue(row.field)
                    } label: {
                        DetailsFieldTile(
                            name: row.field.name,
                            value: row.value,
                            isPinned: row.field.isPinned
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct DetailsKeyValueRow: View {
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

struct DetailsFieldCard: View {
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(displayValue)
                    .font(isEmpty ? .callout.weight(.semibold) : .callout)
                    .foregroundStyle(isEmpty ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10))
        )
    }
}

struct DetailsFieldTile: View {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Text(displayValue)
                .font(isEmpty ? .callout.weight(.semibold) : .callout)
                .foregroundStyle(isEmpty ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .lineLimit(4)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10))
        )
    }
}
