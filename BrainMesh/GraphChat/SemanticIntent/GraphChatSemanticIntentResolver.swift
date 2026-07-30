//
//  GraphChatSemanticIntentResolver.swift
//  BrainMesh
//
//  App-owned binding of an untrusted semantic draft to schema, scope and
//  precompiled local actions.
//

import Foundation

nonisolated enum GraphChatSemanticFieldSelectionRole:
    Hashable,
    Sendable
{
    case filter(Int)
    case sorting
    case projection(Int)
    case grouping
}

nonisolated struct GraphChatSemanticSelectedField:
    Hashable,
    Sendable
{
    let role: GraphChatSemanticFieldSelectionRole
    let fieldID: UUID
}

nonisolated enum GraphChatSemanticNodeSelectionRole:
    Hashable,
    Sendable
{
    case details
    case comparison(Int)
    case relationshipCenter
    case relationshipCounterpart
}

nonisolated enum GraphChatSemanticEntitySelectionRole:
    Hashable,
    Sendable
{
    case primary
    case relationshipCounterpart
}

nonisolated struct GraphChatSemanticSelectedNode:
    Hashable,
    Sendable
{
    let role: GraphChatSemanticNodeSelectionRole
    let node: NodeRefKey
}

nonisolated struct GraphChatSemanticIntentSelection:
    Hashable,
    Sendable
{
    let draft: GraphChatUntrustedSemanticIntentDraft
    let selectedEntityID: UUID?
    let selectedRelationshipCounterpartEntityID:
        UUID?
    let selectedFields: [GraphChatSemanticSelectedField]
    let selectedNodes: [GraphChatSemanticSelectedNode]

    init(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedEntityID: UUID?,
        selectedRelationshipCounterpartEntityID:
            UUID? = nil,
        selectedFields:
            [GraphChatSemanticSelectedField] = [],
        selectedNodes:
            [GraphChatSemanticSelectedNode] = []
    ) {
        self.draft = draft
        self.selectedEntityID = selectedEntityID
        self.selectedRelationshipCounterpartEntityID =
            selectedRelationshipCounterpartEntityID
        self.selectedFields = selectedFields
        self.selectedNodes = selectedNodes
    }
}

nonisolated struct GraphChatSemanticIntentContinuation:
    Hashable,
    Sendable
{
    let selection: GraphChatSemanticIntentSelection
    let sourceTurnID: UUID?
    let clarificationID: UUID
}

nonisolated struct GraphChatSemanticEntityCandidate:
    Hashable,
    Sendable
{
    let entityID: UUID
    let displayName: String
    let selectionRole:
        GraphChatSemanticEntitySelectionRole
    let preservedPrimaryEntityID: UUID?
    let preservedRelationshipCounterpartEntityID:
        UUID?
    let selectedFields: [GraphChatSemanticSelectedField]
    let selectedNodes: [GraphChatSemanticSelectedNode]

    init(
        entityID: UUID,
        displayName: String,
        selectionRole:
            GraphChatSemanticEntitySelectionRole =
                .primary,
        preservedPrimaryEntityID:
            UUID? = nil,
        preservedRelationshipCounterpartEntityID:
            UUID? = nil,
        selectedFields:
            [GraphChatSemanticSelectedField] = [],
        selectedNodes:
            [GraphChatSemanticSelectedNode] = []
    ) {
        self.entityID = entityID
        self.displayName = displayName
        self.selectionRole = selectionRole
        self.preservedPrimaryEntityID =
            preservedPrimaryEntityID
        self.preservedRelationshipCounterpartEntityID =
            preservedRelationshipCounterpartEntityID
        self.selectedFields = selectedFields
        self.selectedNodes = selectedNodes
    }
}

nonisolated struct GraphChatSemanticEntityClarification:
    Hashable,
    Sendable
{
    let question: String
    let candidates: [GraphChatSemanticEntityCandidate]
    let draft: GraphChatUntrustedSemanticIntentDraft
}

nonisolated enum GraphChatSemanticIntentResolution:
    Hashable,
    Sendable
{
    case compiled(GraphChatTypedIntentAdaptation)
    case clarification(GraphChatSemanticEntityClarification)
    case legacyProviderFallback
}

