//
//  DetailsFormatting.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import Foundation

nonisolated enum DetailValuePresentationSnapshot: Hashable, Sendable {
    case empty
    case value(DetailTypedValue)
    case conflict
}

enum DetailsFormatting {
    static let conflictDisplayText = "Mehrere Werte – bitte prüfen"

    static func presentationSnapshot(
        for field: MetaDetailFieldDefinition,
        on attribute: MetaAttribute
    ) -> DetailValuePresentationSnapshot {
        presentationSnapshot(
            for: field,
            on: attribute,
            records: attribute.detailValuesList.filter {
                $0.fieldID == field.id
            }
        )
    }

    static func presentationSnapshot(
        for field: MetaDetailFieldDefinition,
        on attribute: MetaAttribute,
        records: [MetaDetailFieldValue]
    ) -> DetailValuePresentationSnapshot {
        switch DetailDataModelSnapshotMapper.authority(
            field: field,
            attribute: attribute,
            records: records
        ) {
        case .missing:
            return .empty
        case .authoritative(_, let value, _):
            return value.isEmpty ? .empty : .value(value)
        case .conflict, .invalid:
            return .conflict
        }
    }

    static func displayValue(
        for field: MetaDetailFieldDefinition,
        on attribute: MetaAttribute
    ) -> String? {
        displayValue(
            for: field,
            snapshot: presentationSnapshot(for: field, on: attribute)
        )
    }

    static func displayValue(
        for field: MetaDetailFieldDefinition,
        snapshot: DetailValuePresentationSnapshot
    ) -> String? {
        switch snapshot {
        case .empty:
            return nil
        case .conflict:
            return conflictDisplayText
        case .value(let value):
            switch value {
            case .text(let text), .choice(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : text
            case .integer(let integer):
                return formatNumber(integer, unit: field.unit)
            case .decimal(let decimal):
                return formatNumber(decimal, unit: field.unit)
            case .date(let date):
                return formatDate(date)
            case .boolean(let boolean):
                return boolean ? "Ja" : "Nein"
            case .empty:
                return nil
            }
        }
    }

    static func shortPillValue(
        for field: MetaDetailFieldDefinition,
        on attribute: MetaAttribute
    ) -> String? {
        shortPillValue(
            for: field,
            snapshot: presentationSnapshot(for: field, on: attribute)
        )
    }

    static func shortPillValue(
        for field: MetaDetailFieldDefinition,
        snapshot: DetailValuePresentationSnapshot
    ) -> String? {
        guard let raw = displayValue(for: field, snapshot: snapshot) else {
            return nil
        }

        let maxLen: Int = 22

        switch field.type {
        case .multiLineText:
            return raw.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maxLen)
                .description

        default:
            return raw.count > maxLen ? String(raw.prefix(maxLen)) + "…" : raw
        }
    }

    static func systemImage(for field: MetaDetailFieldDefinition) -> String {
        field.type.systemImage
    }

    private static func formatNumber(_ v: Int, unit: String?) -> String {
        if let unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(v) \(unit)".trimmingCharacters(in: .whitespaces)
        }
        return "\(v)"
    }

    private static func formatNumber(_ v: Double, unit: String?) -> String {
        let formatted = v.formatted(.number.precision(.fractionLength(0...2)))
        if let unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(formatted) \(unit)".trimmingCharacters(in: .whitespaces)
        }
        return formatted
    }

    private static func formatDate(_ d: Date) -> String {
        d.formatted(date: .numeric, time: .omitted)
    }
}
