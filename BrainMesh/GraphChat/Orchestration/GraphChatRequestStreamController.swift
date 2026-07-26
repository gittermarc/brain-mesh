//
//  GraphChatRequestStreamController.swift
//  BrainMesh
//
//  Exactly-once start, terminal event and finish for one request stream.
//

import Foundation

nonisolated struct GraphChatRequestStreamLifecycleSnapshot: Hashable, Sendable {
    let requestID: UUID
    let startedCount: Int
    let terminalEventCount: Int
    let finishCount: Int
}

actor GraphChatRequestStreamController {
    private let requestID: UUID
    private let continuation: GraphChatEventStream.Continuation
    private var didStart = false
    private var didEmitTerminalEvent = false
    private var didFinish = false
    private var startedCount = 0
    private var terminalEventCount = 0
    private var finishCount = 0

    init(
        requestID: UUID,
        continuation: GraphChatEventStream.Continuation
    ) {
        self.requestID = requestID
        self.continuation = continuation
    }

    func start() {
        guard didStart == false,
              didFinish == false else {
            return
        }
        didStart = true
        startedCount += 1
        continuation.yield(.started(requestID: requestID))
    }

    func forward(
        _ event: GraphChatProviderForwardedEvent
    ) {
        guard didStart,
              didEmitTerminalEvent == false,
              didFinish == false else {
            return
        }
        switch event {
        case .toolActivity(let activity):
            continuation.yield(.toolActivity(activity))
        case .partialAnswer(let text):
            continuation.yield(.partialAnswer(text))
        }
    }

    func complete(_ answer: GraphChatAnswer) {
        emitTerminal(.completed(answer))
    }

    func cancel() {
        emitTerminal(.cancelled)
    }

    func fail(_ error: GraphChatError) {
        emitTerminal(.failure(error))
    }

    func finish() {
        guard didFinish == false else {
            return
        }
        didFinish = true
        finishCount += 1
        continuation.finish()
    }

    func snapshotForTesting() -> GraphChatRequestStreamLifecycleSnapshot {
        GraphChatRequestStreamLifecycleSnapshot(
            requestID: requestID,
            startedCount: startedCount,
            terminalEventCount: terminalEventCount,
            finishCount: finishCount
        )
    }

    private func emitTerminal(
        _ event: GraphChatStreamEvent
    ) {
        guard didStart,
              didEmitTerminalEvent == false,
              didFinish == false else {
            return
        }
        didEmitTerminalEvent = true
        terminalEventCount += 1
        continuation.yield(event)
    }
}
