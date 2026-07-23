//
//  GraphChatAccessControl.swift
//  BrainMesh
//
//  Deterministic product access policy plus defense-in-depth execution authorization.
//

import Foundation

nonisolated struct GraphChatExecutionAuthorization: Hashable, Sendable {
    let activeGraphID: UUID?
    let authorizedScope: GraphChatScope?
    let hasProEntitlement: Bool
    let isGraphUnlocked: Bool

    static let denied = GraphChatExecutionAuthorization(
        activeGraphID: nil,
        authorizedScope: nil,
        hasProEntitlement: false,
        isGraphUnlocked: false
    )

    func permits(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> Bool {
        activeGraphID == graphScope.graphID
            && authorizedScope == chatScope
            && chatScope.graphScope == graphScope
            && hasProEntitlement
            && isGraphUnlocked
    }
}

@MainActor
final class GraphChatExecutionGate {
    private var authorization: GraphChatExecutionAuthorization = .denied

    func update(_ authorization: GraphChatExecutionAuthorization) {
        self.authorization = authorization
    }

    func revoke() {
        authorization = .denied
    }

    func permits(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> Bool {
        authorization.permits(
            graphScope: graphScope,
            chatScope: chatScope
        )
    }
}

actor AccessControlledGraphChatOrchestrator: GraphChatOrchestrating {
    private let base: any GraphChatOrchestrating
    private let gate: GraphChatExecutionGate

    init(
        base: any GraphChatOrchestrating,
        gate: GraphChatExecutionGate
    ) {
        self.base = base
        self.gate = gate
    }

    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream {
        guard await gate.permits(
            graphScope: graphScope,
            chatScope: chatScope
        ) else {
            let pair = GraphChatEventStream.makeStream()
            pair.continuation.yield(
                .failure(
                    GraphChatError(
                        code: .unavailable,
                        message: "Graph Chat ist für diesen Graphen nicht freigeschaltet.",
                        recoverySuggestion: "Prüfe Pro-Status, aktiven Graphen, Graph-Sperre, Modell und lokalen Index."
                    )
                )
            )
            pair.continuation.finish()
            return pair.stream
        }

        return await base.streamAnswer(
            question: question,
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    func cancelCurrentGeneration() async {
        await base.cancelCurrentGeneration()
    }

    func discardSession() async {
        await base.discardSession()
    }

    func discardSession(
        reason: GraphChatConversationResetReason
    ) async {
        await base.discardSession(reason: reason)
    }

    func conversationStateSnapshot() async -> GraphChatConversationState? {
        await base.conversationStateSnapshot()
    }

    func resolveAnswerPresentation(
        artifactIDs: [GraphChatAnswerArtifactID],
        evidence: [GraphEvidence],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatAnswerPresentationResolution {
        guard await gate.permits(
            graphScope: graphScope,
            chatScope: chatScope
        ) else {
            return .unavailable(
                graphScope: graphScope,
                chatScope: chatScope,
                requestedArtifactIDs: artifactIDs,
                reason: .scopeMismatch
            )
        }
        return await base.resolveAnswerPresentation(
            artifactIDs: artifactIDs,
            evidence: evidence,
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    func restoreConversationState(
        from checkpoint: GraphChatConversationCheckpoint
    ) async throws {
        guard await gate.permits(
            graphScope: checkpoint.graphScope,
            chatScope: checkpoint.chatScope
        ) else {
            throw GraphChatError(
                code: .unavailable,
                message: "Graph Chat ist für diesen Graphen nicht freigeschaltet.",
                recoverySuggestion: "Prüfe Pro-Status, aktiven Graphen, Graph-Sperre, Modell und lokalen Index."
            )
        }
        try await base.restoreConversationState(from: checkpoint)
    }
}

nonisolated enum GraphChatEntitlementAccessState: Hashable, Sendable {
    case unknown
    case free
    case pro
}

nonisolated enum GraphChatAccessRoute: Hashable, Sendable {
    case noActiveGraph
    case graphNotFound
    case entitlementLoading
    case proRequired
    case graphLocked
    case modelAvailabilityLoading
    case modelUnavailable(GraphChatModelUnavailableReason)
    case modelAvailabilityFailed(String)
    case indexPreparing(GraphChatIndexPresentationState)
    case reconciliationRunning(documentCount: Int?)
    case indexUnavailable(message: String)
    case ready
}

nonisolated struct GraphChatAccessPolicyInput: Hashable, Sendable {
    let activeGraphID: UUID?
    let graphExists: Bool
    let requestedScope: GraphChatScope?
    let entitlement: GraphChatEntitlementAccessState
    let graphRequiresUnlock: Bool
    let isGraphUnlocked: Bool
    let availability: GraphChatAvailabilityPresentationState
    let indexState: GraphChatIndexPresentationState
    let isReconciliationRunning: Bool
    let isGenerationRunning: Bool

    init(
        activeGraphID: UUID?,
        graphExists: Bool,
        requestedScope: GraphChatScope?,
        entitlement: GraphChatEntitlementAccessState,
        graphRequiresUnlock: Bool,
        isGraphUnlocked: Bool,
        availability: GraphChatAvailabilityPresentationState,
        indexState: GraphChatIndexPresentationState,
        isReconciliationRunning: Bool = false,
        isGenerationRunning: Bool = false
    ) {
        self.activeGraphID = activeGraphID
        self.graphExists = graphExists
        self.requestedScope = requestedScope
        self.entitlement = entitlement
        self.graphRequiresUnlock = graphRequiresUnlock
        self.isGraphUnlocked = isGraphUnlocked
        self.availability = availability
        self.indexState = indexState
        self.isReconciliationRunning = isReconciliationRunning
        self.isGenerationRunning = isGenerationRunning
    }
}

nonisolated struct GraphChatAccessDecision: Hashable, Sendable {
    let route: GraphChatAccessRoute
    let canPresentChat: Bool
    let canStartGeneration: Bool
    let canCancelGeneration: Bool
    let usesIndexFallback: Bool

    static let denied = GraphChatAccessDecision(
        route: .noActiveGraph,
        canPresentChat: false,
        canStartGeneration: false,
        canCancelGeneration: false,
        usesIndexFallback: false
    )

    var executionIsAuthorized: Bool {
        canPresentChat
    }
}

nonisolated enum GraphChatAccessPolicy {
    static func evaluate(
        _ input: GraphChatAccessPolicyInput
    ) -> GraphChatAccessDecision {
        guard let activeGraphID = input.activeGraphID,
              let requestedScope = input.requestedScope,
              requestedScope.graphScope.graphID == activeGraphID else {
            return decision(route: .noActiveGraph)
        }

        guard input.graphExists else {
            return decision(route: .graphNotFound)
        }

        if input.graphRequiresUnlock && input.isGraphUnlocked == false {
            return decision(route: .graphLocked)
        }

        switch input.entitlement {
        case .unknown:
            return decision(route: .entitlementLoading)
        case .free:
            return decision(route: .proRequired)
        case .pro:
            break
        }

        switch input.availability {
        case .loading:
            return decision(route: .modelAvailabilityLoading)
        case .available:
            break
        case .unavailable(let reason):
            return decision(route: .modelUnavailable(reason))
        case .failed(let message):
            return decision(route: .modelAvailabilityFailed(message))
        }

        if input.isReconciliationRunning {
            return decision(
                route: .reconciliationRunning(
                    documentCount: input.indexState.documentCount
                )
            )
        }

        let usesIndexFallback: Bool
        switch input.indexState {
        case .loading, .notReady, .building, .stale:
            return decision(route: .indexPreparing(input.indexState))
        case .reconciling(let documentCount):
            return decision(
                route: .reconciliationRunning(documentCount: documentCount)
            )
        case .ready:
            usesIndexFallback = false
        case .failed(let message, let isUsable, _):
            guard isUsable else {
                return decision(route: .indexUnavailable(message: message))
            }
            usesIndexFallback = true
        }

        return GraphChatAccessDecision(
            route: .ready,
            canPresentChat: true,
            canStartGeneration: input.isGenerationRunning == false,
            canCancelGeneration: input.isGenerationRunning,
            usesIndexFallback: usesIndexFallback
        )
    }

    static func updatingGenerationState(
        in decision: GraphChatAccessDecision,
        isGenerationRunning: Bool
    ) -> GraphChatAccessDecision {
        guard decision.route == .ready else {
            return decision
        }
        return GraphChatAccessDecision(
            route: .ready,
            canPresentChat: true,
            canStartGeneration: isGenerationRunning == false,
            canCancelGeneration: isGenerationRunning,
            usesIndexFallback: decision.usesIndexFallback
        )
    }

    private static func decision(
        route: GraphChatAccessRoute
    ) -> GraphChatAccessDecision {
        GraphChatAccessDecision(
            route: route,
            canPresentChat: false,
            canStartGeneration: false,
            canCancelGeneration: false,
            usesIndexFallback: false
        )
    }
}

/// Compatibility façade retained for existing callers and tests. All decisions are delegated to
/// `GraphChatAccessPolicy`; no independent routing rules live here.
nonisolated enum GraphChatAccessRouter {
    static func route(
        input: GraphChatAccessPolicyInput
    ) -> GraphChatAccessRoute {
        GraphChatAccessPolicy.evaluate(input).route
    }

    static func route(
        activeGraphID: UUID?,
        requestedScope: GraphChatScope?,
        entitlement: GraphChatEntitlementAccessState,
        graphRequiresUnlock: Bool,
        isGraphUnlocked: Bool,
        availability: GraphChatAvailabilityPresentationState
    ) -> GraphChatAccessRoute {
        GraphChatAccessPolicy.evaluate(
            GraphChatAccessPolicyInput(
                activeGraphID: activeGraphID,
                graphExists: activeGraphID != nil,
                requestedScope: requestedScope,
                entitlement: entitlement,
                graphRequiresUnlock: graphRequiresUnlock,
                isGraphUnlocked: isGraphUnlocked,
                availability: availability,
                indexState: .ready(documentCount: nil)
            )
        ).route
    }
}
