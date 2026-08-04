//
//  GraphChatRelationshipIntentCompiler.swift
//  BrainMesh
//
//  App-owned grounding and compilation of semantic relationship drafts.
//

import Foundation

nonisolated struct GraphChatRelationshipIntentCompiler:
    Hashable,
    Sendable
{
    private let mentionResolver: GraphMentionResolver
    private let limits: GraphChatIntentLimitPolicy

    init(
        mentionResolver:
            GraphMentionResolver =
                GraphMentionResolver(),
        limits:
            GraphChatIntentLimitPolicy =
                .default
    ) {
        self.mentionResolver = mentionResolver
        self.limits = limits
    }

    func compile(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedEntityID: UUID?,
        selectedRelationshipCounterpartEntityID:
            UUID?,
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?,
        mentionCatalog: GraphMentionCatalog? = nil
    ) throws -> GraphChatSemanticIntentResolution {
        guard draft.family == .relationships else {
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        }
        guard schemaContext.graphScope
                == providerPlan
                    .scopeKey.graphScope,
              schemaContext.foundationalAliases
                .graphScope
                == schemaContext.graphScope else {
            throw GraphChatSemanticIntentResolutionError
                .invalidSchemaIdentity
        }
        if draft.conversationReference
            == .currentSelection {
            return try compileContinuation(
                draft: draft,
                providerPlan: providerPlan,
                schemaContext: schemaContext,
                requestID: requestID,
                clarificationID: clarificationID
            )
        }

        let catalog = mentionCatalog ?? GraphMentionCatalog(
            schemaContext: schemaContext
        )
        let centerEntityOutcome =
            try resolveEntity(
                term: draft.entityTerm,
                selectedID: selectedEntityID,
                role: .primary,
                chatScope:
                    providerPlan.scopeKey
                        .chatScope,
                preservedPrimaryEntityID:
                    selectedEntityID,
                preservedCounterpartEntityID:
                    selectedRelationshipCounterpartEntityID,
                selectedNodes: selectedNodes,
                draft: draft,
                catalog: catalog,
                schemaContext: schemaContext
            )
        let centerEntity:
            GraphSchemaEntityResolution?
        switch centerEntityOutcome {
        case .resolved(let value):
            centerEntity = value
        case .clarification(let clarification):
            return .clarification(clarification)
        }

        guard let centerTerm = draft.nodeTerms.first else {
            throw GraphChatSemanticIntentResolutionError
                .nodeNotFound
        }
        let selectedCenter = selectedNodes.first {
            $0.role == .relationshipCenter
        }?.node
        let centerOutcome = try resolveNode(
            term: centerTerm,
            selectedNode: selectedCenter,
            role: .relationshipCenter,
            ownerEntityID:
                centerEntity?.entityID,
            chatScope:
                providerPlan.scopeKey.chatScope,
            primaryEntityID:
                centerEntity?.entityID
                ?? selectedEntityID,
            counterpartEntityID:
                selectedRelationshipCounterpartEntityID,
            selectedNodes: selectedNodes,
            draft: draft,
            catalog: catalog,
            schemaContext: schemaContext
        )
        let centerResolution:
            GraphSchemaNodeResolution
        switch centerOutcome {
        case .resolved(let value):
            centerResolution = value
        case .clarification(let clarification):
            return .clarification(clarification)
        }
        let resolvedCenterEntity =
            try typedEntity(
                id:
                    centerResolution
                        .ownerEntityID,
                schemaContext:
                    schemaContext
            )
        if let centerEntity,
           centerEntity.entityID
            != resolvedCenterEntity.id {
            throw GraphChatSemanticIntentResolutionError
                .scopeViolation
        }

        let counterpartEntityOutcome =
            try resolveEntity(
                term:
                    draft
                        .relationshipCounterpartEntityTerm,
                selectedID:
                    selectedRelationshipCounterpartEntityID,
                role: .relationshipCounterpart,
                chatScope:
                    .entireGraph(
                        schemaContext.graphScope
                    ),
                preservedPrimaryEntityID:
                    resolvedCenterEntity.id,
                preservedCounterpartEntityID:
                    selectedRelationshipCounterpartEntityID,
                selectedNodes: selectedNodes,
                draft: draft,
                catalog: catalog,
                schemaContext: schemaContext
            )
        var counterpartEntity:
            GraphSchemaEntityResolution?
        switch counterpartEntityOutcome {
        case .resolved(let value):
            counterpartEntity = value
        case .clarification(let clarification):
            return .clarification(clarification)
        }

        var counterpartResolution:
            GraphSchemaNodeResolution?
        if draft.nodeTerms.count == 2 {
            let selectedCounterpart =
                selectedNodes.first {
                    $0.role
                        == .relationshipCounterpart
                }?.node
            let outcome = try resolveNode(
                term: draft.nodeTerms[1],
                selectedNode:
                    selectedCounterpart,
                role:
                    .relationshipCounterpart,
                ownerEntityID:
                    counterpartEntity?
                        .entityID,
                chatScope:
                    .entireGraph(
                        schemaContext.graphScope
                    ),
                primaryEntityID:
                    resolvedCenterEntity.id,
                counterpartEntityID:
                    counterpartEntity?.entityID,
                selectedNodes:
                    selectedNodes,
                draft: draft,
                catalog: catalog,
                schemaContext:
                    schemaContext
            )
            switch outcome {
            case .resolved(let value):
                counterpartResolution = value
            case .clarification(let clarification):
                return .clarification(
                    clarification
                )
            }
            guard let counterpartResolution else {
                throw GraphChatSemanticIntentResolutionError
                    .nodeNotFound
            }
            if let counterpartEntity {
                guard
                    counterpartResolution
                        .ownerEntityID
                        == counterpartEntity
                            .entityID
                else {
                    throw GraphChatSemanticIntentResolutionError
                        .scopeViolation
                }
            } else {
                counterpartEntity =
                    schemaContext
                        .foundationalAliases
                        .entity(
                            id:
                                counterpartResolution
                                    .ownerEntityID
                        )
            }
        }

        let typedCenterNode =
            typedNode(centerResolution)
        let typedCounterpartEntity =
            try counterpartEntity.map {
                try typedEntity(
                    $0
                )
            }
        let typedCounterpartNode =
            counterpartResolution.map(
                typedNode
            )
        let request = relationshipRequest(
            draft.relationshipRequest
        )
        let direction =
            request
                == .linkNotesBetweenNodes
            ? GraphChatRelationshipDirection.both
            : relationshipDirection(
                draft.relationshipDirection
            )
        let notePredicate = try notePredicate(
            draft
        )
        let binding =
            GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID:
                    providerPlan
                        .requestBaseState
                        .conversationID,
                turnID: requestID,
                sourceTurnID:
                    sourceTurnID,
                clarificationID:
                    clarificationID
            )
        let intentLimits =
            relationshipLimits()
        let queryScope = GraphChatScope.node(
            typedCenterNode.node,
            in: schemaContext.graphScope
        )
        let plan = try GraphChatRelationshipPlan(
            graphScope:
                schemaContext.graphScope,
            chatScope:
                providerPlan.scopeKey
                    .chatScope,
            queryScope: queryScope,
            binding: binding,
            request: request,
            centerEntity:
                resolvedCenterEntity,
            centerNode:
                typedCenterNode,
            direction: direction,
            counterpartEntity:
                typedCounterpartEntity,
            counterpartNode:
                typedCounterpartNode,
            notePredicate:
                notePredicate,
            limits: intentLimits,
            responseLanguage:
                draft.responseLanguage
        )
        return .compiled(
            try adaptation(
                plan: plan,
                intentLimits: intentLimits,
                source:
                    clarificationID == nil
                    ? .appSemanticResolution
                    : .conversationContinuation,
                origin:
                    clarificationID == nil
                    ? .schemaDisplayName
                    : .clarificationSelection,
                quality:
                    clarificationID == nil
                    ? .exact
                    : .revalidatedClarification
            )
        )
    }

    private func compileContinuation(
        draft: GraphChatUntrustedSemanticIntentDraft,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        clarificationID: UUID?
    ) throws -> GraphChatSemanticIntentResolution {
        guard
            let previous =
                providerPlan
                    .requestBaseState
                    .lastRelationship,
            previous.plan.graphScope
                == schemaContext.graphScope,
            previous.plan.chatScope
                == providerPlan.scopeKey
                    .chatScope,
            providerPlan.requestBaseState
                .resultContexts.contains(
                    where: {
                        $0.id
                            == previous
                                .resultContextID
                        && $0.kind
                            == .relationship
                    }
                ),
            providerPlan.requestBaseState
                .turnContexts.contains(
                    where: {
                        $0.id
                            == previous.sourceTurnID
                    }
                )
        else {
            throw GraphChatSemanticIntentResolutionError
                .conversationSelectionUnavailable
        }
        let aliases =
            schemaContext.foundationalAliases
        guard
            let centerResolution =
                aliases.nodesByKey[
                    previous
                        .plan.centerNode.node
                ],
            centerResolution.ownerEntityID
                == previous
                    .plan.centerEntity.id,
            GraphChatScopeAuthorization.allows(
                scope: .node(
                    centerResolution.node,
                    in:
                        schemaContext
                            .graphScope
                ),
                within:
                    providerPlan
                        .scopeKey.chatScope,
                aliases: aliases
            )
        else {
            throw GraphChatSemanticIntentResolutionError
                .staleNodeSelection
        }
        let centerEntity =
            try typedEntity(
                id:
                    centerResolution
                        .ownerEntityID,
                schemaContext:
                    schemaContext
            )
        let counterpartNode:
            GraphChatTypedNodeIdentity?
        let counterpartEntity:
            GraphChatTypedEntityIdentity?
        if let previousCounterpartNode =
                previous.plan.counterpartNode {
            guard
                let resolution =
                    aliases.nodesByKey[
                        previousCounterpartNode
                            .node
                    ],
                resolution.ownerEntityID
                    == previousCounterpartNode
                        .ownerEntityID
            else {
                throw GraphChatSemanticIntentResolutionError
                    .staleNodeSelection
            }
            counterpartNode =
                typedNode(resolution)
            counterpartEntity =
                try typedEntity(
                    id:
                        resolution
                            .ownerEntityID,
                    schemaContext:
                        schemaContext
                )
        } else if let previousEntity =
                    previous.plan.counterpartEntity {
            counterpartNode = nil
            counterpartEntity =
                try typedEntity(
                    id: previousEntity.id,
                    schemaContext:
                        schemaContext
                )
        } else {
            counterpartNode = nil
            counterpartEntity = nil
        }

        let direction:
            GraphChatRelationshipDirection
        switch draft.relationshipDirection {
        case .unspecified:
            direction =
                previous.plan.direction
        case .incoming:
            direction = .incoming
        case .outgoing:
            direction = .outgoing
        case .both:
            direction = .both
        }
        let request = relationshipRequest(
            draft.relationshipRequest
        )
        let effectiveDirection =
            request
                == .linkNotesBetweenNodes
            ? GraphChatRelationshipDirection.both
            : direction
        let explicitNotePredicate =
            try notePredicate(draft)
        let intentLimits =
            relationshipLimits()
        let binding =
            GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID:
                    providerPlan
                        .requestBaseState
                        .conversationID,
                turnID: requestID,
                sourceTurnID:
                    previous.sourceTurnID,
                clarificationID:
                    clarificationID
            )
        let centerNode =
            typedNode(centerResolution)
        let queryScope = GraphChatScope.node(
            centerNode.node,
            in: schemaContext.graphScope
        )
        let plan = try GraphChatRelationshipPlan(
            graphScope:
                schemaContext.graphScope,
            chatScope:
                providerPlan.scopeKey
                    .chatScope,
            queryScope: queryScope,
            binding: binding,
            request: request,
            centerEntity: centerEntity,
            centerNode: centerNode,
            direction:
                effectiveDirection,
            counterpartEntity:
                counterpartEntity,
            counterpartNode:
                counterpartNode,
            notePredicate:
                explicitNotePredicate
                ?? previous.plan
                    .notePredicate,
            limits: intentLimits,
            responseLanguage:
                draft.responseLanguage,
            sourceRelationshipContextID:
                previous.resultContextID
        )
        return .compiled(
            try adaptation(
                plan: plan,
                intentLimits: intentLimits,
                source:
                    .conversationContinuation,
                origin:
                    .conversationReference,
                quality:
                    .revalidatedConversationReference
            )
        )
    }

    private enum EntityOutcome {
        case resolved(
            GraphSchemaEntityResolution?
        )
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private func resolveEntity(
        term: String?,
        selectedID: UUID?,
        role:
            GraphChatSemanticEntitySelectionRole,
        chatScope: GraphChatScope,
        preservedPrimaryEntityID: UUID?,
        preservedCounterpartEntityID: UUID?,
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        draft: GraphChatUntrustedSemanticIntentDraft,
        catalog: GraphMentionCatalog,
        schemaContext: GraphSchemaContext
    ) throws -> EntityOutcome {
        guard let term else {
            guard let selectedID else {
                return .resolved(nil)
            }
            guard let entity =
                    schemaContext
                        .foundationalAliases
                        .entity(id: selectedID)
            else {
                throw GraphChatSemanticIntentResolutionError
                    .staleEntitySelection
            }
            return .resolved(entity)
        }
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: term,
                kind: .entity,
                language:
                    draft.responseLanguage,
                graphScope:
                    schemaContext.graphScope,
                catalog: catalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: chatScope,
                        allowedEntityIDs:
                            selectedID.map {
                                Set([$0])
                            }
                    )
            )
        )
        switch result {
        case .success(let resolution):
            guard case .entity(let entity) =
                    resolution
                        .candidate.identity else {
                throw GraphChatSemanticIntentResolutionError
                    .invalidSchemaIdentity
            }
            return .resolved(entity)
        case .failure(.ambiguous(let alternatives)):
            let entities = alternatives
                .compactMap {
                    alternative
                        -> GraphSchemaEntityResolution?
                    in
                    guard case .entity(let entity) =
                            alternative
                                .candidate.identity
                    else {
                        return nil
                    }
                    return entity
                }
            guard entities.isEmpty == false else {
                throw GraphChatSemanticIntentResolutionError
                    .invalidSchemaIdentity
            }
            return .clarification(
                GraphChatSemanticEntityClarification(
                    question:
                        clarificationQuestion(
                            language:
                                draft.responseLanguage
                        ),
                    candidates:
                        entities.map {
                            GraphChatSemanticEntityCandidate(
                                entityID:
                                    $0.entityID,
                                displayName:
                                    $0.name,
                                selectionRole: role,
                                preservedPrimaryEntityID:
                                    preservedPrimaryEntityID,
                                preservedRelationshipCounterpartEntityID:
                                    preservedCounterpartEntityID,
                                selectedNodes:
                                    selectedNodes
                            )
                        },
                    draft: draft
                )
            )
        case .failure(.staleSelection):
            throw GraphChatSemanticIntentResolutionError
                .staleEntitySelection
        case .failure(.scopeViolation),
            .failure(.ownerEntityMismatch):
            throw GraphChatSemanticIntentResolutionError
                .scopeViolation
        case .failure(.graphScopeMismatch):
            throw GraphChatSemanticIntentResolutionError
                .invalidSchemaIdentity
        case .failure(.emptyMention),
            .failure(.noCandidates),
            .failure(.notFound):
            throw GraphChatSemanticIntentResolutionError
                .entityNotFound
        }
    }

    private enum NodeOutcome {
        case resolved(
            GraphSchemaNodeResolution
        )
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private func resolveNode(
        term: String,
        selectedNode: NodeRefKey?,
        role: GraphChatSemanticNodeSelectionRole,
        ownerEntityID: UUID?,
        chatScope: GraphChatScope,
        primaryEntityID: UUID?,
        counterpartEntityID: UUID?,
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        draft: GraphChatUntrustedSemanticIntentDraft,
        catalog: GraphMentionCatalog,
        schemaContext: GraphSchemaContext
    ) throws -> NodeOutcome {
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: term,
                kind: .node,
                language:
                    draft.responseLanguage,
                graphScope:
                    schemaContext.graphScope,
                catalog: catalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: chatScope,
                        ownerEntityID:
                            ownerEntityID,
                        allowedNodes:
                            selectedNode.map {
                                Set([$0])
                            }
                    )
            )
        )
        switch result {
        case .success(let resolution):
            guard case .node(let node) =
                    resolution
                        .candidate.identity else {
                throw GraphChatSemanticIntentResolutionError
                    .invalidSchemaIdentity
            }
            return .resolved(node)
        case .failure(.ambiguous(let alternatives)):
            let nodes = alternatives
                .compactMap {
                    alternative
                        -> (
                            GraphSchemaNodeResolution,
                            String?
                        )?
                    in
                    guard case .node(let node) =
                            alternative
                                .candidate.identity
                    else {
                        return nil
                    }
                    return (
                        node,
                        alternative
                            .candidate
                            .ownerDisplayName
                    )
                }
            guard nodes.isEmpty == false else {
                throw GraphChatSemanticIntentResolutionError
                    .invalidSchemaIdentity
            }
            let preservedNodes =
                selectedNodes.filter {
                    $0.role != role
                }
            return .clarification(
                GraphChatSemanticEntityClarification(
                    question:
                        clarificationQuestion(
                            language:
                                draft.responseLanguage
                        ),
                    candidates:
                        nodes.map { node, owner in
                            GraphChatSemanticEntityCandidate(
                                entityID:
                                    node.ownerEntityID,
                                displayName:
                                    [
                                        node.displayName,
                                        owner,
                                    ]
                                    .compactMap { $0 }
                                    .joined(
                                        separator: " · "
                                    ),
                                selectionRole:
                                    role
                                        == .relationshipCounterpart
                                    ? .relationshipCounterpart
                                    : .primary,
                                preservedPrimaryEntityID:
                                    primaryEntityID,
                                preservedRelationshipCounterpartEntityID:
                                    counterpartEntityID,
                                selectedNodes:
                                    preservedNodes
                                    + [
                                        GraphChatSemanticSelectedNode(
                                            role: role,
                                            node: node.node
                                        ),
                                    ]
                            )
                        },
                    draft: draft
                )
            )
        case .failure(.staleSelection):
            throw GraphChatSemanticIntentResolutionError
                .staleNodeSelection
        case .failure(.scopeViolation),
            .failure(.ownerEntityMismatch):
            throw GraphChatSemanticIntentResolutionError
                .scopeViolation
        case .failure(.graphScopeMismatch):
            throw GraphChatSemanticIntentResolutionError
                .invalidSchemaIdentity
        case .failure(.emptyMention),
            .failure(.noCandidates),
            .failure(.notFound):
            throw GraphChatSemanticIntentResolutionError
                .nodeNotFound
        }
    }

    private func typedEntity(
        id: UUID,
        schemaContext: GraphSchemaContext
    ) throws -> GraphChatTypedEntityIdentity {
        guard let entity =
                schemaContext
                    .foundationalAliases
                    .entity(id: id)
        else {
            throw GraphChatSemanticIntentResolutionError
                .invalidSchemaIdentity
        }
        return try typedEntity(entity)
    }

    private func typedEntity(
        _ entity: GraphSchemaEntityResolution
    ) throws -> GraphChatTypedEntityIdentity {
        GraphChatTypedEntityIdentity(
            id: entity.entityID,
            alias: entity.alias,
            displayName: entity.name
        )
    }

    private func typedNode(
        _ node: GraphSchemaNodeResolution
    ) -> GraphChatTypedNodeIdentity {
        GraphChatTypedNodeIdentity(
            node: node.node,
            displayName:
                node.displayName,
            ownerEntityID:
                node.ownerEntityID
        )
    }

    private func relationshipRequest(
        _ request:
            GraphChatSemanticRelationshipRequest
    ) -> GraphChatRelationshipRequestKind {
        switch request {
        case .connections:
            return .connections
        case .linkNotesBetweenNodes:
            return .linkNotesBetweenNodes
        }
    }

    private func relationshipDirection(
        _ direction:
            GraphChatSemanticRelationshipDirection
    ) -> GraphChatRelationshipDirection {
        switch direction {
        case .unspecified, .both:
            return .both
        case .incoming:
            return .incoming
        case .outgoing:
            return .outgoing
        }
    }

    private func notePredicate(
        _ draft:
            GraphChatUntrustedSemanticIntentDraft
    ) throws -> GraphChatRelationshipNotePredicate? {
        switch draft.relationshipNotePredicate {
        case .unspecified:
            return nil
        case .present:
            return .present
        case .missing:
            return .missing
        case .contains:
            guard let term =
                    draft.relationshipNoteTerm else {
                throw GraphChatSemanticIntentResolutionError
                    .unsupportedCombination
            }
            return .contains(term)
        }
    }

    private func relationshipLimits()
        -> GraphChatTypedIntentLimits
    {
        GraphChatTypedIntentLimits(
            resultLimit:
                limits.nodeDetailRelatedItemCount,
            maximumResultLimit:
                limits.maximumNeighborCount,
            maximumEvidenceCount:
                limits.maximumNeighborCount + 1,
            maximumArtifactCount: 1
        )
    }

    private func adaptation(
        plan: GraphChatRelationshipPlan,
        intentLimits: GraphChatTypedIntentLimits,
        source:
            GraphChatTypedIntentResolutionSource,
        origin:
            GraphChatTypedIntentResolutionOrigin,
        quality:
            GraphChatTypedIntentResolutionQuality
    ) throws -> GraphChatTypedIntentAdaptation {
        let intent = try GraphChatTypedIntent(
            version: .v2,
            scope: GraphChatTypedIntentScope(
                graphScope: plan.graphScope,
                chatScope: plan.chatScope,
                queryScope: plan.queryScope
            ),
            responseLanguage:
                plan.responseLanguage,
            binding: plan.binding,
            resolution:
                GraphChatTypedIntentResolution(
                    source: source,
                    origin: origin,
                    quality: quality
                ),
            expectedCardinality:
                plan.expectedCardinality,
            factExpectation: .none,
            limits: intentLimits,
            payload: .relationships(plan)
        )
        return GraphChatTypedIntentAdaptation(
            intent: intent,
            action: .relationships(plan)
        )
    }

    private func clarificationQuestion(
        language: GraphChatResponseLanguage
    ) -> String {
        language == .german
            ? "Welchen fachlichen Eintrag meinst du?"
            : "Which domain item do you mean?"
    }
}