nonisolated enum GraphChatSemanticIntentResolutionError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case entityNotFound
    case staleEntitySelection
    case scopeViolation
    case conversationSelectionUnavailable
    case conversationSelectionMismatch
    case invalidSchemaIdentity
    case unsupportedCombination
    case nodeNotFound
    case fieldNotFound
    case staleNodeSelection
    case comparisonLimitExceeded
    case featureLimitExceeded
    case unsupportedComparison(
        GraphChatResponseLanguage
    )
    case graphStateRequiresEntireGraph

    var errorDescription: String? {
        switch self {
        case .entityNotFound:
            return "Die gemeinte Entity konnte im aktuellen Schema nicht sicher aufgelöst werden."
        case .staleEntitySelection:
            return "Die ausgewählte Entity ist im aktuellen Schema nicht mehr eindeutig gebunden."
        case .scopeViolation:
            return "Der Semantic Intent würde den autorisierten Chat-Scope erweitern."
        case .conversationSelectionUnavailable:
            return "Die gemeinte Conversation-Auswahl ist nicht mehr verfügbar."
        case .conversationSelectionMismatch:
            return "Die Conversation-Auswahl passt nicht zur gemeinten Entity."
        case .invalidSchemaIdentity:
            return "Das vollständige appseitige Schema enthält keine konsistente Identität."
        case .unsupportedCombination:
            return "Die erkannte Intent-Kombination wird lokal nicht unterstützt."
        case .nodeNotFound:
            return "Der gemeinte Node konnte im autorisierten Chat-Scope nicht eindeutig gefunden werden."
        case .fieldNotFound:
            return "Das gemeinte Feld konnte im autorisierten Chat-Scope nicht eindeutig gefunden werden."
        case .staleNodeSelection:
            return "Ein ausgewählter oder referenzierter Node ist nicht mehr aktuell."
        case .comparisonLimitExceeded:
            return "Der Vergleich enthält zu viele Nodes und muss eingegrenzt werden."
        case .featureLimitExceeded:
            return "Der Vergleich enthält zu viele Features und muss eingegrenzt werden."
        case .unsupportedComparison(let language):
            return language == .german
                ? "Für diese Nodes ist kein belegbarer gemeinsamer Vergleich verfügbar."
                : "No evidence-backed common comparison is available for these nodes."
        case .graphStateRequiresEntireGraph:
            return "Graph-Statistiken sind nur im Chat-Scope des gesamten Graphen verfügbar."
        }
    }
}

