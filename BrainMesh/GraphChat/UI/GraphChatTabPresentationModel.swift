//
//  GraphChatTabPresentationModel.swift
//  BrainMesh
//
//  Value-only presentation and task identities for the Graph Chat tab composition root.
//

import Foundation

nonisolated enum GraphChatTabHost: Hashable, Sendable {
    case rootTab
    case canvasInspector
}

nonisolated enum GraphChatHostVisibilityPolicy {
    static func isVisible(
        host: GraphChatTabHost,
        selectedTab: RootTab,
        isSceneActive: Bool,
        isMounted: Bool
    ) -> Bool {
        guard isMounted, isSceneActive else { return false }
        switch host {
        case .rootTab:
            return selectedTab == .chat
        case .canvasInspector:
            return selectedTab == .graph
        }
    }
}

nonisolated struct GraphChatVisibilityTaskIdentity<Base>:
    Hashable,
    Sendable
where Base: Hashable & Sendable {
    let base: Base
    let isVisible: Bool
}

nonisolated struct GraphChatTabActiveGraphPresentation: Hashable, Sendable {
    let id: UUID
    let name: String
    let isProtected: Bool
}

nonisolated struct GraphChatTabPresentedSessionIdentity: Hashable, Sendable {
    let requestID: UUID
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let launchContext: GraphChatLaunchContext
}

nonisolated struct GraphChatTabRuntimeTaskIdentity: Hashable, Sendable {
    let activeGraphIDString: String
    let entitlement: GraphChatEntitlementAccessState
    let lockRevision: UInt64
}

nonisolated struct GraphChatTabAccessTaskIdentity: Hashable, Sendable {
    let runtime: GraphChatTabRuntimeTaskIdentity
    let sourceRequestID: UUID?
    let sourceScope: GraphChatScope?
    let sourceLaunchContext: GraphChatLaunchContext?
    let effectiveRequestID: UUID?
    let effectiveScope: GraphChatScope?
    let effectiveLaunchContext: GraphChatLaunchContext?
    let availability: GraphChatAvailabilityPresentationState
    let indexState: GraphChatIndexPresentationState
    let isGenerationRunning: Bool
    let route: GraphChatAccessRoute
}

nonisolated struct GraphChatTabLaunchValidationTaskIdentity: Hashable, Sendable {
    let activeGraphIDString: String
    let sourceRequestID: UUID?
    let sourceScope: GraphChatScope?
    let sourceLaunchContext: GraphChatLaunchContext?
    let lockRevision: UInt64
}

nonisolated struct GraphChatTabFreePreviewPresentation: Hashable, Sendable {
    let showsDraft: Bool
    let suggestions: [GraphChatEmptyStateSuggestion]
    let errorMessage: String?
}

nonisolated enum GraphChatTabReadyContentState: Hashable, Sendable {
    case chat(requestID: UUID)
    case preparingSession
    case graphUnavailable
}

nonisolated enum GraphChatTabAccessContentState: Hashable, Sendable {
    case noActiveGraph
    case graphNotFound
    case entitlementLoading
    case proRequired(GraphChatTabFreePreviewPresentation)
    case graphLocked
    case modelAvailabilityLoading
    case modelUnavailable(GraphChatModelUnavailableReason)
    case modelAvailabilityFailed
    case indexPreparing(GraphChatIndexPresentationState)
    case reconciliationRunning(GraphChatIndexPresentationState)
    case indexUnavailable(message: String)
    case ready(GraphChatTabReadyContentState)

    static func make(
        route: GraphChatAccessRoute,
        indexState: GraphChatIndexPresentationState,
        freePreview: GraphChatTabFreePreviewPresentation,
        readyState: GraphChatTabReadyContentState
    ) -> GraphChatTabAccessContentState {
        switch route {
        case .noActiveGraph:
            return .noActiveGraph
        case .graphNotFound:
            return .graphNotFound
        case .entitlementLoading:
            return .entitlementLoading
        case .proRequired:
            return .proRequired(freePreview)
        case .graphLocked:
            return .graphLocked
        case .modelAvailabilityLoading:
            return .modelAvailabilityLoading
        case .modelUnavailable(let reason):
            return .modelUnavailable(reason)
        case .modelAvailabilityFailed:
            return .modelAvailabilityFailed
        case .indexPreparing(let state):
            return .indexPreparing(state)
        case .reconciliationRunning:
            return .reconciliationRunning(indexState)
        case .indexUnavailable(let message):
            return .indexUnavailable(message: message)
        case .ready:
            return .ready(readyState)
        }
    }
}

nonisolated enum GraphChatTabContentState: Hashable, Sendable {
    case launchValidationPending
    case invalidLaunch(GraphChatTabLaunchValidationErrorPresentation)
    case access(GraphChatTabAccessContentState)
}

