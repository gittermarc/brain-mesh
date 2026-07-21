//
//  GraphChatQueryEngine+Evidence.swift
//  BrainMesh
//
//  Result projection, aggregation, and concrete source evidence.
//

import Foundation

nonisolated extension GraphChatQueryEngine {
    struct ResultRowBuild: Sendable {
        let rows: [GraphChatQueryResultRow]
        let evidence: [GraphEvidence]
    }

    struct AggregationBuild: Sendable {
        let state: GraphChatResultState
        let result: GraphChatAggregationResult
        let evidence: [GraphEvidence]
    }

    static func makeResultRows(
        _ rows: [GraphChatPreparedQueryRow],
        plan: ValidatedGraphQueryPlan,
        fieldMap: [UUID: GraphDetailFieldDefinitionDTO],
        maximumEvidenceCount: Int
    ) throws -> ResultRowBuild {
        let evidenceFieldIDs = evidenceFieldIDs(for: plan)
        let projectedFieldIDs = plan.projection.compactMap { projection -> UUID? in
            if case .field(let fieldID) = projection {
                return fieldID
            }
            return nil
        }

        var resultRows: [GraphChatQueryResultRow] = []
        resultRows.reserveCapacity(rows.count)
        var evidence: [GraphEvidence] = []

        for row in rows {
            try Task.checkCancellation()
            let baseEvidence = makeAttributeEvidence(row.attribute)
            evidence.append(baseEvidence)
            var rowEvidenceIDs: [GraphEvidenceID] = [baseEvidence.id]
            var fieldEvidenceByID: [UUID: GraphEvidence] = [:]

            for fieldID in evidenceFieldIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let field = fieldMap[fieldID] else {
                    continue
                }
                let item = makeFieldEvidence(
                    row: row,
                    field: field
                )
                fieldEvidenceByID[fieldID] = item
                evidence.append(item)
                rowEvidenceIDs.append(item.id)
            }

            let cells = projectedFieldIDs.compactMap { fieldID -> GraphChatQueryCell? in
                guard let field = fieldMap[fieldID] else {
                    return nil
                }
                let item: GraphEvidence
                if let existing = fieldEvidenceByID[fieldID] {
                    item = existing
                } else {
                    item = makeFieldEvidence(row: row, field: field)
                    fieldEvidenceByID[fieldID] = item
                    evidence.append(item)
                    rowEvidenceIDs.append(item.id)
                }
                let value = row.valuesByFieldID[fieldID]?.value.graphChatCellValue ?? .missing
                return GraphChatQueryCell(
                    fieldID: fieldID,
                    fieldName: field.name,
                    unit: field.unit,
                    value: value,
                    evidenceID: item.id
                )
            }

            resultRows.append(
                GraphChatQueryResultRow(
                    node: row.attribute.nodeKey,
                    label: row.attribute.displayLabel,
                    cells: cells,
                    evidenceIDs: GraphEvidenceCollection(
                        rowEvidenceIDs.compactMap { id in
                            evidence.first(where: { $0.id == id })
                        }
                    ).ids
                )
            )

            guard evidence.count <= maximumEvidenceCount else {
                throw GraphChatQueryEngineError.evidenceLimitExceeded(
                    maximum: maximumEvidenceCount
                )
            }
        }

        return ResultRowBuild(
            rows: resultRows,
            evidence: GraphEvidenceCollection(evidence).values
        )
    }

    static func makeAggregation(
        _ aggregation: GraphValidatedAggregation,
        rows: [GraphChatPreparedQueryRow],
        entity: GraphEntityDTO,
        fieldMap: [UUID: GraphDetailFieldDefinitionDTO],
        scope: GraphResolvedQueryScope,
        sourceAttributes: [GraphAttributeDTO],
        limit: Int,
        maximumEvidenceCount: Int
    ) throws -> AggregationBuild {
        switch aggregation {
        case .count:
            let aggregateEvidence = makeAggregateEvidence(
                entity: entity,
                scope: scope,
                sourceAttributes: sourceAttributes,
                kind: .count,
                count: rows.count,
                field: nil,
                value: nil
            )
            var evidence = [aggregateEvidence]
            let supportingLimit = min(limit, max(0, maximumEvidenceCount - 1))
            evidence.append(
                contentsOf: rows.prefix(supportingLimit).map {
                    makeAttributeEvidence($0.attribute)
                }
            )
            let deduplicatedEvidence = GraphEvidenceCollection(evidence).values
            guard deduplicatedEvidence.count <= maximumEvidenceCount else {
                throw GraphChatQueryEngineError.evidenceLimitExceeded(
                    maximum: maximumEvidenceCount
                )
            }
            return AggregationBuild(
                state: .success,
                result: GraphChatAggregationResult(
                    kind: .count,
                    fieldID: nil,
                    fieldName: nil,
                    count: rows.count,
                    groups: [],
                    value: nil,
                    evidenceIDs: deduplicatedEvidence.map(\.id)
                ),
                evidence: deduplicatedEvidence
            )

        case .groupCount(let fieldID):
            guard let field = fieldMap[fieldID] else {
                throw GraphChatQueryEngineError.sourceUnavailable
            }
            var grouped: [GraphChatQueryCellValue: [GraphChatPreparedQueryRow]] = [:]
            for row in rows {
                try Task.checkCancellation()
                let value = row.valuesByFieldID[fieldID]?.value.graphChatCellValue ?? .missing
                grouped[value, default: []].append(row)
            }

            let sortedKeys = grouped.keys.sorted {
                GraphChatQueryValueFormatting.stableKey($0)
                    < GraphChatQueryValueFormatting.stableKey($1)
            }
            var evidence: [GraphEvidence] = []
            var groups: [GraphChatGroupCount] = []
            let limitedKeys = Array(sortedKeys.prefix(limit))
            var remainingEvidenceSlots = max(0, maximumEvidenceCount - 1)
            for (index, value) in limitedKeys.enumerated() {
                guard let groupRows = grouped[value], groupRows.isEmpty == false else {
                    continue
                }
                let remainingGroups = limitedKeys.count - index
                let reservedForFollowingGroups = max(0, remainingGroups - 1)
                let availableForCurrentGroup = max(
                    1,
                    remainingEvidenceSlots - reservedForFollowingGroups
                )
                let currentEvidenceLimit = min(
                    groupRows.count,
                    availableForCurrentGroup
                )
                var ids: [GraphEvidenceID] = []
                for row in groupRows.prefix(currentEvidenceLimit) {
                    let item = makeFieldEvidence(row: row, field: field)
                    evidence.append(item)
                    ids.append(item.id)
                }
                remainingEvidenceSlots = max(0, remainingEvidenceSlots - ids.count)
                groups.append(
                    GraphChatGroupCount(
                        value: value,
                        count: groupRows.count,
                        evidenceIDs: ids
                    )
                )
            }
            let aggregateEvidence = makeAggregateEvidence(
                entity: entity,
                scope: scope,
                sourceAttributes: sourceAttributes,
                kind: .groupCount,
                count: rows.count,
                field: field,
                value: nil
            )
            evidence.insert(aggregateEvidence, at: 0)
            guard evidence.count <= maximumEvidenceCount else {
                throw GraphChatQueryEngineError.evidenceLimitExceeded(
                    maximum: maximumEvidenceCount
                )
            }
            return AggregationBuild(
                state: rows.isEmpty ? .noResults : .success,
                result: GraphChatAggregationResult(
                    kind: .groupCount,
                    fieldID: fieldID,
                    fieldName: field.name,
                    count: rows.count,
                    groups: groups,
                    value: nil,
                    evidenceIDs: [aggregateEvidence.id] + groups.flatMap(\.evidenceIDs)
                ),
                evidence: GraphEvidenceCollection(evidence).values
            )

        case .minimum(let fieldID), .maximum(let fieldID):
            guard let field = fieldMap[fieldID] else {
                throw GraphChatQueryEngineError.sourceUnavailable
            }
            let presentRows = rows.filter { row in
                row.valuesByFieldID[fieldID].map { isPresent($0.value) } == true
            }
            let selected = extremeRows(
                presentRows,
                fieldID: fieldID,
                chooseMaximum: {
                    if case .maximum = aggregation { return true }
                    return false
                }()
            )
            let selectedValue = selected.first?.valuesByFieldID[fieldID]?.value.graphChatCellValue
            let supportingLimit = min(limit, max(0, maximumEvidenceCount - 1))
            var evidence = selected.prefix(supportingLimit).map {
                makeFieldEvidence(row: $0, field: field)
            }
            let kind: GraphChatAggregationKind = {
                if case .minimum = aggregation { return .minimum }
                return .maximum
            }()
            let aggregateEvidence = makeAggregateEvidence(
                entity: entity,
                scope: scope,
                sourceAttributes: sourceAttributes,
                kind: kind,
                count: presentRows.count,
                field: field,
                value: selectedValue
            )
            evidence.insert(aggregateEvidence, at: 0)
            guard evidence.count <= maximumEvidenceCount else {
                throw GraphChatQueryEngineError.evidenceLimitExceeded(
                    maximum: maximumEvidenceCount
                )
            }
            return AggregationBuild(
                state: selectedValue == nil ? .noResults : .success,
                result: GraphChatAggregationResult(
                    kind: kind,
                    fieldID: fieldID,
                    fieldName: field.name,
                    count: presentRows.count,
                    groups: [],
                    value: selectedValue,
                    evidenceIDs: evidence.map(\.id)
                ),
                evidence: GraphEvidenceCollection(evidence).values
            )
        }
    }

    static func makeAttributeEvidence(
        _ attribute: GraphAttributeDTO
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: attribute.scope.graphID,
                sourceKind: .attribute,
                sourceID: attribute.id,
                node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                owner: attribute.ownerEntityID.map {
                    GraphSourceNodeReference(kind: .entity, id: $0)
                }
            ),
            summary: attribute.displayLabel,
            navigationTitle: attribute.displayLabel,
            identitySuffix: "query-row"
        )
    }

    static func makeFieldEvidence(
        row: GraphChatPreparedQueryRow,
        field: GraphDetailFieldDefinitionDTO
    ) -> GraphEvidence {
        let owner = row.attribute.ownerEntityID.map {
            GraphSourceNodeReference(kind: .entity, id: $0)
        }
        let node = GraphSourceNodeReference(
            kind: .attribute,
            id: row.attribute.id
        )
        let valueDTO = row.valuesByFieldID[field.id]
        let value = valueDTO?.value.graphEvidenceValue ?? .missing
        let sourceReference: GraphSourceReference
        if let valueDTO {
            sourceReference = GraphSourceReference(
                graphID: row.attribute.scope.graphID,
                sourceKind: .detailValue,
                sourceID: valueDTO.id,
                node: node,
                owner: owner,
                fieldID: field.id
            )
        } else {
            sourceReference = GraphSourceReference(
                graphID: row.attribute.scope.graphID,
                sourceKind: .attribute,
                sourceID: row.attribute.id,
                node: node,
                owner: owner,
                fieldID: field.id
            )
        }
        return GraphEvidence(
            sourceReference: sourceReference,
            summary: "\(row.attribute.displayLabel): \(field.name)",
            fieldValues: [
                GraphEvidenceFieldValue(
                    fieldID: field.id,
                    fieldName: field.name,
                    value: value,
                    unit: field.unit
                )
            ],
            navigationTitle: row.attribute.displayLabel,
            identitySuffix: valueDTO == nil ? "missing" : "value"
        )
    }

    private static func evidenceFieldIDs(
        for plan: ValidatedGraphQueryPlan
    ) -> Set<UUID> {
        var result = Set(plan.filters.map(\.fieldID))
        for projection in plan.projection {
            if case .field(let fieldID) = projection {
                result.insert(fieldID)
            }
        }
        for sort in plan.sorting {
            if case .field(let fieldID) = sort.key {
                result.insert(fieldID)
            }
        }
        return result
    }

    private static func makeAggregateEvidence(
        entity: GraphEntityDTO,
        scope: GraphResolvedQueryScope,
        sourceAttributes: [GraphAttributeDTO],
        kind: GraphChatAggregationKind,
        count: Int,
        field: GraphDetailFieldDefinitionDTO?,
        value: GraphChatQueryCellValue?
    ) -> GraphEvidence {
        var fieldValues: [GraphEvidenceFieldValue] = [
            GraphEvidenceFieldValue(
                fieldID: nil,
                fieldName: "Datenbasis",
                value: .integer(count),
                unit: "Attribute"
            )
        ]
        if let field, let value {
            fieldValues.append(
                GraphEvidenceFieldValue(
                    fieldID: field.id,
                    fieldName: field.name,
                    value: evidenceValue(value),
                    unit: field.unit
                )
            )
        }
        return GraphEvidence(
            sourceReference: aggregateSourceReference(
                entity: entity,
                scope: scope,
                sourceAttributes: sourceAttributes
            ),
            summary: "\(kind.rawValue) auf \(count) passenden Attributen in \(entity.name)",
            fieldValues: fieldValues,
            navigationTitle: entity.name,
            identitySuffix: "aggregation:\(kind.rawValue):\(field?.id.uuidString ?? "none"):\(count)"
        )
    }

    private static func aggregateSourceReference(
        entity: GraphEntityDTO,
        scope: GraphResolvedQueryScope,
        sourceAttributes: [GraphAttributeDTO]
    ) -> GraphSourceReference {
        let selectedAttributeID: UUID?
        switch scope {
        case .graph, .entity:
            selectedAttributeID = nil
        case .node(let node):
            selectedAttributeID = node.kind == .attribute ? node.id : nil
        case .selection(let nodes):
            if nodes.contains(NodeRefKey(kind: .entity, id: entity.id)) {
                selectedAttributeID = nil
            } else {
                selectedAttributeID = nodes
                    .filter { $0.kind == .attribute }
                    .map(\.id)
                    .sorted { $0.uuidString < $1.uuidString }
                    .first
            }
        }

        if let selectedAttributeID,
           let attribute = sourceAttributes.first(where: { $0.id == selectedAttributeID }) {
            return GraphSourceReference(
                graphID: entity.scope.graphID,
                sourceKind: .attribute,
                sourceID: attribute.id,
                node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                owner: GraphSourceNodeReference(kind: .entity, id: entity.id)
            )
        }
        return GraphSourceReference(
            graphID: entity.scope.graphID,
            sourceKind: .entity,
            sourceID: entity.id,
            node: GraphSourceNodeReference(kind: .entity, id: entity.id)
        )
    }

    private static func extremeRows(
        _ rows: [GraphChatPreparedQueryRow],
        fieldID: UUID,
        chooseMaximum: Bool
    ) -> [GraphChatPreparedQueryRow] {
        guard let first = rows.first,
              let firstValue = first.valuesByFieldID[fieldID]?.value else {
            return []
        }
        var bestValue = firstValue
        var result = [first]
        for row in rows.dropFirst() {
            guard let value = row.valuesByFieldID[fieldID]?.value else {
                continue
            }
            let comparison = comparePayloads(value, bestValue)
            let isBetter = chooseMaximum
                ? comparison == .orderedDescending
                : comparison == .orderedAscending
            if isBetter {
                bestValue = value
                result = [row]
            } else if comparison == .orderedSame {
                result.append(row)
            }
        }
        return result.sorted {
            $0.attribute.id.uuidString < $1.attribute.id.uuidString
        }
    }

    private static func evidenceValue(
        _ value: GraphChatQueryCellValue
    ) -> GraphEvidenceValue {
        switch value {
        case .text(let value): return .text(value)
        case .integer(let value): return .integer(value)
        case .decimal(let value): return .decimal(value)
        case .date(let value): return .date(value)
        case .boolean(let value): return .boolean(value)
        case .choice(let value): return .choice(value)
        case .missing: return .missing
        }
    }
}
