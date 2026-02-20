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

    var layout: AttributeDetailDetailsLayout = .list
    var hideEmpty: Bool = false

    let onConfigureSchema: () -> Void
    let onEditValue: (MetaDetailFieldDefinition) -> Void

    @State private var showEmptyFields: Bool = false

    private var fields: [MetaDetailFieldDefinition] {
        owner.detailFieldsList
    }

    private struct FieldRow: Identifiable {
        let id: UUID
        let field: MetaDetailFieldDefinition
        let value: String?

        init(field: MetaDetailFieldDefinition, value: String?) {
            self.id = field.id
            self.field = field
            self.value = value
        }

        var isEmpty: Bool {
            value == nil
        }
    }

    private var rows: [FieldRow] {
        fields.map { field in
            FieldRow(field: field, value: DetailsFormatting.displayValue(for: field, on: attribute))
        }
    }

    private var visibleRows: [FieldRow] {
        if hideEmpty {
            return rows.filter { !$0.isEmpty }
        }
        return rows
    }

    private var emptyRows: [FieldRow] {
        rows.filter { $0.isEmpty }
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
                detailsContainer
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
        .onAppear {
            if hideEmpty, visibleRows.isEmpty, !emptyRows.isEmpty {
                showEmptyFields = true
            }
        }
        .onChange(of: hideEmpty) { _, newValue in
            if newValue, visibleRows.isEmpty, !emptyRows.isEmpty {
                showEmptyFields = true
            }
            if !newValue {
                showEmptyFields = false
            }
        }
    }

    private var detailsContainer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hideEmpty, visibleRows.isEmpty, !emptyRows.isEmpty {
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
                contentBody(rows: visibleRows)
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
    private func contentBody(rows: [FieldRow]) -> some View {
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

private struct DetailsFieldCard: View {
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

private struct DetailsFieldTile: View {
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
