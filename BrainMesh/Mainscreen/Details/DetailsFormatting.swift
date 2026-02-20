//
//  DetailsFormatting.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import Foundation

enum DetailsFormatting {
    static func displayValue(
        for field: MetaDetailFieldDefinition,
        on attribute: MetaAttribute
    ) -> String? {
        let value = attribute.detailValuesList.first(where: { $0.fieldID == field.id })
        return displayValue(for: field, value: value)
    }

    /// Like `displayValue(for:on:)`, but takes a pre-fetched value.
    /// Useful when building list snapshots to avoid touching relationships in SwiftUI render paths.
    static func displayValue(
        for field: MetaDetailFieldDefinition,
        value: MetaDetailFieldValue?
    ) -> String? {
        guard let value else { return nil }

        switch field.type {
        case .singleLineText, .multiLineText, .singleChoice:
            let s = (value.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s

        case .numberInt:
            guard let v = value.intValue else { return nil }
            return formatNumber(v, unit: field.unit)

        case .numberDouble:
            guard let v = value.doubleValue else { return nil }
            return formatNumber(v, unit: field.unit)

        case .date:
            guard let d = value.dateValue else { return nil }
            return formatDate(d)

        case .toggle:
            guard let b = value.boolValue else { return nil }
            return b ? "Ja" : "Nein"
        }
    }

    static func shortPillValue(
        for field: MetaDetailFieldDefinition,
        on attribute: MetaAttribute
    ) -> String? {
        let value = attribute.detailValuesList.first(where: { $0.fieldID == field.id })
        return shortPillValue(for: field, value: value)
    }

    /// Like `shortPillValue(for:on:)`, but takes a pre-fetched value.
    static func shortPillValue(
        for field: MetaDetailFieldDefinition,
        value: MetaDetailFieldValue?
    ) -> String? {
        guard let raw = displayValue(for: field, value: value) else { return nil }

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
