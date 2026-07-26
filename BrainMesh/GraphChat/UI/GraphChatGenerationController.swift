//
//  GraphChatGenerationController.swift
//  BrainMesh
//
//  Main-actor owner of the technical generation and streaming lifecycle.
//

import Foundation

@MainActor
final class GraphChatGenerationController {
    typealias Preparation = @MainActor (
        _ operationID: GraphChatGenerationOperationID
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
    private let operationIDFactory: @MainActor () -> GraphChatGenerationOperationID

    private(set) var state: GraphChatGenerationState = .idle
    private var activeOperation: ActiveOperation?
    private var activeTask: Task<Void, Never>?
    private var cancellationBarrier: Task<Void, Never>?
    private var cancellationBarrierID: UUID?

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        orchestrator: any GraphChatOrchestrating,
        historyStore: any GraphChatHistoryStoring,
        observability: any GraphChatObservabilityRecording,
        callbacks: GraphChatGenerationCallbacks,
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
        previousTask?.cancel()

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
        let operationTimer = BMDuration()
        activeTask = Task { [weak self] in
            await priorBarrier?.value

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

            if let previousTask {
                await orchestrator.cancelCurrentGeneration()
                await previousTask.value
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
                let isReady = await preparation(operationID)
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
            }

            await self.consume(
                request: request,
                operationID: operationID
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
            }
            self?.clearCancellationBarrier(barrierID)
        }
        cancellationBarrier = barrier
        return barrier
    }

    func isActive(_ operationID: GraphChatGenerationOperationID) -> Bool {
        activeOperation?.operationID == operationID
    }

    private func consume(
        request: GraphChatGenerationRequest,
        operationID: GraphChatGenerationOperationID
    ) async {
        let timer = BMDuration()
        var toolCount = 0
        var toolKinds: Set<GraphChatToolKind> = []

        await historyStore.save(
            callbacks.messageSnapshot(),
            for: chatScope
        )
        guard Task.isCancelled == false,
              acceptsCallbacks(
                operationID: operationID,
                assistantMessageID: request.assistantMessageID
              ) else {
            await recordCancellationMetric(
                for: request,
                timer: timer,
                toolCount: toolCount,
                toolKinds: toolKinds
            )
            return
        }

        let stream = await orchestrator.streamAnswer(
            question: request.question,
            graphScope: graphScope,
            chatScope: chatScope
        )

        for await event in stream {
            guard Task.isCancelled == false,
                  acceptsCallbacks(
                    operationID: operationID,
                    assistantMessageID: request.assistantMessageID
                  ) else {
                await recordCancellationMetric(
                    for: request,
                    timer: timer,
                    toolCount: toolCount,
                    toolKinds: toolKinds
                )
                return
            }

            if case .toolActivity(let activity) = event,
               activity.state == .started {
                toolCount += 1
                toolKinds.insert(activity.tool)
            }

            let terminalOutcome = GraphChatGenerationEventClassifier.outcome(
                for: event
            )
            if terminalOutcome != nil {
                markTerminalEventAccepted(operationID)
            }
            callbacks.eventDidArrive(
                event,
                operationID,
                request.assistantMessageID
            )
            if let terminalOutcome {
                callbacks.outcomeDidResolve(
                    operationID,
                    request.assistantMessageID,
                    terminalOutcome
                )
            }

            if case .completed = event {
                await callbacks.completedTurnDidArrive(
                    operationID,
                    request.assistantMessageID
                )
            }

            await historyStore.save(
                callbacks.messageSnapshot(),
                for: chatScope
            )

            guard GraphChatGenerationEventClassifier.isTerminal(event) else {
                continue
            }

            let metric = GraphChatGenerationMetricFactory.terminalMetric(
                for: event,
                request: request,
                durationMilliseconds: timer.millisecondsElapsed,
                toolCount: toolCount,
                toolKinds: toolKinds
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
            await recordCancellationMetric(
                for: request,
                timer: timer,
                toolCount: toolCount,
                toolKinds: toolKinds
            )
            return
        }

        let failure = GraphChatError(
            code: .unexpected,
            message: "Die Antwort wurde ohne Abschluss beendet.",
            recoverySuggestion: "Versuche die Frage erneut."
        )
        markTerminalEventAccepted(operationID)
        callbacks.eventDidArrive(
            .failure(failure),
            operationID,
            request.assistantMessageID
        )
        callbacks.outcomeDidResolve(
            operationID,
            request.assistantMessageID,
            .failure(failure)
        )
        await historyStore.save(
            callbacks.messageSnapshot(),
            for: chatScope
        )
        await observability.record(
            .request(
                GraphChatRequestMetric(
                    durationMilliseconds: timer.millisecondsElapsed,
                    toolCount: toolCount,
                    toolKinds: toolKinds,
                    evidenceCount: 0,
                    usedIndexFallback: request.usedIndexFallback,
                    outcome: .failed,
                    errorCode: failure.code
                )
            )
        )
        guard isActive(operationID) else {
            return
        }
        finish(operationID)
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
    }

    private func finish(_ operationID: GraphChatGenerationOperationID) {
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
