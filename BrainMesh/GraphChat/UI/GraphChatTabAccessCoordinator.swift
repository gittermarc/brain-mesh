//
//  GraphChatTabAccessCoordinator.swift
//  BrainMesh
//
//  Stateless access preparation and session synchronization for the Graph Chat tab.
//

import Foundation


nonisolated struct GraphChatTabRuntimeAccessContext: Hashable, Sendable {
    let activeGraphID: UUID?
    let entitlement: GraphChatEntitlementAccessState
    let isGraphUnlocked: Bool
}

nonisolated struct GraphChatTabSessionAccessContext: Hashable, Sendable {
    let decision: GraphChatAccessDecision
    let activeGraphID: UUID?
    let request: GraphChatLaunchRequest?
    let isGraphUnlocked: Bool
}

nonisolated enum GraphChatTabAccessCoordinator {
    @MainActor
    static func entitlementAccessState(
        for entitlement: ProEntitlementStore.EntitlementState
    ) -> GraphChatEntitlementAccessState {
        switch entitlement {
        case .unknown:
            return .unknown
        case .free:
            return .free
        case .pro:
            return .pro
        }
    }

    static func isGraphUnlocked(
        activeGraph: GraphChatTabActiveGraphPresentation?,
        graphUnlockGranted: Bool
    ) -> Bool {
        guard let activeGraph else {
            return false
        }
        return activeGraph.isProtected == false || graphUnlockGranted
    }

    static func policyInput(
        activeGraphID: UUID?,
        activeGraph: GraphChatTabActiveGraphPresentation?,
        requestedScope: GraphChatScope?,
        entitlement: GraphChatEntitlementAccessState,
        isGraphUnlocked: Bool,
        availability: GraphChatAvailabilityPresentationState,
        indexState: GraphChatIndexPresentationState,
        isReconciliationRunning: Bool,
        isGenerationRunning: Bool
    ) -> GraphChatAccessPolicyInput {
        GraphChatAccessPolicyInput(
            activeGraphID: activeGraphID,
            graphExists: activeGraph != nil,
            requestedScope: requestedScope,
            entitlement: entitlement,
            graphRequiresUnlock: activeGraph?.isProtected == true,
            isGraphUnlocked: isGraphUnlocked,
            availability: availability,
            indexState: indexState,
            isReconciliationRunning: isReconciliationRunning,
            isGenerationRunning: isGenerationRunning
        )
    }

    static func decision(
        activeGraphID: UUID?,
        activeGraph: GraphChatTabActiveGraphPresentation?,
        requestedScope: GraphChatScope?,
        entitlement: GraphChatEntitlementAccessState,
        isGraphUnlocked: Bool,
        availability: GraphChatAvailabilityPresentationState,
        indexState: GraphChatIndexPresentationState,
        isReconciliationRunning: Bool,
        isGenerationRunning: Bool
    ) -> GraphChatAccessDecision {
        GraphChatAccessPolicy.evaluate(
            policyInput(
                activeGraphID: activeGraphID,
                activeGraph: activeGraph,
                requestedScope: requestedScope,
                entitlement: entitlement,
                isGraphUnlocked: isGraphUnlocked,
                availability: availability,
                indexState: indexState,
                isReconciliationRunning: isReconciliationRunning,
                isGenerationRunning: isGenerationRunning
            )
        )
    }

    static func shouldPreserveDraft(
        for route: GraphChatAccessRoute
    ) -> Bool {
        switch route {
        case .modelAvailabilityLoading, .modelUnavailable, .modelAvailabilityFailed,
             .indexPreparing, .reconciliationRunning, .indexUnavailable, .proRequired,
             .entitlementLoading:
            return true
        case .noActiveGraph, .graphNotFound, .graphLocked, .ready:
            return false
        }
    }

    static func shouldPrepareIndexDuringRuntimeRefresh(
        entitlement: GraphChatEntitlementAccessState,
        isGraphUnlocked: Bool,
        availability: GraphChatAvailabilityPresentationState
    ) -> Bool {
        entitlement == .pro
            && isGraphUnlocked
            && availability.isAvailable
    }
}

@MainActor
extension GraphChatTabAccessCoordinator {
    static func refreshRuntimeStates(
        sessionStore: GraphChatSessionStore,
        contextProvider: @MainActor () -> GraphChatTabRuntimeAccessContext
    ) async {
        await sessionStore.refreshAvailability()
        let context = contextProvider()
        let mayPrepareIndex = shouldPrepareIndexDuringRuntimeRefresh(
            entitlement: context.entitlement,
            isGraphUnlocked: context.isGraphUnlocked,
            availability: sessionStore.availabilityState
        )
        await sessionStore.refreshIndex(
            for: context.activeGraphID.map { GraphScope(graphID: $0) },
            prepareIfNeeded: mayPrepareIndex
        )
    }

    static func synchronizeSessionAccess(
        sessionStore: GraphChatSessionStore,
        context: GraphChatTabSessionAccessContext,
        currentActiveGraphID: @MainActor () -> UUID?
    ) async {
        await sessionStore.synchronizeAccess(
            decision: context.decision,
            activeGraphID: context.activeGraphID,
            scope: context.request?.scope,
            isGraphUnlocked: context.isGraphUnlocked
        )

        if context.decision.canPresentChat == false,
           sessionStore.hasActiveSession {
            sessionStore.invalidate(
                removeHistory: false,
                preserveDraft: shouldPreserveDraft(for: context.decision.route)
            )
        }

        guard case .indexPreparing(let state) = context.decision.route,
              state.shouldStartPreparation,
              let activeGraphID = currentActiveGraphID() else {
            return
        }
        await sessionStore.refreshIndex(
            for: GraphScope(graphID: activeGraphID),
            prepareIfNeeded: true
        )
    }
}
