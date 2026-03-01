//
//  GraphCanvasScreen+PeekOverlay.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Details Peek UI

    func detailsPeekBar(chips: [GraphDetailsPeekChip]) -> some View {
        let visible = 3

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.prefix(visible))) { chip in
                    Button {
                        openDetailsValueEditor(fieldID: chip.fieldID)
                    } label: {
                        detailsPeekChip(chip)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func entityFieldsPeekPanel(summaryChips: [GraphDetailsPeekChip], fields: [GraphEntityFieldPeekItem]) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(summaryChips) { chip in
                detailsPeekChip(chip)
            }

            if fields.isEmpty {
                Text("Keine Detail-Felder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(fields) { field in
                            entityFieldRow(field)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func entityFieldRow(_ field: GraphEntityFieldPeekItem) -> some View {
        HStack(spacing: 6) {
            if field.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(verbatim: field.fieldName)
                .foregroundStyle(.primary)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.18))
        )
    }

    func detailsPeekChip(_ chip: GraphDetailsPeekChip) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: chip.fieldName)
                .foregroundStyle(.secondary)
            Text(verbatim: ": ")
                .foregroundStyle(.secondary)
            Text(verbatim: chip.valueText)
                .foregroundStyle(chip.isPlaceholder ? .secondary : .primary)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(.secondary.opacity(0.18))
        )
    }
}
