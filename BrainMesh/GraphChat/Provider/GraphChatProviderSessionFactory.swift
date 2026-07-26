//
//  GraphChatProviderSessionFactory.swift
//  BrainMesh
//
//  Complete creation and cleanup of graph/scope-bound provider attempts.
//

import Foundation

nonisolated enum GraphChatProviderSessionPurpose: String, Hashable, Sendable {
    case standard
    case recovery
}

nonisolated struct GraphChatProviderSessionFactory: Sendable {
    static let controlledToolKinds: Set<GraphChatToolKind> = [
        .describeGraphSchema,
        .searchGraph,
        .queryDetailValues,
        .getNode,
        .getNeighbors,
        .graphStats,
    ]

    private let provider: any GraphChatModelProvider
    private let schemaProvider: any GraphSchemaSnapshotProviding
    private let toolRunnerFactory: any GraphChatModelToolRunnerFactory
    private let standardToolBudgetPolicy: GraphChatToolBudgetPolicy
    private let conversationStateReducer: GraphChatConversationStateReducer
    private let referenceResolver: GraphChatConversationReferenceResolver
    private let requestBuilder: GraphChatProviderRequestBuilder
    private let errorMapper: GraphChatProviderErrorMapper
    private let observability: any GraphChatObservabilityRecording
    private let referenceDate: @Sendable () -> Date
    private let calendar: Calendar
    private let timeZone: TimeZone

    init(
        provider: any GraphChatModelProvider,
        schemaProvider: any GraphSchemaSnapshotProviding,
        toolRunnerFactory: any GraphChatModelToolRunnerFactory,
        standardToolBudgetPolicy: GraphChatToolBudgetPolicy,
        conversationStateReducer: GraphChatConversationStateReducer,
        referenceResolver: GraphChatConversationReferenceResolver,
        requestBuilder: GraphChatProviderRequestBuilder,
        errorMapper: GraphChatProviderErrorMapper,
        observability: any GraphChatObservabilityRecording =
            NoOpGraphChatObservabilityRecorder(),
        referenceDate: @escaping @Sendable () -> Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) {
        self.provider = provider
        self.schemaProvider = schemaProvider
        self.toolRunnerFactory = toolRunnerFactory
        self.standardToolBudgetPolicy = standardToolBudgetPolicy
        self.conversationStateReducer = conversationStateReducer
        self.referenceResolver = referenceResolver
        self.requestBuilder = requestBuilder
        self.errorMapper = errorMapper
        self.observability = observability
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.timeZone = timeZone
    }

    func makeInitialSession(
        for key: GraphChatOrchestrationScopeKey,
        artifactSession: GraphChatArtifactSessionResources,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage
    ) async throws -> GraphChatProviderSessionResources {
        let schemaContext = try await loadSchema(for: key)
        let primaryResultLedger = GraphChatPrimaryResultLedger(
            graphScope: key.graphScope,
            chatScope: key.chatScope,
            artifactSessionID: artifactSession.sessionID
        )
        return try await makeSession(
            purpose: .standard,
            key: key,
            schemaContext: schemaContext,
            artifactSession: artifactSession,
            conversationBaseState: conversationBaseState,
            conversationContext: conversationContext,
            responseLanguage: responseLanguage,
            toolBudgetPolicy: budgetPolicy(for: .standard),
            recoveryCoordinator: GraphChatProviderRecoveryCoordinator(
                observability: observability
            ),
            primaryResultLedger: primaryResultLedger
        )
    }

    func makeRecoverySession(
        replacing resources: GraphChatProviderSessionResources
    ) async throws -> GraphChatProviderSessionResources {
        let artifactSession = GraphChatArtifactSessionResources(
            key: resources.key,
            sessionID: resources.artifactSessionID,
            registry: resources.artifactRegistry
        )
        let carriesPendingRepair = await resources.recoveryCoordinator
            .pendingRepairResult() != nil
        return try await makeSession(
            purpose: .recovery,
            key: resources.key,
            schemaContext: resources.schemaContext,
            artifactSession: artifactSession,
            conversationBaseState: resources.conversationBaseState,
            conversationContext: resources.conversationContext,
            responseLanguage: resources.responseLanguage,
            toolBudgetPolicy: recoveryBudgetPolicy(
                carriesPendingRepair: carriesPendingRepair
            ),
            recoveryCoordinator: resources.recoveryCoordinator,
            primaryResultLedger: resources.primaryResultLedger
        )
    }

    func prewarm(
        _ resources: GraphChatProviderSessionResources
    ) async throws {
        do {
            try await provider.prewarm(
                sessionID: resources.sessionID,
                promptPrefix: requestBuilder.prewarmPromptPrefix(
                    language: resources.responseLanguage
                )
            )
        } catch {
            await cleanupFailedAttempt(
                resources,
                requestProviderCancellation: false
            )
            throw errorMapper.map(error)
        }
    }

    func requestCancellation(
        _ resources: GraphChatProviderSessionResources
    ) async {
        await resources.lifecycle.requestProviderCancellation(
            provider: provider,
            sessionID: resources.sessionID
        )
    }

    func completeProviderStream(
        _ resources: GraphChatProviderSessionResources
    ) async {
        await resources.lifecycle.completeProviderStream(
            provider: provider,
            sessionID: resources.sessionID
        )
    }

    func cleanupFailedAttempt(
        _ resources: GraphChatProviderSessionResources,
        requestProviderCancellation: Bool
    ) async {
        await resources.lifecycle.cleanupFailedAttempt(
            provider: provider,
            resources: resources,
            requestProviderCancellation: requestProviderCancellation
        )
    }

    func finishCommittedAttempt(
        _ resources: GraphChatProviderSessionResources,
        requestID: UUID
    ) async {
        await resources.lifecycle.finishCommittedAttempt(
            evidenceRegistry: resources.evidenceRegistry,
            primaryResultLedger: resources.primaryResultLedger,
            requestID: requestID
        )
    }

    func budgetPolicy(
        for purpose: GraphChatProviderSessionPurpose
    ) -> GraphChatToolBudgetPolicy {
        switch purpose {
        case .standard:
            return standardToolBudgetPolicy
        case .recovery:
            return GraphChatToolBudgetPolicy(
                maximumCalls: min(standardToolBudgetPolicy.maximumCalls, 3),
                maximumResultCountPerTool: min(
                    standardToolBudgetPolicy.maximumResultCountPerTool,
                    12
                ),
                maximumEvidenceCount: min(
                    standardToolBudgetPolicy.maximumEvidenceCount,
                    40
                )
            )
        }
    }

    private func recoveryBudgetPolicy(
        carriesPendingRepair: Bool
    ) -> GraphChatToolBudgetPolicy {
        let recoveryPolicy = budgetPolicy(for: .recovery)
        guard carriesPendingRepair else {
            return recoveryPolicy
        }
        return GraphChatToolBudgetPolicy(
            maximumCalls: recoveryPolicy.maximumCalls,
            maximumResultCountPerTool:
                standardToolBudgetPolicy.maximumResultCountPerTool,
            maximumEvidenceCount:
                standardToolBudgetPolicy.maximumEvidenceCount
        )
    }

    private func loadSchema(
        for key: GraphChatOrchestrationScopeKey
    ) async throws -> GraphSchemaContext {
        let availability = await provider.availability()
        guard availability.isAvailable else {
            throw errorMapper.availabilityError(availability)
        }
        let schemaContext: GraphSchemaContext
        do {
            try Task.checkCancellation()
            schemaContext = try await schemaProvider.makeSnapshot(
                in: key.graphScope,
                exampleFieldIDs: []
            )
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Das Schema des aktiven Graphen konnte nicht geladen werden.",
                recoverySuggestion:
                    "Öffne den Graphen erneut und versuche es noch einmal."
            )
        }
        guard schemaContext.graphScope == key.graphScope else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Das geladene Schema gehört nicht zum aktiven Graphen."
            )
        }
        return schemaContext
    }

    private func makeSession(
        purpose: GraphChatProviderSessionPurpose,
        key: GraphChatOrchestrationScopeKey,
        schemaContext: GraphSchemaContext,
        artifactSession: GraphChatArtifactSessionResources,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage,
        toolBudgetPolicy: GraphChatToolBudgetPolicy,
        recoveryCoordinator: GraphChatProviderRecoveryCoordinator,
        primaryResultLedger: GraphChatPrimaryResultLedger
    ) async throws -> GraphChatProviderSessionResources {
        try Task.checkCancellation()
        guard schemaContext.graphScope == key.graphScope else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Das geladene Schema gehört nicht zum aktiven Graphen."
            )
        }
        guard artifactSession.key == key else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Die Artifact-Session gehört nicht zum aktiven Graph-Chat-Scope."
            )
        }
        guard conversationBaseState.graphScope == key.graphScope,
              conversationBaseState.chatScope == key.chatScope,
              conversationContext.graphScope == key.graphScope,
              conversationContext.chatScope == key.chatScope else {
            throw GraphChatError(
                code: .invalidRequest,
                message:
                    "Conversation State und Provider-Kontext gehören nicht zum aktiven Graph-Chat-Scope."
            )
        }

        let toolBudget = GraphChatToolBudget(policy: toolBudgetPolicy)
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: key.chatScope)
        let presentationRegistry = GraphChatPresentationRegistry(
            schemaContext: schemaContext,
            conversationContext: conversationContext,
            language: responseLanguage
        )
        let artifactTransactionID = GraphChatAnswerArtifactTransactionID()
        let conversationTransaction = GraphChatConversationStateTransaction(
            baseState: conversationBaseState,
            reducer: conversationStateReducer
        )
        let lifecycle = GraphChatProviderAttemptLifecycle()
        let baseToolRunner = toolRunnerFactory.makeRunner(
            scope: key.chatScope,
            schemaContext: schemaContext,
            budget: toolBudget,
            evidenceRegistry: evidenceRegistry,
            presentationRegistry: presentationRegistry,
            artifactRegistry: artifactSession.registry,
            artifactTransactionID: artifactTransactionID,
            conversationTransaction: conversationTransaction,
            conversationContext: conversationContext,
            referenceResolver: referenceResolver,
            recoveryCoordinator: recoveryCoordinator,
            responseLanguage: responseLanguage,
            referenceDate: referenceDate(),
            calendar: calendar,
            timeZone: timeZone
        )
        let toolRunner = GraphChatPrimaryResultRecordingToolRunner(
            base: baseToolRunner,
            ledger: primaryResultLedger,
            graphScope: key.graphScope,
            artifactSessionID: artifactSession.sessionID,
            transactionID: artifactTransactionID,
            evidenceRegistry: evidenceRegistry,
            artifactRegistry: artifactSession.registry
        )

        let registeredKinds = await toolRunner.registeredToolKinds()
        let registeredIdentifiers = await toolRunner.registeredToolIdentifiers()
        let controlledIdentifiers = Set(
            Self.controlledToolKinds.map(\.rawValue)
        )
        guard registeredKinds == Self.controlledToolKinds,
              registeredIdentifiers == controlledIdentifiers,
              registeredKinds.count == 6 else {
            await evidenceRegistry.removeAll()
            await artifactSession.registry.rollback(
                transactionID: artifactTransactionID
            )
            await primaryResultLedger.discard(
                transactionID: artifactTransactionID
            )
            throw controlledToolRegistrationError(for: purpose)
        }

        let configuration = GraphChatModelSessionConfiguration(
            graphScope: key.graphScope,
            chatScope: key.chatScope,
            schemaContext: schemaContext,
            instructions: requestBuilder.systemInstructions(
                for: key.chatScope,
                language: responseLanguage
            ),
            toolRunner: toolRunner
        )
        var createdSessionID: GraphChatModelSessionID?
        do {
            try Task.checkCancellation()
            let sessionID = try await provider.createSession(
                configuration: configuration
            )
            createdSessionID = sessionID
            try Task.checkCancellation()
            return GraphChatProviderSessionResources(
                key: key,
                sessionID: sessionID,
                schemaContext: schemaContext,
                toolBudget: toolBudget,
                evidenceRegistry: evidenceRegistry,
                presentationRegistry: presentationRegistry,
                artifactRegistry: artifactSession.registry,
                artifactSessionID: artifactSession.sessionID,
                artifactTransactionID: artifactTransactionID,
                primaryResultLedger: primaryResultLedger,
                conversationBaseState: conversationBaseState,
                conversationContext: conversationContext,
                responseLanguage: responseLanguage,
                conversationTransaction: conversationTransaction,
                recoveryCoordinator: recoveryCoordinator,
                toolRunner: toolRunner,
                lifecycle: lifecycle
            )
        } catch {
            if let createdSessionID {
                await provider.discardSession(sessionID: createdSessionID)
            }
            await evidenceRegistry.removeAll()
            await artifactSession.registry.rollback(
                transactionID: artifactTransactionID
            )
            await primaryResultLedger.discard(
                transactionID: artifactTransactionID
            )
            if error is CancellationError || Task.isCancelled {
                throw CancellationError()
            }
            switch purpose {
            case .standard:
                throw errorMapper.map(error)
            case .recovery:
                throw error
            }
        }
    }

    private func controlledToolRegistrationError(
        for purpose: GraphChatProviderSessionPurpose
    ) -> GraphChatError {
        let message: String
        switch purpose {
        case .standard:
            message =
                "Für den Graph-Chat sind nicht exakt die kontrollierten read-only Tools registriert."
        case .recovery:
            message =
                "Für den Context-Retry sind nicht exakt die kontrollierten read-only Tools registriert."
        }
        return GraphChatError(
            code: .invalidRequest,
            message: message
        )
    }
}
