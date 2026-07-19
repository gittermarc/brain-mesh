//
//  BrainMeshSearchDetailValueFormatter.swift
//  BrainMesh
//
//  Pure formatting helpers shared by detail-value search candidate construction and tests.
//

import Foundation

nonisolated struct BrainMeshSearchDetailValueContent: Equatable, Sendable {
    let stringValue: String?
    let intValue: Int?
    let doubleValue: Double?
    let dateValue: Date?
    let boolValue: Bool?

    init(
        stringValue: String? = nil,
        intValue: Int? = nil,
        doubleValue: Double? = nil,
        dateValue: Date? = nil,
        boolValue: Bool? = nil
    ) {
        self.stringValue = stringValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.dateValue = dateValue
        self.boolValue = boolValue
    }
}

nonisolated enum BrainMeshSearchDetailValueFormatter {
    static func rankingFields(
        for components: BrainMeshSearchDetailValueContent
    ) -> [BrainMeshSearchRankingField] {
        var fields: [BrainMeshSearchRankingField] = []

        if let stringValue = components.stringValue,
            stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            fields.append(
                BrainMeshSearchRankingField(
                    text: stringValue,
                    reason: "Detailwert",
                    priority: .primaryLabel
                )
            )
        }

        if let intValue = components.intValue {
            fields.append(
                BrainMeshSearchRankingField(
                    text: String(intValue),
                    reason: "Detailwert",
                    priority: .primaryLabel
                )
            )
        }

        if let doubleValue = components.doubleValue {
            fields.append(
                BrainMeshSearchRankingField(
                    text: String(doubleValue),
                    reason: "Detailwert",
                    priority: .primaryLabel
                )
            )
        }

        if let dateValue = components.dateValue {
            fields.append(
                BrainMeshSearchRankingField(
                    text: localizedDateText(dateValue),
                    reason: "Detailwert",
                    priority: .primaryLabel
                )
            )
            fields.append(
                BrainMeshSearchRankingField(
                    text: isoDateText(dateValue),
                    reason: "Detailwert",
                    priority: .metadata
                )
            )
        }

        if let boolValue = components.boolValue {
            fields.append(
                BrainMeshSearchRankingField(
                    text: localizedBoolText(boolValue),
                    reason: "Detailwert",
                    priority: .primaryLabel
                )
            )
            fields.append(
                BrainMeshSearchRankingField(
                    text: metadataBoolText(boolValue),
                    reason: "Detailwert",
                    priority: .metadata
                )
            )
        }

        return fields
    }

    static func displayText(for components: BrainMeshSearchDetailValueContent) -> String? {
        if let stringValue = components.stringValue,
            stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            return stringValue
        }
        if let intValue = components.intValue {
            return String(intValue)
        }
        if let doubleValue = components.doubleValue {
            return String(doubleValue)
        }
        if let dateValue = components.dateValue {
            return localizedDateText(dateValue)
        }
        if let boolValue = components.boolValue {
            return localizedBoolText(boolValue)
        }
        return nil
    }

    static func localizedDateText(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    static func isoDateText(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    static func localizedBoolText(_ value: Bool) -> String {
        value ? "Ja" : "Nein"
    }

    static func metadataBoolText(_ value: Bool) -> String {
        value ? "true" : "false"
    }
}
