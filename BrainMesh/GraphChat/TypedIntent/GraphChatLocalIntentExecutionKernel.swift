//
//  GraphChatLocalIntentExecutionKernel.swift
//  BrainMesh
//
//  Provider-free execution and lifecycle boundary for app-compiled read plans.
//

import Foundation

nonisolated enum GraphChatLocalIntentExecutionError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case invalidBinding
    case invalidScope
    case staleSchemaIdentity
    case invalidCompiledAction
    case safetyLimitExceeded
    case artifactUnavailable
    case primaryResultUnavailable
    case scopeExpansionPrevented
    case staleResultSet

    var errorDescription: String? {
        switch self {
        case .invalidBinding:
            return "Der lokale Intent gehört nicht zum aktuellen Turn."
        case .invalidScope:
            return "Der lokale Intent gehört nicht zum aktuellen Graph-Chat-Scope."
        case .staleSchemaIdentity:
            return "Eine validierte Identität des lokalen Intent ist nicht mehr aktuell."
        case .invalidCompiledAction:
            return "Die kompilierte lokale Action hat die erneute Validierung nicht bestanden."
        case .safetyLimitExceeded:
            return "Das lokale Ergebnis überschreitet ein appseitiges Sicherheitslimit."
        case .artifactUnavailable:
            return "Für das validierte lokale Ergebnis konnte kein Result-Artefakt erzeugt werden."
        case .primaryResultUnavailable:
            return "Das validierte lokale Ergebnis konnte nicht im Result-Ledger gebunden werden."
        case .scopeExpansionPrevented:
            return "Die lokale Query würde den revalidierten Ergebnisscope erweitern."
        case .staleResultSet:
            return "Die referenzierte Ergebnismenge ist nicht mehr frisch revalidierbar."
        }
    }
}

nonisolated struct GraphChatLocalIntentPreparedExecution: Sendable {
    let adaptation: GraphChatTypedIntentAdaptation
    let intent: GraphChatTypedIntent
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

nonisolated enum GraphChatLocalIntentCleanupOutcome:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case committed
    case rolledBack
}

nonisolated struct GraphChatLocalIntentCleanupReport:
    Hashable,
    Sendable
{
    let outcome: GraphChatLocalIntentCleanupOutcome
    let evidenceCount: Int
    let presentationEntryCount: Int
    let stagedArtifactCount: Int
    let ledgerEntryCount: Int
    let ledgerIsBound: Bool
    let conversationRestoredToBase: Bool
}

nonisolated struct GraphChatLocalIntentExecutionKernelObserver:
    Sendable
{
    private let handler: @Sendable (
        GraphChatLocalIntentCleanupReport
    ) async -> Void

    static let disabled =
        GraphChatLocalIntentExecutionKernelObserver { _ in }

    init(
        handler: @escaping @Sendable (
            GraphChatLocalIntentCleanupReport
        ) async -> Void
    ) {
        self.handler = handler
    }

    func record(
        _ report: GraphChatLocalIntentCleanupReport
    ) async {
        await handler(report)
    }
}

