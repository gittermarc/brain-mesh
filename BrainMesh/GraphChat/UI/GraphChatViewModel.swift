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
        navigationActions: GraphChatNavigationActions
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
        composerState.canSend && availabilityState.isAvailable
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

        indexState = await indexStatusProvider.presentationState(for: graphScope)
    }

    func setComposerText(_ text: String) {
        composerState.text = String(text.prefix(4_000))
    }

    func useSuggestion(_ suggestion: GraphChatEmptyStateSuggestion) {
        guard isGenerating == false else {
            return
        }
        composerState.text = suggestion.prompt
    }

    func useFollowUp(_ suggestion: GraphChatFollowUpSuggestion) {
        guard isGenerating == false else {
            return
        }
        composerState.text = suggestion.prompt
    }

    func send() {
        guard availabilityState.isAvailable,
              let question = composerState.submissionText() else {
            return
        }

        composerState.text = ""
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
            assistantMessageID: assistantID
        )
    }

    func retry(messageID: UUID) {
        guard isGenerating == false,
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
            assistantMessageID: messageID
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
        composerState.isGenerating = false
        await orchestrator.cancelCurrentGeneration()
        messages = []
        scrollAnchorToken = UUID()
        await historyStore.removeMessages(for: chatScope)
    }

    func openEntry(_ presentation: GraphChatEvidencePresentation) {
        guard let target = presentation.navigationTarget else {
            return
        }
        navigationActions.openEntry(target)
    }

    func showInGraph(_ presentation: GraphChatEvidencePresentation) {
        guard let target = presentation.navigationTarget else {
            return
        }
        navigationActions.showInGraph(target)
    }

    private func startGeneration(
        question: String,
        assistantMessageID: UUID
    ) {
        generationTask?.cancel()
        composerState.isGenerating = true
        scrollAnchorToken = UUID()

        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let graphScope = self.graphScope
        let chatScope = self.chatScope

        generationTask = Task { [weak self] in
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

                self.apply(
                    event,
                    toAssistantMessageID: assistantMessageID
                )
                receivedTerminalEvent = self.isTerminal(event)
                let messageSnapshot = self.messages
                await historyStore.save(messageSnapshot, for: chatScope)

                if receivedTerminalEvent {
                    break
                }
            }

            guard Task.isCancelled == false else {
                return
            }
            guard let self else {
                return
            }

            if receivedTerminalEvent == false {
                self.apply(
                    .failure(
                        GraphChatError(
                            code: .unexpected,
                            message: "Die Antwort wurde ohne Abschluss beendet.",
                            recoverySuggestion: "Versuche die Frage erneut."
                        )
                    ),
                    toAssistantMessageID: assistantMessageID
                )
                await historyStore.save(self.messages, for: chatScope)
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
        }
        scrollAnchorToken = UUID()

    }

    private func finishGeneration() {
        composerState.isGenerating = false
        generationTask = nil
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

        composerState.isGenerating = false
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
}
