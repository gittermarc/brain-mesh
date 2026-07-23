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
    let discardReasons: [GraphChatConversationResetReason]
    let restoredCheckpoints: [GraphChatConversationCheckpoint]
    let conversationState: GraphChatConversationState?
}

actor GraphChatUIFakeOrchestrator: GraphChatOrchestrating {
    private var scripts: [GraphChatUIFakeScript]
    private var questions: [String] = []
    private var cancellationCount = 0
    private var discardCount = 0
    private var discardReasons: [GraphChatConversationResetReason] = []
    private var restoredCheckpoints: [GraphChatConversationCheckpoint] = []
    private var conversationState: GraphChatConversationState?
    private var activeTask: Task<Void, Never>?
    private let restoreDelayNanoseconds: UInt64

    init(
        scripts: [GraphChatUIFakeScript],
        restoreDelayNanoseconds: UInt64 = 0
    ) {
        self.scripts = scripts
        self.restoreDelayNanoseconds = restoreDelayNanoseconds
    }

    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream {
        questions.append(question)
        prepareConversationStateIfNeeded(
            graphScope: graphScope,
            chatScope: chatScope
        )
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
                var toolKinds: Set<GraphChatToolKind> = []
                for event in script.events {
                    try Task.checkCancellation()
                    if script.delayNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: script.delayNanoseconds)
                    }
                    if case .toolActivity(let activity) = event {
                        toolKinds.insert(activity.tool)
                    }
                    if case .completed(let answer) = event {
                        await self?.commitConversationTurn(
                            question: question,
                            answer: answer,
                            toolKinds: toolKinds
                        )
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

    func conversationStateSnapshot() async -> GraphChatConversationState? {
        conversationState
    }

    func restoreConversationState(
        from checkpoint: GraphChatConversationCheckpoint
    ) async throws {
        if restoreDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: restoreDelayNanoseconds)
        }
        guard checkpoint.belongsTo(
            graphScope: checkpoint.graphScope,
            chatScope: checkpoint.chatScope
        ) else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Invalid fake conversation checkpoint."
            )
        }
        await cancelCurrentGeneration()
        restoredCheckpoints.append(checkpoint)
        conversationState = checkpoint.state
            ?? .initial(
                graphScope: checkpoint.graphScope,
                chatScope: checkpoint.chatScope,
                resetReason: .newConversation
            )
    }

    func cancelCurrentGeneration() async {
        cancellationCount += 1
        let task = activeTask
        task?.cancel()
        await task?.value
    }

    func discardSession() async {
        discardCount += 1
        discardReasons.append(.sessionDiscarded)
        conversationState = nil
    }

    func discardSession(
        reason: GraphChatConversationResetReason
    ) async {
        discardCount += 1
        discardReasons.append(reason)
        conversationState = nil
    }

    func snapshot() -> GraphChatUIOrchestratorSnapshot {
        GraphChatUIOrchestratorSnapshot(
            questions: questions,
            cancellationCount: cancellationCount,
            discardCount: discardCount,
            discardReasons: discardReasons,
            restoredCheckpoints: restoredCheckpoints,
            conversationState: conversationState
        )
    }

    private func prepareConversationStateIfNeeded(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) {
        guard conversationState?.graphScope != graphScope
                || conversationState?.chatScope != chatScope else {
            return
        }
        conversationState = .initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    private func commitConversationTurn(
        question: String,
        answer: GraphChatAnswer,
        toolKinds: Set<GraphChatToolKind>
    ) {
        guard var state = conversationState else {
            return
        }
        let turnID = UUID()
        let completedAt = Date()
        state.turnContexts.append(
            GraphChatConversationTurnContext(
                id: turnID,
                completedAt: completedAt,
                toolKinds: toolKinds.sorted { $0.rawValue < $1.rawValue },
                resultContextIDs: [],
                evidenceIDs: answer.evidenceIDs,
                technicalDescription: "Validated fake turn for: \(question)"
            )
        )
        if case .clarification(let clarification) = answer.state {
            state.pendingClarification = GraphChatPendingClarification(
                id: clarification.id,
                decision: .conversationReference,
                options: clarification.options.map { option in
                    GraphChatPendingClarificationOption(
                        id: option.id,
                        title: option.title,
                        proposal: .alias(option.title)
                    )
                },
                sourceTurnID: turnID,
                graphScope: state.graphScope,
                chatScope: state.chatScope,
                continuationOperation: .answerAboutReference,
                continuationQuestion: clarification.question,
                createdAt: completedAt,
                expiresAt: completedAt.addingTimeInterval(300)
            )
        } else {
            state.pendingClarification = nil
        }
        if state.turnContexts.count > GraphChatConversationStatePolicy.default.maximumTurnContexts {
            state.turnContexts.removeFirst(
                state.turnContexts.count
                    - GraphChatConversationStatePolicy.default.maximumTurnContexts
            )
        }
        conversationState = state
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
    private(set) var openedReferences: [GraphSourceReference] = []
    private(set) var shownReferences: [GraphSourceReference] = []
    private(set) var openedArtifactTargets: [GraphChatAnswerArtifactNavigationTarget] = []
    private let allowsArtifactTargets: Bool

    init(allowsArtifactTargets: Bool = true) {
        self.allowsArtifactTargets = allowsArtifactTargets
    }

    func actions() -> GraphChatNavigationActions {
        GraphChatNavigationActions(
            openEntry: { [weak self] reference in
                self?.openedReferences.append(reference)
            },
            showInGraph: { [weak self] reference in
                self?.shownReferences.append(reference)
            },
            canOpenArtifactTarget: { [weak self] _ in
                self?.allowsArtifactTargets == true
            },
            openArtifactTarget: { [weak self] target in
                self?.openedArtifactTargets.append(target)
            }
        )
    }
}

@MainActor
final class GraphChatUITestClipboardWriter: GraphChatClipboardWriting {
    private(set) var values: [String] = []

    func write(_ text: String) {
        values.append(text)
    }
}

@MainActor
final class GraphChatUITestAccessibilityAnnouncer: GraphChatAccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
    }
}

