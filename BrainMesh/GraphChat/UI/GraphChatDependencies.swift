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

    func cancelCurrentGeneration() async
    func discardSession() async
}

extension GraphChatOrchestrator: GraphChatOrchestrating {}

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

    init(
        openEntry: @escaping (GraphSourceReference) -> Void,
        showInGraph: @escaping (GraphSourceReference) -> Void
    ) {
        self.openEntry = openEntry
        self.showInGraph = showInGraph
    }

    static let disabled = GraphChatNavigationActions(
        openEntry: { _ in },
        showInGraph: { _ in }
    )
}
