//
//  GraphChatAnswerArtifactFactory.swift
//  BrainMesh
//
//  Deterministic adapters from revalidated read-only tool outputs to value-only artifacts.
//

import Foundation

nonisolated struct GraphChatAnswerArtifactFactoryBudget: Hashable, Sendable {
    let maximumRows: Int
    let maximumColumns: Int

    static let `default` = GraphChatAnswerArtifactFactoryBudget(
        maximumRows: 50,
        maximumColumns: 12
    )

    init(maximumRows: Int, maximumColumns: Int) {
        precondition(maximumRows > 0)
        precondition(maximumColumns > 1)
        self.maximumRows = maximumRows
        self.maximumColumns = maximumColumns
    }
}

nonisolated enum GraphChatAnswerArtifactFactory {
    static func schemaOverview(
        output: DescribeGraphSchemaOutput,
        schemaContext: GraphSchemaContext,
        evidenceIDs: [GraphEvidenceID],
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.snapshot.entities.isEmpty == false,
              evidenceIDs.isEmpty == false else {
            return nil
        }
        let strings = Strings(language)
        let entityColumnID = stableItemID("schema-entity")
        let attributeCountColumnID = stableItemID("schema-attribute-count")
        let fieldsColumnID = stableItemID("schema-fields")
        let columns = [
            GraphChatAnswerArtifactTableColumn(
                id: entityColumnID,
                key: "entity",
                title: strings.entity,
                role: .primary,
                unit: nil,
                valuePresentation: strings.presentation()
            ),
            GraphChatAnswerArtifactTableColumn(
                id: attributeCountColumnID,
                key: "attributeCount",
                title: strings.entries,
                role: .measure,
                unit: nil,
                valuePresentation: strings.presentation()
            ),
            GraphChatAnswerArtifactTableColumn(
                id: fieldsColumnID,
                key: "fields",
                title: strings.fields,
                role: .secondary,
                unit: nil,
                valuePresentation: strings.presentation()
            )
        ]
        let includedEntities = Array(output.snapshot.entities.prefix(budget.maximumRows))
        let graphEvidence = GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: evidenceIDs)
        let rows = includedEntities.map { entity in
            let resolution = schemaContext.aliases.entity(for: entity.alias)
            let node = resolution.map {
                NodeRefKey(kind: .entity, id: $0.entityID)
            }
            let navigationTarget = node.map {
                GraphChatAnswerArtifactNavigationTarget.openNode(
                    graphScope: schemaContext.graphScope,
                    node: $0
                )
            }
            let fieldDescription = entity.fields.map { field in
                var value = "\(field.name) [\(localizedFieldType(field.type, language: language))]"
                if let unit = field.unit, unit.isEmpty == false {
                    value += " (\(unit))"
                }
                return value
            }.joined(separator: ", ")
            return GraphChatAnswerArtifactTableRow(
                id: resolution.map {
                    GraphChatAnswerArtifactItemID(rawValue: $0.entityID)
                } ?? stableItemID("schema:\(entity.alias.rawValue)"),
                cells: [
                    GraphChatAnswerArtifactTableCell(
                        columnID: entityColumnID,
                        value: .text(entity.name),
                        evidence: graphEvidence
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: attributeCountColumnID,
                        value: .integer(entity.attributeCount),
                        evidence: graphEvidence
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: fieldsColumnID,
                        value: fieldDescription.isEmpty ? .missing : .text(fieldDescription),
                        evidence: graphEvidence
                    )
                ],
                navigationTarget: navigationTarget,
                evidence: graphEvidence
            )
        }
        let sourceWindow = GraphChatResultWindow(
            totalCount: output.snapshot.truncation.sourceEntityCount,
            returnedCount: output.snapshot.entities.count,
            limit: nil,
            limitReached: output.snapshot.truncation.sourceEntityCount
                > output.snapshot.truncation.includedEntityCount,
            limitSource: .source
        )
        let title = strings.schemaOverview(output.snapshot.graphName)
        let payload = GraphChatAnswerArtifactTablePayload(
            title: title,
            columns: columns,
            rows: rows,
            sorting: [],
            resultMetadata: resultMetadata(
                sourceWindow: sourceWindow,
                includedCount: rows.count,
                sourceReason: .sourceLimited
            ),
            evidence: graphEvidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: schemaContext.graphScope,
            title: title,
            payload: .table(payload),
            evidence: graphEvidence,
            navigationTargets: rows.compactMap(\.navigationTarget)
        )
    }

    static func searchResults(
        output: SearchGraphOutput,
        graphScope: GraphScope,
        requestedLimit: Int,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.hits.isEmpty == false else {
            return nil
        }
        let strings = Strings(language)
        let includedHits = Array(output.hits.prefix(budget.maximumRows))
        let rows = includedHits.map { hit in
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
        let title = strings.searchResults(output.query)
        let payload = GraphChatAnswerArtifactResultListPayload(
            title: title,
            rows: rows,
            resultMetadata: resultMetadata(
                sourceWindow: output.resultWindow,
                includedCount: rows.count,
                sourceReason: .toolLimit,
                fallbackLimit: requestedLimit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: title,
            payload: .resultList(payload),
            evidence: evidence,
            navigationTargets: rows.flatMap(\.navigationTargets)
        )
    }

    static func queryResult(
        _ result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        let summary = querySummary(
            plan: plan,
            schemaContext: schemaContext,
            language: language
        )
        if let aggregation = result.aggregation {
            switch aggregation.kind {
            case .groupCount:
                return grouping(
                    aggregation: aggregation,
                    result: result,
                    plan: plan,
                    schemaContext: schemaContext,
                    language: language,
                    budget: budget,
                    querySummary: summary
                )
            case .count, .minimum, .maximum:
                return metric(
                    aggregation: aggregation,
                    result: result,
                    plan: plan,
                    schemaContext: schemaContext,
                    language: language,
                    querySummary: summary
                )
            }
        }
        guard result.rows.isEmpty == false else {
            return nil
        }
        if let timeline = timeline(
            result: result,
            plan: plan,
            schemaContext: schemaContext,
            language: language,
            budget: budget,
            querySummary: summary
        ) {
            return timeline
        }
        let fieldIDs = projectedFieldIDs(plan)
        if fieldIDs.count <= 1 {
            return resultList(
                result: result,
                plan: plan,
                schemaContext: schemaContext,
                language: language,
                budget: budget,
                querySummary: summary
            )
        }
        return table(
            result: result,
            plan: plan,
            schemaContext: schemaContext,
            language: language,
            budget: budget,
            querySummary: summary
        )
    }

    static func nodeDetails(
        output: GetNodeOutput,
        graphScope: GraphScope,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.detailValues.isEmpty == false,
              let baseEvidenceID = output.evidenceIDs.first else {
            return nil
        }
        let strings = Strings(language)
        let fieldColumnID = stableItemID("node-detail-field")
        let valueColumnID = stableItemID("node-detail-value")
        let unitColumnID = stableItemID("node-detail-unit")
        let columns = [
            GraphChatAnswerArtifactTableColumn(
                id: fieldColumnID,
                key: "field",
                title: strings.field,
                role: .primary,
                unit: nil,
                valuePresentation: strings.presentation()
            ),
            GraphChatAnswerArtifactTableColumn(
                id: valueColumnID,
                key: "value",
                title: strings.value,
                role: .measure,
                unit: nil,
                valuePresentation: strings.presentation()
            ),
            GraphChatAnswerArtifactTableColumn(
                id: unitColumnID,
                key: "unit",
                title: strings.unit,
                role: .secondary,
                unit: nil,
                valuePresentation: strings.presentation()
            )
        ]
        let nodeTarget = GraphChatAnswerArtifactNavigationTarget.openNode(
            graphScope: graphScope,
            node: output.node
        )
        let includedValues = Array(output.detailValues.prefix(budget.maximumRows))
        let rows = includedValues.map { detail in
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
                        value: artifactValue(
                            detail.value,
                            field: FieldInfo(
                                id: detail.fieldID,
                                name: detail.fieldName,
                                type: detail.fieldType,
                                unit: detail.unit,
                                choiceOptions: []
                            )
                        ),
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
            resultMetadata: resultMetadata(
                sourceWindow: output.detailValueWindow,
                includedCount: rows.count,
                sourceReason: .toolLimit
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
        requestedLimit: Int,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.connections.isEmpty == false,
              let centerEvidenceID = output.evidenceIDs.first else {
            return nil
        }
        let strings = Strings(language)
        let includedConnections = Array(output.connections.prefix(budget.maximumRows))
        let rows = includedConnections.map { connection in
            let direction = connection.direction == .incoming
                ? strings.incoming
                : strings.outgoing
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
        let title = strings.neighbors(output.center.label)
        let payload = GraphChatAnswerArtifactResultListPayload(
            title: title,
            rows: rows,
            resultMetadata: resultMetadata(
                sourceWindow: output.resultWindow,
                includedCount: rows.count,
                sourceReason: .toolLimit,
                fallbackLimit: requestedLimit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: title,
            payload: .resultList(payload),
            evidence: evidence,
            navigationTargets: rows.flatMap(\.navigationTargets)
        )
    }

    static func statistics(
        output: GraphStatsOutput,
        graphScope: GraphScope,
        requestedHubLimit: Int,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> [GraphChatAnswerArtifactDraft] {
        guard let graphEvidenceID = output.evidenceIDs.first else {
            return []
        }
        let strings = Strings(language)
        let graphEvidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [graphEvidenceID]
        )
        var drafts: [GraphChatAnswerArtifactDraft] = []

        let scoreTitle = strings.graphHealthScore
        drafts.append(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: scoreTitle,
                payload: .metric(
                    GraphChatAnswerArtifactMetricPayload(
                        title: scoreTitle,
                        value: .integer(output.healthScore),
                        unit: strings.points,
                        contextDescription: strings.graphOverviewContext(
                            nodeCount: output.nodeCount,
                            linkCount: output.linkCount
                        ),
                        evidence: graphEvidence
                    )
                ),
                evidence: graphEvidence
            )
        )

        if output.hubs.isEmpty == false {
            let includedHubs = Array(output.hubs.prefix(budget.maximumRows))
            let entries = includedHubs.enumerated().map { index, hub in
                GraphChatAnswerArtifactRankingEntry(
                    id: GraphChatAnswerArtifactItemID(rawValue: hub.node.id),
                    rank: index + 1,
                    label: hub.label,
                    value: .integer(hub.degree),
                    share: output.linkCount > 0
                        ? .percentage(Decimal(hub.degree) / Decimal(max(1, output.linkCount * 2)))
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
            let evidence = GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [graphEvidenceID] + output.hubs.map(\.evidenceID)
            )
            let title = strings.mostConnectedNodes
            let payload = GraphChatAnswerArtifactRankingPayload(
                title: title,
                entries: entries,
                resultMetadata: resultMetadata(
                    sourceWindow: output.hubWindow,
                    includedCount: entries.count,
                    sourceReason: .toolLimit,
                    fallbackLimit: requestedHubLimit
                ),
                evidence: evidence
            )
            drafts.append(
                GraphChatAnswerArtifactDraft(
                    graphScope: graphScope,
                    title: title,
                    payload: .ranking(payload),
                    evidence: evidence,
                    navigationTargets: entries.compactMap(\.navigationTarget)
                )
            )
        }

        if output.healthIssueCount > 0 || output.isolatedNodeCount > 0 {
            let findingType: GraphChatAnswerArtifactHealthFindingType = output.isolatedNodeCount > 0
                ? .isolatedNodes
                : .other
            let affectedCount = output.isolatedNodeCount > 0
                ? output.isolatedNodeCount
                : output.healthIssueCount
            let severity: GraphChatAnswerArtifactHealthSeverity = output.healthScore < 50
                ? .critical
                : .warning
            let title = strings.graphHealthFinding
            drafts.append(
                GraphChatAnswerArtifactDraft(
                    graphScope: graphScope,
                    title: title,
                    payload: .healthFinding(
                        GraphChatAnswerArtifactHealthFindingPayload(
                            findingType: findingType,
                            severity: severity,
                            summary: strings.healthFindingSummary(
                                isolatedNodeCount: output.isolatedNodeCount,
                                issueCount: output.healthIssueCount
                            ),
                            affectedElementCount: affectedCount,
                            affectedNodes: [],
                            evidence: graphEvidence,
                            navigationTargets: []
                        )
                    ),
                    evidence: graphEvidence
                )
            )
        }
        return drafts
    }

    static func querySummary(
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage
    ) -> GraphChatAnswerArtifactQuerySummary {
        let strings = Strings(language)
        let entityLabel = entityName(plan.entityID, schemaContext: schemaContext)
            ?? plan.entityID.uuidString
        let fields = fieldInfoByID(schemaContext)
        let filterSummaries = plan.filters.map { filter in
            let field = fields[filter.fieldID] ?? FieldInfo(
                id: filter.fieldID,
                name: filter.fieldID.uuidString,
                type: filter.fieldType,
                unit: nil,
                choiceOptions: []
            )
            let values = artifactValues(filter.value, field: field)
            return GraphChatAnswerArtifactQueryFilterSummary(
                field: field.summary,
                operation: filter.operation,
                operationLabel: strings.operation(filter.operation),
                values: values,
                valueDescription: values.isEmpty
                    ? nil
                    : values.map { readableLabel($0, strings: strings) }.joined(separator: ", ")
            )
        }
        let projectionFields = projectedFieldIDs(plan).compactMap { fieldID in
            fields[fieldID]?.summary
        }
        let sorting = plan.sorting.map { sort in
            switch sort.key {
            case .nodeName:
                return GraphChatAnswerArtifactQuerySortSummary(
                    key: "nodeName",
                    label: strings.name,
                    direction: sort.direction.artifactDirection,
                    directionLabel: strings.sortDirection(sort.direction)
                )
            case .field(let fieldID):
                return GraphChatAnswerArtifactQuerySortSummary(
                    key: fieldID.uuidString,
                    label: fields[fieldID]?.name ?? fieldID.uuidString,
                    direction: sort.direction.artifactDirection,
                    directionLabel: strings.sortDirection(sort.direction)
                )
            }
        }
        let aggregation: GraphChatAnswerArtifactQueryAggregationSummary?
        let grouping: GraphChatAnswerArtifactQueryFieldSummary?
        switch plan.aggregation {
        case .count:
            aggregation = .count(label: strings.count)
            grouping = nil
        case .minimum(let fieldID):
            let field = fields[fieldID]?.summary
                ?? GraphChatAnswerArtifactQueryFieldSummary(fieldID: fieldID, label: fieldID.uuidString)
            aggregation = .minimum(field: field, label: strings.minimum)
            grouping = nil
        case .maximum(let fieldID):
            let field = fields[fieldID]?.summary
                ?? GraphChatAnswerArtifactQueryFieldSummary(fieldID: fieldID, label: fieldID.uuidString)
            aggregation = .maximum(field: field, label: strings.maximum)
            grouping = nil
        case .groupCount(let fieldID):
            let field = fields[fieldID]?.summary
                ?? GraphChatAnswerArtifactQueryFieldSummary(fieldID: fieldID, label: fieldID.uuidString)
            aggregation = .groupCount(field: field, label: strings.groupCount)
            grouping = field
        case nil:
            aggregation = nil
            grouping = nil
        }
        let includesNodeIdentity = plan.projection.contains { projection in
            if case .nodeIdentity = projection {
                return true
            }
            return false
        }
        let displayText = querySummaryText(
            entityLabel: entityLabel,
            filters: filterSummaries,
            grouping: grouping,
            sorting: sorting,
            projection: projectionFields,
            includesNodeIdentity: includesNodeIdentity,
            limit: plan.limit,
            aggregation: aggregation,
            strings: strings
        )
        return GraphChatAnswerArtifactQuerySummary(
            language: language,
            entityID: plan.entityID,
            entityLabel: entityLabel,
            filters: filterSummaries,
            grouping: grouping,
            sorting: sorting,
            projection: projectionFields,
            includesNodeIdentity: includesNodeIdentity,
            limit: plan.limit,
            aggregation: aggregation,
            displayText: displayText
        )
    }

    private static func metric(
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

    private static func grouping(
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

    private static func resultList(
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

    private static func table(
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

    private static func timeline(
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

    private static func resultMetadata(
        sourceWindow: GraphChatResultWindow,
        includedCount: Int,
        sourceReason: GraphChatAnswerArtifactTruncationReason,
        fallbackLimit: Int? = nil,
        forceUILimit: Bool = false,
        omittedColumnCount: Int? = nil
    ) -> GraphChatAnswerArtifactResultMetadata {
        let normalizedIncludedCount = max(0, includedCount)
        var reasons: [GraphChatAnswerArtifactTruncationReason] = []
        if sourceWindow.limitReached {
            if sourceWindow.limitSources.isEmpty {
                reasons.append(sourceReason)
            } else {
                reasons.append(
                    contentsOf: sourceWindow.limitSources.map {
                        truncationReason(for: $0, fallback: sourceReason)
                    }
                )
            }
        } else if sourceWindow.limit == nil,
                  let fallbackLimit,
                  fallbackLimit > 0,
                  sourceWindow.returnedCount > fallbackLimit {
            reasons.append(sourceReason)
        }
        if normalizedIncludedCount < sourceWindow.returnedCount || forceUILimit {
            reasons.append(.uiLimit)
        }
        let omittedCount: Int?
        if let totalCount = sourceWindow.totalCount {
            omittedCount = max(0, totalCount - normalizedIncludedCount)
        } else if reasons == [.uiLimit] {
            omittedCount = max(0, sourceWindow.returnedCount - normalizedIncludedCount)
        } else {
            omittedCount = nil
        }
        return GraphChatAnswerArtifactResultMetadata(
            resultCount: sourceWindow.totalCount,
            returnedCount: normalizedIncludedCount,
            truncation: GraphChatAnswerArtifactTruncation(
                reasons: reasons,
                omittedCount: omittedCount,
                omittedColumnCount: omittedColumnCount
            )
        )
    }

    private static func truncationReason(
        for source: GraphChatResultLimitSource?,
        fallback: GraphChatAnswerArtifactTruncationReason
    ) -> GraphChatAnswerArtifactTruncationReason {
        switch source {
        case .tool:
            return .toolLimit
        case .query:
            return .queryLimit
        case .source:
            return .sourceLimited
        case nil:
            return fallback
        }
    }

    private static func querySummaryText(
        entityLabel: String,
        filters: [GraphChatAnswerArtifactQueryFilterSummary],
        grouping: GraphChatAnswerArtifactQueryFieldSummary?,
        sorting: [GraphChatAnswerArtifactQuerySortSummary],
        projection: [GraphChatAnswerArtifactQueryFieldSummary],
        includesNodeIdentity: Bool,
        limit: Int,
        aggregation: GraphChatAnswerArtifactQueryAggregationSummary?,
        strings: Strings
    ) -> String {
        var clauses = ["\(strings.entity): \(entityLabel)"]
        if filters.isEmpty == false {
            let filterText = filters.map { filter in
                var value = "\(filter.field.label) \(filter.operationLabel)"
                if let description = filter.valueDescription, description.isEmpty == false {
                    value += " \(description)"
                }
                return value
            }.joined(separator: ", ")
            clauses.append("\(strings.filters): \(filterText)")
        }
        if let grouping {
            clauses.append("\(strings.grouping): \(grouping.label)")
        }
        if sorting.isEmpty == false {
            let value = sorting.map { "\($0.label) \($0.directionLabel)" }.joined(separator: ", ")
            clauses.append("\(strings.sorting): \(value)")
        }
        var projectionLabels = projection.map(\.label)
        if includesNodeIdentity {
            projectionLabels.insert(strings.name, at: 0)
        }
        if projectionLabels.isEmpty == false {
            clauses.append("\(strings.projection): \(projectionLabels.joined(separator: ", "))")
        }
        clauses.append("\(strings.limit): \(limit)")
        if let aggregation {
            clauses.append("\(strings.aggregation): \(aggregationLabel(aggregation))")
        }
        return clauses.joined(separator: "; ")
    }

    private static func aggregationLabel(
        _ aggregation: GraphChatAnswerArtifactQueryAggregationSummary
    ) -> String {
        switch aggregation {
        case .count(let label):
            return label
        case .minimum(let field, let label),
             .maximum(let field, let label),
             .groupCount(let field, let label):
            return "\(label): \(field.label)"
        }
    }

    private static func projectedFieldIDs(
        _ plan: ValidatedGraphQueryPlan
    ) -> [UUID] {
        var seen = Set<UUID>()
        return plan.projection.compactMap { projection in
            guard case .field(let fieldID) = projection,
                  seen.insert(fieldID).inserted else {
                return nil
            }
            return fieldID
        }
    }

    private static func entityName(
        _ entityID: UUID,
        schemaContext: GraphSchemaContext
    ) -> String? {
        schemaContext.aliases.entitiesByAlias.values.first {
            $0.entityID == entityID
        }?.name
    }

    private static func fieldInfoByID(
        _ schemaContext: GraphSchemaContext
    ) -> [UUID: FieldInfo] {
        let sorted = schemaContext.aliases.fieldsByAlias.values.sorted {
            if $0.alias.rawValue != $1.alias.rawValue {
                return $0.alias.rawValue < $1.alias.rawValue
            }
            return $0.fieldID.uuidString < $1.fieldID.uuidString
        }
        return sorted.reduce(into: [:]) { result, resolution in
            result[resolution.fieldID] = FieldInfo(
                id: resolution.fieldID,
                name: resolution.name,
                type: resolution.type,
                unit: resolution.unit,
                choiceOptions: resolution.choiceOptions
            )
        }
    }

    private static func artifactValues(
        _ value: GraphValidatedFilterValue,
        field: FieldInfo
    ) -> [GraphChatAnswerArtifactValue] {
        switch value {
        case .none:
            return []
        case .text(let value):
            return [.text(value)]
        case .integer(let value):
            return [.integer(value)]
        case .integerRange(let range):
            return [.integer(range.lowerBound), .integer(range.upperBound)]
        case .decimal(let value):
            return [.decimal(Decimal(value))]
        case .decimalRange(let range):
            return [.decimal(Decimal(range.lowerBound)), .decimal(Decimal(range.upperBound))]
        case .date(let value):
            return [.date(value)]
        case .dateInterval(let interval):
            return [.date(interval.lowerBound), .date(interval.upperBoundExclusive)]
        case .boolean(let value):
            return [.boolean(value)]
        case .choice(let value):
            return [choiceValue(value.canonicalValue, field: field)]
        case .choices(let values):
            return values.map { choiceValue($0.canonicalValue, field: field) }
        }
    }

    private static func artifactValue(
        _ value: GraphChatQueryCellValue,
        field: FieldInfo?
    ) -> GraphChatAnswerArtifactValue {
        switch value {
        case .choice(let rawValue):
            return choiceValue(rawValue, field: field)
        default:
            return GraphChatAnswerArtifactValue(queryValue: value)
        }
    }

    private static func choiceValue(
        _ rawValue: String,
        field: FieldInfo?
    ) -> GraphChatAnswerArtifactValue {
        let label = field?.choiceOptions.first {
            GraphQueryChoiceNormalizer.normalize($0)
                == GraphQueryChoiceNormalizer.normalize(rawValue)
        } ?? rawValue
        return .choice(
            GraphChatAnswerArtifactChoiceValue(
                value: rawValue,
                label: label
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
        _ value: GraphChatAnswerArtifactValue,
        strings: Strings
    ) -> String {
        switch value {
        case .text(let value):
            return value
        case .integer(let value):
            return String(value)
        case .decimal(let value):
            return NSDecimalNumber(decimal: value).stringValue
        case .boolean(let value):
            return value ? strings.yes : strings.no
        case .date(let value), .dateTime(let value):
            return value.formatted(
                Date.FormatStyle(
                    date: .numeric,
                    time: .omitted,
                    locale: Locale(identifier: strings.language.localeIdentifier)
                )
            )
        case .duration(let value):
            return String(value)
        case .percentage(let value):
            return NSDecimalNumber(decimal: value).stringValue
        case .choice(let value):
            return value.label
        case .missing:
            return strings.missing
        }
    }

    private static func localizedFieldType(
        _ type: DetailFieldType,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, type) {
        case (.german, .singleLineText):
            return "Text"
        case (.english, .singleLineText):
            return "Text"
        case (.german, .multiLineText):
            return "Mehrzeiliger Text"
        case (.english, .multiLineText):
            return "Multiline text"
        case (.german, .numberInt):
            return "Ganzzahl"
        case (.english, .numberInt):
            return "Integer"
        case (.german, .numberDouble):
            return "Dezimalzahl"
        case (.english, .numberDouble):
            return "Decimal"
        case (.german, .date):
            return "Datum"
        case (.english, .date):
            return "Date"
        case (.german, .toggle):
            return "Ja/Nein"
        case (.english, .toggle):
            return "Yes/No"
        case (.german, .singleChoice):
            return "Auswahl"
        case (.english, .singleChoice):
            return "Choice"
        }
    }

    private static func stableItemID(_ key: String) -> GraphChatAnswerArtifactItemID {
        GraphChatAnswerArtifactItemID(
            rawValue: GraphEvidenceStableIdentity.deterministicUUID(for: "answer-artifact:\(key)")
        )
    }

    private struct FieldInfo: Hashable, Sendable {
        let id: UUID
        let name: String
        let type: DetailFieldType
        let unit: String?
        let choiceOptions: [String]

        var summary: GraphChatAnswerArtifactQueryFieldSummary {
            GraphChatAnswerArtifactQueryFieldSummary(
                fieldID: id,
                label: name
            )
        }
    }

    private struct Strings: Sendable {
        let language: GraphChatResponseLanguage

        init(_ language: GraphChatResponseLanguage) {
            self.language = language
        }

        var entity: String { localized("Entity", "Entity") }
        var entries: String { localized("Einträge", "Entries") }
        var fields: String { localized("Felder", "Fields") }
        var field: String { localized("Feld", "Field") }
        var value: String { localized("Wert", "Value") }
        var unit: String { localized("Einheit", "Unit") }
        var name: String { localized("Name", "Name") }
        var incoming: String { localized("Eingehend", "Incoming") }
        var outgoing: String { localized("Ausgehend", "Outgoing") }
        var queryResults: String { localized("Abfrageergebnisse", "Query results") }
        var timeline: String { localized("Zeitliche Ergebnisse", "Timeline results") }
        var mostConnectedNodes: String { localized("Am stärksten verknüpfte Nodes", "Most connected nodes") }
        var graphHealthScore: String { localized("Graph-Health-Score", "Graph health score") }
        var graphHealthFinding: String { localized("Graph-Health-Befund", "Graph health finding") }
        var points: String { localized("Punkte", "points") }
        var yes: String { localized("Ja", "Yes") }
        var no: String { localized("Nein", "No") }
        var missing: String { localized("Fehlend", "Missing") }
        var filters: String { localized("Filter", "Filters") }
        var grouping: String { localized("Gruppierung", "Grouping") }
        var sorting: String { localized("Sortierung", "Sorting") }
        var projection: String { localized("Projektion", "Projection") }
        var limit: String { localized("Limit", "Limit") }
        var aggregation: String { localized("Aggregation", "Aggregation") }
        var count: String { localized("Anzahl", "Count") }
        var minimum: String { localized("Minimum", "Minimum") }
        var maximum: String { localized("Maximum", "Maximum") }
        var groupCount: String { localized("Gruppierte Anzahl", "Grouped count") }

        func schemaOverview(_ graphName: String) -> String {
            localized("Schemaübersicht: \(graphName)", "Schema overview: \(graphName)")
        }

        func searchResults(_ query: String) -> String {
            localized("Suchergebnisse für \(query)", "Search results for \(query)")
        }

        func neighbors(_ label: String) -> String {
            localized("Nachbarn von \(label)", "Neighbors of \(label)")
        }

        func countFor(_ entity: String) -> String {
            localized("Anzahl \(entity)", "Count of \(entity)")
        }

        func minimumFor(_ field: String) -> String {
            localized("Minimum von \(field)", "Minimum of \(field)")
        }

        func maximumFor(_ field: String) -> String {
            localized("Maximum von \(field)", "Maximum of \(field)")
        }

        func groupedBy(_ field: String) -> String {
            localized("Gruppiert nach \(field)", "Grouped by \(field)")
        }

        func graphOverviewContext(nodeCount: Int, linkCount: Int) -> String {
            localized(
                "\(nodeCount) Nodes und \(linkCount) Verknüpfungen",
                "\(nodeCount) nodes and \(linkCount) links"
            )
        }

        func healthFindingSummary(isolatedNodeCount: Int, issueCount: Int) -> String {
            if isolatedNodeCount > 0 {
                return localized(
                    "\(isolatedNodeCount) isolierte Nodes bei insgesamt \(issueCount) Health-Befunden.",
                    "\(isolatedNodeCount) isolated nodes across \(issueCount) health findings."
                )
            }
            return localized(
                "\(issueCount) Health-Befunde wurden erkannt.",
                "\(issueCount) health findings were detected."
            )
        }

        func operation(_ operation: GraphQueryFilterOperator) -> String {
            switch (language, operation) {
            case (.german, .contains): return "enthält"
            case (.english, .contains): return "contains"
            case (.german, .equals): return "ist gleich"
            case (.english, .equals): return "equals"
            case (.german, .startsWith): return "beginnt mit"
            case (.english, .startsWith): return "starts with"
            case (.german, .isPresent): return "ist vorhanden"
            case (.english, .isPresent): return "is present"
            case (.german, .isMissing): return "fehlt"
            case (.english, .isMissing): return "is missing"
            case (.german, .lessThan): return "ist kleiner als"
            case (.english, .lessThan): return "is less than"
            case (.german, .lessThanOrEqual): return "ist höchstens"
            case (.english, .lessThanOrEqual): return "is at most"
            case (.german, .greaterThan): return "ist größer als"
            case (.english, .greaterThan): return "is greater than"
            case (.german, .greaterThanOrEqual): return "ist mindestens"
            case (.english, .greaterThanOrEqual): return "is at least"
            case (.german, .between): return "liegt zwischen"
            case (.english, .between): return "is between"
            case (.german, .before): return "liegt vor"
            case (.english, .before): return "is before"
            case (.german, .after): return "liegt nach"
            case (.english, .after): return "is after"
            case (.german, .inYear): return "liegt im Jahr"
            case (.english, .inYear): return "is in year"
            case (.german, .inMonth): return "liegt im Monat"
            case (.english, .inMonth): return "is in month"
            case (.german, .isOverdue): return "ist überfällig"
            case (.english, .isOverdue): return "is overdue"
            case (.german, .oneOf): return "ist einer von"
            case (.english, .oneOf): return "is one of"
            }
        }

        func sortDirection(_ direction: GraphQuerySortDirection) -> String {
            switch (language, direction) {
            case (.german, .ascending): return "aufsteigend"
            case (.english, .ascending): return "ascending"
            case (.german, .descending): return "absteigend"
            case (.english, .descending): return "descending"
            }
        }

        func presentation(for field: FieldInfo? = nil) -> GraphChatAnswerArtifactValuePresentation {
            GraphChatAnswerArtifactValuePresentation(
                missingLabel: missing,
                booleanTrueLabel: yes,
                booleanFalseLabel: no,
                dateFormat: field?.type == .date ? .localizedDate : nil,
                choiceLabels: field?.choiceOptions.map {
                    GraphChatAnswerArtifactChoiceValue(value: $0, label: $0)
                } ?? []
            )
        }

        private func localized(_ german: String, _ english: String) -> String {
            language == .german ? german : english
        }
    }
}

nonisolated private extension GraphQuerySortDirection {
    var artifactDirection: GraphChatAnswerArtifactSortDirection {
        self == .ascending ? .ascending : .descending
    }
}
