//
//  GraphChatViewModel.swift
//  BrainMesh
//
//  Main-actor presentation owner for graph-chat UI state and public actions.
//

import Combine
import Foundation

@MainActor
final class GraphChatViewModel: ObservableObject {
    @Published private(set) var availabilityState: GraphChatAvailabilityPresentationState = .loading
    @Published private(set) var indexState: GraphChatIndexPresentationState = .loading
    @Published private(set) var schemaSnapshot: GraphSchemaSnapshot?
    @Published private(set) var schemaContext: GraphSchemaContext?
    @Published private(set) var suggestionsSnapshot:
        GraphChatSuggestionsSnapshot?
    @Published private(set) var isLoadingSuggestions = false
    @Published private(set) var isGenerating = false
    @Published private(set) var schemaErrorMessage: String?
    @Published private(set) var editingState: GraphChatEditingState?
    @Published private(set) var feedbackByMessageID: [UUID: GraphChatFeedbackCategory] = [:]
    @Published private(set) var actionNotice: GraphChatActionNotice?
    @Published private(set) var isPerformingSessionMutation = false
    @Published private(set) var composerFocusRequestID: UUID?
    @Published private(set) var correctionEditorSession:
        GraphChatInterpretationCorrectionEditorSession?

    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let configuredGraphName: String
    let launchContext: GraphChatLaunchContext
    let interfaceLanguage: GraphChatResponseLanguage
    let interfaceLocaleIdentifier: String
    let availableTools: Set<GraphChatToolKind>
    let composerController: GraphChatComposerController
    let transcriptController = GraphChatTranscriptController()

    var messages: [GraphChatTranscriptMessage] {
        transcriptController.messages
    }

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
    private let availabilityStateDidChange: @MainActor (GraphChatAvailabilityPresentationState) -> Void
    private let indexStateDidChange: @MainActor (GraphChatIndexPresentationState) -> Void
    private let generationStateDidChange: @MainActor (Bool) -> Void
    private let sessionDerivedStateDidClear: @MainActor () -> Void
    private let checkpointController: GraphChatConversationCheckpointController
    private let suggestionsSnapshotController:
        GraphChatSuggestionsSnapshotController

