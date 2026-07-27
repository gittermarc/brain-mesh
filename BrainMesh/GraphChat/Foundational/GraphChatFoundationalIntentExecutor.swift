//
//  GraphChatFoundationalIntentExecutor.swift
//  BrainMesh
//
//  Provider-free execution through the existing query, evidence, artifact,
//  ledger, conversation, and finalization boundaries.
//

import Foundation

nonisolated protocol GraphChatFoundationalQueryExecuting: Sendable {
    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult
}

extension GraphChatQueryEngine: GraphChatFoundationalQueryExecuting {}

nonisolated enum GraphChatFoundationalIntentExecutionError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case invalidBinding
    case invalidCompiledPlan
    case missingRequiredField
    case artifactUnavailable
    case primaryResultUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidBinding:
            return "Der kompilierte Intent gehört nicht zum aktuellen Turn."
        case .invalidCompiledPlan:
            return "Der kompilierte Query-Plan hat die erneute Validierung nicht bestanden."
        case .missingRequiredField:
            return "Das angeforderte Detailfeld ist nicht mehr verfügbar."
        case .artifactUnavailable:
            return "Für das validierte Ergebnis konnte kein Result-Artefakt erzeugt werden."
        case .primaryResultUnavailable:
            return "Das validierte lokale Ergebnis konnte nicht im Result-Ledger gebunden werden."
        }
    }
}

nonisolated struct GraphChatFoundationalIntentExecution: Sendable {
    let intent: GraphChatFoundationalIntent
    let schemaContext: GraphSchemaContext
    let conversationContext: GraphChatConversationContextSnapshot
    let conversationTransaction: GraphChatConversationStateTransaction
    let evidenceRegistry: GraphChatEvidenceRegistry
    let presentationRegistry: GraphChatPresentationRegistry
    let artifactRegistry: GraphChatAnswerArtifactRegistry
    let artifactContext: GraphChatArtifactCommitContext
    let primaryResultLedger: GraphChatPrimaryResultLedger
    let primaryResult: GraphChatToolExecutionLedgerEntry
    let authoritativeFactExpectation:
        GraphChatAuthoritativeFactExpectation?
}

