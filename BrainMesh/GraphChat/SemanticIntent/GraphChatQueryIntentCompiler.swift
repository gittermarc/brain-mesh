//
//  GraphChatQueryIntentCompiler.swift
//  BrainMesh
//
//  App-owned compilation of bounded semantic query meaning into a validated
//  read-only query action.
//

import Foundation

nonisolated enum GraphChatQueryIntentCompilationError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case unsupportedFamily
    case entityNotFound
    case staleSelection
    case fieldNotFound
    case fieldEntityMismatch
    case typeConflict
    case valueParsingRejected
    case projectionLimitExceeded
    case scopeExpansionPrevented
    case staleResultSet
    case invalidCompiledPlan

    var errorDescription: String? {
        switch self {
        case .unsupportedFamily:
            return "Die erkannte Intent-Familie ist keine lokal kompilierbare Query."
        case .entityNotFound:
            return "Die gemeinte Entity konnte im aktuellen Schema nicht sicher aufgelöst werden."
        case .staleSelection:
            return "Eine ausgewählte fachliche Bedeutung ist nicht mehr aktuell."
        case .fieldNotFound:
            return "Das gemeinte Feld konnte in der ausgewählten Entity nicht sicher aufgelöst werden."
        case .fieldEntityMismatch:
            return "Das gemeinte Feld gehört nicht zur ausgewählten Entity."
        case .typeConflict:
            return "Die fachliche Filterrelation passt nicht zum aktuellen Feldtyp."
        case .valueParsingRejected:
            return "Ein Filterwert konnte nicht eindeutig und typgerecht interpretiert werden."
        case .projectionLimitExceeded:
            return "Die gewünschte Projektion überschreitet das gemeinsame Spaltenlimit."
        case .scopeExpansionPrevented:
            return "Die Query würde den autorisierten oder revalidierten Ergebnisscope erweitern."
        case .staleResultSet:
            return "Die referenzierte Ergebnismenge ist nicht mehr frisch revalidierbar."
        case .invalidCompiledPlan:
            return "Der appseitig erzeugte Query-Plan hat die erneute Validierung nicht bestanden."
        }
    }
}

nonisolated enum GraphChatQueryIntentCompilationResult:
    Hashable,
    Sendable
{
    case compiled(GraphChatTypedIntentAdaptation)
    case clarification(GraphChatSemanticEntityClarification)
}

nonisolated struct GraphChatQueryIntentCompilationPolicy:
    Hashable,
    Sendable
{
    let maximumProjectedFields: Int
    let maximumEvidenceCount: Int

    static let `default` =
        GraphChatQueryIntentCompilationPolicy(
            maximumProjectedFields:
                GraphChatAnswerArtifactFactoryBudget
                    .default.maximumColumns - 1,
            maximumEvidenceCount:
                GraphChatQueryEngineLimits
                    .default.maximumEvidenceCount
        )

    init(
        maximumProjectedFields: Int,
        maximumEvidenceCount: Int
    ) {
        precondition(maximumProjectedFields > 0)
        precondition(maximumEvidenceCount > 1)
        self.maximumProjectedFields =
            maximumProjectedFields
        self.maximumEvidenceCount =
            maximumEvidenceCount
    }
}

