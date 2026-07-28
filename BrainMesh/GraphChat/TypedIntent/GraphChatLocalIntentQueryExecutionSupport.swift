//
//  GraphChatLocalIntentQueryExecutionSupport.swift
//  BrainMesh
//
//  Deterministic validation, result normalization and artifact staging for
//  the query actions currently accepted by the local execution kernel.
//

import Foundation

nonisolated struct GraphChatLocalIntentQueryExecutionSupport:
    Sendable
{
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let referenceDate: @Sendable () -> Date

    init(
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate: @escaping @Sendable () -> Date
    ) {
        self.calendar = calendar
        self.timeZone = timeZone
        self.referenceDate = referenceDate
    }

    func revalidateIdentities(
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext
    ) throws {
        guard schemaContext.graphScope
                == intent.scope.graphScope,
              schemaContext.aliases.graphScope
                == intent.scope.graphScope else {
            throw GraphChatLocalIntentExecutionError
                .invalidScope
        }
        for entity in intent.payload.entities {
            guard let resolution =
                schemaContext.aliases.entity(
                    for: entity.alias
                ),
                  resolution.entityID == entity.id,
                  resolution.name == entity.displayName else {
                throw GraphChatLocalIntentExecutionError
                    .staleSchemaIdentity
            }
        }
        for field in intent.payload.fields {
            guard let resolution =
                schemaContext.aliases.field(
                    for: field.alias
                ),
                  resolution.fieldID == field.id,
                  resolution.entityID
                    == field.ownerEntityID,
                  resolution.name == field.displayName,
                  resolution.type == field.type,
                  resolution.unit == field.unit else {
                throw GraphChatLocalIntentExecutionError
                    .staleSchemaIdentity
            }
        }
        for node in intent.payload.nodes {
            guard let resolution =
                schemaContext.aliases
                    .nodesByKey[node.node],
                  resolution.ownerEntityID
                    == node.ownerEntityID,
                  resolution.displayName
                    == node.displayName else {
                throw GraphChatLocalIntentExecutionError
                    .staleSchemaIdentity
            }
        }
    }

    func validatedPlan(
        adaptation: GraphChatTypedIntentAdaptation,
        schemaContext: GraphSchemaContext
    ) throws -> ValidatedGraphQueryPlan {
        let intent = adaptation.intent
        let action = try queryAction(
            in: adaptation.action
        )
        guard action.plan.scope
                == intent.scope.queryScope,
              action.plan.limit
                == intent.limits.resultLimit else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        let validator = GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate:
                action.compilationReferenceDate
                ?? referenceDate(),
            defaultLimit:
                GraphQueryPlanLimits.defaultResultLimit,
            maximumLimit:
                GraphQueryPlanLimits.maximumResultLimit
        )
        let plan = try validator.validate(
            action.plan,
            against: schemaContext
        )
        guard plan.graphScope
                == intent.scope.graphScope,
              plan.limit == intent.limits.resultLimit,
              GraphChatScopeAuthorization.allows(
                plan: plan,
                within: intent.scope.chatScope
              ) else {
            throw GraphChatLocalIntentExecutionError
                .invalidScope
        }
        try validate(
            plan: plan,
            contract: action.resultContract,
            intent: intent
        )
        return plan
    }

    func queryAction(
        in action: GraphChatLocalIntentAction
    ) throws -> GraphChatLocalQueryAction {
        switch action {
        case .queryDetailValues(let query):
            return query
        case .searchGraph, .nodeDetails,
            .compareNodes,
            .inspectGraphState:
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
    }

    func validatedComparisonPlan(
        _ comparison: GraphChatComparisonPlan,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext
    ) throws -> ValidatedGraphQueryPlan {
        let featureFields =
            comparison.features.compactMap {
                if case .field(let value) = $0 {
                    return value
                }
                return nil
            }
        guard
            comparison.kind
                == .sameEntityAttributes,
            comparison.binding
                == intent.binding,
            comparison.graphScope
                == intent.scope.graphScope,
            comparison.chatScope
                == intent.scope.chatScope,
            comparison.nodes
                == intent.payload.nodes,
            featureFields
                == intent.payload.fields,
            let source =
                comparison.selectionQuery,
            source.scope
                == intent.scope.queryScope,
            source.limit
                == comparison.nodes.count
        else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        let validator = GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: referenceDate(),
            defaultLimit:
                GraphQueryPlanLimits
                    .defaultResultLimit,
            maximumLimit:
                GraphQueryPlanLimits
                    .maximumResultLimit
        )
        let plan = try validator.validate(
            source,
            against: schemaContext
        )
        let projectedFields =
            plan.projection.compactMap {
                if case .field(let fieldID) = $0 {
                    return fieldID
                }
                return nil
            }
        guard case .selection(
            let expectedSelection
        ) = intent.scope.queryScope.target else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        guard
            plan.graphScope
                == intent.scope.graphScope,
            plan.entityID
                == comparison.nodes[0]
                    .ownerEntityID,
            plan.scope
                == .selection(
                    expectedSelection
                ),
            plan.filters.isEmpty,
            plan.aggregation == nil,
            plan.sorting == [
                GraphValidatedQuerySort(
                    key: .nodeName,
                    direction: .ascending
                ),
            ],
            projectedFields
                == intent.payload.fields
                    .map(\.id),
            plan.limit
                == comparison.nodes.count,
            GraphChatScopeAuthorization.allows(
                plan: plan,
                within:
                    intent.scope.chatScope
            )
        else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        try validate(
            plan: plan,
            contract: .comparison,
            intent: intent
        )
        return plan
    }

    func normalizedResult(
        _ result: GraphChatQueryResult,
        contract: GraphChatLocalQueryResultContract,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext,
        limit: Int
    ) -> GraphChatQueryResult {
        let normalized: GraphChatQueryResult
        if result.state == .noEvidence
            || (
                result.state == .success
                    && result.evidence.isEmpty
            ) {
            normalized = noResults(
                limit: limit,
                integrityConflictedValueKeys:
                    result.integrityConflictedValueKeys
            )
        } else if case .authoritativeSingleField(
            _,
            let field
        ) = contract {
            guard result.state == .success,
                  result.rows.count == 1,
                  let cell = result.rows[0].cells.first(
                    where: { $0.fieldID == field.id }
                  ),
                  cell.value != .missing,
                  result.rows[0].evidenceIDs
                    .contains(cell.evidenceID),
                  result.evidence.contains(
                    where: { $0.id == cell.evidenceID }
                  ) else {
                return noResults(
                    limit: limit,
                    integrityConflictedValueKeys:
                        result.integrityConflictedValueKeys
                )
            }
            normalized = result
        } else {
            normalized = result
        }
        return semanticPresentationResult(
            normalized,
            contract: contract,
            intent: intent,
            schemaContext: schemaContext
        )
    }

    func stageArtifacts(
        for result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        action: GraphChatLocalQueryAction,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage,
        registry: GraphChatAnswerArtifactRegistry,
        evidenceRegistry: GraphChatEvidenceRegistry,
        presentationRegistry:
            GraphChatPresentationRegistry,
        transactionID:
            GraphChatAnswerArtifactTransactionID
    ) async throws -> [GraphChatAnswerArtifactID] {
        guard result.state == .success else {
            return []
        }
        let budget = GraphChatAnswerArtifactFactoryBudget(
            maximumRows:
                GraphQueryPlanLimits.maximumResultLimit,
            maximumColumns:
                GraphChatAnswerArtifactFactoryBudget
                    .default.maximumColumns
        )
        let sourceDraft: GraphChatAnswerArtifactDraft?
        switch action.resultContract {
        case .authoritativeSingleField:
            let summary =
                GraphChatAnswerArtifactFactory.querySummary(
                    plan: plan,
                    schemaContext: schemaContext,
                    language: language
                )
            sourceDraft =
                GraphChatAnswerArtifactFactory.table(
                    result: result,
                    plan: plan,
                    schemaContext: schemaContext,
                    language: language,
                    budget: budget,
                    querySummary: summary
                )
        case .entityCollection, .compiledCollection,
            .count, .groupCount, .refinement,
            .comparison:
            sourceDraft =
                GraphChatAnswerArtifactFactory.queryResult(
                    result,
                    plan: plan,
                    schemaContext: schemaContext,
                    language: language,
                    budget: budget
                )
        }
        guard let sourceDraft else {
            throw GraphChatLocalIntentExecutionError
                .artifactUnavailable
        }
        let draft = compactCollectionArtifact(
            sourceDraft,
            plan: plan
        )
        let artifactID = try await registry.stage(
            draft,
            transactionID: transactionID,
            evidenceRegistry: evidenceRegistry
        )
        await presentationRegistry
            .registerValidatedArtifact(
                id: artifactID,
                title: draft.title
            )
        return [artifactID]
    }

    func toolState(
        for state: GraphChatResultState
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

    private func validate(
        plan: ValidatedGraphQueryPlan,
        contract: GraphChatLocalQueryResultContract,
        intent: GraphChatTypedIntent
    ) throws {
        switch contract {
        case .authoritativeSingleField(
            let node,
            let field
        ):
            guard intent.kind == .nodeDetails,
                  intent.factExpectation
                    == .authoritativeSingleField,
                  plan.entityID
                    == field.ownerEntityID,
                  node.ownerEntityID
                    == field.ownerEntityID,
                  plan.scope == .node(node.node),
                  plan.filters.isEmpty,
                  plan.aggregation == nil,
                  plan.limit == 1,
                  plan.projection == [
                    .nodeIdentity,
                    .field(field.id),
                  ] else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }
        case .entityCollection:
            guard intent.kind == .entityCollection,
                  intent.factExpectation == .none,
                  intent.expectedCardinality
                    == .zeroOrMore,
                  intent.payload.fields.isEmpty,
                  intent.limits.maximumResultLimit
                    == GraphQueryPlanLimits
                        .maximumResultLimit,
                  intent.limits.maximumEvidenceCount
                    == intent.limits.resultLimit,
                  intent.limits.maximumArtifactCount
                    == 1,
                  let entity =
                    intent.payload.entities.first,
                  plan.entityID == entity.id,
                  plan.filters.isEmpty,
                  plan.aggregation == nil,
                  plan.limit
                    == intent.limits.resultLimit,
                  plan.sorting == [
                    GraphValidatedQuerySort(
                        key: .nodeName,
                        direction: .ascending
                    )
                  ],
                  plan.projection == [.nodeIdentity] else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }

        case .compiledCollection:
            guard intent.kind == .entityCollection,
                  intent.factExpectation == .none,
                  intent.expectedCardinality
                    == .zeroOrMore,
                  plan.aggregation == nil,
                  plan.projection.first
                    == .nodeIdentity,
                  let collection =
                    entityCollection(
                        in: intent
                    ),
                  plan.entityID
                    == collection.entity.id,
                  Set(
                    plan.projection.compactMap {
                        if case .field(
                            let fieldID
                        ) = $0 {
                            return fieldID
                        }
                        return nil
                    }
                  ) == Set(
                    collection.projectedFields
                        .map(\.id)
                  ),
                  fieldIDs(in: plan)
                    == Set(
                        collection
                            .referencedFields
                            .map(\.id)
                    ) else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }

        case .count:
            guard intent.kind == .countOrGroup,
                  intent.expectedCardinality
                    == .exactlyOne,
                  intent.factExpectation == .none,
                  plan.sorting.isEmpty,
                  plan.projection == [.nodeIdentity],
                  plan.aggregation == .count,
                  let value = countOrGroup(
                    in: intent
                  ),
                  case .count = value.operation,
                  plan.entityID == value.entity.id,
                  fieldIDs(in: plan)
                    == Set(
                        value.referencedFields
                            .map(\.id)
                    ) else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }

        case .groupCount:
            guard intent.kind == .countOrGroup,
                  intent.expectedCardinality
                    == .zeroOrMore,
                  intent.factExpectation == .none,
                  plan.sorting.isEmpty,
                  plan.projection == [.nodeIdentity],
                  let value = countOrGroup(
                    in: intent
                  ),
                  case .group(let groupField) =
                    value.operation,
                  plan.entityID == value.entity.id,
                  plan.aggregation
                    == .groupCount(groupField.id),
                  fieldIDs(in: plan)
                    == Set(
                        value.referencedFields
                            .map(\.id)
                    ) else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }

        case .refinement:
            guard intent.kind == .narrowResultSet,
                  intent.expectedCardinality
                    == .zeroOrMore,
                  intent.factExpectation == .none,
                  plan.aggregation == nil,
                  plan.projection.first
                    == .nodeIdentity,
                  let value = refinement(
                    in: intent
                  ),
                  plan.entityID == value.entity.id,
                  Set(
                    plan.projection.compactMap {
                        if case .field(
                            let fieldID
                        ) = $0 {
                            return fieldID
                        }
                        return nil
                    }
                  ) == Set(
                    value.projectedFields
                        .map(\.id)
                  ),
                  fieldIDs(in: plan)
                    == Set(value.fields.map(\.id)),
                  planScopeNodes(plan.scope)
                    == Set(
                        value.nodes.map(\.node)
                    ) else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }
        case .comparison:
            guard intent.kind == .compareNodes,
                  intent.expectedCardinality
                    == .twoOrMore,
                  intent.factExpectation == .none,
                  plan.aggregation == nil,
                  plan.filters.isEmpty,
                  plan.projection.first
                    == .nodeIdentity
            else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }
        }
    }

    private func noResults(
        limit: Int,
        integrityConflictedValueKeys:
            Set<DetailValueAuthorityKey> = []
    ) -> GraphChatQueryResult {
        GraphChatQueryResult(
            state: .noResults,
            rows: [],
            aggregation: nil,
            appliedFilters: [],
            evidence: [],
            resultWindow: GraphChatResultWindow(
                totalCount: 0,
                returnedCount: 0,
                limit: limit,
                limitReached: false,
                limitSource: .query
            ),
            integrityConflictedValueKeys:
                integrityConflictedValueKeys
        )
    }

    private func semanticPresentationResult(
        _ result: GraphChatQueryResult,
        contract: GraphChatLocalQueryResultContract,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext
    ) -> GraphChatQueryResult {
        guard isCollectionContract(contract),
              intent.resolution.source
                != .foundationalFastPath,
              let entity =
                intent.payload.entities.first,
              result.rows.isEmpty == false else {
            return result
        }
        let rows = result.rows.map { row in
            let resolution =
                schemaContext.aliases
                    .nodesByKey[row.node]
            let displayName = resolution
                .flatMap { candidate -> String? in
                    guard candidate.ownerEntityID
                            == entity.id else {
                        return nil
                    }
                    let normalized =
                        candidate.displayName
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                    return normalized.isEmpty
                        ? nil
                        : normalized
                }
                ?? row.label
            return GraphChatQueryResultRow(
                node: row.node,
                label: displayName,
                cells: row.cells,
                evidenceIDs: row.evidenceIDs
            )
        }
        return GraphChatQueryResult(
            state: result.state,
            rows: rows,
            aggregation: result.aggregation,
            appliedFilters:
                result.appliedFilters,
            evidence: result.evidence,
            resultWindow:
                result.resultWindow,
            integrityConflictedValueKeys:
                result.integrityConflictedValueKeys
        )
    }

    func revalidateRefinementSource(
        action: GraphChatLocalQueryAction,
        intent: GraphChatTypedIntent,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws {
        guard let source = action.refinementSource else {
            guard action.resultContract
                    != .refinement else {
                throw GraphChatLocalIntentExecutionError
                    .staleResultSet
            }
            return
        }
        guard action.resultContract == .refinement
                || action.resultContract == .count
                || action.resultContract == .groupCount
        else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        guard
            providerPlan.currentResolvedScope
                == source,
            providerPlan.conversationContext
                .currentResolvedScope == source,
            source.graphScope
                == intent.scope.graphScope,
            source.chatScope
                == intent.scope.chatScope,
            source.conversationID
                == intent.binding.conversationID,
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
            let sourcePlan =
                source.revision
                    .validatedQueryPlan,
            sourcePlan.graphScope
                == source.graphScope,
            sourcePlan.entityID
                == source.entityID,
            let result =
                providerPlan.conversationContext
                    .results.first(
                        where: {
                            $0.id == sourceResultID
                                && $0.alias
                                    == sourceAlias
                                && $0
                                    .sourceReferenceCount
                                    == source.revision
                                        .sourceReferenceCount
                        }
                    ),
            providerPlan.conversationContext
                .turns.contains(
                    where: {
                        $0.id == sourceTurnID
                            && $0.completedAt
                                == sourceTurnCompletedAt
                            && $0.resultAliases
                                .contains(result.alias)
                    }
                ),
            providerPlan.conversationContext
                .resultRevalidations
                .contains(
                    where: {
                        $0.resultAlias
                            == result.alias
                            && $0.plan
                                == sourcePlan
                            && $0
                                .sourceReferenceCount
                                == source.revision
                                    .sourceReferenceCount
                    }
                )
        else {
            throw GraphChatLocalIntentExecutionError
                .staleResultSet
        }
        let expectedNodes = Set(source.nodes)
        let compiledNodes = scopeNodes(
            action.plan.scope
        )
        guard expectedNodes == compiledNodes,
              GraphChatScopeAuthorization.allows(
                scope: action.plan.scope
                    ?? intent.scope.queryScope,
                within: source.chatScope,
                aliases: schemaContext.aliases
              ) else {
            throw GraphChatLocalIntentExecutionError
                .scopeExpansionPrevented
        }
        if action.resultContract == .refinement {
            guard
                let value = refinement(in: intent),
                value.sourceResultContextID
                    == sourceResultID,
                Set(value.nodes.map(\.node))
                    == expectedNodes,
                value.entity.id
                    == source.entityID
            else {
                throw GraphChatLocalIntentExecutionError
                    .staleResultSet
            }
        }
    }

    private func entityCollection(
        in intent: GraphChatTypedIntent
    ) -> GraphChatTypedEntityCollectionIntent? {
        guard case .entityCollection(let value) =
            intent.payload else {
            return nil
        }
        return value
    }

    private func countOrGroup(
        in intent: GraphChatTypedIntent
    ) -> GraphChatTypedCountOrGroupIntent? {
        guard case .countOrGroup(let value) =
            intent.payload else {
            return nil
        }
        return value
    }

    private func refinement(
        in intent: GraphChatTypedIntent
    ) -> GraphChatTypedNarrowResultSetIntent? {
        guard case .narrowResultSet(let value) =
            intent.payload else {
            return nil
        }
        return value
    }

    private func fieldIDs(
        in plan: ValidatedGraphQueryPlan
    ) -> Set<UUID> {
        var result = Set(plan.filters.map(\.fieldID))
        for sort in plan.sorting {
            if case .field(let fieldID) = sort.key {
                result.insert(fieldID)
            }
        }
        for projection in plan.projection {
            if case .field(let fieldID) = projection {
                result.insert(fieldID)
            }
        }
        switch plan.aggregation {
        case .groupCount(let fieldID),
            .minimum(let fieldID),
            .maximum(let fieldID):
            result.insert(fieldID)
        case .count, nil:
            break
        }
        return result
    }

    private func planScopeNodes(
        _ scope: GraphResolvedQueryScope
    ) -> Set<NodeRefKey> {
        switch scope {
        case .node(let node):
            return [node]
        case .selection(let nodes):
            return Set(nodes)
        case .graph, .entity:
            return []
        }
    }

    private func scopeNodes(
        _ scope: GraphChatScope?
    ) -> Set<NodeRefKey> {
        guard let scope else {
            return []
        }
        switch scope.target {
        case .node(let node):
            return [node]
        case .selection(let nodes):
            return Set(nodes)
        case .graph, .entity:
            return []
        }
    }

    private func isCollectionContract(
        _ contract: GraphChatLocalQueryResultContract
    ) -> Bool {
        switch contract {
        case .entityCollection, .compiledCollection,
            .refinement:
            return true
        case .authoritativeSingleField, .count,
            .groupCount, .comparison:
            return false
        }
    }

    private func compactCollectionArtifact(
        _ draft: GraphChatAnswerArtifactDraft,
        plan: ValidatedGraphQueryPlan
    ) -> GraphChatAnswerArtifactDraft {
        guard plan.projection == [.nodeIdentity],
              case .resultList(let payload) =
                draft.payload else {
            return draft
        }
        let requiresDeepCompaction =
            payload.rows.count >
                GraphChatAnswerArtifactFactoryBudget
                .default.maximumRows
        let rows = payload.rows.map { row in
            GraphChatAnswerArtifactListRow(
                id: row.id,
                primaryText: row.primaryText,
                secondaryText: row.secondaryText,
                navigationTargets:
                    requiresDeepCompaction
                    ? []
                    : Array(
                        row.navigationTargets.prefix(1)
                    ),
                evidence:
                    requiresDeepCompaction
                    ? .empty
                    : row.evidence
            )
        }
        return GraphChatAnswerArtifactDraft(
            graphScope: draft.graphScope,
            title: draft.title,
            payload: .resultList(
                GraphChatAnswerArtifactResultListPayload(
                    title: payload.title,
                    rows: rows,
                    resultMetadata:
                        payload.resultMetadata,
                    evidence: .empty
                )
            ),
            evidence:
                requiresDeepCompaction
                ? draft.evidence
                : .empty,
            navigationTargets:
                requiresDeepCompaction
                ? [
                    .openEntityList(
                        graphScope: draft.graphScope,
                        entityID: plan.entityID,
                        filters: []
                    )
                ]
                : draft.navigationTargets,
            querySummary: draft.querySummary
        )
    }
}