nonisolated struct GraphChatSemanticIntentResolver:
    Hashable,
    Sendable
{
    private let limitPolicy:
        GraphChatSemanticIntentLimitPolicy
    private let mentionResolver:
        GraphMentionResolver
    private let queryCompiler:
        GraphChatQueryIntentCompiler
    private let advancedCompiler:
        GraphChatAdvancedIntentCompiler
    private let relationshipCompiler:
        GraphChatRelationshipIntentCompiler

    init(
        limitPolicy:
            GraphChatSemanticIntentLimitPolicy = .default,
        mentionResolver:
            GraphMentionResolver =
                GraphMentionResolver(),
        queryCompiler:
            GraphChatQueryIntentCompiler =
                GraphChatQueryIntentCompiler(
                    calendar: Calendar(
                        identifier: .gregorian
                    ),
                    timeZone:
                        TimeZone(
                            secondsFromGMT: 0
                        )!
                ),
        advancedCompiler:
            GraphChatAdvancedIntentCompiler =
                GraphChatAdvancedIntentCompiler(),
        relationshipCompiler:
            GraphChatRelationshipIntentCompiler =
                GraphChatRelationshipIntentCompiler()
    ) {
        self.limitPolicy = limitPolicy
        self.mentionResolver = mentionResolver
        self.queryCompiler = queryCompiler
        self.advancedCompiler = advancedCompiler
        self.relationshipCompiler =
            relationshipCompiler
    }

    func resolve(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedEntityID: UUID?,
        selectedRelationshipCounterpartEntityID:
            UUID? = nil,
        selectedFields:
            [GraphChatSemanticSelectedField] = [],
        selectedNodes:
            [GraphChatSemanticSelectedNode] = [],
        currentResolvedScope:
            GraphChatResolvedConversationScope?,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?,
        referenceDate: Date =
            Date(
                timeIntervalSinceReferenceDate: 0
            )
    ) throws -> GraphChatSemanticIntentResolution {
        guard
            schemaContext.graphScope
                == providerPlan.scopeKey.graphScope,
            schemaContext.foundationalAliases.graphScope
                == schemaContext.graphScope
        else {
            throw GraphChatSemanticIntentResolutionError
                .invalidSchemaIdentity
        }

        switch draft.family {
        case .unrecognized, .openEnded:
            return .legacyProviderFallback
        case .entityList, .filteredCollection,
            .count, .groupCount, .refinement:
            let executionSchemaContext =
                GraphSchemaContext(
                    graphScope:
                        schemaContext.graphScope,
                    snapshot:
                        schemaContext.snapshot,
                    aliases:
                        schemaContext
                            .foundationalAliases
                )
            do {
                let result = try queryCompiler.compile(
                    draft: draft,
                    selectedEntityID:
                        selectedEntityID,
                    selectedFields:
                        selectedFields,
                    currentResolvedScope:
                        currentResolvedScope,
                    providerPlan: providerPlan,
                    schemaContext:
                        executionSchemaContext,
                    requestID: requestID,
                    sourceTurnID:
                        sourceTurnID,
                    clarificationID:
                        clarificationID,
                    referenceDate:
                        referenceDate
                )
                switch result {
                case .compiled(let adaptation):
                    return .compiled(adaptation)
                case .clarification(
                    let clarification
                ):
                    return .clarification(
                        clarification
                    )
                }
            } catch let error
                as GraphChatQueryIntentCompilationError {
                throw mappedQueryCompilationError(
                    error
                )
            }
        case .nodeDetails, .compareNodes,
            .inspectGraphState:
            return try advancedCompiler.compile(
                draft: draft,
                selectedEntityID:
                    selectedEntityID,
                selectedFields: selectedFields,
                selectedNodes: selectedNodes,
                currentResolvedScope:
                    currentResolvedScope,
                providerPlan: providerPlan,
                schemaContext: schemaContext,
                requestID: requestID,
                sourceTurnID: sourceTurnID,
                clarificationID: clarificationID
            )
        case .relationships:
            return try relationshipCompiler.compile(
                draft: draft,
                selectedEntityID:
                    selectedEntityID,
                selectedRelationshipCounterpartEntityID:
                    selectedRelationshipCounterpartEntityID,
                selectedNodes:
                    selectedNodes,
                providerPlan:
                    providerPlan,
                schemaContext:
                    schemaContext,
                requestID:
                    requestID,
                sourceTurnID:
                    sourceTurnID,
                clarificationID:
                    clarificationID
            )
        case .findNodes:
            break
        }

        let entityResolution = try resolveEntity(
            term: draft.entityTerm,
            selectedEntityID: selectedEntityID,
            draft: draft,
            chatScope: providerPlan.scopeKey.chatScope,
            conversationEntityID:
                draft.conversationReference
                    == .currentSelection
                ? currentResolvedScope?.entityID
                : nil,
            schemaContext: schemaContext
        )
        switch entityResolution {
        case .clarification(let clarification):
            return .clarification(clarification)
        case .resolved(
            let entity,
            let mentionResolution
        ):
            let effectiveScope = try effectiveScope(
                entityID: entity?.entityID,
                conversationReference:
                    draft.conversationReference,
                currentResolvedScope:
                    currentResolvedScope,
                chatScope:
                    providerPlan.scopeKey.chatScope,
                aliases:
                    schemaContext.foundationalAliases
            )
            let executionSchemaContext =
                GraphSchemaContext(
                    graphScope:
                        schemaContext.graphScope,
                    snapshot: schemaContext.snapshot,
                    aliases:
                        schemaContext
                            .foundationalAliases
                )
            let adaptation = try adaptation(
                draft: draft,
                entity: entity,
                mentionResolution:
                    mentionResolution,
                effectiveScope: effectiveScope,
                usesConversationSelection:
                    currentResolvedScope != nil,
                providerPlan: providerPlan,
                schemaContext: executionSchemaContext,
                requestID: requestID,
                sourceTurnID: sourceTurnID,
                clarificationID: clarificationID
            )
            return .compiled(adaptation)
        }
    }

    private enum EntityResolution {
        case resolved(
            GraphSchemaEntityResolution?,
            GraphMentionResolution?
        )
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private func resolveEntity(
        term: String?,
        selectedEntityID: UUID?,
        draft: GraphChatUntrustedSemanticIntentDraft,
        chatScope: GraphChatScope,
        conversationEntityID: UUID?,
        schemaContext: GraphSchemaContext
    ) throws -> EntityResolution {
        guard let term else {
            guard selectedEntityID == nil else {
                throw GraphChatSemanticIntentResolutionError
                    .staleEntitySelection
            }
            return .resolved(nil, nil)
        }
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: term,
                kind: .entity,
                language: draft.responseLanguage,
                graphScope: schemaContext.graphScope,
                catalog: GraphMentionCatalog(
                    schemaContext: schemaContext
                ),
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: chatScope,
                        allowedEntityIDs:
                            selectedEntityID.map {
                                Set([$0])
                            },
                        conversationEntityID:
                            conversationEntityID
                    )
            )
        )
        switch result {
        case .success(let resolution):
            guard case .entity(let entity) =
                    resolution.candidate.identity else {
                throw GraphChatSemanticIntentResolutionError
                    .invalidSchemaIdentity
            }
            return .resolved(entity, resolution)
        case .failure(.ambiguous(let alternatives)):
            let candidates = alternatives.compactMap {
                alternative
                    -> GraphSchemaEntityResolution? in
                guard case .entity(let entity) =
                        alternative.candidate.identity else {
                    return nil
                }
                return entity
            }
            guard candidates.isEmpty == false else {
                throw GraphChatSemanticIntentResolutionError
                    .invalidSchemaIdentity
            }
            let question =
                draft.responseLanguage == .german
                ? "Welchen fachlichen Eintrag meinst du?"
                : "Which domain item do you mean?"
            return .clarification(
                GraphChatSemanticEntityClarification(
                    question: question,
                    candidates: candidates.map {
                        GraphChatSemanticEntityCandidate(
                            entityID: $0.entityID,
                            displayName: $0.name
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
        case .failure(.noCandidates),
            .failure(.emptyMention),
            .failure(.notFound):
            throw GraphChatSemanticIntentResolutionError
                .entityNotFound
        }
    }

    private func effectiveScope(
        entityID: UUID?,
        conversationReference:
            GraphChatSemanticConversationReference,
        currentResolvedScope:
            GraphChatResolvedConversationScope?,
        chatScope: GraphChatScope,
        aliases: GraphSchemaAliasMap
    ) throws -> GraphChatScope {
        if conversationReference == .currentSelection
            || currentResolvedScope != nil
        {
            guard let currentResolvedScope else {
                throw GraphChatSemanticIntentResolutionError
                    .conversationSelectionUnavailable
            }
            guard
                currentResolvedScope.graphScope
                    == chatScope.graphScope,
                currentResolvedScope.chatScope == chatScope
            else {
                throw GraphChatSemanticIntentResolutionError
                    .scopeViolation
            }
            if let entityID {
                guard
                    currentResolvedScope.entityID
                        == entityID
                else {
                    throw GraphChatSemanticIntentResolutionError
                        .conversationSelectionMismatch
                }
            }
            return try scope(
                for: currentResolvedScope.nodes,
                graphScope: chatScope.graphScope
            )
        }

        guard let entityID else {
            return chatScope
        }
        switch chatScope.target {
        case .graph:
            return .entity(
                entityID,
                in: chatScope.graphScope
            )
        case .entity(let scopedEntityID):
            guard scopedEntityID == entityID else {
                throw GraphChatSemanticIntentResolutionError
                    .scopeViolation
            }
            return chatScope
        case .node(let node):
            guard
                aliases.owningEntityID(for: node)
                    == entityID
            else {
                throw GraphChatSemanticIntentResolutionError
                    .scopeViolation
            }
            return chatScope
        case .selection(let nodes):
            let matchingNodes = nodes.filter {
                aliases.owningEntityID(for: $0)
                    == entityID
            }
            guard matchingNodes.isEmpty == false else {
                throw GraphChatSemanticIntentResolutionError
                    .scopeViolation
            }
            return try scope(
                for: matchingNodes,
                graphScope: chatScope.graphScope
            )
        }
    }

    private func scope(
        for nodes: [NodeRefKey],
        graphScope: GraphScope
    ) throws -> GraphChatScope {
        let unique = Array(Set(nodes)).sorted {
            if $0.kind.rawValue != $1.kind.rawValue {
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        guard unique.isEmpty == false else {
            throw GraphChatSemanticIntentResolutionError
                .conversationSelectionUnavailable
        }
        if unique.count == 1 {
            return .node(unique[0], in: graphScope)
        }
        return try .selection(unique, in: graphScope)
    }

    private func adaptation(
        draft: GraphChatUntrustedSemanticIntentDraft,
        entity: GraphSchemaEntityResolution?,
        mentionResolution:
            GraphMentionResolution?,
        effectiveScope: GraphChatScope,
        usesConversationSelection: Bool,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?
    ) throws -> GraphChatTypedIntentAdaptation {
        let binding = GraphChatTypedIntentBinding(
            requestID: requestID,
            conversationID:
                providerPlan.requestBaseState
                    .conversationID,
            turnID: requestID,
            sourceTurnID: sourceTurnID,
            clarificationID: clarificationID
        )
        let source:
            GraphChatTypedIntentResolutionSource =
            clarificationID == nil
            ? .appSemanticResolution
            : .conversationContinuation
        let origin:
            GraphChatTypedIntentResolutionOrigin
        if clarificationID != nil {
            origin = .clarificationSelection
        } else if usesConversationSelection {
            origin = .conversationReference
        } else if entity != nil {
            origin = .schemaDisplayName
        } else {
            origin = .appRule
        }
        let resolutionQuality:
            GraphChatTypedIntentResolutionQuality
        if clarificationID != nil {
            resolutionQuality =
                .revalidatedClarification
        } else if usesConversationSelection {
            resolutionQuality =
                .revalidatedConversationReference
        } else if let mentionResolution {
            resolutionQuality =
                mentionResolution
                    .isDirectDisplayBinding
                ? .exact
                : .constrainedSynonym
        } else {
            resolutionQuality = .exact
        }
        let resolution = GraphChatTypedIntentResolution(
            source: source,
            origin: origin,
            quality: resolutionQuality
        )
        let scope = GraphChatTypedIntentScope(
            graphScope:
                providerPlan.scopeKey.graphScope,
            chatScope:
                providerPlan.scopeKey.chatScope,
            queryScope: effectiveScope
        )
        let typedEntity = entity.map {
            GraphChatTypedEntityIdentity(
                id: $0.entityID,
                alias: $0.alias,
                displayName: $0.name
            )
        }

        switch draft.family {
        case .findNodes:
            let limit = limitPolicy.findLimit(
                for: draft.resultAmount
            )
            let nodeScope = typedNodeScope(
                in: effectiveScope,
                entityID: entity?.entityID,
                schemaContext: schemaContext
            )
            let intent = try GraphChatTypedIntent(
                version: .v1,
                scope: scope,
                responseLanguage:
                    draft.responseLanguage,
                binding: binding,
                resolution: resolution,
                expectedCardinality: .zeroOrMore,
                factExpectation: .none,
                limits: GraphChatTypedIntentLimits(
                    resultLimit: limit,
                    maximumResultLimit:
                        SearchGraphTool
                            .maximumResultCount,
                    maximumEvidenceCount: limit,
                    maximumArtifactCount: 1
                ),
                payload: .findNodes(
                    GraphChatTypedFindNodesIntent(
                        entity: typedEntity,
                        fields: [],
                        nodeScope: nodeScope
                    )
                )
            )
            guard let searchTerm = draft.searchTerm else {
                throw GraphChatSemanticIntentResolutionError
                    .unsupportedCombination
            }
            return GraphChatTypedIntentAdaptation(
                intent: intent,
                action: .searchGraph(
                    GraphChatLocalSearchAction(
                        query: searchTerm,
                        limit: limit,
                        scope: effectiveScope,
                        target: searchTarget(
                            draft.findTarget
                        ),
                        entityID: entity?.entityID
                    )
                )
            )

        case .entityList:
            guard let typedEntity else {
                throw GraphChatSemanticIntentResolutionError
                    .unsupportedCombination
            }
            let limit = limitPolicy.entityListLimit(
                for: draft.resultAmount
            )
            let intent = try GraphChatTypedIntent(
                version: .v1,
                scope: scope,
                responseLanguage:
                    draft.responseLanguage,
                binding: binding,
                resolution: resolution,
                expectedCardinality: .zeroOrMore,
                factExpectation: .none,
                limits: GraphChatTypedIntentLimits(
                    resultLimit: limit,
                    maximumResultLimit:
                        GraphQueryPlanLimits
                            .maximumResultLimit,
                    maximumEvidenceCount: limit,
                    maximumArtifactCount: 1
                ),
                payload: .entityCollection(
                    GraphChatTypedEntityCollectionIntent(
                        entity: typedEntity,
                        projectedFields: []
                    )
                )
            )
            return GraphChatTypedIntentAdaptation(
                intent: intent,
                action: .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan: GraphQueryPlan(
                            entityAlias:
                                typedEntity.alias,
                            scope: effectiveScope,
                            filters: [],
                            sorting: [
                                GraphQuerySort(
                                    key: .nodeName,
                                    direction:
                                        .ascending
                                )
                            ],
                            projection:
                                [.nodeIdentity],
                            aggregation: nil,
                            limit: limit
                        ),
                        resultContract:
                            .entityCollection
                    )
                )
            )

        case .unrecognized, .openEnded:
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        case .filteredCollection, .count,
            .groupCount, .refinement,
            .nodeDetails, .compareNodes,
            .inspectGraphState,
            .relationships:
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        }
    }

    private func typedNodeScope(
        in scope: GraphChatScope,
        entityID: UUID?,
        schemaContext: GraphSchemaContext
    ) -> [GraphChatTypedNodeIdentity] {
        guard let entityID else {
            return []
        }
        return scope.nodeReferences.compactMap { node in
            guard
                let resolution =
                    schemaContext.aliases
                        .nodesByKey[node],
                resolution.ownerEntityID == entityID
            else {
                return nil
            }
            return GraphChatTypedNodeIdentity(
                node: node,
                displayName:
                    resolution.displayName,
                ownerEntityID:
                    resolution.ownerEntityID
            )
        }
    }

    private func searchTarget(
        _ target: GraphChatSemanticFindTarget
    ) -> GraphChatLocalSearchTarget {
        switch target {
        case .anyEntry:
            return .anyEntry
        case .entities:
            return .entities
        case .attributes:
            return .attributes
        case .entityNodes:
            return .entityNodes
        }
    }

    private func mappedQueryCompilationError(
        _ error: GraphChatQueryIntentCompilationError
    ) -> Error {
        switch error {
        case .entityNotFound:
            return GraphChatSemanticIntentResolutionError
                .entityNotFound
        case .staleSelection:
            return GraphChatSemanticIntentResolutionError
                .staleEntitySelection
        case .scopeExpansionPrevented:
            return GraphChatSemanticIntentResolutionError
                .scopeViolation
        case .unsupportedFamily:
            return GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        case .fieldNotFound, .fieldEntityMismatch,
            .typeConflict, .valueParsingRejected,
            .projectionLimitExceeded,
            .staleResultSet,
            .invalidCompiledPlan:
            return error
        }
    }
}
