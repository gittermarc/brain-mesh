//
//  GraphChatGenerationMetricFactory.swift
//  BrainMesh
//
//  Pure terminal classification and content-free request metric creation.
//

import Foundation

nonisolated enum GraphChatGenerationEventClassifier {
    static func outcome(
        for event: GraphChatStreamEvent
    ) -> GraphChatGenerationOutcome? {
        switch event {
        case .completed(let answer):
            if case .noResults = answer.state {
                return .noResults
            }
            return .completed
        case .cancelled:
            return .cancelled
        case .failure(let error):
            return error.code == .cancelled
                ? .cancelled
                : .failure(error)
        case .started, .toolActivity, .partialAnswer:
            return nil
        }
    }

    static func isTerminal(_ event: GraphChatStreamEvent) -> Bool {
        outcome(for: event) != nil
    }
}

nonisolated enum GraphChatGenerationMetricFactory {
    static func cancellationMetric(
        for request: GraphChatGenerationRequest,
        durationMilliseconds: Double,
        toolCount: Int = 0,
        toolKinds: Set<GraphChatToolKind> = []
    ) -> GraphChatRequestMetric {
        GraphChatRequestMetric(
            durationMilliseconds: durationMilliseconds,
            toolCount: toolCount,
            toolKinds: toolKinds,
            evidenceCount: 0,
            usedIndexFallback: request.usedIndexFallback,
            outcome: .cancelled,
            errorCode: .cancelled
        )
    }

    static func terminalMetric(
        for event: GraphChatStreamEvent,
        request: GraphChatGenerationRequest,
        durationMilliseconds: Double,
        toolCount: Int,
        toolKinds: Set<GraphChatToolKind>
    ) -> GraphChatRequestMetric? {
        switch event {
        case .completed(let answer):
            return GraphChatRequestMetric(
                durationMilliseconds: durationMilliseconds,
                toolCount: toolCount,
                toolKinds: toolKinds,
                evidenceCount: answer.evidence.count,
                usedIndexFallback: request.usedIndexFallback,
                outcome: {
                    if case .noResults = answer.state {
                        return .noResults
                    }
                    return .completed
                }(),
                errorCode: nil
            )
        case .cancelled:
            return cancellationMetric(
                for: request,
                durationMilliseconds: durationMilliseconds,
                toolCount: toolCount,
                toolKinds: toolKinds
            )
        case .failure(let error):
            return GraphChatRequestMetric(
                durationMilliseconds: durationMilliseconds,
                toolCount: toolCount,
                toolKinds: toolKinds,
                evidenceCount: 0,
                usedIndexFallback: request.usedIndexFallback,
                outcome: error.code == .cancelled ? .cancelled : .failed,
                errorCode: error.code
            )
        case .started, .toolActivity, .partialAnswer:
            return nil
        }
    }
}
