import Foundation
import Testing
@testable import BrainMesh

struct GraphStatsJumpActionTests {

    @Test
    func topHubEntityBuildsGraphJump() {
        let graphID = UUID()
        let entityID = UUID()
        let hub = GraphHubItem(
            id: entityID,
            label: "Atlas",
            kind: .entity,
            degree: 12
        )

        let plan = GraphStatsJumpActionResolver.action(graphID: graphID, hub: hub)

        #expect(plan?.tab == .graph)
        #expect(plan?.graphID == graphID)
        #expect(plan?.nodeKey == NodeKey(kind: .entity, uuid: entityID))
    }

    @Test
    func topHubAttributeBuildsGraphJump() {
        let graphID = UUID()
        let attributeID = UUID()
        let hub = GraphHubItem(
            id: attributeID,
            label: "Status",
            kind: .attribute,
            degree: 8
        )

        let plan = GraphStatsJumpActionResolver.action(graphID: graphID, hub: hub)

        #expect(plan?.tab == .graph)
        #expect(plan?.graphID == graphID)
        #expect(plan?.nodeKey == NodeKey(kind: .attribute, uuid: attributeID))
    }

    @Test
    func topMediaNodeBuildsGraphJump() {
        let graphID = UUID()
        let attributeID = UUID()
        let item = GraphMediaNodeItem(
            id: attributeID,
            label: "Mockups",
            kind: .attribute,
            attachmentCount: 4,
            headerImageCount: 1
        )

        let plan = GraphStatsJumpActionResolver.action(graphID: graphID, mediaNode: item)

        #expect(plan?.tab == .graph)
        #expect(plan?.graphID == graphID)
        #expect(plan?.nodeKey == NodeKey(kind: .attribute, uuid: attributeID))
    }

    @Test
    func missingDashboardGraphIDBuildsNoJumpAction() {
        let hub = GraphHubItem(
            id: UUID(),
            label: "Atlas",
            kind: .entity,
            degree: 3
        )

        let plan = GraphStatsJumpActionResolver.action(graphID: nil, hub: hub)

        #expect(plan == nil)
    }
}
