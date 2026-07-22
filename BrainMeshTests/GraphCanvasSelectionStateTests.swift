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
}
