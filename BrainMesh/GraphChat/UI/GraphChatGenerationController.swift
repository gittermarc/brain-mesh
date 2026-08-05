//
//  GraphChatGenerationController.swift
//  BrainMesh
//
//  Main-actor owner of the technical generation and streaming lifecycle.
//

import Foundation

@MainActor
final class GraphChatGenerationController {
    typealias TurnStartPersistence = @MainActor () async -> Bool
    typealias Preparation = @MainActor (
        _ operationID: GraphChatGenerationOperationID,
        _ persistTurnStart: TurnStartPersistence
    ) async -> Bool

    private struct ActiveOperation {
        let request: GraphChatGenerationRequest
        var terminalEventAccepted = false

        var presentation: GraphChatActiveGeneration {
            GraphChatActiveGeneration(
                operationID: operationID,
                assistantMessageID: request.assistantMessageID,
                mode: request.mode
            )
        }

        let operationID: GraphChatGenerationOperationID
    }

    private let graphScope: GraphScope
    private let chatScope: GraphChatScope
    private let orchestrator: any GraphChatOrchestrating
    private let historyStore: any GraphChatHistoryStoring
    private let observability: any GraphChatObservabilityRecording
    private let callbacks: GraphChatGenerationCallbacks
    private let streamingConfiguration:
        GraphChatStreamingBackpressureConfiguration
    private let streamingClock: GraphChatStreamingClock
    private let operationIDFactory: @MainActor () -> GraphChatGenerationOperationID

