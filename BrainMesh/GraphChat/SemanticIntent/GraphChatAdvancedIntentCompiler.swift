//
//  GraphChatAdvancedIntentCompiler.swift
//  BrainMesh
//
//  Deterministic compiler for Node Details, Compare Nodes and Graph State.
//

import Foundation

nonisolated struct GraphChatAdvancedIntentCompiler:
    Hashable,
    Sendable
{
    private let policy: GraphChatAdvancedIntentPolicy

    init(
        policy: GraphChatAdvancedIntentPolicy = .default
    ) {
        self.policy = policy
    }

    func compile(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedFields:
            [GraphChatSemanticSelectedField],
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        currentResolvedScope:
            GraphChatResolvedConversationScope?,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?
    ) throws -> GraphChatSemanticIntentResolution {
        guard
            schemaContext.graphScope
                == providerPlan.scopeKey.graphScope,
            schemaContext.foundationalAliases
                .graphScope
                == schemaContext.graphScope
        else {
            throw GraphChatSemanticIntentResolutionError
                .invalidSchemaIdentity
        }

        switch draft.family {
        case .nodeDetails:
            return try compileNodeDetails(
                draft: draft,
                selectedFields:
                    selectedFields,
                selectedNodes: selectedNodes,
                currentResolvedScope:
                    currentResolvedScope,
                providerPlan: providerPlan,
                schemaContext: schemaContext,
                requestID: requestID,
                sourceTurnID: sourceTurnID,
                clarificationID: clarificationID
            )
        case .compareNodes:
            return try compileComparison(
                draft: draft,
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
        case .inspectGraphState:
            return try compileGraphState(
                draft: draft,
                providerPlan: providerPlan,
                schemaContext: schemaContext,
                requestID: requestID,
                sourceTurnID: sourceTurnID,
                clarificationID: clarificationID
            )
        case .findNodes, .entityList,
            .filteredCollection, .count,
            .groupCount, .refinement,
            .unrecognized, .openEnded:
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        }
    }

    private func compileNodeDetails(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedFields:
            [GraphChatSemanticSelectedField],
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        currentResolvedScope:
            GraphChatResolvedConversationScope?,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?
    ) throws -> GraphChatSemanticIntentResolution {
        let resolution = try resolveNodes(
            draft: draft,
            selectedNodes: selectedNodes,
            currentResolvedScope:
                currentResolvedScope,
            providerPlan: providerPlan,
            schemaContext: schemaContext
        )
        switch resolution {
        case .clarification(let value):
            return .clarification(value)
        case .nodes(let nodes):
            guard nodes.count == 1,
                  let node = nodes.first else {
                throw GraphChatSemanticIntentResolutionError
                    .nodeNotFound
            }
            let fields = try explicitFields(
                draft.projectionTerms,
                entityID: node.ownerEntityID,
                selectedFields: selectedFields,
                schemaContext: schemaContext,
                draft: draft
            )
            switch fields {
            case .clarification(let value):
                return .clarification(value)
            case .fields(let values):
                let binding = binding(
                    providerPlan: providerPlan,
                    requestID: requestID,
                    sourceTurnID: sourceTurnID,
                    clarificationID:
                        clarificationID
                )
                let entity = try typedEntity(
                    id: node.ownerEntityID,
                    schemaContext: schemaContext
                )
                let typedIntent =
                    try GraphChatTypedIntent(
                        version: .v1,
                        scope:
                            GraphChatTypedIntentScope(
                                graphScope:
                                    schemaContext
                                        .graphScope,
                                chatScope:
                                    providerPlan
                                        .scopeKey
                                        .chatScope,
                                queryScope:
                                    .node(
                                        node.node,
                                        in:
                                            schemaContext
                                                .graphScope
                                    )
                            ),
                        responseLanguage:
                            draft.responseLanguage,
                        binding: binding,
                        resolution:
                            resolutionMetadata(
                                draft: draft,
                                clarificationID:
                                    clarificationID
                            ),
                        expectedCardinality:
                            .zeroOrOne,
                        factExpectation:
                            .none,
                        limits: typedLimits(
                            resultLimit: 1
                        ),
                        payload: .nodeDetails(
                            GraphChatTypedNodeDetailsIntent(
                                entity: entity,
                                node: node,
                                fields: values
                            )
                        )
                    )
                return .compiled(
                    GraphChatTypedIntentAdaptation(
                        intent: typedIntent,
                        action: .nodeDetails(
                            GraphChatLocalNodeDetailsAction(
                                node: node,
                                relatedLimit:
                                    policy
                                        .nodeDetailRelatedLimit
                            )
                        )
                    )
                )
            }
        }
    }

    private func compileComparison(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedFields:
            [GraphChatSemanticSelectedField],
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        currentResolvedScope:
            GraphChatResolvedConversationScope?,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?
    ) throws -> GraphChatSemanticIntentResolution {
        let resolution = try resolveNodes(
            draft: draft,
            selectedNodes: selectedNodes,
            currentResolvedScope:
                currentResolvedScope,
            providerPlan: providerPlan,
            schemaContext: schemaContext
        )
        switch resolution {
        case .clarification(let value):
            return .clarification(value)
        case .nodes(let nodes):
            guard nodes.count >= 2 else {
                throw GraphChatSemanticIntentResolutionError
                    .nodeNotFound
            }
            guard nodes.count
                    <= policy
                        .maximumComparisonNodeCount
            else {
                throw GraphChatSemanticIntentResolutionError
                    .comparisonLimitExceeded
            }

            let binding = binding(
                providerPlan: providerPlan,
                requestID: requestID,
                sourceTurnID: sourceTurnID,
                clarificationID: clarificationID
            )
            let sameEntity =
                nodes.allSatisfy {
                    $0.node.kind == .attribute
                }
                && Set(nodes.map(\.ownerEntityID))
                    .count == 1
            let comparisonKind:
                GraphChatComparisonKind
            let features:
                [GraphChatComparisonFeature]
            let typedFields:
                [GraphChatTypedFieldIdentity]
            let queryPlan: GraphQueryPlan?
            let relatedLimit: Int

            if sameEntity,
               let entityID =
                    nodes.first?.ownerEntityID
            {
                let fieldResolution =
                    try comparisonFields(
                        draft: draft,
                        entityID: entityID,
                        selectedFields:
                            selectedFields,
                        schemaContext:
                            schemaContext
                    )
                switch fieldResolution {
                case .clarification(let value):
                    return .clarification(value)
                case .fields(let fields):
                    guard fields.isEmpty == false else {
                        throw GraphChatSemanticIntentResolutionError
                            .unsupportedCombination
                    }
                    comparisonKind =
                        .sameEntityAttributes
                    features = fields.map {
                        .field($0)
                    }
                    typedFields = fields
                    relatedLimit = 0
                    let entity = try typedEntity(
                        id: entityID,
                        schemaContext:
                            schemaContext
                    )
                    queryPlan = GraphQueryPlan(
                        entityAlias: entity.alias,
                        scope: try GraphChatScope.selection(
                            nodes.map(\.node),
                            in: schemaContext
                                .graphScope
                        ),
                        sorting: [
                            GraphQuerySort(
                                key: .nodeName,
                                direction: .ascending
                            ),
                        ],
                        projection:
                            [.nodeIdentity]
                            + fields.map {
                                .field($0.alias)
                            },
                        limit: nodes.count
                    )
                }
            } else {
                let structural = try structuralFeatures(
                    draft.projectionTerms,
                    language:
                        draft.responseLanguage
                )
                guard structural.isEmpty == false else {
                    throw GraphChatSemanticIntentResolutionError
                        .unsupportedComparison(
                            draft.responseLanguage
                        )
                }
                comparisonKind = .structural
                features = structural.map {
                    .structure($0)
                }
                typedFields = []
                queryPlan = nil
                relatedLimit =
                    policy.structuralRelatedLimit
            }

            let plan = try GraphChatComparisonPlan(
                graphScope:
                    schemaContext.graphScope,
                chatScope:
                    providerPlan.scopeKey.chatScope,
                binding: binding,
                nodes: nodes,
                kind: comparisonKind,
                features: features,
                selectionQuery: queryPlan,
                relatedLimit: relatedLimit,
                responseLanguage:
                    draft.responseLanguage,
                policy: policy
            )
            let entities = try Set(
                nodes.map(\.ownerEntityID)
            ).map {
                try typedEntity(
                    id: $0,
                    schemaContext: schemaContext
                )
            }.sorted {
                if $0.displayName != $1.displayName {
                    return $0.displayName < $1.displayName
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            let typedIntent =
                try GraphChatTypedIntent(
                    version: .v1,
                    scope:
                        GraphChatTypedIntentScope(
                            graphScope:
                                schemaContext
                                    .graphScope,
                            chatScope:
                                providerPlan
                                    .scopeKey
                                    .chatScope,
                            queryScope:
                                try GraphChatScope.selection(
                                    nodes.map(\.node),
                                    in:
                                        schemaContext
                                            .graphScope
                                )
                        ),
                    responseLanguage:
                        draft.responseLanguage,
                    binding: binding,
                    resolution:
                        resolutionMetadata(
                            draft: draft,
                            clarificationID:
                                clarificationID
                        ),
                    expectedCardinality:
                        .twoOrMore,
                    factExpectation: .none,
                    limits: typedLimits(
                        resultLimit: nodes.count
                    ),
                    payload: .compareNodes(
                        GraphChatTypedCompareNodesIntent(
                            entities: entities,
                            nodes: nodes,
                            fields: typedFields
                        )
                    )
                )
            return .compiled(
                GraphChatTypedIntentAdaptation(
                    intent: typedIntent,
                    action: .compareNodes(plan)
                )
            )
        }
    }

    private func compileGraphState(
        draft: GraphChatUntrustedSemanticIntentDraft,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?
    ) throws -> GraphChatSemanticIntentResolution {
        guard
            providerPlan.scopeKey.chatScope
                == GraphChatScope.entireGraph(
                    schemaContext.graphScope
                )
        else {
            throw GraphChatSemanticIntentResolutionError
                .graphStateRequiresEntireGraph
        }
        let binding = binding(
            providerPlan: providerPlan,
            requestID: requestID,
            sourceTurnID: sourceTurnID,
            clarificationID: clarificationID
        )
        let intent = try GraphChatTypedIntent(
            version: .v1,
            scope: GraphChatTypedIntentScope(
                graphScope:
                    schemaContext.graphScope,
                chatScope:
                    providerPlan.scopeKey
                        .chatScope,
                queryScope:
                    providerPlan.scopeKey
                        .chatScope
            ),
            responseLanguage:
                draft.responseLanguage,
            binding: binding,
            resolution:
                resolutionMetadata(
                    draft: draft,
                    clarificationID:
                        clarificationID
                ),
            expectedCardinality: .exactlyOne,
            factExpectation: .none,
            limits: typedLimits(
                resultLimit:
                    max(1, policy.graphHubLimit)
            ),
            payload: .inspectGraphState(
                GraphChatTypedInspectGraphStateIntent(
                    aspect:
                        draft.graphStateAspect
                )
            )
        )
        return .compiled(
            GraphChatTypedIntentAdaptation(
                intent: intent,
                action: .inspectGraphState(
                    GraphChatLocalGraphStateAction(
                        aspect:
                            draft.graphStateAspect,
                        hubLimit:
                            policy.graphHubLimit
                    )
                )
            )
        )
    }

    private enum NodeResolution {
        case nodes([GraphChatTypedNodeIdentity])
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private func resolveNodes(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        currentResolvedScope:
            GraphChatResolvedConversationScope?,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws -> NodeResolution {
        if draft.nodeTerms.isEmpty {
            let referenced =
                providerPlan.currentReference?
                    .nodes
                ?? currentResolvedScope?.nodes
                ?? []
            return .nodes(
                try typedNodes(
                    referenced,
                    providerPlan: providerPlan,
                    schemaContext: schemaContext
                )
            )
        }

        var resolved:
            [GraphChatTypedNodeIdentity] = []
        for (index, term) in
            draft.nodeTerms.enumerated()
        {
            let role:
                GraphChatSemanticNodeSelectionRole =
                    draft.family == .nodeDetails
                    ? .details
                    : .comparison(index)
            if let selected =
                selectedNodes.last(
                    where: { $0.role == role }
                )
            {
                guard
                    let node = try typedNode(
                        selected.node,
                        providerPlan:
                            providerPlan,
                        schemaContext:
                            schemaContext
                    )
                else {
                    throw GraphChatSemanticIntentResolutionError
                        .staleNodeSelection
                }
                resolved.append(node)
                continue
            }

            let folded = BMSearch.fold(term)
            let entityFolded = draft.entityTerm
                .map { BMSearch.fold($0) }
            let nameCandidates =
                schemaContext
                    .foundationalAliases
                    .nodesByKey.values
                    .filter {
                        BMSearch.fold(
                            $0.displayName
                        ) == folded
                    }
                    .filter { candidate in
                        guard let entityFolded else {
                            return true
                        }
                        return schemaContext
                            .foundationalAliases
                            .entity(
                                id:
                                    candidate
                                        .ownerEntityID
                            )
                            .map {
                                BMSearch.fold(
                                    $0.name
                                ) == entityFolded
                            } ?? false
                    }
                    .sorted {
                        let leftOwner =
                            schemaContext
                                .foundationalAliases
                                .entity(
                                    id:
                                        $0
                                            .ownerEntityID
                                )?.name ?? ""
                        let rightOwner =
                            schemaContext
                                .foundationalAliases
                                .entity(
                                    id:
                                        $1
                                            .ownerEntityID
                                )?.name ?? ""
                        if leftOwner != rightOwner {
                            return leftOwner < rightOwner
                        }
                        if $0.node.kind != $1.node.kind {
                            return $0.node.kind.rawValue < $1.node.kind.rawValue
                        }
                        return $0.node.id.uuidString < $1.node.id.uuidString
                    }
            let candidates =
                nameCandidates.filter {
                    nodeIsAllowed(
                        $0.node,
                        providerPlan:
                            providerPlan,
                        schemaContext:
                            schemaContext
                    )
                }
            if nameCandidates.isEmpty == false,
               candidates.isEmpty {
                throw GraphChatSemanticIntentResolutionError
                    .scopeViolation
            }
            guard candidates.isEmpty == false else {
                throw GraphChatSemanticIntentResolutionError
                    .nodeNotFound
            }
            guard candidates.count == 1 else {
                let question =
                    draft.responseLanguage
                        == .german
                    ? "Welchen Eintrag mit dem Namen „\(term)“ meinst du?"
                    : "Which entry named “\(term)” do you mean?"
                return .clarification(
                    GraphChatSemanticEntityClarification(
                        question: question,
                        candidates:
                            candidates.map {
                                candidate in
                                let owner =
                                    schemaContext
                                        .foundationalAliases
                                        .entity(
                                            id:
                                                candidate
                                                    .ownerEntityID
                                        )?.name
                                let suffix =
                                    owner.map {
                                        " · \($0)"
                                    } ?? ""
                                return GraphChatSemanticEntityCandidate(
                                    entityID:
                                        candidate
                                            .ownerEntityID,
                                    displayName:
                                        candidate
                                            .displayName
                                        + suffix,
                                    selectedNodes:
                                        selectedNodes
                                        + [
                                            GraphChatSemanticSelectedNode(
                                                role:
                                                    role,
                                                node:
                                                    candidate
                                                        .node
                                            ),
                                        ]
                                )
                            },
                        draft: draft
                    )
                )
            }
            resolved.append(
                GraphChatTypedNodeIdentity(
                    node: candidates[0].node,
                    displayName:
                        candidates[0].displayName,
                    ownerEntityID:
                        candidates[0].ownerEntityID
                )
            )
        }
        let unique = resolved.reduce(
            into: [GraphChatTypedNodeIdentity]()
        ) { partial, node in
            if partial.contains(
                where: {
                    $0.node == node.node
                }
            ) == false {
                partial.append(node)
            }
        }
        guard unique.count
                == resolved.count else {
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        }
        return .nodes(unique)
    }

    private func typedNodes(
        _ nodes: [NodeRefKey],
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws -> [GraphChatTypedNodeIdentity] {
        guard nodes.isEmpty == false else {
            throw GraphChatSemanticIntentResolutionError
                .conversationSelectionUnavailable
        }
        return try nodes.map { node in
            guard
                let typed = try typedNode(
                    node,
                    providerPlan: providerPlan,
                    schemaContext: schemaContext
                )
            else {
                throw GraphChatSemanticIntentResolutionError
                    .staleNodeSelection
            }
            return typed
        }
    }

    private func typedNode(
        _ node: NodeRefKey,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws -> GraphChatTypedNodeIdentity? {
        guard
            let resolution =
                schemaContext
                    .foundationalAliases
                    .nodesByKey[node],
            nodeIsAllowed(
                node,
                providerPlan: providerPlan,
                schemaContext: schemaContext
            )
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

    private func nodeIsAllowed(
        _ node: NodeRefKey,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) -> Bool {
        GraphChatScopeAuthorization.allows(
            scope: .node(
                node,
                in: schemaContext.graphScope
            ),
            within:
                providerPlan.scopeKey
                    .chatScope,
            aliases:
                schemaContext
                    .foundationalAliases
        )
    }

    private enum FieldResolution {
        case fields(
            [GraphChatTypedFieldIdentity]
        )
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private func explicitFields(
        _ terms: [String],
        entityID: UUID,
        selectedFields:
            [GraphChatSemanticSelectedField],
        schemaContext: GraphSchemaContext,
        draft: GraphChatUntrustedSemanticIntentDraft
    ) throws -> FieldResolution {
        try fields(
            terms,
            entityID: entityID,
            selectedFields: selectedFields,
            schemaContext: schemaContext,
            draft: draft
        )
    }

    private func comparisonFields(
        draft: GraphChatUntrustedSemanticIntentDraft,
        entityID: UUID,
        selectedFields:
            [GraphChatSemanticSelectedField],
        schemaContext: GraphSchemaContext
    ) throws -> FieldResolution {
        if draft.projectionTerms.isEmpty {
            let sorted =
                schemaContext
                    .foundationalAliases
                    .fieldsByAlias.values
                    .filter {
                        $0.entityID == entityID
                    }
                    .sorted {
                        if $0.isPinned
                            != $1.isPinned {
                            return $0.isPinned
                        }
                        if $0.sortIndex
                            != $1.sortIndex {
                            return $0.sortIndex < $1.sortIndex
                        }
                        let left =
                            BMSearch.fold(
                                $0.name
                            )
                        let right =
                            BMSearch.fold(
                                $1.name
                            )
                        if left != right {
                            return left < right
                        }
                        return $0.fieldID.uuidString < $1.fieldID.uuidString
                    }
            let selected = Array(
                sorted.prefix(
                    policy
                        .defaultComparisonFeatureCount
                )
            )
            return .fields(
                selected.map(typedField)
            )
        }
        guard draft.projectionTerms.count
                <= policy
                    .maximumComparisonFeatureCount
        else {
            throw GraphChatSemanticIntentResolutionError
                .featureLimitExceeded
        }
        return try fields(
            draft.projectionTerms,
            entityID: entityID,
            selectedFields: selectedFields,
            schemaContext: schemaContext,
            draft: draft
        )
    }

    private func fields(
        _ terms: [String],
        entityID: UUID,
        selectedFields:
            [GraphChatSemanticSelectedField],
        schemaContext: GraphSchemaContext,
        draft: GraphChatUntrustedSemanticIntentDraft
    ) throws -> FieldResolution {
        var values:
            [GraphChatTypedFieldIdentity] = []
        for (index, term) in
            terms.enumerated()
        {
            let role =
                GraphChatSemanticFieldSelectionRole
                    .projection(index)
            if let selected =
                selectedFields.last(
                    where: { $0.role == role }
                )
            {
                guard
                    let value =
                        schemaContext
                            .foundationalAliases
                            .fieldsByAlias
                            .values.first(
                                where: {
                                    $0.fieldID
                                        == selected
                                            .fieldID
                                        && $0
                                            .entityID
                                            == entityID
                                }
                            )
                else {
                    throw GraphChatSemanticIntentResolutionError
                        .staleEntitySelection
                }
                values.append(typedField(value))
                continue
            }
            let folded = BMSearch.fold(term)
            let matches =
                schemaContext
                    .foundationalAliases
                    .fieldsByAlias.values
                    .filter {
                        $0.entityID == entityID
                            && BMSearch.fold(
                                $0.name
                            ) == folded
                    }
                    .sorted {
                        $0.fieldID.uuidString < $1.fieldID.uuidString
                    }
            guard matches.isEmpty == false else {
                throw GraphChatSemanticIntentResolutionError
                    .unsupportedCombination
            }
            guard matches.count == 1 else {
                let entityName =
                    schemaContext
                        .foundationalAliases
                        .entity(id: entityID)?
                        .name ?? ""
                let question =
                    draft.responseLanguage
                        == .german
                    ? "Welches Feld „\(term)“ meinst du?"
                    : "Which “\(term)” field do you mean?"
                return .clarification(
                    GraphChatSemanticEntityClarification(
                        question: question,
                        candidates:
                            matches.map {
                                GraphChatSemanticEntityCandidate(
                                    entityID:
                                        entityID,
                                    displayName:
                                        "\($0.name) · \(entityName)",
                                    selectedFields:
                                        selectedFields
                                        + [
                                            GraphChatSemanticSelectedField(
                                                role:
                                                    role,
                                                fieldID:
                                                    $0
                                                        .fieldID
                                            ),
                                        ]
                                )
                            },
                        draft: draft
                    )
                )
            }
            values.append(typedField(matches[0]))
        }
        return .fields(values)
    }

    private func structuralFeatures(
        _ terms: [String],
        language: GraphChatResponseLanguage
    ) throws -> [GraphChatStructuralComparisonFeature] {
        if terms.isEmpty {
            return [
                .nodeKind,
                .ownerDisplayName,
                .directLinkCount,
                .attachmentMetadataCount,
                .hasNotes,
                .authoritativeDetailValueCount,
            ]
        }
        guard terms.count
                <= policy
                    .maximumComparisonFeatureCount
        else {
            throw GraphChatSemanticIntentResolutionError
                .featureLimitExceeded
        }
        let names:
            [GraphChatStructuralComparisonFeature:
                Set<String>] = [
            .nodeKind: [
                "art", "node art", "node-art",
                "kind", "node kind",
            ],
            .ownerDisplayName: [
                "owner", "besitzer",
                "übergeordnete entity",
            ],
            .directLinkCount: [
                "links", "verbindungen",
                "direkte links",
                "direct links",
            ],
            .attachmentMetadataCount: [
                "attachments", "anhänge",
                "anlagen",
            ],
            .hasNotes: [
                "notizen", "notes",
            ],
            .authoritativeDetailValueCount: [
                "detailwerte",
                "autoritative detailwerte",
                "detail values",
            ],
        ]
        return try terms.map { term in
            let folded = BMSearch.fold(term)
            guard
                let value =
                    GraphChatStructuralComparisonFeature
                        .allCases.first(
                            where: { feature in
                                names[feature]?
                                    .contains(
                                        where: { name in
                                            BMSearch.fold(name)
                                                == folded
                                        }
                                    ) == true
                            }
                        )
            else {
                throw GraphChatSemanticIntentResolutionError
                    .unsupportedComparison(
                        language
                    )
            }
            return value
        }
    }

    private func typedEntity(
        id: UUID,
        schemaContext: GraphSchemaContext
    ) throws -> GraphChatTypedEntityIdentity {
        guard
            let value =
                schemaContext
                    .foundationalAliases
                    .entity(id: id)
        else {
            throw GraphChatSemanticIntentResolutionError
                .staleEntitySelection
        }
        return GraphChatTypedEntityIdentity(
            id: value.entityID,
            alias: value.alias,
            displayName: value.name
        )
    }

    private func typedField(
        _ value: GraphSchemaFieldResolution
    ) -> GraphChatTypedFieldIdentity {
        GraphChatTypedFieldIdentity(
            id: value.fieldID,
            alias: value.alias,
            displayName: value.name,
            ownerEntityID: value.entityID,
            type: value.type,
            unit: value.unit
        )
    }

    private func binding(
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?
    ) -> GraphChatTypedIntentBinding {
        GraphChatTypedIntentBinding(
            requestID: requestID,
            conversationID:
                providerPlan.requestBaseState
                    .conversationID,
            turnID: requestID,
            sourceTurnID: sourceTurnID,
            clarificationID: clarificationID
        )
    }

    private func resolutionMetadata(
        draft: GraphChatUntrustedSemanticIntentDraft,
        clarificationID: UUID?
    ) -> GraphChatTypedIntentResolution {
        GraphChatTypedIntentResolution(
            source:
                clarificationID == nil
                ? .appSemanticResolution
                : .conversationContinuation,
            origin:
                clarificationID != nil
                ? .clarificationSelection
                : (
                    draft.conversationReference
                        == .currentSelection
                    ? .conversationReference
                    : .schemaDisplayName
                ),
            quality:
                clarificationID != nil
                ? .revalidatedClarification
                : (
                    draft.conversationReference
                        == .currentSelection
                    ? .revalidatedConversationReference
                    : .exact
                )
        )
    }

    private func typedLimits(
        resultLimit: Int
    ) -> GraphChatTypedIntentLimits {
        GraphChatTypedIntentLimits(
            resultLimit: max(1, resultLimit),
            maximumResultLimit:
                max(
                    policy
                        .maximumComparisonNodeCount,
                    max(1, resultLimit)
                ),
            maximumEvidenceCount:
                policy.maximumEvidenceCount,
            maximumArtifactCount:
                policy.maximumArtifactCount
        )
    }
}
