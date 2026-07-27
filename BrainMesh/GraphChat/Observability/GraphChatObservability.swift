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

nonisolated enum GraphChatToolRepairOutcome: String, CaseIterable, Hashable, Sendable {
    case offered
    case succeeded
    case failed
    case notAllowed
    case budgetExhausted
}

nonisolated struct GraphChatToolRepairMetric: Hashable, Sendable {
    let outcome: GraphChatToolRepairOutcome
    let tool: GraphChatToolKind
    let reason: GraphChatToolRepairReason?
    let nonRepairableReason: GraphChatToolNonRepairableReason?
    let contextRetryCount: Int

    init(
        outcome: GraphChatToolRepairOutcome,
        tool: GraphChatToolKind,
        reason: GraphChatToolRepairReason?,
        nonRepairableReason: GraphChatToolNonRepairableReason? = nil,
        contextRetryCount: Int
    ) {
        self.outcome = outcome
        self.tool = tool
        self.reason = reason
        self.nonRepairableReason = nonRepairableReason
        self.contextRetryCount = max(0, contextRetryCount)
    }
}

nonisolated enum GraphChatAuthoritativeFactMetric:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case recognized
    case rendered
    case replacedModelText
    case blockedSearchOnlyClaim
    case rejectedMissingValue
    case rejectedAmbiguousCardinality
    case rejectedIntegrityConflict
    case rejectedRevalidation
}

nonisolated enum GraphChatLocalIntentLifecycleEvent:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case foundationalAdapted
    case executionStarted
    case executionCommitted
    case executionRolledBack
    case revalidationRejected
    case cancelledBeforeCommit
}

nonisolated enum GraphChatLocalIntentRevalidationRejection:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case binding
    case scope
    case schemaIdentity
    case compiledAction
}

nonisolated struct GraphChatLocalIntentMetric: Hashable, Sendable {
    let event: GraphChatLocalIntentLifecycleEvent
    let kind: GraphChatTypedIntentKind
    let rejection: GraphChatLocalIntentRevalidationRejection?
}

nonisolated enum GraphChatObservabilityEvent: Hashable, Sendable {
    case request(GraphChatRequestMetric)
    case availability(GraphChatAvailabilityMetricState)
    case toolRepair(GraphChatToolRepairMetric)
    case authoritativeFact(GraphChatAuthoritativeFactMetric)
    case localIntent(GraphChatLocalIntentMetric)
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
        case .toolRepair(let metric):
            let reason = metric.reason?.rawValue ?? "none"
            let nonRepairableReason =
                metric.nonRepairableReason?.rawValue ?? "none"
            BMLog.chat.info(
                "Tool repair outcome=\(metric.outcome.rawValue, privacy: .public) tool=\(metric.tool.rawValue, privacy: .public) reason=\(reason, privacy: .public) nonRepairableReason=\(nonRepairableReason, privacy: .public) contextRetryCount=\(metric.contextRetryCount)"
            )
        case .authoritativeFact(let metric):
            BMLog.chat.info(
                "Authoritative fact outcome=\(metric.rawValue, privacy: .public)"
            )
        case .localIntent(let metric):
            let rejection = metric.rejection?.rawValue ?? "none"
            BMLog.chat.info(
                "Local intent event=\(metric.event.rawValue, privacy: .public) kind=\(metric.kind.rawValue, privacy: .public) rejection=\(rejection, privacy: .public)"
            )
        }
    }
}

actor NoOpGraphChatObservabilityRecorder: GraphChatObservabilityRecording {
    func record(_ event: GraphChatObservabilityEvent) {}
}
