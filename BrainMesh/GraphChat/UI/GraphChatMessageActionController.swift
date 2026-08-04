//
//  GraphChatMessageActionController.swift
//  BrainMesh
//
//  Main-actor coordination for message actions, branch replacement, feedback,
//  technical retry, and new-chat session cleanup.
//

import Foundation

nonisolated struct GraphChatMessageActionSnapshot: Hashable, Sendable {
    let messages: [GraphChatTranscriptMessage]
    let composerText: String
    let editingState: GraphChatEditingState?
    let feedbackByMessageID: [UUID: GraphChatFeedbackCategory]
    let isPerformingSessionMutation: Bool
}

nonisolated enum GraphChatMessageActionControllerResult: Hashable, Sendable {
    case notice(GraphChatActionNotice)
    case editingBegan(
        editingState: GraphChatEditingState,
        composerText: String
    )
    case feedbackChanged(
        feedbackByMessageID: [UUID: GraphChatFeedbackCategory],
        notice: GraphChatActionNotice
    )
    case sessionMutationBegan
    case branchCommitted(
        messages: [GraphChatTranscriptMessage],
        feedbackByMessageID: [UUID: GraphChatFeedbackCategory],
        composerText: String,
        clearsEditing: Bool
    )
    case newChatBegan
    case interpretationCorrectionCommitted
    case interpretationCorrectionFailed(
        validationState:
            GraphChatInterpretationCorrectionValidationState,
        notice: GraphChatActionNotice
    )
    case interpretationCorrectionCancelled
    case sessionMutationFinished(notice: GraphChatActionNotice?)
}

@MainActor
struct GraphChatMessageActionGenerationBridge {
    typealias TurnStartPersistence = @MainActor () async -> Bool
    typealias Preparation = @MainActor (
        _ operationID: GraphChatGenerationOperationID,
        _ persistTurnStart: TurnStartPersistence
    ) async -> Bool

    private let isGeneratingValue: () -> Bool
    private let activeAssistantMessageIDValue: () -> UUID?
    private let activeModeValue: () -> GraphChatGenerationMode?
    private let startHandler: (
        _ request: GraphChatGenerationRequest,
        _ preparation: Preparation?
    ) -> GraphChatGenerationOperationID
    private let cancelHandler: (
        _ discardSession: Bool,
        _ persistMessageSnapshot: Bool
    ) -> Task<Void, Never>?
    private let isActiveHandler: (
        _ operationID: GraphChatGenerationOperationID
    ) -> Bool

    init(controller: GraphChatGenerationController) {
        self.isGeneratingValue = {
            controller.isGenerating
        }
        self.activeAssistantMessageIDValue = {
            controller.activeAssistantMessageID
        }
        self.activeModeValue = {
            controller.activeMode
        }
        self.startHandler = { request, preparation in
            controller.start(
                request,
                preparation: preparation
            )
        }
        self.cancelHandler = { discardSession, persistMessageSnapshot in
            controller.cancelRuntime(
                discardSession: discardSession,
                persistMessageSnapshot: persistMessageSnapshot
            )
        }
        self.isActiveHandler = { operationID in
            controller.isActive(operationID)
        }
    }

    var isGenerating: Bool {
        isGeneratingValue()
    }

    var activeAssistantMessageID: UUID? {
        activeAssistantMessageIDValue()
    }

    var activeMode: GraphChatGenerationMode? {
        activeModeValue()
    }

    @discardableResult
    func start(
        _ request: GraphChatGenerationRequest,
        preparation: Preparation? = nil
    ) -> GraphChatGenerationOperationID {
        startHandler(request, preparation)
    }

    func cancel(
        discardSession: Bool,
        persistMessageSnapshot: Bool = true
    ) -> Task<Void, Never>? {
        cancelHandler(
            discardSession,
            persistMessageSnapshot
        )
    }

    func isActive(
        _ operationID: GraphChatGenerationOperationID
    ) -> Bool {
        isActiveHandler(operationID)
    }
}

@MainActor
final class GraphChatMessageActionController {
    typealias AccessDecisionProvider = @MainActor () -> GraphChatAccessDecision
    typealias ResultHandler = @MainActor (
        _ result: GraphChatMessageActionControllerResult
    ) -> Void