nonisolated struct GraphChatQueryIntentCompiler:
    Hashable,
    Sendable
{
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let limitPolicy:
        GraphChatSemanticIntentLimitPolicy
    private let compilationPolicy:
        GraphChatQueryIntentCompilationPolicy
    private let valueParser:
        GraphChatQueryIntentValueParser

    init(
        calendar: Calendar,
        timeZone: TimeZone,
        limitPolicy:
            GraphChatSemanticIntentLimitPolicy = .default,
        compilationPolicy:
            GraphChatQueryIntentCompilationPolicy = .default
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
        self.limitPolicy = limitPolicy
        self.compilationPolicy =
            compilationPolicy
        self.valueParser =
            GraphChatQueryIntentValueParser(
                calendar: configuredCalendar,
                timeZone: timeZone
            )
    }

    func compile(
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedEntityID: UUID?,
        selectedFields:
            [GraphChatSemanticSelectedField],
        currentResolvedScope:
            GraphChatResolvedConversationScope?,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?,
        referenceDate: Date
    ) throws -> GraphChatQueryIntentCompilationResult {
        guard isQueryFamily(draft.family) else {
            throw GraphChatQueryIntentCompilationError
                .unsupportedFamily
        }
        guard
            schemaContext.graphScope
                == providerPlan.scopeKey.graphScope,
            schemaContext.aliases.graphScope
                == schemaContext.graphScope
        else {
            throw GraphChatQueryIntentCompilationError
                .invalidCompiledPlan
        }
        guard Set(selectedFields.map(\.role)).count
                == selectedFields.count else {
            throw GraphChatQueryIntentCompilationError
                .staleSelection
        }

        let source = try validatedSource(
            currentResolvedScope,
            draft: draft,
            selectedEntityID: selectedEntityID,
            providerPlan: providerPlan,
            schemaContext: schemaContext
        )
        let entityResolution = try resolveEntity(
            term: draft.entityTerm,
            selectedEntityID: selectedEntityID,
            selectedFields: selectedFields,
            source: source,
            draft: draft,
            providerPlan: providerPlan,
            schemaContext: schemaContext
        )
        switch entityResolution {
        case .clarification(let clarification):
            return .clarification(clarification)
        case .resolved(let entity):
            return try compile(
                draft: draft,
                entity: entity,
                selectedFields: selectedFields,
                source: source,
                providerPlan: providerPlan,
                schemaContext: schemaContext,
                requestID: requestID,
                sourceTurnID: sourceTurnID,
                clarificationID: clarificationID,
                referenceDate: referenceDate
            )
        }
    }

    private struct ValidatedSource {
        let scope: GraphChatResolvedConversationScope
        let plan: ValidatedGraphQueryPlan
    }

    private enum EntityResolution {
        case resolved(GraphSchemaEntityResolution)
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private enum FieldResolution {
        case resolved(GraphSchemaFieldResolution)
        case clarification(
            GraphChatSemanticEntityClarification
        )
    }

    private func validatedSource(
        _ source: GraphChatResolvedConversationScope?,
        draft: GraphChatUntrustedSemanticIntentDraft,
        selectedEntityID: UUID?,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws -> ValidatedSource? {
        let requiresSource =
            draft.family == .refinement
                || draft.conversationReference
                    == .currentSelection
                || source != nil
        guard requiresSource else {
            return nil
        }
        guard
            let source,
            providerPlan.currentResolvedScope
                == source,
            providerPlan.conversationContext
                .currentResolvedScope == source,
            source.graphScope
                == providerPlan.scopeKey.graphScope,
            source.chatScope
                == providerPlan.scopeKey.chatScope,
            source.conversationID
                == providerPlan.requestBaseState
                    .conversationID,
            source.nodes.isEmpty == false,
            Set(source.nodes).count
                == source.nodes.count,
            source.nodes.allSatisfy({
                $0.kind == .attribute
                    && schemaContext.aliases
                        .owningEntityID(for: $0)
                        == source.entityID
            }),
            let sourceResultID =
                source.revision.sourceResultID,
            let sourceAlias =
                source.revision.sourceAlias,
            let sourceTurnID =
                source.revision.sourceTurnID,
            let sourceTurnCompletedAt =
                source.revision
                    .sourceTurnCompletedAt,
            let plan =
                source.revision
                    .validatedQueryPlan,
            plan.graphScope == source.graphScope,
            plan.entityID == source.entityID,
            let contextResult =
                providerPlan.conversationContext
                    .results.first(
                        where: {
                            $0.id == sourceResultID
                                && $0.alias
                                    == sourceAlias
                        }
                    ),
            contextResult.sourceReferenceCount
                == source.revision
                    .sourceReferenceCount,
            let contextTurn =
                providerPlan.conversationContext
                    .turns.first(
                        where: {
                            $0.id == sourceTurnID
                                && $0.completedAt
                                    == sourceTurnCompletedAt
                                && $0.resultAliases
                                    .contains(
                                        contextResult
                                            .alias
                                    )
                        }
                    ),
            contextTurn.id == sourceTurnID,
            providerPlan.conversationContext
                .resultRevalidations
                .contains(
                    where: {
                        $0.resultAlias
                            == contextResult.alias
                            && $0.plan == plan
                            && $0.sourceReferenceCount
                                == source.revision
                                    .sourceReferenceCount
                    }
                )
        else {
            throw GraphChatQueryIntentCompilationError
                .staleResultSet
        }
        if let selectedEntityID,
           selectedEntityID != source.entityID {
            throw GraphChatQueryIntentCompilationError
                .scopeExpansionPrevented
        }
        let exactScope = try queryScope(
            for: source.nodes,
            graphScope: source.graphScope
        )
        guard
            GraphChatScopeAuthorization.allows(
                scope: exactScope,
                within: source.chatScope,
                aliases: schemaContext.aliases
            )
        else {
            throw GraphChatQueryIntentCompilationError
                .scopeExpansionPrevented
        }
        return ValidatedSource(
            scope: source,
            plan: plan
        )
    }

    private func resolveEntity(
        term: String?,
        selectedEntityID: UUID?,
        selectedFields:
            [GraphChatSemanticSelectedField],
        source: ValidatedSource?,
        draft: GraphChatUntrustedSemanticIntentDraft,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws -> EntityResolution {
        if let source {
            guard
                let entity =
                    schemaContext.aliases
                        .entity(
                            id:
                                source.scope
                                    .entityID
                        )
            else {
                throw GraphChatQueryIntentCompilationError
                    .staleResultSet
            }
            if let selectedEntityID,
               selectedEntityID != entity.entityID {
                throw GraphChatQueryIntentCompilationError
                    .scopeExpansionPrevented
            }
            if let term {
                let candidates = matchingEntities(
                    term,
                    schemaContext: schemaContext
                )
                guard candidates.contains(
                    where: {
                        $0.entityID
                            == entity.entityID
                    }
                ) else {
                    throw GraphChatQueryIntentCompilationError
                        .scopeExpansionPrevented
                }
            }
            return .resolved(entity)
        }

        if let term {
            let candidates = matchingEntities(
                term,
                schemaContext: schemaContext
            )
            guard candidates.isEmpty == false else {
                throw GraphChatQueryIntentCompilationError
                    .entityNotFound
            }
            if let selectedEntityID {
                guard
                    let selected = candidates.first(
                        where: {
                            $0.entityID
                                == selectedEntityID
                        }
                    )
                else {
                    throw GraphChatQueryIntentCompilationError
                        .staleSelection
                }
                return .resolved(selected)
            }
            guard candidates.count == 1 else {
                let question =
                    draft.responseLanguage == .german
                    ? "Welche Entity mit dem Namen „\(term)“ meinst du?"
                    : "Which entity named “\(term)” do you mean?"
                return .clarification(
                    GraphChatSemanticEntityClarification(
                        question: question,
                        candidates: candidates.map {
                            GraphChatSemanticEntityCandidate(
                                entityID: $0.entityID,
                                displayName: $0.name,
                                selectedFields:
                                    selectedFields
                            )
                        },
                        draft: draft
                    )
                )
            }
            return .resolved(candidates[0])
        }

        guard
            let entityID = scopedEntityID(
                providerPlan.scopeKey.chatScope,
                aliases: schemaContext.aliases
            ),
            let entity =
                schemaContext.aliases
                    .entity(id: entityID)
        else {
            throw GraphChatQueryIntentCompilationError
                .entityNotFound
        }
        if let selectedEntityID,
           selectedEntityID != entity.entityID {
            throw GraphChatQueryIntentCompilationError
                .staleSelection
        }
        return .resolved(entity)
    }

    private func compile(
        draft: GraphChatUntrustedSemanticIntentDraft,
        entity: GraphSchemaEntityResolution,
        selectedFields:
            [GraphChatSemanticSelectedField],
        source: ValidatedSource?,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        sourceTurnID: UUID?,
        clarificationID: UUID?,
        referenceDate: Date
    ) throws -> GraphChatQueryIntentCompilationResult {
        var resolvedFields:
            [GraphChatSemanticFieldSelectionRole:
                GraphSchemaFieldResolution] = [:]
        var usedRoles =
            Set<GraphChatSemanticFieldSelectionRole>()

        func field(
            term: String,
            role: GraphChatSemanticFieldSelectionRole
        ) throws -> FieldResolution {
            usedRoles.insert(role)
            return try resolveField(
                term: term,
                role: role,
                entity: entity,
                selectedFields: selectedFields,
                draft: draft,
                schemaContext: schemaContext
            )
        }

        for (index, filter) in
            draft.filters.enumerated()
        {
            let role:
                GraphChatSemanticFieldSelectionRole =
                .filter(index)
            switch try field(
                term: filter.fieldTerm,
                role: role
            ) {
            case .resolved(let value):
                resolvedFields[role] = value
            case .clarification(let clarification):
                return .clarification(clarification)
            }
        }
        if let sorting = draft.sorting,
           sorting.target == .field,
           let term = sorting.fieldTerm {
            switch try field(
                term: term,
                role: .sorting
            ) {
            case .resolved(let value):
                resolvedFields[.sorting] = value
            case .clarification(let clarification):
                return .clarification(clarification)
            }
        }
        for (index, term) in
            draft.projectionTerms.enumerated()
        {
            let role:
                GraphChatSemanticFieldSelectionRole =
                .projection(index)
            switch try field(
                term: term,
                role: role
            ) {
            case .resolved(let value):
                resolvedFields[role] = value
            case .clarification(let clarification):
                return .clarification(clarification)
            }
        }
        if let term = draft.groupFieldTerm {
            switch try field(
                term: term,
                role: .grouping
            ) {
            case .resolved(let value):
                resolvedFields[.grouping] = value
            case .clarification(let clarification):
                return .clarification(clarification)
            }
        }
        guard Set(selectedFields.map(\.role))
                .isSubset(of: usedRoles) else {
            throw GraphChatQueryIntentCompilationError
                .staleSelection
        }

        var filters: [GraphQueryFilter] = []
        if let source {
            filters = try source.plan.filters.map {
                try sourceFilter(
                    $0,
                    schemaContext: schemaContext
                )
            }
        }
        for (index, draftFilter) in
            draft.filters.enumerated()
        {
            guard
                let field =
                    resolvedFields[.filter(index)]
            else {
                throw GraphChatQueryIntentCompilationError
                    .invalidCompiledPlan
            }
            do {
                filters.append(
                    try valueParser.filter(
                        draftFilter,
                        field: field,
                        language:
                            draft.responseLanguage,
                        referenceDate:
                            referenceDate
                    )
                )
            } catch let error
                as GraphChatQueryIntentValueParsingError {
                switch error {
                case .incompatibleRelation:
                    throw GraphChatQueryIntentCompilationError
                        .typeConflict
                case .invalidValue, .ambiguousChoice:
                    throw GraphChatQueryIntentCompilationError
                        .valueParsingRejected
                }
            }
        }
        filters = deduplicated(filters)

        let isCount = draft.family == .count
        let isGroup = draft.family == .groupCount
        let isCollection = isCount == false
            && isGroup == false

        let sorting: [GraphQuerySort]
        if isCollection {
            if let semanticSort = draft.sorting {
                sorting = [
                    try querySort(
                        semanticSort,
                        field:
                            resolvedFields[.sorting]
                    )
                ]
            } else if let source {
                let inherited = try source.plan
                    .sorting.map {
                        try sourceSort(
                            $0,
                            schemaContext:
                                schemaContext
                        )
                    }
                sorting = inherited.isEmpty
                    ? [defaultNameSort()]
                    : inherited
            } else {
                sorting = [defaultNameSort()]
            }
        } else {
            sorting = []
        }

        var projectedFields:
            [GraphSchemaFieldResolution] = []
        if isCollection {
            if draft.projectionTerms.isEmpty == false {
                for index in
                    draft.projectionTerms.indices
                {
                    guard
                        let field =
                            resolvedFields[
                                .projection(index)
                            ]
                    else {
                        throw GraphChatQueryIntentCompilationError
                            .invalidCompiledPlan
                    }
                    projectedFields.append(field)
                }
            } else if let source {
                projectedFields =
                    try source.plan.projection
                        .compactMap {
                            projection in
                            guard
                                case .field(
                                    let fieldID
                                ) = projection
                            else {
                                return nil
                            }
                            return try fieldResolution(
                                id: fieldID,
                                schemaContext:
                                    schemaContext
                            )
                        }
            }
            projectedFields =
                deduplicated(projectedFields)
            guard projectedFields.count
                    <= compilationPolicy
                        .maximumProjectedFields else {
                throw GraphChatQueryIntentCompilationError
                    .projectionLimitExceeded
            }
        }

        let projection: [GraphQueryProjection] =
            [.nodeIdentity]
            + projectedFields.map {
                .field($0.alias)
            }
        let aggregation:
            GraphQueryAggregation?
        if isCount {
            aggregation = .count
        } else if isGroup {
            guard
                let grouping =
                    resolvedFields[.grouping]
            else {
                throw GraphChatQueryIntentCompilationError
                    .invalidCompiledPlan
            }
            aggregation =
                .groupCount(grouping.alias)
        } else {
            aggregation = nil
        }

        let queryScope: GraphChatScope
        if let source {
            queryScope = try self.queryScope(
                for: source.scope.nodes,
                graphScope:
                    source.scope.graphScope
            )
        } else {
            queryScope = try scopedQueryScope(
                entityID: entity.entityID,
                chatScope:
                    providerPlan.scopeKey
                        .chatScope,
                aliases: schemaContext.aliases
            )
        }
        guard
            GraphChatScopeAuthorization.allows(
                scope: queryScope,
                within:
                    providerPlan.scopeKey
                        .chatScope,
                aliases: schemaContext.aliases
            )
        else {
            throw GraphChatQueryIntentCompilationError
                .scopeExpansionPrevented
        }

        let requestedLimit: Int
        if isCount {
            requestedLimit =
                GraphQueryPlanLimits
                    .maximumResultLimit
        } else if let source,
                  draft.resultAmount == .standard {
            requestedLimit = source.plan.limit
        } else {
            requestedLimit =
                limitPolicy.entityListLimit(
                    for: draft.resultAmount
                )
        }
        let fieldEvidenceCount = Set(
            filters.map(\.fieldAlias)
                + sorting.compactMap {
                    if case .field(let alias) = $0.key {
                        return alias
                    }
                    return nil
                }
                + projection.compactMap {
                    if case .field(let alias) = $0 {
                        return alias
                    }
                    return nil
                }
        ).count
        let limit: Int
        if isCollection {
            let perRowEvidence =
                max(1, fieldEvidenceCount + 1)
            let evidenceBoundedLimit = max(
                1,
                compilationPolicy
                    .maximumEvidenceCount
                    / perRowEvidence
            )
            limit = min(
                GraphQueryPlanLimits
                    .maximumResultLimit,
                min(
                    requestedLimit,
                    evidenceBoundedLimit
                )
            )
        } else {
            limit = min(
                GraphQueryPlanLimits
                    .maximumResultLimit,
                requestedLimit
            )
        }

        let rawPlan = GraphQueryPlan(
            entityAlias: entity.alias,
            scope: queryScope,
            filters: filters,
            sorting: sorting,
            projection: projection,
            aggregation: aggregation,
            limit: limit
        )
        let validator = GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: referenceDate
        )
        let validatedPlan: ValidatedGraphQueryPlan
        do {
            validatedPlan = try validator.validate(
                rawPlan,
                against: schemaContext
            )
        } catch {
            throw GraphChatQueryIntentCompilationError
                .invalidCompiledPlan
        }
        guard
            validatedPlan.entityID
                == entity.entityID,
            validatedPlan.limit == limit,
            validatedPlan.projection.first
                == .nodeIdentity,
            GraphChatScopeAuthorization.allows(
                plan: validatedPlan,
                within:
                    providerPlan.scopeKey
                        .chatScope
            )
        else {
            throw GraphChatQueryIntentCompilationError
                .scopeExpansionPrevented
        }

        let typedEntity =
            GraphChatTypedEntityIdentity(
                id: entity.entityID,
                alias: entity.alias,
                displayName: entity.name
            )
        let allFieldIDs = fieldIDs(
            in: validatedPlan
        )
        let referencedFields = try allFieldIDs
            .sorted {
                $0.uuidString < $1.uuidString
            }
            .map {
                try typedField(
                    id: $0,
                    schemaContext: schemaContext
                )
            }
        let typedProjectedFields =
            try validatedPlan.projection
                .compactMap {
                    projection
                        -> GraphChatTypedFieldIdentity?
                    in
                    guard
                        case .field(let fieldID) =
                            projection
                    else {
                        return nil
                    }
                    return try typedField(
                        id: fieldID,
                        schemaContext:
                            schemaContext
                    )
                }

        let sourceNodes:
            [GraphChatTypedNodeIdentity]
        if let source {
            sourceNodes = try source.scope.nodes.map {
                node in
                guard
                    let resolution =
                        schemaContext.aliases
                            .nodesByKey[node],
                    resolution.ownerEntityID
                        == entity.entityID
                else {
                    throw GraphChatQueryIntentCompilationError
                        .staleResultSet
                }
                return GraphChatTypedNodeIdentity(
                    node: node,
                    displayName:
                        resolution.displayName,
                    ownerEntityID:
                        resolution.ownerEntityID
                )
            }
        } else {
            sourceNodes = []
        }

        let payload:
            GraphChatTypedIntentPayload
        let contract:
            GraphChatLocalQueryResultContract
        if isCount {
            payload = .countOrGroup(
                GraphChatTypedCountOrGroupIntent(
                    entity: typedEntity,
                    operation: .count,
                    referencedFields:
                        referencedFields
                )
            )
            contract = .count
        } else if isGroup {
            guard
                let groupField =
                    referencedFields.first(
                        where: {
                            if case .groupCount(
                                let fieldID
                            )? = validatedPlan
                                .aggregation
                            {
                                return $0.id == fieldID
                            }
                            return false
                        }
                    )
            else {
                throw GraphChatQueryIntentCompilationError
                    .invalidCompiledPlan
            }
            payload = .countOrGroup(
                GraphChatTypedCountOrGroupIntent(
                    entity: typedEntity,
                    operation:
                        .group(field: groupField),
                    referencedFields:
                        referencedFields
                )
            )
            contract = .groupCount
        } else if let source {
            guard
                let sourceResultID =
                    source.scope.revision
                        .sourceResultID
            else {
                throw GraphChatQueryIntentCompilationError
                    .staleResultSet
            }
            payload = .narrowResultSet(
                GraphChatTypedNarrowResultSetIntent(
                    sourceResultContextID:
                        sourceResultID,
                    entity: typedEntity,
                    nodes: sourceNodes,
                    fields: referencedFields,
                    projectedFields:
                        typedProjectedFields
                )
            )
            contract = .refinement
        } else {
            payload = .entityCollection(
                GraphChatTypedEntityCollectionIntent(
                    entity: typedEntity,
                    projectedFields:
                        typedProjectedFields,
                    referencedFields:
                        referencedFields
                )
            )
            let isLegacyCollection =
                draft.family == .entityList
                && draft.filters.isEmpty
                && draft.sorting == nil
                && draft.projectionTerms.isEmpty
            contract = isLegacyCollection
                ? .entityCollection
                : .compiledCollection
        }

        let binding = GraphChatTypedIntentBinding(
            requestID: requestID,
            conversationID:
                providerPlan.requestBaseState
                    .conversationID,
            turnID: requestID,
            sourceTurnID:
                sourceTurnID
                ?? source?.scope.revision
                    .sourceTurnID,
            clarificationID: clarificationID
        )
        let resolution =
            GraphChatTypedIntentResolution(
                source:
                    source != nil
                    || clarificationID != nil
                    ? .conversationContinuation
                    : .appSemanticResolution,
                origin:
                    clarificationID != nil
                    ? .clarificationSelection
                    : (
                        source != nil
                        ? .conversationReference
                        : .schemaDisplayName
                    ),
                quality:
                    clarificationID != nil
                    ? .revalidatedClarification
                    : (
                        source != nil
                        ? .revalidatedConversationReference
                        : .exact
                    )
            )
        let maximumEvidenceCount: Int
        if isCollection {
            maximumEvidenceCount = min(
                compilationPolicy
                    .maximumEvidenceCount,
                limit * max(
                    1,
                    fieldEvidenceCount + 1
                )
            )
        } else if isGroup {
            maximumEvidenceCount =
                compilationPolicy
                    .maximumEvidenceCount
        } else {
            maximumEvidenceCount = min(
                compilationPolicy
                    .maximumEvidenceCount,
                limit + 1
            )
        }
        let intent = try GraphChatTypedIntent(
            version: .v1,
            scope: GraphChatTypedIntentScope(
                graphScope:
                    providerPlan.scopeKey
                        .graphScope,
                chatScope:
                    providerPlan.scopeKey
                        .chatScope,
                queryScope: queryScope
            ),
            responseLanguage:
                draft.responseLanguage,
            binding: binding,
            resolution: resolution,
            expectedCardinality:
                isCount ? .exactlyOne : .zeroOrMore,
            factExpectation: .none,
            limits: GraphChatTypedIntentLimits(
                resultLimit: limit,
                maximumResultLimit:
                    GraphQueryPlanLimits
                        .maximumResultLimit,
                maximumEvidenceCount:
                    maximumEvidenceCount,
                maximumArtifactCount: 1
            ),
            payload: payload
        )
        return .compiled(
            GraphChatTypedIntentAdaptation(
                intent: intent,
                action: .queryDetailValues(
                    GraphChatLocalQueryAction(
                        plan: rawPlan,
                        resultContract: contract,
                        refinementSource:
                            source?.scope,
                        compilationReferenceDate:
                            referenceDate
                    )
                )
            )
        )
    }

    private func resolveField(
        term: String,
        role: GraphChatSemanticFieldSelectionRole,
        entity: GraphSchemaEntityResolution,
        selectedFields:
            [GraphChatSemanticSelectedField],
        draft: GraphChatUntrustedSemanticIntentDraft,
        schemaContext: GraphSchemaContext
    ) throws -> FieldResolution {
        let folded = BMSearch.fold(term)
        let allMatches = schemaContext.aliases
            .fieldsByAlias.values
            .filter {
                BMSearch.fold($0.name) == folded
            }
            .sorted(by: fieldSort)
        let candidates = allMatches.filter {
            $0.entityID == entity.entityID
        }
        guard candidates.isEmpty == false else {
            throw allMatches.isEmpty
                ? GraphChatQueryIntentCompilationError
                    .fieldNotFound
                : GraphChatQueryIntentCompilationError
                    .fieldEntityMismatch
        }

        if let selected =
            selectedFields.first(
                where: { $0.role == role }
            )
        {
            guard
                let field = candidates.first(
                    where: {
                        $0.fieldID
                            == selected.fieldID
                    }
                )
            else {
                throw GraphChatQueryIntentCompilationError
                    .staleSelection
            }
            return .resolved(field)
        }
        guard candidates.count == 1 else {
            let question =
                draft.responseLanguage == .german
                ? "Welches Feld „\(term)“ meinst du?"
                : "Which “\(term)” field do you mean?"
            return .clarification(
                GraphChatSemanticEntityClarification(
                    question: question,
                    candidates:
                        candidates.map {
                            candidate in
                            var bindings =
                                selectedFields.filter {
                                    $0.role != role
                                }
                            bindings.append(
                                GraphChatSemanticSelectedField(
                                    role: role,
                                    fieldID:
                                        candidate
                                            .fieldID
                                )
                            )
                            return GraphChatSemanticEntityCandidate(
                                entityID:
                                    entity.entityID,
                                displayName:
                                    fieldClarificationLabel(
                                        candidate,
                                        language:
                                            draft
                                                .responseLanguage
                                    ),
                                selectedFields:
                                    bindings
                            )
                        },
                    draft: draft
                )
            )
        }
        return .resolved(candidates[0])
    }

    private func matchingEntities(
        _ term: String,
        schemaContext: GraphSchemaContext
    ) -> [GraphSchemaEntityResolution] {
        let folded = BMSearch.fold(term)
        return schemaContext.aliases
            .entitiesByAlias.values
            .filter {
                BMSearch.fold($0.name) == folded
            }
            .sorted { lhs, rhs in
                if lhs.name != rhs.name {
                    return lhs.name < rhs.name
                }
                return lhs.entityID.uuidString < rhs.entityID.uuidString
            }
    }

    private func scopedEntityID(
        _ scope: GraphChatScope,
        aliases: GraphSchemaAliasMap
    ) -> UUID? {
        switch scope.target {
        case .graph:
            return nil
        case .entity(let entityID):
            return entityID
        case .node(let node):
            return aliases.owningEntityID(
                for: node
            )
        case .selection(let nodes):
            let entityIDs = Set(
                nodes.compactMap {
                    aliases.owningEntityID(
                        for: $0
                    )
                }
            )
            return entityIDs.count == 1
                ? entityIDs.first
                : nil
        }
    }

    private func scopedQueryScope(
        entityID: UUID,
        chatScope: GraphChatScope,
        aliases: GraphSchemaAliasMap
    ) throws -> GraphChatScope {
        switch chatScope.target {
        case .graph:
            return .entity(
                entityID,
                in: chatScope.graphScope
            )
        case .entity(let scopedEntityID):
            guard scopedEntityID == entityID else {
                throw GraphChatQueryIntentCompilationError
                    .scopeExpansionPrevented
            }
            return chatScope
        case .node(let node):
            guard aliases.owningEntityID(
                for: node
            ) == entityID else {
                throw GraphChatQueryIntentCompilationError
                    .scopeExpansionPrevented
            }
            return chatScope
        case .selection(let nodes):
            let matching = nodes.filter {
                aliases.owningEntityID(for: $0)
                    == entityID
            }
            guard matching.isEmpty == false else {
                throw GraphChatQueryIntentCompilationError
                    .scopeExpansionPrevented
            }
            return try queryScope(
                for: matching,
                graphScope:
                    chatScope.graphScope
            )
        }
    }

    private func queryScope(
        for nodes: [NodeRefKey],
        graphScope: GraphScope
    ) throws -> GraphChatScope {
        let unique = Array(Set(nodes)).sorted {
            lhs,
            rhs in
            if lhs.kind.rawValue
                != rhs.kind.rawValue {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard unique.isEmpty == false,
              unique.allSatisfy({
                $0.kind == .attribute
              }) else {
            throw GraphChatQueryIntentCompilationError
                .scopeExpansionPrevented
        }
        if unique.count == 1 {
            return .node(
                unique[0],
                in: graphScope
            )
        }
        return try .selection(
            unique,
            in: graphScope
        )
    }

    private func querySort(
        _ source: GraphChatSemanticSortDraft,
        field: GraphSchemaFieldResolution?
    ) throws -> GraphQuerySort {
        let direction:
            GraphQuerySortDirection =
            source.direction == .descending
            ? .descending
            : .ascending
        switch source.target {
        case .nodeName:
            return GraphQuerySort(
                key: .nodeName,
                direction: direction
            )
        case .field:
            guard let field else {
                throw GraphChatQueryIntentCompilationError
                    .invalidCompiledPlan
            }
            return GraphQuerySort(
                key: .field(field.alias),
                direction: direction
            )
        }
    }

    private func defaultNameSort() -> GraphQuerySort {
        GraphQuerySort(
            key: .nodeName,
            direction: .ascending
        )
    }

    private func sourceFilter(
        _ source: GraphValidatedQueryFilter,
        schemaContext: GraphSchemaContext
    ) throws -> GraphQueryFilter {
        let field = try fieldResolution(
            id: source.fieldID,
            schemaContext: schemaContext
        )
        var operation = source.operation
        let value: GraphQueryFilterValue
        switch source.value {
        case .none:
            value = .none
        case .text(let text):
            value = .text(text)
        case .integer(let number):
            value = .integer(number)
        case .integerRange(let range):
            value = .integerRange(range)
        case .decimal(let number):
            value = .decimal(number)
        case .decimalRange(let range):
            value = .decimalRange(range)
        case .date(let date):
            if source.operation == .before
                || source.operation == .after
            {
                guard calendar.startOfDay(
                    for: date
                ) == date else {
                    throw GraphChatQueryIntentCompilationError
                        .staleResultSet
                }
            }
            value = .date(date)
        case .dateInterval(let interval):
            switch source.operation {
            case .equals:
                let lowerBound = calendar.startOfDay(
                    for: interval.lowerBound
                )
                guard
                    lowerBound == interval.lowerBound,
                    calendar.date(
                        byAdding: .day,
                        value: 1,
                        to: lowerBound
                    ) == interval.upperBoundExclusive
                else {
                    throw GraphChatQueryIntentCompilationError
                        .staleResultSet
                }
                value = .date(
                    lowerBound
                )
            case .inYear:
                guard let year = calendar
                    .dateComponents(
                        [.year],
                        from:
                            interval
                                .lowerBound
                    ).year,
                      try calendarInterval(
                        year: year
                      ) == interval else {
                    throw GraphChatQueryIntentCompilationError
                        .staleResultSet
                }
                value = .year(year)
            case .inMonth:
                let components = calendar
                    .dateComponents(
                        [.year, .month],
                        from:
                            interval
                                .lowerBound
                    )
                guard
                    let year = components.year,
                    let month = components.month,
                    try calendarInterval(
                        year: year,
                        month: month
                    ) == interval
                else {
                    throw GraphChatQueryIntentCompilationError
                        .staleResultSet
                }
                value = .month(
                    GraphQueryYearMonth(
                        year: year,
                        month: month
                    )
                )
            case .isOverdue:
                guard calendar.startOfDay(
                    for:
                        interval
                            .upperBoundExclusive
                ) == interval
                    .upperBoundExclusive else {
                    throw GraphChatQueryIntentCompilationError
                        .staleResultSet
                }
                operation = .before
                value = .date(
                    interval
                        .upperBoundExclusive
                )
            case .between:
                guard
                    calendar.startOfDay(
                        for:
                            interval
                                .lowerBound
                    ) == interval.lowerBound,
                    calendar.startOfDay(
                        for:
                            interval
                                .upperBoundExclusive
                    ) == interval
                        .upperBoundExclusive
                else {
                    throw GraphChatQueryIntentCompilationError
                        .staleResultSet
                }
                value = .dateInterval(
                    interval
                )
            default:
                value = .dateInterval(
                    interval
                )
            }
        case .boolean(let boolean):
            value = .boolean(boolean)
        case .choice(let choice):
            value = .choice(
                choice.canonicalValue
            )
        case .choices(let choices):
            value = .choices(
                choices.map(
                    \.canonicalValue
                )
            )
        }
        return GraphQueryFilter(
            fieldAlias: field.alias,
            operation: operation,
            value: value
        )
    }

    private func calendarInterval(
        year: Int,
        month: Int? = nil
    ) throws -> GraphQueryDateInterval {
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month ?? 1,
            day: 1
        )
        guard
            let lowerBound =
                calendar.date(from: components),
            let upperBound = calendar.date(
                byAdding:
                    month == nil ? .year : .month,
                value: 1,
                to: lowerBound
            ),
            lowerBound < upperBound
        else {
            throw GraphChatQueryIntentCompilationError
                .staleResultSet
        }
        return GraphQueryDateInterval(
            lowerBound: lowerBound,
            upperBoundExclusive: upperBound
        )
    }

    private func sourceSort(
        _ source: GraphValidatedQuerySort,
        schemaContext: GraphSchemaContext
    ) throws -> GraphQuerySort {
        switch source.key {
        case .nodeName:
            return GraphQuerySort(
                key: .nodeName,
                direction: source.direction
            )
        case .field(let fieldID):
            let field = try fieldResolution(
                id: fieldID,
                schemaContext: schemaContext
            )
            return GraphQuerySort(
                key: .field(field.alias),
                direction: source.direction
            )
        }
    }

    private func fieldResolution(
        id: UUID,
        schemaContext: GraphSchemaContext
    ) throws -> GraphSchemaFieldResolution {
        guard
            let field =
                schemaContext.aliases
                    .fieldsByAlias.values
                    .first(
                        where: {
                            $0.fieldID == id
                        }
                    )
        else {
            throw GraphChatQueryIntentCompilationError
                .staleResultSet
        }
        return field
    }

    private func typedField(
        id: UUID,
        schemaContext: GraphSchemaContext
    ) throws -> GraphChatTypedFieldIdentity {
        let field = try fieldResolution(
            id: id,
            schemaContext: schemaContext
        )
        return GraphChatTypedFieldIdentity(
            id: field.fieldID,
            alias: field.alias,
            displayName: field.name,
            ownerEntityID: field.entityID,
            type: field.type,
            unit: field.unit
        )
    }

    private func fieldIDs(
        in plan: ValidatedGraphQueryPlan
    ) -> Set<UUID> {
        var ids = Set(plan.filters.map(\.fieldID))
        for sort in plan.sorting {
            if case .field(let fieldID) =
                sort.key {
                ids.insert(fieldID)
            }
        }
        for projection in plan.projection {
            if case .field(let fieldID) =
                projection {
                ids.insert(fieldID)
            }
        }
        switch plan.aggregation {
        case .groupCount(let fieldID),
            .minimum(let fieldID),
            .maximum(let fieldID):
            ids.insert(fieldID)
        case .count, nil:
            break
        }
        return ids
    }

    private func deduplicated(
        _ source: [GraphQueryFilter]
    ) -> [GraphQueryFilter] {
        var seen = Set<GraphQueryFilter>()
        return source.filter {
            seen.insert($0).inserted
        }
    }

    private func deduplicated(
        _ source: [GraphSchemaFieldResolution]
    ) -> [GraphSchemaFieldResolution] {
        var seen = Set<UUID>()
        return source.filter {
            seen.insert($0.fieldID).inserted
        }
    }

    private func fieldSort(
        _ lhs: GraphSchemaFieldResolution,
        _ rhs: GraphSchemaFieldResolution
    ) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        if lhs.type != rhs.type {
            return lhs.type.rawValue < rhs.type.rawValue
        }
        return lhs.fieldID.uuidString < rhs.fieldID.uuidString
    }

    private func fieldClarificationLabel(
        _ field: GraphSchemaFieldResolution,
        language: GraphChatResponseLanguage
    ) -> String {
        let typeLabel: String
        switch (language, field.type) {
        case (.german, .singleLineText):
            typeLabel = "Text"
        case (.english, .singleLineText):
            typeLabel = "Text"
        case (.german, .multiLineText):
            typeLabel = "Langtext"
        case (.english, .multiLineText):
            typeLabel = "Long text"
        case (.german, .numberInt):
            typeLabel = "Ganzzahl"
        case (.english, .numberInt):
            typeLabel = "Integer"
        case (.german, .numberDouble):
            typeLabel = "Dezimalzahl"
        case (.english, .numberDouble):
            typeLabel = "Decimal"
        case (.german, .date):
            typeLabel = "Datum"
        case (.english, .date):
            typeLabel = "Date"
        case (.german, .toggle):
            typeLabel = "Ja/Nein"
        case (.english, .toggle):
            typeLabel = "Yes/No"
        case (.german, .singleChoice):
            typeLabel = "Auswahl"
        case (.english, .singleChoice):
            typeLabel = "Choice"
        }
        var parts = [field.name, typeLabel]
        if let unit = field.unit,
           unit.trimmingCharacters(
            in: .whitespacesAndNewlines
           ).isEmpty == false {
            parts.append(unit)
        }
        return parts.joined(separator: " · ")
    }

    private func isQueryFamily(
        _ family: GraphChatSemanticIntentFamily
    ) -> Bool {
        switch family {
        case .entityList, .filteredCollection,
            .count, .groupCount, .refinement:
            return true
        case .findNodes, .unrecognized,
            .openEnded:
            return false
        }
    }
}
