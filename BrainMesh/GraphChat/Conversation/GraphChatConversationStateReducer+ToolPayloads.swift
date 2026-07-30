//
//  GraphChatConversationStateReducer+ToolPayloads.swift
//  BrainMesh
//
//  Trusted tool-payload application and turn completion.
//

import Foundation

nonisolated extension GraphChatConversationStateReducer {
    func applySchema(
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

    func applySearch(
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
            guard
                let node = hit.sourceReference.node?.nodeKey
                    ?? inferredNode(from: hit.sourceReference)
            else {
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

    func applyQuery(
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
            .sorted(by: { $0.alias.rawValue < $1.alias.rawValue })
        {
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

    func applyNode(
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

    func applyNeighbors(
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

    func applyRelationship(
        plan: GraphChatRelationshipPlan,
        output: GraphChatRelationshipOutput,
        resultState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        let validIDs = Set(evidence.map(\.id))
        guard
            validIDs.contains(
                output.centerEvidenceID
            )
        else {
            return
        }
        let centerEvidenceID =
            output.centerEvidenceID
        let center =
            GraphChatConversationNodeReference(
                node: output.center.nodeKey,
                label:
                    boundedLabel(
                        output.center.label
                    ),
                ownerEntityID:
                    output.center.kind
                        == .entity
                    ? output.center
                        .nodeKey.id
                    : output.center
                        .ownerEntityID,
                evidenceIDs:
                    boundedEvidenceIDs([
                        centerEvidenceID,
                    ])
            )
        upsertNode(center, in: &state)
        upsertEntityFromNode(
            center,
            fallbackName:
                plan.centerEntity
                    .displayName,
            in: &state
        )

        var orderedNodes = [NodeRefKey]()
        var labels = [NodeRefKey: String]()
        var owners = [NodeRefKey: UUID?]()
        var evidenceByNode =
            [NodeRefKey: [GraphEvidenceID]]()
        for connection in output.connections
        where validIDs.contains(
            connection.evidenceID
        ) {
            let node =
                connection.counterpart.nodeKey
            if labels[node] == nil {
                orderedNodes.append(node)
                labels[node] =
                    connection.counterpart
                        .visibleName
                owners[node] =
                    connection.counterpart.kind
                        == .entity
                    ? connection.counterpart
                        .nodeKey.id
                    : connection.counterpart
                        .ownerEntityID
            }
            evidenceByNode[node, default: []]
                .append(
                    connection.evidenceID
                )
        }
        let references = orderedNodes
            .enumerated()
            .map { index, node in
                let itemEvidence =
                    boundedEvidenceIDs(
                        evidenceByNode[node]
                            ?? []
                    )
                let label =
                    boundedLabel(
                        labels[node] ?? ""
                    )
                let reference =
                    GraphChatConversationNodeReference(
                        node: node,
                        label: label,
                        ownerEntityID:
                            owners[node] ?? nil,
                        evidenceIDs:
                            itemEvidence
                    )
                upsertNode(
                    reference,
                    in: &state
                )
                upsertEntityFromNode(
                    reference,
                    fallbackName:
                        plan
                            .counterpartEntity?
                            .displayName,
                    in: &state
                )
                return GraphChatConversationResultReference(
                    ordinal: index + 1,
                    reference: .node(node),
                    label: label,
                    evidenceIDs:
                        itemEvidence
                )
            }
        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: .relationship,
                state: resultState,
                entityID:
                    plan.counterpartEntity?.id,
                references: references,
                groupReferences: [],
                evidenceIDs:
                    boundedEvidenceIDs(
                        evidence.map(\.id)
                    ),
                appliedFilters: [],
                technicalDescription:
                    boundedTechnicalDescription(
                        "Direkte Relationship-Auswahl mit \(output.connections.count) Links, Richtung \(plan.direction.rawValue), vollständig \(output.resultWindow.totalCount != nil)"
                    )
            ),
            to: &state
        )
        state.lastRelationship =
            GraphChatConversationRelationshipContext(
                resultContextID: eventID,
                sourceTurnID:
                    plan.binding.turnID,
                plan: plan,
                resultWindow:
                    output.resultWindow
            )
    }

    func applyStats(
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

    func applyValidatedEvidence(
        tool: GraphChatToolKind,
        resultState: GraphChatToolResultState,
        evidence: [GraphEvidence],
        eventID: UUID,
        to state: inout GraphChatConversationState
    ) {
        var references: [GraphChatConversationResultReference] = []
        references.reserveCapacity(evidence.count)
        for item in evidence {
            guard
                let node = item.sourceReference.node?.nodeKey
                    ?? inferredNode(from: item.sourceReference)
            else {
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

    func applyComparison(
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

    func applyComparisonResult(
        subjects:
            [GraphChatConversationComparisonSubject],
        evidence: [GraphEvidence],
        technicalDescription: String,
        eventID: UUID,
        to state:
            inout GraphChatConversationState
    ) {
        let validIDs = Set(evidence.map(\.id))
        let validSubjects = subjects.filter {
            $0.evidenceIDs.contains(
                where: validIDs.contains
            )
        }
        guard validSubjects.count >= 2 else {
            return
        }
        let references =
            validSubjects.enumerated().map {
                index, subject in
                let evidenceIDs =
                    boundedEvidenceIDs(
                        subject.evidenceIDs
                            .filter(
                                validIDs.contains
                            )
                    )
                let nodeReference =
                    GraphChatConversationNodeReference(
                        node: subject.node,
                        label:
                            boundedLabel(
                                subject.label
                            ),
                        ownerEntityID:
                            subject.ownerEntityID,
                        evidenceIDs:
                            evidenceIDs
                    )
                upsertNode(
                    nodeReference,
                    in: &state
                )
                upsertEntityFromNode(
                    nodeReference,
                    in: &state
                )
                return GraphChatConversationResultReference(
                    ordinal: index + 1,
                    reference:
                        .node(subject.node),
                    label:
                        boundedLabel(
                            subject.label
                        ),
                    evidenceIDs:
                        evidenceIDs
                )
            }
        let entityIDs = Set(
            validSubjects.compactMap(
                \.ownerEntityID
            )
        )
        appendResultContext(
            GraphChatConversationResultContext(
                id: eventID,
                kind: .comparison,
                state: .success,
                entityID:
                    entityIDs.count == 1
                    ? entityIDs.first
                    : nil,
                references: references,
                groupReferences: [],
                evidenceIDs:
                    boundedEvidenceIDs(
                        evidence.map(\.id)
                    ),
                appliedFilters: [],
                technicalDescription:
                    boundedTechnicalDescription(
                        technicalDescription
                    )
            ),
            to: &state
        )
        applyComparison(
            references:
                references.map(\.reference),
            technicalDescription:
                technicalDescription,
            to: &state
        )
    }

    func applyTurnCompletion(
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
}