    private let graphScope: GraphScope
    private let chatScope: GraphChatScope
    private let orchestrator: any GraphChatOrchestrating
    private let historyStore: any GraphChatHistoryStoring
    private let feedbackStore: any GraphChatFeedbackStoring
    private let clipboardWriter: any GraphChatClipboardWriting
    private let observability: any GraphChatObservabilityRecording
    private let checkpointController: GraphChatConversationCheckpointController
    private let generation: GraphChatMessageActionGenerationBridge
    private let accessDecisionProvider: AccessDecisionProvider
    private let resultHandler: ResultHandler

    private var sessionMutationTask: Task<Void, Never>?
    private var interpretationCorrectionCancellationTask:
        Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var activeSessionMutationID: UUID?
    private var activeInterpretationCorrectionID: UUID?
    private var activeInterpretationCorrectionStreamID:
        UUID?
    private var activeInterpretationCorrectionCancellationID:
        UUID?

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        orchestrator: any GraphChatOrchestrating,
        historyStore: any GraphChatHistoryStoring,
        feedbackStore: any GraphChatFeedbackStoring,
        clipboardWriter: any GraphChatClipboardWriting,
        observability: any GraphChatObservabilityRecording =
            NoOpGraphChatObservabilityRecorder(),
        checkpointController: GraphChatConversationCheckpointController,
        generation: GraphChatMessageActionGenerationBridge,
        accessDecisionProvider: @escaping AccessDecisionProvider,
        resultHandler: @escaping ResultHandler
    ) {
        precondition(
            graphScope == chatScope.graphScope,
            "GraphChatMessageActionController requires matching graph and chat scopes."
        )
        precondition(
            checkpointController.graphScope == graphScope
                && checkpointController.chatScope == chatScope,
            "GraphChatMessageActionController requires a matching checkpoint controller."
        )
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.orchestrator = orchestrator
        self.historyStore = historyStore
        self.feedbackStore = feedbackStore
        self.clipboardWriter = clipboardWriter
        self.observability = observability
        self.checkpointController = checkpointController
        self.generation = generation
        self.accessDecisionProvider = accessDecisionProvider
        self.resultHandler = resultHandler
    }

    deinit {
        sessionMutationTask?.cancel()
        interpretationCorrectionCancellationTask?
            .cancel()
        feedbackTask?.cancel()
    }

    func perform(
        _ action: GraphChatMessageAction,
        messageID: UUID?,
        snapshot: GraphChatMessageActionSnapshot
    ) {
        switch action {
        case .startNewChat:
            startNewChat(snapshot: snapshot)
        case .copy:
            guard let messageID else {
                return
            }
            copyAssistantResponse(
                messageID: messageID,
                snapshot: snapshot
            )
        case .editAndResend:
            guard let messageID else {
                return
            }
            beginEditing(
                messageID: messageID,
                snapshot: snapshot
            )
        case .regenerate:
            guard let messageID else {
                return
            }
            regenerate(
                messageID: messageID,
                allowsTechnicalState: false,
                snapshot: snapshot
            )
        case .feedback(let category):
            guard let messageID else {
                return
            }
            setFeedback(
                category,
                for: messageID,
                snapshot: snapshot
            )
        case .removeFeedback:
            guard let messageID else {
                return
            }
            removeFeedback(
                for: messageID,
                snapshot: snapshot
            )
        }
    }

    func retry(
        messageID: UUID,
        snapshot: GraphChatMessageActionSnapshot
    ) {
        regenerate(
            messageID: messageID,
            allowsTechnicalState: true,
            snapshot: snapshot
        )
    }

    func submitEditedQuestion(
        snapshot: GraphChatMessageActionSnapshot,
        replacementQuestion: String
    ) {
        let decision = accessDecisionProvider()
        guard decision.canStartGeneration,
              snapshot.isPerformingSessionMutation == false,
              let editingState = snapshot.editingState,
              let plan = GraphChatMessageActionPlanner.editResendPlan(
                messages: snapshot.messages,
                userMessageID: editingState.userMessageID,
                replacementQuestion: replacementQuestion,
                graphScope: graphScope,
                chatScope: chatScope
              ) else {
            return
        }

        resultHandler(.sessionMutationBegan)
        let previousFeedbackTask = feedbackTask
        let assistantID = UUID()
        let request = GraphChatGenerationRequest(
            question: plan.replacementQuestion,
            assistantMessageID: assistantID,
            mode: .branchReplacement,
            usedIndexFallback: decision.usesIndexFallback
        )
        generation.start(request) { [weak self] operationID, persistTurnStart in
            guard let self else {
                return false
            }
            await previousFeedbackTask?.value
            guard Task.isCancelled == false,
                  self.generation.isActive(operationID) else {
                return false
            }

            let restoreResult = await self.restoreForBranch(
                plan.restoreCheckpoint
            )
            guard case .restored = restoreResult else {
                self.finishFailedBranchRestore(
                    restoreResult,
                    operationID: operationID
                )
                return false
            }
            guard Task.isCancelled == false,
                  self.generation.isActive(operationID) else {
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
            let replacementMessages =
                plan.retainedMessages + [userMessage, assistantMessage]
            let replacementFeedback = snapshot.feedbackByMessageID.filter {
                plan.removedMessageIDs.contains($0.key) == false
            }
            self.resultHandler(
                .branchCommitted(
                    messages: replacementMessages,
                    feedbackByMessageID: replacementFeedback,
                    composerText: "",
                    clearsEditing: true
                )
            )
            guard await persistTurnStart() else {
                return false
            }
            await self.feedbackStore.remove(
                messageIDs: plan.removedMessageIDs,
                for: self.chatScope
            )
            guard Task.isCancelled == false,
                  self.generation.isActive(operationID) else {
                return false
            }
            self.resultHandler(
                .sessionMutationFinished(notice: nil)
            )
            return true
        }
    }

    /// Runs a schema-bound interpretation correction without changing the
    /// visible transcript until the orchestrator has committed one complete
    /// local replacement turn.
    func applyInterpretationCorrection(
        _ request:
            GraphChatInterpretationCorrectionRequest,
        snapshot:
            GraphChatMessageActionSnapshot
    ) {
        let decision = accessDecisionProvider()
        guard
            decision.route == .ready,
            snapshot
                .isPerformingSessionMutation
                == false,
            activeInterpretationCorrectionID
                == nil,
            let plan =
                GraphChatInterpretationCorrectionPlanner
                    .plan(
                        messages:
                            snapshot.messages,
                        assistantMessageID:
                            request.binding
                                .originalAssistantMessage
                                .id,
                        graphScope:
                            graphScope,
                        chatScope:
                            chatScope
                    ),
            plan.binding == request.binding
        else {
            rejectInterpretationCorrection(
                state:
                    .stale(
                        .conversationChanged
                    ),
                language:
                    request.binding
                        .originalInterpretation
                        .responseLanguage,
                finishesMutation: false
            )
            return
        }

        let mutationID = UUID()
        activeSessionMutationID =
            mutationID
        activeInterpretationCorrectionID =
            mutationID
        resultHandler(.sessionMutationBegan)

        let generationCleanupTask =
            generation.cancel(
                discardSession: false,
                persistMessageSnapshot:
                    false
            )
        let previousFeedbackTask =
            feedbackTask
        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let feedbackStore = self.feedbackStore
        let observability = self.observability
        let checkpointController =
            self.checkpointController
        let chatScope = self.chatScope

        sessionMutationTask =
            Task { [weak self] in
                await generationCleanupTask?
                    .value
                await previousFeedbackTask?
                    .value
                guard
                    let self,
                    Task.isCancelled
                        == false,
                    self.isActiveSessionMutation(
                        mutationID
                    )
                else {
                    return
                }

                let stream =
                    await orchestrator
                        .streamCorrectedIntent(
                            request
                        )
                guard
                    Task.isCancelled == false,
                    self.isActiveSessionMutation(
                        mutationID
                    )
                else {
                    return
                }
                self.activeInterpretationCorrectionStreamID =
                    mutationID
                var replacementState =
                    GraphChatAssistantMessageState(
                        question:
                            request.binding
                                .originalQuestion
                    )
                var terminalEvent:
                    GraphChatStreamEvent?
                var terminalCount = 0

                for await event in stream {
                    guard
                        self.isActiveSessionMutation(
                            mutationID
                        )
                    else {
                        return
                    }
                    switch event {
                    case .started,
                        .toolActivity,
                        .partialAnswer:
                        replacementState
                            .apply(event)
                    case .completed,
                        .cancelled,
                        .failure:
                        terminalCount += 1
                        if terminalEvent == nil {
                            terminalEvent =
                                event
                        }
                    }
                }

                if self
                    .activeInterpretationCorrectionCancellationID
                    == mutationID {
                    await self
                        .interpretationCorrectionCancellationTask?
                        .value
                }
                guard
                    self.isActiveSessionMutation(
                        mutationID
                    )
                else {
                    return
                }
                guard
                    terminalCount == 1,
                    let terminalEvent
                else {
                    self.rejectInterpretationCorrection(
                        state:
                            .stale(
                                .conversationChanged
                            ),
                        language:
                            request.binding
                                .originalInterpretation
                                .responseLanguage
                    )
                    self.finishSessionMutation(
                        mutationID
                    )
                    return
                }

                switch terminalEvent {
                case .completed(
                    let answer
                ):
                    // The original artifact session authorizes the request
                    // before execution. A completed replacement may carry the
                    // runtime's newly committed session in its fresh origin.
                    guard
                        let interpretation =
                            answer.interpretation,
                        interpretation
                            .isCorrectionEditable,
                        interpretation
                            .turnBinding
                            .conversationID
                            == request
                                .binding
                                .conversationID,
                        interpretation
                            .scopeBinding
                            .graphScope
                            == request
                                .binding
                                .graphScope,
                        interpretation
                            .scopeBinding
                            .chatScope
                            == request
                                .binding
                                .chatScope,
                        interpretation
                            .intentKind
                            == request
                                .capabilities
                                .intentKind,
                        interpretation
                            .turnBinding
                            .requestID
                            != request
                                .binding
                                .originalRequest
                                .id,
                        let state =
                            await orchestrator
                                .conversationStateSnapshot(),
                        let checkpoint =
                            checkpointController
                                .captureCommittedCheckpoint(
                                    state:
                                        state,
                                    outcome:
                                        .completed
                                )
                    else {
                        self.rejectInterpretationCorrection(
                            state:
                                .stale(
                                    .conversationChanged
                                ),
                            language:
                                request.binding
                                    .originalInterpretation
                                    .responseLanguage
                        )
                        self.finishSessionMutation(
                            mutationID
                        )
                        return
                    }

                    replacementState.apply(
                        terminalEvent
                    )
                    guard
                        replacementState
                            .isTerminal,
                        replacementState
                            .answer != nil
                    else {
                        self.rejectInterpretationCorrection(
                            state:
                                .stale(
                                    .conversationChanged
                                ),
                            language:
                                request.binding
                                    .originalInterpretation
                                    .responseLanguage
                        )
                        self.finishSessionMutation(
                            mutationID
                        )
                        return
                    }

                    let assistantMessage =
                        GraphChatTranscriptMessage(
                            state:
                                .assistant(
                                    replacementState
                                ),
                            conversationCheckpointBeforeTurn:
                                request
                                    .binding
                                    .checkpointBeforeOriginalTurn,
                            conversationCheckpointAfterTurn:
                                checkpoint
                        )
                    let replacementMessages =
                        plan.retainedMessages
                        + [
                            assistantMessage
                        ]
                    let replacementFeedback =
                        snapshot
                            .feedbackByMessageID
                            .filter {
                                plan
                                    .removedMessageIDs
                                    .contains(
                                        $0.key
                                    )
                                    == false
                            }

                    await feedbackStore.remove(
                        messageIDs:
                            plan.removedMessageIDs,
                        for: chatScope
                    )
                    await historyStore.save(
                        replacementMessages,
                        for: chatScope
                    )
                    await observability.record(
                        .historySave(
                            GraphChatHistorySaveMetric(
                                boundary: .interpretationCorrection
                            )
                        )
                    )
                    self.resultHandler(
                        .branchCommitted(
                            messages:
                                replacementMessages,
                            feedbackByMessageID:
                                replacementFeedback,
                            composerText:
                                snapshot
                                    .composerText,
                            clearsEditing:
                                false
                        )
                    )
                    self.resultHandler(
                        .interpretationCorrectionCommitted
                    )
                    self.resultHandler(
                        .sessionMutationFinished(
                            notice: nil
                        )
                    )
                    self.finishSessionMutation(
                        mutationID
                    )

                case .cancelled:
                    self.resultHandler(
                        .interpretationCorrectionCancelled
                    )
                    self.resultHandler(
                        .sessionMutationFinished(
                            notice: nil
                        )
                    )
                    self.finishSessionMutation(
                        mutationID
                    )

                case .failure(
                    let failure
                ):
                    self.rejectInterpretationCorrection(
                        state:
                            failure.code
                                == .unavailable
                            ? .stale(
                                .graphLocked
                            )
                            : .stale(
                                .schemaChanged
                            ),
                        language:
                            request.binding
                                .originalInterpretation
                                .responseLanguage,
                        errorCode:
                            failure.code
                    )
                    self.finishSessionMutation(
                        mutationID
                    )

                case .started,
                    .toolActivity,
                    .partialAnswer:
                    self.rejectInterpretationCorrection(
                        state:
                            .stale(
                                .conversationChanged
                            ),
                        language:
                            request.binding
                                .originalInterpretation
                                .responseLanguage
                    )
                    self.finishSessionMutation(
                        mutationID
                    )
                }
            }
    }

    func cancelInterpretationCorrection() {
        guard
            let mutationID =
                activeInterpretationCorrectionID,
            activeSessionMutationID
                == mutationID
        else {
            return
        }
        let orchestrator = self.orchestrator
        if activeInterpretationCorrectionStreamID
            != mutationID {
            guard
                activeInterpretationCorrectionCancellationID
                    != mutationID
            else {
                return
            }
            activeInterpretationCorrectionCancellationID =
                mutationID
            let pendingTask =
                sessionMutationTask
            pendingTask?.cancel()
            sessionMutationTask =
                Task { [weak self] in
                    await pendingTask?.value
                    await orchestrator
                        .cancelCurrentGeneration()
                    guard
                        let self,
                        self.isActiveSessionMutation(
                            mutationID
                        ),
                        self
                            .activeInterpretationCorrectionCancellationID
                            == mutationID
                    else {
                        return
                    }
                    self.resultHandler(
                        .interpretationCorrectionCancelled
                    )
                    self.resultHandler(
                        .sessionMutationFinished(
                            notice: nil
                        )
                    )
                    self.finishSessionMutation(
                        mutationID
                    )
                }
            return
        }
        guard
            activeInterpretationCorrectionCancellationID
                != mutationID
        else {
            return
        }
        activeInterpretationCorrectionCancellationID =
            mutationID
        interpretationCorrectionCancellationTask =
            Task {
                await orchestrator
                    .cancelCurrentGeneration()
            }
    }

    func messageActionAvailability(
        for messageID: UUID,
        snapshot: GraphChatMessageActionSnapshot
    ) -> GraphChatMessageActionAvailability {
        let availability = GraphChatMessageActionPolicy.availability(
            for: messageID,
            in: snapshot.messages,
            isGenerating: generation.isGenerating
        )
        guard snapshot.isPerformingSessionMutation else {
            return availability
        }
        return GraphChatMessageActionAvailability(
            canCopy: availability.canCopy,
            canEditAndResend: false,
            canRegenerate: false,
            canGiveFeedback: false
        )
    }

    func loadFeedback(
        for messages: [GraphChatTranscriptMessage]
    ) async -> [UUID: GraphChatFeedbackCategory] {
        await feedbackTask?.value
        let records = await feedbackStore.records(for: chatScope)
        let messageIDs = Set(messages.map(\.id))
        let staleMessageIDs = records.compactMap { record in
            messageIDs.contains(record.localMessageID)
                ? nil
                : record.localMessageID
        }
        if staleMessageIDs.isEmpty == false {
            await feedbackStore.remove(
                messageIDs: staleMessageIDs,
                for: chatScope
            )
        }
        return Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                guard messageIDs.contains(record.localMessageID) else {
                    return nil
                }
                return (record.localMessageID, record.category)
            }
        )
    }

    func cancelGeneration(
        discardSession: Bool,
        showCancellationNotice: Bool
    ) {
        if activeInterpretationCorrectionID
            != nil {
            cancelInterpretationCorrection()
            return
        }
        let generationCleanupTask = generation.cancel(
            discardSession: discardSession
        )
        let previousMutationTask = sessionMutationTask
        previousMutationTask?.cancel()
        let mutationID = UUID()
        activeSessionMutationID = mutationID
        resultHandler(.sessionMutationBegan)

        sessionMutationTask = Task { [weak self] in
            await previousMutationTask?.value
            await generationCleanupTask?.value
            guard let self,
                  Task.isCancelled == false,
                  self.isActiveSessionMutation(mutationID) else {
                return
            }
            let notice = showCancellationNotice
                ? GraphChatActionNotice(
                    message: "Antwort abgebrochen",
                    systemImage: "stop.circle"
                )
                : nil
            self.resultHandler(
                .sessionMutationFinished(notice: notice)
            )
            self.finishSessionMutation(mutationID)
        }
    }

    func clearHistory(
        snapshot: GraphChatMessageActionSnapshot
    ) async {
        startNewChat(snapshot: snapshot)
        await sessionMutationTask?.value
    }

    @discardableResult
    func discardSensitiveState() -> [Task<Void, Never>] {
        let generationCleanupTask = generation.cancel(
            discardSession: false,
            persistMessageSnapshot: false
        )
        let correctionCleanupTask:
            Task<Void, Never>? =
                activeInterpretationCorrectionID
                == nil
                ? nil
                : Task { [orchestrator] in
                    await orchestrator
                        .cancelCurrentGeneration()
                }
        sessionMutationTask?.cancel()
        interpretationCorrectionCancellationTask?
            .cancel()
        feedbackTask?.cancel()
        let pendingTasks = [
            generationCleanupTask,
            correctionCleanupTask,
            sessionMutationTask,
            interpretationCorrectionCancellationTask,
            feedbackTask,
        ].compactMap { $0 }
        activeSessionMutationID = nil
        activeInterpretationCorrectionID =
            nil
        activeInterpretationCorrectionStreamID =
            nil
        activeInterpretationCorrectionCancellationID =
            nil
        sessionMutationTask = nil
        interpretationCorrectionCancellationTask =
            nil
        feedbackTask = nil
        checkpointController.reset()
        return pendingTasks
    }

    private func copyAssistantResponse(
        messageID: UUID,
        snapshot: GraphChatMessageActionSnapshot
    ) {
        guard let message = snapshot.messages.first(where: { $0.id == messageID }),
              case .assistant(let state) = message.state,
              let payload = GraphChatCopyContentBuilder.payload(for: state) else {
            return
        }
        clipboardWriter.write(payload.text)
        resultHandler(
            .notice(
                GraphChatActionNotice(
                    message: "Antwort kopiert",
                    systemImage: "doc.on.doc"
                )
            )
        )
    }

    private func beginEditing(
        messageID: UUID,
        snapshot: GraphChatMessageActionSnapshot
    ) {
        guard let message = snapshot.messages.first(where: { $0.id == messageID }),
              case .userQuestion(let question) = message.state,
              question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        let generationCleanupTask = generation.isGenerating
            ? generation.cancel(discardSession: false)
            : nil
        resultHandler(
            .editingBegan(
                editingState: GraphChatEditingState(
                    userMessageID: messageID,
                    originalQuestion: question
                ),
                composerText: question
            )
        )
        if let generationCleanupTask {
            beginGenerationCancellationMutation(
                awaiting: generationCleanupTask
            )
        }
    }

    private func regenerate(
        messageID: UUID,
        allowsTechnicalState: Bool,
        snapshot: GraphChatMessageActionSnapshot
    ) {
        guard let plan = GraphChatMessageActionPlanner.regenerationPlan(
            messages: snapshot.messages,
            assistantMessageID: messageID,
            graphScope: graphScope,
            chatScope: chatScope
        ) else {
            return
        }
        guard let message = snapshot.messages.first(where: { $0.id == messageID }),
              case .assistant(let state) = message.state else {
            return
        }

        let isTechnicalRetry = state.phase == .technicalError
        guard state.answer != nil
                || (allowsTechnicalState && isTechnicalRetry)
                || state.isTerminal == false else {
            return
        }

        let decision = accessDecisionProvider()
        if generation.isGenerating {
            guard generation.activeAssistantMessageID == messageID,
                  generation.activeMode?.isRegeneration == false,
                  decision.canCancelGeneration else {
                return
            }
        } else {
            guard decision.canStartGeneration,
                  snapshot.isPerformingSessionMutation == false else {
                return
            }
        }

        let previousFeedbackTask = feedbackTask
        resultHandler(.sessionMutationBegan)
        let request = GraphChatGenerationRequest(
            question: plan.question,
            assistantMessageID: messageID,
            mode: isTechnicalRetry ? .technicalRetry : .regeneration,
            usedIndexFallback: decision.usesIndexFallback
        )
        generation.start(request) { [weak self] operationID, persistTurnStart in
            guard let self else {
                return false
            }
            await previousFeedbackTask?.value
            guard Task.isCancelled == false,
                  self.generation.isActive(operationID) else {
                return false
            }

            let restoreResult = await self.restoreForBranch(
                plan.restoreCheckpoint
            )
            guard case .restored = restoreResult else {
                self.finishFailedBranchRestore(
                    restoreResult,
                    operationID: operationID
                )
                return false
            }
            guard Task.isCancelled == false,
                  self.generation.isActive(operationID) else {
                return false
            }

            let assistantMessage = GraphChatTranscriptMessage(
                id: plan.assistantMessageID,
                createdAt: plan.assistantCreatedAt,
                state: .assistant(
                    GraphChatAssistantMessageState(
                        question: plan.question
                    )
                ),
                conversationCheckpointBeforeTurn: plan.restoreCheckpoint
            )
            let replacementMessages =
                plan.retainedMessages + [assistantMessage]
            var replacementFeedback = snapshot.feedbackByMessageID
            replacementFeedback[plan.assistantMessageID] = nil
            self.resultHandler(
                .branchCommitted(
                    messages: replacementMessages,
                    feedbackByMessageID: replacementFeedback,
                    composerText: snapshot.composerText,
                    clearsEditing: false
                )
            )
            guard await persistTurnStart() else {
                return false
            }
            await self.feedbackStore.remove(
                messageID: plan.assistantMessageID,
                for: self.chatScope
            )
            guard Task.isCancelled == false,
                  self.generation.isActive(operationID) else {
                return false
            }
            self.resultHandler(
                .sessionMutationFinished(notice: nil)
            )
            return true
        }
    }

    private func setFeedback(
        _ category: GraphChatFeedbackCategory,
        for messageID: UUID,
        snapshot: GraphChatMessageActionSnapshot
    ) {
        guard snapshot.isPerformingSessionMutation == false,
              let message = snapshot.messages.first(where: { $0.id == messageID }),
              case .assistant(let state) = message.state,
              let answerState = GraphChatMessageActionPolicy.feedbackAnswerState(
                for: state
              ) else {
            return
        }

        if snapshot.feedbackByMessageID[messageID] == category {
            removeFeedback(
                for: messageID,
                snapshot: snapshot
            )
            return
        }

        let record = GraphChatFeedbackRecord(
            localMessageID: messageID,
            category: category,
            answerState: answerState,
            scopeType: GraphChatFeedbackScopeType(scope: chatScope),
            toolCategories: state.toolActivities.map(\.tool)
        )
        var feedback = snapshot.feedbackByMessageID
        feedback[messageID] = category
        enqueueFeedbackWrite { [feedbackStore, chatScope] in
            await feedbackStore.save(
                record,
                for: chatScope
            )
        }
        resultHandler(
            .feedbackChanged(
                feedbackByMessageID: feedback,
                notice: GraphChatActionNotice(
                    message: "Feedback gespeichert: \(category.title)",
                    systemImage: "checkmark.circle"
                )
            )
        )
    }

    private func removeFeedback(
        for messageID: UUID,
        snapshot: GraphChatMessageActionSnapshot
    ) {
        guard snapshot.isPerformingSessionMutation == false,
              snapshot.feedbackByMessageID[messageID] != nil else {
            return
        }
        var feedback = snapshot.feedbackByMessageID
        feedback[messageID] = nil
        enqueueFeedbackWrite { [feedbackStore, chatScope] in
            await feedbackStore.remove(
                messageID: messageID,
                for: chatScope
            )
        }
        resultHandler(
            .feedbackChanged(
                feedbackByMessageID: feedback,
                notice: GraphChatActionNotice(
                    message: "Feedback entfernt",
                    systemImage: "xmark.circle"
                )
            )
        )
    }

    private func startNewChat(
        snapshot: GraphChatMessageActionSnapshot
    ) {
        guard snapshot.isPerformingSessionMutation == false
                || generation.isGenerating else {
            return
        }

        let generationCleanupTask = generation.cancel(
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
        resultHandler(.sessionMutationBegan)

        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let feedbackStore = self.feedbackStore
        let chatScope = self.chatScope
        sessionMutationTask = Task { [weak self] in
            await previousMutationTask?.value
            await generationCleanupTask?.value
            await previousFeedbackTask?.value
            await orchestrator.discardSession(
                reason: .newConversation
            )
            await historyStore.removeMessages(for: chatScope)
            await feedbackStore.removeAll(for: chatScope)
            guard let self,
                  Task.isCancelled == false,
                  self.isActiveSessionMutation(mutationID) else {
                return
            }
            self.checkpointController.reset()
            self.resultHandler(.newChatBegan)
            self.resultHandler(
                .sessionMutationFinished(
                    notice: GraphChatActionNotice(
                        message: "Neuer Chat gestartet",
                        systemImage: "plus.message"
                    )
                )
            )
            self.finishSessionMutation(mutationID)
        }
    }

    private func restoreForBranch(
        _ checkpoint: GraphChatConversationCheckpoint
    ) async -> GraphChatConversationBranchRestoreResult {
        await checkpointController.restoreCheckpointForBranch(
            checkpoint,
            accessIsValid: { [weak self] in
                guard let self else {
                    return false
                }
                return self.accessDecisionProvider().route == .ready
            },
            restore: { [orchestrator] checkpoint in
                try await orchestrator.restoreConversationState(
                    from: checkpoint
                )
            }
        )
    }

    private func finishFailedBranchRestore(
        _ result: GraphChatConversationBranchRestoreResult,
        operationID: GraphChatGenerationOperationID
    ) {
        guard generation.isActive(operationID),
              case .rejected(let message) = result else {
            return
        }
        resultHandler(
            .sessionMutationFinished(
                notice: GraphChatActionNotice(
                    message: message,
                    systemImage: "exclamationmark.triangle"
                )
            )
        )
    }

    private func enqueueFeedbackWrite(
        _ operation: @escaping @Sendable () async -> Void
    ) {
        let previousFeedbackTask = feedbackTask
        feedbackTask = Task {
            await previousFeedbackTask?.value
            guard Task.isCancelled == false else {
                return
            }
            await operation()
        }
    }

    private func beginGenerationCancellationMutation(
        awaiting generationCleanupTask: Task<Void, Never>
    ) {
        let previousMutationTask = sessionMutationTask
        previousMutationTask?.cancel()
        let mutationID = UUID()
        activeSessionMutationID = mutationID
        resultHandler(.sessionMutationBegan)
        sessionMutationTask = Task { [weak self] in
            await previousMutationTask?.value
            await generationCleanupTask.value
            guard let self,
                  Task.isCancelled == false,
                  self.isActiveSessionMutation(mutationID) else {
                return
            }
            self.resultHandler(
                .sessionMutationFinished(notice: nil)
            )
            self.finishSessionMutation(mutationID)
        }
    }

    private func finishSessionMutation(
        _ mutationID: UUID
    ) {
        guard activeSessionMutationID == mutationID else {
            return
        }
        if activeInterpretationCorrectionID
            == mutationID {
            activeInterpretationCorrectionID =
                nil
        }
        if activeInterpretationCorrectionStreamID
            == mutationID {
            activeInterpretationCorrectionStreamID =
                nil
        }
        if activeInterpretationCorrectionCancellationID
            == mutationID {
            activeInterpretationCorrectionCancellationID =
                nil
        }
        activeSessionMutationID = nil
        sessionMutationTask = nil
        interpretationCorrectionCancellationTask =
            nil
    }

    private func rejectInterpretationCorrection(
        state:
            GraphChatInterpretationCorrectionValidationState,
        language:
            GraphChatResponseLanguage,
        errorCode:
            GraphChatErrorCode =
                .invalidRequest,
        finishesMutation: Bool = true
    ) {
        let localizer =
            GraphChatResponseLocalizer(
                language: language
            )
        resultHandler(
            .interpretationCorrectionFailed(
                validationState: state,
                notice:
                    GraphChatActionNotice(
                        message:
                            localizer
                                .userFacingFailure(
                                    errorCode
                                ),
                        systemImage:
                            "exclamationmark.triangle"
                    )
            )
        )
        if finishesMutation {
            resultHandler(
                .sessionMutationFinished(
                    notice: nil
                )
            )
        }
    }

    private func isActiveSessionMutation(
        _ mutationID: UUID
    ) -> Bool {
        activeSessionMutationID == mutationID
    }
}
