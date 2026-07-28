//
//  GraphChatConversationStateReducer+References.swift
//  BrainMesh
//
//  Result-context and validated conversation-reference construction.
//

import Foundation

nonisolated extension GraphChatConversationStateReducer {
    func appendResultContext(
        _ context: GraphChatConversationResultContext,
        to state: inout GraphChatConversationState
    ) {
        state.resultContexts.removeAll { $0.id == context.id }
        state.resultContexts.append(context)
        for group in context.groupReferences {
            upsertGroup(group, in: &state)
        }
        updateReferenceTargets(from: context, state: &state)
    }

    func updateReferenceTargets(
        from context: GraphChatConversationResultContext,
        state: inout GraphChatConversationState
    ) {
        let ordinal = context.references.map(\.reference)
        let groups = context.groupReferences.map { GraphChatConversationReference.group($0.id) }
        let singular: GraphChatConversationReference?
        if ordinal.count == 1 {
            singular = ordinal.first
        } else if context.kind == .node || context.kind == .neighbors {
            singular = ordinal.first
        } else {
            singular = nil
        }
        state.referenceTargets = GraphChatConversationReferenceTargets(
            singular: singular,
            plural: ordinal,
            ordinal: ordinal,
            group: groups.last,
            compared: state.lastComparison?.references ?? []
        )
    }
    func upsertNode(
        _ reference: GraphChatConversationNodeReference,
        in state: inout GraphChatConversationState
    ) {
        state.nodeReferences.removeAll { $0.node == reference.node }
        state.nodeReferences.append(reference)
    }

    func upsertEntity(
        _ reference: GraphChatConversationEntityReference,
        in state: inout GraphChatConversationState
    ) {
        state.entityReferences.removeAll { $0.entityID == reference.entityID }
        state.entityReferences.append(reference)
    }

    func upsertField(
        _ reference: GraphChatConversationFieldReference,
        in state: inout GraphChatConversationState
    ) {
        state.fieldReferences.removeAll { $0.fieldID == reference.fieldID }
        state.fieldReferences.append(reference)
    }

    func upsertGroup(
        _ reference: GraphChatConversationGroupReference,
        in state: inout GraphChatConversationState
    ) {
        state.groupReferences.removeAll { $0.id == reference.id }
        state.groupReferences.append(reference)
    }

    func upsertEntityFromNode(
        _ node: GraphChatConversationNodeReference,
        fallbackName: String? = nil,
        in state: inout GraphChatConversationState
    ) {
        guard let entityID = node.ownerEntityID else {
            return
        }
        if let existing = state.entityReferences.first(where: { $0.entityID == entityID }) {
            upsertEntity(existing, in: &state)
            return
        }
        let name =
            fallbackName
            ?? (node.node.kind == .entity ? node.label : "Entity")
        upsertEntity(
            GraphChatConversationEntityReference(
                entityID: entityID,
                name: boundedLabel(name),
                alias: nil
            ),
            in: &state
        )
    }

    func makeNodeReference(
        node: NodeRefKey,
        label: String,
        sourceReference: GraphSourceReference,
        evidenceIDs: [GraphEvidenceID]
    ) -> GraphChatConversationNodeReference {
        let ownerEntityID: UUID?
        if node.kind == .entity {
            ownerEntityID = node.id
        } else if sourceReference.ownerKind == .entity {
            ownerEntityID = sourceReference.ownerID
        } else {
            ownerEntityID = nil
        }
        return GraphChatConversationNodeReference(
            node: node,
            label: boundedLabel(label),
            ownerEntityID: ownerEntityID,
            evidenceIDs: boundedEvidenceIDs(evidenceIDs)
        )
    }

    func fieldReference(
        from resolution: GraphSchemaFieldResolution
    ) -> GraphChatConversationFieldReference {
        GraphChatConversationFieldReference(
            fieldID: resolution.fieldID,
            entityID: resolution.entityID,
            name: boundedLabel(resolution.name),
            type: resolution.type,
            unit: resolution.unit.map(boundedLabel),
            alias: resolution.alias
        )
    }

    func fieldIDs(in plan: ValidatedGraphQueryPlan) -> Set<UUID> {
        var ids = Set(plan.filters.map(\.fieldID))
        for sort in plan.sorting {
            if case .field(let fieldID) = sort.key {
                ids.insert(fieldID)
            }
        }
        for projection in plan.projection {
            if case .field(let fieldID) = projection {
                ids.insert(fieldID)
            }
        }
        if let aggregation = plan.aggregation {
            switch aggregation {
            case .count:
                break
            case .groupCount(let fieldID),
                .minimum(let fieldID),
                .maximum(let fieldID):
                ids.insert(fieldID)
            }
        }
        return ids
    }

    func makeGroups(
        from aggregation: GraphChatAggregationResult?,
        evidence: [GraphEvidence]
    ) -> [GraphChatConversationGroupReference] {
        guard let aggregation, aggregation.kind == .groupCount else {
            return []
        }
        let evidenceByID = Dictionary(uniqueKeysWithValues: evidence.map { ($0.id, $0) })
        return aggregation.groups.enumerated().map { index, group in
            let validIDs = boundedEvidenceIDs(
                group.evidenceIDs.filter { evidenceByID[$0] != nil }
            )
            let evidenceMembers = validIDs.compactMap {
                evidenceID in
                evidenceByID[evidenceID]?
                    .sourceReference.node?.nodeKey
                    ?? evidenceByID[evidenceID]
                        .flatMap {
                            inferredNode(
                                from:
                                    $0.sourceReference
                            )
                        }
            }
            let members = group.memberNodes.isEmpty
                ? evidenceMembers
                : group.memberNodes
            let valueDescription = valueDescription(group.value)
            let stableID = GraphChatConversationGroupIdentity.make(
                fieldID: aggregation.fieldID,
                value: group.value,
                index: index
            )
            return GraphChatConversationGroupReference(
                id: stableID,
                fieldID: aggregation.fieldID,
                fieldName: aggregation.fieldName.map(boundedLabel),
                valueDescription: boundedLabel(valueDescription),
                count: group.count,
                evidenceIDs: validIDs,
                memberNodes: members
            )
        }
    }

    func valueDescription(_ value: GraphChatQueryCellValue) -> String {
        switch value {
        case .text(let value), .choice(let value):
            return value
        case .integer(let value):
            return String(value)
        case .decimal(let value):
            return String(value)
        case .date(let value):
            return ISO8601DateFormatter().string(from: value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .missing:
            return "missing"
        }
    }

    func queryTechnicalDescription(
        _ result: GraphChatQueryResult
    ) -> String {
        if let aggregation = result.aggregation {
            return
                "Validierte Query-Aggregation \(aggregation.kind.rawValue) mit \(aggregation.groups.count) Gruppen"
        }
        return "Validierte Query-Ergebnismenge mit \(result.rows.count) geordneten Rows"
    }

    func resultKind(
        for tool: GraphChatToolKind
    ) -> GraphChatConversationResultKind {
        switch tool {
        case .describeGraphSchema:
            return .schema
        case .searchGraph:
            return .search
        case .queryDetailValues:
            return .query
        case .getNode:
            return .node
        case .getNeighbors:
            return .neighbors
        case .graphStats:
            return .stats
        }
    }

    func toolResultState(
        from state: GraphChatResultState
    ) -> GraphChatToolResultState {
        switch state {
        case .success:
            return .success
        case .noResults:
            return .noResults
        case .noEvidence:
            return .noEvidence
        }
    }

    func inferredNode(
        from sourceReference: GraphSourceReference
    ) -> NodeRefKey? {
        switch sourceReference.sourceKind {
        case .entity:
            return NodeRefKey(kind: .entity, id: sourceReference.sourceID)
        case .attribute:
            return NodeRefKey(kind: .attribute, id: sourceReference.sourceID)
        case .graph, .detailField, .detailValue, .link, .attachment:
            return sourceReference.owner?.nodeKey
        }
    }
    func deduplicated(
        _ references: [GraphChatConversationReference]
    ) -> [GraphChatConversationReference] {
        var seen = Set<String>()
        return references.filter { seen.insert($0.stableKey).inserted }
    }
}
