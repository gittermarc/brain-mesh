//
//  NodeDetailsValuesCard+RowModel.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import Foundation

extension NodeDetailsValuesCard {
    var fields: [MetaDetailFieldDefinition] {
        owner.detailFieldsList
    }

    struct FieldRow: Identifiable {
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

    var rows: [FieldRow] {
        fields.map { field in
            FieldRow(field: field, value: DetailsFormatting.displayValue(for: field, on: attribute))
        }
    }

    var visibleRows: [FieldRow] {
        if hideEmpty {
            return rows.filter { !$0.isEmpty }
        }
        return rows
    }

    var emptyRows: [FieldRow] {
        rows.filter { $0.isEmpty }
    }
}
