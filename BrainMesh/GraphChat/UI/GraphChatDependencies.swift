//
//  GraphChatDependencies.swift
//  BrainMesh
//
//  Dependency boundaries for the graph chat presentation layer.
//

import Foundation

nonisolated protocol GraphChatOrchestrating: Sendable {
    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream

    func streamCorrectedIntent(
        _ request:
            GraphChatInterpretationCorrectionRequest
    ) async -> GraphChatEventStream

    func cancelCurrentGeneration() async
    func discardSession() async
    func discardSession(reason: GraphChatConversationResetReason) async
    func conversationStateSnapshot() async -> GraphChatConversationState?
    func restoreConversationState(
        from checkpoint: GraphChatConversationCheckpoint
    ) async throws
    func resolveAnswerPresentation(
        artifactIDs: [GraphChatAnswerArtifactID],
        evidence: [GraphEvidence],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatAnswerPresentationResolution
}

extension GraphChatOrchestrator: GraphChatOrchestrating {}

nonisolated extension GraphChatOrchestrating {
    func streamCorrectedIntent(
        _ request:
            GraphChatInterpretationCorrectionRequest
    ) async -> GraphChatEventStream {
        let pair =
            GraphChatEventStream.makeStream()
        let localizer =
            GraphChatResponseLocalizer(
                language:
                    request.binding
                        .originalInterpretation
                        .responseLanguage
            )
        pair.continuation.yield(
            .failure(
                GraphChatError(
                    code: .unavailable,
                    message:
                        localizer
                            .userFacingFailure(
                                .unavailable
                            )
                )
            )
        )
        pair.continuation.finish()
        return pair.stream
    }

    func discardSession(reason: GraphChatConversationResetReason) async {
        await discardSession()
    }

    func resolveAnswerPresentation(
        artifactIDs: [GraphChatAnswerArtifactID],
        evidence: [GraphEvidence],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatAnswerPresentationResolution {
        GraphChatAnswerPresentationResolution(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: nil,
            requestedArtifactIDs: artifactIDs,
            artifacts: [],
            evidence: evidence,
            defaultUnavailableReason: .sessionUnavailable
        )
    }
}

nonisolated protocol GraphChatAvailabilityProviding: Sendable {
    func availability() async -> GraphChatModelAvailability
}

nonisolated struct GraphChatModelAvailabilityAdapter: GraphChatAvailabilityProviding {
    let provider: any GraphChatModelProvider

    func availability() async -> GraphChatModelAvailability {
        await provider.availability()
    }
}

nonisolated protocol GraphChatIndexStatusProviding: Sendable {
    func presentationState(
        for scope: GraphScope
    ) async -> GraphChatIndexPresentationState

    func prepareIndex(
        for scope: GraphScope
    ) async -> GraphChatIndexPresentationState
}

nonisolated extension GraphChatIndexStatusProviding {
    func prepareIndex(
        for scope: GraphScope
    ) async -> GraphChatIndexPresentationState {
        await presentationState(for: scope)
    }
}

nonisolated struct LiveGraphChatIndexStatusProvider: GraphChatIndexStatusProviding {
    let indexer: GraphSearchIndexer
    let reconciler: GraphSearchIndexReconciler

    init(
        indexer: GraphSearchIndexer = .shared,
        reconciler: GraphSearchIndexReconciler = .shared
    ) {
        self.indexer = indexer
        self.reconciler = reconciler
    }

    func presentationState(
        for scope: GraphScope
    ) async -> GraphChatIndexPresentationState {
        let status = await indexer.status(for: scope)
        let readiness = await reconciler.readiness(for: scope)

        if readiness.state == .reconciling {
            return .reconciling(documentCount: readiness.documentCount)
        }

        switch status.state {
        case .notInitialized:
            return .notReady(documentCount: readiness.documentCount)
        case .building:
            return .building(
                processed: status.progress?.processedSources ?? 0,
                estimated: status.progress?.estimatedSources,
                documentCount: status.documentCount
            )
        case .ready:
            return .ready(documentCount: status.documentCount)
        case .stale:
            return .stale(documentCount: status.documentCount)
        case .failed:
            return .failed(
                message: status.failure?.message ?? "Der lokale Index ist nicht verfügbar.",
                isUsable: readiness.isIndexUsable,
                documentCount: status.documentCount ?? readiness.documentCount
            )
        }
    }

    func prepareIndex(
        for scope: GraphScope
    ) async -> GraphChatIndexPresentationState {
        _ = await reconciler.ensureReady(
            scope: scope,
            reason: .chatSession
        )
        return await presentationState(for: scope)
    }
}

nonisolated protocol GraphChatHistoryStoring: Sendable {
    func messages(for scope: GraphChatScope) async -> [GraphChatTranscriptMessage]
    func save(
        _ messages: [GraphChatTranscriptMessage],
        for scope: GraphChatScope
    ) async
    func removeMessages(for scope: GraphChatScope) async
}

actor InMemoryGraphChatHistoryStore: GraphChatHistoryStoring {
    static let maximumMessagesPerScope = 50

    private var messagesByScope: [GraphChatScope: [GraphChatTranscriptMessage]] = [:]

    func messages(for scope: GraphChatScope) -> [GraphChatTranscriptMessage] {
        messagesByScope[scope, default: []]
    }

    func save(
        _ messages: [GraphChatTranscriptMessage],
        for scope: GraphChatScope
    ) {
        messagesByScope[scope] = Array(
            messages.suffix(Self.maximumMessagesPerScope)
        )
    }

    func removeMessages(for scope: GraphChatScope) {
        messagesByScope.removeValue(forKey: scope)
    }
}

@MainActor
struct GraphChatNavigationActions {
    let openEntry: (GraphSourceReference) -> Void
    let showInGraph: (GraphSourceReference) -> Void
    let canOpenArtifactTarget: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    let openArtifactTarget: (GraphChatAnswerArtifactNavigationTarget) -> Void

    init(
        openEntry: @escaping (GraphSourceReference) -> Void,
        showInGraph: @escaping (GraphSourceReference) -> Void,
        canOpenArtifactTarget: @escaping (GraphChatAnswerArtifactNavigationTarget) -> Bool = { _ in false },
        openArtifactTarget: @escaping (GraphChatAnswerArtifactNavigationTarget) -> Void = { _ in }
    ) {
        self.openEntry = openEntry
        self.showInGraph = showInGraph
        self.canOpenArtifactTarget = canOpenArtifactTarget
        self.openArtifactTarget = openArtifactTarget
    }

    static let disabled = GraphChatNavigationActions(
        openEntry: { _ in },
        showInGraph: { _ in },
        canOpenArtifactTarget: { _ in false },
        openArtifactTarget: { _ in }
    )
}
