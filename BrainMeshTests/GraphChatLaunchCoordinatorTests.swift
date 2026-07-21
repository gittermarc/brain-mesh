import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct GraphChatLaunchCoordinatorTests {
    @Test
    func rootTabRawValuesAndVisibleOrderRemainStable() {
        #expect(RootTab.entities.rawValue == 0)
        #expect(RootTab.graph.rawValue == 1)
        #expect(RootTab.stats.rawValue == 2)
        #expect(RootTab.settings.rawValue == 3)
        #expect(RootTab.chat.rawValue == 4)
        #expect(RootTab.visibleOrder == [
            .entities,
            .graph,
            .chat,
            .stats,
            .settings
        ])
    }

    @Test
    func launchStoresValueOnlyScopePromptAndPresentation() {
        let graphID = UUID()
        let entityID = UUID()
        let scope = GraphChatScope.entity(
            entityID,
            in: GraphScope(graphID: graphID)
        )
        let coordinator = GraphChatLaunchCoordinator()

        coordinator.launch(
            scope: scope,
            prefilledQuestion: "  Welche Risiken gibt es?  ",
            presentationStyle: .rootTab
        )

        #expect(coordinator.request?.scope == scope)
        #expect(coordinator.request?.prefilledQuestion == "Welche Risiken gibt es?")
        #expect(coordinator.request?.presentationStyle == .rootTab)
    }

    @Test
    func activeGraphChangeResetsToWholeGraphScope() throws {
        let oldGraphID = UUID()
        let newGraphID = UUID()
        let coordinator = GraphChatLaunchCoordinator()
        coordinator.launch(
            scope: .node(
                NodeRefKey(kind: .attribute, id: UUID()),
                in: GraphScope(graphID: oldGraphID)
            )
        )

        coordinator.handleActiveGraphChange(to: newGraphID)

        let request = try #require(coordinator.request)
        #expect(request.scope == .entireGraph(GraphScope(graphID: newGraphID)))
        #expect(request.prefilledQuestion == nil)
    }

    @Test
    func graphLockInvalidatesOnlyMatchingOrGlobalLaunches() throws {
        let graphID = UUID()
        let coordinator = GraphChatLaunchCoordinator()
        coordinator.launch(
            scope: .entireGraph(GraphScope(graphID: graphID))
        )

        coordinator.handleSecurityLock(graphID: UUID())
        _ = try #require(coordinator.request)

        coordinator.handleSecurityLock(graphID: graphID)
        #expect(coordinator.request == nil)

        coordinator.launch(
            scope: .entireGraph(GraphScope(graphID: graphID))
        )
        coordinator.handleSecurityLock(graphID: nil)
        #expect(coordinator.request == nil)
    }

    @Test
    func missingOrForeignRequestFallsBackToActiveWholeGraph() {
        let activeGraphID = UUID()
        let foreignGraphID = UUID()
        let coordinator = GraphChatLaunchCoordinator()
        coordinator.launch(
            scope: .entireGraph(GraphScope(graphID: foreignGraphID))
        )

        let resolved = coordinator.requestForActiveGraph(activeGraphID)

        #expect(resolved.scope == .entireGraph(GraphScope(graphID: activeGraphID)))
    }
}
