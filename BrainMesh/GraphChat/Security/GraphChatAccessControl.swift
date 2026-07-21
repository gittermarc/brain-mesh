//
//  GraphChatAccessControl.swift
//  BrainMesh
//
//  Defense-in-depth authorization immediately in front of model and tool execution.
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
                        recoverySuggestion: "Prüfe Pro-Status, aktiven Graphen und Graph-Sperre."
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
}

nonisolated enum GraphChatEntitlementAccessState: Hashable, Sendable {
    case unknown
    case free
    case pro
}

nonisolated enum GraphChatAccessRoute: Hashable, Sendable {
    case noActiveGraph
    case entitlementLoading
    case proRequired
    case graphLocked
    case modelAvailabilityLoading
    case modelUnavailable(GraphChatModelUnavailableReason)
    case modelAvailabilityFailed(String)
    case ready
}

nonisolated enum GraphChatAccessRouter {
    static func route(
        activeGraphID: UUID?,
        requestedScope: GraphChatScope?,
        entitlement: GraphChatEntitlementAccessState,
        graphRequiresUnlock: Bool,
        isGraphUnlocked: Bool,
        availability: GraphChatAvailabilityPresentationState
    ) -> GraphChatAccessRoute {
        guard let activeGraphID,
              let requestedScope,
              requestedScope.graphScope.graphID == activeGraphID else {
            return .noActiveGraph
        }

        if graphRequiresUnlock && isGraphUnlocked == false {
            return .graphLocked
        }

        switch entitlement {
        case .unknown:
            return .entitlementLoading
        case .free:
            return .proRequired
        case .pro:
            break
        }

        switch availability {
        case .loading:
            return .modelAvailabilityLoading
        case .available:
            return .ready
        case .unavailable(let reason):
            return .modelUnavailable(reason)
        case .failed(let message):
            return .modelAvailabilityFailed(message)
        }
    }
}
