//
//  DetailsSchemaFieldRow.swift
//  BrainMesh
//

import SwiftUI

// MARK: - Row

struct DetailsFieldRow: View {
    let field: MetaDetailFieldDefinition

    private var subtitle: String {
        var parts: [String] = [field.type.title]
        if let unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, field.type.supportsUnit {
            parts.append("Einheit: \(unit)")
        }
        if field.type.supportsOptions {
            let count = field.options.count
            parts.append("\(count) Option\(count == 1 ? "" : "en")")
        }
        return parts.joined(separator: " · ")
    }

    private var unit: String? {
        field.unit
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: field.type.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 24)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(field.name.isEmpty ? "Feld" : field.name)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if field.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
