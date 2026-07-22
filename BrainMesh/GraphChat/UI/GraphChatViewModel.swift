//
//  GraphChatViewModel.swift
//  BrainMesh
//
//  Main-actor presentation logic for the internal graph chat UI.
//

import Combine
import Foundation

@MainActor
final class GraphChatViewModel: ObservableObject {
    @Published private(set) var messages: [GraphChatTranscriptMessage] = []
    @Published private(set) var composerState = GraphChatComposerState()
    @Published private(set) var availabilityState: GraphChatAvailabilityPresentationState = .loading
    @Published private(set) var indexState: GraphChatIndexPresentationState = .loading
    @Published private(set) var schemaSnapshot: GraphSchemaSnapshot?
    @Published private(set) var schemaErrorMessage: String?
    @Published private(set) var scrollAnchorToken = UUID()

    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let configuredGraphName: String

    private let orchestrator: any GraphChatOrchestrating
    private let schemaProvider: any GraphSchemaSnapshotProviding
    private let availabilityProvider: any GraphChatAvailabilityProviding
    private let indexStatusProvider: any GraphChatIndexStatusProviding
    private let historyStore: any GraphChatHistoryStoring
    private let navigationActions: GraphChatNavigationActions
    private let accessDecisionProvider: (@MainActor () -> GraphChatAccessDecision)?
    private let generationAccessProvider: @MainActor () -> Bool
    private let observability: any GraphChatObservabilityRecording
    private let draftChangeHandler: @MainActor (String) -> Void
    private let availabilityStateDidChange: @MainActor (GraphChatAvailabilityPresentationState) -> Void
    private let indexStateDidChange: @MainActor (GraphChatIndexPresentationState) -> Void
    private let generationStateDidChange: @MainActor (Bool) -> Void

