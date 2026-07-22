//
//  GraphChatViewModel.swift
//  BrainMesh
//
//  Main-actor presentation and centralized message-action coordination.
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
    @Published private(set) var schemaContext: GraphSchemaContext?
    @Published private(set) var schemaErrorMessage: String?
    @Published private(set) var scrollAnchorToken = UUID()
    @Published private(set) var editingState: GraphChatEditingState?
    @Published private(set) var feedbackByMessageID: [UUID: GraphChatFeedbackCategory] = [:]
    @Published private(set) var actionNotice: GraphChatActionNotice?
    @Published private(set) var isPerformingSessionMutation = false

    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let configuredGraphName: String
    let launchContext: GraphChatLaunchContext
    let interfaceLanguage: GraphChatResponseLanguage
    let availableTools: Set<GraphChatToolKind>

    private let orchestrator: any GraphChatOrchestrating
    private let schemaProvider: any GraphSchemaSnapshotProviding
    private let availabilityProvider: any GraphChatAvailabilityProviding
    private let indexStatusProvider: any GraphChatIndexStatusProviding
    private let historyStore: any GraphChatHistoryStoring
    private let feedbackStore: any GraphChatFeedbackStoring
    private let clipboardWriter: any GraphChatClipboardWriting
    private let accessibilityAnnouncer: any GraphChatAccessibilityAnnouncing
    private let navigationActions: GraphChatNavigationActions
    private let accessDecisionProvider: (@MainActor () -> GraphChatAccessDecision)?
    private let generationAccessProvider: @MainActor () -> Bool
    private let observability: any GraphChatObservabilityRecording
    private let draftChangeHandler: @MainActor (String) -> Void
    private let availabilityStateDidChange: @MainActor (GraphChatAvailabilityPresentationState) -> Void
    private let indexStateDidChange: @MainActor (GraphChatIndexPresentationState) -> Void
    private let generationStateDidChange: @MainActor (Bool) -> Void

    private var sessionTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var activeOperationID: UUID?
    private var activeAssistantMessageID: UUID?
    private var activeGenerationIsRegeneration = false
    private var committedConversationCheckpoint: GraphChatConversationCheckpoint?
    private var hasLoaded = false
    private var isLoadingSchema = false

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        graphName: String,
        launchContext: GraphChatLaunchContext? = nil,
        interfaceLanguage: GraphChatResponseLanguage = GraphChatResponseLanguageSelector.systemFallback(),
        availableTools: Set<GraphChatToolKind> = Set(GraphChatToolKind.allCases),
        orchestrator: any GraphChatOrchestrating,
        schemaProvider: any GraphSchemaSnapshotProviding,
        availabilityProvider: any GraphChatAvailabilityProviding,
        indexStatusProvider: any GraphChatIndexStatusProviding,
        historyStore: any GraphChatHistoryStoring,
        feedbackStore: any GraphChatFeedbackStoring = InMemoryGraphChatFeedbackStore(),
        clipboardWriter: (any GraphChatClipboardWriting)? = nil,
        accessibilityAnnouncer: (any GraphChatAccessibilityAnnouncing)? = nil,
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
        self.launchContext = launchContext ?? .inferred(from: chatScope)
        self.interfaceLanguage = interfaceLanguage
        self.availableTools = availableTools
        self.orchestrator = orchestrator
        self.schemaProvider = schemaProvider
        self.availabilityProvider = availabilityProvider
        self.indexStatusProvider = indexStatusProvider
        self.historyStore = historyStore
        self.feedbackStore = feedbackStore
        self.clipboardWriter = clipboardWriter ?? SystemGraphChatClipboardWriter()
        self.accessibilityAnnouncer = accessibilityAnnouncer
            ?? SystemGraphChatAccessibilityAnnouncer()
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
        sessionTask?.cancel()
        feedbackTask?.cancel()
        noticeTask?.cancel()
    }

    var graphName: String {
        schemaSnapshot?.graphName ?? configuredGraphName
    }

    var scopePresentation: GraphChatScopePresentationModel {
        GraphChatScopePresentation.model(
            for: launchContext,
            scope: chatScope,
            language: interfaceLanguage
        )
    }

    var scopeTitle: String {
        scopePresentation.title
    }

    var isGenerating: Bool {
        composerState.isGenerating
    }

    var canSend: Bool {
        composerState.canSend
            && isPerformingSessionMutation == false
            && currentAccessDecision.canStartGeneration
    }

    var canStartNewChat: Bool {
        messages.isEmpty == false
            || composerState.normalizedText.isEmpty == false
            || editingState != nil
            || isGenerating
    }

    var suggestions: [GraphChatEmptyStateSuggestion] {
        guard let schemaContext else {
            return []
        }
        return GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: GraphChatSuggestionContext(
                schema: schemaContext,
                scope: chatScope,
                launchContext: launchContext,
                availableTools: availableTools,
                modelAvailability: availabilityState,
                language: interfaceLanguage
            )
        )
    }

    func load() async {
        var shouldRestoreConversationState = false
        if hasLoaded == false {
            hasLoaded = true
            messages = await historyStore.messages(for: chatScope)
            await normalizeRestoredHistory()
            await loadFeedback()
            shouldRestoreConversationState = true
        }

        await refreshRuntimeStates()
        if shouldRestoreConversationState {
            await restoreLatestCommittedConversationStateIfAvailable()
        }

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
            schemaContext = context
            schemaSnapshot = context.snapshot
            schemaErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            schemaContext = nil
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
              editingState == nil,
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
        guard isGenerating == false,
              isPerformingSessionMutation == false else {
            return
        }
        cancelEditing(clearComposer: false)
        composerState.text = suggestion.prompt
        draftChangeHandler(suggestion.prompt)
    }

    func useFollowUp(_ suggestion: GraphChatFollowUpSuggestion) {
        guard isGenerating == false,
              isPerformingSessionMutation == false else {
            return
        }
        cancelEditing(clearComposer: false)
        composerState.text = suggestion.prompt
        draftChangeHandler(suggestion.prompt)
    }

    func send() {
        if editingState != nil {
            submitEditedQuestion()
            return
        }

        let decision = currentAccessDecision
        guard decision.canStartGeneration,
              isPerformingSessionMutation == false,
              let question = composerState.submissionText() else {
            return
        }

        let checkpoint = checkpointBeforeNextTurn()
        composerState.text = ""
        draftChangeHandler("")
        let userMessage = GraphChatTranscriptMessage(
            state: .userQuestion(question),
            conversationCheckpointBeforeTurn: checkpoint
        )
        let assistantID = UUID()
        let assistantMessage = GraphChatTranscriptMessage(
            id: assistantID,
            state: .assistant(
                GraphChatAssistantMessageState(question: question)
            ),
            conversationCheckpointBeforeTurn: checkpoint
        )
        messages.append(userMessage)
        messages.append(assistantMessage)
        launchGeneration(
            question: question,
            assistantMessageID: assistantID,
            usedIndexFallback: decision.usesIndexFallback,
            isRegeneration: false
        )
    }

    func retry(messageID: UUID) {
        regenerate(messageID: messageID, allowsTechnicalState: true)
    }

    func performMessageAction(
        _ action: GraphChatMessageAction,
        messageID: UUID
    ) {
        performAction(action, messageID: messageID)
    }

    func performChatAction(_ action: GraphChatMessageAction) {
        performAction(action, messageID: nil)
    }

    private func performAction(
        _ action: GraphChatMessageAction,
        messageID: UUID?
    ) {
        switch action {
        case .startNewChat:
            startNewChat()
        case .copy:
            guard let messageID else {
                return
            }
            copyAssistantResponse(messageID: messageID)
        case .editAndResend:
            guard let messageID else {
                return
            }
            beginEditing(messageID: messageID)
        case .regenerate:
            guard let messageID else {
                return
            }
            regenerate(messageID: messageID, allowsTechnicalState: false)
        case .feedback(let category):
            guard let messageID else {
                return
            }
            setFeedback(category, for: messageID)
        case .removeFeedback:
            guard let messageID else {
                return
            }
            removeFeedback(for: messageID)
        }
    }

    func messageActionAvailability(
        for messageID: UUID
    ) -> GraphChatMessageActionAvailability {
        let availability = GraphChatMessageActionPolicy.availability(
            for: messageID,
            in: messages,
            isGenerating: isGenerating
        )
        guard isPerformingSessionMutation else {
            return availability
        }
        return GraphChatMessageActionAvailability(
            canCopy: availability.canCopy,
            canEditAndResend: false,
            canRegenerate: false,
            canGiveFeedback: false
        )
    }

    func feedbackCategory(
        for messageID: UUID
    ) -> GraphChatFeedbackCategory? {
        feedbackByMessageID[messageID]
    }

    func cancelEditing() {
        cancelEditing(clearComposer: true)
    }

    func cancelGeneration() {
        guard isGenerating || isPerformingSessionMutation else {
            return
        }
        cancelActiveSessionOperation(
            discardSession: false,
            showCancellationNotice: false
        )
    }

    func viewDidDisappear() {
        cancelActiveSessionOperation(
            discardSession: true,
            showCancellationNotice: false
        )
    }

    /// A new chat intentionally keeps the current graph and the exact current scope.
    /// Only session-derived messages, trusted conversation state, clarification, evidence,
    /// tool runtime state, feedback, and composer state are reset.
    private func startNewChat() {
        let previousTask = sessionTask
        previousTask?.cancel()
        let previousFeedbackTask = feedbackTask
        previousFeedbackTask?.cancel()
        feedbackTask = nil
        let operationID = UUID()
        activeOperationID = operationID
        activeAssistantMessageID = nil
        activeGenerationIsRegeneration = false
        setGenerationState(false)
        isPerformingSessionMutation = true

        messages = []
        composerState.text = ""
        draftChangeHandler("")
        editingState = nil
        feedbackByMessageID = [:]
        committedConversationCheckpoint = nil
        scrollAnchorToken = UUID()

        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let feedbackStore = self.feedbackStore
        let chatScope = self.chatScope
        sessionTask = Task { [weak self] in
            await orchestrator.cancelCurrentGeneration()
            await previousTask?.value
            await previousFeedbackTask?.value
            await orchestrator.discardSession(reason: .newConversation)
            await historyStore.removeMessages(for: chatScope)
            await feedbackStore.removeAll(for: chatScope)
            guard let self,
                  self.isActiveOperation(operationID) else {
                return
            }
            self.isPerformingSessionMutation = false
            self.finishOperation(operationID)
            self.showNotice(
                message: "Neuer Chat gestartet",
                systemImage: "plus.message"
            )
        }
    }

    func clearHistory() async {
        startNewChat()
        let task = sessionTask
        await task?.value
    }

    @discardableResult
    func discardSensitiveState(
        preserveDraft: Bool = false
    ) -> [Task<Void, Never>] {
        let pendingLocalTasks = [sessionTask, feedbackTask].compactMap { $0 }
        activeOperationID = nil
        activeAssistantMessageID = nil
        activeGenerationIsRegeneration = false
        pendingLocalTasks.forEach { $0.cancel() }
        sessionTask = nil
        feedbackTask = nil
        noticeTask?.cancel()
        noticeTask = nil
        actionNotice = nil
        composerState = GraphChatComposerState()
        isPerformingSessionMutation = false
        generationStateDidChange(false)
        if preserveDraft == false {
            draftChangeHandler("")
        }
        messages = []
        feedbackByMessageID = [:]
        editingState = nil
        committedConversationCheckpoint = nil
        schemaContext = nil
        schemaSnapshot = nil
        schemaErrorMessage = nil
        indexState = .loading
        scrollAnchorToken = UUID()
        return pendingLocalTasks
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

    private func launchGeneration(
        question: String,
        assistantMessageID: UUID,
        usedIndexFallback: Bool,
        isRegeneration: Bool
    ) {
        let previousTask = sessionTask
        previousTask?.cancel()
        let operationID = UUID()
        activeOperationID = operationID
        activeAssistantMessageID = assistantMessageID
        activeGenerationIsRegeneration = isRegeneration
        setGenerationState(true)
        scrollAnchorToken = UUID()

        sessionTask = Task { [weak self] in
            if let previousTask {
                await previousTask.value
            }
            guard let self,
                  Task.isCancelled == false,
                  self.isActiveOperation(operationID) else {
                return
            }
            await self.consumeGeneration(
                question: question,
                assistantMessageID: assistantMessageID,
                usedIndexFallback: usedIndexFallback,
                operationID: operationID
            )
        }
    }

    private func consumeGeneration(
        question: String,
        assistantMessageID: UUID,
        usedIndexFallback: Bool,
        operationID: UUID
    ) async {
        let timer = BMDuration()
        var toolCount = 0
        var toolKinds: Set<GraphChatToolKind> = []
        var terminalMetric: GraphChatRequestMetric?

        await historyStore.save(messages, for: chatScope)
        let stream = await orchestrator.streamAnswer(
            question: question,
            graphScope: graphScope,
            chatScope: chatScope
        )
        var receivedTerminalEvent = false

        for await event in stream {
            guard Task.isCancelled == false,
                  isActiveOperation(operationID),
                  activeAssistantMessageID == assistantMessageID else {
                break
            }

            if case .toolActivity(let activity) = event,
               activity.state == .started {
                toolCount += 1
                toolKinds.insert(activity.tool)
            }

            apply(
                event,
                toAssistantMessageID: assistantMessageID
            )

            if case .completed = event {
                await captureCommittedConversationCheckpoint(
                    for: assistantMessageID,
                    operationID: operationID
                )
            }

            receivedTerminalEvent = isTerminal(event)
            await historyStore.save(messages, for: chatScope)

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

        if Task.isCancelled || isActiveOperation(operationID) == false {
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

        if receivedTerminalEvent == false {
            let failure = GraphChatError(
                code: .unexpected,
                message: "Die Antwort wurde ohne Abschluss beendet.",
                recoverySuggestion: "Versuche die Frage erneut."
            )
            apply(
                .failure(failure),
                toAssistantMessageID: assistantMessageID
            )
            await historyStore.save(messages, for: chatScope)
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
        finishGeneration(operationID)
    }

    private func submitEditedQuestion() {
        let decision = currentAccessDecision
        guard decision.canStartGeneration,
              isPerformingSessionMutation == false,
              let editingState,
              let question = composerState.submissionText(),
              let plan = GraphChatMessageActionPlanner.editResendPlan(
                messages: messages,
                userMessageID: editingState.userMessageID,
                replacementQuestion: question,
                graphScope: graphScope,
                chatScope: chatScope
              ) else {
            return
        }

        let operationID = UUID()
        activeOperationID = operationID
        activeAssistantMessageID = nil
        activeGenerationIsRegeneration = false
        setGenerationState(true)
        isPerformingSessionMutation = true
        let previousTask = sessionTask
        previousTask?.cancel()
        let previousFeedbackTask = feedbackTask

        sessionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.orchestrator.cancelCurrentGeneration()
            await previousTask?.value
            await previousFeedbackTask?.value
            guard Task.isCancelled == false,
                  self.isActiveOperation(operationID) else {
                return
            }

            do {
                try await self.orchestrator.restoreConversationState(
                    from: plan.restoreCheckpoint
                )
            } catch {
                self.handleBranchRestoreFailure(
                    error,
                    operationID: operationID
                )
                return
            }

            guard Task.isCancelled == false,
                  self.isActiveOperation(operationID),
                  self.currentAccessDecision.route == .ready else {
                self.handleBranchRestoreFailure(
                    GraphChatError(
                        code: .unavailable,
                        message: "Der aktive Graph-Chat-Kontext hat sich geändert."
                    ),
                    operationID: operationID
                )
                return
            }

            let assistantID = UUID()
            let userMessage = GraphChatTranscriptMessage(
                state: .userQuestion(plan.replacementQuestion),
                conversationCheckpointBeforeTurn: plan.restoreCheckpoint
            )
            let assistantMessage = GraphChatTranscriptMessage(
                id: assistantID,
                state: .assistant(
                    GraphChatAssistantMessageState(
                        question: plan.replacementQuestion
                    )
                ),
                conversationCheckpointBeforeTurn: plan.restoreCheckpoint
            )

            self.messages = plan.retainedMessages + [userMessage, assistantMessage]
            self.committedConversationCheckpoint = plan.restoreCheckpoint
            self.composerState.text = ""
            self.draftChangeHandler("")
            self.editingState = nil
            self.activeAssistantMessageID = assistantID
            self.feedbackByMessageID = self.feedbackByMessageID.filter {
                plan.removedMessageIDs.contains($0.key) == false
            }
            await self.feedbackStore.remove(
                messageIDs: plan.removedMessageIDs,
                for: self.chatScope
            )
            await self.historyStore.save(self.messages, for: self.chatScope)

            guard Task.isCancelled == false,
                  self.isActiveOperation(operationID) else {
                return
            }
            self.isPerformingSessionMutation = false
            self.scrollAnchorToken = UUID()
            await self.consumeGeneration(
                question: plan.replacementQuestion,
                assistantMessageID: assistantID,
                usedIndexFallback: decision.usesIndexFallback,
                operationID: operationID
            )
        }
    }

    private func beginEditing(messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }),
              case .userQuestion(let question) = message.state,
              question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        editingState = GraphChatEditingState(
            userMessageID: messageID,
            originalQuestion: question
        )
        composerState.text = question
        draftChangeHandler(question)

        guard isGenerating else {
            return
        }

        let previousTask = sessionTask
        previousTask?.cancel()
        let operationID = UUID()
        activeOperationID = operationID
        activeGenerationIsRegeneration = false
        markActiveAssistantCancelled()
        activeAssistantMessageID = nil
        setGenerationState(false)
        isPerformingSessionMutation = true
        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let chatScope = self.chatScope
        let messageSnapshot = messages

        sessionTask = Task { [weak self] in
            await orchestrator.cancelCurrentGeneration()
            await previousTask?.value
            await historyStore.save(messageSnapshot, for: chatScope)
            guard let self,
                  Task.isCancelled == false,
                  self.isActiveOperation(operationID) else {
                return
            }
            self.isPerformingSessionMutation = false
            self.finishOperation(operationID)
        }
    }

    private func cancelEditing(clearComposer: Bool) {
        editingState = nil
        guard clearComposer else {
            return
        }
        composerState.text = ""
        draftChangeHandler("")
    }

    private func regenerate(
        messageID: UUID,
        allowsTechnicalState: Bool
    ) {
        guard let plan = GraphChatMessageActionPlanner.regenerationPlan(
            messages: messages,
            assistantMessageID: messageID,
            graphScope: graphScope,
            chatScope: chatScope
        ) else {
            return
        }

        guard let message = messages.first(where: { $0.id == messageID }),
              case .assistant(let state) = message.state else {
            return
        }
        let isTechnicalRetry = state.phase == .technicalError
        guard state.answer != nil || (allowsTechnicalState && isTechnicalRetry) || state.isTerminal == false else {
            return
        }

        let decision = currentAccessDecision
        if isGenerating {
            guard activeAssistantMessageID == messageID,
                  activeGenerationIsRegeneration == false,
                  decision.canCancelGeneration else {
                return
            }
        } else {
            guard decision.canStartGeneration,
                  isPerformingSessionMutation == false else {
                return
            }
        }

        let previousTask = sessionTask
        previousTask?.cancel()
        let previousFeedbackTask = feedbackTask
        let operationID = UUID()
        activeOperationID = operationID
        activeAssistantMessageID = messageID
        activeGenerationIsRegeneration = true
        setGenerationState(true)
        isPerformingSessionMutation = true

        sessionTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.orchestrator.cancelCurrentGeneration()
            await previousTask?.value
            await previousFeedbackTask?.value
            guard Task.isCancelled == false,
                  self.isActiveOperation(operationID) else {
                return
            }

            do {
                try await self.orchestrator.restoreConversationState(
                    from: plan.restoreCheckpoint
                )
            } catch {
                self.handleBranchRestoreFailure(
                    error,
                    operationID: operationID
                )
                return
            }

            guard Task.isCancelled == false,
                  self.isActiveOperation(operationID),
                  self.currentAccessDecision.route == .ready else {
                self.handleBranchRestoreFailure(
                    GraphChatError(
                        code: .unavailable,
                        message: "Der aktive Graph-Chat-Kontext hat sich geändert."
                    ),
                    operationID: operationID
                )
                return
            }

            let assistantMessage = GraphChatTranscriptMessage(
                id: plan.assistantMessageID,
                createdAt: plan.assistantCreatedAt,
                state: .assistant(
                    GraphChatAssistantMessageState(question: plan.question)
                ),
                conversationCheckpointBeforeTurn: plan.restoreCheckpoint
            )
            self.messages = plan.retainedMessages + [assistantMessage]
            self.committedConversationCheckpoint = plan.restoreCheckpoint
            self.feedbackByMessageID[plan.assistantMessageID] = nil
            await self.feedbackStore.remove(
                messageID: plan.assistantMessageID,
                for: self.chatScope
            )
            await self.historyStore.save(self.messages, for: self.chatScope)

            guard Task.isCancelled == false,
                  self.isActiveOperation(operationID) else {
                return
            }
            self.isPerformingSessionMutation = false
            self.scrollAnchorToken = UUID()
            await self.consumeGeneration(
                question: plan.question,
                assistantMessageID: plan.assistantMessageID,
                usedIndexFallback: decision.usesIndexFallback,
                operationID: operationID
            )
        }
    }

    private func copyAssistantResponse(messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }),
              case .assistant(let state) = message.state,
              let payload = GraphChatCopyContentBuilder.payload(for: state) else {
            return
        }
        clipboardWriter.write(payload.text)
        showNotice(
            message: "Antwort kopiert",
            systemImage: "doc.on.doc"
        )
    }

    private func setFeedback(
        _ category: GraphChatFeedbackCategory,
        for messageID: UUID
    ) {
        guard isPerformingSessionMutation == false,
              let message = messages.first(where: { $0.id == messageID }),
              case .assistant(let state) = message.state,
              let answerState = GraphChatMessageActionPolicy.feedbackAnswerState(for: state) else {
            return
        }

        if feedbackByMessageID[messageID] == category {
            removeFeedback(for: messageID)
            return
        }

        let record = GraphChatFeedbackRecord(
            localMessageID: messageID,
            category: category,
            answerState: answerState,
            scopeType: GraphChatFeedbackScopeType(scope: chatScope),
            toolCategories: state.toolActivities.map(\.tool)
        )
        feedbackByMessageID[messageID] = category
        let previousFeedbackTask = feedbackTask
        let feedbackStore = self.feedbackStore
        let chatScope = self.chatScope
        feedbackTask = Task {
            await previousFeedbackTask?.value
            guard Task.isCancelled == false else {
                return
            }
            await feedbackStore.save(record, for: chatScope)
        }
        showNotice(
            message: "Feedback gespeichert: \(category.title)",
            systemImage: "checkmark.circle"
        )
    }

    private func removeFeedback(for messageID: UUID) {
        guard isPerformingSessionMutation == false,
              feedbackByMessageID[messageID] != nil else {
            return
        }
        feedbackByMessageID[messageID] = nil
        let previousFeedbackTask = feedbackTask
        let feedbackStore = self.feedbackStore
        let chatScope = self.chatScope
        feedbackTask = Task {
            await previousFeedbackTask?.value
            guard Task.isCancelled == false else {
                return
            }
            await feedbackStore.remove(
                messageID: messageID,
                for: chatScope
            )
        }
        showNotice(
            message: "Feedback entfernt",
            systemImage: "xmark.circle"
        )
    }

    private func cancelActiveSessionOperation(
        discardSession: Bool,
        showCancellationNotice: Bool
    ) {
        let previousTask = sessionTask
        previousTask?.cancel()
        let operationID = UUID()
        activeOperationID = operationID
        activeGenerationIsRegeneration = false
        markActiveAssistantCancelled()
        activeAssistantMessageID = nil
        setGenerationState(false)
        isPerformingSessionMutation = true
        scrollAnchorToken = UUID()

        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let chatScope = self.chatScope
        let messageSnapshot = messages
        sessionTask = Task { [weak self] in
            await orchestrator.cancelCurrentGeneration()
            await previousTask?.value
            if discardSession {
                await orchestrator.discardSession()
            }
            await historyStore.save(messageSnapshot, for: chatScope)
            guard let self,
                  Task.isCancelled == false,
                  self.isActiveOperation(operationID) else {
                return
            }
            self.isPerformingSessionMutation = false
            self.finishOperation(operationID)
            if showCancellationNotice {
                self.showNotice(
                    message: "Antwort abgebrochen",
                    systemImage: "stop.circle"
                )
            }
        }
    }

    private func markActiveAssistantCancelled() {
        let targetID = activeAssistantMessageID
        guard let index = messages.lastIndex(where: { message in
            guard case .assistant(let state) = message.state,
                  state.isTerminal == false else {
                return false
            }
            return targetID == nil || message.id == targetID
        }), case .assistant(var state) = messages[index].state else {
            return
        }
        state.markCancelled()
        messages[index].state = .assistant(state)
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

    private func captureCommittedConversationCheckpoint(
        for messageID: UUID,
        operationID: UUID
    ) async {
        guard let state = await orchestrator.conversationStateSnapshot(),
              Task.isCancelled == false,
              isActiveOperation(operationID),
              state.graphScope == graphScope,
              state.chatScope == chatScope,
              let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return
        }
        let checkpoint = GraphChatConversationCheckpoint.committed(state)
        messages[index].conversationCheckpointAfterTurn = checkpoint
        committedConversationCheckpoint = checkpoint
    }

    private func checkpointBeforeNextTurn() -> GraphChatConversationCheckpoint {
        if let committedConversationCheckpoint,
           committedConversationCheckpoint.belongsTo(
            graphScope: graphScope,
            chatScope: chatScope
           ) {
            return committedConversationCheckpoint
        }
        return .initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    private func restoreLatestCommittedConversationStateIfAvailable() async {
        guard let checkpoint = messages.reversed().compactMap(
            \.conversationCheckpointAfterTurn
        ).first,
        checkpoint.belongsTo(
            graphScope: graphScope,
            chatScope: chatScope
        ) else {
            committedConversationCheckpoint = nil
            return
        }

        committedConversationCheckpoint = checkpoint
        guard currentAccessDecision.route == .ready else {
            return
        }

        do {
            try await orchestrator.restoreConversationState(from: checkpoint)
        } catch {
            await resetUnrestorableHistory(error: error)
        }
    }

    private func loadFeedback() async {
        let records = await feedbackStore.records(for: chatScope)
        let messageIDs = Set(messages.map(\.id))
        let staleMessageIDs = records.compactMap { record in
            messageIDs.contains(record.localMessageID) ? nil : record.localMessageID
        }
        if staleMessageIDs.isEmpty == false {
            await feedbackStore.remove(
                messageIDs: staleMessageIDs,
                for: chatScope
            )
        }
        feedbackByMessageID = Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                guard messageIDs.contains(record.localMessageID) else {
                    return nil
                }
                return (record.localMessageID, record.category)
            }
        )
    }

    private func resetUnrestorableHistory(error _: Error) async {
        messages = []
        feedbackByMessageID = [:]
        committedConversationCheckpoint = nil
        editingState = nil
        composerState.text = ""
        draftChangeHandler("")
        await orchestrator.discardSession(reason: .newConversation)
        await historyStore.removeMessages(for: chatScope)
        await feedbackStore.removeAll(for: chatScope)
        scrollAnchorToken = UUID()
        showNotice(
            message: "Der frühere Gesprächskontext konnte nicht sicher wiederhergestellt werden. Ein neuer Chat wurde gestartet.",
            systemImage: "arrow.clockwise.circle"
        )
    }

    private func handleBranchRestoreFailure(
        _ error: Error,
        operationID: UUID
    ) {
        guard isActiveOperation(operationID) else {
            return
        }
        isPerformingSessionMutation = false
        setGenerationState(false)
        activeAssistantMessageID = nil
        activeGenerationIsRegeneration = false
        finishOperation(operationID)
        showNotice(
            message: error.localizedDescription,
            systemImage: "exclamationmark.triangle"
        )
    }

    private func finishGeneration(_ operationID: UUID) {
        guard isActiveOperation(operationID) else {
            return
        }
        setGenerationState(false)
        activeAssistantMessageID = nil
        activeGenerationIsRegeneration = false
        isPerformingSessionMutation = false
        finishOperation(operationID)
    }

    private func finishOperation(_ operationID: UUID) {
        guard activeOperationID == operationID else {
            return
        }
        activeOperationID = nil
        sessionTask = nil
    }

    private func isActiveOperation(_ operationID: UUID) -> Bool {
        activeOperationID == operationID
    }

    private func setGenerationState(_ isGenerating: Bool) {
        composerState.isGenerating = isGenerating
        generationStateDidChange(isGenerating)
    }

    private func showNotice(
        message: String,
        systemImage: String
    ) {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedMessage.isEmpty == false else {
            return
        }
        noticeTask?.cancel()
        let notice = GraphChatActionNotice(
            message: String(normalizedMessage.prefix(240)),
            systemImage: systemImage
        )
        actionNotice = notice
        accessibilityAnnouncer.announce(notice.message)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard Task.isCancelled == false,
                  self?.actionNotice?.id == notice.id else {
                return
            }
            self?.actionNotice = nil
        }
    }

    private func normalizeRestoredHistory() async {
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
        await historyStore.save(messages, for: chatScope)
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
                outcome: {
                    if case .noResults = answer.state {
                        return .noResults
                    }
                    return .completed
                }(),
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
