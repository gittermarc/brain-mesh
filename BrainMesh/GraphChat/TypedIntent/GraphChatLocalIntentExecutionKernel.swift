//
//  GraphChatLocalIntentExecutionKernel.swift
//  BrainMesh
//
//  Provider-free execution and lifecycle boundary for app-compiled actions.
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
        }
    }
}

nonisolated struct GraphChatLocalIntentPreparedExecution: Sendable {
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
    private let conversationStateReducer:
        GraphChatConversationStateReducer
    private let timeZone: TimeZone
    private let querySupport:
        GraphChatLocalIntentQueryExecutionSupport
    private let observability:
        any GraphChatObservabilityRecording
    private let observer:
        GraphChatLocalIntentExecutionKernelObserver

    init(
        queryExecutor:
            any GraphChatLocalIntentQueryExecuting,
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
        self.conversationStateReducer =
            conversationStateReducer
        self.timeZone = timeZone
        self.querySupport =
            GraphChatLocalIntentQueryExecutionSupport(
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: referenceDate
            )
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

        let plan: ValidatedGraphQueryPlan
        do {
            try querySupport.revalidateIdentities(
                intent: intent,
                schemaContext: schemaContext
            )
            plan = try querySupport.validatedPlan(
                adaptation: adaptation,
                schemaContext: schemaContext
            )
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
            transactionID: transactionID
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
                    tool: .queryDetailValues,
                    state: .started
                )
            )
            let rawResult = try await queryExecutor.execute(plan)
            try Task.checkCancellation()
            guard rawResult.rows.count
                    <= intent.limits.resultLimit,
                  rawResult.evidence.count
                    <= intent.limits.maximumEvidenceCount else {
                throw GraphChatLocalIntentExecutionError
                    .safetyLimitExceeded
            }
            let authoritativeFactExpectation =
                GraphChatAuthoritativeFactExpectation(
                    intent: intent,
                    result: rawResult,
                    timeZone: timeZone
                )
            let result = querySupport.normalizedResult(
                rawResult,
                contract: querySupport.queryAction(
                    in: adaptation.action
                ).resultContract,
                limit: intent.limits.resultLimit
            )
            try await evidenceRegistry.register(
                result.evidence
            )
            await presentationRegistry
                .registerValidatedEvidence(result.evidence)
            try await conversationTransaction.apply(
                GraphChatConversationTrustedEvent(
                    graphScope: intent.scope.graphScope,
                    chatScope: intent.scope.chatScope,
                    payload: .queryResolved(
                        plan: plan,
                        result: result,
                        schemaContext: schemaContext
                    )
                )
            )

            let artifactIDs =
                try await querySupport.stageArtifacts(
                for: result,
                plan: plan,
                action: querySupport.queryAction(
                    in: adaptation.action
                ),
                schemaContext: schemaContext,
                language: intent.responseLanguage,
                registry: artifactSession.registry,
                evidenceRegistry: evidenceRegistry,
                presentationRegistry:
                    presentationRegistry,
                transactionID: transactionID
            )
            guard artifactIDs.count
                    <= intent.limits.maximumArtifactCount else {
                throw GraphChatLocalIntentExecutionError
                    .safetyLimitExceeded
            }
            let response = GraphChatModelToolResponse(
                tool: .queryDetailValues,
                state: querySupport.toolState(
                    for: result.state
                ),
                content: "local-foundational-result",
                evidenceIDs: result.evidence.map(\.id),
                artifactIDs: artifactIDs
            )
            let artifacts = try await artifactSession.registry
                .validatedArtifacts(
                    for: artifactIDs.map {
                        $0.rawValue.uuidString
                    },
                    graphScope: intent.scope.graphScope,
                    sessionID: artifactSession.sessionID,
                    transactionID: transactionID
                )
            try await ledger.record(
                response: response,
                evidence: result.evidence,
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
                    tool: .queryDetailValues,
                    state: .finished
                )
            )

            let execution =
                GraphChatLocalIntentPreparedExecution(
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
                        authoritativeFactExpectation
                )
            try await validateCurrentRequest()
            try Task.checkCancellation()
            let candidateTurn = try await finalize(execution)
            finalizedTurn = candidateTurn
            try await validateCurrentRequest()
            try Task.checkCancellation()
            try await commit(candidateTurn)
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
            if let finalizedTurn {
                await artifactSession.registry
                    .removeCommittedArtifacts(
                        finalizedTurn
                            .committedArtifactIDs,
                        sessionID:
                            artifactSession.sessionID
                    )
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
                  providerPlan.foundationalContinuation?
                    .sourceTurnID == sourceTurnID else {
                throw GraphChatLocalIntentExecutionError
                    .invalidBinding
            }
        }
        if let clarificationID =
            intent.binding.clarificationID {
            guard providerPlan.foundationalContinuation?
                .clarificationID == clarificationID else {
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
        await artifactRegistry.rollback(
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
        switch executionError {
        case .invalidBinding:
            rejection = .binding
        case .invalidScope:
            rejection = .scope
        case .staleSchemaIdentity:
            rejection = .schemaIdentity
        case .invalidCompiledAction, .safetyLimitExceeded,
            .artifactUnavailable, .primaryResultUnavailable:
            rejection = .compiledAction
        }
        await record(
            .revalidationRejected,
            kind: kind,
            rejection: rejection
        )
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
        error is CancellationError || Task.isCancelled
    }
}
