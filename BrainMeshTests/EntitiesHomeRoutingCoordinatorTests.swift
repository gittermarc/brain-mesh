import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct EntitiesHomeRoutingCoordinatorTests {

    @Test
    func requestQuickFilterStoresPendingRoute() {
        let coordinator = EntitiesHomeRoutingCoordinator()
        let graphID = UUID()

        coordinator.requestQuickFilter(.isolatedEntities, graphID: graphID)

        #expect(coordinator.pendingQuickFilterRoute?.graphID == graphID)
        #expect(coordinator.pendingQuickFilterRoute?.filter == .isolatedEntities)
    }

    @Test
    func consumeQuickFilterRouteClearsMatchingRoute() throws {
        let coordinator = EntitiesHomeRoutingCoordinator()
        coordinator.requestQuickFilter(.entitiesWithoutDetails, graphID: UUID())
        let route = try #require(coordinator.pendingQuickFilterRoute)

        let consumed = coordinator.consumeQuickFilterRoute(id: route.id)

        #expect(consumed == route)
        #expect(coordinator.pendingQuickFilterRoute == nil)
    }

    @Test
    func consumeWithDifferentIDKeepsRoute() throws {
        let coordinator = EntitiesHomeRoutingCoordinator()
        coordinator.requestQuickFilter(.entitiesWithoutAttributes, graphID: UUID())
        let route = try #require(coordinator.pendingQuickFilterRoute)

        let consumed = coordinator.consumeQuickFilterRoute(id: UUID())

        #expect(consumed == nil)
        #expect(coordinator.pendingQuickFilterRoute == route)
    }
}
