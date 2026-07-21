//
//  GraphChatQueryEngine+Sorting.swift
//  BrainMesh
//
//  Stable typed sorting with an attribute-ID tiebreaker.
//

import Foundation

nonisolated extension GraphChatQueryEngine {
    static func sortedRows(
        _ rows: [GraphChatPreparedQueryRow],
        using sorting: [GraphValidatedQuerySort]
    ) -> [GraphChatPreparedQueryRow] {
        rows.sorted { lhs, rhs in
            for sort in sorting {
                let comparison: GraphChatQueryComparisonResult
                switch sort.key {
                case .nodeName:
                    comparison = compareText(
                        lhs.attribute.displayLabel,
                        rhs.attribute.displayLabel
                    )
                case .field(let fieldID):
                    let lhsValue = lhs.valuesByFieldID[fieldID]?.value
                    let rhsValue = rhs.valuesByFieldID[fieldID]?.value
                    let lhsPresent = lhsValue.map(isPresent) ?? false
                    let rhsPresent = rhsValue.map(isPresent) ?? false
                    if lhsPresent != rhsPresent {
                        return lhsPresent
                    }
                    comparison = compareOptionalPayloads(lhsValue, rhsValue)
                }

                guard comparison != .orderedSame else {
                    continue
                }
                if comparison == .orderedAscending {
                    return sort.direction == .ascending
                }
                return sort.direction == .descending
            }
            return lhs.attribute.id.uuidString < rhs.attribute.id.uuidString
        }
    }

    static func compareOptionalPayloads(
        _ lhs: GraphDetailValuePayload?,
        _ rhs: GraphDetailValuePayload?
    ) -> GraphChatQueryComparisonResult {
        let lhsPresent = lhs.map(isPresent) ?? false
        let rhsPresent = rhs.map(isPresent) ?? false
        if lhsPresent != rhsPresent {
            return lhsPresent ? .orderedAscending : .orderedDescending
        }
        guard lhsPresent, let lhs, let rhs else {
            return .orderedSame
        }
        return comparePayloads(lhs, rhs)
    }

    static func comparePayloads(
        _ lhs: GraphDetailValuePayload,
        _ rhs: GraphDetailValuePayload
    ) -> GraphChatQueryComparisonResult {
        switch (lhs, rhs) {
        case (.text(let lhs), .text(let rhs)),
            (.choice(let lhs), .choice(let rhs)):
            return compareText(lhs, rhs)
        case (.integer(let lhs), .integer(let rhs)):
            return compare(lhs, rhs)
        case (.decimal(let lhs), .decimal(let rhs)):
            return compare(lhs, rhs)
        case (.date(let lhs), .date(let rhs)):
            return compare(lhs, rhs)
        case (.boolean(let lhs), .boolean(let rhs)):
            return compare(lhs ? 1 : 0, rhs ? 1 : 0)
        case (.empty, .empty):
            return .orderedSame
        default:
            return compareText(
                String(describing: lhs),
                String(describing: rhs)
            )
        }
    }

    private static func compareText(
        _ lhs: String,
        _ rhs: String
    ) -> GraphChatQueryComparisonResult {
        let foldedLHS = BMSearch.fold(lhs)
        let foldedRHS = BMSearch.fold(rhs)
        if foldedLHS < foldedRHS {
            return .orderedAscending
        }
        if foldedLHS > foldedRHS {
            return .orderedDescending
        }
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }

    private static func compare<T: Comparable>(
        _ lhs: T,
        _ rhs: T
    ) -> GraphChatQueryComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }
}
