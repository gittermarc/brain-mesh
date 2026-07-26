//
//  GraphChatProviderSessionResources.swift
//  BrainMesh
//
//  Request-scoped, value/model-free resources for one provider attempt.
//

import Foundation

nonisolated struct GraphChatArtifactSessionResources: Sendable {
    let key: GraphChatOrchestrationScopeKey
    let sessionID: GraphChatAnswerArtifactSessionID
    let registry: GraphChatAnswerArtifactRegistry
}

nonisolated struct GraphChatProviderSessionResources: Sendable {
    let key: GraphChatOrchestrationScopeKey
    let sessionID: GraphChatModelSessionID
    let schemaContext: GraphSchemaContext
    let toolBudget: GraphChatToolBudget
    let evidenceRegistry: GraphChatEvidenceRegistry
    let presentationRegistry: GraphChatPresentationRegistry
    let artifactRegistry: GraphChatAnswerArtifactRegistry
    let artifactSessionID: GraphChatAnswerArtifactSessionID
    let artifactTransactionID: GraphChatAnswerArtifactTransactionID
    let conversationBaseState: GraphChatConversationState
    let conversationContext: GraphChatConversationContextSnapshot
    let responseLanguage: GraphChatResponseLanguage
    let conversationTransaction: GraphChatConversationStateTransaction
    let toolRunner: any GraphChatModelToolRunning
    let lifecycle: GraphChatProviderAttemptLifecycle
}

nonisolated struct GraphChatProviderExecutionResult: Sendable {
    let finalAnswer: GraphChatProviderFinalAnswer
    let resources: GraphChatProviderSessionResources
    let request: GraphChatModelRequest
}

nonisolated struct GraphChatProviderAttemptLifecycleSnapshot: Hashable, Sendable {
    let providerCancellationRequested: Bool
    let providerStreamCompleted: Bool
    let evidenceCleaned: Bool
    let artifactRolledBack: Bool
    let sessionDiscarded: Bool
}

actor GraphChatProviderAttemptLifecycle {
    private var providerCancellationRequested = false
    private var providerCancellationTask: Task<Void, Never>?
    private var providerStreamCompleted = false
    private var evidenceCleaned = false
    private var artifactRolledBack = false
    private var sessionDiscarded = false

    func requestProviderCancellation(
        provider: any GraphChatModelProvider,
        sessionID: GraphChatModelSessionID
    ) async {
        guard providerStreamCompleted == false else {
            return
        }
        // Cancellation can arrive through the handler and the stream error path.
        // Both callers must await the same provider operation before cleanup.
        if let providerCancellationTask {
            await providerCancellationTask.value
            return
        }

        providerCancellationRequested = true
        let cancellationTask = Task {
            await provider.cancelGeneration(sessionID: sessionID)
        }
        providerCancellationTask = cancellationTask
        await cancellationTask.value
    }

    func completeProviderStream(
        provider: any GraphChatModelProvider,
        sessionID: GraphChatModelSessionID
    ) async {
        guard providerStreamCompleted == false else {
            return
        }
        providerStreamCompleted = true
        await discardProviderSessionIfNeeded(
            provider: provider,
            sessionID: sessionID
        )
    }

    func cleanupFailedAttempt(
        provider: any GraphChatModelProvider,
        resources: GraphChatProviderSessionResources,
        requestProviderCancellation: Bool
    ) async {
        if requestProviderCancellation {
            await self.requestProviderCancellation(
                provider: provider,
                sessionID: resources.sessionID
            )
        }
        await cleanEvidenceIfNeeded(resources.evidenceRegistry)
        await rollbackArtifactIfNeeded(
            registry: resources.artifactRegistry,
            transactionID: resources.artifactTransactionID
        )
        await discardProviderSessionIfNeeded(
            provider: provider,
            sessionID: resources.sessionID
        )
    }

    func finishCommittedAttempt(
        evidenceRegistry: GraphChatEvidenceRegistry
    ) async {
        await cleanEvidenceIfNeeded(evidenceRegistry)
    }

    func snapshotForTesting() -> GraphChatProviderAttemptLifecycleSnapshot {
        GraphChatProviderAttemptLifecycleSnapshot(
            providerCancellationRequested: providerCancellationRequested,
            providerStreamCompleted: providerStreamCompleted,
            evidenceCleaned: evidenceCleaned,
            artifactRolledBack: artifactRolledBack,
            sessionDiscarded: sessionDiscarded
        )
    }

    private func cleanEvidenceIfNeeded(
        _ evidenceRegistry: GraphChatEvidenceRegistry
    ) async {
        guard evidenceCleaned == false else {
            return
        }
        evidenceCleaned = true
        await evidenceRegistry.removeAll()
    }

    private func rollbackArtifactIfNeeded(
        registry: GraphChatAnswerArtifactRegistry,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async {
        guard artifactRolledBack == false else {
            return
        }
        artifactRolledBack = true
        await registry.rollback(transactionID: transactionID)
    }

    private func discardProviderSessionIfNeeded(
        provider: any GraphChatModelProvider,
        sessionID: GraphChatModelSessionID
    ) async {
        guard sessionDiscarded == false else {
            return
        }
        sessionDiscarded = true
        await provider.discardSession(sessionID: sessionID)
    }
}
