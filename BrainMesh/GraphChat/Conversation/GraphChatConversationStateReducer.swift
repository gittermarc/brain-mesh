//
//  GraphChatConversationStateReducer.swift
//  BrainMesh
//
//  Central trust boundary and transactional reducer for graph-chat conversation state.
//

import Foundation

nonisolated enum GraphChatConversationStateError: Error, LocalizedError, Equatable, Sendable {
    case graphScopeMismatch
    case chatScopeMismatch
    case evidenceGraphMismatch
    case schemaGraphMismatch

    var errorDescription: String? {
        switch self {
        case .graphScopeMismatch:
            return "Das Conversation-State-Ereignis gehört nicht zum aktiven Graphen."
        case .chatScopeMismatch:
            return "Das Conversation-State-Ereignis gehört nicht zum aktiven Chat-Scope."
        case .evidenceGraphMismatch:
            return "Das Conversation-State-Ereignis enthält Evidence aus einem anderen Graphen."
        case .schemaGraphMismatch:
            return "Das Conversation-State-Ereignis enthält ein Schema aus einem anderen Graphen."
        }
    }
}

nonisolated struct GraphChatConversationTurnCompletion: Sendable {
    let requestID: UUID
    let completedAt: Date
    let toolKinds: [GraphChatToolKind]
    let resultContextIDs: [UUID]
    let evidenceIDs: [GraphEvidenceID]
}

