import Foundation
import Testing
@testable import BrainMesh

struct GraphCanvasFocusHistoryStateTests {

    @Test
    func previousFocusIsDeterministicWhenTimestampsMatch() {
        let graphID = UUID()
        let currentEntityID = UUID()
        let alphaEntityID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let betaEntityID = UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!
        let focusedAt = Date(timeIntervalSince1970: 100)

        let state = GraphCanvasFocusHistoryState(
            items: [
                GraphCanvasFocusHistoryItem(
                    graphID: graphID,
                    entityID: currentEntityID,
                    label: "Current",
                    focusedAt: Date(timeIntervalSince1970: 200)
                ),
                GraphCanvasFocusHistoryItem(
                    graphID: graphID,
                    entityID: betaEntityID,
                    label: "Beta",
                    focusedAt: focusedAt
                ),
                GraphCanvasFocusHistoryItem(
                    graphID: graphID,
                    entityID: alphaEntityID,
                    label: "Alpha",
                    focusedAt: focusedAt
                )
            ]
        )

        let previous = state.previousItem(graphID: graphID, currentEntityID: currentEntityID)

        #expect(previous?.entityID == alphaEntityID)
    }

    @Test
    func recordFocusTrimsEmptyLabelsToFallback() {
        let graphID = UUID()
        let entityID = UUID()
        var state = GraphCanvasFocusHistoryState()

        state.recordFocus(
            graphID: graphID,
            entityID: entityID,
            label: "   ",
            focusedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(state.items(graphID: graphID, limit: 10).first?.label == "Unbenannte Entität")
    }

    @Test
    func clearRemovesOnlyRequestedGraph() {
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let firstEntityID = UUID()
        let secondEntityID = UUID()
        var state = GraphCanvasFocusHistoryState()

        state.recordFocus(graphID: firstGraphID, entityID: firstEntityID, label: "First", focusedAt: Date(timeIntervalSince1970: 100))
        state.recordFocus(graphID: secondGraphID, entityID: secondEntityID, label: "Second", focusedAt: Date(timeIntervalSince1970: 200))
        state.clear(graphID: firstGraphID)

        #expect(state.items(graphID: firstGraphID, limit: 10).isEmpty)
        #expect(state.items(graphID: secondGraphID, limit: 10).map(\.entityID) == [secondEntityID])
    }
}