nonisolated struct GraphChatLocalIntentExecutionKernel: Sendable {
    typealias ActivityHandler =
        @Sendable (GraphChatToolActivity) -> Void
    typealias CurrentRequestValidator =
        @Sendable () async throws -> Void
    typealias FinalizationHandler = @Sendable (
        GraphChatLocalIntentPreparedExecution
    ) async throws -> GraphChatFinalizedTurn
    typealias CommitHandler =
        @Sendable (GraphChatFinalizedTurn) async throws -> Void

    private let queryExecutor:
        any GraphChatLocalIntentQueryExecuting
    private let searchExecutor:
        any GraphChatLocalIntentSearchExecuting
    private let nodeExecutor:
        any GraphChatLocalIntentNodeExecuting
    private let statsExecutor:
        any GraphChatLocalIntentStatsExecuting
    private let relationshipExecutor:
        any GraphChatLocalIntentRelationshipExecuting
    private let conversationStateReducer:
        GraphChatConversationStateReducer
    private let timeZone: TimeZone
    private let querySupport:
        GraphChatLocalIntentQueryExecutionSupport
    private let readPlanValidator:
        GraphChatComposableReadPlanValidator
    private let searchSupport:
        GraphChatLocalIntentSearchExecutionSupport
    private let observability:
        any GraphChatObservabilityRecording
    private let observer:
        GraphChatLocalIntentExecutionKernelObserver

    init(
        queryExecutor:
            any GraphChatLocalIntentQueryExecuting,
        searchExecutor:
            any GraphChatLocalIntentSearchExecuting =
                SearchGraphTool(),
        nodeExecutor:
            any GraphChatLocalIntentNodeExecuting =
                GetNodeTool(),
        statsExecutor:
            any GraphChatLocalIntentStatsExecuting =
                UnavailableGraphChatLocalStatsExecutor(),
        relationshipExecutor:
            any GraphChatLocalIntentRelationshipExecuting =
                GraphChatRelationshipExecutor(),
        conversationStateReducer:
            GraphChatConversationStateReducer,
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate: @escaping @Sendable () -> Date,
        observability:
            any GraphChatObservabilityRecording =
                NoOpGraphChatObservabilityRecorder(),
        observer:
            GraphChatLocalIntentExecutionKernelObserver =
                .disabled
    ) {
        self.queryExecutor = queryExecutor
        self.searchExecutor = searchExecutor
        self.nodeExecutor = nodeExecutor
        self.statsExecutor = statsExecutor
        self.relationshipExecutor =
            relationshipExecutor
        self.conversationStateReducer =
            conversationStateReducer
        self.timeZone = timeZone
        self.querySupport =
            GraphChatLocalIntentQueryExecutionSupport(
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: referenceDate
            )
        self.readPlanValidator =
            GraphChatComposableReadPlanValidator(
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: referenceDate
            )
        self.searchSupport =
            GraphChatLocalIntentSearchExecutionSupport()
        self.observability = observability
        self.observer = observer
    }

    func execute(
        adaptation: GraphChatTypedIntentAdaptation,
        schemaContext: GraphSchemaContext,
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        artifactSession: GraphChatArtifactSessionResources,
        onActivity: ActivityHandler,
        validateCurrentRequest:
            @escaping CurrentRequestValidator,
        finalize: @escaping FinalizationHandler,
        commit: @escaping CommitHandler
    ) async throws -> GraphChatFinalizedTurn {
        let intent = adaptation.intent
        await record(
            .executionStarted,
            kind: intent.kind
        )
        do {
            try validateBinding(
                intent: intent,
                providerPlan: providerPlan,
                requestID: requestID,
                artifactSession: artifactSession
            )
        } catch {
            await recordRevalidationRejection(
                error,
                kind: intent.kind
            )
            throw error
        }

        let validatedAction: ValidatedAction
        do {
            let validatedReadPlan:
                ValidatedGraphChatComposableReadPlan
            do {
                validatedReadPlan =
                    try readPlanValidator.validate(
                        adaptation.readPlan,
                        for: intent,
                        schemaContext:
                            schemaContext,
                        providerPlan:
                            providerPlan
                    )
            } catch let error
                as GraphChatComposableReadPlanValidationError {
                throw localExecutionError(
                    for: error
                )
            }
            let localAction =
                validatedReadPlan.action
            try querySupport.revalidateIdentities(
                intent: intent,
                schemaContext: schemaContext
            )
            switch localAction {
            case .queryDetailValues:
                let action = try querySupport
                    .queryAction(
                        in: localAction
                    )
                try querySupport
                    .revalidateRefinementSource(
                        action: action,
                        intent: intent,
                        providerPlan:
                            providerPlan,
                        schemaContext:
                            schemaContext
                    )
                guard let plan =
                        validatedReadPlan
                            .validatedQueryPlan
                else {
                    throw GraphChatLocalIntentExecutionError
                        .invalidCompiledAction
                }
                let compatibilityPlan =
                    try querySupport
                        .validatedPlan(
                            adaptation:
                                adaptation,
                            schemaContext:
                                schemaContext
                        )
                guard compatibilityPlan == plan else {
                    throw GraphChatLocalIntentExecutionError
                        .invalidCompiledAction
                }
                validatedAction = .query(
                    plan: plan,
                    action: action
                )
            case .searchGraph(let action):
                try searchSupport.validate(
                    intent: intent,
                    action: action,
                    schemaContext:
                        schemaContext
                )
                validatedAction = .search(
                    action
                )
            case .nodeDetails(let action):
                try validateNodeAction(
                    action,
                    intent: intent,
                    schemaContext:
                        schemaContext
                )
                validatedAction = .node(action)
            case .compareNodes(let plan):
                try validateComparisonAction(
                    plan,
                    intent: intent,
                    schemaContext:
                        schemaContext
                )
                if plan.kind
                    == .sameEntityAttributes
                {
                    guard let queryPlan =
                            validatedReadPlan
                                .validatedQueryPlan
                    else {
                        throw GraphChatLocalIntentExecutionError
                            .invalidCompiledAction
                    }
                    let compatibilityPlan =
                        try querySupport
                            .validatedComparisonPlan(
                                plan,
                                intent: intent,
                                schemaContext:
                                    schemaContext
                            )
                    guard compatibilityPlan
                            == queryPlan
                    else {
                        throw GraphChatLocalIntentExecutionError
                            .invalidCompiledAction
                    }
                    validatedAction =
                        .sameEntityComparison(
                            plan: plan,
                            queryPlan: queryPlan
                        )
                } else {
                    validatedAction =
                        .structuralComparison(
                            plan
                        )
                }
            case .inspectGraphState(let action):
                try validateGraphStateAction(
                    action,
                    intent: intent
                )
                validatedAction =
                    .graphState(action)
            case .relationships(let plan):
                try validateRelationshipAction(
                    plan,
                    intent: intent,
                    schemaContext:
                        schemaContext,
                    providerPlan:
                        providerPlan
                )
                validatedAction =
                    .relationship(plan)
            }
        } catch {
            await recordRevalidationRejection(
                error,
                kind: intent.kind
            )
            throw error
        }

        let evidenceRegistry = GraphChatEvidenceRegistry(
            scope: intent.scope.chatScope
        )
        let presentationRegistry = GraphChatPresentationRegistry(
            schemaContext: schemaContext,
            conversationContext: providerPlan.conversationContext,
            language: intent.responseLanguage
        )
        let transactionID =
            GraphChatAnswerArtifactTransactionID()
        let artifactContext = GraphChatArtifactCommitContext(
            graphScope: intent.scope.graphScope,
            chatScope: intent.scope.chatScope,
            sessionID: artifactSession.sessionID,
            transactionID: transactionID,
            readPlanVersion:
                adaptation.readPlan.version
        )
        let conversationTransaction =
            GraphChatConversationStateTransaction(
                baseState: providerPlan.requestBaseState,
                reducer: conversationStateReducer
            )
        let ledger = GraphChatPrimaryResultLedger(
            graphScope: intent.scope.graphScope,
            chatScope: intent.scope.chatScope,
            artifactSessionID: artifactSession.sessionID
        )

        var finalizedTurn: GraphChatFinalizedTurn?
        var didCommit = false
        do {
            try Task.checkCancellation()
            try await ledger.bind(requestID: requestID)
            let activityID = UUID()
            onActivity(
                GraphChatToolActivity(
                    id: activityID,
                    tool:
                        validatedAction
                            .toolKind,
                    state: .started
                )
            )
            let actionExecution:
                ActionExecution
            do {
                actionExecution =
                    try await executeAction(
                        validatedAction,
                        intent: intent,
                        schemaContext:
                            schemaContext,
                        evidenceRegistry:
                            evidenceRegistry,
                        presentationRegistry:
                            presentationRegistry,
                        artifactRegistry:
                            artifactSession
                                .registry,
                        conversationTransaction:
                            conversationTransaction,
                        transactionID:
                            transactionID
                    )
            } catch {
                onActivity(
                    GraphChatToolActivity(
                        id: activityID,
                        tool:
                            validatedAction
                                .toolKind,
                        state: .finished
                    )
                )
                throw error
            }
            guard actionExecution.artifactIDs.count
                    <= intent.limits.maximumArtifactCount else {
                throw GraphChatLocalIntentExecutionError
                    .safetyLimitExceeded
            }
            let artifacts = try await artifactSession.registry
                .validatedArtifacts(
                    for: actionExecution
                        .artifactIDs.map {
                        $0.rawValue.uuidString
                    },
                    graphScope: intent.scope.graphScope,
                    sessionID: artifactSession.sessionID,
                    transactionID: transactionID
                )
            try await ledger.record(
                response:
                    actionExecution.response,
                evidence:
                    actionExecution.evidence,
                artifacts: artifacts,
                transactionID: transactionID
            )
            guard let primaryResult =
                await ledger.primaryResult(
                    requestID: requestID,
                    graphScope:
                        intent.scope.graphScope,
                    chatScope: intent.scope.chatScope,
                    artifactSessionID:
                        artifactSession.sessionID,
                    transactionID: transactionID
                ) else {
                throw GraphChatLocalIntentExecutionError
                    .primaryResultUnavailable
            }
            onActivity(
                GraphChatToolActivity(
                    id: activityID,
                    tool:
                        validatedAction
                            .toolKind,
                    state: .finished
                )
            )

            let execution =
                GraphChatLocalIntentPreparedExecution(
                    adaptation: adaptation,
                    intent: intent,
                    schemaContext: schemaContext,
                    conversationContext:
                        providerPlan.conversationContext,
                    conversationTransaction:
                        conversationTransaction,
                    evidenceRegistry: evidenceRegistry,
                    presentationRegistry:
                        presentationRegistry,
                    artifactRegistry:
                        artifactSession.registry,
                    artifactContext: artifactContext,
                    primaryResultLedger: ledger,
                    primaryResult: primaryResult,
                    authoritativeFactExpectation:
                        actionExecution
                            .authoritativeFactExpectation
                )
            try await validateCurrentRequest()
            try Task.checkCancellation()
            let candidateTurn = try await finalize(execution)
            finalizedTurn = candidateTurn
            try validateFinalizedAdvancedTurn(
                candidateTurn,
                action: validatedAction,
                requestedArtifactIDs:
                    actionExecution
                        .artifactIDs
            )
            try validateDeferredArtifactCommit(
                candidateTurn,
                expectedContext: artifactContext
            )
            try await validateCurrentRequest()
            try Task.checkCancellation()
            try await commit(candidateTurn)
            if let deferredCommit =
                    candidateTurn
                        .deferredArtifactCommit
            {
                _ = await artifactSession.registry
                    .finalizeDeferredCommit(
                        transactionID:
                            deferredCommit
                                .context
                                .transactionID
                    )
            }
            didCommit = true

            let cleanupReport = await cleanup(
                evidenceRegistry: evidenceRegistry,
                presentationRegistry:
                    presentationRegistry,
                artifactRegistry:
                    artifactSession.registry,
                transactionID: transactionID,
                ledger: ledger,
                conversationTransaction:
                    conversationTransaction,
                requestID: requestID,
                discardLedgerTransaction: false,
                outcome: .committed
            )
            await observer.record(cleanupReport)
            await record(
                .executionCommitted,
                kind: intent.kind
            )
            return candidateTurn
        } catch {
            if let executionError =
                    error
                        as? GraphChatLocalIntentExecutionError,
               executionError == .staleSchemaIdentity,
               (
                   intent.kind == .nodeDetails
                       || intent.kind == .compareNodes
                       || intent.kind == .relationships
               )
            {
                await record(
                    .staleNodeDiscarded,
                    kind: intent.kind,
                    rejection:
                        .schemaIdentity
                )
            }
            if let finalizedTurn {
                if let deferredCommit =
                        finalizedTurn
                            .deferredArtifactCommit,
                   deferredCommit.context
                    == artifactContext
                {
                    await artifactSession.registry
                        .rollbackDeferredCommit(
                            transactionID:
                                artifactContext
                                    .transactionID
                        )
                } else if finalizedTurn
                    .deferredArtifactCommit == nil
                {
                    await artifactSession.registry
                        .removeCommittedArtifacts(
                            finalizedTurn
                                .committedArtifactIDs,
                            sessionID:
                                artifactSession.sessionID
                        )
                }
            }
            let cleanupReport = await cleanup(
                evidenceRegistry: evidenceRegistry,
                presentationRegistry:
                    presentationRegistry,
                artifactRegistry:
                    artifactSession.registry,
                transactionID: transactionID,
                ledger: ledger,
                conversationTransaction:
                    conversationTransaction,
                requestID: requestID,
                discardLedgerTransaction: true,
                outcome: .rolledBack
            )
            await observer.record(cleanupReport)
            if isCancellation(error), didCommit == false {
                await record(
                    .cancelledBeforeCommit,
                    kind: intent.kind
                )
            }
            await record(
                .executionRolledBack,
                kind: intent.kind
            )
            throw error
        }
    }

    private func validateFinalizedAdvancedTurn(
        _ turn: GraphChatFinalizedTurn,
        action: ValidatedAction,
        requestedArtifactIDs:
            [GraphChatAnswerArtifactID]
    ) throws {
        switch action {
        case .node, .sameEntityComparison,
            .structuralComparison, .graphState,
            .relationship:
            guard
                requestedArtifactIDs.isEmpty
                    == false,
                Set(
                    turn.committedArtifactIDs
                ) == Set(
                    requestedArtifactIDs
                )
            else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
        case .query, .search:
            break
        }
    }

    private func validateDeferredArtifactCommit(
        _ turn: GraphChatFinalizedTurn,
        expectedContext:
            GraphChatArtifactCommitContext
    ) throws {
        guard let deferredCommit =
                turn.deferredArtifactCommit else {
            return
        }
        guard deferredCommit.context
                == expectedContext,
              deferredCommit.artifactIDs
                == turn.committedArtifactIDs
        else {
            throw GraphChatLocalIntentExecutionError
                .invalidBinding
        }
    }

    private enum ValidatedAction {
        case query(
            plan: ValidatedGraphQueryPlan,
            action: GraphChatLocalQueryAction
        )
        case search(GraphChatLocalSearchAction)
        case node(GraphChatLocalNodeDetailsAction)
        case sameEntityComparison(
            plan: GraphChatComparisonPlan,
            queryPlan: ValidatedGraphQueryPlan
        )
        case structuralComparison(
            GraphChatComparisonPlan
        )
        case graphState(
            GraphChatLocalGraphStateAction
        )
        case relationship(
            GraphChatRelationshipPlan
        )

        var toolKind: GraphChatToolKind {
            switch self {
            case .query:
                return .queryDetailValues
            case .search:
                return .searchGraph
            case .node,
                .structuralComparison:
                return .getNode
            case .sameEntityComparison:
                return .queryDetailValues
            case .graphState:
                return .graphStats
            case .relationship:
                return .getNeighbors
            }
        }
    }

    private struct ActionExecution {
        let response: GraphChatModelToolResponse
        let evidence: [GraphEvidence]
        let artifactIDs:
            [GraphChatAnswerArtifactID]
        let authoritativeFactExpectation:
            GraphChatAuthoritativeFactExpectation?
    }

    private func executeAction(
        _ action: ValidatedAction,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext,
        evidenceRegistry:
            GraphChatEvidenceRegistry,
        presentationRegistry:
            GraphChatPresentationRegistry,
        artifactRegistry:
            GraphChatAnswerArtifactRegistry,
        conversationTransaction:
            GraphChatConversationStateTransaction,
        transactionID:
            GraphChatAnswerArtifactTransactionID
    ) async throws -> ActionExecution {
        switch action {
        case .query(let plan, let queryAction):
            let rawResult =
                try await queryExecutor
                    .execute(plan)
            try Task.checkCancellation()
            guard
                rawResult.rows.count
                    <= intent.limits
                        .resultLimit,
                rawResult.evidence.count
                    <= intent.limits
                        .maximumEvidenceCount
            else {
                throw GraphChatLocalIntentExecutionError
                    .safetyLimitExceeded
            }
            let expectation =
                GraphChatAuthoritativeFactExpectation(
                    intent: intent,
                    result: rawResult,
                    timeZone: timeZone
                )
            let result = querySupport
                .normalizedResult(
                    rawResult,
                    contract:
                        queryAction
                            .resultContract,
                    intent: intent,
                    schemaContext:
                        schemaContext,
                    limit:
                        intent.limits
                            .resultLimit
                )
            try await evidenceRegistry.register(
                result.evidence
            )
            await presentationRegistry
                .registerValidatedEvidence(
                    result.evidence
                )
            try await conversationTransaction
                .apply(
                    GraphChatConversationTrustedEvent(
                        graphScope:
                            intent.scope
                                .graphScope,
                        chatScope:
                            intent.scope
                                .chatScope,
                        payload: .queryResolved(
                            plan: plan,
                            result: result,
                            schemaContext:
                                schemaContext
                        )
                    )
                )
            let artifactIDs =
                try await querySupport
                    .stageArtifacts(
                        for: result,
                        plan: plan,
                        action: queryAction,
                        schemaContext:
                            schemaContext,
                        language:
                            intent
                                .responseLanguage,
                        registry:
                            artifactRegistry,
                        evidenceRegistry:
                            evidenceRegistry,
                        presentationRegistry:
                            presentationRegistry,
                        transactionID:
                            transactionID
                    )
            return ActionExecution(
                response:
                    GraphChatModelToolResponse(
                        tool:
                            .queryDetailValues,
                        state:
                            querySupport
                                .toolState(
                                    for:
                                        result
                                            .state
                                ),
                        content:
                            "local-intent-query-result",
                        evidenceIDs:
                            result.evidence
                                .map(\.id),
                        artifactIDs:
                            artifactIDs
                    ),
                evidence: result.evidence,
                artifactIDs: artifactIDs,
                authoritativeFactExpectation:
                    expectation
            )

        case .search(let searchAction):
            let budget = GraphChatToolBudget(
                policy:
                    GraphChatToolBudgetPolicy(
                        maximumCalls: 1,
                        maximumResultCountPerTool:
                            SearchGraphTool
                                .maximumResultCount,
                        maximumEvidenceCount:
                            intent.limits
                                .maximumEvidenceCount
                    )
            )
            let rawResult =
                try await searchExecutor
                    .execute(
                        SearchGraphInput(
                            query:
                                searchAction
                                    .query,
                            limit:
                                searchAction
                                    .limit
                        ),
                        context:
                            GraphChatToolContext(
                                scope:
                                    searchAction
                                        .scope,
                                budget: budget
                            )
                    )
            try Task.checkCancellation()
            let result = searchSupport
                .normalizedResult(
                    rawResult,
                    action: searchAction,
                    schemaContext:
                        schemaContext
                )
            guard
                result.output.hits.count
                    <= intent.limits
                        .resultLimit,
                result.evidence.count
                    <= intent.limits
                        .maximumEvidenceCount
            else {
                throw GraphChatLocalIntentExecutionError
                    .safetyLimitExceeded
            }
            try await evidenceRegistry.register(
                result.evidence
            )
            await presentationRegistry
                .registerValidatedEvidence(
                    result.evidence
                )
            try await conversationTransaction
                .apply(
                    GraphChatConversationTrustedEvent(
                        graphScope:
                            intent.scope
                                .graphScope,
                        chatScope:
                            intent.scope
                                .chatScope,
                        payload:
                            .searchResolved(
                                output:
                                    result.output,
                                state:
                                    result.state,
                                evidence:
                                    result.evidence
                            )
                    )
                )
            let artifactIDs =
                try await searchSupport
                    .stageArtifacts(
                        for: result,
                        action: searchAction,
                        intent: intent,
                        registry:
                            artifactRegistry,
                        evidenceRegistry:
                            evidenceRegistry,
                        presentationRegistry:
                            presentationRegistry,
                        transactionID:
                            transactionID
                    )
            return ActionExecution(
                response:
                    GraphChatModelToolResponse(
                        tool: .searchGraph,
                        state: result.state,
                        content:
                            "local-semantic-search-result",
                        evidenceIDs:
                            result.evidence
                                .map(\.id),
                        artifactIDs:
                            artifactIDs
                    ),
                evidence: result.evidence,
                artifactIDs: artifactIDs,
                authoritativeFactExpectation:
                    nil
            )

        case .node(let nodeAction):
            let budget = GraphChatToolBudget(
                policy:
                    GraphChatToolBudgetPolicy(
                        maximumCalls: 1,
                        maximumResultCountPerTool:
                            GetNodeTool
                                .maximumRelatedItemCount
                                + 1,
                        maximumEvidenceCount:
                            intent.limits
                                .maximumEvidenceCount
                    )
            )
            let result = try await nodeExecutor
                .execute(
                    GetNodeInput(
                        node:
                            nodeAction.node.node,
                        relatedLimit:
                            nodeAction
                                .relatedLimit,
                        includeNotes: true
                    ),
                    context:
                        GraphChatToolContext(
                            scope:
                                intent.scope
                                    .queryScope,
                            budget: budget
                        )
                )
            try Task.checkCancellation()
            guard result.state == .success,
                  let output = result.payload,
                  output.node
                    == nodeAction.node.node,
                  result.evidence.count
                    <= intent.limits
                        .maximumEvidenceCount
            else {
                throw GraphChatLocalIntentExecutionError
                    .staleSchemaIdentity
            }
            try await evidenceRegistry.register(
                result.evidence
            )
            await presentationRegistry
                .registerValidatedEvidence(
                    result.evidence
                )
            try await conversationTransaction
                .apply(
                    GraphChatConversationTrustedEvent(
                        graphScope:
                            intent.scope
                                .graphScope,
                        chatScope:
                            intent.scope
                                .chatScope,
                        payload: .nodeResolved(
                            output: output,
                            state: result.state,
                            evidence:
                                result.evidence
                        )
                    )
                )
            let draft =
                GraphChatAnswerArtifactFactory
                    .nodeDetails(
                        output: output,
                        graphScope:
                            intent.scope
                                .graphScope,
                        language:
                            intent
                                .responseLanguage
                    )
                ?? GraphChatAnswerArtifactFactory
                    .nodeOverview(
                        output: output,
                        graphScope:
                            intent.scope
                                .graphScope,
                        language:
                            intent
                                .responseLanguage
                    )
            guard let draft else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            let artifactIDs = try await stage(
                [draft],
                registry: artifactRegistry,
                evidenceRegistry:
                    evidenceRegistry,
                presentationRegistry:
                    presentationRegistry,
                transactionID: transactionID
            )
            return ActionExecution(
                response:
                    GraphChatModelToolResponse(
                        tool: .getNode,
                        state: .success,
                        content:
                            "local-node-details-result",
                        evidenceIDs:
                            result.evidence
                                .map(\.id),
                        artifactIDs:
                            artifactIDs
                    ),
                evidence: result.evidence,
                artifactIDs: artifactIDs,
                authoritativeFactExpectation:
                    nil
            )

        case .sameEntityComparison(
            let comparison,
            let queryPlan
        ):
            let result = try await queryExecutor
                .execute(queryPlan)
            try Task.checkCancellation()
            let resultNodes = Set(
                result.rows.map(\.node)
            )
            guard
                result.state == .success,
                resultNodes
                    == Set(
                        comparison.nodes
                            .map(\.node)
                    ),
                result.rows.count
                    == comparison.nodes.count,
                result.evidence.isEmpty
                    == false,
                result.evidence.count
                    <= intent.limits
                        .maximumEvidenceCount
            else {
                throw GraphChatLocalIntentExecutionError
                    .staleSchemaIdentity
            }
            guard let draft =
                    GraphChatAnswerArtifactFactory
                        .comparison(
                            result: result,
                            plan: comparison,
                            schemaContext:
                                schemaContext
                        )
            else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            try await evidenceRegistry.register(
                result.evidence
            )
            await presentationRegistry
                .registerValidatedEvidence(
                    result.evidence
                )
            try await conversationTransaction
                .apply(
                    GraphChatConversationTrustedEvent(
                        graphScope:
                            intent.scope
                                .graphScope,
                        chatScope:
                            intent.scope
                                .chatScope,
                        payload: .queryResolved(
                            plan: queryPlan,
                            result: result,
                            schemaContext:
                                schemaContext
                        )
                    )
                )
            let comparisonSubjects =
                conversationComparisonSubjects(
                    from: draft,
                    plannedNodes:
                        comparison.nodes
                )
            guard comparisonSubjects.count >= 2 else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            try await conversationTransaction
                .apply(
                    GraphChatConversationTrustedEvent(
                        graphScope:
                            intent.scope
                                .graphScope,
                        chatScope:
                            intent.scope
                                .chatScope,
                        payload:
                            .comparisonResultResolved(
                                subjects:
                                    comparisonSubjects,
                                evidence:
                                    result.evidence,
                                technicalDescription:
                                    "Fachlicher Vergleich mit \(comparisonSubjects.count) Subjects und \(comparison.features.count) autoritativen Features"
                            )
                    )
                )
            let artifactIDs = try await stage(
                [draft],
                registry: artifactRegistry,
                evidenceRegistry:
                    evidenceRegistry,
                presentationRegistry:
                    presentationRegistry,
                transactionID: transactionID
            )
            return ActionExecution(
                response:
                    GraphChatModelToolResponse(
                        tool:
                            .queryDetailValues,
                        state: .success,
                        content:
                            "local-same-entity-comparison-result",
                        evidenceIDs:
                            result.evidence
                                .map(\.id),
                        artifactIDs:
                            artifactIDs
                    ),
                evidence: result.evidence,
                artifactIDs: artifactIDs,
                authoritativeFactExpectation:
                    nil
            )

        case .structuralComparison(
            let comparison
        ):
            let budget = GraphChatToolBudget(
                policy:
                    GraphChatToolBudgetPolicy(
                        maximumCalls:
                            comparison.nodes.count,
                        maximumResultCountPerTool:
                            GetNodeTool
                                .maximumRelatedItemCount
                                + 1,
                        maximumEvidenceCount:
                            intent.limits
                                .maximumEvidenceCount
                    )
            )
            var outputs: [GetNodeOutput] = []
            var collectedEvidence:
                [GraphEvidence] = []
            for node in comparison.nodes {
                try Task.checkCancellation()
                let result =
                    try await nodeExecutor.execute(
                        GetNodeInput(
                            node: node.node,
                            relatedLimit:
                                comparison
                                    .relatedLimit,
                            includeNotes: false
                        ),
                        context:
                            GraphChatToolContext(
                                scope:
                                    comparison
                                        .chatScope,
                                budget: budget
                            )
                    )
                guard
                    result.state == .success,
                    let output =
                        result.payload,
                    output.node == node.node,
                    output.structureEvidenceID
                        != nil
                else {
                    throw GraphChatLocalIntentExecutionError
                        .staleSchemaIdentity
                }
                outputs.append(output)
                collectedEvidence.append(
                    contentsOf:
                        result.evidence
                )
            }
            let evidence =
                GraphEvidenceCollection(
                    collectedEvidence
                ).values
            guard outputs.count
                    == comparison.nodes.count,
                  evidence.count
                    <= intent.limits
                        .maximumEvidenceCount,
                  let draft =
                    GraphChatAnswerArtifactFactory
                        .structuralComparison(
                            outputs: outputs,
                            evidence: evidence,
                            plan: comparison
                        )
            else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            try await evidenceRegistry.register(
                evidence
            )
            await presentationRegistry
                .registerValidatedEvidence(
                    evidence
                )
            let comparisonSubjects =
                conversationComparisonSubjects(
                    from: draft,
                    plannedNodes:
                        comparison.nodes
                )
            guard comparisonSubjects.count >= 2 else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            try await conversationTransaction
                .apply(
                    GraphChatConversationTrustedEvent(
                        graphScope:
                            intent.scope
                                .graphScope,
                        chatScope:
                            intent.scope
                                .chatScope,
                        payload:
                            .comparisonResultResolved(
                                subjects:
                                    comparisonSubjects,
                                evidence:
                                    evidence,
                                technicalDescription:
                                    "Struktureller Vergleich mit \(comparisonSubjects.count) Subjects und \(comparison.features.count) belegten Features"
                            )
                    )
                )
            let artifactIDs = try await stage(
                [draft],
                registry: artifactRegistry,
                evidenceRegistry:
                    evidenceRegistry,
                presentationRegistry:
                    presentationRegistry,
                transactionID: transactionID
            )
            return ActionExecution(
                response:
                    GraphChatModelToolResponse(
                        tool: .getNode,
                        state: .success,
                        content:
                            "local-structural-comparison-result",
                        evidenceIDs:
                            evidence.map(\.id),
                        artifactIDs:
                            artifactIDs
                    ),
                evidence: evidence,
                artifactIDs: artifactIDs,
                authoritativeFactExpectation:
                    nil
            )

        case .graphState(let stateAction):
            let budget = GraphChatToolBudget(
                policy:
                    GraphChatToolBudgetPolicy(
                        maximumCalls: 1,
                        maximumResultCountPerTool:
                            GraphStatsTool
                                .maximumHubCount
                                + 1,
                        maximumEvidenceCount:
                            intent.limits
                                .maximumEvidenceCount
                    )
            )
            let result = try await statsExecutor
                .execute(
                    GraphStatsInput(
                        hubLimit:
                            stateAction.hubLimit
                    ),
                    context:
                        GraphChatToolContext(
                            scope:
                                intent.scope
                                    .chatScope,
                            budget: budget
                        )
                )
            try Task.checkCancellation()
            guard result.state == .success,
                  let output = result.payload,
                  result.evidence.isEmpty
                    == false,
                  result.evidence.count
                    <= intent.limits
                        .maximumEvidenceCount
            else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            let drafts =
                GraphChatAnswerArtifactFactory
                    .graphState(
                        output: output,
                        aspect:
                            stateAction.aspect,
                        graphScope:
                            intent.scope
                                .graphScope,
                        requestedHubLimit:
                            stateAction.hubLimit,
                        language:
                            intent
                                .responseLanguage
                    )
            guard drafts.isEmpty == false,
                  drafts.count
                    <= intent.limits
                        .maximumArtifactCount
            else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            try await evidenceRegistry.register(
                result.evidence
            )
            await presentationRegistry
                .registerValidatedEvidence(
                    result.evidence
                )
            try await conversationTransaction
                .apply(
                    GraphChatConversationTrustedEvent(
                        graphScope:
                            intent.scope
                                .graphScope,
                        chatScope:
                            intent.scope
                                .chatScope,
                        payload: .statsResolved(
                            output: output,
                            state: result.state,
                            evidence:
                                result.evidence
                        )
                    )
                )
            let artifactIDs = try await stage(
                drafts,
                registry: artifactRegistry,
                evidenceRegistry:
                    evidenceRegistry,
                presentationRegistry:
                    presentationRegistry,
                transactionID: transactionID
            )
            return ActionExecution(
                response:
                    GraphChatModelToolResponse(
                        tool: .graphStats,
                        state: .success,
                        content:
                            "local-graph-state-result",
                        evidenceIDs:
                            result.evidence
                                .map(\.id),
                        artifactIDs:
                            artifactIDs
                    ),
                evidence: result.evidence,
                artifactIDs: artifactIDs,
                authoritativeFactExpectation:
                    nil
            )

        case .relationship(let plan):
            let budget = GraphChatToolBudget(
                policy:
                    GraphChatToolBudgetPolicy(
                        maximumCalls: 1,
                        maximumResultCountPerTool:
                            plan.limits
                                .maximumResultLimit
                                + 1,
                        maximumEvidenceCount:
                            plan.limits
                                .maximumEvidenceCount
                    )
            )
            let result =
                try await relationshipExecutor
                    .execute(
                        plan,
                        context:
                            GraphChatToolContext(
                                scope:
                                    plan.queryScope,
                                budget: budget
                            )
                    )
            try Task.checkCancellation()
            guard
                (
                    result.state == .success
                    || result.state
                        == .noResults
                ),
                let output = result.payload,
                output.center.nodeKey
                    == plan.centerNode.node,
                output.connections.count
                    <= plan.limits
                        .resultLimit,
                result.evidence.isEmpty
                    == false,
                result.evidence.count
                    <= plan.limits
                        .maximumEvidenceCount,
                let draft =
                    GraphChatAnswerArtifactFactory
                        .relationships(
                            output: output,
                            plan: plan
                        )
            else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            try await evidenceRegistry.register(
                result.evidence
            )
            await presentationRegistry
                .registerValidatedEvidence(
                    result.evidence
                )
            try await conversationTransaction
                .apply(
                    GraphChatConversationTrustedEvent(
                        graphScope:
                            intent.scope.graphScope,
                        chatScope:
                            intent.scope.chatScope,
                        payload:
                            .relationshipResolved(
                                plan: plan,
                                output: output,
                                state:
                                    result.state,
                                evidence:
                                    result.evidence
                            )
                    )
                )
            let artifactIDs = try await stage(
                [draft],
                registry: artifactRegistry,
                evidenceRegistry:
                    evidenceRegistry,
                presentationRegistry:
                    presentationRegistry,
                transactionID: transactionID
            )
            return ActionExecution(
                response:
                    GraphChatModelToolResponse(
                        tool: .getNeighbors,
                        state: result.state,
                        content:
                            "local-relationship-result",
                        evidenceIDs:
                            result.evidence
                                .map(\.id),
                        artifactIDs:
                            artifactIDs
                    ),
                evidence: result.evidence,
                artifactIDs: artifactIDs,
                authoritativeFactExpectation:
                    nil
            )
        }
    }

    private func stage(
        _ drafts:
            [GraphChatAnswerArtifactDraft],
        registry:
            GraphChatAnswerArtifactRegistry,
        evidenceRegistry:
            GraphChatEvidenceRegistry,
        presentationRegistry:
            GraphChatPresentationRegistry,
        transactionID:
            GraphChatAnswerArtifactTransactionID
    ) async throws
        -> [GraphChatAnswerArtifactID]
    {
        var values:
            [GraphChatAnswerArtifactID] = []
        for draft in drafts {
            try Task.checkCancellation()
            try validateLocallyCompiledArtifact(
                draft
            )
            let id = try await registry.stage(
                draft,
                transactionID:
                    transactionID,
                evidenceRegistry:
                    evidenceRegistry
            )
            await presentationRegistry
                .registerValidatedArtifact(
                    id: id,
                    title: draft.title
                )
            values.append(id)
        }
        return values
    }

    private func validateLocallyCompiledArtifact(
        _ draft:
            GraphChatAnswerArtifactDraft
    ) throws {
        if case .relationship(let payload) =
                draft.payload {
            guard
                payload.identityEvidence
                    .evidenceIDs
                    .isEmpty == false,
                payload.connections
                    .allSatisfy({
                        $0.evidence
                            .evidenceIDs
                            .isEmpty == false
                    }),
                payload.resultMetadata
                    .returnedCount
                    == payload
                        .connections.count,
                payload.resultWindow
                    .returnedCount
                    == payload
                        .connections.count,
                payload.resultWindow
                    .totalCount
                    == payload.resultMetadata
                        .totalCount
            else {
                throw GraphChatLocalIntentExecutionError
                    .artifactUnavailable
            }
            return
        }
        guard case .comparison(let payload) =
                draft.payload else {
            return
        }
        let subjectIDs = Set(
            payload.subjects.map(\.id)
        )
        let featureIDs = Set(
            payload.features.map(\.id)
        )
        let valueSubjectIDs = Set(
            payload.values.map(\.subjectID)
        )
        let valueFeatureIDs = Set(
            payload.values.map(\.featureID)
        )
        guard
            payload.subjects.count >= 2,
            payload.features.isEmpty == false,
            payload.values.isEmpty == false,
            valueSubjectIDs == subjectIDs,
            valueFeatureIDs == featureIDs,
            payload.values.allSatisfy({
                guard let evidence =
                        $0.evidence
                else {
                    return false
                }
                return evidence
                    .evidenceIDs
                    .isEmpty == false
            })
        else {
            throw GraphChatLocalIntentExecutionError
                .artifactUnavailable
        }
    }

    private func conversationComparisonSubjects(
        from draft:
            GraphChatAnswerArtifactDraft,
        plannedNodes:
            [GraphChatTypedNodeIdentity]
    ) -> [GraphChatConversationComparisonSubject] {
        guard case .comparison(let payload) =
                draft.payload
        else {
            return []
        }
        let plannedByNode = Dictionary(
            uniqueKeysWithValues:
                plannedNodes.map {
                    ($0.node, $0)
                }
        )
        return payload.subjects.compactMap {
            subject in
            guard
                let target =
                    subject.navigationTarget,
                case .openNode(
                    _,
                    let node
                ) = target,
                let planned = plannedByNode[node]
            else {
                return nil
            }
            var seen = Set<GraphEvidenceID>()
            let evidenceIDs =
                (
                    subject.evidence.evidenceIDs
                    + payload.values
                        .filter {
                            $0.subjectID == subject.id
                        }
                        .flatMap {
                            $0.evidence?
                                .evidenceIDs ?? []
                        }
                ).filter {
                    seen.insert($0).inserted
                }
            guard evidenceIDs.isEmpty == false else {
                return nil
            }
            return GraphChatConversationComparisonSubject(
                node: node,
                label: subject.label,
                ownerEntityID:
                    planned.ownerEntityID,
                evidenceIDs: evidenceIDs
            )
        }
    }

    private func validateNodeAction(
        _ action:
            GraphChatLocalNodeDetailsAction,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext
    ) throws {
        let policy =
            GraphChatAdvancedIntentPolicy
                .default
        guard
            intent.kind == .nodeDetails,
            intent.factExpectation == .none,
            intent.expectedCardinality
                == .zeroOrOne,
            case .nodeDetails(let details) =
                intent.payload,
            details.node == action.node,
            action.relatedLimit
                == policy
                    .nodeDetailRelatedLimit,
            intent.scope.queryScope
                == .node(
                    action.node.node,
                    in:
                        intent.scope
                            .graphScope
                ),
            GraphChatScopeAuthorization.allows(
                scope:
                    intent.scope.queryScope,
                within:
                    intent.scope.chatScope,
                aliases:
                    schemaContext.aliases
            )
        else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
    }

    private func validateComparisonAction(
        _ plan: GraphChatComparisonPlan,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext
    ) throws {
        guard
            intent.kind == .compareNodes,
            intent.factExpectation == .none,
            intent.expectedCardinality
                == .twoOrMore,
            case .compareNodes(let details) =
                intent.payload,
            plan.policy
                == GraphChatAdvancedIntentPolicy
                    .default,
            plan.binding == intent.binding,
            plan.graphScope
                == intent.scope.graphScope,
            plan.chatScope
                == intent.scope.chatScope,
            plan.responseLanguage
                == intent.responseLanguage,
            plan.nodes == details.nodes,
            Set(
                plan.nodes.map(\.node)
            ).count == plan.nodes.count,
            plan.nodes.count
                <= plan.policy
                    .maximumComparisonNodeCount,
            plan.features.count
                <= plan.policy
                    .maximumComparisonFeatureCount,
            intent.scope.queryScope
                == (try GraphChatScope.selection(
                    plan.nodes.map(\.node),
                    in: plan.graphScope
                )),
            GraphChatScopeAuthorization.allows(
                scope:
                    intent.scope.queryScope,
                within: plan.chatScope,
                aliases:
                    schemaContext.aliases
            )
        else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        switch plan.kind {
        case .sameEntityAttributes:
            let fields =
                plan.features.compactMap {
                    if case .field(let field) =
                        $0 {
                        return field
                    }
                    return nil
                }
            guard
                fields == details.fields,
                plan.relatedLimit == 0,
                plan.selectionQuery != nil
            else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }
        case .structural:
            guard details.fields.isEmpty,
                  plan.relatedLimit
                    == plan.policy
                        .structuralRelatedLimit,
                  plan.selectionQuery == nil,
                  plan.features.allSatisfy({ feature in
                      if case .structure = feature {
                          return true
                      }
                      return false
                  }) else {
                throw GraphChatLocalIntentExecutionError
                    .invalidCompiledAction
            }
        }
    }

    private func validateGraphStateAction(
        _ action:
            GraphChatLocalGraphStateAction,
        intent: GraphChatTypedIntent
    ) throws {
        let policy =
            GraphChatAdvancedIntentPolicy
                .default
        guard
            intent.kind
                == .inspectGraphState,
            intent.factExpectation == .none,
            intent.expectedCardinality
                == .exactlyOne,
            case .inspectGraphState(
                let details
            ) = intent.payload,
            details.entity == nil,
            details.aspect
                == action.aspect,
            action.hubLimit
                == policy.graphHubLimit,
            intent.scope.chatScope
                == GraphChatScope.entireGraph(
                    intent.scope.graphScope
                ),
            intent.scope.queryScope
                == intent.scope.chatScope
        else {
            throw GraphChatLocalIntentExecutionError
                .scopeExpansionPrevented
        }
    }

    private func validateRelationshipAction(
        _ plan: GraphChatRelationshipPlan,
        intent: GraphChatTypedIntent,
        schemaContext: GraphSchemaContext,
        providerPlan: GraphChatProviderTurnPlan
    ) throws {
        guard
            intent.version == .v2,
            intent.kind == .relationships,
            intent.factExpectation == .none,
            intent.expectedCardinality
                == .zeroOrMore,
            case .relationships(
                let payloadPlan
            ) = intent.payload,
            payloadPlan == plan,
            plan.binding == intent.binding,
            plan.graphScope
                == intent.scope.graphScope,
            plan.chatScope
                == intent.scope.chatScope,
            plan.queryScope
                == intent.scope.queryScope,
            plan.limits == intent.limits,
            plan.responseLanguage
                == intent.responseLanguage,
            let center =
                schemaContext
                    .foundationalAliases
                    .nodesByKey[
                        plan.centerNode.node
                    ],
            center.ownerEntityID
                == plan.centerEntity.id,
            center.displayName
                == plan.centerNode.displayName,
            schemaContext
                .foundationalAliases
                .entity(
                    id:
                        plan.centerEntity.id
                ) != nil,
            GraphChatScopeAuthorization.allows(
                scope: plan.queryScope,
                within: plan.chatScope,
                aliases:
                    schemaContext
                        .foundationalAliases
            )
        else {
            throw GraphChatLocalIntentExecutionError
                .invalidCompiledAction
        }
        if let counterpartEntity =
                plan.counterpartEntity {
            guard
                schemaContext
                    .foundationalAliases
                    .entity(
                        id:
                            counterpartEntity.id
                    ) != nil
            else {
                throw GraphChatLocalIntentExecutionError
                    .staleSchemaIdentity
            }
        }
        if let counterpartNode =
                plan.counterpartNode {
            guard
                let node =
                    schemaContext
                        .foundationalAliases
                        .nodesByKey[
                            counterpartNode.node
                        ],
                node.ownerEntityID
                    == counterpartNode
                        .ownerEntityID,
                node.displayName
                    == counterpartNode
                        .displayName
            else {
                throw GraphChatLocalIntentExecutionError
                    .staleSchemaIdentity
            }
        }
        if let sourceContextID =
                plan
                    .sourceRelationshipContextID {
            guard
                let previous =
                    providerPlan
                        .requestBaseState
                        .lastRelationship,
                previous.resultContextID
                    == sourceContextID,
                previous.sourceTurnID
                    == plan.binding
                        .sourceTurnID,
                previous.plan.graphScope
                    == plan.graphScope,
                previous.plan.chatScope
                    == plan.chatScope,
                previous.plan.centerEntity.id
                    == plan.centerEntity.id,
                previous.plan.centerNode.node
                    == plan.centerNode.node,
                previous.plan.counterpartEntity?
                    .id
                    == plan.counterpartEntity?
                        .id,
                previous.plan.counterpartNode?
                    .node
                    == plan.counterpartNode?
                        .node,
                providerPlan
                    .requestBaseState
                    .turnContexts
                    .contains(
                        where: {
                            $0.id
                                == previous
                                    .sourceTurnID
                        }
                    ),
                providerPlan
                    .requestBaseState
                    .resultContexts
                    .contains(
                        where: {
                            $0.id
                                == sourceContextID
                            && $0.kind
                                == .relationship
                        }
                    )
            else {
                throw GraphChatLocalIntentExecutionError
                    .staleResultSet
            }
        }
    }

    private func validateBinding(
        intent: GraphChatTypedIntent,
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        artifactSession: GraphChatArtifactSessionResources
    ) throws {
        guard intent.binding.requestID == requestID,
              intent.binding.turnID == requestID,
              intent.binding.conversationID
                == providerPlan.requestBaseState
                    .conversationID else {
            throw GraphChatLocalIntentExecutionError
                .invalidBinding
        }
        if let sourceTurnID = intent.binding.sourceTurnID {
            guard providerPlan.requestBaseState
                .turnContexts.contains(
                    where: { $0.id == sourceTurnID }
                ),
                  (
                    providerPlan
                        .foundationalContinuation?
                        .sourceTurnID
                        == sourceTurnID
                    || providerPlan
                            .semanticContinuation?
                            .sourceTurnID
                            == sourceTurnID
                    || providerPlan
                            .currentResolvedScope?
                            .revision
                            .sourceTurnID
                            == sourceTurnID
                    || providerPlan
                            .requestBaseState
                            .lastRelationship?
                            .sourceTurnID
                            == sourceTurnID
                  ) else {
                throw GraphChatLocalIntentExecutionError
                    .invalidBinding
            }
        }
        if let clarificationID =
            intent.binding.clarificationID {
            guard
                providerPlan
                    .foundationalContinuation?
                    .clarificationID
                    == clarificationID
                    || providerPlan
                        .semanticContinuation?
                        .clarificationID
                        == clarificationID
            else {
                throw GraphChatLocalIntentExecutionError
                    .invalidBinding
            }
        }
        guard intent.scope.graphScope
                == providerPlan.scopeKey.graphScope,
              intent.scope.chatScope
                == providerPlan.scopeKey.chatScope,
              providerPlan.requestBaseState.graphScope
                == intent.scope.graphScope,
              providerPlan.requestBaseState.chatScope
                == intent.scope.chatScope,
              artifactSession.key
                == providerPlan.scopeKey else {
            throw GraphChatLocalIntentExecutionError
                .invalidScope
        }
    }

    private func cleanup(
        evidenceRegistry: GraphChatEvidenceRegistry,
        presentationRegistry:
            GraphChatPresentationRegistry,
        artifactRegistry:
            GraphChatAnswerArtifactRegistry,
        transactionID:
            GraphChatAnswerArtifactTransactionID,
        ledger: GraphChatPrimaryResultLedger,
        conversationTransaction:
            GraphChatConversationStateTransaction,
        requestID: UUID,
        discardLedgerTransaction: Bool,
        outcome: GraphChatLocalIntentCleanupOutcome
    ) async -> GraphChatLocalIntentCleanupReport {
        await evidenceRegistry.removeAll()
        await presentationRegistry.removeAll()
        await artifactRegistry.rollbackDeferredCommit(
            transactionID: transactionID
        )
        if discardLedgerTransaction {
            await ledger.discard(
                transactionID: transactionID
            )
        }
        await ledger.finish(requestID: requestID)
        await conversationTransaction.resetToBase()
        let evidenceCount =
            await evidenceRegistry.snapshotForTesting().count
        let presentation =
            await presentationRegistry.snapshot()
        let stagedArtifactCount =
            await artifactRegistry.stagedSnapshotForTesting(
                transactionID: transactionID
            ).count
        let ledgerSnapshot =
            await ledger.snapshotForTesting(
                transactionID: transactionID
            )
        let conversationSnapshot =
            await conversationTransaction.snapshot()
        let conversationBase =
            await conversationTransaction.baseSnapshot()
        let conversationRestoredToBase =
            conversationSnapshot == conversationBase
        return GraphChatLocalIntentCleanupReport(
            outcome: outcome,
            evidenceCount: evidenceCount,
            presentationEntryCount:
                presentation.entries.count,
            stagedArtifactCount: stagedArtifactCount,
            ledgerEntryCount:
                ledgerSnapshot.entries.count,
            ledgerIsBound:
                ledgerSnapshot.requestBinding != nil,
            conversationRestoredToBase:
                conversationRestoredToBase
        )
    }

    private func recordRevalidationRejection(
        _ error: Error,
        kind: GraphChatTypedIntentKind
    ) async {
        let rejection:
            GraphChatLocalIntentRevalidationRejection
        guard let executionError =
            error as? GraphChatLocalIntentExecutionError else {
            rejection = .compiledAction
            await record(
                .revalidationRejected,
                kind: kind,
                rejection: rejection
            )
            return
        }
        if executionError
            == .scopeExpansionPrevented
        {
            await record(
                .scopeExpansionPrevented,
                kind: kind,
                rejection: .scope
            )
        } else if executionError
            == .staleResultSet
        {
            await record(
                .staleResultSetRejected,
                kind: kind,
                rejection: .compiledAction
            )
        } else if executionError
            == .staleSchemaIdentity,
            kind == .nodeDetails
                || kind == .compareNodes
        {
            await record(
                .staleNodeDiscarded,
                kind: kind,
                rejection: .schemaIdentity
            )
        }
        switch executionError {
        case .invalidBinding:
            rejection = .binding
        case .invalidScope:
            rejection = .scope
        case .staleSchemaIdentity:
            rejection = .schemaIdentity
        case .invalidCompiledAction, .safetyLimitExceeded,
            .artifactUnavailable, .primaryResultUnavailable,
            .scopeExpansionPrevented,
            .staleResultSet:
            rejection = .compiledAction
        }
        await record(
            .revalidationRejected,
            kind: kind,
            rejection: rejection
        )
    }

    private func localExecutionError(
        for error:
            GraphChatComposableReadPlanValidationError
    ) -> GraphChatLocalIntentExecutionError {
        switch error {
        case .bindingMismatch:
            return .invalidBinding
        case .scopeMismatch:
            return .invalidScope
        case .invalidLimits:
            return .safetyLimitExceeded
        case .staleEntity, .staleNode,
            .staleField:
            return .staleSchemaIdentity
        case .staleConversationResult:
            return .staleResultSet
        case .unsupportedVersion,
            .invalidOperationOrder,
            .duplicateStep,
            .unboundStepReference,
            .cyclicStepReference,
            .invalidSelection,
            .invalidQuery,
            .invalidProjectionAggregation,
            .invalidStableSort,
            .invalidTraversal,
            .invalidResultContract,
            .invalidEvidenceContract,
            .invalidArtifactContract:
            return .invalidCompiledAction
        }
    }

    private func record(
        _ event: GraphChatLocalIntentLifecycleEvent,
        kind: GraphChatTypedIntentKind,
        rejection:
            GraphChatLocalIntentRevalidationRejection? = nil
    ) async {
        await observability.record(
            .localIntent(
                GraphChatLocalIntentMetric(
                    event: event,
                    kind: kind,
                    rejection: rejection
                )
            )
        )
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError
            || Task.isCancelled
        {
            return true
        }
        return (error as? GraphChatToolError)?
            .code == .cancelled
    }
}
