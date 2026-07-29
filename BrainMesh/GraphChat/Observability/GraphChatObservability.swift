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
    case scopeExpansionPrevented
    case staleResultSetRejected
    case staleNodeDiscarded
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

nonisolated enum GraphChatSemanticIntentLifecycleEvent:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case interpreterStarted
    case interpreterRetry
    case draftAccepted
    case draftRejected
    case findIntentCompiled
    case listIntentCompiled
    case filteredCollectionCompiled
    case countIntentCompiled
    case groupIntentCompiled
    case refinementIntentCompiled
    case nodeDetailsCompiled
    case sameEntityComparisonCompiled
    case structuralComparisonCompiled
    case comparisonRejected
    case graphOverviewCompiled
    case graphHealthCompiled
    case staleNodeDiscarded
    case typeConflict
    case valueParsingRejected
    case scopeExpansionPrevented
    case staleResultSetRejected
    case clarificationRequired
    case legacyProviderFallback
    case answerProviderStarted
    case cancellation
}

nonisolated struct GraphChatSemanticIntentMetric:
    Hashable,
    Sendable
{
    let event: GraphChatSemanticIntentLifecycleEvent
    let family: GraphChatSemanticIntentFamily?
    let interpreterCallCount: Int
    let answerProviderCallCount: Int

    init(
        event: GraphChatSemanticIntentLifecycleEvent,
        family: GraphChatSemanticIntentFamily?,
        interpreterCallCount: Int = 0,
        answerProviderCallCount: Int = 0
    ) {
        self.event = event
        self.family = family
        self.interpreterCallCount = max(
            0,
            interpreterCallCount
        )
        self.answerProviderCallCount = max(
            0,
            answerProviderCallCount
        )
    }
}

nonisolated enum GraphChatTypedPlannerDraftOutcome:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case accepted
    case rejected
    case unrecognized
    case openEnded
    case interpreterUnavailable
}

nonisolated enum GraphChatTypedPlannerCancellationStage:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case preflight
    case foundationalFastPath
    case semanticInterpreter
    case localExecution
    case providerResources
    case legacyProvider
    case finalization
    case commit
    case correction
    case unknown
}

nonisolated enum GraphChatTypedPlannerEvent:
    Hashable,
    Sendable
{
    case foundationalFastPath(
        GraphChatFoundationalIntentKind
    )
    case semanticInterpreter
    case draftOutcome(
        GraphChatTypedPlannerDraftOutcome,
        GraphChatSemanticIntentFamily?
    )
    case localIntent(GraphChatTypedIntentKind)
    case legacyProviderFallback(
        GraphChatLegacyProviderFallbackReason
    )
    case interpreterRetry
    case clarification(
        GraphChatSemanticIntentFamily?
    )
    case correctionRerun
    case terminalOutcome(GraphChatRequestOutcome)
    case cancellation(
        GraphChatTypedPlannerCancellationStage
    )
}

nonisolated struct GraphChatTypedPlannerMetric:
    Hashable,
    Sendable
{
    let event: GraphChatTypedPlannerEvent
}

nonisolated enum GraphChatIntentInterpretationLifecycleEvent:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case created
    case displayed
    case discardedPresentationViolation
    case correctionEditorOpened
    case correctionCancelled
    case correctionValidated
    case correctionStale
    case localCorrectionRerunStarted
    case localCorrectionRerunCommitted
    case localCorrectionRerunRolledBack
}

nonisolated struct GraphChatIntentInterpretationMetric:
    Hashable,
    Sendable
{
    let event:
        GraphChatIntentInterpretationLifecycleEvent
}

nonisolated enum GraphChatObservabilityEvent: Hashable, Sendable {
    case request(GraphChatRequestMetric)
    case availability(GraphChatAvailabilityMetricState)
    case toolRepair(GraphChatToolRepairMetric)
    case authoritativeFact(GraphChatAuthoritativeFactMetric)
    case localIntent(GraphChatLocalIntentMetric)
    case semanticIntent(GraphChatSemanticIntentMetric)
    case typedPlanner(GraphChatTypedPlannerMetric)
    case intentInterpretation(
        GraphChatIntentInterpretationMetric
    )
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
        case .semanticIntent(let metric):
            let family = metric.family?.rawValue ?? "none"
            BMLog.chat.info(
                "Semantic intent event=\(metric.event.rawValue, privacy: .public) family=\(family, privacy: .public) interpreterCalls=\(metric.interpreterCallCount) answerProviderCalls=\(metric.answerProviderCallCount)"
            )
        case .typedPlanner(let metric):
            let values = typedPlannerLogValues(
                metric.event
            )
            BMLog.chat.info(
                "Typed planner event=\(values.event, privacy: .public) detail=\(values.detail, privacy: .public)"
            )
        case .intentInterpretation(let metric):
            BMLog.chat.info(
                "Intent interpretation event=\(metric.event.rawValue, privacy: .public)"
            )
        }
    }

    private func typedPlannerLogValues(
        _ event: GraphChatTypedPlannerEvent
    ) -> (event: String, detail: String) {
        switch event {
        case .foundationalFastPath(let kind):
            return (
                "foundationalFastPath",
                kind.rawValue
            )
        case .semanticInterpreter:
            return (
                "semanticInterpreter",
                "none"
            )
        case .draftOutcome(
            let outcome,
            let family
        ):
            return (
                "draftOutcome",
                "\(outcome.rawValue):\(family?.rawValue ?? "none")"
            )
        case .localIntent(let kind):
            return (
                "localIntent",
                kind.rawValue
            )
        case .legacyProviderFallback(let reason):
            return (
                "legacyProviderFallback",
                reason.rawValue
            )
        case .interpreterRetry:
            return (
                "interpreterRetry",
                "compact"
            )
        case .clarification(let family):
            return (
                "clarification",
                family?.rawValue ?? "none"
            )
        case .correctionRerun:
            return (
                "correctionRerun",
                "local"
            )
        case .terminalOutcome(let outcome):
            return (
                "terminalOutcome",
                outcome.rawValue
            )
        case .cancellation(let stage):
            return (
                "cancellation",
                stage.rawValue
            )
        }
    }
}

actor NoOpGraphChatObservabilityRecorder: GraphChatObservabilityRecording {
    func record(_ event: GraphChatObservabilityEvent) {}
}