nonisolated struct GraphChatFoundationalIntentExecutor: Sendable {
    typealias ActivityHandler = @Sendable (GraphChatToolActivity) -> Void

    private let queryExecutor: any GraphChatFoundationalQueryExecuting
    private let conversationStateReducer: GraphChatConversationStateReducer
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let referenceDate: @Sendable () -> Date

    init(
        queryExecutor: any GraphChatFoundationalQueryExecuting,
        conversationStateReducer: GraphChatConversationStateReducer,
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate: @escaping @Sendable () -> Date
    ) {
        self.queryExecutor = queryExecutor
        self.conversationStateReducer = conversationStateReducer
        self.calendar = calendar
        self.timeZone = timeZone
        self.referenceDate = referenceDate
    }

    func execute(
        intent: GraphChatFoundationalIntent,
        schemaContext: GraphSchemaContext,
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        artifactSession: GraphChatArtifactSessionResources,
        onActivity: ActivityHandler
    ) async throws -> GraphChatFoundationalIntentExecution {
        guard intent.binding.requestID == requestID,
              intent.binding.conversationID
                == providerPlan.requestBaseState.conversationID,
              intent.graphScope == providerPlan.scopeKey.graphScope,
              intent.chatScope == providerPlan.scopeKey.chatScope,
              schemaContext.graphScope == intent.graphScope,
              artifactSession.key == providerPlan.scopeKey else {
            throw GraphChatFoundationalIntentExecutionError.invalidBinding
        }

        let plan = try validatedPlan(
            for: intent,
            schemaContext: schemaContext
        )
        guard GraphChatScopeAuthorization.allows(
            plan: plan,
            within: intent.chatScope
        ) else {
            throw GraphChatFoundationalIntentExecutionError
                .invalidCompiledPlan
        }

        let evidenceRegistry = GraphChatEvidenceRegistry(
            scope: intent.chatScope
        )
        let presentationRegistry = GraphChatPresentationRegistry(
            schemaContext: schemaContext,
            conversationContext: providerPlan.conversationContext,
            language: intent.responseLanguage
        )
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let artifactContext = GraphChatArtifactCommitContext(
            graphScope: intent.graphScope,
            chatScope: intent.chatScope,
            sessionID: artifactSession.sessionID,
            transactionID: transactionID
        )
        let conversationTransaction = GraphChatConversationStateTransaction(
            baseState: providerPlan.requestBaseState,
            reducer: conversationStateReducer
        )
        let ledger = GraphChatPrimaryResultLedger(
            graphScope: intent.graphScope,
            chatScope: intent.chatScope,
            artifactSessionID: artifactSession.sessionID
        )

        do {
            try await ledger.bind(requestID: requestID)
            let activityID = UUID()
            onActivity(
                GraphChatToolActivity(
                    id: activityID,
                    tool: .queryDetailValues,
                    state: .started
                )
            )
            let rawResult = try await queryExecutor.execute(plan)
            try Task.checkCancellation()
            let authoritativeFactExpectation =
                GraphChatAuthoritativeFactExpectation(
                    intent: intent,
                    result: rawResult,
                    timeZone: timeZone
                )
            let result = normalizedResult(
                rawResult,
                for: intent
            )
            try await evidenceRegistry.register(result.evidence)
            await presentationRegistry.registerValidatedEvidence(
                result.evidence
            )
            try await conversationTransaction.apply(
                GraphChatConversationTrustedEvent(
                    graphScope: intent.graphScope,
                    chatScope: intent.chatScope,
                    payload: .queryResolved(
                        plan: plan,
                        result: result,
                        schemaContext: schemaContext
                    )
                )
            )

            let artifactIDs = try await stageArtifacts(
                for: result,
                plan: plan,
                schemaContext: schemaContext,
                language: intent.responseLanguage,
                registry: artifactSession.registry,
                evidenceRegistry: evidenceRegistry,
                presentationRegistry: presentationRegistry,
                transactionID: transactionID
            )
            let response = GraphChatModelToolResponse(
                tool: .queryDetailValues,
                state: toolState(for: result.state),
                content: "local-foundational-result",
                evidenceIDs: result.evidence.map(\.id),
                artifactIDs: artifactIDs
            )
            let artifacts = try await artifactSession.registry
                .validatedArtifacts(
                    for: artifactIDs.map {
                        $0.rawValue.uuidString
                    },
                    graphScope: intent.graphScope,
                    sessionID: artifactSession.sessionID,
                    transactionID: transactionID
                )
            try await ledger.record(
                response: response,
                evidence: result.evidence,
                artifacts: artifacts,
                transactionID: transactionID
            )
            guard let primaryResult = await ledger.primaryResult(
                requestID: requestID,
                graphScope: intent.graphScope,
                chatScope: intent.chatScope,
                artifactSessionID: artifactSession.sessionID,
                transactionID: transactionID
            ) else {
                throw GraphChatFoundationalIntentExecutionError
                    .primaryResultUnavailable
            }
            onActivity(
                GraphChatToolActivity(
                    id: activityID,
                    tool: .queryDetailValues,
                    state: .finished
                )
            )
            return GraphChatFoundationalIntentExecution(
                intent: intent,
                schemaContext: schemaContext,
                conversationContext: providerPlan.conversationContext,
                conversationTransaction: conversationTransaction,
                evidenceRegistry: evidenceRegistry,
                presentationRegistry: presentationRegistry,
                artifactRegistry: artifactSession.registry,
                artifactContext: artifactContext,
                primaryResultLedger: ledger,
                primaryResult: primaryResult,
                authoritativeFactExpectation:
                    authoritativeFactExpectation
            )
        } catch {
            await evidenceRegistry.removeAll()
            await artifactSession.registry.rollback(
                transactionID: transactionID
            )
            await ledger.discard(transactionID: transactionID)
            await ledger.finish(requestID: requestID)
            throw error
        }
    }

    func cleanupFailedExecution(
        _ execution: GraphChatFoundationalIntentExecution,
        requestID: UUID
    ) async {
        await execution.evidenceRegistry.removeAll()
        await execution.artifactRegistry.rollback(
            transactionID: execution.artifactContext.transactionID
        )
        await execution.primaryResultLedger.discard(
            transactionID: execution.artifactContext.transactionID
        )
        await execution.primaryResultLedger.finish(requestID: requestID)
    }

    func finishCommittedExecution(
        _ execution: GraphChatFoundationalIntentExecution,
        requestID: UUID
    ) async {
        await execution.evidenceRegistry.removeAll()
        await execution.primaryResultLedger.finish(requestID: requestID)
    }

    private func validatedPlan(
        for intent: GraphChatFoundationalIntent,
        schemaContext: GraphSchemaContext
    ) throws -> ValidatedGraphQueryPlan {
        let projection: [GraphQueryProjection]
        switch intent.kind {
        case .singleNodeFieldValue:
            guard let field = intent.field, intent.node != nil else {
                throw GraphChatFoundationalIntentExecutionError
                    .missingRequiredField
            }
            projection = [
                .nodeIdentity,
                .field(field.alias),
            ]
        case .entityAttributeCollection:
            projection = [.nodeIdentity]
        }

        let validator = GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: referenceDate(),
            defaultLimit: GraphQueryPlanLimits.defaultResultLimit,
            maximumLimit: GraphQueryPlanLimits.maximumResultLimit
        )
        let plan = try validator.validate(
            GraphQueryPlan(
                entityAlias: intent.entity.alias,
                scope: intent.queryScope,
                filters: [],
                sorting: [
                    GraphQuerySort(
                        key: .nodeName,
                        direction: .ascending
                    )
                ],
                projection: projection,
                aggregation: nil,
                limit: intent.resultLimit
            ),
            against: schemaContext
        )
        guard plan.entityID == intent.entity.id,
              plan.limit == intent.resultLimit,
              plan.filters.isEmpty,
              plan.aggregation == nil,
              plan.projection.first == .nodeIdentity else {
            throw GraphChatFoundationalIntentExecutionError
                .invalidCompiledPlan
        }
        switch intent.kind {
        case .singleNodeFieldValue:
            guard let field = intent.field,
                  plan.limit == 1,
                  plan.projection == [
                    .nodeIdentity,
                    .field(field.id),
                  ] else {
                throw GraphChatFoundationalIntentExecutionError
                    .invalidCompiledPlan
            }
        case .entityAttributeCollection:
            guard plan.limit
                    == GraphQueryPlanLimits.maximumResultLimit,
                  plan.projection == [.nodeIdentity] else {
                throw GraphChatFoundationalIntentExecutionError
                    .invalidCompiledPlan
            }
        }
        return plan
    }

    private func normalizedResult(
        _ result: GraphChatQueryResult,
        for intent: GraphChatFoundationalIntent
    ) -> GraphChatQueryResult {
        if result.state == .noEvidence
            || (
                result.state == .success
                    && result.evidence.isEmpty
            ) {
            return noResults(
                limit: intent.resultLimit,
                integrityConflictedValueKeys:
                    result.integrityConflictedValueKeys
            )
        }
        guard intent.kind == .singleNodeFieldValue,
              let fieldID = intent.field?.id else {
            return result
        }
        guard result.state == .success,
              result.rows.count == 1,
              let cell = result.rows[0].cells.first(
                where: { $0.fieldID == fieldID }
              ),
              cell.value != .missing,
              result.rows[0].evidenceIDs.contains(cell.evidenceID),
              result.evidence.contains(
                where: { $0.id == cell.evidenceID }
              ) else {
            return noResults(
                limit: 1,
                integrityConflictedValueKeys:
                    result.integrityConflictedValueKeys
            )
        }
        return result
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

    private func stageArtifacts(
        for result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage,
        registry: GraphChatAnswerArtifactRegistry,
        evidenceRegistry: GraphChatEvidenceRegistry,
        presentationRegistry: GraphChatPresentationRegistry,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async throws -> [GraphChatAnswerArtifactID] {
        guard result.state == .success else {
            return []
        }
        let budget = GraphChatAnswerArtifactFactoryBudget(
            maximumRows: GraphQueryPlanLimits.maximumResultLimit,
            maximumColumns:
                GraphChatAnswerArtifactFactoryBudget.default
                    .maximumColumns
        )
        let sourceDraft: GraphChatAnswerArtifactDraft?
        if plan.limit == 1,
           plan.projection.count == 2,
           plan.projection.first == .nodeIdentity {
            let summary = GraphChatAnswerArtifactFactory.querySummary(
                plan: plan,
                schemaContext: schemaContext,
                language: language
            )
            sourceDraft = GraphChatAnswerArtifactFactory.table(
                result: result,
                plan: plan,
                schemaContext: schemaContext,
                language: language,
                budget: budget,
                querySummary: summary
            )
        } else {
            sourceDraft = GraphChatAnswerArtifactFactory.queryResult(
                result,
                plan: plan,
                schemaContext: schemaContext,
                language: language,
                budget: budget
            )
        }
        guard let sourceDraft else {
            throw GraphChatFoundationalIntentExecutionError
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
        await presentationRegistry.registerValidatedArtifact(
            id: artifactID,
            title: draft.title
        )
        return [artifactID]
    }

    private func compactCollectionArtifact(
        _ draft: GraphChatAnswerArtifactDraft,
        plan: ValidatedGraphQueryPlan
    ) -> GraphChatAnswerArtifactDraft {
        guard plan.projection == [.nodeIdentity],
              case .resultList(let payload) = draft.payload else {
            return draft
        }
        let requiresDeepCompaction =
            payload.rows.count > GraphChatAnswerArtifactFactoryBudget.default.maximumRows
        let rows = payload.rows.map { row in
            GraphChatAnswerArtifactListRow(
                id: row.id,
                primaryText: row.primaryText,
                secondaryText: row.secondaryText,
                navigationTargets: requiresDeepCompaction
                    ? []
                    : Array(row.navigationTargets.prefix(1)),
                evidence: requiresDeepCompaction ? .empty : row.evidence
            )
        }
        return GraphChatAnswerArtifactDraft(
            graphScope: draft.graphScope,
            title: draft.title,
            payload: .resultList(
                GraphChatAnswerArtifactResultListPayload(
                    title: payload.title,
                    rows: rows,
                    resultMetadata: payload.resultMetadata,
                    evidence: .empty
                )
            ),
            evidence: requiresDeepCompaction ? draft.evidence : .empty,
            navigationTargets: requiresDeepCompaction
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

    private func toolState(
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
}