nonisolated enum GraphChatUITestSupport {
    @MainActor
    static func makeViewModel(
        graphID: UUID = GraphChatTestSupport.graphID,
        chatScope: GraphChatScope? = nil,
        scripts: [GraphChatUIFakeScript],
        restoreDelayNanoseconds: UInt64 = 0,
        availability: GraphChatModelAvailability = .available,
        indexState: GraphChatIndexPresentationState = .ready(documentCount: 12),
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore(),
        feedbackStore: (any GraphChatFeedbackStoring)? = nil,
        clipboardWriter: GraphChatUITestClipboardWriter? = nil,
        accessibilityAnnouncer: GraphChatUITestAccessibilityAnnouncer? = nil,
        navigationActions: GraphChatNavigationActions = .disabled,
        accessDecisionProvider: (@MainActor () -> GraphChatAccessDecision)? = nil,
        schemaContext: GraphSchemaContext? = nil
    ) -> (
        viewModel: GraphChatViewModel,
        orchestrator: GraphChatUIFakeOrchestrator,
        feedbackStore: any GraphChatFeedbackStoring,
        clipboardWriter: GraphChatUITestClipboardWriter,
        accessibilityAnnouncer: GraphChatUITestAccessibilityAnnouncer
    ) {
        let graphScope = GraphScope(graphID: graphID)
        let resolvedChatScope = chatScope ?? .entireGraph(graphScope)
        let context = schemaContext ?? GraphChatTestSupport.makeSchemaContext(graphID: graphID)
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: scripts,
            restoreDelayNanoseconds: restoreDelayNanoseconds
        )
        let resolvedFeedbackStore = feedbackStore ?? InMemoryGraphChatFeedbackStore()
        let resolvedClipboardWriter = clipboardWriter ?? GraphChatUITestClipboardWriter()
        let resolvedAccessibilityAnnouncer = accessibilityAnnouncer
            ?? GraphChatUITestAccessibilityAnnouncer()
        let viewModel = GraphChatViewModel(
            graphScope: graphScope,
            chatScope: resolvedChatScope,
            graphName: context.snapshot.graphName,
            orchestrator: orchestrator,
            schemaProvider: GraphChatUIFakeSchemaProvider(contexts: [context]),
            availabilityProvider: GraphChatUIFakeAvailabilityProvider(value: availability),
            indexStatusProvider: GraphChatUIFakeIndexProvider(value: indexState),
            historyStore: historyStore,
            feedbackStore: resolvedFeedbackStore,
            clipboardWriter: resolvedClipboardWriter,
            accessibilityAnnouncer: resolvedAccessibilityAnnouncer,
            navigationActions: navigationActions,
            accessDecisionProvider: accessDecisionProvider
        )
        return (
            viewModel,
            orchestrator,
            resolvedFeedbackStore,
            resolvedClipboardWriter,
            resolvedAccessibilityAnnouncer
        )
    }

    static func finalAnswer(
        state: GraphChatAnswerState = .answer,
        directAnswer: String = "Final answer",
        evidence: [GraphEvidence] = [],
        filters: [GraphChatAppliedFilter] = [],
        followUps: [GraphChatFollowUpSuggestion] = [],
        insufficient: Bool = false
    ) -> GraphChatAnswer {
        GraphChatAnswer(
            state: state,
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
