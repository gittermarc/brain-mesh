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
    private let sessionDerivedStateDidClear: @MainActor () -> Void

    private lazy var generationController = GraphChatGenerationController(
        graphScope: graphScope,
        chatScope: chatScope,
        orchestrator: orchestrator,
        historyStore: historyStore,
        observability: observability,
        callbacks: GraphChatGenerationCallbacks(
            messageSnapshot: { [weak self] in
                self?.messages ?? []
            },
            operationWillCancel: { [weak self] _, assistantMessageID in
                self?.markAssistantCancelled(
                    messageID: assistantMessageID
                )
            },
            eventDidArrive: { [weak self] event, _, assistantMessageID in
                self?.apply(
                    event,
                    toAssistantMessageID: assistantMessageID
                )
            },
            completedTurnDidArrive: { [weak self] operationID, assistantMessageID in
                await self?.captureCommittedConversationCheckpoint(
                    for: assistantMessageID,
                    operationID: operationID
                )
            },
            generationStateDidChange: { [weak self] isGenerating in
                self?.updateVisibleGenerationState(isGenerating)
            }
        )
    )
    private var sessionMutationTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var presentationCleanupTask: Task<Void, Never>?
    private var visiblePresentationIDs: Set<UUID> = []
    private var activeSessionMutationID: UUID?
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
        generationStateDidChange: @escaping @MainActor (Bool) -> Void = { _ in },
        sessionDerivedStateDidClear: @escaping @MainActor () -> Void = {}
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
        self.sessionDerivedStateDidClear = sessionDerivedStateDidClear
    }

    deinit {
        sessionMutationTask?.cancel()
        feedbackTask?.cancel()
        noticeTask?.cancel()
        presentationCleanupTask?.cancel()
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
        generationController.isGenerating
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
            mode: .newTurn
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

    /// Multiple visible hosts can share this memory-only view model on iPad.
    func presentationDidAppear(_ presentationID: UUID) {
        presentationCleanupTask?.cancel()
        presentationCleanupTask = nil
        visiblePresentationIDs.insert(presentationID)
    }

    func presentationDidDisappear(_ presentationID: UUID) {
        guard visiblePresentationIDs.remove(presentationID) != nil else {
            return
        }
        guard visiblePresentationIDs.isEmpty else {
            return
        }

        presentationCleanupTask?.cancel()
        presentationCleanupTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  Task.isCancelled == false,
                  self.visiblePresentationIDs.isEmpty else {
                return
            }
            self.presentationCleanupTask = nil
            guard self.isGenerating else {
                return
            }
            self.cancelActiveSessionOperation(
                discardSession: false,
                showCancellationNotice: false
            )
        }
    }

    func viewDidDisappear() {
        presentationCleanupTask?.cancel()
        presentationCleanupTask = nil
        visiblePresentationIDs.removeAll()
        cancelActiveSessionOperation(
            discardSession: true,
            showCancellationNotice: false
        )
    }

    /// A new chat intentionally keeps the current graph and the exact current scope.
    /// Only session-derived messages, trusted conversation state, clarification, evidence,
    /// tool runtime state, feedback, and composer state are reset.
    private func startNewChat() {
        let hadActiveGeneration = generationController.isGenerating
        let generationCleanupTask = generationController.cancel(
            discardSession: false,
            persistMessageSnapshot: false
        )
        let previousMutationTask = sessionMutationTask
        previousMutationTask?.cancel()
        let previousFeedbackTask = feedbackTask
        previousFeedbackTask?.cancel()
        feedbackTask = nil
        let mutationID = UUID()
        activeSessionMutationID = mutationID
        isPerformingSessionMutation = true

        messages = []
        composerState.text = ""
        draftChangeHandler("")
        editingState = nil
        feedbackByMessageID = [:]
        committedConversationCheckpoint = nil
        scrollAnchorToken = UUID()
        sessionDerivedStateDidClear()

        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let feedbackStore = self.feedbackStore
        let chatScope = self.chatScope
        sessionMutationTask = Task { [weak self] in
            await previousMutationTask?.value
            if hadActiveGeneration {
                await generationCleanupTask?.value
            } else {
                await orchestrator.cancelCurrentGeneration()
            }
            await previousFeedbackTask?.value
            await orchestrator.discardSession(reason: .newConversation)
            await historyStore.removeMessages(for: chatScope)
            await feedbackStore.removeAll(for: chatScope)
            guard let self,
                  self.isActiveSessionMutation(mutationID) else {
                return
            }
            self.isPerformingSessionMutation = false
            self.finishSessionMutation(mutationID)
            self.showNotice(
                message: "Neuer Chat gestartet",
                systemImage: "plus.message"
            )
        }
    }

    func clearHistory() async {
        startNewChat()
        let task = sessionMutationTask
        await task?.value
    }

    @discardableResult
    func discardSensitiveState(
        preserveDraft: Bool = false
    ) -> [Task<Void, Never>] {
        let generationCleanupTask = generationController.cancel(
            discardSession: false,
            persistMessageSnapshot: false
        )
        sessionMutationTask?.cancel()
        feedbackTask?.cancel()
        let pendingLocalTasks = [
            generationCleanupTask,
            sessionMutationTask,
            feedbackTask,
        ].compactMap { $0 }
        activeSessionMutationID = nil
        sessionMutationTask = nil
        feedbackTask = nil
        noticeTask?.cancel()
        noticeTask = nil
        presentationCleanupTask?.cancel()
        presentationCleanupTask = nil
        visiblePresentationIDs.removeAll()
        actionNotice = nil
        composerState = GraphChatComposerState()
        isPerformingSessionMutation = false
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
        sessionDerivedStateDidClear()
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

    func resolveAnswerPresentation(
        for answer: GraphChatAnswer
    ) async -> GraphChatAnswerPresentationResolution {
        await orchestrator.resolveAnswerPresentation(
            artifactIDs: answer.artifactIDs
                + answer.sections.flatMap(\.artifactIDs),
            evidence: answer.evidence,
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    func canOpenArtifactTarget(
        _ target: GraphChatAnswerArtifactNavigationTarget
    ) -> Bool {
        currentAccessDecision.route == .ready
            && target.graphScope == graphScope
            && navigationActions.canOpenArtifactTarget(target)
    }

    func openArtifactTarget(
        _ target: GraphChatAnswerArtifactNavigationTarget
    ) {
        guard canOpenArtifactTarget(target) else {
            return
        }
        navigationActions.openArtifactTarget(target)
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
        mode: GraphChatGenerationMode
    ) {
        scrollAnchorToken = UUID()
        generationController.start(
            GraphChatGenerationRequest(
                question: question,
                assistantMessageID: assistantMessageID,
                mode: mode,
                usedIndexFallback: usedIndexFallback,
            )
        )
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

        isPerformingSessionMutation = true
        let previousFeedbackTask = feedbackTask
        let assistantID = UUID()
        let request = GraphChatGenerationRequest(
            question: plan.replacementQuestion,
            assistantMessageID: assistantID,
            mode: .branchReplacement,
            usedIndexFallback: decision.usesIndexFallback
        )
        generationController.start(request) { [weak self] operationID in
            guard let self else {
                return false
            }
            await previousFeedbackTask?.value
            guard Task.isCancelled == false,
                  self.generationController.isActive(operationID) else {
                return false
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
                return false
            }

            guard Task.isCancelled == false,
                  self.generationController.isActive(operationID),
                  self.currentAccessDecision.route == .ready else {
                self.handleBranchRestoreFailure(
                    GraphChatError(
                        code: .unavailable,
                        message: "Der aktive Graph-Chat-Kontext hat sich geändert."
                    ),
                    operationID: operationID
                )
                return false
            }

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
            self.feedbackByMessageID = self.feedbackByMessageID.filter {
                plan.removedMessageIDs.contains($0.key) == false
            }
            await self.feedbackStore.remove(
                messageIDs: plan.removedMessageIDs,
                for: self.chatScope
            )
            await self.historyStore.save(self.messages, for: self.chatScope)

            guard Task.isCancelled == false,
                  self.generationController.isActive(operationID) else {
                return false
            }
            self.isPerformingSessionMutation = false
            self.scrollAnchorToken = UUID()
            return true
        }
    }

    private func beginEditing(messageID: UUID) {
        guard let message = messages.first(where: { $0.id == messageID }),
              case .userQuestion(let question) = message.state,
              question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        let generationCleanupTask: Task<Void, Never>?
        if isGenerating {
            generationCleanupTask = generationController.cancel(
                discardSession: false
            )
        } else {
            generationCleanupTask = nil
        }
        editingState = GraphChatEditingState(
            userMessageID: messageID,
            originalQuestion: question
        )
        composerState.text = question
        draftChangeHandler(question)

        if let generationCleanupTask {
            beginGenerationCancellationMutation(
                awaiting: generationCleanupTask
            )
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
            guard generationController.activeAssistantMessageID == messageID,
                  generationController.activeMode?.isRegeneration == false,
                  decision.canCancelGeneration else {
                return
            }
        } else {
            guard decision.canStartGeneration,
                  isPerformingSessionMutation == false else {
                return
            }
        }

        let previousFeedbackTask = feedbackTask
        isPerformingSessionMutation = true
        let mode: GraphChatGenerationMode = isTechnicalRetry
            ? .technicalRetry
            : .regeneration
        let request = GraphChatGenerationRequest(
            question: plan.question,
            assistantMessageID: messageID,
            mode: mode,
            usedIndexFallback: decision.usesIndexFallback
        )
        generationController.start(request) { [weak self] operationID in
            guard let self else {
                return false
            }
            await previousFeedbackTask?.value
            guard Task.isCancelled == false,
                  self.generationController.isActive(operationID) else {
                return false
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
                return false
            }

            guard Task.isCancelled == false,
                  self.generationController.isActive(operationID),
                  self.currentAccessDecision.route == .ready else {
                self.handleBranchRestoreFailure(
                    GraphChatError(
                        code: .unavailable,
                        message: "Der aktive Graph-Chat-Kontext hat sich geändert."
                    ),
                    operationID: operationID
                )
                return false
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
                  self.generationController.isActive(operationID) else {
                return false
            }
            self.isPerformingSessionMutation = false
            self.scrollAnchorToken = UUID()
            return true
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
        let hadActiveGeneration = generationController.isGenerating
        let generationCleanupTask = generationController.cancel(
            discardSession: discardSession
        )
        let previousMutationTask = sessionMutationTask
        previousMutationTask?.cancel()
        let mutationID = UUID()
        activeSessionMutationID = mutationID
        isPerformingSessionMutation = true
        scrollAnchorToken = UUID()

        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let chatScope = self.chatScope
        let messageSnapshot = messages
        sessionMutationTask = Task { [weak self] in
            await previousMutationTask?.value
            if hadActiveGeneration {
                await generationCleanupTask?.value
            } else {
                await orchestrator.cancelCurrentGeneration()
                if discardSession {
                    await orchestrator.discardSession()
                }
                await historyStore.save(messageSnapshot, for: chatScope)
            }
            guard let self,
                  Task.isCancelled == false,
                  self.isActiveSessionMutation(mutationID) else {
                return
            }
            self.isPerformingSessionMutation = false
            self.finishSessionMutation(mutationID)
            if showCancellationNotice {
                self.showNotice(
                    message: "Antwort abgebrochen",
                    systemImage: "stop.circle"
                )
            }
        }
    }

    private func beginGenerationCancellationMutation(
        awaiting generationCleanupTask: Task<Void, Never>
    ) {
        let previousMutationTask = sessionMutationTask
        previousMutationTask?.cancel()
        let mutationID = UUID()
        activeSessionMutationID = mutationID
        isPerformingSessionMutation = true
        sessionMutationTask = Task { [weak self] in
            await previousMutationTask?.value
            await generationCleanupTask.value
            guard let self,
                  Task.isCancelled == false,
                  self.isActiveSessionMutation(mutationID) else {
                return
            }
            self.isPerformingSessionMutation = false
            self.finishSessionMutation(mutationID)
        }
    }

    private func markAssistantCancelled(messageID: UUID) {
        guard let index = messages.lastIndex(where: { message in
            guard case .assistant(let state) = message.state,
                  state.isTerminal == false else {
                return false
            }
            return message.id == messageID
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
        operationID: GraphChatGenerationOperationID
    ) async {
        guard let state = await orchestrator.conversationStateSnapshot(),
              Task.isCancelled == false,
              generationController.isActive(operationID),
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
        operationID: GraphChatGenerationOperationID
    ) {
        guard generationController.isActive(operationID) else {
            return
        }
        isPerformingSessionMutation = false
        showNotice(
            message: error.localizedDescription,
            systemImage: "exclamationmark.triangle"
        )
    }

    private func finishSessionMutation(_ mutationID: UUID) {
        guard activeSessionMutationID == mutationID else {
            return
        }
        activeSessionMutationID = nil
        sessionMutationTask = nil
    }

    private func isActiveSessionMutation(_ mutationID: UUID) -> Bool {
        activeSessionMutationID == mutationID
    }

    private func updateVisibleGenerationState(_ isGenerating: Bool) {
        guard composerState.isGenerating != isGenerating else {
            return
        }
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

}
