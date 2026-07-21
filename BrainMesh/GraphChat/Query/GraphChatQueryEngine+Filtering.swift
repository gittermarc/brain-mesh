//
//  GraphChatQueryEngine+Filtering.swift
//  BrainMesh
//
//  Typed filter evaluation and applied-filter descriptions.
//

import Foundation

nonisolated extension GraphChatQueryEngine {
    static func matchesAllFilters(
        _ row: GraphChatPreparedQueryRow,
        filters: [GraphValidatedQueryFilter]
    ) -> Bool {
        filters.allSatisfy { filter in
            matches(
                row.valuesByFieldID[filter.fieldID]?.value,
                filter: filter
            )
        }
    }

    static func matches(
        _ payload: GraphDetailValuePayload?,
        filter: GraphValidatedQueryFilter
    ) -> Bool {
        if filter.operation == .isPresent {
            return payload.map(isPresent) ?? false
        }
        if filter.operation == .isMissing {
            return payload.map(isPresent) != true
        }

        guard let payload, isPresent(payload) else {
            return false
        }

        switch (filter.fieldType, filter.operation, filter.value, payload) {
        case (.singleLineText, .contains, .text(let query), .text(let value)),
            (.multiLineText, .contains, .text(let query), .text(let value)):
            return BMSearch.fold(value).contains(BMSearch.fold(query))

        case (.singleLineText, .equals, .text(let query), .text(let value)),
            (.multiLineText, .equals, .text(let query), .text(let value)):
            return BMSearch.fold(value) == BMSearch.fold(query)

        case (.singleLineText, .startsWith, .text(let query), .text(let value)),
            (.multiLineText, .startsWith, .text(let query), .text(let value)):
            return BMSearch.fold(value).hasPrefix(BMSearch.fold(query))

        case (.numberInt, .equals, .integer(let expected), .integer(let actual)):
            return actual == expected
        case (.numberInt, .lessThan, .integer(let expected), .integer(let actual)):
            return actual < expected
        case (.numberInt, .lessThanOrEqual, .integer(let expected), .integer(let actual)):
            return actual <= expected
        case (.numberInt, .greaterThan, .integer(let expected), .integer(let actual)):
            return actual > expected
        case (.numberInt, .greaterThanOrEqual, .integer(let expected), .integer(let actual)):
            return actual >= expected
        case (.numberInt, .between, .integerRange(let range), .integer(let actual)):
            return actual >= range.lowerBound && actual <= range.upperBound

        case (.numberDouble, .equals, .decimal(let expected), .decimal(let actual)):
            return actual == expected
        case (.numberDouble, .lessThan, .decimal(let expected), .decimal(let actual)):
            return actual < expected
        case (.numberDouble, .lessThanOrEqual, .decimal(let expected), .decimal(let actual)):
            return actual <= expected
        case (.numberDouble, .greaterThan, .decimal(let expected), .decimal(let actual)):
            return actual > expected
        case (.numberDouble, .greaterThanOrEqual, .decimal(let expected), .decimal(let actual)):
            return actual >= expected
        case (.numberDouble, .between, .decimalRange(let range), .decimal(let actual)):
            return actual >= range.lowerBound && actual <= range.upperBound

        case (.date, .before, .date(let boundary), .date(let actual)):
            return actual < boundary
        case (.date, .after, .date(let boundary), .date(let actual)):
            return actual > boundary
        case (.date, .between, .dateInterval(let interval), .date(let actual)),
            (.date, .inYear, .dateInterval(let interval), .date(let actual)),
            (.date, .inMonth, .dateInterval(let interval), .date(let actual)),
            (.date, .isOverdue, .dateInterval(let interval), .date(let actual)):
            return actual >= interval.lowerBound && actual < interval.upperBoundExclusive

        case (.toggle, .equals, .boolean(let expected), .boolean(let actual)):
            return actual == expected

        case (.singleChoice, .equals, .choice(let expected), .choice(let actual)):
            return GraphQueryChoiceNormalizer.normalize(actual)
                == GraphQueryChoiceNormalizer.normalize(expected.canonicalValue)
        case (.singleChoice, .oneOf, .choices(let expected), .choice(let actual)):
            let normalizedActual = GraphQueryChoiceNormalizer.normalize(actual)
            return expected.contains {
                GraphQueryChoiceNormalizer.normalize($0.canonicalValue) == normalizedActual
            }

        default:
            return false
        }
    }

    static func appliedFilters(
        _ filters: [GraphValidatedQueryFilter],
        fieldMap: [UUID: GraphDetailFieldDefinitionDTO]
    ) -> [GraphChatAppliedFilter] {
        filters.enumerated().map { index, filter in
            let fieldName = fieldMap[filter.fieldID]?.name ?? filter.fieldID.uuidString
            let valueDescription = filter.valueDescription
                ?? filterValueDescription(filter.value)
            let stableKey = [
                filter.fieldID.uuidString,
                filter.operation.rawValue,
                valueDescription ?? "",
                String(index)
            ].joined(separator: "|")
            return GraphChatAppliedFilter(
                id: GraphEvidenceStableIdentity.deterministicUUID(for: stableKey),
                fieldName: fieldName,
                operationDescription: operationDescription(filter.operation),
                valueDescription: valueDescription
            )
        }
    }

    static func isPresent(_ payload: GraphDetailValuePayload) -> Bool {
        switch payload {
        case .text(let value), .choice(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .decimal(let value):
            return value.isFinite
        case .integer, .date, .boolean:
            return true
        case .empty:
            return false
        }
    }

    private static func operationDescription(
        _ operation: GraphQueryFilterOperator
    ) -> String {
        switch operation {
        case .contains: return "enthält"
        case .equals: return "ist gleich"
        case .startsWith: return "beginnt mit"
        case .isPresent: return "ist vorhanden"
        case .isMissing: return "fehlt"
        case .lessThan: return "ist kleiner als"
        case .lessThanOrEqual: return "ist kleiner oder gleich"
        case .greaterThan: return "ist größer als"
        case .greaterThanOrEqual: return "ist größer oder gleich"
        case .between: return "liegt zwischen"
        case .before: return "liegt vor"
        case .after: return "liegt nach"
        case .inYear: return "liegt im Jahr"
        case .inMonth: return "liegt im Monat"
        case .isOverdue: return "ist überfällig"
        case .oneOf: return "ist einer von"
        }
    }

    private static func filterValueDescription(
        _ value: GraphValidatedFilterValue
    ) -> String? {
        switch value {
        case .none:
            return nil
        case .text(let text):
            return text
        case .integer(let integer):
            return String(integer)
        case .integerRange(let range):
            return "\(range.lowerBound) bis \(range.upperBound)"
        case .decimal(let decimal):
            return String(decimal)
        case .decimalRange(let range):
            return "\(range.lowerBound) bis \(range.upperBound)"
        case .date(let date):
            return date.formatted(.iso8601)
        case .dateInterval(let interval):
            return "\(interval.lowerBound.formatted(.iso8601)) bis vor \(interval.upperBoundExclusive.formatted(.iso8601))"
        case .boolean(let boolean):
            return boolean ? "Ja" : "Nein"
        case .choice(let choice):
            return choice.canonicalValue
        case .choices(let choices):
            return choices.map(\.canonicalValue).joined(separator: ", ")
        }
    }
}
