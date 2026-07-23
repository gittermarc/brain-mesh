//
//  GraphChatAnswerArtifacts.swift
//  BrainMesh
//
//  Value-only, graph-scoped answer artifacts backed exclusively by revalidated evidence.
//

import Foundation

nonisolated struct GraphChatAnswerArtifactID: RawRepresentable, Hashable, Sendable, Identifiable {
    let rawValue: UUID

    var id: UUID {
        rawValue
    }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct GraphChatAnswerArtifactSessionID: RawRepresentable, Hashable, Sendable,
    Identifiable
{
    let rawValue: UUID

    var id: UUID {
        rawValue
    }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct GraphChatAnswerArtifactTransactionID: RawRepresentable, Hashable, Sendable,
    Identifiable
{
    let rawValue: UUID

    var id: UUID {
        rawValue
    }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct GraphChatAnswerArtifactItemID: RawRepresentable, Hashable, Sendable, Identifiable {
    let rawValue: UUID

    var id: UUID {
        rawValue
    }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct GraphChatAnswerArtifactChoiceValue: Hashable, Sendable {
    let value: String
    let label: String

    init(value: String, label: String? = nil) {
        self.value = value
        self.label = label ?? value
    }
}

nonisolated enum GraphChatAnswerArtifactValue: Hashable, Sendable {
    case text(String)
    case integer(Int)
    case decimal(Decimal)
    case boolean(Bool)
    case date(Date)
    case dateTime(Date)
    case duration(TimeInterval)
    case percentage(Decimal)
    case choice(GraphChatAnswerArtifactChoiceValue)
    case missing

    init(queryValue: GraphChatQueryCellValue) {
        switch queryValue {
        case .text(let value):
            self = .text(value)
        case .integer(let value):
            self = .integer(value)
        case .decimal(let value):
            self = .decimal(Decimal(value))
        case .date(let value):
            self = .date(value)
        case .boolean(let value):
            self = .boolean(value)
        case .choice(let value):
            self = .choice(GraphChatAnswerArtifactChoiceValue(value: value))
        case .missing:
            self = .missing
        }
    }
}

nonisolated struct GraphChatAnswerArtifactEvidenceBinding: Hashable, Sendable {
    let evidenceIDs: [GraphEvidenceID]

    init(evidenceIDs: [GraphEvidenceID]) {
        var seen = Set<GraphEvidenceID>()
        self.evidenceIDs = evidenceIDs.filter { seen.insert($0).inserted }
    }

    static let empty = GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: [])
}

nonisolated struct GraphChatAnswerArtifactFilterValue: Hashable, Sendable {
    let fieldID: UUID?
    let fieldName: String
    let operationDescription: String
    let values: [GraphChatAnswerArtifactValue]

    init(
        fieldID: UUID? = nil,
        fieldName: String,
        operationDescription: String,
        values: [GraphChatAnswerArtifactValue] = []
    ) {
        self.fieldID = fieldID
        self.fieldName = fieldName
        self.operationDescription = operationDescription
        self.values = values
    }
}

nonisolated enum GraphChatAnswerArtifactNavigationTarget: Hashable, Sendable {
    case openNode(graphScope: GraphScope, node: NodeRefKey)
    case focusNodeInGraph(graphScope: GraphScope, node: NodeRefKey)
    case openEntityList(
        graphScope: GraphScope,
        entityID: UUID,
        filters: [GraphChatAnswerArtifactFilterValue]
    )
    case showResultNodes(
        graphScope: GraphScope,
        title: String,
        nodes: [NodeRefKey]
    )
    case openResultFilter(
        graphScope: GraphScope,
        entityID: UUID?,
        filters: [GraphChatAnswerArtifactFilterValue],
        resultNodes: [NodeRefKey]
    )
    case highlightNodesInCanvas(graphScope: GraphScope, nodes: [NodeRefKey])
    case clearCanvasHighlight(graphScope: GraphScope)
    case addNodesToCanvasSelection(graphScope: GraphScope, nodes: [NodeRefKey])
    case replaceCanvasSelection(graphScope: GraphScope, nodes: [NodeRefKey])
    case compareNodes(graphScope: GraphScope, nodes: [NodeRefKey])

    var graphScope: GraphScope {
        switch self {
        case .openNode(let graphScope, _),
            .focusNodeInGraph(let graphScope, _),
            .openEntityList(let graphScope, _, _),
            .showResultNodes(let graphScope, _, _),
            .openResultFilter(let graphScope, _, _, _),
            .highlightNodesInCanvas(let graphScope, _),
            .clearCanvasHighlight(let graphScope),
            .addNodesToCanvasSelection(let graphScope, _),
            .replaceCanvasSelection(let graphScope, _),
            .compareNodes(let graphScope, _):
            return graphScope
        }
    }
}

nonisolated extension GraphChatAnswerArtifactNavigationTarget {
    var nodeReferences: [NodeRefKey] {
        switch self {
        case .openNode(_, let node), .focusNodeInGraph(_, let node):
            return [node]
        case .showResultNodes(_, _, let nodes),
            .highlightNodesInCanvas(_, let nodes),
            .addNodesToCanvasSelection(_, let nodes),
            .replaceCanvasSelection(_, let nodes),
            .compareNodes(_, let nodes):
            return nodes
        case .openResultFilter(_, _, _, let resultNodes):
            return resultNodes
        case .openEntityList, .clearCanvasHighlight:
            return []
        }
    }
}

nonisolated enum GraphChatAnswerArtifactTruncationReason: String, CaseIterable, Hashable, Sendable {
    case toolLimit
    case queryLimit
    case uiLimit
    case registryBudget
    case sourceLimited
    case unknown
}

nonisolated struct GraphChatAnswerArtifactTruncation: Hashable, Sendable {
    let isTruncated: Bool
    let omittedCount: Int?
    let omittedColumnCount: Int?
    let reasons: [GraphChatAnswerArtifactTruncationReason]

    var reason: GraphChatAnswerArtifactTruncationReason? {
        reasons.first
    }

    static let complete = GraphChatAnswerArtifactTruncation(
        isTruncated: false
    )

    init(
        isTruncated: Bool,
        omittedCount: Int? = nil,
        reason: GraphChatAnswerArtifactTruncationReason? = nil
    ) {
        self.init(
            reasons: isTruncated ? reason.map { [$0] } ?? [.unknown] : [],
            omittedCount: omittedCount,
            omittedColumnCount: nil
        )
    }

    init(
        reasons: [GraphChatAnswerArtifactTruncationReason],
        omittedCount: Int? = nil,
        omittedColumnCount: Int? = nil
    ) {
        var seen = Set<GraphChatAnswerArtifactTruncationReason>()
        let normalizedReasons = reasons.filter { seen.insert($0).inserted }
        self.isTruncated = normalizedReasons.isEmpty == false
        self.omittedCount =
            normalizedReasons.isEmpty
            ? nil
            : omittedCount.map { max(0, $0) }
        self.omittedColumnCount =
            normalizedReasons.isEmpty
            ? nil
            : omittedColumnCount.map { max(0, $0) }
        self.reasons = normalizedReasons
    }
}

nonisolated struct GraphChatAnswerArtifactResultMetadata: Hashable, Sendable {
    let totalCount: Int?
    let returnedCount: Int
    let truncation: GraphChatAnswerArtifactTruncation

    var resultCount: Int? {
        totalCount
    }

    var totalCountIsKnown: Bool {
        totalCount != nil
    }

    var isComplete: Bool {
        guard let totalCount else {
            return false
        }
        return truncation.isTruncated == false && returnedCount == totalCount
    }

    init(
        resultCount: Int?,
        returnedCount: Int,
        truncation: GraphChatAnswerArtifactTruncation = .complete
    ) {
        let normalizedReturnedCount = max(0, returnedCount)
        self.totalCount = resultCount.map { max(normalizedReturnedCount, $0) }
        self.returnedCount = normalizedReturnedCount
        self.truncation = truncation
    }
}

nonisolated struct GraphChatAnswerArtifactMetricPayload: Hashable, Sendable {
    let title: String
    let value: GraphChatAnswerArtifactValue
    let unit: String?
    let contextDescription: String?
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactListRow: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactItemID
    let primaryText: String
    let secondaryText: String?
    let navigationTargets: [GraphChatAnswerArtifactNavigationTarget]
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactResultListPayload: Hashable, Sendable {
    let title: String
    let rows: [GraphChatAnswerArtifactListRow]
    let resultMetadata: GraphChatAnswerArtifactResultMetadata
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated enum GraphChatAnswerArtifactColumnRole: String, CaseIterable, Hashable, Sendable {
    case primary
    case secondary
    case measure
    case status
    case date
    case other
}

nonisolated enum GraphChatAnswerArtifactDateFormat: String, CaseIterable, Hashable, Sendable {
    case localizedDate
    case localizedDateTime
}

nonisolated struct GraphChatAnswerArtifactValuePresentation: Hashable, Sendable {
    let missingLabel: String
    let booleanTrueLabel: String
    let booleanFalseLabel: String
    let dateFormat: GraphChatAnswerArtifactDateFormat?
    let choiceLabels: [GraphChatAnswerArtifactChoiceValue]

    init(
        missingLabel: String = "Missing",
        booleanTrueLabel: String = "Yes",
        booleanFalseLabel: String = "No",
        dateFormat: GraphChatAnswerArtifactDateFormat? = nil,
        choiceLabels: [GraphChatAnswerArtifactChoiceValue] = []
    ) {
        self.missingLabel = missingLabel
        self.booleanTrueLabel = booleanTrueLabel
        self.booleanFalseLabel = booleanFalseLabel
        self.dateFormat = dateFormat
        self.choiceLabels = choiceLabels
    }
}

nonisolated struct GraphChatAnswerArtifactTableColumn: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactItemID
    let key: String
    let title: String
    let role: GraphChatAnswerArtifactColumnRole
    let unit: String?
    let valuePresentation: GraphChatAnswerArtifactValuePresentation

    init(
        id: GraphChatAnswerArtifactItemID,
        key: String,
        title: String,
        role: GraphChatAnswerArtifactColumnRole,
        unit: String?,
        valuePresentation: GraphChatAnswerArtifactValuePresentation =
            GraphChatAnswerArtifactValuePresentation()
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.role = role
        self.unit = unit
        self.valuePresentation = valuePresentation
    }
}

nonisolated struct GraphChatAnswerArtifactTableCell: Hashable, Sendable, Identifiable {
    let columnID: GraphChatAnswerArtifactItemID
    let value: GraphChatAnswerArtifactValue
    let evidence: GraphChatAnswerArtifactEvidenceBinding?

    var id: GraphChatAnswerArtifactItemID {
        columnID
    }
}

nonisolated struct GraphChatAnswerArtifactTableRow: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactItemID
    let cells: [GraphChatAnswerArtifactTableCell]
    let navigationTarget: GraphChatAnswerArtifactNavigationTarget?
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated enum GraphChatAnswerArtifactSortDirection: String, CaseIterable, Hashable, Sendable {
    case ascending
    case descending
}

nonisolated struct GraphChatAnswerArtifactSortDescriptor: Hashable, Sendable {
    let columnID: GraphChatAnswerArtifactItemID
    let direction: GraphChatAnswerArtifactSortDirection
}

nonisolated struct GraphChatAnswerArtifactTablePayload: Hashable, Sendable {
    let title: String
    let columns: [GraphChatAnswerArtifactTableColumn]
    let rows: [GraphChatAnswerArtifactTableRow]
    let sorting: [GraphChatAnswerArtifactSortDescriptor]
    let resultMetadata: GraphChatAnswerArtifactResultMetadata
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactRankingEntry: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactItemID
    let rank: Int
    let label: String
    let value: GraphChatAnswerArtifactValue
    let share: GraphChatAnswerArtifactValue?
    let navigationTarget: GraphChatAnswerArtifactNavigationTarget?
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactRankingPayload: Hashable, Sendable {
    let title: String
    let entries: [GraphChatAnswerArtifactRankingEntry]
    let resultMetadata: GraphChatAnswerArtifactResultMetadata
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactGroupingEntry: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactItemID
    let groupKey: GraphChatAnswerArtifactValue
    let label: String
    let count: Int
    let share: GraphChatAnswerArtifactValue?
    let includedResultReferences: [GraphChatAnswerArtifactItemID]
    let navigationTarget: GraphChatAnswerArtifactNavigationTarget?
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactGroupingPayload: Hashable, Sendable {
    let title: String
    let groups: [GraphChatAnswerArtifactGroupingEntry]
    let resultMetadata: GraphChatAnswerArtifactResultMetadata
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactComparisonSubject: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactItemID
    let label: String
    let navigationTarget: GraphChatAnswerArtifactNavigationTarget?
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactComparisonFeature: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactItemID
    let key: String
    let label: String
    let unit: String?
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactComparisonValue: Hashable, Sendable, Identifiable {
    let subjectID: GraphChatAnswerArtifactItemID
    let featureID: GraphChatAnswerArtifactItemID
    let value: GraphChatAnswerArtifactValue
    let evidence: GraphChatAnswerArtifactEvidenceBinding?

    var id: String {
        "\(subjectID.rawValue.uuidString):\(featureID.rawValue.uuidString)"
    }
}

nonisolated struct GraphChatAnswerArtifactComparisonPayload: Hashable, Sendable {
    let title: String
    let subjects: [GraphChatAnswerArtifactComparisonSubject]
    let features: [GraphChatAnswerArtifactComparisonFeature]
    let values: [GraphChatAnswerArtifactComparisonValue]
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated enum GraphChatAnswerArtifactHealthFindingType: String, CaseIterable, Hashable, Sendable {
    case isolatedNodes
    case missingRequiredValues
    case inconsistentValues
    case duplicateCandidates
    case staleReferences
    case other
}

nonisolated enum GraphChatAnswerArtifactHealthSeverity: String, CaseIterable, Hashable, Sendable {
    case info
    case warning
    case critical
}

nonisolated struct GraphChatAnswerArtifactHealthFindingPayload: Hashable, Sendable {
    let findingType: GraphChatAnswerArtifactHealthFindingType
    let severity: GraphChatAnswerArtifactHealthSeverity?
    let summary: String
    let affectedElementCount: Int
    let affectedNodes: [NodeRefKey]
    let evidence: GraphChatAnswerArtifactEvidenceBinding
    let navigationTargets: [GraphChatAnswerArtifactNavigationTarget]
}

nonisolated struct GraphChatAnswerArtifactTimeInterval: Hashable, Sendable {
    let start: Date
    let end: Date?

    init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }
}

nonisolated struct GraphChatAnswerArtifactTimelineEntry: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactItemID
    let interval: GraphChatAnswerArtifactTimeInterval
    let title: String
    let value: GraphChatAnswerArtifactValue
    let resultReferences: [GraphChatAnswerArtifactItemID]
    let navigationTarget: GraphChatAnswerArtifactNavigationTarget?
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated struct GraphChatAnswerArtifactTimelinePayload: Hashable, Sendable {
    let title: String
    let entries: [GraphChatAnswerArtifactTimelineEntry]
    let resultMetadata: GraphChatAnswerArtifactResultMetadata
    let evidence: GraphChatAnswerArtifactEvidenceBinding
}

nonisolated enum GraphChatAnswerArtifactPayload: Hashable, Sendable {
    case metric(GraphChatAnswerArtifactMetricPayload)
    case resultList(GraphChatAnswerArtifactResultListPayload)
    case table(GraphChatAnswerArtifactTablePayload)
    case ranking(GraphChatAnswerArtifactRankingPayload)
    case grouping(GraphChatAnswerArtifactGroupingPayload)
    case comparison(GraphChatAnswerArtifactComparisonPayload)
    case healthFinding(GraphChatAnswerArtifactHealthFindingPayload)
    case timeline(GraphChatAnswerArtifactTimelinePayload)
}

nonisolated enum GraphChatAnswerArtifactKind: String, CaseIterable, Hashable, Sendable {
    case metric
    case resultList
    case table
    case ranking
    case grouping
    case comparison
    case healthFinding
    case timeline
}

nonisolated struct GraphChatAnswerArtifactQueryFieldSummary: Hashable, Sendable, Identifiable {
    let fieldID: UUID
    let label: String

    var id: UUID {
        fieldID
    }
}

nonisolated struct GraphChatAnswerArtifactQueryFilterSummary: Hashable, Sendable, Identifiable {
    let field: GraphChatAnswerArtifactQueryFieldSummary
    let operation: GraphQueryFilterOperator
    let operationLabel: String
    let values: [GraphChatAnswerArtifactValue]
    let valueDescription: String?

    var id: String {
        "\(field.fieldID.uuidString):\(operation.rawValue):\(valueDescription ?? "")"
    }
}

nonisolated struct GraphChatAnswerArtifactQuerySortSummary: Hashable, Sendable, Identifiable {
    let key: String
    let label: String
    let direction: GraphChatAnswerArtifactSortDirection
    let directionLabel: String

    var id: String {
        "\(key):\(direction.rawValue)"
    }
}

nonisolated enum GraphChatAnswerArtifactQueryAggregationSummary: Hashable, Sendable {
    case count(label: String)
    case minimum(field: GraphChatAnswerArtifactQueryFieldSummary, label: String)
    case maximum(field: GraphChatAnswerArtifactQueryFieldSummary, label: String)
    case groupCount(field: GraphChatAnswerArtifactQueryFieldSummary, label: String)
}

nonisolated struct GraphChatAnswerArtifactQuerySummary: Hashable, Sendable {
    let language: GraphChatResponseLanguage
    let entityID: UUID
    let entityLabel: String
    let filters: [GraphChatAnswerArtifactQueryFilterSummary]
    let grouping: GraphChatAnswerArtifactQueryFieldSummary?
    let sorting: [GraphChatAnswerArtifactQuerySortSummary]
    let projection: [GraphChatAnswerArtifactQueryFieldSummary]
    let includesNodeIdentity: Bool
    let limit: Int
    let aggregation: GraphChatAnswerArtifactQueryAggregationSummary?
    let displayText: String
}

nonisolated struct GraphChatAnswerArtifactDraft: Hashable, Sendable {
    let graphScope: GraphScope
    let title: String
    let payload: GraphChatAnswerArtifactPayload
    let evidence: GraphChatAnswerArtifactEvidenceBinding
    let navigationTargets: [GraphChatAnswerArtifactNavigationTarget]
    let querySummary: GraphChatAnswerArtifactQuerySummary?

    init(
        graphScope: GraphScope,
        title: String,
        payload: GraphChatAnswerArtifactPayload,
        evidence: GraphChatAnswerArtifactEvidenceBinding,
        navigationTargets: [GraphChatAnswerArtifactNavigationTarget] = [],
        querySummary: GraphChatAnswerArtifactQuerySummary? = nil
    ) {
        self.graphScope = graphScope
        self.title = title
        self.payload = payload
        self.evidence = evidence
        self.navigationTargets = navigationTargets
        self.querySummary = querySummary
    }

    var allNavigationTargets: [GraphChatAnswerArtifactNavigationTarget] {
        navigationTargets + payload.allNavigationTargets
    }
}

nonisolated struct GraphChatAnswerArtifact: Hashable, Sendable, Identifiable {
    let id: GraphChatAnswerArtifactID
    let sessionID: GraphChatAnswerArtifactSessionID
    let graphScope: GraphScope
    let title: String
    let payload: GraphChatAnswerArtifactPayload
    let evidence: GraphChatAnswerArtifactEvidenceBinding
    let navigationTargets: [GraphChatAnswerArtifactNavigationTarget]
    let querySummary: GraphChatAnswerArtifactQuerySummary?

    init(
        id: GraphChatAnswerArtifactID,
        sessionID: GraphChatAnswerArtifactSessionID,
        graphScope: GraphScope,
        title: String,
        payload: GraphChatAnswerArtifactPayload,
        evidence: GraphChatAnswerArtifactEvidenceBinding,
        navigationTargets: [GraphChatAnswerArtifactNavigationTarget],
        querySummary: GraphChatAnswerArtifactQuerySummary? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.graphScope = graphScope
        self.title = title
        self.payload = payload
        self.evidence = evidence
        self.navigationTargets = navigationTargets
        self.querySummary = querySummary
    }

    var kind: GraphChatAnswerArtifactKind {
        switch payload {
        case .metric:
            return .metric
        case .resultList:
            return .resultList
        case .table:
            return .table
        case .ranking:
            return .ranking
        case .grouping:
            return .grouping
        case .comparison:
            return .comparison
        case .healthFinding:
            return .healthFinding
        case .timeline:
            return .timeline
        }
    }

    var allEvidenceIDs: [GraphEvidenceID] {
        var values = evidence.evidenceIDs
        values.append(contentsOf: payload.allEvidenceIDs)
        var seen = Set<GraphEvidenceID>()
        return values.filter { seen.insert($0).inserted }
    }

    var allNavigationTargets: [GraphChatAnswerArtifactNavigationTarget] {
        navigationTargets + payload.allNavigationTargets
    }

    var workspaceNavigationTargets: [GraphChatAnswerArtifactNavigationTarget] {
        let nodes = boundedResultNodes
        guard nodes.isEmpty == false else {
            return []
        }

        var targets: [GraphChatAnswerArtifactNavigationTarget] = [
            .showResultNodes(
                graphScope: graphScope,
                title: title,
                nodes: nodes
            ),
            .highlightNodesInCanvas(graphScope: graphScope, nodes: nodes),
            .clearCanvasHighlight(graphScope: graphScope),
        ]

        if let querySummary {
            let filters = querySummary.filters.map { filter in
                GraphChatAnswerArtifactFilterValue(
                    fieldID: filter.field.fieldID,
                    fieldName: filter.field.label,
                    operationDescription: filter.operationLabel,
                    values: filter.values
                )
            }
            targets.append(
                .openResultFilter(
                    graphScope: graphScope,
                    entityID: querySummary.entityID,
                    filters: filters,
                    resultNodes: nodes
                )
            )
        }

        targets.append(.addNodesToCanvasSelection(graphScope: graphScope, nodes: nodes))
        targets.append(.replaceCanvasSelection(graphScope: graphScope, nodes: nodes))
        if nodes.count >= 2 {
            targets.append(.compareNodes(graphScope: graphScope, nodes: nodes))
        }
        return targets
    }

    private var boundedResultNodes: [NodeRefKey] {
        var seen = Set<NodeRefKey>()
        var nodes: [NodeRefKey] = []
        for target in allNavigationTargets {
            for node in target.nodeReferences where seen.insert(node).inserted {
                nodes.append(node)
                if nodes.count == GraphChatWorkspaceBudget.maximumActionNodes {
                    return nodes
                }
            }
        }
        if case .healthFinding(let payload) = payload {
            for node in payload.affectedNodes where seen.insert(node).inserted {
                nodes.append(node)
                if nodes.count == GraphChatWorkspaceBudget.maximumActionNodes {
                    return nodes
                }
            }
        }
        return nodes
    }

    var estimatedByteCount: Int {
        max(1, String(reflecting: self).utf8.count)
    }
}

nonisolated extension GraphChatAnswerArtifactPayload {
    fileprivate var allNavigationTargets: [GraphChatAnswerArtifactNavigationTarget] {
        switch self {
        case .metric:
            return []
        case .resultList(let payload):
            return payload.rows.flatMap(\.navigationTargets)
        case .table(let payload):
            return payload.rows.compactMap(\.navigationTarget)
        case .ranking(let payload):
            return payload.entries.compactMap(\.navigationTarget)
        case .grouping(let payload):
            return payload.groups.compactMap(\.navigationTarget)
        case .comparison(let payload):
            return payload.subjects.compactMap(\.navigationTarget)
        case .healthFinding(let payload):
            return payload.navigationTargets
        case .timeline(let payload):
            return payload.entries.compactMap(\.navigationTarget)
        }
    }

    fileprivate var allEvidenceIDs: [GraphEvidenceID] {
        switch self {
        case .metric(let payload):
            return payload.evidence.evidenceIDs
        case .resultList(let payload):
            return payload.evidence.evidenceIDs
                + payload.rows.flatMap { $0.evidence.evidenceIDs }
        case .table(let payload):
            return payload.evidence.evidenceIDs
                + payload.rows.flatMap { row in
                    row.evidence.evidenceIDs
                        + row.cells.flatMap { $0.evidence?.evidenceIDs ?? [] }
                }
        case .ranking(let payload):
            return payload.evidence.evidenceIDs
                + payload.entries.flatMap { $0.evidence.evidenceIDs }
        case .grouping(let payload):
            return payload.evidence.evidenceIDs
                + payload.groups.flatMap { $0.evidence.evidenceIDs }
        case .comparison(let payload):
            return payload.evidence.evidenceIDs
                + payload.subjects.flatMap { $0.evidence.evidenceIDs }
                + payload.features.flatMap { $0.evidence.evidenceIDs }
                + payload.values.flatMap { $0.evidence?.evidenceIDs ?? [] }
        case .healthFinding(let payload):
            return payload.evidence.evidenceIDs
        case .timeline(let payload):
            return payload.evidence.evidenceIDs
                + payload.entries.flatMap { $0.evidence.evidenceIDs }
        }
    }
}