    private lazy var generationController: GraphChatGenerationController = GraphChatGenerationController(
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
            publicationDidArrive: { [weak self] publication, _, assistantMessageID in
                self?.apply(
                    publication,
                    toAssistantMessageID: assistantMessageID
                )
            },
            completedTurnDidArrive: { [weak self] operationID, assistantMessageID in
                guard let self,
                      let state = await self.orchestrator.conversationStateSnapshot(),
                      Task.isCancelled == false,
                      self.generationController.isActive(operationID),
                      let checkpoint = self.checkpointController.captureCommittedCheckpoint(
                        state: state,
                        outcome: .completed
                      ) else {
                    return
                }
                self.transcriptController.setCheckpointAfterTurn(
                    checkpoint,
                    messageID: assistantMessageID
                )
            },
            generationStateDidChange: { [weak self] isGenerating in
                self?.updateVisibleGenerationState(isGenerating)
            }
        )
    )
    private lazy var messageActionController = GraphChatMessageActionController(
        graphScope: graphScope,
        chatScope: chatScope,
        orchestrator: orchestrator,
        historyStore: historyStore,
        feedbackStore: feedbackStore,
        clipboardWriter: clipboardWriter,
        observability: observability,
        checkpointController: checkpointController,
        generation: GraphChatMessageActionGenerationBridge(
            controller: generationController
        ),
        accessDecisionProvider: { [weak self] in
            self?.currentAccessDecision ?? .denied
        },
        resultHandler: { [weak self] result in
            self?.applyMessageActionResult(result)
        }
    )
    private var noticeTask: Task<Void, Never>?
    private var presentationCleanupTask: Task<Void, Never>?
    private var correctionEditorTask:
        Task<Void, Never>?
    private var correctionApplyTask:
        Task<Void, Never>?
    private var correctionExecutionWasSubmitted =
        false
    private var visiblePresentationIDs: Set<UUID> = []
    private var hasLoaded = false
    private var isLoadingSchema = false
    private var requestedSuggestionsKey:
        GraphChatSuggestionsSnapshotKey?
    private var suggestionsPublicationTask: Task<Void, Never>?

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        graphName: String,
        launchContext: GraphChatLaunchContext? = nil,
        interfaceLanguage: GraphChatResponseLanguage = GraphChatResponseLanguageSelector.systemFallback(),
        interfaceLocaleIdentifier: String = Locale.current.identifier,
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
        sessionDerivedStateDidClear: @escaping @MainActor () -> Void = {},
        suggestionsSnapshotBuilder:
            any GraphChatSuggestionsSnapshotBuilding =
                GraphChatProductionSuggestionsSnapshotBuilder()
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
        self.interfaceLocaleIdentifier = interfaceLocaleIdentifier
        self.availableTools = availableTools
        self.composerController = GraphChatComposerController(
            checkpointHandler: draftChangeHandler
        )
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
        self.availabilityStateDidChange = availabilityStateDidChange
        self.indexStateDidChange = indexStateDidChange
        self.generationStateDidChange = generationStateDidChange
        self.sessionDerivedStateDidClear = sessionDerivedStateDidClear
        self.checkpointController = GraphChatConversationCheckpointController(
            graphScope: graphScope,
            chatScope: chatScope
        )
        self.suggestionsSnapshotController =
            GraphChatSuggestionsSnapshotController(
                builder: suggestionsSnapshotBuilder
            )
    }

    deinit {
        noticeTask?.cancel()
        presentationCleanupTask?.cancel()
        correctionEditorTask?.cancel()
        correctionApplyTask?.cancel()
        suggestionsPublicationTask?.cancel()
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

    var composerState: GraphChatComposerState {
        GraphChatComposerState(
            text: composerController.text,
            isGenerating: isGenerating
        )
    }

    var canSend: Bool {
        composerController.hasSubmissionText
            && isGenerating == false
            && isPerformingSessionMutation == false
            && correctionEditorSession == nil
            && currentAccessDecision.canStartGeneration
    }

    var canSubmitComposer: Bool {
        isGenerating == false
            && isPerformingSessionMutation == false
            && correctionEditorSession == nil
            && currentAccessDecision.canStartGeneration
    }

    var canStartNewChat: Bool {
        canStartNewChatFromPublishedState
            || (
                correctionEditorSession == nil
                && composerController.hasSubmissionText
            )
    }

    var canStartNewChatFromPublishedState: Bool {
        correctionEditorSession == nil
            && (
                messages.isEmpty == false
                    || editingState != nil
                    || isGenerating
            )
    }

    func recordInterpretationEvent(
        _ event:
            GraphChatIntentInterpretationLifecycleEvent
    ) {
        let observability = observability
        Task {
            await observability.record(
                .intentInterpretation(
                    GraphChatIntentInterpretationMetric(
                        event: event
                    )
                )
            )
        }
    }

    var suggestions: [GraphChatEmptyStateSuggestion] {
        suggestionsSnapshot?.suggestions ?? []
    }

    func load() async {
        var shouldRestoreConversationState = false
        if hasLoaded == false {
            hasLoaded = true
            let restoredMessages = await historyStore.messages(for: chatScope)
            transcriptController.replaceMessages(restoredMessages)
            await normalizeRestoredHistory()
            feedbackByMessageID = await messageActionController.loadFeedback(
                for: messages
            )
            shouldRestoreConversationState = true
        }

        await refreshRuntimeStates()
        if shouldRestoreConversationState {
            let restoreResult = await checkpointController.restoreLatestCommittedCheckpoint(
                from: messages,
                shouldRestoreRuntime: currentAccessDecision.route == .ready,
                restore: { [orchestrator] checkpoint in
                    try await orchestrator.restoreConversationState(
                        from: checkpoint
                    )
                },
                controlledReset: { [orchestrator, historyStore, feedbackStore, chatScope] in
                    await orchestrator.discardSession(
                        reason: .newConversation
                    )
                    await historyStore.removeMessages(for: chatScope)
                    await feedbackStore.removeAll(for: chatScope)
                }
            )
            if restoreResult == .controlledReset {
                applyControlledHistoryReset()
            }
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
            await refreshSuggestionsSnapshotIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            schemaContext = nil
            schemaSnapshot = nil
            schemaErrorMessage = error.localizedDescription
            invalidateSuggestionsSnapshot()
        }
    }

    func refreshSchemaAfterAuthoritativeChange() async {
        schemaContext = nil
        schemaSnapshot = nil
        schemaErrorMessage = nil
        invalidateSuggestionsSnapshot()
        await load()
    }

    func refreshRuntimeStates() async {
        let availability = await availabilityProvider.availability()
        let resolvedAvailability: GraphChatAvailabilityPresentationState
        switch availability {
        case .available:
            resolvedAvailability = .available
        case .unavailable(let reason):
            resolvedAvailability = .unavailable(reason: reason)
        }
        if availabilityState != resolvedAvailability {
            availabilityState = resolvedAvailability
            availabilityStateDidChange(resolvedAvailability)
        }
        if schemaContext != nil {
            await refreshSuggestionsSnapshotIfNeeded()
        }

        let resolvedIndexState = await indexStatusProvider
            .presentationState(for: graphScope)
        if indexState != resolvedIndexState {
            indexState = resolvedIndexState
            indexStateDidChange(resolvedIndexState)
        }
    }

    func refreshSuggestionsSnapshotIfNeeded() async {
        guard let schemaContext else {
            invalidateSuggestionsSnapshot()
            return
        }
        let context = GraphChatSuggestionContext(
            schema: schemaContext,
            scope: chatScope,
            launchContext: launchContext,
            availableTools: availableTools,
            modelAvailability: availabilityState,
            language: interfaceLanguage,
            localeIdentifier: interfaceLocaleIdentifier
        )
        let request = GraphChatSuggestionsSnapshotRequest(
            context: context
        )
        if suggestionsSnapshot?.key == request.key {
            if isLoadingSuggestions {
                isLoadingSuggestions = false
            }
            return
        }

        if requestedSuggestionsKey != request.key {
            requestedSuggestionsKey = request.key
            if suggestionsSnapshot != nil {
                suggestionsSnapshot = nil
            }
            if isLoadingSuggestions == false {
                isLoadingSuggestions = true
            }
        }

        do {
            let snapshot = try await suggestionsSnapshotController
                .snapshot(for: request)
            guard Task.isCancelled == false,
                  requestedSuggestionsKey == request.key else {
                return
            }
            if suggestionsSnapshot != snapshot {
                suggestionsSnapshot = snapshot
            }
            if isLoadingSuggestions {
                isLoadingSuggestions = false
            }
        } catch is CancellationError {
            guard requestedSuggestionsKey == request.key,
                  Task.isCancelled == false else {
                return
            }
            if isLoadingSuggestions {
                isLoadingSuggestions = false
            }
        } catch {
            guard requestedSuggestionsKey == request.key else {
                return
            }
            if isLoadingSuggestions {
                isLoadingSuggestions = false
            }
        }
    }

    private func scheduleSuggestionsSnapshotRefresh() {
        suggestionsPublicationTask?.cancel()
        if suggestionsSnapshot != nil {
            suggestionsSnapshot = nil
        }
        if schemaContext != nil,
           isLoadingSuggestions == false {
            isLoadingSuggestions = true
        }
        suggestionsPublicationTask = Task { @MainActor [weak self] in
            await self?.refreshSuggestionsSnapshotIfNeeded()
        }
    }

    private func invalidateSuggestionsSnapshot() {
        suggestionsPublicationTask?.cancel()
        suggestionsPublicationTask = nil
        suggestionsSnapshotController.cancel(
            clearCachedSnapshot: true
        )
        requestedSuggestionsKey = nil
        if suggestionsSnapshot != nil {
            suggestionsSnapshot = nil
        }
        if isLoadingSuggestions {
            isLoadingSuggestions = false
        }
    }

    func setComposerText(_ text: String) {
        composerController.updateFromUser(text)
    }

    func notifyGenerationAccessChanged() {
        objectWillChange.send()
        guard
            var session =
                correctionEditorSession,
            currentAccessDecision.route
                != .ready
        else {
            return
        }
        session.validationState =
            currentAccessDecision.route
                == .graphLocked
            ? .stale(.graphLocked)
            : .stale(.scopeChanged)
        session.isApplying = false
        correctionEditorSession =
            session
        correctionApplyTask?.cancel()
        correctionApplyTask = nil
        if correctionExecutionWasSubmitted {
            messageActionController
                .cancelInterpretationCorrection()
        }
        recordInterpretationEvent(
            .correctionStale
        )
    }

    func applyPrefilledQuestion(_ question: String?) {
        guard isGenerating == false,
              isPerformingSessionMutation == false,
              correctionEditorSession == nil,
              editingState == nil,
              composerController.normalizedText.isEmpty,
              let question = question?.trimmingCharacters(in: .whitespacesAndNewlines),
              question.isEmpty == false else {
            return
        }
        composerController.replaceText(
            question,
            checkpoint: true
        )
    }

    func useSuggestion(_ suggestion: GraphChatEmptyStateSuggestion) {
        useComposerPrompt(
            suggestion.prompt,
            requestsFocus: false
        )
    }

    func useBetaQuestion(
        _ selection: GraphChatBetaQuestionSelection
    ) {
        guard selection.submitsAutomatically == false else {
            return
        }
        useComposerPrompt(
            selection.composerText,
            requestsFocus: selection.requestsComposerFocus
        )
    }

    private func useComposerPrompt(
        _ prompt: String,
        requestsFocus: Bool
    ) {
        guard isGenerating == false,
              isPerformingSessionMutation == false,
              correctionEditorSession == nil else {
            return
        }
        cancelEditing(clearComposer: false)
        composerController.replaceText(
            prompt,
            checkpoint: true
        )
        if requestsFocus {
            composerFocusRequestID = UUID()
        }
    }

    func useFollowUp(_ suggestion: GraphChatFollowUpSuggestion) {
        guard isGenerating == false,
              isPerformingSessionMutation == false,
              correctionEditorSession == nil else {
            return
        }
        cancelEditing(clearComposer: false)
        composerController.replaceText(
            suggestion.prompt,
            checkpoint: true
        )
    }

    func send() {
        guard isPerformingSessionMutation == false,
              correctionEditorSession == nil else {
            return
        }
        if editingState != nil {
            guard let question = composerController.submissionText() else {
                return
            }
            composerController.checkpointLatest()
            messageActionController.submitEditedQuestion(
                snapshot: messageActionSnapshot,
                replacementQuestion: question
            )
            return
        }

        let decision = currentAccessDecision
        guard decision.canStartGeneration,
              let question = composerController.submissionText() else {
            return
        }

        composerController.checkpointLatest()
        let checkpoint = checkpointController.checkpointBeforeNextTurn()
        composerController.replaceText("", checkpoint: true)
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
        transcriptController.appendTurn(
            userMessage: userMessage,
            assistantMessage: assistantMessage
        )
        launchGeneration(
            question: question,
            assistantMessageID: assistantID,
            usedIndexFallback: decision.usesIndexFallback,
            mode: .newTurn
        )
    }

    func retry(messageID: UUID) {
        messageActionController.retry(
            messageID: messageID,
            snapshot: messageActionSnapshot
        )
    }

    func openInterpretationCorrection(
        messageID: UUID
    ) {
        guard
            correctionEditorSession == nil,
            correctionEditorTask == nil,
            correctionApplyTask == nil,
            isPerformingSessionMutation
                == false,
            currentAccessDecision.route
                == .ready,
            let plan =
                GraphChatInterpretationCorrectionPlanner
                    .plan(
                        messages: messages,
                        assistantMessageID:
                            messageID,
                        graphScope:
                            graphScope,
                        chatScope:
                            chatScope
                    ),
            let message =
                messages.first(
                    where: {
                        $0.id == messageID
                    }
                ),
            case .assistant(let state) =
                message.state,
            let answer = state.answer,
            let interpretation =
                answer.interpretation,
            let origin =
                interpretation
                    .correctionOrigin
        else {
            return
        }

        let schemaProvider =
            self.schemaProvider
        let orchestrator =
            self.orchestrator
        let graphScope =
            self.graphScope
        let chatScope =
            self.chatScope
        let language =
            interpretation
                .responseLanguage

        correctionEditorTask =
            Task { @MainActor [weak self] in
                do {
                    async let freshContext =
                        schemaProvider
                            .makeSnapshot(
                                in: graphScope,
                                exampleFieldIDs:
                                    []
                            )
                    async let resolution =
                        orchestrator
                            .resolveAnswerPresentation(
                                artifactIDs:
                                    answer
                                        .artifactIDs
                                    + answer
                                        .sections
                                        .flatMap(
                                            \.artifactIDs
                                        ),
                                evidence:
                                    answer.evidence,
                                graphScope:
                                    graphScope,
                                chatScope:
                                    chatScope
                            )
                    let (
                        context,
                        presentationResolution
                    ) = try await (
                        freshContext,
                        resolution
                    )
                    guard
                        let self,
                        Task.isCancelled
                            == false,
                        self
                            .correctionEditorSession
                            == nil,
                        self
                            .currentAccessDecision
                            .route
                            == .ready,
                        let currentPlan =
                            GraphChatInterpretationCorrectionPlanner
                                .plan(
                                    messages:
                                        self.messages,
                                    assistantMessageID:
                                        messageID,
                                    graphScope:
                                        graphScope,
                                    chatScope:
                                        chatScope
                                ),
                        currentPlan.binding
                            == plan.binding
                    else {
                        self?
                            .correctionEditorTask =
                            nil
                        return
                    }

                    let snapshot =
                        GraphChatInterpretationCorrectionSchemaBuilder()
                            .makeSnapshot(
                                context:
                                    context,
                                chatScope:
                                    chatScope,
                                language:
                                    language,
                                includeFullGraphRelationshipCatalog:
                                    interpretation
                                        .intentKind
                                        == .relationships
                            )
                    let capabilities =
                        GraphChatInterpretationCorrectionCapabilities
                            .derive(
                                from:
                                    interpretation
                            )
                    let selection =
                        snapshot
                            .initialSelection(
                                interpretation:
                                    interpretation,
                                origin:
                                    origin
                            )
                    let request =
                        GraphChatInterpretationCorrectionRequest(
                            binding:
                                plan.binding,
                            selection:
                                selection
                        )
                    let validationState:
                        GraphChatInterpretationCorrectionValidationState
                    if presentationResolution
                        .artifactSessionID
                        == origin
                            .artifactSessionID,
                       presentationResolution
                        .hasUnavailableArtifacts
                        == false
                    {
                        validationState =
                            snapshot
                                .validationState(
                                    for:
                                        request,
                                    currentArtifactSessionID:
                                        origin
                                            .artifactSessionID,
                                    currentCheckpoint:
                                        plan
                                            .binding
                                            .expectedCurrentCheckpoint,
                                    graphIsLocked:
                                        false
                                )
                    } else {
                        validationState =
                            .stale(
                                .artifactSessionChanged
                            )
                    }
                    self.correctionEditorSession =
                        GraphChatInterpretationCorrectionEditorSession(
                            assistantMessageID:
                                messageID,
                            branchPlan:
                                plan,
                            snapshot:
                                snapshot,
                            capabilities:
                                capabilities,
                            presentation:
                                self
                                    .correctionEditorPresentation(
                                        for:
                                            interpretation
                                    ),
                            selection:
                                selection,
                            validationState:
                                validationState
                        )
                    self
                        .correctionEditorTask =
                        nil
                    self
                        .correctionExecutionWasSubmitted =
                        false
                    self
                        .recordInterpretationEvent(
                            .correctionEditorOpened
                        )
                } catch is CancellationError {
                    self?
                        .correctionEditorTask =
                        nil
                } catch {
                    guard let self else {
                        return
                    }
                    self
                        .correctionEditorTask =
                        nil
                    self.showNotice(
                        message:
                            language
                                == .german
                            ? "Die Interpretation kann gerade nicht bearbeitet werden."
                            : "The interpretation cannot be edited right now.",
                        systemImage:
                            "exclamationmark.triangle"
                    )
                }
            }
    }

    func updateInterpretationCorrectionSelection(
        _ selection:
            GraphChatInterpretationCorrectionSelection
    ) {
        guard
            var session =
                correctionEditorSession,
            session.isApplying
                == false
        else {
            return
        }
        session.selection =
            selection
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding:
                    session
                        .branchPlan
                        .binding,
                selection:
                    selection
            )
        session.validationState =
            session.snapshot
                .validationState(
                    for: request,
                    currentArtifactSessionID:
                        session
                            .branchPlan
                            .binding
                            .artifactSessionID,
                    currentCheckpoint:
                        session
                            .branchPlan
                            .binding
                            .expectedCurrentCheckpoint,
                    graphIsLocked:
                        currentAccessDecision
                            .route
                            == .graphLocked
                )
        correctionEditorSession =
            session
    }

    func applyInterpretationCorrection(
        _ selection:
            GraphChatInterpretationCorrectionSelection
    ) {
        guard
            var session =
                correctionEditorSession,
            session.isApplying
                == false,
            correctionApplyTask == nil,
            currentAccessDecision.route
                == .ready
        else {
            return
        }
        session.selection =
            selection
        session.isApplying =
            true
        correctionEditorSession =
            session

        let schemaProvider =
            self.schemaProvider
        let orchestrator =
            self.orchestrator
        let graphScope =
            self.graphScope
        let chatScope =
            self.chatScope
        let assistantID =
            session.assistantMessageID
        let binding =
            session.branchPlan.binding
        let language =
            binding
                .originalInterpretation
                .responseLanguage

        correctionApplyTask =
            Task { @MainActor [weak self] in
                do {
                    async let freshContext =
                        schemaProvider
                            .makeSnapshot(
                                in: graphScope,
                                exampleFieldIDs:
                                    []
                            )
                    async let currentResolution =
                        orchestrator
                            .resolveAnswerPresentation(
                                artifactIDs:
                                    binding
                                        .artifactIDsToReplace,
                                evidence:
                                    [],
                                graphScope:
                                    graphScope,
                                chatScope:
                                    chatScope
                            )
                    let (
                        context,
                        resolution
                    ) = try await (
                        freshContext,
                        currentResolution
                    )
                    guard
                        let self,
                        Task.isCancelled
                            == false,
                        var currentSession =
                            self
                                .correctionEditorSession,
                        currentSession.id
                            == session.id,
                        let currentPlan =
                            GraphChatInterpretationCorrectionPlanner
                                .plan(
                                    messages:
                                        self.messages,
                                    assistantMessageID:
                                        assistantID,
                                    graphScope:
                                        graphScope,
                                    chatScope:
                                        chatScope
                                ),
                        currentPlan.binding
                            == binding
                    else {
                        self?
                            .markCorrectionStale(
                                .conversationChanged
                            )
                        return
                    }

                    let freshSnapshot =
                        GraphChatInterpretationCorrectionSchemaBuilder()
                            .makeSnapshot(
                                context:
                                    context,
                                chatScope:
                                    chatScope,
                                language:
                                    language,
                                graphIsLocked:
                                    self
                                        .currentAccessDecision
                                        .route
                                        == .graphLocked,
                                includeFullGraphRelationshipCatalog:
                                    binding
                                        .originalInterpretation
                                        .intentKind
                                        == .relationships
                            )
                    let request =
                        GraphChatInterpretationCorrectionRequest(
                            binding:
                                binding,
                            selection:
                                selection
                        )
                    let validationState:
                        GraphChatInterpretationCorrectionValidationState
                    if resolution
                        .artifactSessionID
                        != binding
                            .artifactSessionID
                        || resolution
                            .hasUnavailableArtifacts
                    {
                        validationState =
                            .stale(
                                .artifactSessionChanged
                            )
                    } else {
                        validationState =
                            freshSnapshot
                                .validationState(
                                    for:
                                        request,
                                    currentArtifactSessionID:
                                        binding
                                            .artifactSessionID,
                                    currentCheckpoint:
                                        currentPlan
                                            .binding
                                            .expectedCurrentCheckpoint,
                                    graphIsLocked:
                                        self
                                            .currentAccessDecision
                                            .route
                                            == .graphLocked
                                )
                    }
                    guard
                        validationState
                            == .ready
                    else {
                        currentSession
                            .validationState =
                            validationState
                        currentSession
                            .isApplying =
                            false
                        self
                            .correctionEditorSession =
                            currentSession
                        self
                            .correctionApplyTask =
                            nil
                        if case .stale =
                                validationState {
                            self
                                .recordInterpretationEvent(
                                    .correctionStale
                                )
                        }
                        return
                    }

                    self
                        .correctionApplyTask =
                        nil
                    self
                        .correctionExecutionWasSubmitted =
                        true
                    self
                        .messageActionController
                        .applyInterpretationCorrection(
                            request,
                            snapshot:
                                self
                                    .messageActionSnapshot
                        )
                } catch is CancellationError {
                    self?
                        .correctionApplyTask =
                        nil
                } catch {
                    self?
                        .markCorrectionStale(
                            .schemaChanged
                        )
                }
            }
    }

    func cancelInterpretationCorrection() {
        guard
            correctionEditorSession
                != nil
        else {
            correctionEditorTask?
                .cancel()
            correctionEditorTask =
                nil
            return
        }
        if correctionExecutionWasSubmitted {
            messageActionController
                .cancelInterpretationCorrection()
            return
        }
        recordInterpretationEvent(
            .correctionCancelled
        )
        correctionApplyTask?.cancel()
        correctionApplyTask = nil
        correctionEditorSession = nil
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
        messageActionController.perform(
            action,
            messageID: messageID,
            snapshot: messageActionSnapshot
        )
    }

    func messageActionAvailability(
        for messageID: UUID
    ) -> GraphChatMessageActionAvailability {
        // Availability does not depend on the draft. Keeping the local
        // composer text out of this body-time snapshot preserves the
        // transcript's Observation boundary while editing.
        let availabilitySnapshot = GraphChatMessageActionSnapshot(
            messages: messages,
            composerText: "",
            editingState: editingState,
            feedbackByMessageID: feedbackByMessageID,
            isPerformingSessionMutation:
                isPerformingSessionMutation
        )
        let availability =
            messageActionController.messageActionAvailability(
                for: messageID,
                snapshot: availabilitySnapshot
            )
        guard correctionEditorSession != nil else {
            return availability
        }
        return GraphChatMessageActionAvailability(
            canCopy:
                availability.canCopy,
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
        messageActionController.cancelGeneration(
            discardSession: false,
            showCancellationNotice: false
        )
    }

    /// Pauses chat-owned work while preserving the transcript and draft.
    /// The session remains reusable when any explicit host becomes visible.
    func suspendForVisibilityLoss() {
        composerController.checkpointLatest()
        presentationCleanupTask?.cancel()
        presentationCleanupTask = nil
        noticeTask?.cancel()
        noticeTask = nil
        cancelInterpretationCorrection()
        correctionEditorTask?.cancel()
        correctionEditorTask = nil
        correctionApplyTask?.cancel()
        correctionApplyTask = nil
        suggestionsPublicationTask?.cancel()
        suggestionsPublicationTask = nil
        suggestionsSnapshotController.cancel(
            clearCachedSnapshot: false
        )
        isLoadingSuggestions = false
        messageActionController.cancelGeneration(
            discardSession: false,
            showCancellationNotice: false
        )
    }

    func releaseTransientCapacityForMemoryPressure() {
        suspendForVisibilityLoss()
        suggestionsSnapshotController.cancel(
            clearCachedSnapshot: true
        )
        requestedSuggestionsKey = nil
        suggestionsSnapshot = nil
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
        composerController.checkpointLatest()

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
            self.messageActionController.cancelGeneration(
                discardSession: false,
                showCancellationNotice: false
            )
        }
    }

    func viewDidDisappear() {
        composerController.checkpointLatest()
        presentationCleanupTask?.cancel()
        presentationCleanupTask = nil
        visiblePresentationIDs.removeAll()
        cancelInterpretationCorrection()
        messageActionController.cancelGeneration(
            discardSession: true,
            showCancellationNotice: false
        )
    }

    func clearHistory() async {
        await messageActionController.clearHistory(
            snapshot: messageActionSnapshot
        )
    }

    @discardableResult
    func discardSensitiveState(
        preserveDraft: Bool = false
    ) -> [Task<Void, Never>] {
        let pendingLocalTasks = messageActionController.discardSensitiveState()
        noticeTask?.cancel()
        noticeTask = nil
        presentationCleanupTask?.cancel()
        presentationCleanupTask = nil
        correctionEditorTask?.cancel()
        correctionEditorTask = nil
        correctionApplyTask?.cancel()
        correctionApplyTask = nil
        correctionExecutionWasSubmitted =
            false
        correctionEditorSession = nil
        visiblePresentationIDs.removeAll()
        actionNotice = nil
        composerController.deactivate(
            preserveDraft: preserveDraft
        )
        suggestionsPublicationTask?.cancel()
        suggestionsPublicationTask = nil
        suggestionsSnapshotController.cancel(
            clearCachedSnapshot: true
        )
        requestedSuggestionsKey = nil
        suggestionsSnapshot = nil
        isLoadingSuggestions = false
        isGenerating = false
        isPerformingSessionMutation = false
        transcriptController.replaceMessages([])
        feedbackByMessageID = [:]
        editingState = nil
        schemaContext = nil
        schemaSnapshot = nil
        schemaErrorMessage = nil
        indexState = .loading
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
        generationController.start(
            GraphChatGenerationRequest(
                question: question,
                assistantMessageID: assistantMessageID,
                mode: mode,
                usedIndexFallback: usedIndexFallback,
            )
        )
    }

    private func cancelEditing(clearComposer: Bool) {
        editingState = nil
        guard clearComposer else {
            return
        }
        composerController.replaceText("", checkpoint: true)
    }

    private func markAssistantCancelled(messageID: UUID) {
        guard messages.lastIndex(where: { message in
            guard case .assistant(let state) = message.state,
                  state.isTerminal == false else {
                return false
            }
            return message.id == messageID
        }) != nil else {
            return
        }
        transcriptController.mutateAssistant(
            messageID: messageID,
            preferLastMatch: true
        ) { state in
            state.markCancelled()
        }
    }

    private func apply(
        _ publication: GraphChatStreamingUIPublication,
        toAssistantMessageID messageID: UUID
    ) {
        guard transcriptController.apply(
            publication,
            toAssistantMessageID: messageID
        ) else {
            return
        }
        let availabilityFailure = publication.events.first { event in
            guard case .failure(let failure) = event else {
                return false
            }
            return failure.code == .modelUnavailable
                || failure.code == .unavailable
        }
        if availabilityFailure != nil {
            let unavailableState:
                GraphChatAvailabilityPresentationState =
                    .unavailable(reason: .unknown)
            if availabilityState != unavailableState {
                availabilityState = unavailableState
                availabilityStateDidChange(unavailableState)
                scheduleSuggestionsSnapshotRefresh()
            }
        }
    }

    private var messageActionSnapshot: GraphChatMessageActionSnapshot {
        GraphChatMessageActionSnapshot(
            messages: messages,
            composerText: composerController.text,
            editingState: editingState,
            feedbackByMessageID: feedbackByMessageID,
            isPerformingSessionMutation: isPerformingSessionMutation
        )
    }

    private func applyMessageActionResult(
        _ result: GraphChatMessageActionControllerResult
    ) {
        switch result {
        case .notice(let notice):
            showNotice(notice)

        case .editingBegan(let editingState, let composerText):
            self.editingState = editingState
            composerController.replaceText(
                composerText,
                checkpoint: true
            )

        case .feedbackChanged(let feedbackByMessageID, let notice):
            self.feedbackByMessageID = feedbackByMessageID
            showNotice(notice)

        case .sessionMutationBegan:
            isPerformingSessionMutation = true
            transcriptController.requestConversationMutationScroll()

        case .branchCommitted(
            let messages,
            let feedbackByMessageID,
            let composerText,
            let clearsEditing
        ):
            transcriptController.replaceMessages(
                messages,
                scroll: .conversationMutation
            )
            self.feedbackByMessageID = feedbackByMessageID
            composerController.replaceText(
                composerText,
                checkpoint: true
            )
            if clearsEditing {
                editingState = nil
            }

        case .newChatBegan:
            transcriptController.replaceMessages(
                [],
                scroll: .conversationMutation
            )
            composerController.replaceText("", checkpoint: true)
            editingState = nil
            feedbackByMessageID = [:]
            isPerformingSessionMutation = true
            sessionDerivedStateDidClear()

        case .interpretationCorrectionCommitted:
            correctionApplyTask?.cancel()
            correctionApplyTask = nil
            correctionExecutionWasSubmitted =
                false
            correctionEditorSession = nil

        case .interpretationCorrectionFailed(
            let validationState,
            let notice
        ):
            correctionExecutionWasSubmitted =
                false
            if var session =
                    correctionEditorSession {
                session.isApplying =
                    false
                session.validationState =
                    validationState
                correctionEditorSession =
                    session
            }
            showNotice(notice)

        case .interpretationCorrectionCancelled:
            recordInterpretationEvent(
                .correctionCancelled
            )
            correctionExecutionWasSubmitted =
                false
            correctionEditorSession = nil

        case .sessionMutationFinished(let notice):
            isPerformingSessionMutation = false
            if let notice {
                showNotice(notice)
            }
        }
    }

    private func applyControlledHistoryReset() {
        transcriptController.replaceMessages(
            [],
            scroll: .conversationMutation
        )
        feedbackByMessageID = [:]
        editingState = nil
        composerController.replaceText("", checkpoint: true)
        sessionDerivedStateDidClear()
        showNotice(
            message: "Der frühere Gesprächskontext konnte nicht sicher wiederhergestellt werden. Ein neuer Chat wurde gestartet.",
            systemImage: "arrow.clockwise.circle"
        )
    }

    private func updateVisibleGenerationState(_ isGenerating: Bool) {
        guard self.isGenerating != isGenerating else {
            return
        }
        self.isGenerating = isGenerating
        generationStateDidChange(isGenerating)
    }

    private func showNotice(
        message: String,
        systemImage: String
    ) {
        showNotice(
            GraphChatActionNotice(
                message: message,
                systemImage: systemImage
            )
        )
    }

    private func showNotice(
        _ notice: GraphChatActionNotice
    ) {
        let normalizedMessage = notice.message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedMessage.isEmpty == false else {
            return
        }
        noticeTask?.cancel()
        let visibleNotice = GraphChatActionNotice(
            id: notice.id,
            message: String(normalizedMessage.prefix(240)),
            systemImage: notice.systemImage
        )
        actionNotice = visibleNotice
        accessibilityAnnouncer.announce(visibleNotice.message)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard Task.isCancelled == false,
                  self?.actionNotice?.id == visibleNotice.id else {
                return
            }
            self?.actionNotice = nil
        }
    }

    private func normalizeRestoredHistory() async {
        var normalizedMessages = messages
        var changed = false
        for index in normalizedMessages.indices {
            guard case .assistant(var state) = normalizedMessages[index].state,
                  state.isTerminal == false else {
                continue
            }
            state.markCancelled()
            normalizedMessages[index].state = .assistant(state)
            changed = true
        }

        guard changed else {
            return
        }
        transcriptController.replaceMessages(normalizedMessages)
        await historyStore.save(normalizedMessages, for: chatScope)
        await observability.record(
            .historySave(
                GraphChatHistorySaveMetric(
                    boundary: .recoveryNormalization
                )
            )
        )
    }

    private func correctionEditorPresentation(
        for interpretation:
            GraphChatIntentInterpretation
    ) -> GraphChatInterpretationCorrectionEditorPresentation {
        GraphChatInterpretationCorrectionEditorPresentation(
            entitySelectionIsOptional:
                interpretation.intentKind
                    == .findNodes,
            minimumFieldCount: 0,
            sourceResultDescription:
                interpretation.intentKind
                    == .narrowResultSet
                ? interpretation
                    .presentation
                    .title
                : nil
        )
    }

    private func markCorrectionStale(
        _ reason:
            GraphChatInterpretationCorrectionStaleReason
    ) {
        correctionApplyTask = nil
        correctionExecutionWasSubmitted =
            false
        guard
            var session =
                correctionEditorSession
        else {
            return
        }
        session.isApplying =
            false
        session.validationState =
            .stale(reason)
        correctionEditorSession =
            session
        recordInterpretationEvent(
            .correctionStale
        )
    }

}