nonisolated struct GraphChatTabPresentationModel: Hashable, Sendable {
    let activeGraphID: UUID?
    let activeGraph: GraphChatTabActiveGraphPresentation?
    let sourceRequest: GraphChatLaunchRequest?
    let effectiveRequest: GraphChatLaunchRequest?
    let isGraphUnlocked: Bool
    let accessDecision: GraphChatAccessDecision
    let contentState: GraphChatTabContentState
    let runtimeTaskIdentity: GraphChatTabRuntimeTaskIdentity
    let accessTaskIdentity: GraphChatTabAccessTaskIdentity
    let launchValidationTaskIdentity: GraphChatTabLaunchValidationTaskIdentity
    let language: GraphChatResponseLanguage

    init(
        activeGraphIDString: String,
        activeGraph: GraphChatTabActiveGraphPresentation?,
        sourceRequest: GraphChatLaunchRequest?,
        launchValidationState: GraphChatTabLaunchValidationState,
        entitlement: GraphChatEntitlementAccessState,
        lockRevision: UInt64,
        graphUnlockGranted: Bool,
        availability: GraphChatAvailabilityPresentationState,
        indexState: GraphChatIndexPresentationState,
        isReconciliationRunning: Bool,
        isGenerationRunning: Bool,
        presentedSessionIdentity: GraphChatTabPresentedSessionIdentity?,
        previewSuggestionsSnapshot: GraphChatSuggestionsSnapshot?,
        previewErrorMessage: String?,
        language: GraphChatResponseLanguage
    ) {
        let activeGraphID = UUID(uuidString: activeGraphIDString)
        let isGraphUnlocked = GraphChatTabAccessCoordinator.isGraphUnlocked(
            activeGraph: activeGraph,
            graphUnlockGranted: graphUnlockGranted
        )
        let effectiveRequest = launchValidationState.effectiveRequest(
            matching: sourceRequest
        )
        let accessDecision = GraphChatTabAccessCoordinator.decision(
            activeGraphID: activeGraphID,
            activeGraph: activeGraph,
            requestedScope: effectiveRequest?.scope ?? sourceRequest?.scope,
            entitlement: entitlement,
            isGraphUnlocked: isGraphUnlocked,
            availability: availability,
            indexState: indexState,
            isReconciliationRunning: isReconciliationRunning,
            isGenerationRunning: isGenerationRunning
        )
        let visibleSuggestions: [GraphChatEmptyStateSuggestion]
        if previewSuggestionsSnapshot?.key.graphID == activeGraphID {
            visibleSuggestions = Array(
                (previewSuggestionsSnapshot?.suggestions ?? [])
                    .prefix(4)
            )
        } else {
            visibleSuggestions = []
        }
        let freePreview = GraphChatTabFreePreviewPresentation(
            showsDraft: effectiveRequest != nil,
            suggestions: visibleSuggestions,
            errorMessage: visibleSuggestions.isEmpty ? previewErrorMessage : nil
        )
        let readyState = Self.readyState(
            activeGraph: activeGraph,
            request: effectiveRequest,
            presentedSessionIdentity: presentedSessionIdentity
        )
        let accessContent = GraphChatTabAccessContentState.make(
            route: accessDecision.route,
            indexState: indexState,
            freePreview: freePreview,
            readyState: readyState
        )
        let contentState: GraphChatTabContentState
        if launchValidationState.isPending(matching: sourceRequest), activeGraph != nil {
            contentState = .launchValidationPending
        } else if let validationError = launchValidationState.errorPresentation(
            matching: sourceRequest
        ) {
            contentState = .invalidLaunch(validationError)
        } else {
            contentState = .access(accessContent)
        }
        let runtimeTaskIdentity = GraphChatTabRuntimeTaskIdentity(
            activeGraphIDString: activeGraphIDString,
            entitlement: entitlement,
            lockRevision: lockRevision
        )

        self.activeGraphID = activeGraphID
        self.activeGraph = activeGraph
        self.sourceRequest = sourceRequest
        self.effectiveRequest = effectiveRequest
        self.isGraphUnlocked = isGraphUnlocked
        self.accessDecision = accessDecision
        self.contentState = contentState
        self.runtimeTaskIdentity = runtimeTaskIdentity
        self.accessTaskIdentity = GraphChatTabAccessTaskIdentity(
            runtime: runtimeTaskIdentity,
            sourceRequestID: sourceRequest?.id,
            sourceScope: sourceRequest?.scope,
            sourceLaunchContext: sourceRequest?.context,
            effectiveRequestID: effectiveRequest?.id,
            effectiveScope: effectiveRequest?.scope,
            effectiveLaunchContext: effectiveRequest?.context,
            availability: availability,
            indexState: indexState,
            isGenerationRunning: isGenerationRunning,
            route: accessDecision.route
        )
        self.launchValidationTaskIdentity = GraphChatTabLaunchValidationTaskIdentity(
            activeGraphIDString: activeGraphIDString,
            sourceRequestID: sourceRequest?.id,
            sourceScope: sourceRequest?.scope,
            sourceLaunchContext: sourceRequest?.context,
            lockRevision: lockRevision
        )
        self.language = language
    }

    private static func readyState(
        activeGraph: GraphChatTabActiveGraphPresentation?,
        request: GraphChatLaunchRequest?,
        presentedSessionIdentity: GraphChatTabPresentedSessionIdentity?
    ) -> GraphChatTabReadyContentState {
        guard let activeGraph, let request else {
            return .graphUnavailable
        }
        guard let presentedSessionIdentity,
              presentedSessionIdentity.requestID == request.id,
              presentedSessionIdentity.graphScope.graphID == activeGraph.id,
              presentedSessionIdentity.chatScope == request.scope,
              presentedSessionIdentity.launchContext == request.context else {
            return .preparingSession
        }
        return .chat(requestID: request.id)
    }
}
