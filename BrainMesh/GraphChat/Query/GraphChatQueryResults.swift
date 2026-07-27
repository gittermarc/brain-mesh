//
//  GraphChatQueryResults.swift
//  BrainMesh
//
//  Value-only deterministic query results and aggregation payloads.
//

import Foundation

nonisolated enum GraphChatResultState: String, Hashable, Sendable {
    case success
    case noResults
    case noEvidence
}

nonisolated enum GraphChatQueryCellValue: Hashable, Sendable {
    case text(String)
    case integer(Int)
    case decimal(Double)
    case date(Date)
    case boolean(Bool)
    case choice(String)
    case missing
}

nonisolated struct GraphChatQueryCell: Hashable, Sendable, Identifiable {
    let fieldID: UUID
    let fieldName: String
    let unit: String?
    let value: GraphChatQueryCellValue
    let evidenceID: GraphEvidenceID

    var id: UUID {
        fieldID
    }
}

nonisolated struct GraphChatQueryResultRow: Hashable, Sendable, Identifiable {
    let node: NodeRefKey
    let label: String
    let cells: [GraphChatQueryCell]
    let evidenceIDs: [GraphEvidenceID]

    var id: NodeRefKey {
        node
    }
}

nonisolated enum GraphChatAggregationKind: String, Hashable, Sendable {
    case count
    case groupCount
    case minimum
    case maximum
}

nonisolated struct GraphChatGroupCount: Hashable, Sendable, Identifiable {
    let value: GraphChatQueryCellValue
    let count: Int
    let evidenceIDs: [GraphEvidenceID]

    var id: String {
        "\(GraphChatQueryValueFormatting.stableKey(value)):\(count)"
    }
}

nonisolated struct GraphChatAggregationResult: Hashable, Sendable {
    let kind: GraphChatAggregationKind
    let fieldID: UUID?
    let fieldName: String?
    let count: Int?
    let groups: [GraphChatGroupCount]
    let value: GraphChatQueryCellValue?
    let evidenceIDs: [GraphEvidenceID]
}

nonisolated struct GraphChatQueryResult: Hashable, Sendable {
    let state: GraphChatResultState
    let rows: [GraphChatQueryResultRow]
    let aggregation: GraphChatAggregationResult?
    let appliedFilters: [GraphChatAppliedFilter]
    let evidence: [GraphEvidence]
    let resultWindow: GraphChatResultWindow
    let integrityConflictedValueKeys: Set<DetailValueAuthorityKey>

    init(
        state: GraphChatResultState,
        rows: [GraphChatQueryResultRow],
        aggregation: GraphChatAggregationResult?,
        appliedFilters: [GraphChatAppliedFilter],
        evidence: [GraphEvidence],
        resultWindow: GraphChatResultWindow? = nil,
        integrityConflictedValueKeys: Set<DetailValueAuthorityKey> = []
    ) {
        self.state = state
        self.rows = rows
        self.aggregation = aggregation
        self.appliedFilters = appliedFilters
        self.evidence = evidence
        self.resultWindow = resultWindow ?? GraphChatResultWindow.complete(
            totalCount: aggregation == nil ? rows.count : aggregation?.groups.count ?? 1
        )
        self.integrityConflictedValueKeys = integrityConflictedValueKeys
    }
}

nonisolated enum GraphChatQueryEngineError: Error, LocalizedError, Equatable, Sendable {
    case sourceUnavailable
    case graphScopeMismatch
    case entityMismatch
    case resultLimitExceeded(maximum: Int)
    case evidenceLimitExceeded(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            return "Die angeforderten Graphdaten sind nicht mehr verfügbar."
        case .graphScopeMismatch:
            return "Die geladenen Query-Daten gehören nicht zum validierten Graphen."
        case .entityMismatch:
            return "Die geladenen Query-Daten gehören nicht zur validierten Entity."
        case .resultLimitExceeded(let maximum):
            return "Das Query-Limit überschreitet das Maximum von \(maximum)."
        case .evidenceLimitExceeded(let maximum):
            return "Die Query würde das Evidence-Limit von \(maximum) überschreiten."
        }
    }
}

nonisolated enum GraphChatQueryValueFormatting {
    static func stableKey(_ value: GraphChatQueryCellValue) -> String {
        switch value {
        case .text(let value):
            return "0:\(BMSearch.fold(value))"
        case .integer(let value):
            return "1:\(String(format: "%020d", value))"
        case .decimal(let value):
            return "2:\(String(format: "%024.8f", value))"
        case .date(let value):
            return "3:\(String(format: "%024.6f", value.timeIntervalSinceReferenceDate))"
        case .boolean(let value):
            return "4:\(value ? 1 : 0)"
        case .choice(let value):
            return "5:\(BMSearch.fold(value))"
        case .missing:
            return "9:missing"
        }
    }
}

nonisolated extension GraphDetailValuePayload {
    var graphChatCellValue: GraphChatQueryCellValue {
        switch self {
        case .text(let value):
            return .text(value)
        case .integer(let value):
            return .integer(value)
        case .decimal(let value):
            return .decimal(value)
        case .date(let value):
            return .date(value)
        case .boolean(let value):
            return .boolean(value)
        case .choice(let value):
            return .choice(value)
        case .empty:
            return .missing
        }
    }
}
