import Foundation
@testable import BrainMesh

nonisolated struct GraphChatUIFakeScript: Sendable {
    let events: [GraphChatStreamEvent]
    let delayNanoseconds: UInt64
    let waitsForCancellation: Bool

    init(
        events: [GraphChatStreamEvent],
        delayNanoseconds: UInt64 = 0,
        waitsForCancellation: Bool = false
    ) {
        self.events = events
        self.delayNanoseconds = delayNanoseconds
        self.waitsForCancellation = waitsForCancellation
    }
}

nonisolated struct GraphChatUIOrchestratorSnapshot: Sendable {
    let questions: [String]
    let cancellationCount: Int
    let discardCount: Int
}

actor GraphChatUIFakeOrchestrator: GraphChatOrchestrating {
    private var scripts: [GraphChatUIFakeScript]
    private var questions: [String] = []
    private var cancellationCount = 0
    private var discardCount = 0
    private var activeTask: Task<Void, Never>?

    init(scripts: [GraphChatUIFakeScript]) {
        self.scripts = scripts
    }

    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream {
        questions.append(question)
        let script = scripts.isEmpty
            ? GraphChatUIFakeScript(
                events: [
                    .failure(
                        GraphChatError(
                            code: .unexpected,
                            message: "Missing fake UI script."
                        )
                    )
                ]
            )
            : scripts.removeFirst()
        let pair = GraphChatEventStream.makeStream()

        let task = Task { [weak self] in
            do {
                for event in script.events {
                    try Task.checkCancellation()
                    if script.delayNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: script.delayNanoseconds)
                    }
                    pair.continuation.yield(event)
                }
                if script.waitsForCancellation {
                    try await Task.sleep(nanoseconds: UInt64.max)
                }
                pair.continuation.finish()
            } catch is CancellationError {
                pair.continuation.yield(.cancelled)
                pair.continuation.finish()
            } catch {
                pair.continuation.yield(
                    .failure(
                        GraphChatError(
                            code: .unexpected,
                            message: error.localizedDescription
                        )
                    )
                )
                pair.continuation.finish()
            }
            await self?.clearActiveTask()
        }
        activeTask = task
        pair.continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return pair.stream
    }

    func cancelCurrentGeneration() async {
        cancellationCount += 1
        let task = activeTask
        task?.cancel()
        await task?.value
    }

    func discardSession() async {
        discardCount += 1
    }

    func snapshot() -> GraphChatUIOrchestratorSnapshot {
        GraphChatUIOrchestratorSnapshot(
            questions: questions,
            cancellationCount: cancellationCount,
            discardCount: discardCount
        )
    }

    private func clearActiveTask() {
        activeTask = nil
    }
}

actor GraphChatUIFakeSchemaProvider: GraphSchemaSnapshotProviding {
    private let contextsByGraphID: [UUID: GraphSchemaContext]
    private let error: GraphChatError?

    init(
        contexts: [GraphSchemaContext],
        error: GraphChatError? = nil
    ) {
        self.contextsByGraphID = Dictionary(
            uniqueKeysWithValues: contexts.map { ($0.graphScope.graphID, $0) }
        )
        self.error = error
    }

    func makeSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) async throws -> GraphSchemaContext {
        if let error {
            throw error
        }
        guard let context = contextsByGraphID[scope.graphID] else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Missing fake schema."
            )
        }
        return context
    }
}

nonisolated struct GraphChatUIFakeAvailabilityProvider: GraphChatAvailabilityProviding {
    let value: GraphChatModelAvailability

    func availability() async -> GraphChatModelAvailability {
        value
    }
}

nonisolated struct GraphChatUIFakeIndexProvider: GraphChatIndexStatusProviding {
    let value: GraphChatIndexPresentationState

    func presentationState(
        for scope: GraphScope
    ) async -> GraphChatIndexPresentationState {
        value
    }
}

@MainActor
final class GraphChatUINavigationRecorder {
    private(set) var openedTargets: [GraphSourceNavigationTarget] = []
    private(set) var shownTargets: [GraphSourceNavigationTarget] = []

    func actions() -> GraphChatNavigationActions {
        GraphChatNavigationActions(
            openEntry: { [weak self] target in
                self?.openedTargets.append(target)
            },
            showInGraph: { [weak self] target in
                self?.shownTargets.append(target)
            }
        )
    }
}

nonisolated enum GraphChatUITestSupport {
    @MainActor
    static func makeViewModel(
        graphID: UUID = GraphChatTestSupport.graphID,
        chatScope: GraphChatScope? = nil,
        scripts: [GraphChatUIFakeScript],
        availability: GraphChatModelAvailability = .available,
        indexState: GraphChatIndexPresentationState = .ready(documentCount: 12),
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore(),
        navigationActions: GraphChatNavigationActions = .disabled,
        schemaContext: GraphSchemaContext? = nil
    ) -> (
        viewModel: GraphChatViewModel,
        orchestrator: GraphChatUIFakeOrchestrator
    ) {
        let graphScope = GraphScope(graphID: graphID)
        let resolvedChatScope = chatScope ?? .entireGraph(graphScope)
        let context = schemaContext ?? GraphChatTestSupport.makeSchemaContext(graphID: graphID)
        let orchestrator = GraphChatUIFakeOrchestrator(scripts: scripts)
        let viewModel = GraphChatViewModel(
            graphScope: graphScope,
            chatScope: resolvedChatScope,
            graphName: context.snapshot.graphName,
            orchestrator: orchestrator,
            schemaProvider: GraphChatUIFakeSchemaProvider(contexts: [context]),
            availabilityProvider: GraphChatUIFakeAvailabilityProvider(value: availability),
            indexStatusProvider: GraphChatUIFakeIndexProvider(value: indexState),
            historyStore: historyStore,
            navigationActions: navigationActions
        )
        return (viewModel, orchestrator)
    }

    static func finalAnswer(
        directAnswer: String = "Final answer",
        evidence: [GraphEvidence] = [],
        filters: [GraphChatAppliedFilter] = [],
        followUps: [GraphChatFollowUpSuggestion] = [],
        insufficient: Bool = false
    ) -> GraphChatAnswer {
        GraphChatAnswer(
            directAnswer: directAnswer,
            evidence: evidence,
            appliedFilters: filters,
            followUpSuggestions: followUps,
            hasInsufficientEvidence: insufficient
        )
    }

    @MainActor
    static func waitUntil(
        maximumYields: Int = 2_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<maximumYields {
            if condition() {
                return
            }
            await Task.yield()
        }
    }
}
