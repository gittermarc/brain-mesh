import Foundation
import Testing

@testable import BrainMesh

struct GraphCanvasSelectionStateTests {
    @Test
    func retainedNodesAndPrimaryFormOneDeterministicSelection() {
        let first = NodeKey(kind: .entity, uuid: UUID())
        let second = NodeKey(kind: .attribute, uuid: UUID())
        var state = GraphCanvasSelectionState(primary: first)

        state.togglePrimaryRetention()
        state.setPrimary(second)

        #expect(Set(state.chatNodes) == Set([first, second]))
        #expect(state.chatNodeCount == 2)
        #expect(state.primary == second)
    }

    @Test
    func clearingPrimaryClearsTheSingleSelectionStore() {
        let node = NodeKey(kind: .attribute, uuid: UUID())
        var state = GraphCanvasSelectionState(primary: node)
        state.togglePrimaryRetention()

        state.setPrimary(nil)

        #expect(state.primary == nil)
        #expect(state.chatNodes.isEmpty)
    }

    @Test
    func deletedNodesAreDiscardedDuringRevalidation() {
        let existing = NodeKey(kind: .entity, uuid: UUID())
        let deleted = NodeKey(kind: .attribute, uuid: UUID())
        var state = GraphCanvasSelectionState(primary: deleted, retainedNodes: [existing])

        state.retainAvailableNodes([existing])

        #expect(state.primary == existing)
        #expect(state.chatNodes == [existing])
    }

    @Test
    func addingNodesUsesTheExistingPrimaryAndDeduplicatesTheRetainedSelection() {
        let primary = NodeKey(
            kind: .entity,
            uuid: UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!
        )
        let first = NodeKey(
            kind: .attribute,
            uuid: UUID(uuidString: "C1000000-0000-0000-0000-000000000002")!
        )
        let second = NodeKey(
            kind: .attribute,
            uuid: UUID(uuidString: "C1000000-0000-0000-0000-000000000003")!
        )
        var state = GraphCanvasSelectionState(primary: primary)

        state.add([second, first, first, primary])

        #expect(state.primary == primary)
        #expect(Set(state.chatNodes) == Set([primary, first, second]))
        #expect(state.chatNodeCount == 3)
    }

    @Test
    func replacingSelectionIsDeterministicAndAnEmptyReplacementClearsIt() {
        let first = NodeKey(
            kind: .entity,
            uuid: UUID(uuidString: "C1000000-0000-0000-0000-000000000010")!
        )
        let second = NodeKey(
            kind: .attribute,
            uuid: UUID(uuidString: "C1000000-0000-0000-0000-000000000011")!
        )
        var state = GraphCanvasSelectionState(primary: second)

        state.replace(with: [second, first, second])

        #expect(state.primary == first)
        #expect(state.chatNodes == [first, second])

        state.replace(with: [])

        #expect(state.primary == nil)
        #expect(state.chatNodes.isEmpty)
    }

}
