import Foundation
import Testing
@testable import BrainMesh

struct GraphCanvasJumpActionResolverTests {

    @Test
    func entityNodeBuildsGraphJumpPlan() {
        let graphID = UUID()
        let entityID = UUID()

        let plan = GraphCanvasJumpActionResolver.resolve(
            graphID: graphID,
            kind: .entity,
            nodeID: entityID
        )

        #expect(plan?.tab == .graph)
        #expect(plan?.graphID == graphID)
        #expect(plan?.nodeKey == NodeKey(kind: .entity, uuid: entityID))
        #expect(plan?.centerOnArrival == true)
    }

    @Test
    func attributeNodeBuildsGraphJumpPlan() {
        let graphID = UUID()
        let attributeID = UUID()

        let plan = GraphCanvasJumpActionResolver.resolve(
            graphID: graphID,
            kind: .attribute,
            nodeID: attributeID,
            centerOnArrival: false
        )

        #expect(plan?.tab == .graph)
        #expect(plan?.graphID == graphID)
        #expect(plan?.nodeKey == NodeKey(kind: .attribute, uuid: attributeID))
        #expect(plan?.centerOnArrival == false)
    }

    @Test
    func missingGraphIDBuildsNoPlan() {
        let plan = GraphCanvasJumpActionResolver.resolve(
            graphID: nil,
            kind: .entity,
            nodeID: UUID()
        )

        #expect(plan == nil)
    }

    @Test
    func missingNodeIDBuildsNoPlan() {
        let plan = GraphCanvasJumpActionResolver.resolve(
            graphID: UUID(),
            kind: .entity,
            nodeID: nil
        )

        #expect(plan == nil)
    }

    @Test
    func invalidRawNodeKindBuildsNoPlan() {
        let plan = GraphCanvasJumpActionResolver.resolve(
            graphID: UUID(),
            nodeKindRaw: 99,
            nodeID: UUID()
        )

        #expect(plan == nil)
    }
}
