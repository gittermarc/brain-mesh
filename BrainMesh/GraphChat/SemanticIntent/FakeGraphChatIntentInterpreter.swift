//
//  FakeGraphChatIntentInterpreter.swift
//  BrainMesh
//
//  Deterministic, tool-free semantic interpreter double.
//

import Foundation

nonisolated enum FakeGraphChatIntentInterpreterStep:
    Hashable,
    Sendable
{
    case draft(GraphChatUntrustedSemanticIntentDraft)
    case failure(GraphChatIntentInterpreterError)
    case waitForCancellation
}

nonisolated struct FakeGraphChatIntentInterpreterSnapshot:
    Hashable,
    Sendable
{
    let requests: [GraphChatIntentInterpreterRequest]
    let cancellationCount: Int
}

actor FakeGraphChatIntentInterpreter:
    GraphChatIntentInterpreting
{
    private var currentAvailability:
        GraphChatModelAvailability
    private var steps:
        [FakeGraphChatIntentInterpreterStep]
    private let delayNanoseconds: UInt64
    private var requests:
        [GraphChatIntentInterpreterRequest] = []
    private var cancellationCount = 0

    init(
        availability:
            GraphChatModelAvailability = .available,
        steps:
            [FakeGraphChatIntentInterpreterStep] = [],
        delayNanoseconds: UInt64 = 0
    ) {
        self.currentAvailability = availability
        self.steps = steps
        self.delayNanoseconds = delayNanoseconds
    }

    func availability() -> GraphChatModelAvailability {
        currentAvailability
    }

    func setAvailability(
        _ availability: GraphChatModelAvailability
    ) {
        currentAvailability = availability
    }

    func enqueue(
        _ step: FakeGraphChatIntentInterpreterStep
    ) {
        steps.append(step)
    }

    func interpret(
        _ request: GraphChatIntentInterpreterRequest
    ) async throws -> GraphChatUntrustedSemanticIntentDraft {
        guard currentAvailability.isAvailable else {
            throw GraphChatIntentInterpreterError(
                code: .unavailable,
                message:
                    "Der deterministische Semantic-Interpreter ist nicht verfügbar."
            )
        }
        requests.append(request)
        do {
            if delayNanoseconds > 0 {
                try await Task.sleep(
                    nanoseconds: delayNanoseconds
                )
            }
            try Task.checkCancellation()
            let step = steps.isEmpty
                ? .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .openEnded,
                        responseLanguage:
                            request.responseLanguage
                    )
                )
                : steps.removeFirst()
            switch step {
            case .draft(let draft):
                return draft
            case .failure(let error):
                throw error
            case .waitForCancellation:
                try await Task.sleep(
                    nanoseconds: UInt64.max
                )
                throw CancellationError()
            }
        } catch is CancellationError {
            cancellationCount += 1
            throw GraphChatIntentInterpreterError.cancelled()
        }
    }

    func snapshot()
        -> FakeGraphChatIntentInterpreterSnapshot
    {
        FakeGraphChatIntentInterpreterSnapshot(
            requests: requests,
            cancellationCount: cancellationCount
        )
    }
}
