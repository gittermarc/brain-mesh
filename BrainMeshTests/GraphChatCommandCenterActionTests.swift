import Foundation
import Testing
@testable import BrainMesh

struct GraphChatCommandCenterActionTests {
    @Test
    func quickActionResolvesToSharedChatEntry() {
        #expect(
            CommandCenterActionResolver.action(for: .chatWithGraph) == .openChat
        )
        #expect(CommandCenterQuickAction.chatWithGraph.title == "Frag deinen Graphen")
    }

    @Test
    func commandCenterLaunchUsesActiveWholeGraphScope() throws {
        let graphID = UUID()
        let launch = try #require(
            CommandCenterActionResolver.graphChatLaunch(activeGraphID: graphID)
        )

        #expect(
            launch.scope == .entireGraph(GraphScope(graphID: graphID))
        )
        #expect(launch.prefilledQuestion == nil)
        #expect(
            CommandCenterActionResolver.graphChatLaunch(activeGraphID: nil) == nil
        )
    }

    @Test
    func commandCenterOverviewIncludesChatAction() {
        #expect(
            CommandCenterStateBuilder.defaultQuickActions.contains(.chatWithGraph)
        )
    }
}