    private var generationTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isLoadingSchema = false

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        graphName: String,
        orchestrator: any GraphChatOrchestrating,
        schemaProvider: any GraphSchemaSnapshotProviding,
        availabilityProvider: any GraphChatAvailabilityProviding,
        indexStatusProvider: any GraphChatIndexStatusProviding,
        historyStore: any GraphChatHistoryStoring,
        navigationActions: GraphChatNavigationActions,
        generationAccessProvider: @escaping @MainActor () -> Bool = { true },
        accessDecisionProvider: (@MainActor () -> GraphChatAccessDecision)? = nil,
        observability: any GraphChatObservabilityRecording = NoOpGraphChatObservabilityRecorder(),
        draftChangeHandler: @escaping @MainActor (String) -> Void = { _ in },
        availabilityStateDidChange: @escaping @MainActor (GraphChatAvailabilityPresentationState) -> Void = { _ in },
        indexStateDidChange: @escaping @MainActor (GraphChatIndexPresentationState) -> Void = { _ in },
        generationStateDidChange: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        precondition(
            graphScope == chatScope.graphScope,
            "GraphChatViewModel requires matching graph and chat scopes."
        )
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.configuredGraphName = graphName
        self.orchestrator = orchestrator
        self.schemaProvider = schemaProvider
        self.availabilityProvider = availabilityProvider
        self.indexStatusProvider = indexStatusProvider
        self.historyStore = historyStore
        self.navigationActions = navigationActions
        self.accessDecisionProvider = accessDecisionProvider
        self.generationAccessProvider = generationAccessProvider
        self.observability = observability
        self.draftChangeHandler = draftChangeHandler
        self.availabilityStateDidChange = availabilityStateDidChange
        self.indexStateDidChange = indexStateDidChange
        self.generationStateDidChange = generationStateDidChange
    }

    deinit {
        generationTask?.cancel()
    }

    var graphName: String {
        schemaSnapshot?.graphName ?? configuredGraphName
    }

    var scopeTitle: String {
        GraphChatScopePresentation.title(for: chatScope)
    }

    var isGenerating: Bool {
        composerState.isGenerating
    }

    var canSend: Bool {
        composerState.canSend && currentAccessDecision.canStartGeneration
    }

    var suggestions: [GraphChatEmptyStateSuggestion] {
        guard let schemaSnapshot else {
            return []
        }
        return GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: schemaSnapshot,
            scope: chatScope
        )
    }

    func load() async {
        if hasLoaded == false {
            hasLoaded = true
            messages = await historyStore.messages(for: chatScope)
            normalizeRestoredHistory()
        }

        await refreshRuntimeStates()

        guard schemaSnapshot == nil, isLoadingSchema == false else {
            return
        }
        isLoadingSchema = true
        defer {
            isLoadingSchema = false
        }

        do {
            let context = try await schemaProvider.makeSnapshot(
                in: graphScope,
                exampleFieldIDs: []
            )
            guard context.graphScope == graphScope else {
                throw GraphChatError(
                    code: .schemaUnavailable,
                    message: "Das geladene Schema gehört nicht zum aktiven Graphen."
                )
            }
            schemaSnapshot = context.snapshot
            schemaErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            schemaSnapshot = nil
            schemaErrorMessage = error.localizedDescription
        }
    }

    func refreshRuntimeStates() async {
        let availability = await availabilityProvider.availability()
        switch availability {
        case .available:
            availabilityState = .available
        case .unavailable(let reason):
            availabilityState = .unavailable(reason: reason)
        }
        availabilityStateDidChange(availabilityState)

        indexState = await indexStatusProvider.presentationState(for: graphScope)
        indexStateDidChange(indexState)
    }

    func setComposerText(_ text: String) {
        let bounded = String(text.prefix(4_000))
        composerState.text = bounded
        draftChangeHandler(bounded)
    }

    func notifyGenerationAccessChanged() {
        objectWillChange.send()
    }

    func applyPrefilledQuestion(_ question: String?) {
        guard isGenerating == false,
              composerState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let question = question?.trimmingCharacters(in: .whitespacesAndNewlines),
              question.isEmpty == false else {
            return
        }
        let bounded = String(question.prefix(4_000))
        composerState.text = bounded
        draftChangeHandler(bounded)
    }

    func useSuggestion(_ suggestion: GraphChatEmptyStateSuggestion) {
        guard isGenerating == false else {
            return
        }
        composerState.text = suggestion.prompt
        draftChangeHandler(suggestion.prompt)
    }

    func useFollowUp(_ suggestion: GraphChatFollowUpSuggestion) {
        guard isGenerating == false else {
            return
        }
        composerState.text = suggestion.prompt
        draftChangeHandler(suggestion.prompt)
    }

    func send() {
        let decision = currentAccessDecision
        guard decision.canStartGeneration,
              let question = composerState.submissionText() else {
            return
        }

        composerState.text = ""
        draftChangeHandler("")
        let assistantID = UUID()
        messages.append(
            GraphChatTranscriptMessage(
                state: .userQuestion(question)
            )
        )
        messages.append(
            GraphChatTranscriptMessage(
                id: assistantID,
                state: .assistant(
                    GraphChatAssistantMessageState(question: question)
                )
            )
        )
        startGeneration(
            question: question,
            assistantMessageID: assistantID,
            usedIndexFallback: decision.usesIndexFallback
        )
    }

    func retry(messageID: UUID) {
        let decision = currentAccessDecision
        guard decision.canStartGeneration,
              isGenerating == false,
              let index = messages.firstIndex(where: { $0.id == messageID }),
              case .assistant(let state) = messages[index].state,
              state.canRetry else {
            return
        }

        messages[index].state = .assistant(
            GraphChatAssistantMessageState(question: state.question)
        )
        startGeneration(
            question: state.question,
            assistantMessageID: messageID,
            usedIndexFallback: decision.usesIndexFallback
        )
    }

    func cancelGeneration() {
        cancelGeneration(discardSession: false)
    }

    func viewDidDisappear() {
        cancelGeneration(discardSession: true)
    }

    func clearHistory() async {
        generationTask?.cancel()
        generationTask = nil
        setGenerationState(false)
        await orchestrator.cancelCurrentGeneration()
        messages = []
        scrollAnchorToken = UUID()
        await historyStore.removeMessages(for: chatScope)
    }

    func discardSensitiveState(preserveDraft: Bool = false) {
        generationTask?.cancel()
        generationTask = nil
        composerState = GraphChatComposerState()
        generationStateDidChange(false)
        if preserveDraft == false {
            draftChangeHandler("")
        }
        messages = []
        schemaSnapshot = nil
        schemaErrorMessage = nil
        indexState = .loading
        scrollAnchorToken = UUID()
    }

    func openEntry(_ presentation: GraphChatEvidencePresentation) {
        guard presentation.canOpenEntry else {
            return
        }
        navigationActions.openEntry(presentation.sourceReference)
    }

    func showInGraph(_ presentation: GraphChatEvidencePresentation) {
        guard presentation.canShowInGraph else {
            return
        }
        navigationActions.showInGraph(presentation.sourceReference)
    }


    private var currentAccessDecision: GraphChatAccessDecision {
        guard let accessDecisionProvider else {
            return evaluatedAccessDecision(
                entitlement: generationAccessProvider() ? .pro : .free
            )
        }

        let externalDecision = accessDecisionProvider()
        guard externalDecision.route == .ready else {
            return externalDecision
        }

        let runtimeDecision = evaluatedAccessDecision(entitlement: .pro)
        guard runtimeDecision.route == .ready else {
            return runtimeDecision
        }

        return GraphChatAccessDecision(
            route: .ready,
            canPresentChat: externalDecision.canPresentChat
                && runtimeDecision.canPresentChat,
            canStartGeneration: externalDecision.canStartGeneration
                && runtimeDecision.canStartGeneration,
            canCancelGeneration: externalDecision.canCancelGeneration
                || runtimeDecision.canCancelGeneration,
            usesIndexFallback: externalDecision.usesIndexFallback
                || runtimeDecision.usesIndexFallback
        )
    }

    private func evaluatedAccessDecision(
        entitlement: GraphChatEntitlementAccessState
    ) -> GraphChatAccessDecision {
        GraphChatAccessPolicy.evaluate(
            GraphChatAccessPolicyInput(
                activeGraphID: graphScope.graphID,
                graphExists: true,
                requestedScope: chatScope,
                entitlement: entitlement,
                graphRequiresUnlock: false,
                isGraphUnlocked: true,
                availability: availabilityState,
                indexState: indexState,
                isReconciliationRunning: indexState.isReconciliationRunning,
                isGenerationRunning: isGenerating
            )
        )
    }

    private func startGeneration(
        question: String,
        assistantMessageID: UUID,
        usedIndexFallback: Bool
    ) {
        generationTask?.cancel()
        setGenerationState(true)
        scrollAnchorToken = UUID()

        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let graphScope = self.graphScope
        let chatScope = self.chatScope
        let observability = self.observability

        generationTask = Task { [weak self] in
            let timer = BMDuration()
            var toolCount = 0
            var toolKinds: Set<GraphChatToolKind> = []
            var terminalMetric: GraphChatRequestMetric?

            if let initialMessages = self?.messages {
                await historyStore.save(initialMessages, for: chatScope)
            }

            let stream = await orchestrator.streamAnswer(
                question: question,
                graphScope: graphScope,
                chatScope: chatScope
            )
            var receivedTerminalEvent = false

            for await event in stream {
                guard Task.isCancelled == false else {
                    break
                }
                guard let self else {
                    return
                }

                if case .toolActivity(let activity) = event,
                   activity.state == .started {
                    toolCount += 1
                    toolKinds.insert(activity.tool)
                }

                self.apply(
                    event,
                    toAssistantMessageID: assistantMessageID
                )
                receivedTerminalEvent = self.isTerminal(event)
                let messageSnapshot = self.messages
                await historyStore.save(messageSnapshot, for: chatScope)

                if receivedTerminalEvent {
                    terminalMetric = Self.metric(
                        for: event,
                        durationMilliseconds: timer.millisecondsElapsed,
                        toolCount: toolCount,
                        toolKinds: toolKinds,
                        usedIndexFallback: usedIndexFallback
                    )
                    break
                }
            }

            if Task.isCancelled {
                await observability.record(
                    .request(
                        GraphChatRequestMetric(
                            durationMilliseconds: timer.millisecondsElapsed,
                            toolCount: toolCount,
                            toolKinds: toolKinds,
                            evidenceCount: 0,
                            usedIndexFallback: usedIndexFallback,
                            outcome: .cancelled,
                            errorCode: .cancelled
                        )
                    )
                )
                return
            }
            guard let self else {
                return
            }

            if receivedTerminalEvent == false {
                let failure = GraphChatError(
                    code: .unexpected,
                    message: "Die Antwort wurde ohne Abschluss beendet.",
                    recoverySuggestion: "Versuche die Frage erneut."
                )
                self.apply(
                    .failure(failure),
                    toAssistantMessageID: assistantMessageID
                )
                await historyStore.save(self.messages, for: chatScope)
                terminalMetric = GraphChatRequestMetric(
                    durationMilliseconds: timer.millisecondsElapsed,
                    toolCount: toolCount,
                    toolKinds: toolKinds,
                    evidenceCount: 0,
                    usedIndexFallback: usedIndexFallback,
                    outcome: .failed,
                    errorCode: failure.code
                )
            }
            if let terminalMetric {
                await observability.record(.request(terminalMetric))
            }
            self.finishGeneration()
        }
    }

    private func apply(
        _ event: GraphChatStreamEvent,
        toAssistantMessageID messageID: UUID
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              case .assistant(var state) = messages[index].state else {
            return
        }

        state.apply(event)
        messages[index].state = .assistant(state)
        if case .failure(let failure) = event,
           failure.code == .modelUnavailable || failure.code == .unavailable {
            availabilityState = .unavailable(reason: .unknown)
            availabilityStateDidChange(availabilityState)
        }
        scrollAnchorToken = UUID()
    }

    private func finishGeneration() {
        setGenerationState(false)
        generationTask = nil
    }

    private func setGenerationState(_ isGenerating: Bool) {
        composerState.isGenerating = isGenerating
        generationStateDidChange(isGenerating)
    }

    private func cancelGeneration(discardSession: Bool) {
        let activeTask = generationTask
        generationTask = nil
        activeTask?.cancel()

        if let index = messages.lastIndex(where: { message in
            guard case .assistant(let state) = message.state else {
                return false
            }
            return state.isTerminal == false
        }), case .assistant(var state) = messages[index].state {
            state.markCancelled()
            messages[index].state = .assistant(state)
        }

        setGenerationState(false)
        scrollAnchorToken = UUID()

        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let chatScope = self.chatScope
        let messageSnapshot = messages
        Task {
            await orchestrator.cancelCurrentGeneration()
            if discardSession {
                await orchestrator.discardSession()
            }
            await historyStore.save(messageSnapshot, for: chatScope)
        }
    }

    private func normalizeRestoredHistory() {
        var changed = false
        for index in messages.indices {
            guard case .assistant(var state) = messages[index].state,
                  state.isTerminal == false else {
                continue
            }
            state.markCancelled()
            messages[index].state = .assistant(state)
            changed = true
        }

        guard changed else {
            return
        }
        let historyStore = self.historyStore
        let chatScope = self.chatScope
        let messageSnapshot = messages
        Task {
            await historyStore.save(messageSnapshot, for: chatScope)
        }
    }

    private func isTerminal(_ event: GraphChatStreamEvent) -> Bool {
        switch event {
        case .completed, .cancelled, .failure:
            return true
        case .started, .toolActivity, .partialAnswer:
            return false
        }
    }

    private nonisolated static func metric(
        for event: GraphChatStreamEvent,
        durationMilliseconds: Double,
        toolCount: Int,
        toolKinds: Set<GraphChatToolKind>,
        usedIndexFallback: Bool
    ) -> GraphChatRequestMetric? {
        switch event {
        case .completed(let answer):
            return GraphChatRequestMetric(
                durationMilliseconds: durationMilliseconds,
                toolCount: toolCount,
                toolKinds: toolKinds,
                evidenceCount: answer.evidence.count,
                usedIndexFallback: usedIndexFallback,
                outcome: answer.hasInsufficientEvidence && answer.evidence.isEmpty
                    ? .noResults
                    : .completed,
                errorCode: nil
            )
        case .cancelled:
            return GraphChatRequestMetric(
                durationMilliseconds: durationMilliseconds,
                toolCount: toolCount,
                toolKinds: toolKinds,
                evidenceCount: 0,
                usedIndexFallback: usedIndexFallback,
                outcome: .cancelled,
                errorCode: .cancelled
            )
        case .failure(let error):
            return GraphChatRequestMetric(
                durationMilliseconds: durationMilliseconds,
                toolCount: toolCount,
                toolKinds: toolKinds,
                evidenceCount: 0,
                usedIndexFallback: usedIndexFallback,
                outcome: error.code == .cancelled ? .cancelled : .failed,
                errorCode: error.code
            )
        case .started, .toolActivity, .partialAnswer:
            return nil
        }
    }
}