nonisolated enum GraphChatConversationTrustedPayload: Sendable {
    case schemaResolved(
        schemaContext: GraphSchemaContext,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case searchResolved(
        output: SearchGraphOutput,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case queryResolved(
        plan: ValidatedGraphQueryPlan,
        result: GraphChatQueryResult,
        schemaContext: GraphSchemaContext
    )
    case nodeResolved(
        output: GetNodeOutput,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case neighborsResolved(
        output: GetNeighborsOutput,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case statsResolved(
        output: GraphStatsOutput,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case validatedEvidence(
        tool: GraphChatToolKind,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case comparisonResolved(
        references: [GraphChatConversationReference],
        technicalDescription: String
    )
    case turnCompleted(GraphChatConversationTurnCompletion)

    var toolKind: GraphChatToolKind? {
        switch self {
        case .schemaResolved:
            return .describeGraphSchema
        case .searchResolved:
            return .searchGraph
        case .queryResolved:
            return .queryDetailValues
        case .nodeResolved:
            return .getNode
        case .neighborsResolved:
            return .getNeighbors
        case .statsResolved:
            return .graphStats
        case .validatedEvidence(let tool, _, _):
            return tool
        case .comparisonResolved, .turnCompleted:
            return nil
        }
    }
}

nonisolated struct GraphChatConversationTrustedEvent: Sendable {
    let id: UUID
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let payload: GraphChatConversationTrustedPayload

    init(
        id: UUID = UUID(),
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        payload: GraphChatConversationTrustedPayload
    ) {
        self.id = id
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.payload = payload
    }
}

nonisolated struct GraphChatConversationStateReduction: Sendable {
    let state: GraphChatConversationState
    let evictedItemCount: Int
}

nonisolated struct GraphChatConversationStateReducer: Sendable {
    let policy: GraphChatConversationStatePolicy

    init(policy: GraphChatConversationStatePolicy = .default) {
        self.policy = policy
    }

    func reduce(
        _ state: GraphChatConversationState,
        event: GraphChatConversationTrustedEvent
    ) throws -> GraphChatConversationStateReduction {
        guard event.graphScope == state.graphScope else {
            throw GraphChatConversationStateError.graphScopeMismatch
        }
        guard event.chatScope == state.chatScope else {
            throw GraphChatConversationStateError.chatScopeMismatch
        }

        var candidate = state
        switch event.payload {
        case .schemaResolved(let schemaContext, let resultState, let evidence):
            try validate(schemaContext: schemaContext, evidence: evidence, state: state)
            applySchema(
                schemaContext,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .searchResolved(let output, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applySearch(
                output,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .queryResolved(let plan, let result, let schemaContext):
            guard plan.graphScope == state.graphScope else {
                throw GraphChatConversationStateError.graphScopeMismatch
            }
            guard GraphChatScopeAuthorization.allows(
                plan: plan,
                within: state.chatScope
            ) else {
                throw GraphChatConversationStateError.chatScopeMismatch
            }
            try validate(schemaContext: schemaContext, evidence: result.evidence, state: state)
            applyQuery(
                plan: plan,
                result: result,
                schemaContext: schemaContext,
                eventID: event.id,
                to: &candidate
            )
        case .nodeResolved(let output, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applyNode(
                output,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .neighborsResolved(let output, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applyNeighbors(
                output,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .statsResolved(let output, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applyStats(
                output,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .validatedEvidence(let tool, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applyValidatedEvidence(
                tool: tool,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .comparisonResolved(let references, let technicalDescription):
            applyComparison(
                references: references,
                technicalDescription: technicalDescription,
                to: &candidate
            )
        case .turnCompleted(let completion):
            applyTurnCompletion(completion, to: &candidate)
        }

        let result = enforceBudgets(candidate)
        return GraphChatConversationStateReduction(
            state: result.state,
            evictedItemCount: result.evictedItemCount
        )
    }

    func transition(
        _ state: GraphChatConversationState,
        to newScope: GraphChatScope,
        reason: GraphChatConversationResetReason = .scopeChanged
    ) -> GraphChatConversationStateReduction {
        guard state.graphScope == newScope.graphScope else {
            return GraphChatConversationStateReduction(
                state: .initial(
                    graphScope: newScope.graphScope,
                    chatScope: newScope,
                    resetReason: .graphChanged
                ),
                evictedItemCount: state.turnContexts.count
                    + state.nodeReferences.count
                    + state.entityReferences.count
                    + state.fieldReferences.count
                    + state.resultContexts.count
                    + state.groupReferences.count
            )
        }
        guard state.chatScope != newScope else {
            return GraphChatConversationStateReduction(
                state: state,
                evictedItemCount: 0
            )
        }

        var transitioned = GraphChatConversationState(
            conversationID: state.conversationID,
            graphScope: state.graphScope,
            chatScope: newScope,
            turnContexts: [],
            nodeReferences: state.nodeReferences.filter { allows($0, in: newScope) },
            entityReferences: state.entityReferences,
            fieldReferences: state.fieldReferences,
            resultContexts: [],
            groupReferences: [],
            lastValidatedQueryPlan: nil,
            lastComparison: nil,
            referenceTargets: .empty,
            lastResetReason: reason,
            budgetEvictionCount: state.budgetEvictionCount
        )

        let allowedEntityIDs = Set(
            transitioned.nodeReferences.compactMap(\.ownerEntityID)
                + entityIDsExplicitlyAllowed(by: newScope)
        )
        switch newScope.target {
        case .graph:
            transitioned.nodeReferences = []
        case .entity(let entityID):
            transitioned.entityReferences = transitioned.entityReferences.filter {
                $0.entityID == entityID
            }
            transitioned.fieldReferences = transitioned.fieldReferences.filter {
                $0.entityID == entityID
            }
        case .node, .selection:
            transitioned.entityReferences = transitioned.entityReferences.filter {
                allowedEntityIDs.contains($0.entityID)
            }
            transitioned.fieldReferences = transitioned.fieldReferences.filter {
                allowedEntityIDs.contains($0.entityID)
            }
        }

        let priorCount = state.turnContexts.count
            + state.nodeReferences.count
            + state.entityReferences.count
            + state.fieldReferences.count
            + state.resultContexts.count
            + state.groupReferences.count
        let retainedCount = transitioned.nodeReferences.count
            + transitioned.entityReferences.count
            + transitioned.fieldReferences.count
        let evicted = max(0, priorCount - retainedCount)
        transitioned.budgetEvictionCount += evicted
        return GraphChatConversationStateReduction(
            state: transitioned,
            evictedItemCount: evicted
        )
    }

    private func validate(
        schemaContext: GraphSchemaContext,
        evidence: [GraphEvidence],
        state: GraphChatConversationState
    ) throws {
        guard schemaContext.graphScope == state.graphScope,
              schemaContext.aliases.graphScope == state.graphScope else {
            throw GraphChatConversationStateError.schemaGraphMismatch
        }
        try validate(evidence: evidence, state: state)
    }

    private func validate(
        evidence: [GraphEvidence],
        state: GraphChatConversationState
    ) throws {
        guard evidence.allSatisfy({
            $0.sourceReference.graphID == state.graphScope.graphID
        }) else {
            throw GraphChatConversationStateError.evidenceGraphMismatch
        }
    }

    private func applySchema(
        _ schemaContext: GraphSchemaContext,
        resultState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        guard resultState != .noEvidence else {
            return
        }
        let allowedEntityIDs = schemaEntityIDsAllowed(
            in: state,
            schemaContext: schemaContext
        )
        let entityResolutions = schemaContext.aliases.entitiesByAlias.values
            .filter { resolution in
                allowedEntityIDs?.contains(resolution.entityID) ?? true
            }
            .sorted {
                $0.alias.rawValue < $1.alias.rawValue
            }
        for resolution in entityResolutions {
            upsertEntity(
                GraphChatConversationEntityReference(
                    entityID: resolution.entityID,
                    name: boundedLabel(resolution.name),
                    alias: resolution.alias
                ),
                in: &state
            )
        }
        let fieldResolutions = schemaContext.aliases.fieldsByAlias.values
            .filter { resolution in
                allowedEntityIDs?.contains(resolution.entityID) ?? true
            }
            .sorted {
                $0.alias.rawValue < $1.alias.rawValue
            }
        for resolution in fieldResolutions {
            upsertField(
                fieldReference(from: resolution),
                in: &state
            )
        }
        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: .schema,
                state: resultState,
                entityID: nil,
                references: entityResolutions.enumerated().map { index, resolution in
                    GraphChatConversationResultReference(
                        ordinal: index + 1,
                        reference: .entity(resolution.entityID),
                        label: boundedLabel(resolution.name),
                        evidenceIDs: boundedEvidenceIDs(evidence.map(\.id))
                    )
                },
                groupReferences: [],
                evidenceIDs: boundedEvidenceIDs(evidence.map(\.id)),
                appliedFilters: [],
                technicalDescription: boundedTechnicalDescription(
                    "Schema mit \(entityResolutions.count) Entities und \(fieldResolutions.count) Feldern validiert"
                )
            ),
            to: &state
        )
    }

    private func applySearch(
        _ output: SearchGraphOutput,
        resultState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        let validIDs = Set(evidence.map(\.id))
        let hits = output.hits.filter { validIDs.contains($0.evidenceID) }
        var references: [GraphChatConversationResultReference] = []
        references.reserveCapacity(hits.count)
        for hit in hits {
            guard let node = hit.sourceReference.node?.nodeKey
                    ?? inferredNode(from: hit.sourceReference) else {
                continue
            }
            let nodeReference = makeNodeReference(
                node: node,
                label: hit.title,
                sourceReference: hit.sourceReference,
                evidenceIDs: [hit.evidenceID]
            )
            upsertNode(nodeReference, in: &state)
            upsertEntityFromNode(nodeReference, in: &state)
            references.append(
                GraphChatConversationResultReference(
                    ordinal: references.count + 1,
                    reference: .node(node),
                    label: boundedLabel(hit.title),
                    evidenceIDs: boundedEvidenceIDs([hit.evidenceID])
                )
            )
        }
        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: .search,
                state: resultState,
                entityID: nil,
                references: references,
                groupReferences: [],
                evidenceIDs: boundedEvidenceIDs(evidence.map(\.id)),
                appliedFilters: [],
                technicalDescription: boundedTechnicalDescription(
                    "Lokale Suche mit \(references.count) revalidierten Treffern"
                )
            ),
            to: &state
        )
    }

    private func applyQuery(
        plan: ValidatedGraphQueryPlan,
        result: GraphChatQueryResult,
        schemaContext: GraphSchemaContext,
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        state.lastValidatedQueryPlan = plan
        if let entity = schemaContext.aliases.entitiesByAlias.values.first(where: {
            $0.entityID == plan.entityID
        }) {
            upsertEntity(
                GraphChatConversationEntityReference(
                    entityID: entity.entityID,
                    name: boundedLabel(entity.name),
                    alias: entity.alias
                ),
                in: &state
            )
        }

        let usedFieldIDs = fieldIDs(in: plan)
        for resolution in schemaContext.aliases.fieldsByAlias.values
            .filter({ usedFieldIDs.contains($0.fieldID) })
            .sorted(by: { $0.alias.rawValue < $1.alias.rawValue }) {
            upsertField(fieldReference(from: resolution), in: &state)
        }

        let validIDs = Set(result.evidence.map(\.id))
        let rows = result.rows.filter { row in
            row.evidenceIDs.contains(where: validIDs.contains)
                || row.cells.contains(where: { validIDs.contains($0.evidenceID) })
        }
        let references = rows.enumerated().map { index, row in
            let evidenceIDs = boundedEvidenceIDs(
                row.evidenceIDs.filter(validIDs.contains)
                    + row.cells.map(\.evidenceID).filter(validIDs.contains)
            )
            let nodeReference = GraphChatConversationNodeReference(
                node: row.node,
                label: boundedLabel(row.label),
                ownerEntityID: plan.entityID,
                evidenceIDs: evidenceIDs
            )
            upsertNode(nodeReference, in: &state)
            for cell in row.cells where validIDs.contains(cell.evidenceID) {
                if let resolution = schemaContext.aliases.fieldsByAlias.values.first(where: {
                    $0.fieldID == cell.fieldID
                }) {
                    upsertField(fieldReference(from: resolution), in: &state)
                }
            }
            return GraphChatConversationResultReference(
                ordinal: index + 1,
                reference: .node(row.node),
                label: boundedLabel(row.label),
                evidenceIDs: evidenceIDs
            )
        }
        let groups = makeGroups(
            from: result.aggregation,
            evidence: result.evidence
        )
        for group in groups {
            upsertGroup(group, in: &state)
        }
        if groups.count > 1 {
            state.lastComparison = GraphChatConversationComparisonContext(
                references: groups.map { .group($0.id) },
                technicalDescription: boundedTechnicalDescription(
                    "\(groups.count) appseitig gruppierte Ergebnisgruppen"
                )
            )
        }

        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: .query,
                state: toolResultState(from: result.state),
                entityID: plan.entityID,
                references: references,
                groupReferences: groups,
                evidenceIDs: boundedEvidenceIDs(result.evidence.map(\.id)),
                appliedFilters: result.appliedFilters,
                technicalDescription: boundedTechnicalDescription(
                    queryTechnicalDescription(result)
                )
            ),
            to: &state
        )
    }

    private func applyNode(
        _ output: GetNodeOutput,
        resultState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        let validIDs = Set(evidence.map(\.id))
        guard output.evidenceIDs.contains(where: validIDs.contains) else {
            return
        }
        let centerEvidenceIDs = boundedEvidenceIDs(output.evidenceIDs.filter(validIDs.contains))
        let center = GraphChatConversationNodeReference(
            node: output.node,
            label: boundedLabel(output.label),
            ownerEntityID: output.node.kind == .entity
                ? output.node.id
                : output.owner?.entityID,
            evidenceIDs: centerEvidenceIDs
        )
        upsertNode(center, in: &state)
        upsertEntityFromNode(center, fallbackName: output.owner?.label, in: &state)

        if let entityID = center.ownerEntityID {
            for detail in output.detailValues where validIDs.contains(detail.evidenceID) {
                upsertField(
                    GraphChatConversationFieldReference(
                        fieldID: detail.fieldID,
                        entityID: entityID,
                        name: boundedLabel(detail.fieldName),
                        type: detail.fieldType,
                        unit: detail.unit.map(boundedLabel),
                        alias: nil
                    ),
                    in: &state
                )
            }
        }

        var resultReferences = [
            GraphChatConversationResultReference(
                ordinal: 1,
                reference: .node(output.node),
                label: boundedLabel(output.label),
                evidenceIDs: centerEvidenceIDs
            )
        ]
        for link in output.links where validIDs.contains(link.evidenceID) {
            let relatedNode = link.direction == .outgoing ? link.target : link.source
            let relatedLabel = link.direction == .outgoing ? link.targetLabel : link.sourceLabel
            let related = GraphChatConversationNodeReference(
                node: relatedNode,
                label: boundedLabel(relatedLabel),
                ownerEntityID: relatedNode.kind == .entity ? relatedNode.id : nil,
                evidenceIDs: boundedEvidenceIDs([link.evidenceID])
            )
            upsertNode(related, in: &state)
            upsertEntityFromNode(related, in: &state)
            resultReferences.append(
                GraphChatConversationResultReference(
                    ordinal: resultReferences.count + 1,
                    reference: .node(relatedNode),
                    label: boundedLabel(relatedLabel),
                    evidenceIDs: boundedEvidenceIDs([link.evidenceID])
                )
            )
        }

        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: .node,
                state: resultState,
                entityID: center.ownerEntityID,
                references: resultReferences,
                groupReferences: [],
                evidenceIDs: boundedEvidenceIDs(evidence.map(\.id)),
                appliedFilters: [],
                technicalDescription: boundedTechnicalDescription(
                    "Node mit \(output.detailValues.count) Feldern und \(output.links.count) Links revalidiert"
                )
            ),
            to: &state
        )
    }

    private func applyNeighbors(
        _ output: GetNeighborsOutput,
        resultState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        let validIDs = Set(evidence.map(\.id))
        let centerEvidenceIDs = boundedEvidenceIDs(output.evidenceIDs.filter(validIDs.contains))
        guard centerEvidenceIDs.isEmpty == false else {
            return
        }
        let center = GraphChatConversationNodeReference(
            node: output.center.nodeKey,
            label: boundedLabel(output.center.label),
            ownerEntityID: output.center.kind == .entity
                ? output.center.nodeKey.id
                : output.center.ownerEntityID,
            evidenceIDs: centerEvidenceIDs
        )
        upsertNode(center, in: &state)
        upsertEntityFromNode(center, in: &state)

        var references = [
            GraphChatConversationResultReference(
                ordinal: 1,
                reference: .node(output.center.nodeKey),
                label: boundedLabel(output.center.label),
                evidenceIDs: centerEvidenceIDs
            )
        ]
        for connection in output.connections where validIDs.contains(connection.evidenceID) {
            let node = GraphChatConversationNodeReference(
                node: connection.neighbor,
                label: boundedLabel(connection.neighborLabel),
                ownerEntityID: connection.neighbor.kind == .entity
                    ? connection.neighbor.id
                    : nil,
                evidenceIDs: boundedEvidenceIDs([connection.evidenceID])
            )
            upsertNode(node, in: &state)
            upsertEntityFromNode(node, in: &state)
            references.append(
                GraphChatConversationResultReference(
                    ordinal: references.count + 1,
                    reference: .node(connection.neighbor),
                    label: boundedLabel(connection.neighborLabel),
                    evidenceIDs: boundedEvidenceIDs([connection.evidenceID])
                )
            )
        }

        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: .neighbors,
                state: resultState,
                entityID: center.ownerEntityID,
                references: references,
                groupReferences: [],
                evidenceIDs: boundedEvidenceIDs(evidence.map(\.id)),
                appliedFilters: [],
                technicalDescription: boundedTechnicalDescription(
                    "Direkte Nachbarschaft mit \(max(0, references.count - 1)) revalidierten Verbindungen"
                )
            ),
            to: &state
        )
    }

    private func applyStats(
        _ output: GraphStatsOutput,
        resultState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        let validIDs = Set(evidence.map(\.id))
        let hubs = output.hubs.filter { validIDs.contains($0.evidenceID) }
        let references = hubs.enumerated().map { index, hub in
            let node = GraphChatConversationNodeReference(
                node: hub.node,
                label: boundedLabel(hub.label),
                ownerEntityID: hub.node.kind == .entity ? hub.node.id : nil,
                evidenceIDs: boundedEvidenceIDs([hub.evidenceID])
            )
            upsertNode(node, in: &state)
            upsertEntityFromNode(node, in: &state)
            return GraphChatConversationResultReference(
                ordinal: index + 1,
                reference: .node(hub.node),
                label: boundedLabel(hub.label),
                evidenceIDs: boundedEvidenceIDs([hub.evidenceID])
            )
        }
        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: .stats,
                state: resultState,
                entityID: nil,
                references: references,
                groupReferences: [],
                evidenceIDs: boundedEvidenceIDs(evidence.map(\.id)),
                appliedFilters: [],
                technicalDescription: boundedTechnicalDescription(
                    "Graph-Statistik mit \(hubs.count) revalidierten Hubs"
                )
            ),
            to: &state
        )
    }

    private func applyValidatedEvidence(
        tool: GraphChatToolKind,
        resultState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        var references: [GraphChatConversationResultReference] = []
        references.reserveCapacity(evidence.count)
        for item in evidence {
            guard let node = item.sourceReference.node?.nodeKey
                    ?? inferredNode(from: item.sourceReference) else {
                if let fieldID = item.sourceReference.fieldID {
                    references.append(
                        GraphChatConversationResultReference(
                            ordinal: references.count + 1,
                            reference: .field(fieldID),
                            label: boundedLabel(item.navigationTitle ?? item.summary),
                            evidenceIDs: boundedEvidenceIDs([item.id])
                        )
                    )
                }
                continue
            }
            let nodeReference = makeNodeReference(
                node: node,
                label: item.navigationTitle ?? item.summary,
                sourceReference: item.sourceReference,
                evidenceIDs: [item.id]
            )
            upsertNode(nodeReference, in: &state)
            upsertEntityFromNode(nodeReference, in: &state)
            references.append(
                GraphChatConversationResultReference(
                    ordinal: references.count + 1,
                    reference: .node(node),
                    label: boundedLabel(item.navigationTitle ?? item.summary),
                    evidenceIDs: boundedEvidenceIDs([item.id])
                )
            )
        }
        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: resultKind(for: tool),
                state: resultState,
                entityID: nil,
                references: references,
                groupReferences: [],
                evidenceIDs: boundedEvidenceIDs(evidence.map(\.id)),
                appliedFilters: [],
                technicalDescription: boundedTechnicalDescription(
                    "\(tool.rawValue) mit \(evidence.count) revalidierten Evidence-Einträgen"
                )
            ),
            to: &state
        )
    }

    private func applyComparison(
        references: [GraphChatConversationReference],
        technicalDescription: String,
        to state: inout GraphChatConversationState
    ) {
        let known = knownReferenceKeys(in: state)
        let resolved = deduplicated(references).filter {
            known.contains($0.stableKey)
        }
        guard resolved.isEmpty == false else {
            return
        }
        state.lastComparison = GraphChatConversationComparisonContext(
            references: Array(resolved.prefix(policy.maximumComparisonReferences)),
            technicalDescription: boundedTechnicalDescription(technicalDescription)
        )
        state.referenceTargets = GraphChatConversationReferenceTargets(
            singular: state.referenceTargets.singular,
            plural: state.referenceTargets.plural,
            ordinal: state.referenceTargets.ordinal,
            group: state.referenceTargets.group,
            compared: Array(resolved.prefix(policy.maximumComparisonReferences))
        )
    }

    private func applyTurnCompletion(
        _ completion: GraphChatConversationTurnCompletion,
        to state: inout GraphChatConversationState
    ) {
        let uniqueToolKinds = Array(Set(completion.toolKinds)).sorted {
            $0.rawValue < $1.rawValue
        }
        let resultIDs = Array(Set(completion.resultContextIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        let turn = GraphChatConversationTurnContext(
            id: completion.requestID,
            completedAt: completion.completedAt,
            toolKinds: uniqueToolKinds,
            resultContextIDs: resultIDs,
            evidenceIDs: boundedEvidenceIDs(completion.evidenceIDs),
            technicalDescription: boundedTechnicalDescription(
                "Turn abgeschlossen: \(uniqueToolKinds.count) Tools, \(resultIDs.count) Ergebnis-Kontexte, \(completion.evidenceIDs.count) Evidence-Einträge"
            )
        )
        state.turnContexts.removeAll { $0.id == turn.id }
        state.turnContexts.append(turn)
    }

    private func appendResultContext(
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

    private func updateReferenceTargets(
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
            group: groups.count == 1 ? groups.first : nil,
            compared: state.lastComparison?.references ?? []
        )
    }

    private func enforceBudgets(
        _ input: GraphChatConversationState
    ) -> GraphChatConversationStateReduction {
        var state = input
        var evicted = 0

        evicted += trimRecent(&state.turnContexts, limit: policy.maximumTurnContexts)
        evicted += trimRecent(&state.nodeReferences, limit: policy.maximumNodeReferences)
        evicted += trimRecent(&state.entityReferences, limit: policy.maximumEntityReferences)
        evicted += trimRecent(&state.fieldReferences, limit: policy.maximumFieldReferences)
        evicted += trimRecent(&state.resultContexts, limit: policy.maximumResultContexts)

        let resultContentReduction = trimResultContextContents(state.resultContexts)
        state.resultContexts = resultContentReduction.contexts
        evicted += resultContentReduction.evictedItemCount

        let retainedGroupIDs = Set(
            state.resultContexts.flatMap(\.groupReferences).map(\.id)
        )
        state.groupReferences = state.groupReferences.filter {
            retainedGroupIDs.contains($0.id)
        }

        let retainedResultIDs = Set(state.resultContexts.map(\.id))
        state.turnContexts = state.turnContexts.map { turn in
            GraphChatConversationTurnContext(
                id: turn.id,
                completedAt: turn.completedAt,
                toolKinds: turn.toolKinds,
                resultContextIDs: turn.resultContextIDs.filter(retainedResultIDs.contains),
                evidenceIDs: boundedEvidenceIDs(turn.evidenceIDs),
                technicalDescription: boundedTechnicalDescription(turn.technicalDescription)
            )
        }

        state.nodeReferences = state.nodeReferences.map { reference in
            GraphChatConversationNodeReference(
                node: reference.node,
                label: boundedLabel(reference.label),
                ownerEntityID: reference.ownerEntityID,
                evidenceIDs: boundedEvidenceIDs(reference.evidenceIDs)
            )
        }
        state.entityReferences = state.entityReferences.map { reference in
            GraphChatConversationEntityReference(
                entityID: reference.entityID,
                name: boundedLabel(reference.name),
                alias: reference.alias
            )
        }
        state.fieldReferences = state.fieldReferences.map { reference in
            GraphChatConversationFieldReference(
                fieldID: reference.fieldID,
                entityID: reference.entityID,
                name: boundedLabel(reference.name),
                type: reference.type,
                unit: reference.unit.map(boundedLabel),
                alias: reference.alias
            )
        }
        state.groupReferences = state.groupReferences.map(sanitizedGroup)

        state.referenceTargets = sanitizedTargets(state.referenceTargets, state: state)
        if let comparison = state.lastComparison {
            let known = knownReferenceKeys(in: state)
            let references = comparison.references.filter {
                known.contains($0.stableKey)
            }
            state.lastComparison = references.isEmpty
                ? nil
                : GraphChatConversationComparisonContext(
                    references: Array(references.prefix(policy.maximumComparisonReferences)),
                    technicalDescription: boundedTechnicalDescription(
                        comparison.technicalDescription
                    )
                )
        }
        state.budgetEvictionCount += evicted
        return GraphChatConversationStateReduction(
            state: state,
            evictedItemCount: evicted
        )
    }

    private func trimResultContextContents(
        _ contexts: [GraphChatConversationResultContext]
    ) -> (contexts: [GraphChatConversationResultContext], evictedItemCount: Int) {
        var remainingResultReferences = policy.maximumResultReferences
        var remainingGroupReferences = policy.maximumGroupReferences
        var reversed: [GraphChatConversationResultContext] = []
        var evicted = 0

        for context in contexts.reversed() {
            let retainedReferences = Array(
                context.references.prefix(remainingResultReferences)
            )
            let retainedGroups = Array(
                context.groupReferences.prefix(remainingGroupReferences)
            ).map(sanitizedGroup)
            evicted += max(0, context.references.count - retainedReferences.count)
            evicted += max(0, context.groupReferences.count - retainedGroups.count)
            remainingResultReferences = max(
                0,
                remainingResultReferences - retainedReferences.count
            )
            remainingGroupReferences = max(
                0,
                remainingGroupReferences - retainedGroups.count
            )
            reversed.append(
                GraphChatConversationResultContext(
                    id: context.id,
                    kind: context.kind,
                    state: context.state,
                    entityID: context.entityID,
                    references: retainedReferences,
                    groupReferences: retainedGroups,
                    evidenceIDs: boundedEvidenceIDs(context.evidenceIDs),
                    appliedFilters: context.appliedFilters,
                    technicalDescription: boundedTechnicalDescription(
                        context.technicalDescription
                    )
                )
            )
        }
        return (Array(reversed.reversed()), evicted)
    }

    private func sanitizedGroup(
        _ group: GraphChatConversationGroupReference
    ) -> GraphChatConversationGroupReference {
        GraphChatConversationGroupReference(
            id: group.id,
            fieldID: group.fieldID,
            fieldName: group.fieldName.map(boundedLabel),
            valueDescription: boundedLabel(group.valueDescription),
            count: group.count,
            evidenceIDs: boundedEvidenceIDs(group.evidenceIDs),
            memberNodes: Array(
                group.memberNodes.prefix(policy.maximumResultReferences)
            )
        )
    }

    private func trimRecent<T>(
        _ values: inout [T],
        limit: Int
    ) -> Int {
        guard values.count > limit else {
            return 0
        }
        let evicted = values.count - limit
        values = Array(values.suffix(limit))
        return evicted
    }

    private func upsertNode(
        _ reference: GraphChatConversationNodeReference,
        in state: inout GraphChatConversationState
    ) {
        state.nodeReferences.removeAll { $0.node == reference.node }
        state.nodeReferences.append(reference)
    }

    private func upsertEntity(
        _ reference: GraphChatConversationEntityReference,
        in state: inout GraphChatConversationState
    ) {
        state.entityReferences.removeAll { $0.entityID == reference.entityID }
        state.entityReferences.append(reference)
    }

    private func upsertField(
        _ reference: GraphChatConversationFieldReference,
        in state: inout GraphChatConversationState
    ) {
        state.fieldReferences.removeAll { $0.fieldID == reference.fieldID }
        state.fieldReferences.append(reference)
    }

    private func upsertGroup(
        _ reference: GraphChatConversationGroupReference,
        in state: inout GraphChatConversationState
    ) {
        state.groupReferences.removeAll { $0.id == reference.id }
        state.groupReferences.append(reference)
    }

    private func upsertEntityFromNode(
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
        let name = fallbackName
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

    private func makeNodeReference(
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

    private func fieldReference(
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

    private func fieldIDs(in plan: ValidatedGraphQueryPlan) -> Set<UUID> {
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

    private func makeGroups(
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
            let members = validIDs.compactMap { evidenceID in
                evidenceByID[evidenceID]?.sourceReference.node?.nodeKey
                    ?? evidenceByID[evidenceID].flatMap {
                        inferredNode(from: $0.sourceReference)
                    }
            }
            let valueDescription = valueDescription(group.value)
            let stableID = [
                aggregation.fieldID?.uuidString ?? "none",
                GraphChatQueryValueFormatting.stableKey(group.value),
                String(index)
            ].joined(separator: ":")
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

    private func valueDescription(_ value: GraphChatQueryCellValue) -> String {
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

    private func queryTechnicalDescription(
        _ result: GraphChatQueryResult
    ) -> String {
        if let aggregation = result.aggregation {
            return "Validierte Query-Aggregation \(aggregation.kind.rawValue) mit \(aggregation.groups.count) Gruppen"
        }
        return "Validierte Query-Ergebnismenge mit \(result.rows.count) geordneten Rows"
    }

    private func resultKind(
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

    private func toolResultState(
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

    private func inferredNode(
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

    private func allows(
        _ reference: GraphChatConversationNodeReference,
        in scope: GraphChatScope
    ) -> Bool {
        switch scope.target {
        case .graph:
            return false
        case .entity(let entityID):
            return reference.node == NodeRefKey(kind: .entity, id: entityID)
                || reference.ownerEntityID == entityID
        case .node(let node):
            return reference.node == node
        case .selection(let nodes):
            return Set(nodes).contains(reference.node)
        }
    }

    private func schemaEntityIDsAllowed(
        in state: GraphChatConversationState,
        schemaContext: GraphSchemaContext
    ) -> Set<UUID>? {
        switch state.chatScope.target {
        case .graph:
            return nil
        case .entity(let entityID):
            return [entityID]
        case .node(let node):
            if node.kind == .entity {
                return [node.id]
            }
            if let entityID = schemaContext.aliases.owningEntityID(for: node)
                ?? state.nodeReferences.first(where: { $0.node == node })?.ownerEntityID {
                return [entityID]
            }
            return []
        case .selection(let nodes):
            let entityIDs = nodes.compactMap { node -> UUID? in
                if node.kind == .entity {
                    return node.id
                }
                return schemaContext.aliases.owningEntityID(for: node)
                    ?? state.nodeReferences.first(where: { $0.node == node })?.ownerEntityID
            }
            return Set(entityIDs)
        }
    }

    private func entityIDsExplicitlyAllowed(
        by scope: GraphChatScope
    ) -> [UUID] {
        switch scope.target {
        case .graph:
            return []
        case .entity(let entityID):
            return [entityID]
        case .node(let node):
            return node.kind == .entity ? [node.id] : []
        case .selection(let nodes):
            return nodes.compactMap { $0.kind == .entity ? $0.id : nil }
        }
    }

    private func knownReferenceKeys(
        in state: GraphChatConversationState
    ) -> Set<String> {
        var keys = Set(state.nodeReferences.map {
            GraphChatConversationReference.node($0.node).stableKey
        })
        keys.formUnion(state.entityReferences.map {
            GraphChatConversationReference.entity($0.entityID).stableKey
        })
        keys.formUnion(state.fieldReferences.map {
            GraphChatConversationReference.field($0.fieldID).stableKey
        })
        keys.formUnion(state.resultContexts.map {
            GraphChatConversationReference.result($0.id).stableKey
        })
        keys.formUnion(state.resultContexts.flatMap(\.references).map {
            $0.reference.stableKey
        })
        keys.formUnion(state.resultContexts.flatMap(\.groupReferences).map {
            GraphChatConversationReference.group($0.id).stableKey
        })
        keys.formUnion(state.groupReferences.map {
            GraphChatConversationReference.group($0.id).stableKey
        })
        return keys
    }

    private func sanitizedTargets(
        _ targets: GraphChatConversationReferenceTargets,
        state: GraphChatConversationState
    ) -> GraphChatConversationReferenceTargets {
        let known = knownReferenceKeys(in: state)
        func retained(
            _ values: [GraphChatConversationReference]
        ) -> [GraphChatConversationReference] {
            deduplicated(values).filter { known.contains($0.stableKey) }
        }
        let singular = targets.singular.flatMap {
            known.contains($0.stableKey) ? $0 : nil
        }
        let group = targets.group.flatMap {
            known.contains($0.stableKey) ? $0 : nil
        }
        return GraphChatConversationReferenceTargets(
            singular: singular,
            plural: retained(targets.plural),
            ordinal: retained(targets.ordinal),
            group: group,
            compared: Array(
                retained(targets.compared).prefix(policy.maximumComparisonReferences)
            )
        )
    }

    private func deduplicated(
        _ references: [GraphChatConversationReference]
    ) -> [GraphChatConversationReference] {
        var seen = Set<String>()
        return references.filter { seen.insert($0.stableKey).inserted }
    }

    private func boundedEvidenceIDs(
        _ values: [GraphEvidenceID]
    ) -> [GraphEvidenceID] {
        var seen = Set<GraphEvidenceID>()
        return Array(
            values.filter { seen.insert($0).inserted }
                .prefix(policy.maximumEvidenceIDsPerReference)
        )
    }

    private func boundedTechnicalDescription(_ value: String) -> String {
        bounded(value, limit: policy.maximumTechnicalDescriptionLength)
    }

    private func boundedLabel(_ value: String) -> String {
        bounded(value, limit: policy.maximumLabelLength)
    }

    private func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit))
    }
}

actor GraphChatConversationStateTransaction {
    private let baseState: GraphChatConversationState
    private let reducer: GraphChatConversationStateReducer
    private var candidateState: GraphChatConversationState
    private var appliedToolKinds: [GraphChatToolKind] = []
    private var resultContextIDs: [UUID] = []

    init(
        baseState: GraphChatConversationState,
        reducer: GraphChatConversationStateReducer
    ) {
        self.baseState = baseState
        self.reducer = reducer
        self.candidateState = baseState
    }

    func apply(_ event: GraphChatConversationTrustedEvent) throws {
        let previousResultIDs = Set(candidateState.resultContexts.map(\.id))
        let reduction = try reducer.reduce(candidateState, event: event)
        candidateState = reduction.state
        if let toolKind = event.payload.toolKind {
            appliedToolKinds.append(toolKind)
        }
        let addedResultIDs = candidateState.resultContexts
            .map(\.id)
            .filter { previousResultIDs.contains($0) == false }
        resultContextIDs.append(contentsOf: addedResultIDs)
    }

    func resetToBase() {
        candidateState = baseState
        appliedToolKinds = []
        resultContextIDs = []
    }

    func snapshot() -> GraphChatConversationState {
        candidateState
    }

    func baseSnapshot() -> GraphChatConversationState {
        baseState
    }

    func finalizedState(
        requestID: UUID,
        completedAt: Date,
        validatedEvidenceIDs: [GraphEvidenceID]
    ) throws -> GraphChatConversationState {
        let event = GraphChatConversationTrustedEvent(
            id: requestID,
            graphScope: candidateState.graphScope,
            chatScope: candidateState.chatScope,
            payload: .turnCompleted(
                GraphChatConversationTurnCompletion(
                    requestID: requestID,
                    completedAt: completedAt,
                    toolKinds: appliedToolKinds,
                    resultContextIDs: resultContextIDs,
                    evidenceIDs: validatedEvidenceIDs
                )
            )
        )
        candidateState = try reducer.reduce(candidateState, event: event).state
        return candidateState
    }
}
