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
            referenceDate: referenceDate(),
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
        case .searchGraph:
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
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
        case .entityCollection:
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
        guard case .entityCollection = contract,
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
