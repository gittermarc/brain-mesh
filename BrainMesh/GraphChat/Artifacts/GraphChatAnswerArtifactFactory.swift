//
//  GraphChatAnswerArtifactFactory.swift
//  BrainMesh
//
//  Deterministic adapters from revalidated read-only tool outputs to value-only artifacts.
//

import Foundation

nonisolated enum GraphChatAnswerArtifactFactory {
    static func searchResults(
        output: SearchGraphOutput,
        graphScope: GraphScope,
        requestedLimit: Int
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.hits.isEmpty == false else {
            return nil
        }
        let rows = output.hits.map { hit in
            GraphChatAnswerArtifactListRow(
                id: GraphChatAnswerArtifactItemID(rawValue: hit.evidenceID.rawValue),
                primaryText: hit.title,
                secondaryText: hit.subtitle.isEmpty ? nil : hit.subtitle,
                navigationTargets: navigationTargets(
                    for: hit.sourceReference,
                    graphScope: graphScope
                ),
                evidence: GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: [hit.evidenceID]
                )
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: output.hits.map(\.evidenceID)
        )
        let payload = GraphChatAnswerArtifactResultListPayload(
            title: "Search results for \(output.query)",
            rows: rows,
            resultMetadata: resultMetadata(
                returnedCount: rows.count,
                requestedLimit: requestedLimit,
                truncationReason: .toolLimit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: payload.title,
            payload: .resultList(payload),
            evidence: evidence,
            navigationTargets: rows.flatMap(\.navigationTargets)
        )
    }

    static func queryResult(
        _ result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext
    ) -> GraphChatAnswerArtifactDraft? {
        if let aggregation = result.aggregation {
            switch aggregation.kind {
            case .groupCount:
                return grouping(
                    aggregation: aggregation,
                    result: result,
                    plan: plan
                )
            case .count, .minimum, .maximum:
                return metric(
                    aggregation: aggregation,
                    result: result,
                    plan: plan
                )
            }
        }
        guard result.rows.isEmpty == false else {
            return nil
        }
        return table(
            result: result,
            plan: plan,
            schemaContext: schemaContext
        )
    }

    static func nodeDetails(
        output: GetNodeOutput,
        graphScope: GraphScope
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.detailValues.isEmpty == false,
              let baseEvidenceID = output.evidenceIDs.first else {
            return nil
        }
        let fieldColumnID = stableItemID("node-detail-field")
        let valueColumnID = stableItemID("node-detail-value")
        let unitColumnID = stableItemID("node-detail-unit")
        let columns = [
            GraphChatAnswerArtifactTableColumn(
                id: fieldColumnID,
                key: "field",
                title: "Field",
                role: .primary,
                unit: nil
            ),
            GraphChatAnswerArtifactTableColumn(
                id: valueColumnID,
                key: "value",
                title: "Value",
                role: .measure,
                unit: nil
            ),
            GraphChatAnswerArtifactTableColumn(
                id: unitColumnID,
                key: "unit",
                title: "Unit",
                role: .secondary,
                unit: nil
            )
        ]
        let nodeTarget = GraphChatAnswerArtifactNavigationTarget.openNode(
            graphScope: graphScope,
            node: output.node
        )
        let rows = output.detailValues.map { detail in
            let binding = GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [detail.evidenceID]
            )
            return GraphChatAnswerArtifactTableRow(
                id: GraphChatAnswerArtifactItemID(rawValue: detail.valueID),
                cells: [
                    GraphChatAnswerArtifactTableCell(
                        columnID: fieldColumnID,
                        value: .text(detail.fieldName),
                        evidence: binding
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: valueColumnID,
                        value: GraphChatAnswerArtifactValue(queryValue: detail.value),
                        evidence: binding
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: unitColumnID,
                        value: detail.unit.map(GraphChatAnswerArtifactValue.text) ?? .missing,
                        evidence: binding
                    )
                ],
                navigationTarget: nodeTarget,
                evidence: binding
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [baseEvidenceID] + output.detailValues.map(\.evidenceID)
        )
        let payload = GraphChatAnswerArtifactTablePayload(
            title: output.label,
            columns: columns,
            rows: rows,
            sorting: [],
            resultMetadata: GraphChatAnswerArtifactResultMetadata(
                resultCount: rows.count,
                returnedCount: rows.count
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: output.label,
            payload: .table(payload),
            evidence: evidence,
            navigationTargets: [
                nodeTarget,
                .focusNodeInGraph(graphScope: graphScope, node: output.node)
            ]
        )
    }

    static func neighbors(
        output: GetNeighborsOutput,
        graphScope: GraphScope,
        requestedLimit: Int
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.connections.isEmpty == false,
              let centerEvidenceID = output.evidenceIDs.first else {
            return nil
        }
        let rows = output.connections.map { connection in
            let direction = connection.direction == .incoming ? "Incoming" : "Outgoing"
            return GraphChatAnswerArtifactListRow(
                id: GraphChatAnswerArtifactItemID(rawValue: connection.id),
                primaryText: connection.neighborLabel,
                secondaryText: connection.note.map { "\(direction): \($0)" } ?? direction,
                navigationTargets: [
                    .openNode(graphScope: graphScope, node: connection.neighbor),
                    .focusNodeInGraph(graphScope: graphScope, node: connection.neighbor)
                ],
                evidence: GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: [connection.evidenceID]
                )
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [centerEvidenceID] + output.connections.map(\.evidenceID)
        )
        let payload = GraphChatAnswerArtifactResultListPayload(
            title: "Neighbors of \(output.center.label)",
            rows: rows,
            resultMetadata: resultMetadata(
                returnedCount: rows.count,
                requestedLimit: requestedLimit,
                truncationReason: .toolLimit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: payload.title,
            payload: .resultList(payload),
            evidence: evidence,
            navigationTargets: rows.flatMap(\.navigationTargets)
        )
    }

    static func statistics(
        output: GraphStatsOutput,
        graphScope: GraphScope,
        requestedHubLimit: Int
    ) -> GraphChatAnswerArtifactDraft? {
        guard let graphEvidenceID = output.evidenceIDs.first else {
            return nil
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: output.evidenceIDs
        )
        if output.hubs.isEmpty == false {
            let entries = output.hubs.enumerated().map { index, hub in
                GraphChatAnswerArtifactRankingEntry(
                    id: GraphChatAnswerArtifactItemID(rawValue: hub.node.id),
                    rank: index + 1,
                    label: hub.label,
                    value: .integer(hub.degree),
                    share: output.nodeCount > 0
                        ? .percentage(Decimal(hub.degree) / Decimal(output.nodeCount))
                        : nil,
                    navigationTarget: .openNode(
                        graphScope: graphScope,
                        node: hub.node
                    ),
                    evidence: GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: [hub.evidenceID]
                    )
                )
            }
            let payload = GraphChatAnswerArtifactRankingPayload(
                title: "Most connected nodes",
                entries: entries,
                resultMetadata: resultMetadata(
                    returnedCount: entries.count,
                    requestedLimit: requestedHubLimit,
                    truncationReason: .toolLimit
                ),
                evidence: evidence
            )
            return GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: payload.title,
                payload: .ranking(payload),
                evidence: evidence,
                navigationTargets: entries.compactMap(\.navigationTarget)
            )
        }
        if output.healthIssueCount > 0 {
            let payload = GraphChatAnswerArtifactHealthFindingPayload(
                findingType: .other,
                severity: output.healthScore < 50 ? .critical : .warning,
                summary: "The graph health scan found \(output.healthIssueCount) open items.",
                affectedElementCount: output.healthIssueCount,
                affectedNodes: [],
                evidence: evidence,
                navigationTargets: []
            )
            return GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: "Graph health",
                payload: .healthFinding(payload),
                evidence: evidence
            )
        }
        let payload = GraphChatAnswerArtifactMetricPayload(
            title: "Node count",
            value: .integer(output.nodeCount),
            unit: nil,
            contextDescription: "\(output.linkCount) links and \(output.isolatedNodeCount) isolated nodes",
            evidence: GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [graphEvidenceID]
            )
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: payload.title,
            payload: .metric(payload),
            evidence: evidence
        )
    }

    private static func metric(
        aggregation: GraphChatAggregationResult,
        result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan
    ) -> GraphChatAnswerArtifactDraft? {
        let value: GraphChatAnswerArtifactValue
        switch aggregation.kind {
        case .count:
            guard let count = aggregation.count else {
                return nil
            }
            value = .integer(count)
        case .minimum, .maximum:
            guard let aggregationValue = aggregation.value else {
                return nil
            }
            value = GraphChatAnswerArtifactValue(queryValue: aggregationValue)
        case .groupCount:
            return nil
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: aggregation.evidenceIDs
        )
        guard evidence.evidenceIDs.isEmpty == false else {
            return nil
        }
        let operationTitle: String
        switch aggregation.kind {
        case .count:
            operationTitle = "Count"
        case .minimum:
            operationTitle = "Minimum"
        case .maximum:
            operationTitle = "Maximum"
        case .groupCount:
            operationTitle = "Grouped count"
        }
        let title = aggregation.fieldName.map { "\(operationTitle): \($0)" } ?? operationTitle
        let payload = GraphChatAnswerArtifactMetricPayload(
            title: title,
            value: value,
            unit: nil,
            contextDescription: result.appliedFilters.isEmpty
                ? nil
                : "Based on \(result.appliedFilters.count) validated filters",
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .metric(payload),
            evidence: evidence
        )
    }

    private static func grouping(
        aggregation: GraphChatAggregationResult,
        result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan
    ) -> GraphChatAnswerArtifactDraft? {
        guard aggregation.groups.isEmpty == false else {
            return nil
        }
        let totalCount = aggregation.groups.reduce(0) { $0 + $1.count }
        let groups = aggregation.groups.enumerated().map { index, group in
            let value = GraphChatAnswerArtifactValue(queryValue: group.value)
            return GraphChatAnswerArtifactGroupingEntry(
                id: stableItemID("group:\(index):\(GraphChatQueryValueFormatting.stableKey(group.value))"),
                groupKey: value,
                label: readableLabel(for: value),
                count: group.count,
                share: totalCount > 0
                    ? .percentage(Decimal(group.count) / Decimal(totalCount))
                    : nil,
                includedResultReferences: [],
                navigationTarget: nil,
                evidence: GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: group.evidenceIDs
                )
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: aggregation.evidenceIDs
                + groups.flatMap { $0.evidence.evidenceIDs }
        )
        let title = aggregation.fieldName.map { "Grouped by \($0)" } ?? "Grouped results"
        let payload = GraphChatAnswerArtifactGroupingPayload(
            title: title,
            groups: groups,
            resultMetadata: resultMetadata(
                returnedCount: groups.count,
                requestedLimit: plan.limit,
                truncationReason: .queryLimit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .grouping(payload),
            evidence: evidence
        )
    }

    private static func table(
        result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext
    ) -> GraphChatAnswerArtifactDraft {
        let primaryColumnID = stableItemID("query-primary:\(plan.entityID.uuidString)")
        let fieldIDs = orderedFieldIDs(from: result.rows)
        var columns = [
            GraphChatAnswerArtifactTableColumn(
                id: primaryColumnID,
                key: "node",
                title: "Name",
                role: .primary,
                unit: nil
            )
        ]
        columns.append(contentsOf: fieldIDs.map { fieldID in
            let resolution = schemaContext.aliases.fieldsByAlias.values.first {
                $0.fieldID == fieldID
            }
            return GraphChatAnswerArtifactTableColumn(
                id: GraphChatAnswerArtifactItemID(rawValue: fieldID),
                key: fieldID.uuidString,
                title: resolution?.name ?? fieldID.uuidString,
                role: columnRole(for: resolution?.type),
                unit: resolution?.unit
            )
        })
        let rows = result.rows.map { row in
            let cellsByFieldID = Dictionary(uniqueKeysWithValues: row.cells.map { ($0.fieldID, $0) })
            var cells = [
                GraphChatAnswerArtifactTableCell(
                    columnID: primaryColumnID,
                    value: .text(row.label),
                    evidence: GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: row.evidenceIDs
                    )
                )
            ]
            cells.append(contentsOf: fieldIDs.map { fieldID in
                guard let source = cellsByFieldID[fieldID] else {
                    return GraphChatAnswerArtifactTableCell(
                        columnID: GraphChatAnswerArtifactItemID(rawValue: fieldID),
                        value: .missing,
                        evidence: nil
                    )
                }
                return GraphChatAnswerArtifactTableCell(
                    columnID: GraphChatAnswerArtifactItemID(rawValue: fieldID),
                    value: GraphChatAnswerArtifactValue(queryValue: source.value),
                    evidence: GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: [source.evidenceID]
                    )
                )
            })
            return GraphChatAnswerArtifactTableRow(
                id: GraphChatAnswerArtifactItemID(rawValue: row.node.id),
                cells: cells,
                navigationTarget: .openNode(
                    graphScope: plan.graphScope,
                    node: row.node
                ),
                evidence: GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: row.evidenceIDs
                )
            )
        }
        let sorting = plan.sorting.compactMap { sort -> GraphChatAnswerArtifactSortDescriptor? in
            let columnID: GraphChatAnswerArtifactItemID
            switch sort.key {
            case .nodeName:
                columnID = primaryColumnID
            case .field(let fieldID):
                guard fieldIDs.contains(fieldID) else {
                    return nil
                }
                columnID = GraphChatAnswerArtifactItemID(rawValue: fieldID)
            }
            return GraphChatAnswerArtifactSortDescriptor(
                columnID: columnID,
                direction: sort.direction == .ascending ? .ascending : .descending
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: result.evidence.map(\.id)
        )
        let payload = GraphChatAnswerArtifactTablePayload(
            title: "Query results",
            columns: columns,
            rows: rows,
            sorting: sorting,
            resultMetadata: resultMetadata(
                returnedCount: rows.count,
                requestedLimit: plan.limit,
                truncationReason: .queryLimit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: payload.title,
            payload: .table(payload),
            evidence: evidence,
            navigationTargets: rows.compactMap(\.navigationTarget)
        )
    }

    private static func orderedFieldIDs(
        from rows: [GraphChatQueryResultRow]
    ) -> [UUID] {
        var seen = Set<UUID>()
        return rows.flatMap(\.cells).compactMap { cell in
            seen.insert(cell.fieldID).inserted ? cell.fieldID : nil
        }
    }

    private static func resultMetadata(
        returnedCount: Int,
        requestedLimit: Int,
        truncationReason: GraphChatAnswerArtifactTruncationReason
    ) -> GraphChatAnswerArtifactResultMetadata {
        let isTruncated = requestedLimit > 0 && returnedCount >= requestedLimit
        return GraphChatAnswerArtifactResultMetadata(
            resultCount: returnedCount,
            returnedCount: returnedCount,
            truncation: GraphChatAnswerArtifactTruncation(
                isTruncated: isTruncated,
                reason: isTruncated ? truncationReason : nil
            )
        )
    }

    private static func navigationTargets(
        for reference: GraphSourceReference,
        graphScope: GraphScope
    ) -> [GraphChatAnswerArtifactNavigationTarget] {
        guard reference.graphID == graphScope.graphID else {
            return []
        }
        let node: NodeRefKey?
        if let sourceNode = reference.node?.nodeKey {
            node = sourceNode
        } else if let owner = reference.owner?.nodeKey {
            node = owner
        } else {
            switch reference.sourceKind {
            case .entity:
                node = NodeRefKey(kind: .entity, id: reference.sourceID)
            case .attribute:
                node = NodeRefKey(kind: .attribute, id: reference.sourceID)
            case .graph, .detailField, .detailValue, .link, .attachment:
                node = nil
            }
        }
        guard let node else {
            return []
        }
        return [
            .openNode(graphScope: graphScope, node: node),
            .focusNodeInGraph(graphScope: graphScope, node: node)
        ]
    }

    private static func columnRole(
        for type: DetailFieldType?
    ) -> GraphChatAnswerArtifactColumnRole {
        switch type {
        case .date:
            return .date
        case .toggle, .singleChoice:
            return .status
        case .numberInt, .numberDouble:
            return .measure
        case .singleLineText, .multiLineText:
            return .secondary
        case nil:
            return .other
        }
    }

    private static func readableLabel(
        for value: GraphChatAnswerArtifactValue
    ) -> String {
        switch value {
        case .text(let value):
            return value
        case .integer(let value):
            return String(value)
        case .decimal(let value):
            return NSDecimalNumber(decimal: value).stringValue
        case .boolean(let value):
            return value ? "True" : "False"
        case .date(let value), .dateTime(let value):
            return String(value.timeIntervalSinceReferenceDate)
        case .duration(let value):
            return String(value)
        case .percentage(let value):
            return NSDecimalNumber(decimal: value).stringValue
        case .choice(let value):
            return value.label
        case .missing:
            return "Missing"
        }
    }

    private static func stableItemID(_ key: String) -> GraphChatAnswerArtifactItemID {
        GraphChatAnswerArtifactItemID(
            rawValue: GraphEvidenceStableIdentity.deterministicUUID(for: "answer-artifact:\(key)")
        )
    }
}
