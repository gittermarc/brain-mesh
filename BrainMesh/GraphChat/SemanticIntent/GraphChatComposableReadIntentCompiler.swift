//
//  GraphChatComposableReadIntentCompiler.swift
//  BrainMesh
//
//  App-owned grounding and plan compilation for bounded entity traversals.
//

import Foundation

nonisolated struct GraphChatComposableReadIntentCompiler:
    Hashable,
    Sendable
{
    private let mentionResolver: GraphMentionResolver
    private let limitPolicy:
        GraphChatSemanticIntentLimitPolicy
    private let policy: GraphChatIntentLimitPolicy
    private let valueParser:
        GraphChatQueryIntentValueParser

    init(
        calendar: Calendar = Calendar(
            identifier: .gregorian
        ),
        timeZone: TimeZone = TimeZone(
            secondsFromGMT: 0
        )!,
        mentionResolver: GraphMentionResolver =
            GraphMentionResolver(),
        limitPolicy:
            GraphChatSemanticIntentLimitPolicy = .default,
        policy: GraphChatIntentLimitPolicy = .default
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.mentionResolver = mentionResolver
        self.limitPolicy = limitPolicy
        self.policy = policy
        self.valueParser = GraphChatQueryIntentValueParser(
            calendar: configuredCalendar,
            timeZone: timeZone
        )
    }

    func compile(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedEntityID: UUID?,
        selectedIntermediateEntityID: UUID?,
        selectedCounterpartEntityID: UUID?,
        selectedFields:
            [GraphChatSemanticSelectedField],
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?,
        referenceDate: Date,
        mentionCatalog: GraphMentionCatalog? = nil
    ) throws -> GraphChatSemanticIntentResolution {
        guard
            draft.family == .relationships,
            draft.nodeTerms.isEmpty,
            draft.conversationReference == .none,
            let rootTerm = draft.entityTerm,
            let counterpartTerm =
                draft.relationshipCounterpartEntityTerm,
            providerPlan.scopeKey.chatScope
                == .entireGraph(schemaContext.graphScope),
            schemaContext.graphScope
                == providerPlan.scopeKey.graphScope,
            schemaContext.foundationalAliases.graphScope
                == schemaContext.graphScope
        else {
            throw GraphChatSemanticIntentResolutionError
                .scopeViolation
        }
        let catalog = mentionCatalog ?? GraphMentionCatalog(
            schemaContext: schemaContext
        )
        let rootOutcome = try resolveEntity(
            term: rootTerm,
            selectedID: selectedEntityID,
            role: .primary,
            preservedRootID: selectedEntityID,
            preservedIntermediateID:
                selectedIntermediateEntityID,
            preservedCounterpartID:
                selectedCounterpartEntityID,
            selectedFields: selectedFields,
            selectedNodes: selectedNodes,
            draft: draft,
            catalog: catalog,
            schemaContext: schemaContext
        )
        let root: GraphSchemaEntityResolution
        switch rootOutcome {
        case .resolved(let value):
            root = value
        case .clarification(let clarification):
            return .clarification(clarification)
        }

        var intermediate:
            GraphSchemaEntityResolution?
        if let intermediateTerm =
                draft.relationshipIntermediateEntityTerm {
            let outcome = try resolveEntity(
                term: intermediateTerm,
                selectedID:
                    selectedIntermediateEntityID,
                role: .composableIntermediate,
                preservedRootID: root.entityID,
                preservedIntermediateID:
                    selectedIntermediateEntityID,
                preservedCounterpartID:
                    selectedCounterpartEntityID,
                selectedFields: selectedFields,
                selectedNodes: selectedNodes,
                draft: draft,
                catalog: catalog,
                schemaContext: schemaContext
            )
            switch outcome {
            case .resolved(let value):
                intermediate = value
            case .clarification(let clarification):
                return .clarification(clarification)
            }
        } else if selectedIntermediateEntityID != nil {
            throw GraphChatSemanticIntentResolutionError
                .staleEntitySelection
        }

        let counterpartOutcome = try resolveEntity(
            term: counterpartTerm,
            selectedID: selectedCounterpartEntityID,
            role: .relationshipCounterpart,
            preservedRootID: root.entityID,
            preservedIntermediateID:
                intermediate?.entityID,
            preservedCounterpartID:
                selectedCounterpartEntityID,
            selectedFields: selectedFields,
            selectedNodes: selectedNodes,
            draft: draft,
            catalog: catalog,
            schemaContext: schemaContext
        )
        let counterpart: GraphSchemaEntityResolution
        switch counterpartOutcome {
        case .resolved(let value):
            counterpart = value
        case .clarification(let clarification):
            return .clarification(clarification)
        }
        let chain = [root]
            + (intermediate.map { [$0] } ?? [])
            + [counterpart]
        guard
            Set(chain.map(\.entityID)).count
                == chain.count,
            chain.count - 1
                <= policy
                    .maximumComposableReadTraversalHopCount
        else {
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        }
        let notePredicate = try Self.notePredicate(
            draft
        )
        let noteOwnerID = try resolvedNoteOwnerID(
            draft: draft,
            traversedEntities: Array(chain.dropFirst()),
            notePredicate: notePredicate,
            catalog: catalog,
            schemaContext: schemaContext
        )
        let counterpartNodeOutcome = try resolveCounterpartNode(
            term: draft.relationshipCounterpartNodeTerm,
            selectedNode: selectedNodes.first {
                $0.role == .relationshipCounterpart
            }?.node,
            rootEntityID: root.entityID,
            intermediateEntityID:
                intermediate?.entityID,
            counterpart: counterpart,
            selectedFields: selectedFields,
            selectedNodes: selectedNodes,
            draft: draft,
            catalog: catalog,
            schemaContext: schemaContext
        )
        let counterpartNode:
            GraphChatTypedNodeIdentity?
        switch counterpartNodeOutcome {
        case .resolved(let value):
            counterpartNode = value.map(Self.typedNode)
        case .clarification(let clarification):
            return .clarification(clarification)
        }

        var predicatesByEntity = [
            UUID: [GraphChatComposableReadPredicate]
        ]()
        var referencedFields:
            [GraphChatTypedFieldIdentity] = []
        for (index, filterDraft) in
            draft.filters.enumerated()
        {
            let allowedOwners = try filterOwners(
                for: filterDraft,
                chain: chain,
                draft: draft,
                catalog: catalog,
                schemaContext: schemaContext
            )
            let fieldOutcome = try resolveField(
                term: filterDraft.fieldTerm,
                role: .filter(index),
                owners: allowedOwners,
                rootEntityID: root.entityID,
                intermediateEntityID:
                    intermediate?.entityID,
                counterpartEntityID:
                    counterpart.entityID,
                selectedFields: selectedFields,
                selectedNodes: selectedNodes,
                draft: draft,
                catalog: catalog,
                schemaContext: schemaContext
            )
            let field: GraphSchemaFieldResolution
            switch fieldOutcome {
            case .resolved(let value):
                field = value
            case .clarification(let clarification):
                return .clarification(clarification)
            }
            let rawFilter: GraphQueryFilter
            do {
                rawFilter = try valueParser.filter(
                    filterDraft,
                    field: field,
                    language: draft.responseLanguage,
                    referenceDate: referenceDate
                )
            } catch {
                throw GraphChatSemanticIntentResolutionError
                    .unsupportedCombination
            }
            let typedField = Self.typedField(field)
            referencedFields.append(typedField)
            predicatesByEntity[
                field.entityID,
                default: []
            ].append(
                GraphChatComposableReadPredicate(
                    field:
                        GraphChatComposableReadFieldReference(
                            alias: field.alias,
                            identity: typedField
                        ),
                    operation: rawFilter.operation,
                    value: rawFilter.value
                )
            )
        }
        referencedFields = Self.stableUnique(
            referencedFields
        )

        let direction = Self.direction(
            draft.relationshipDirection
        )
        let typedRoot = Self.typedEntity(root)
        let typedRelated = chain.dropFirst().map(
            Self.typedEntity
        )
        let resultLimit = limitPolicy.entityListLimit(
            for: draft.resultAmount
        )
        let maximumEvidence =
            policy.maximumQueryEvidenceCount
        let binding = GraphChatTypedIntentBinding(
            requestID: requestID,
            conversationID:
                providerPlan.requestBaseState
                    .conversationID,
            turnID: requestID,
            sourceTurnID: sourceTurnID,
            clarificationID: clarificationID
        )
        let queryScope = GraphChatScope.entity(
            typedRoot.id,
            in: schemaContext.graphScope
        )
        let intentLimits = GraphChatTypedIntentLimits(
            resultLimit: resultLimit,
            maximumResultLimit:
                GraphQueryPlanLimits.maximumResultLimit,
            maximumEvidenceCount: maximumEvidence,
            maximumArtifactCount: 1
        )
        let intent = try GraphChatTypedIntent(
            version: .v2,
            scope: GraphChatTypedIntentScope(
                graphScope: schemaContext.graphScope,
                chatScope:
                    providerPlan.scopeKey.chatScope,
                queryScope: queryScope
            ),
            responseLanguage: draft.responseLanguage,
            binding: binding,
            resolution: GraphChatTypedIntentResolution(
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
            ),
            expectedCardinality: .zeroOrMore,
            factExpectation: .none,
            limits: intentLimits,
            payload: .entityCollection(
                GraphChatTypedEntityCollectionIntent(
                    entity: typedRoot,
                    relatedEntities: typedRelated,
                    relatedNodes:
                        counterpartNode.map { [$0] }
                        ?? [],
                    projectedFields: [],
                    referencedFields:
                        referencedFields
                )
            )
        )

        var builder = OperationBuilder()
        builder.append(
            .select(
                .entity(
                    GraphChatComposableReadEntityReference(
                        alias: typedRoot.alias,
                        identity: typedRoot
                    )
                )
            )
        )
        if let rootPredicates =
                predicatesByEntity[typedRoot.id],
           rootPredicates.isEmpty == false {
            builder.append(
                .filter(
                    GraphChatComposableReadFilter(
                        predicates: rootPredicates
                    )
                )
            )
        }
        for entity in typedRelated {
            builder.append(
                .traverseRelationships(
                    GraphChatComposableReadTraversalStage(
                        counterpartEntity: entity,
                        counterpartNode:
                            entity.id == counterpart.entityID
                            ? counterpartNode
                            : nil,
                        direction: direction,
                        notePredicate:
                            noteOwnerID == entity.id
                            ? notePredicate
                            : nil,
                        nodePredicates:
                            predicatesByEntity[
                                entity.id
                            ] ?? []
                    )
                )
            )
        }
        let target:
            GraphChatComposableReadTraversalResultTarget =
                draft.relationshipResultTarget
                    == .startNodes
                ? .startNodes
                : .terminalNodes
        builder.append(
            .projectTraversalNodes(
                GraphChatComposableReadTraversalProjection(
                    target: target,
                    deduplicatesNodes: true
                )
            )
        )
        builder.append(
            .sort(
                GraphChatComposableReadSort(
                    descriptors: [
                        GraphChatComposableReadSortDescriptor(
                            key: .nodeName,
                            direction:
                                draft.sorting?.direction
                                    == .descending
                                ? .descending
                                : .ascending
                        ),
                        GraphChatComposableReadSortDescriptor(
                            key: .stableNodeID,
                            direction: .ascending
                        ),
                    ]
                )
            )
        )
        builder.append(
            .limit(
                GraphChatComposableReadLimit(
                    resultLimit: resultLimit,
                    intermediateResultLimit:
                        policy
                            .maximumComposableReadIntermediateCount
                )
            )
        )
        let hasDetailPredicates =
            predicatesByEntity.values
                .contains { $0.isEmpty == false }
        let evidence:
            [GraphChatComposableReadEvidenceRequirement] =
                hasDetailPredicates
                ? [
                    .nodeIdentity,
                    .authoritativeDetailValue,
                    .composableTraversalPath,
                ]
                : [
                    .nodeIdentity,
                    .composableTraversalPath,
                ]
        let plan = GraphChatComposableReadPlan(
            version: .current,
            queryPlanVersion:
                GraphQueryPlan.currentVersion,
            graphScope: schemaContext.graphScope,
            chatScope:
                providerPlan.scopeKey.chatScope,
            queryScope: queryScope,
            compiledScope: queryScope,
            binding: binding,
            responseLanguage: draft.responseLanguage,
            intentKind: intent.kind,
            operations: builder.operations,
            resultContract: .composableNodeCollection,
            evidenceRequirements: evidence,
            artifactContract: .queryResult,
            limits: GraphChatComposableReadLimits(
                resultLimit: resultLimit,
                maximumResultLimit:
                    GraphQueryPlanLimits.maximumResultLimit,
                intermediateResultLimit:
                    policy
                        .maximumComposableReadIntermediateCount,
                maximumEvidenceCount: maximumEvidence,
                maximumArtifactCount: 1,
                maximumOperationCount:
                    policy
                        .maximumComposableReadOperationCount,
                maximumTraversalHopCount:
                    policy
                        .maximumComposableReadTraversalHopCount,
                selectedStartNodeLimit:
                    policy
                        .maximumComposableReadSelectedStartNodeCount,
                visitedNodeLimit:
                    policy
                        .maximumComposableReadVisitedNodeCount,
                checkedLinkLimit:
                    policy
                        .maximumComposableReadCheckedLinkCount
            ),
            queryReferenceDate: referenceDate
        )
        return .compiled(
            GraphChatTypedIntentAdaptation(
                intent: intent,
                action: .composableRead(plan)
            )
        )
    }

    private enum EntityOutcome {
        case resolved(GraphSchemaEntityResolution)
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private enum FieldOutcome {
        case resolved(GraphSchemaFieldResolution)
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private enum CounterpartNodeOutcome {
        case resolved(GraphSchemaNodeResolution?)
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private func resolveCounterpartNode(
        term: String?,
        selectedNode: NodeRefKey?,
        rootEntityID: UUID,
        intermediateEntityID: UUID?,
        counterpart: GraphSchemaEntityResolution,
        selectedFields:
            [GraphChatSemanticSelectedField],
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        draft: GraphChatUntrustedSemanticIntentDraft,
        catalog: GraphMentionCatalog,
        schemaContext: GraphSchemaContext
    ) throws -> CounterpartNodeOutcome {
        guard let term else {
            guard selectedNode == nil else {
                throw GraphChatSemanticIntentResolutionError
                    .staleNodeSelection
            }
            return .resolved(nil)
        }
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: term,
                kind: .node,
                language: draft.responseLanguage,
                graphScope: schemaContext.graphScope,
                catalog: catalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: .entireGraph(
                            schemaContext.graphScope
                        ),
                        ownerEntityID:
                            counterpart.entityID,
                        allowedNodes:
                            selectedNode.map { Set([$0]) }
                    )
            )
        )
        switch result {
        case .success(let resolution):
            guard case .node(let node) =
                    resolution.candidate.identity,
                  node.node.kind == .attribute,
                  node.ownerEntityID
                    == counterpart.entityID
            else {
                throw GraphChatSemanticIntentResolutionError
                    .invalidSchemaIdentity
            }
            return .resolved(node)
        case .failure(.ambiguous(let alternatives)):
            let nodes = alternatives.compactMap {
                alternative -> GraphSchemaNodeResolution? in
                guard case .node(let node) =
                        alternative.candidate.identity,
                      node.node.kind == .attribute,
                      node.ownerEntityID
                        == counterpart.entityID
                else {
                    return nil
                }
                return node
            }
            guard nodes.isEmpty == false else {
                throw GraphChatSemanticIntentResolutionError
                    .invalidSchemaIdentity
            }
            let retainedNodes = selectedNodes.filter {
                $0.role != .relationshipCounterpart
            }
            return .clarification(
                GraphChatSemanticEntityClarification(
                    question:
                        draft.responseLanguage == .german
                        ? "Welchen fachlichen Gegenknoten meinst du?"
                        : "Which domain counterpart node do you mean?",
                    candidates: nodes.map { node in
                        GraphChatSemanticEntityCandidate(
                            entityID:
                                counterpart.entityID,
                            displayName:
                                node.displayName,
                            selectionRole:
                                .relationshipCounterpart,
                            preservedPrimaryEntityID:
                                rootEntityID,
                            preservedRelationshipCounterpartEntityID:
                                counterpart.entityID,
                            preservedComposableIntermediateEntityID:
                                intermediateEntityID,
                            selectedFields:
                                selectedFields,
                            selectedNodes:
                                retainedNodes
                                + [
                                    GraphChatSemanticSelectedNode(
                                        role:
                                            .relationshipCounterpart,
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

    private func resolveEntity(
        term: String,
        selectedID: UUID?,
        role: GraphChatSemanticEntitySelectionRole,
        preservedRootID: UUID?,
        preservedIntermediateID: UUID?,
        preservedCounterpartID: UUID?,
        selectedFields:
            [GraphChatSemanticSelectedField],
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        draft: GraphChatUntrustedSemanticIntentDraft,
        catalog: GraphMentionCatalog,
        schemaContext: GraphSchemaContext
    ) throws -> EntityOutcome {
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: term,
                kind: .entity,
                language: draft.responseLanguage,
                graphScope: schemaContext.graphScope,
                catalog: catalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: .entireGraph(
                            schemaContext.graphScope
                        ),
                        allowedEntityIDs:
                            selectedID.map { Set([$0]) }
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
            return .resolved(entity)
        case .failure(.ambiguous(let alternatives)):
            let entities = alternatives.compactMap {
                alternative -> GraphSchemaEntityResolution? in
                guard case .entity(let entity) =
                        alternative.candidate.identity else {
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
                        draft.responseLanguage == .german
                        ? "Welche fachliche Entity meinst du?"
                        : "Which domain entity do you mean?",
                    candidates: entities.map {
                        GraphChatSemanticEntityCandidate(
                            entityID: $0.entityID,
                            displayName: $0.name,
                            selectionRole: role,
                            preservedPrimaryEntityID:
                                preservedRootID,
                            preservedRelationshipCounterpartEntityID:
                                preservedCounterpartID,
                            preservedComposableIntermediateEntityID:
                                preservedIntermediateID,
                            selectedFields: selectedFields,
                            selectedNodes: selectedNodes
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

    private func filterOwners(
        for filter: GraphChatSemanticFilterDraft,
        chain: [GraphSchemaEntityResolution],
        draft: GraphChatUntrustedSemanticIntentDraft,
        catalog: GraphMentionCatalog,
        schemaContext: GraphSchemaContext
    ) throws -> [GraphSchemaEntityResolution] {
        guard let term = filter.entityTerm else {
            return chain
        }
        let allowed = Set(chain.map(\.entityID))
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: term,
                kind: .entity,
                language: draft.responseLanguage,
                graphScope: schemaContext.graphScope,
                catalog: catalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: .entireGraph(
                            schemaContext.graphScope
                        ),
                        allowedEntityIDs: allowed
                    )
            )
        )
        guard case .success(let resolution) = result,
              case .entity(let entity) =
                resolution.candidate.identity,
              allowed.contains(entity.entityID)
        else {
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        }
        return [entity]
    }

    private func resolveField(
        term: String,
        role: GraphChatSemanticFieldSelectionRole,
        owners: [GraphSchemaEntityResolution],
        rootEntityID: UUID,
        intermediateEntityID: UUID?,
        counterpartEntityID: UUID,
        selectedFields:
            [GraphChatSemanticSelectedField],
        selectedNodes:
            [GraphChatSemanticSelectedNode],
        draft: GraphChatUntrustedSemanticIntentDraft,
        catalog: GraphMentionCatalog,
        schemaContext: GraphSchemaContext
    ) throws -> FieldOutcome {
        let selected = selectedFields.first {
            $0.role == role
        }
        var fields: [GraphSchemaFieldResolution] = []
        for owner in owners {
            let result = mentionResolver.resolve(
                GraphMentionResolverInput(
                    mention: term,
                    kind: .field,
                    language: draft.responseLanguage,
                    graphScope: schemaContext.graphScope,
                    catalog: catalog,
                    constraints:
                        GraphMentionResolutionConstraints(
                            chatScope: .entireGraph(
                                schemaContext.graphScope
                            ),
                            ownerEntityID:
                                owner.entityID,
                            allowedFieldIDs:
                                selected.map {
                                    Set([$0.fieldID])
                                }
                        )
                )
            )
            switch result {
            case .success(let resolution):
                guard case .field(let field) =
                        resolution.candidate.identity else {
                    throw GraphChatSemanticIntentResolutionError
                        .invalidSchemaIdentity
                }
                fields.append(field)
            case .failure(.ambiguous(let alternatives)):
                fields.append(
                    contentsOf:
                        alternatives.compactMap {
                            guard case .field(let field) =
                                    $0.candidate.identity else {
                                return nil
                            }
                            return field
                        }
                )
            case .failure(.staleSelection):
                throw GraphChatSemanticIntentResolutionError
                    .staleEntitySelection
            case .failure(.scopeViolation),
                .failure(.ownerEntityMismatch),
                .failure(.graphScopeMismatch):
                throw GraphChatSemanticIntentResolutionError
                    .scopeViolation
            case .failure(.emptyMention),
                .failure(.noCandidates),
                .failure(.notFound):
                continue
            }
        }
        fields = Self.stableUnique(fields)
        if fields.count == 1 {
            return .resolved(fields[0])
        }
        guard fields.isEmpty == false else {
            throw GraphChatSemanticIntentResolutionError
                .fieldNotFound
        }
        return .clarification(
            GraphChatSemanticEntityClarification(
                question:
                    draft.responseLanguage == .german
                    ? "Welches fachliche Feld meinst du?"
                    : "Which domain field do you mean?",
                candidates: fields.map { field in
                    var bindings = selectedFields.filter {
                        $0.role != role
                    }
                    bindings.append(
                        GraphChatSemanticSelectedField(
                            role: role,
                            fieldID: field.fieldID
                        )
                    )
                    let ownerName = schemaContext
                        .foundationalAliases
                        .entity(id: field.entityID)?.name
                    return GraphChatSemanticEntityCandidate(
                        entityID: rootEntityID,
                        displayName: [
                            field.name,
                            ownerName,
                        ].compactMap { $0 }
                            .joined(separator: " · "),
                        selectionRole: .primary,
                        preservedPrimaryEntityID:
                            rootEntityID,
                        preservedRelationshipCounterpartEntityID:
                            counterpartEntityID,
                        preservedComposableIntermediateEntityID:
                            intermediateEntityID,
                        selectedFields: bindings,
                        selectedNodes: selectedNodes
                    )
                },
                draft: draft
            )
        )
    }

    private func resolvedNoteOwnerID(
        draft: GraphChatUntrustedSemanticIntentDraft,
        traversedEntities:
            [GraphSchemaEntityResolution],
        notePredicate:
            GraphChatRelationshipNotePredicate?,
        catalog: GraphMentionCatalog,
        schemaContext: GraphSchemaContext
    ) throws -> UUID? {
        guard notePredicate != nil else { return nil }
        if traversedEntities.count == 1,
           draft.relationshipNoteEntityTerm == nil {
            return traversedEntities[0].entityID
        }
        guard let term =
                draft.relationshipNoteEntityTerm else {
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        }
        let allowed = Set(
            traversedEntities.map(\.entityID)
        )
        let result = mentionResolver.resolve(
            GraphMentionResolverInput(
                mention: term,
                kind: .entity,
                language: draft.responseLanguage,
                graphScope: schemaContext.graphScope,
                catalog: catalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope: .entireGraph(
                            schemaContext.graphScope
                        ),
                        allowedEntityIDs: allowed
                    )
            )
        )
        guard case .success(let resolution) = result,
              case .entity(let entity) =
                resolution.candidate.identity,
              allowed.contains(entity.entityID)
        else {
            throw GraphChatSemanticIntentResolutionError
                .unsupportedCombination
        }
        return entity.entityID
    }

    private static func notePredicate(
        _ draft: GraphChatUntrustedSemanticIntentDraft
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

    private static func direction(
        _ source:
            GraphChatSemanticRelationshipDirection
    ) -> GraphChatRelationshipDirection {
        switch source {
        case .incoming:
            return .incoming
        case .outgoing:
            return .outgoing
        case .unspecified, .both:
            return .both
        }
    }

    private static func typedEntity(
        _ source: GraphSchemaEntityResolution
    ) -> GraphChatTypedEntityIdentity {
        GraphChatTypedEntityIdentity(
            id: source.entityID,
            alias: source.alias,
            displayName: source.name
        )
    }

    private static func typedField(
        _ source: GraphSchemaFieldResolution
    ) -> GraphChatTypedFieldIdentity {
        GraphChatTypedFieldIdentity(
            id: source.fieldID,
            alias: source.alias,
            displayName: source.name,
            ownerEntityID: source.entityID,
            type: source.type,
            unit: source.unit
        )
    }

    private static func typedNode(
        _ source: GraphSchemaNodeResolution
    ) -> GraphChatTypedNodeIdentity {
        GraphChatTypedNodeIdentity(
            node: source.node,
            displayName: source.displayName,
            ownerEntityID: source.ownerEntityID
        )
    }

    private struct OperationBuilder {
        private(set) var operations:
            [GraphChatComposableReadOperation] = []

        mutating func append(
            _ payload:
                GraphChatComposableReadOperationPayload
        ) {
            let id = GraphChatComposableReadStepID(
                rawValue: operations.count
            )
            operations.append(
                GraphChatComposableReadOperation(
                    id: id,
                    input: operations.last?.id,
                    payload: payload
                )
            )
        }
    }

    private static func stableUnique<Value: Hashable>(
        _ values: [Value]
    ) -> [Value] {
        var seen = Set<Value>()
        return values.filter {
            seen.insert($0).inserted
        }
    }
}