    private(set) var state: GraphChatGenerationState = .idle
    private var activeOperation: ActiveOperation?
    private var activeTask: Task<Void, Never>?
    private var terminalOperationsFinishing:
        Set<GraphChatGenerationOperationID> = []
    private var cancellationBarrier: Task<Void, Never>?
    private var cancellationBarrierID: UUID?

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        orchestrator: any GraphChatOrchestrating,
        historyStore: any GraphChatHistoryStoring,
        observability: any GraphChatObservabilityRecording,
        callbacks: GraphChatGenerationCallbacks,
        streamingConfiguration:
            GraphChatStreamingBackpressureConfiguration = .standard,
        streamingClock: GraphChatStreamingClock = .continuous,
        operationIDFactory: @escaping @MainActor () -> GraphChatGenerationOperationID = {
            GraphChatGenerationOperationID()
        }
    ) {
        precondition(
            graphScope == chatScope.graphScope,
            "GraphChatGenerationController requires matching graph and chat scopes."
        )
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.orchestrator = orchestrator
        self.historyStore = historyStore
        self.observability = observability
        self.callbacks = callbacks
        self.streamingConfiguration = streamingConfiguration
        self.streamingClock = streamingClock
        self.operationIDFactory = operationIDFactory
    }

    deinit {
        activeTask?.cancel()
        cancellationBarrier?.cancel()
    }

    var isGenerating: Bool {
        state.isGenerating
    }

    var activeOperationID: GraphChatGenerationOperationID? {
        state.activeGeneration?.operationID
    }

    var activeAssistantMessageID: UUID? {
        state.activeGeneration?.assistantMessageID
    }

    var activeMode: GraphChatGenerationMode? {
        state.activeGeneration?.mode
    }

    @discardableResult
    func start(
        _ request: GraphChatGenerationRequest,
        preparation: Preparation? = nil
    ) -> GraphChatGenerationOperationID {
        let previousOperation = activeOperation
        let previousTask = activeTask
        let previousTerminalEventAccepted =
            previousOperation?.terminalEventAccepted == true
        if previousTerminalEventAccepted == false {
            previousTask?.cancel()
        }

        if let previousOperation,
           previousOperation.terminalEventAccepted == false {
            callbacks.outcomeDidResolve(
                previousOperation.operationID,
                previousOperation.request.assistantMessageID,
                .cancelled
            )
        }

        let operationID = operationIDFactory()
        let operation = ActiveOperation(
            request: request,
            operationID: operationID
        )
        activeOperation = operation
        transition(to: .generating(operation.presentation))

        let priorBarrier = cancellationBarrier
        let orchestrator = self.orchestrator
        let observability = self.observability
        let historyStore = self.historyStore
        let chatScope = self.chatScope
        let initialTurnStartSnapshot = preparation == nil
            ? callbacks.messageSnapshot()
            : nil
        let operationTimer = BMDuration()
        activeTask = Task { [weak self] in
            await priorBarrier?.value

            if let previousTask {
                if previousTerminalEventAccepted == false {
                    await orchestrator.cancelCurrentGeneration()
                }
                await previousTask.value
            }

            if let initialTurnStartSnapshot {
                await historyStore.save(
                    initialTurnStartSnapshot,
                    for: chatScope
                )
                await observability.record(
                    .historySave(
                        GraphChatHistorySaveMetric(boundary: .turnStart)
                    )
                )
            }

            guard Task.isCancelled == false else {
                await observability.record(
                    .request(
                        GraphChatGenerationMetricFactory.cancellationMetric(
                            for: request,
                            durationMilliseconds: operationTimer.millisecondsElapsed
                        )
                    )
                )
                return
            }

            guard let self,
                  Task.isCancelled == false,
                  self.acceptsCallbacks(
                    operationID: operationID,
                    assistantMessageID: request.assistantMessageID
                  ) else {
                await observability.record(
                    .request(
                        GraphChatGenerationMetricFactory.cancellationMetric(
                            for: request,
                            durationMilliseconds: operationTimer.millisecondsElapsed
                        )
                    )
                )
                return
            }

            if let preparation {
                var didPersistTurnStart = false
                let isReady = await preparation(
                    operationID,
                    {
                        if didPersistTurnStart {
                            return true
                        }
                        guard Task.isCancelled == false,
                              self.acceptsCallbacks(
                                operationID: operationID,
                                assistantMessageID:
                                    request.assistantMessageID
                              ) else {
                            return false
                        }
                        await self.saveHistory(boundary: .turnStart)
                        guard Task.isCancelled == false,
                              self.acceptsCallbacks(
                                operationID: operationID,
                                assistantMessageID:
                                    request.assistantMessageID
                              ) else {
                            return false
                        }
                        didPersistTurnStart = true
                        return true
                    }
                )
                guard Task.isCancelled == false,
                      self.acceptsCallbacks(
                        operationID: operationID,
                        assistantMessageID: request.assistantMessageID
                      ) else {
                    await observability.record(
                        .request(
                            GraphChatGenerationMetricFactory.cancellationMetric(
                                for: request,
                                durationMilliseconds: operationTimer.millisecondsElapsed
                            )
                        )
                    )
                    return
                }
                guard isReady else {
                    self.finishWithoutTerminalOutcome(operationID)
                    return
                }
                guard didPersistTurnStart else {
                    self.finishWithoutTerminalOutcome(operationID)
                    return
                }
            }

            await self.consume(
                request: request,
                operationID: operationID,
                timer: operationTimer
            )
        }
        return operationID
    }

    @discardableResult
    func cancel(
        discardSession: Bool,
        persistMessageSnapshot: Bool = true
    ) -> Task<Void, Never>? {
        guard let operation = activeOperation,
              let task = activeTask else {
            return cancellationBarrier
        }

        let acceptedTerminalEvent = operation.terminalEventAccepted
        if acceptedTerminalEvent {
            let previousBarrier = cancellationBarrier
            let barrierID = UUID()
            cancellationBarrierID = barrierID
            let orchestrator = self.orchestrator
            let barrier = Task { [weak self] in
                await previousBarrier?.value
                await task.value
                if discardSession {
                    await orchestrator.discardSession()
                }
                self?.clearCancellationBarrier(barrierID)
            }
            cancellationBarrier = barrier
            return barrier
        }
        callbacks.operationWillCancel(
            operation.operationID,
            operation.request.assistantMessageID
        )
        callbacks.outcomeDidResolve(
            operation.operationID,
            operation.request.assistantMessageID,
            .cancelled
        )
        let snapshot = persistMessageSnapshot
            ? callbacks.messageSnapshot()
            : nil

        task.cancel()
        activeOperation = nil
        activeTask = nil
        transition(to: .idle)

        let previousBarrier = cancellationBarrier
        let barrierID = UUID()
        cancellationBarrierID = barrierID
        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let observability = self.observability
        let chatScope = self.chatScope
        let barrier = Task { [weak self] in
            await previousBarrier?.value
            await orchestrator.cancelCurrentGeneration()
            await task.value
            if discardSession {
                await orchestrator.discardSession()
            }
            if let snapshot {
                await historyStore.save(snapshot, for: chatScope)
                await observability.record(
                    .historySave(
                        GraphChatHistorySaveMetric(boundary: .cancellation)
                    )
                )
            }
            self?.clearCancellationBarrier(barrierID)
        }
        cancellationBarrier = barrier
        return barrier
    }

    /// Ensures that provider/tool cancellation stays behind this technical boundary
    /// even when no visible generation operation is currently registered.
    @discardableResult
    func cancelRuntime(
        discardSession: Bool,
        persistMessageSnapshot: Bool = true
    ) -> Task<Void, Never> {
        if activeOperation != nil,
           let cancellationTask = cancel(
            discardSession: discardSession,
            persistMessageSnapshot: persistMessageSnapshot
           ) {
            return cancellationTask
        }

        let snapshot = persistMessageSnapshot
            ? callbacks.messageSnapshot()
            : nil
        let previousBarrier = cancellationBarrier
        let barrierID = UUID()
        cancellationBarrierID = barrierID
        let orchestrator = self.orchestrator
        let historyStore = self.historyStore
        let observability = self.observability
        let chatScope = self.chatScope
        let barrier = Task { [weak self] in
            await previousBarrier?.value
            await orchestrator.cancelCurrentGeneration()
            if discardSession {
                await orchestrator.discardSession()
            }
            if let snapshot {
                await historyStore.save(
                    snapshot,
                    for: chatScope
                )
                await observability.record(
                    .historySave(
                        GraphChatHistorySaveMetric(boundary: .runtimeBoundary)
                    )
                )
            }
            self?.clearCancellationBarrier(barrierID)
        }
        cancellationBarrier = barrier
        return barrier
    }

    func isActive(_ operationID: GraphChatGenerationOperationID) -> Bool {
        activeOperation?.operationID == operationID
            || terminalOperationsFinishing.contains(operationID)
    }

    private func consume(
        request: GraphChatGenerationRequest,
        operationID: GraphChatGenerationOperationID,
        timer: BMDuration
    ) async {
        guard Task.isCancelled == false,
              acceptsCallbacks(
                operationID: operationID,
                assistantMessageID: request.assistantMessageID
              ) else {
            await recordCancellationMetric(
                for: request,
                timer: timer
            )
            return
        }

        let stream = await orchestrator.streamAnswer(
            question: request.question,
            graphScope: graphScope,
            chatScope: chatScope
        )
        let coordinator = GraphChatStreamingBackpressureCoordinator(
            configuration: streamingConfiguration,
            clock: streamingClock
        )
        let statistics = await coordinator.consume(stream) { [weak self] publication in
            guard let self,
                  Task.isCancelled == false,
                  self.acceptsCallbacks(
                    operationID: operationID,
                    assistantMessageID: request.assistantMessageID
                  ) else {
                return false
            }
            return await self.accept(
                publication: publication,
                request: request,
                operationID: operationID
            )
        }

        if let terminalEvent = statistics.terminalEvent {
            await recordStreamingPerformance(
                statistics,
                durationMilliseconds: timer.millisecondsElapsed
            )
            let metric = GraphChatGenerationMetricFactory.terminalMetric(
                for: terminalEvent,
                request: request,
                durationMilliseconds: timer.millisecondsElapsed,
                toolCount: statistics.toolCount,
                toolKinds: statistics.toolKinds
            )
            if let metric {
                await observability.record(.request(metric))
            }
            if isActive(operationID) {
                finish(operationID)
            }
            return
        }

        guard Task.isCancelled == false,
              acceptsCallbacks(
                operationID: operationID,
                assistantMessageID: request.assistantMessageID
              ) else {
            await recordStreamingPerformance(
                statistics,
                durationMilliseconds: timer.millisecondsElapsed
            )
            await recordCancellationMetric(
                for: request,
                timer: timer,
                toolCount: statistics.toolCount,
                toolKinds: statistics.toolKinds
            )
            return
        }

        let failure = GraphChatError(
            code: .unexpected,
            message: "Die Antwort wurde ohne Abschluss beendet.",
            recoverySuggestion: "Versuche die Frage erneut."
        )
        let terminalSourceSequence = UInt64(statistics.sourceEventCount) + 1
        let firstSourceSequence =
            statistics.firstUnpublishedSourceSequence
            ?? terminalSourceSequence
        let acceptedSyntheticTerminal = await accept(
            publication: GraphChatStreamingUIPublication(
                events: statistics.unpublishedEvents + [.failure(failure)],
                reason: .terminal,
                firstSourceSequence: firstSourceSequence,
                lastSourceSequence: terminalSourceSequence
            ),
            request: request,
            operationID: operationID
        )
        let syntheticContainsPartial = statistics.unpublishedEvents.contains {
            event in
            if case .partialAnswer = event {
                return true
            }
            return false
        }
        await recordStreamingPerformance(
            statistics,
            durationMilliseconds: timer.millisecondsElapsed,
            additionalSafeUIPublicationCount:
                acceptedSyntheticTerminal ? 1 : 0,
            additionalPartialPublicationCount:
                acceptedSyntheticTerminal && syntheticContainsPartial ? 1 : 0
        )
        guard acceptedSyntheticTerminal else {
            await recordCancellationMetric(
                for: request,
                timer: timer,
                toolCount: statistics.toolCount,
                toolKinds: statistics.toolKinds
            )
            return
        }
        await observability.record(
            .request(
                GraphChatRequestMetric(
                    durationMilliseconds: timer.millisecondsElapsed,
                    toolCount: statistics.toolCount,
                    toolKinds: statistics.toolKinds,
                    evidenceCount: 0,
                    usedIndexFallback: request.usedIndexFallback,
                    outcome: .failed,
                    errorCode: failure.code
                )
            )
        )
        if isActive(operationID) {
            finish(operationID)
        }
    }

    private func accept(
        publication: GraphChatStreamingUIPublication,
        request: GraphChatGenerationRequest,
        operationID: GraphChatGenerationOperationID
    ) async -> Bool {
        guard Task.isCancelled == false,
              acceptsCallbacks(
                operationID: operationID,
                assistantMessageID: request.assistantMessageID
              ) else {
            return false
        }

        let terminalEvent = publication.terminalEvent
        if terminalEvent != nil {
            markTerminalEventAccepted(operationID)
        }
        callbacks.publicationDidArrive(
            publication,
            operationID,
            request.assistantMessageID
        )

        guard let terminalEvent else {
            return true
        }
        if let terminalOutcome = GraphChatGenerationEventClassifier.outcome(
            for: terminalEvent
        ) {
            callbacks.outcomeDidResolve(
                operationID,
                request.assistantMessageID,
                terminalOutcome
            )
        }
        if case .completed = terminalEvent {
            await callbacks.completedTurnDidArrive(
                operationID,
                request.assistantMessageID
            )
        }
        // Once the terminal publication was accepted, its checkpoint and
        // history boundary must finish even if the user starts the next turn
        // while this task is suspended in the completion callback.
        await saveHistory(boundary: .terminal)
        // The visible generation remains active until the coordinator returns
        // its final statistics and terminal observability has been recorded.
        return true
    }

    private func saveHistory(
        boundary: GraphChatHistorySaveBoundary
    ) async {
        let snapshot = callbacks.messageSnapshot()
        await historyStore.save(snapshot, for: chatScope)
        await observability.record(
            .historySave(GraphChatHistorySaveMetric(boundary: boundary))
        )
    }

    private func recordStreamingPerformance(
        _ statistics: GraphChatStreamingBackpressureStatistics,
        durationMilliseconds: Double,
        additionalSafeUIPublicationCount: Int = 0,
        additionalPartialPublicationCount: Int = 0
    ) async {
        await observability.record(
            .streamingPerformance(
                GraphChatStreamingPerformanceMetric(
                    safeStreamEventCount: statistics.sourceEventCount,
                    partialEventCount: statistics.partialEventCount,
                    safeUIPublicationCount:
                        statistics.safeUIPublicationCount
                        + additionalSafeUIPublicationCount,
                    partialPublicationCount:
                        statistics.partialPublicationCount
                        + additionalPartialPublicationCount,
                    rateLimitedPublicationCount:
                        statistics.rateLimitedPublicationCount,
                    durationMilliseconds: durationMilliseconds
                )
            )
        )
    }

    private func acceptsCallbacks(
        operationID: GraphChatGenerationOperationID,
        assistantMessageID: UUID
    ) -> Bool {
        guard let activeOperation else {
            return false
        }
        return activeOperation.operationID == operationID
            && activeOperation.request.assistantMessageID == assistantMessageID
            && activeOperation.terminalEventAccepted == false
    }

    private func markTerminalEventAccepted(
        _ operationID: GraphChatGenerationOperationID
    ) {
        guard activeOperation?.operationID == operationID else {
            return
        }
        activeOperation?.terminalEventAccepted = true
        terminalOperationsFinishing.insert(operationID)
    }

    private func finish(_ operationID: GraphChatGenerationOperationID) {
        terminalOperationsFinishing.remove(operationID)
        guard activeOperation?.operationID == operationID else {
            return
        }
        activeOperation = nil
        activeTask = nil
        transition(to: .idle)
    }

    private func finishWithoutTerminalOutcome(
        _ operationID: GraphChatGenerationOperationID
    ) {
        finish(operationID)
    }

    private func transition(to newState: GraphChatGenerationState) {
        let previousVisibleState = state.isGenerating
        state = newState
        let newVisibleState = newState.isGenerating
        guard previousVisibleState != newVisibleState else {
            return
        }
        callbacks.generationStateDidChange(newVisibleState)
    }

    private func clearCancellationBarrier(_ barrierID: UUID) {
        guard cancellationBarrierID == barrierID else {
            return
        }
        cancellationBarrierID = nil
        cancellationBarrier = nil
    }

    private func recordCancellationMetric(
        for request: GraphChatGenerationRequest,
        timer: BMDuration,
        toolCount: Int = 0,
        toolKinds: Set<GraphChatToolKind> = []
    ) async {
        await observability.record(
            .request(
                GraphChatGenerationMetricFactory.cancellationMetric(
                    for: request,
                    durationMilliseconds: timer.millisecondsElapsed,
                    toolCount: toolCount,
                    toolKinds: toolKinds
                )
            )
        )
    }

}
