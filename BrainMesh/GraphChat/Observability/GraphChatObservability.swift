//
//  GraphChatObservability.swift
//  BrainMesh
//
//  Content-free technical metrics for the read-only on-device graph chat flow.
//

import Foundation
import os

nonisolated enum GraphChatAvailabilityMetricState: String, CaseIterable, Hashable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailableUnknown
    case technicalFailure
}

nonisolated enum GraphChatRequestOutcome: String, CaseIterable, Hashable, Sendable {
    case completed
    case noResults
    case cancelled
    case failed
}

nonisolated struct GraphChatRequestMetric: Hashable, Sendable {
    let durationMilliseconds: Double
    let toolCount: Int
    let toolKinds: Set<GraphChatToolKind>
    let evidenceCount: Int
    let usedIndexFallback: Bool
    let outcome: GraphChatRequestOutcome
    let errorCode: GraphChatErrorCode?

    init(
        durationMilliseconds: Double,
        toolCount: Int,
        toolKinds: Set<GraphChatToolKind>,
        evidenceCount: Int,
        usedIndexFallback: Bool,
        outcome: GraphChatRequestOutcome,
        errorCode: GraphChatErrorCode?
    ) {
        self.durationMilliseconds = max(0, durationMilliseconds)
        self.toolCount = max(0, toolCount)
        self.toolKinds = toolKinds
        self.evidenceCount = max(0, evidenceCount)
        self.usedIndexFallback = usedIndexFallback
        self.outcome = outcome
        self.errorCode = errorCode
    }
}

nonisolated enum GraphChatObservabilityEvent: Hashable, Sendable {
    case request(GraphChatRequestMetric)
    case availability(GraphChatAvailabilityMetricState)
}

nonisolated protocol GraphChatObservabilityRecording: Sendable {
    func record(_ event: GraphChatObservabilityEvent) async
}

actor GraphChatTechnicalObservabilityRecorder: GraphChatObservabilityRecording {
    func record(_ event: GraphChatObservabilityEvent) {
        switch event {
        case .availability(let availability):
            BMLog.chat.info(
                "Availability state=\(availability.rawValue, privacy: .public)"
            )
        case .request(let metric):
            let toolTypes = metric.toolKinds
                .map(\.rawValue)
                .sorted()
                .joined(separator: ",")
            let errorCode = metric.errorCode?.rawValue ?? "none"
            BMLog.chat.info(
                "Request finished outcome=\(metric.outcome.rawValue, privacy: .public) durationMS=\(metric.durationMilliseconds, format: .fixed(precision: 2)) toolCount=\(metric.toolCount) toolTypes=\(toolTypes, privacy: .public) evidenceCount=\(metric.evidenceCount) indexFallback=\(metric.usedIndexFallback) errorCode=\(errorCode, privacy: .public)"
            )
        }
    }
}

actor NoOpGraphChatObservabilityRecorder: GraphChatObservabilityRecording {
    func record(_ event: GraphChatObservabilityEvent) {}
}
