//
//  GraphChatInterpretationCorrectionCompiler.swift
//  BrainMesh
//
//  Provider-free rebinding of an editor selection to the existing app-owned
//  semantic resolver, query compiler and query-plan validator.
//

import Foundation

nonisolated enum GraphChatInterpretationCorrectionCompilationError:
    Error,
    Hashable,
    Sendable
{
    case stale(
        GraphChatInterpretationCorrectionStaleReason
    )
    case invalid(
        GraphChatInterpretationCorrectionValidationIssue
    )
}

nonisolated struct GraphChatInterpretationCorrectionCompilation:
    Sendable
{
    let adaptation:
        GraphChatTypedIntentAdaptation
    let schemaContext: GraphSchemaContext
}

nonisolated struct GraphChatInterpretationCorrectionCompiler:
    Sendable
{
    private let calendar: Calendar
    private let draftValidator:
        GraphChatSemanticDraftValidator
    private let resolver:
        GraphChatSemanticIntentResolver

    init(
        calendar: Calendar,
        timeZone: TimeZone,
        draftValidator:
            GraphChatSemanticDraftValidator =
                GraphChatSemanticDraftValidator(),
        resolver:
            GraphChatSemanticIntentResolver? = nil
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.draftValidator = draftValidator
        self.resolver =
            resolver
            ?? GraphChatSemanticIntentResolver(
                queryCompiler:
                    GraphChatQueryIntentCompiler(
                        calendar:
                            configuredCalendar,
                        timeZone:
                            timeZone
                    )
            )
    }

    func compile(
        request:
            GraphChatInterpretationCorrectionRequest,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        requestedAt: Date
    ) throws
        -> GraphChatInterpretationCorrectionCompilation
    {
        try validateBinding(
            request,
            providerPlan: providerPlan,
            schemaContext: schemaContext
        )

        let selection = request.selection
        let capabilities = request.capabilities
        guard capabilities.isEditable else {
            throw invalid(.interpretationNotEditable)
        }
        if capabilities.intentKind
            == .relationships {
            return try compileRelationship(
                request: request,
                providerPlan: providerPlan,
                schemaContext: schemaContext,
                requestID: requestID,
                requestedAt: requestedAt
            )
        }
        let aliases =
            schemaContext.foundationalAliases
        let entity = try selectedEntity(
            selection.entityID,
            capabilities: capabilities,
            aliases: aliases
        )
        if capabilities.contains(.entity),
           let entity {
            guard
                entityIsAllowed(
                    entity.entityID,
                    within:
                        request.binding
                            .chatScope,
                    aliases: aliases
                )
            else {
                throw invalid(
                    .scopeExpansion
                )
            }
        }
        let fieldsByID =
            Dictionary(
                uniqueKeysWithValues:
                    aliases.fieldsByAlias
                        .values.map {
                            ($0.fieldID, $0)
                        }
            )
        let nodesByKey = aliases.nodesByKey

        try validateNodes(
            selection.nodes,
            capabilities: capabilities,
            chatScope:
                request.binding.chatScope,
            graphScope:
                request.binding.graphScope,
            nodesByKey: nodesByKey,
            aliases: aliases
        )
        try validateNodeEntitySelection(
            selection,
            intentKind:
                capabilities.intentKind,
            selectedEntity: entity,
            nodesByKey: nodesByKey
        )
        try validateRefinementSelection(
            selection,
            request: request,
            selectedEntity: entity
        )
        guard
            capabilities.contains(.filters)
                || selection.filters.isEmpty
        else {
            throw invalid(.invalidFilter)
        }
        guard
            capabilities.contains(.sorting)
                || selection.sorting.isEmpty
        else {
            throw invalid(.invalidSort)
        }

        let selectedProjectionFields =
            try selection.fields.map {
                try field(
                    id: $0,
                    expectedEntityID:
                        projectionEntityID(
                            entity: entity,
                            selectedNodes:
                                selection.nodes,
                            nodesByKey:
                                nodesByKey,
                            intentKind:
                                capabilities
                                    .intentKind
                        ),
                    fieldsByID:
                        fieldsByID
                )
            }
        guard
            Set(selection.fields).count
                == selection.fields.count,
            selectedProjectionFields.count
                <= GraphChatSemanticSafety
                    .maximumProjectionTerms
        else {
            throw invalid(.invalidFieldSelection)
        }
        if capabilities.intentKind == .compareNodes {
            let ownerEntityIDs = Set(
                selection.nodes.compactMap {
                    nodesByKey[$0]?
                        .ownerEntityID
                }
            )
            let isSameEntityAttributeComparison =
                ownerEntityIDs.count == 1
                && selection.nodes.allSatisfy {
                    $0.kind == .attribute
                }
            guard
                (
                    isSameEntityAttributeComparison
                        && selectedProjectionFields
                            .isEmpty == false
                )
                    || (
                        isSameEntityAttributeComparison
                            == false
                            && selectedProjectionFields
                                .isEmpty
                    )
            else {
                throw invalid(
                    .invalidFieldSelection
                )
            }
        }

        var selectedFields:
            [GraphChatSemanticSelectedField] = []
        let semanticFilters =
            try selection.filters.enumerated()
                .map { index, correction in
                    let resolved = try field(
                        id: correction.fieldID,
                        expectedEntityID:
                            entity?.entityID,
                        fieldsByID:
                            fieldsByID
                    )
                    guard
                        GraphChatQueryOperatorCompatibility
                            .allowedOperators(
                                for: resolved.type
                            )
                            .contains(
                                correction.operation
                            )
                    else {
                        throw invalid(
                            .invalidFilter
                        )
                    }
                    selectedFields.append(
                        GraphChatSemanticSelectedField(
                            role: .filter(index),
                            fieldID:
                                resolved.fieldID
                        )
                    )
                    return try semanticFilter(
                        correction,
                        field: resolved,
                        language:
                            request.binding
                                .originalInterpretation
                                .responseLanguage
                    )
                }
        guard
            selection.filters.count
                <= GraphChatSemanticSafety
                    .maximumFilters,
            Set(selection.filters.map(\.id))
                .count == selection.filters.count
        else {
            throw invalid(.invalidFilter)
        }

        let semanticSorting =
            try semanticSort(
                selection.sorting,
                entityID:
                    entity?.entityID,
                fieldsByID:
                    fieldsByID,
                selectedFields:
                    &selectedFields
            )

        for (
            index,
            projectedField
        ) in selectedProjectionFields
            .enumerated()
        {
            selectedFields.append(
                GraphChatSemanticSelectedField(
                    role: .projection(index),
                    fieldID:
                        projectedField.fieldID
                )
            )
        }

        let groupingField:
            GraphSchemaFieldResolution?
        if let groupingFieldID =
                selection.groupingFieldID
        {
            groupingField = try field(
                id: groupingFieldID,
                expectedEntityID:
                    entity?.entityID,
                fieldsByID:
                    fieldsByID
            )
            selectedFields.append(
                GraphChatSemanticSelectedField(
                    role: .grouping,
                    fieldID:
                        groupingFieldID
                )
            )
        } else {
            groupingField = nil
        }

        let selectedNodes:
            [GraphChatSemanticSelectedNode]
        switch capabilities.intentKind {
        case .nodeDetails:
            selectedNodes =
                selection.nodes.map {
                    GraphChatSemanticSelectedNode(
                        role: .details,
                        node: $0
                    )
                }
        case .compareNodes:
            selectedNodes =
                selection.nodes.enumerated().map {
                    index, node in
                    GraphChatSemanticSelectedNode(
                        role: .comparison(index),
                        node: node
                    )
                }
        case .findNodes,
            .entityCollection,
            .countOrGroup,
            .narrowResultSet,
            .inspectGraphState,
            .relationships:
            selectedNodes = []
        }
        let draft = try semanticDraft(
            request: request,
            entity: entity,
            projectionFields:
                selectedProjectionFields,
            filters: semanticFilters,
            sorting: semanticSorting,
            groupingField:
                groupingField,
            nodesByKey: nodesByKey
        )
        let validatorRequest =
            GraphChatIntentInterpreterRequest(
                normalizedQuestion:
                    request.binding
                        .originalQuestion,
                responseLanguage:
                    draft.responseLanguage,
                schemaEntities: [],
                conversationDescriptions: [],
                scopeDescription: ""
            )
        let validatedDraft: GraphChatUntrustedSemanticIntentDraft
        do {
            validatedDraft =
                try draftValidator.validate(
                    draft,
                    for: validatorRequest
                )
        } catch {
            throw invalid(
                validationIssue(
                    for: draft.family
                )
            )
        }

        let resolution:
            GraphChatSemanticIntentResolution
        do {
            resolution = try resolver.resolve(
                draft: validatedDraft,
                selectedEntityID:
                    entity?.entityID,
                selectedFields:
                    selectedFields,
                selectedNodes:
                    selectedNodes,
                currentResolvedScope:
                    providerPlan
                        .currentResolvedScope,
                providerPlan:
                    providerPlan,
                schemaContext:
                    schemaContext,
                requestID:
                    requestID,
                sourceTurnID:
                    request.binding
                        .originalInterpretation
                        .correctionOrigin?
                        .adaptation
                        .intent
                        .binding
                        .sourceTurnID,
                clarificationID: nil,
                referenceDate:
                    requestedAt
            )
        } catch let error
            as GraphChatSemanticIntentResolutionError
        {
            throw mapped(error)
        } catch {
            throw invalid(
                validationIssue(
                    for: draft.family
                )
            )
        }

        guard case .compiled(let adaptation) =
                resolution,
              adaptation.intent.kind
                == request.capabilities.intentKind,
              adaptation.intent.version
                == request.binding
                    .intentDomainVersion,
              adaptation.intent.scope.graphScope
                == request.binding.graphScope,
              adaptation.intent.scope.chatScope
                == request.binding.chatScope
        else {
            throw stale(.schemaChanged)
        }
        return GraphChatInterpretationCorrectionCompilation(
            adaptation: adaptation,
            schemaContext:
                GraphSchemaContext(
                    graphScope:
                        schemaContext.graphScope,
                    snapshot:
                        schemaContext.snapshot,
                    aliases:
                        schemaContext
                            .foundationalAliases,
                    foundationalAliases:
                        schemaContext
                            .foundationalAliases
                )
        )
    }

    private func compileRelationship(
        request:
            GraphChatInterpretationCorrectionRequest,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        requestedAt: Date
    ) throws
        -> GraphChatInterpretationCorrectionCompilation
    {
        let interpretation =
            request.binding
                .originalInterpretation
        guard
            let relationship =
                interpretation.relationship,
            request.binding.intentDomainVersion
                == .v2,
            let direction =
                request.selection
                    .relationshipDirection
        else {
            throw invalid(
                .invalidRelationshipSelection
            )
        }
        let aliases =
            schemaContext.foundationalAliases
        guard
            let center =
                aliases.nodesByKey[
                    relationship.center.node
                ],
            center.ownerEntityID
                == relationship
                    .center.ownerEntityID,
            GraphChatScopeAuthorization.allows(
                scope: .node(
                    center.node,
                    in:
                        schemaContext
                            .graphScope
                ),
                within:
                    request.binding.chatScope,
                aliases: aliases
            ),
            aliases.entity(
                id: center.ownerEntityID
            ) != nil
        else {
            throw stale(.nodeUnavailable)
        }

        let selectedCounterpartNode =
            request.selection
                .relationshipCounterpartNode
        let counterpartNode =
            try selectedCounterpartNode.map {
                node -> GraphSchemaNodeResolution in
                guard let resolution =
                        aliases.nodesByKey[node]
                else {
                    throw stale(
                        .nodeUnavailable
                    )
                }
                return resolution
            }
        let counterpartEntityID =
            request.selection
                .relationshipCounterpartEntityID
            ?? counterpartNode?
                .ownerEntityID
        let counterpartEntity =
            try counterpartEntityID.map {
                id -> GraphSchemaEntityResolution in
                guard let entity =
                        aliases.entity(id: id)
                else {
                    throw stale(
                        .entityUnavailable
                    )
                }
                return entity
            }
        if let counterpartNode,
           let counterpartEntity,
           counterpartNode.ownerEntityID
            != counterpartEntity.entityID {
            throw invalid(
                .invalidRelationshipSelection
            )
        }
        if relationship.request
            == .linkNotesBetweenNodes {
            guard counterpartNode != nil,
                  direction == .both else {
                throw invalid(
                    .invalidRelationshipSelection
                )
            }
        }

        let note:
            (
                GraphChatSemanticRelationshipNotePredicate,
                String?
            )
        switch request.selection
            .relationshipNotePredicate {
        case nil:
            note = (.unspecified, nil)
        case .present:
            note = (.present, nil)
        case .missing:
            note = (.missing, nil)
        case .contains(let term):
            note = (.contains, term)
        }
        let semanticDirection:
            GraphChatSemanticRelationshipDirection
        switch direction {
        case .incoming:
            semanticDirection = .incoming
        case .outgoing:
            semanticDirection = .outgoing
        case .both:
            semanticDirection = .both
        }
        let semanticRequest:
            GraphChatSemanticRelationshipRequest =
            relationship.request
                == .connections
            ? .connections
            : .linkNotesBetweenNodes
        let nodeTerms =
            [center.displayName]
            + (
                counterpartNode.map {
                    [$0.displayName]
                } ?? []
            )
        let draft =
            GraphChatUntrustedSemanticIntentDraft(
                family: .relationships,
                nodeTerms: nodeTerms,
                relationshipRequest:
                    semanticRequest,
                relationshipDirection:
                    semanticDirection,
                relationshipCounterpartEntityTerm:
                    semanticRequest
                        == .linkNotesBetweenNodes
                    ? nil
                    : counterpartEntity?.name,
                relationshipNotePredicate:
                    note.0,
                relationshipNoteTerm:
                    note.1,
                responseLanguage:
                    interpretation
                        .responseLanguage
            )
        let validatorRequest =
            GraphChatIntentInterpreterRequest(
                normalizedQuestion:
                    request.binding
                        .originalQuestion,
                responseLanguage:
                    draft.responseLanguage,
                schemaEntities: [],
                conversationDescriptions: [],
                scopeDescription: ""
            )
        let validatedDraft:
            GraphChatUntrustedSemanticIntentDraft
        do {
            validatedDraft =
                try draftValidator.validate(
                    draft,
                    for: validatorRequest
                )
        } catch {
            throw invalid(
                .invalidRelationshipSelection
            )
        }
        var selectedNodes = [
            GraphChatSemanticSelectedNode(
                role: .relationshipCenter,
                node: center.node
            ),
        ]
        if let counterpartNode {
            selectedNodes.append(
                GraphChatSemanticSelectedNode(
                    role:
                        .relationshipCounterpart,
                    node:
                        counterpartNode.node
                )
            )
        }
        let resolution:
            GraphChatSemanticIntentResolution
        do {
            resolution = try resolver.resolve(
                draft: validatedDraft,
                selectedEntityID:
                    center.ownerEntityID,
                selectedRelationshipCounterpartEntityID:
                    counterpartEntity?.entityID,
                selectedNodes:
                    selectedNodes,
                currentResolvedScope: nil,
                providerPlan:
                    providerPlan,
                schemaContext:
                    schemaContext,
                requestID: requestID,
                sourceTurnID:
                    interpretation
                        .turnBinding
                        .sourceTurnID,
                clarificationID: nil,
                referenceDate:
                    requestedAt
            )
        } catch let error
            as GraphChatSemanticIntentResolutionError {
            throw mapped(error)
        } catch {
            throw invalid(
                .invalidRelationshipSelection
            )
        }
        guard
            case .compiled(let adaptation) =
                resolution,
            adaptation.intent.kind
                == .relationships,
            adaptation.intent.version
                == .v2,
            adaptation.intent.scope.graphScope
                == request.binding.graphScope,
            adaptation.intent.scope.chatScope
                == request.binding.chatScope
        else {
            throw stale(.schemaChanged)
        }
        return GraphChatInterpretationCorrectionCompilation(
            adaptation: adaptation,
            schemaContext:
                GraphSchemaContext(
                    graphScope:
                        schemaContext.graphScope,
                    snapshot:
                        schemaContext.snapshot,
                    aliases:
                        aliases,
                    foundationalAliases:
                        aliases
                )
        )
    }

    private func validateBinding(
        _ request:
            GraphChatInterpretationCorrectionRequest,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws {
        let binding = request.binding
        guard
            binding.version == .v1,
            binding.graphScope
                == providerPlan.scopeKey
                    .graphScope,
            binding.chatScope
                == providerPlan.scopeKey
                    .chatScope,
            binding.graphScope
                == schemaContext.graphScope,
            binding.conversationID
                == providerPlan
                    .requestBaseState
                    .conversationID,
            binding.originalInterpretation
                .isCorrectionEditable,
            binding.originalInterpretation
                .correctionOrigin?
                .artifactSessionID
                == binding.artifactSessionID,
            request.capabilities
                == .derive(
                    from:
                        binding
                            .originalInterpretation
                )
        else {
            throw stale(.interpretationChanged)
        }
    }

    private func selectedEntity(
        _ entityID: UUID?,
        capabilities:
            GraphChatInterpretationCorrectionCapabilities,
        aliases: GraphSchemaAliasMap
    ) throws -> GraphSchemaEntityResolution? {
        guard let entityID else {
            switch capabilities.intentKind {
            case .findNodes,
                .inspectGraphState,
                .relationships:
                return nil
            case .entityCollection,
                .countOrGroup,
                .narrowResultSet:
                throw invalid(.missingEntity)
            case .nodeDetails,
                .compareNodes:
                return nil
            }
        }
        guard let entity =
                aliases.entity(id: entityID)
        else {
            throw stale(.entityUnavailable)
        }
        return entity
    }

    private func field(
        id: UUID,
        expectedEntityID: UUID?,
        fieldsByID:
            [UUID:
                GraphSchemaFieldResolution]
    ) throws -> GraphSchemaFieldResolution {
        guard let value = fieldsByID[id] else {
            throw stale(.fieldUnavailable)
        }
        if let expectedEntityID,
           value.entityID != expectedEntityID {
            throw invalid(
                .invalidFieldSelection
            )
        }
        return value
    }

    private func projectionEntityID(
        entity:
            GraphSchemaEntityResolution?,
        selectedNodes: [NodeRefKey],
        nodesByKey:
            [NodeRefKey:
                GraphSchemaNodeResolution],
        intentKind:
            GraphChatTypedIntentKind
    ) -> UUID? {
        if intentKind == .compareNodes {
            let owners = Set(
                selectedNodes.compactMap {
                    nodesByKey[$0]?
                        .ownerEntityID
                }
            )
            return owners.count == 1
                ? owners.first
                : nil
        }
        return selectedNodes.first
            .flatMap {
                nodesByKey[$0]?
                    .ownerEntityID
            }
            ?? entity?.entityID
    }

    private func validateNodes(
        _ nodes: [NodeRefKey],
        capabilities:
            GraphChatInterpretationCorrectionCapabilities,
        chatScope: GraphChatScope,
        graphScope: GraphScope,
        nodesByKey:
            [NodeRefKey:
                GraphSchemaNodeResolution],
        aliases: GraphSchemaAliasMap
    ) throws {
        guard
            Set(nodes).count == nodes.count
        else {
            throw invalid(
                .invalidNodeSelection
            )
        }
        if let limit =
                capabilities.nodeSelectionLimit,
           limit.contains(nodes.count)
                == false {
            throw invalid(
                .invalidNodeSelection
            )
        }
        for node in nodes {
            guard nodesByKey[node] != nil else {
                throw stale(.nodeUnavailable)
            }
            guard
                GraphChatScopeAuthorization
                    .allows(
                        scope: .node(
                            node,
                            in: graphScope
                        ),
                        within: chatScope,
                        aliases: aliases
                    )
            else {
                throw invalid(
                    .scopeExpansion
                )
            }
        }
    }

    private func validateRefinementSelection(
        _ selection:
            GraphChatInterpretationCorrectionSelection,
        request:
            GraphChatInterpretationCorrectionRequest,
        selectedEntity:
            GraphSchemaEntityResolution?
    ) throws {
        guard request.capabilities.intentKind
                == .narrowResultSet else {
            return
        }
        let interpretation =
            request.binding
                .originalInterpretation
        let originalNodes = Set(
            interpretation.nodes.map(\.node)
        )
        guard
            Set(selection.nodes)
                .isSubset(of: originalNodes),
            selectedEntity?.entityID
                == interpretation
                    .entities.first?.id
        else {
            throw invalid(
                .scopeExpansion
            )
        }
    }

    private func validateNodeEntitySelection(
        _ selection:
            GraphChatInterpretationCorrectionSelection,
        intentKind:
            GraphChatTypedIntentKind,
        selectedEntity:
            GraphSchemaEntityResolution?,
        nodesByKey:
            [NodeRefKey:
                GraphSchemaNodeResolution]
    ) throws {
        let expectedEntityID: UUID?
        switch intentKind {
        case .nodeDetails:
            expectedEntityID =
                selection.nodes.first.flatMap {
                    nodesByKey[$0]?
                        .ownerEntityID
                }
        case .compareNodes:
            let ownerEntityIDs = Set(
                selection.nodes.compactMap {
                    nodesByKey[$0]?
                        .ownerEntityID
                }
            )
            expectedEntityID =
                ownerEntityIDs.count == 1
                    && selection.nodes
                        .allSatisfy {
                            $0.kind == .attribute
                        }
                ? ownerEntityIDs.first
                : nil
        case .findNodes, .entityCollection,
            .countOrGroup, .narrowResultSet,
            .inspectGraphState,
            .relationships:
            return
        }
        guard
            selectedEntity?.entityID
                == expectedEntityID
        else {
            throw invalid(
                .invalidNodeSelection
            )
        }
    }

    private func entityIsAllowed(
        _ entityID: UUID,
        within chatScope: GraphChatScope,
        aliases: GraphSchemaAliasMap
    ) -> Bool {
        switch chatScope.target {
        case .graph:
            return true
        case .entity(let allowedEntityID):
            return entityID == allowedEntityID
        case .node(let node):
            return aliases.owningEntityID(
                for: node
            ) == entityID
        case .selection(let nodes):
            return nodes.isEmpty == false
                && nodes.contains {
                    aliases.owningEntityID(
                        for: $0
                    ) == entityID
                }
        }
    }

    private func semanticDraft(
        request:
            GraphChatInterpretationCorrectionRequest,
        entity:
            GraphSchemaEntityResolution?,
        projectionFields:
            [GraphSchemaFieldResolution],
        filters:
            [GraphChatSemanticFilterDraft],
        sorting:
            GraphChatSemanticSortDraft?,
        groupingField:
            GraphSchemaFieldResolution?,
        nodesByKey:
            [NodeRefKey:
                GraphSchemaNodeResolution]
    ) throws -> GraphChatUntrustedSemanticIntentDraft {
        let selection = request.selection
        let interpretation =
            request.binding
                .originalInterpretation
        let family:
            GraphChatSemanticIntentFamily
        switch interpretation.intentKind {
        case .findNodes:
            family = .findNodes
        case .entityCollection:
            family = filters.isEmpty
                ? .entityList
                : .filteredCollection
        case .countOrGroup:
            family = interpretation.grouping == nil
                ? .count
                : .groupCount
        case .nodeDetails:
            family = .nodeDetails
        case .narrowResultSet:
            family = .refinement
        case .compareNodes:
            family = .compareNodes
        case .inspectGraphState:
            family = .inspectGraphState
        case .relationships:
            family = .relationships
        }

        if family == .findNodes {
            let term = selection.search?.term
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ) ?? ""
            guard term.isEmpty == false else {
                throw invalid(
                    .emptySearchTerm
                )
            }
        }
        if family == .groupCount,
           groupingField == nil {
            throw invalid(
                .missingGroupingField
            )
        }
        if family == .inspectGraphState,
           request.binding.chatScope
            != .entireGraph(
                request.binding.graphScope
            ) {
            throw invalid(
                .graphStateRequiresEntireGraph
            )
        }

        return GraphChatUntrustedSemanticIntentDraft(
            family: family,
            entityTerm:
                entityTerm(
                    for: family,
                    entity: entity
                ),
            searchTerm:
                selection.search?.term,
            nodeTerms:
                nodeTerms(
                    for: family,
                    nodes: selection.nodes,
                    nodesByKey: nodesByKey,
                    language:
                        interpretation
                            .responseLanguage
                ),
            findTarget:
                selection.search?.target
                ?? .anyEntry,
            resultAmount:
                effectiveResultAmount(
                    selection.resultAmount,
                    interpretation:
                        interpretation
                ),
            conversationReference:
                family == .refinement
                ? .currentSelection
                : .none,
            filters: filters,
            sorting: sorting,
            projectionTerms:
                projectionTerms(
                    request: request,
                    family: family,
                    fields: projectionFields
                ),
            groupFieldTerm:
                groupingField?.name,
            graphStateAspect:
                selection.graphStateAspect
                ?? interpretation
                    .graphStateAspect
                ?? .overview,
            responseLanguage:
                interpretation.responseLanguage
        )
    }

    private func nodeTerms(
        for family:
            GraphChatSemanticIntentFamily,
        nodes: [NodeRefKey],
        nodesByKey:
            [NodeRefKey:
                GraphSchemaNodeResolution],
        language:
            GraphChatResponseLanguage
    ) -> [String] {
        switch family {
        case .nodeDetails:
            return nodes.prefix(1)
                .compactMap {
                    nodesByKey[$0]?
                        .displayName
                }
        case .compareNodes:
            // The selected-node bindings carry the authoritative IDs.
            // The visible display phrase keeps correction rebinding on the
            // central mention resolver; the ordinal only preserves duplicate
            // names through semantic-draft normalization.
            return nodes.enumerated().compactMap {
                index, node in
                guard let displayName =
                        nodesByKey[node]?
                            .displayName else {
                    return nil
                }
                return language == .german
                    ? "\(displayName) Auswahlposition \(index + 1)"
                    : "\(displayName) selection position \(index + 1)"
            }
        case .findNodes,
            .entityList,
            .filteredCollection,
            .count,
            .groupCount,
            .refinement,
            .inspectGraphState,
            .relationships,
            .unrecognized,
            .openEnded:
            return []
        }
    }

    private func projectionTerms(
        request:
            GraphChatInterpretationCorrectionRequest,
        family:
            GraphChatSemanticIntentFamily,
        fields:
            [GraphSchemaFieldResolution]
    ) -> [String] {
        guard
            family == .compareNodes,
            fields.isEmpty,
            let origin =
                request.binding
                    .originalInterpretation
                    .correctionOrigin,
            case .compareNodes(let plan) =
                origin.adaptation.action,
            plan.kind == .structural
        else {
            return fields.map(\.name)
        }
        return plan.features.compactMap {
            guard case .structure(let feature) = $0 else {
                return nil
            }
            switch (
                request.binding
                    .originalInterpretation
                    .responseLanguage,
                feature
            ) {
            case (.german, .nodeKind):
                return "Art"
            case (.english, .nodeKind):
                return "Kind"
            case (.german, .ownerDisplayName):
                return "Besitzer"
            case (.english, .ownerDisplayName):
                return "Owner"
            case (.german, .directLinkCount):
                return "Verbindungen"
            case (.english, .directLinkCount):
                return "Links"
            case (.german, .attachmentMetadataCount):
                return "Anhänge"
            case (.english, .attachmentMetadataCount):
                return "Attachments"
            case (.german, .hasNotes):
                return "Notizen"
            case (.english, .hasNotes):
                return "Notes"
            case (.german, .authoritativeDetailValueCount):
                return "Detailwerte"
            case (.english, .authoritativeDetailValueCount):
                return "Detail values"
            }
        }
    }

    private func effectiveResultAmount(
        _ selected:
            GraphChatSemanticResultAmount?,
        interpretation:
            GraphChatIntentInterpretation
    ) -> GraphChatSemanticResultAmount {
        if let selected {
            return selected
        }
        if interpretation
            .resultExtent
            .includesAllAuthorizedResults {
            return .all
        }
        switch interpretation.intentKind {
        case .findNodes, .entityCollection,
            .narrowResultSet:
            return .first(
                interpretation
                    .resultExtent
                    .resultLimit
            )
        case .countOrGroup, .nodeDetails,
            .compareNodes, .inspectGraphState,
            .relationships:
            return .standard
        }
    }

    private func entityTerm(
        for family:
            GraphChatSemanticIntentFamily,
        entity:
            GraphSchemaEntityResolution?
    ) -> String? {
        switch family {
        case .findNodes, .entityList,
            .filteredCollection, .count,
            .groupCount, .refinement,
            .nodeDetails:
            return entity?.name
        case .compareNodes,
            .inspectGraphState,
            .relationships,
            .unrecognized, .openEnded:
            return nil
        }
    }

    private func semanticFilter(
        _ correction:
            GraphChatInterpretationCorrectionFilter,
        field:
            GraphSchemaFieldResolution,
        language:
            GraphChatResponseLanguage
    ) throws -> GraphChatSemanticFilterDraft {
        GraphChatSemanticFilterDraft(
            fieldTerm: field.name,
            relation:
                relation(
                    for:
                        correction.operation
                ),
            values:
                try semanticValues(
                    correction.value,
                    operation:
                        correction.operation,
                    field: field,
                    language:
                        language
                )
        )
    }

    private func semanticSort(
        _ sorting:
            [GraphChatInterpretationCorrectionSort],
        entityID: UUID?,
        fieldsByID:
            [UUID:
                GraphSchemaFieldResolution],
        selectedFields:
            inout [
                GraphChatSemanticSelectedField
            ]
    ) throws -> GraphChatSemanticSortDraft? {
        guard sorting.count <= 1,
              Set(sorting.map(\.id)).count
                == sorting.count
        else {
            throw invalid(.invalidSort)
        }
        guard let sort = sorting.first else {
            return nil
        }
        switch sort.key {
        case .nodeName:
            return GraphChatSemanticSortDraft(
                target: .nodeName,
                fieldTerm: nil,
                direction:
                    semanticDirection(
                        sort.direction
                    )
            )
        case .field(let fieldID):
            let resolved = try field(
                id: fieldID,
                expectedEntityID:
                    entityID,
                fieldsByID:
                    fieldsByID
            )
            selectedFields.append(
                GraphChatSemanticSelectedField(
                    role: .sorting,
                    fieldID: fieldID
                )
            )
            return GraphChatSemanticSortDraft(
                target: .field,
                fieldTerm: resolved.name,
                direction:
                    semanticDirection(
                        sort.direction
                    )
            )
        }
    }

    private func semanticValues(
        _ value:
            GraphChatInterpretationCorrectionFilterValue,
        operation:
            GraphQueryFilterOperator,
        field:
            GraphSchemaFieldResolution,
        language:
            GraphChatResponseLanguage
    ) throws -> [String] {
        let values: [String]
        switch value {
        case .noValue:
            values = []
        case .text(let value),
            .integerInput(let value),
            .decimalInput(let value):
            values = [value]
        case .integerRangeInput(
            let lower,
            let upper
        ),
            .decimalRangeInput(
                let lower,
                let upper
            ):
            values = [lower, upper]
        case .date(let value):
            values = [dateString(value)]
        case .dateRange(
            let lower,
            let upper
        ):
            values = [
                dateString(lower),
                dateString(upper),
            ]
        case .year(let value):
            values = [String(value)]
        case .month(let value):
            values = [
                String(
                    format:
                        "%04d-%02d",
                    value.year,
                    value.month
                ),
            ]
        case .toggle(let value):
            values = [
                language == .german
                ? (
                    value
                    ? "ja"
                    : "nein"
                )
                : (
                    value
                    ? "yes"
                    : "no"
                ),
            ]
        case .choice(let value):
            values = [value]
        case .choices(let value):
            values = value
        }

        let noValueOperations:
            Set<GraphQueryFilterOperator> = [
                .isPresent,
                .isMissing,
                .isOverdue,
            ]
        guard
            noValueOperations
                .contains(operation)
                == values.isEmpty,
            values.count
                <= GraphChatSemanticSafety
                    .maximumValuesPerFilter
        else {
            throw invalid(
                .invalidFilterValue
            )
        }
        if field.type == .singleChoice {
            let optionSet =
                Set(field.choiceOptions)
            guard values.allSatisfy(
                optionSet.contains
            ) else {
                throw stale(
                    .schemaChanged
                )
            }
        }
        return values
    }

    private func dateString(
        _ date: Date
    ) -> String {
        let components =
            calendar.dateComponents(
                [.year, .month, .day],
                from: date
            )
        return String(
            format:
                "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func relation(
        for operation:
            GraphQueryFilterOperator
    ) -> GraphChatSemanticFilterRelation {
        switch operation {
        case .contains:
            return .contains
        case .equals:
            return .equals
        case .startsWith:
            return .startsWith
        case .isPresent:
            return .isPresent
        case .isMissing:
            return .isMissing
        case .lessThan:
            return .lessThan
        case .lessThanOrEqual:
            return .lessThanOrEqual
        case .greaterThan:
            return .greaterThan
        case .greaterThanOrEqual:
            return .greaterThanOrEqual
        case .between:
            return .between
        case .before:
            return .before
        case .after:
            return .after
        case .inYear:
            return .inYear
        case .inMonth:
            return .inMonth
        case .isOverdue:
            return .isOverdue
        case .oneOf:
            return .oneOf
        }
    }

    private func semanticDirection(
        _ direction:
            GraphQuerySortDirection
    ) -> GraphChatSemanticSortDirection {
        switch direction {
        case .ascending:
            return .ascending
        case .descending:
            return .descending
        }
    }

    private func validationIssue(
        for family:
            GraphChatSemanticIntentFamily
    ) -> GraphChatInterpretationCorrectionValidationIssue {
        switch family {
        case .findNodes:
            return .emptySearchTerm
        case .entityList,
            .filteredCollection,
            .count:
            return .invalidFilter
        case .groupCount:
            return .missingGroupingField
        case .refinement:
            return .invalidFilter
        case .nodeDetails,
            .compareNodes:
            return .invalidNodeSelection
        case .inspectGraphState:
            return .graphStateRequiresEntireGraph
        case .relationships:
            return .invalidRelationshipSelection
        case .unrecognized, .openEnded:
            return .interpretationNotEditable
        }
    }

    private func mapped(
        _ error:
            GraphChatSemanticIntentResolutionError
    ) -> GraphChatInterpretationCorrectionCompilationError {
        switch error {
        case .staleEntitySelection,
            .entityNotFound:
            return stale(
                .entityUnavailable
            )
        case .staleNodeSelection,
            .nodeNotFound:
            return stale(
                .nodeUnavailable
            )
        case .invalidSchemaIdentity:
            return stale(
                .schemaChanged
            )
        case .scopeViolation,
            .conversationSelectionMismatch:
            return invalid(
                .scopeExpansion
            )
        case .conversationSelectionUnavailable:
            return stale(
                .conversationChanged
            )
        case .graphStateRequiresEntireGraph:
            return invalid(
                .graphStateRequiresEntireGraph
            )
        case .comparisonLimitExceeded,
            .featureLimitExceeded,
            .unsupportedComparison,
            .unsupportedCombination,
            .fieldNotFound:
            return invalid(
                .invalidFieldSelection
            )
        }
    }

    private func stale(
        _ reason:
            GraphChatInterpretationCorrectionStaleReason
    ) -> GraphChatInterpretationCorrectionCompilationError {
        .stale(reason)
    }

    private func invalid(
        _ issue:
            GraphChatInterpretationCorrectionValidationIssue
    ) -> GraphChatInterpretationCorrectionCompilationError {
        .invalid(issue)
    }
}
