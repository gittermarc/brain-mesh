import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph canvas physics adapter")
@MainActor
struct GraphCanvasPhysicsAdapterTests {
    @Test
    func pinnedNodesRemainFixedInEveryWorkMode() {
        let pinned = NodeKey(
            kind: .entity,
            uuid: UUID(
                uuidString: "00000000-0000-0000-0000-000000009001"
            )!
        )

        for workMode in WorkMode.allCases {
            let fixedNodeKeys =
                GraphCanvasPhysicsFixedNodeResolver.resolve(
                    pinned: [pinned],
                    draggingKey: nil,
                    workMode: workMode
            )

            #expect(
                fixedNodeKeys == Set([pinned]),
                Comment(rawValue: workMode.rawValue)
            )
        }
    }

    @Test
    func draggedNodeIsFixedOnlyWhenWorkModeAllowsNodeDragging() {
        let dragged = NodeKey(
            kind: .attribute,
            uuid: UUID(
                uuidString: "00000000-0000-0000-0000-000000009002"
            )!
        )

        let organize = GraphCanvasPhysicsFixedNodeResolver.resolve(
            pinned: [],
            draggingKey: dragged,
            workMode: .organize
        )
        let explore = GraphCanvasPhysicsFixedNodeResolver.resolve(
            pinned: [],
            draggingKey: dragged,
            workMode: .explore
        )
        let present = GraphCanvasPhysicsFixedNodeResolver.resolve(
            pinned: [],
            draggingKey: dragged,
            workMode: .present
        )

        #expect(organize == Set([dragged]))
        #expect(explore.isEmpty)
        #expect(present.isEmpty)
    }
}
