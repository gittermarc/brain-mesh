import Foundation
import Testing
@testable import BrainMesh

struct GraphChatAccessRoutingTests {
    private let graphID = UUID()

    @Test
    func freeAndUnknownEntitlementsNeverReachChat() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))

        #expect(route(scope: scope, entitlement: .free) == .proRequired)
        #expect(route(scope: scope, entitlement: .unknown) == .entitlementLoading)
    }

    @Test
    func protectedGraphRequiresUnlockBeforeAvailability() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let result = GraphChatAccessRouter.route(
            activeGraphID: graphID,
            requestedScope: scope,
            entitlement: .pro,
            graphRequiresUnlock: true,
            isGraphUnlocked: false,
            availability: .available
        )

        #expect(result == .graphLocked)
    }

    @Test
    func proWithUnavailableModelShowsConcreteAvailabilityState() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let result = GraphChatAccessRouter.route(
            activeGraphID: graphID,
            requestedScope: scope,
            entitlement: .pro,
            graphRequiresUnlock: false,
            isGraphUnlocked: true,
            availability: .unavailable(reason: .deviceNotEligible)
        )

        #expect(result == .modelUnavailable(.deviceNotEligible))
    }

    @Test
    func foreignScopeAndMissingGraphAreRejected() {
        let foreignScope = GraphChatScope.entireGraph(
            GraphScope(graphID: UUID())
        )

        #expect(route(scope: foreignScope, entitlement: .pro) == .noActiveGraph)
        #expect(
            GraphChatAccessRouter.route(
                activeGraphID: nil,
                requestedScope: nil,
                entitlement: .pro,
                graphRequiresUnlock: false,
                isGraphUnlocked: true,
                availability: .available
            ) == .noActiveGraph
        )
    }

    @Test
    func protectedGraphLockPrecedesFreePreviewAndMissingScopeIsRejected() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        #expect(
            GraphChatAccessRouter.route(
                activeGraphID: graphID,
                requestedScope: scope,
                entitlement: .free,
                graphRequiresUnlock: true,
                isGraphUnlocked: false,
                availability: .available
            ) == .graphLocked
        )
        #expect(
            GraphChatAccessRouter.route(
                activeGraphID: graphID,
                requestedScope: nil,
                entitlement: .pro,
                graphRequiresUnlock: false,
                isGraphUnlocked: true,
                availability: .available
            ) == .noActiveGraph
        )
    }

    @Test
    func onlyProUnlockedAvailableRouteIsReady() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        #expect(route(scope: scope, entitlement: .pro) == .ready)
    }

    private func route(
        scope: GraphChatScope,
        entitlement: GraphChatEntitlementAccessState
    ) -> GraphChatAccessRoute {
        GraphChatAccessRouter.route(
            activeGraphID: graphID,
            requestedScope: scope,
            entitlement: entitlement,
            graphRequiresUnlock: false,
            isGraphUnlocked: true,
            availability: .available
        )
    }
}
