//
//  GraphChatAnswerArtifactFactory+QueryArtifacts.swift
//  BrainMesh
//
//  Deterministic query metric, grouping, list, table, and timeline artifacts.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func metric(
        aggregation: GraphChatAggregationResult,
        result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage,
        querySummary: GraphChatAnswerArtifactQuerySummary
    ) -> GraphChatAnswerArtifactDraft? {
        let strings = Strings(language)
        let fields = fieldInfoByID(schemaContext)
        let value: GraphChatAnswerArtifactValue
        let title: String
        let unit: String?
        switch aggregation.kind {
        case .count:
            guard let count = aggregation.count else {
                return nil
            }
            value = .integer(count)
            title = strings.countFor(querySummary.entityLabel)
            unit = nil
        case .minimum:
            guard let source = aggregation.value else {
                return nil
            }
            let field = aggregation.fieldID.flatMap { fields[$0] }
            value = artifactValue(source, field: field)
            title = strings.minimumFor(aggregation.fieldName ?? field?.name ?? strings.value)
            unit = field?.unit
        case .maximum:
            guard let source = aggregation.value else {
                return nil
            }
            let field = aggregation.fieldID.flatMap { fields[$0] }
            value = artifactValue(source, field: field)
            title = strings.maximumFor(aggregation.fieldName ?? field?.name ?? strings.value)
            unit = field?.unit
        case .groupCount:
            return nil
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: aggregation.evidenceIDs + result.evidence.map(\.id)
        )
        let payload = GraphChatAnswerArtifactMetricPayload(
            title: title,
            value: value,
            unit: unit,
            contextDescription: querySummary.displayText,
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .metric(payload),
            evidence: evidence,
            querySummary: querySummary
        )
    }

    static func grouping(
        aggregation: GraphChatAggregationResult,
        result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage,
        budget: GraphChatAnswerArtifactFactoryBudget,
        querySummary: GraphChatAnswerArtifactQuerySummary
    ) -> GraphChatAnswerArtifactDraft? {
        guard aggregation.groups.isEmpty == false else {
            return nil
        }
        let strings = Strings(language)
        let fields = fieldInfoByID(schemaContext)
        let field = aggregation.fieldID.flatMap { fields[$0] }
        let includedGroups = Array(aggregation.groups.prefix(budget.maximumRows))
        let itemCount = aggregation.count
            ?? aggregation.groups.reduce(0) { $0 + $1.count }
        let groups = includedGroups.enumerated().map { index, group in
            let value = artifactValue(group.value, field: field)
            return GraphChatAnswerArtifactGroupingEntry(
                id: stableItemID(
                    "group:\(index):\(GraphChatQueryValueFormatting.stableKey(group.value))"
                ),
                groupKey: value,
                label: readableLabel(value, strings: strings),
                count: group.count,
                share: itemCount > 0
                    ? .percentage(Decimal(group.count) / Decimal(itemCount))
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
        let title = strings.groupedBy(aggregation.fieldName ?? field?.name ?? strings.value)
        let payload = GraphChatAnswerArtifactGroupingPayload(
            title: title,
            groups: groups,
            resultMetadata: resultMetadata(
                sourceWindow: result.resultWindow,
                includedCount: groups.count,
                sourceReason: .queryLimit,
                fallbackLimit: plan.limit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .grouping(payload),
            evidence: evidence,
            querySummary: querySummary
        )
    }

    static func resultList(
        result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage,
        budget: GraphChatAnswerArtifactFactoryBudget,
        querySummary: GraphChatAnswerArtifactQuerySummary
    ) -> GraphChatAnswerArtifactDraft {
        let strings = Strings(language)
        let fields = fieldInfoByID(schemaContext)
        let fieldID = projectedFieldIDs(plan).first
        let field = fieldID.flatMap { fields[$0] }
        let includedRows = Array(result.rows.prefix(budget.maximumRows))
        let rows = includedRows.map { row in
            let cell = fieldID.flatMap { selectedFieldID in
                row.cells.first { $0.fieldID == selectedFieldID }
            }
            let secondary: String?
            if let cell {
                secondary = "\(cell.fieldName): \(readableLabel(artifactValue(cell.value, field: field), strings: strings))"
            } else {
                secondary = nil
            }
            return GraphChatAnswerArtifactListRow(
                id: GraphChatAnswerArtifactItemID(rawValue: row.node.id),
                primaryText: row.label,
                secondaryText: secondary,
                navigationTargets: [
                    .openNode(graphScope: plan.graphScope, node: row.node),
                    .focusNodeInGraph(graphScope: plan.graphScope, node: row.node)
                ],
                evidence: GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: row.evidenceIDs
                )
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: result.evidence.map(\.id)
        )
        let title = strings.queryResults
        let payload = GraphChatAnswerArtifactResultListPayload(
            title: title,
            rows: rows,
            resultMetadata: resultMetadata(
                sourceWindow: result.resultWindow,
                includedCount: rows.count,
                sourceReason: .queryLimit,
                fallbackLimit: plan.limit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .resultList(payload),
            evidence: evidence,
            navigationTargets: rows.flatMap(\.navigationTargets),
            querySummary: querySummary
        )
    }

    static func table(
        result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage,
        budget: GraphChatAnswerArtifactFactoryBudget,
        querySummary: GraphChatAnswerArtifactQuerySummary
    ) -> GraphChatAnswerArtifactDraft {
        let strings = Strings(language)
        let fields = fieldInfoByID(schemaContext)
        let primaryColumnID = stableItemID("query-primary:\(plan.entityID.uuidString)")
        let maximumFieldColumns = max(1, budget.maximumColumns - 1)
        let fieldIDs = Array(projectedFieldIDs(plan).prefix(maximumFieldColumns))
        var columns = [
            GraphChatAnswerArtifactTableColumn(
                id: primaryColumnID,
                key: "node",
                title: strings.name,
                role: .primary,
                unit: nil,
                valuePresentation: strings.presentation()
            )
        ]
        columns.append(contentsOf: fieldIDs.map { fieldID in
            let field = fields[fieldID]
            return GraphChatAnswerArtifactTableColumn(
                id: GraphChatAnswerArtifactItemID(rawValue: fieldID),
                key: fieldID.uuidString,
                title: field?.name ?? fieldID.uuidString,
                role: columnRole(for: field?.type),
                unit: field?.unit,
                valuePresentation: strings.presentation(for: field)
            )
        })
        let includedRows = Array(result.rows.prefix(budget.maximumRows))
        let rows = includedRows.map { row in
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
                    value: artifactValue(source.value, field: fields[fieldID]),
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
                direction: sort.direction.artifactDirection
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: result.evidence.map(\.id)
        )
        let title = strings.queryResults
        let metadata = resultMetadata(
            sourceWindow: result.resultWindow,
            includedCount: rows.count,
            sourceReason: .queryLimit,
            fallbackLimit: plan.limit,
            forceUILimit: projectedFieldIDs(plan).count > maximumFieldColumns,
            omittedColumnCount: max(
                0,
                projectedFieldIDs(plan).count - maximumFieldColumns
            )
        )
        let payload = GraphChatAnswerArtifactTablePayload(
            title: title,
            columns: columns,
            rows: rows,
            sorting: sorting,
            resultMetadata: metadata,
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .table(payload),
            evidence: evidence,
            navigationTargets: rows.compactMap(\.navigationTarget),
            querySummary: querySummary
        )
    }

    static func timeline(
        result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage,
        budget: GraphChatAnswerArtifactFactoryBudget,
        querySummary: GraphChatAnswerArtifactQuerySummary
    ) -> GraphChatAnswerArtifactDraft? {
        guard let dateSort = plan.sorting.first,
              case .field(let dateFieldID) = dateSort.key,
              projectedFieldIDs(plan) == [dateFieldID],
              fieldInfoByID(schemaContext)[dateFieldID]?.type == .date else {
            return nil
        }
        let strings = Strings(language)
        let fields = fieldInfoByID(schemaContext)
        let includedRows = Array(result.rows.prefix(budget.maximumRows))
        let entries = includedRows.compactMap { row -> GraphChatAnswerArtifactTimelineEntry? in
            guard let dateCell = row.cells.first(where: { $0.fieldID == dateFieldID }),
                  case .date(let date) = dateCell.value else {
                return nil
            }
            let binding = GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: row.evidenceIDs)
            return GraphChatAnswerArtifactTimelineEntry(
                id: GraphChatAnswerArtifactItemID(rawValue: row.node.id),
                interval: GraphChatAnswerArtifactTimeInterval(start: date),
                title: row.label,
                value: artifactValue(dateCell.value, field: fields[dateFieldID]),
                resultReferences: [GraphChatAnswerArtifactItemID(rawValue: row.node.id)],
                navigationTarget: .openNode(graphScope: plan.graphScope, node: row.node),
                evidence: binding
            )
        }
        guard entries.isEmpty == false,
              entries.count == includedRows.count else {
            return nil
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: result.evidence.map(\.id)
        )
        let title = strings.timeline
        let payload = GraphChatAnswerArtifactTimelinePayload(
            title: title,
            entries: entries,
            resultMetadata: resultMetadata(
                sourceWindow: result.resultWindow,
                includedCount: entries.count,
                sourceReason: .queryLimit,
                fallbackLimit: plan.limit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload: .timeline(payload),
            evidence: evidence,
            navigationTargets: entries.compactMap(\.navigationTarget),
            querySummary: querySummary
        )
    }

}

nonisolated extension GraphQuerySortDirection {
    var artifactDirection: GraphChatAnswerArtifactSortDirection {
        self == .ascending ? .ascending : .descending
    }
}
