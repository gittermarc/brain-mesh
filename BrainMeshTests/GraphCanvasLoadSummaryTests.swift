import Foundation
import Testing
@testable import BrainMesh

struct GraphCanvasLoadSummaryTests {

    @Test
    func nodesLoadedAtMaxNodesReportsPossibleNodeLimit() {
        let summary = makeSummary(nodesLoaded: 140, edgesLoaded: 12, maxNodes: 140, maxLinks: 800)

        #expect(summary.possibleNodeLimitReached == true)
        #expect(summary.possibleLinkLimitReached == false)
        #expect(summary.hasPossibleLimitReached == true)
    }

    @Test
    func edgesLoadedAtMaxLinksReportsPossibleLinkLimit() {
        let summary = makeSummary(nodesLoaded: 12, edgesLoaded: 800, maxNodes: 140, maxLinks: 800)

        #expect(summary.possibleNodeLimitReached == false)
        #expect(summary.possibleLinkLimitReached == true)
        #expect(summary.hasPossibleLimitReached == true)
    }

    @Test
    func valuesBelowLimitsDoNotReportLimitNotice() {
        let summary = makeSummary(nodesLoaded: 139, edgesLoaded: 799, maxNodes: 140, maxLinks: 800)

        #expect(summary.possibleNodeLimitReached == false)
        #expect(summary.possibleLinkLimitReached == false)
        #expect(summary.hasPossibleLimitReached == false)
        #expect(summary.reasonText == nil)
    }

    @Test
    func reasonTextUsesCautiousWording() throws {
        let summary = makeSummary(nodesLoaded: 140, edgesLoaded: 799, maxNodes: 140, maxLinks: 800)
        let reasonText = try #require(summary.reasonText)

        #expect(reasonText.contains("Möglicherweise"))
        #expect(reasonText.contains("sicher") == false)
        #expect(reasonText.contains("fehlen") == false)
    }

    @Test
    func globalAndNeighborhoodSummariesRemainDistinct() {
        let focusID = UUID()
        let global = GraphCanvasLoadSummary(
            mode: .global,
            focusEntityID: nil,
            nodesLoaded: 10,
            edgesLoaded: 20,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: false
        )
        let neighborhood = GraphCanvasLoadSummary(
            mode: .neighborhood,
            focusEntityID: focusID,
            nodesLoaded: 10,
            edgesLoaded: 20,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: true
        )

        #expect(global.mode == .global)
        #expect(global.focusEntityID == nil)
        #expect(neighborhood.mode == .neighborhood)
        #expect(neighborhood.focusEntityID == focusID)
        #expect(global.noticeFingerprint != neighborhood.noticeFingerprint)
    }

    private func makeSummary(
        nodesLoaded: Int,
        edgesLoaded: Int,
        maxNodes: Int,
        maxLinks: Int
    ) -> GraphCanvasLoadSummary {
        GraphCanvasLoadSummary(
            mode: .global,
            focusEntityID: nil,
            nodesLoaded: nodesLoaded,
            edgesLoaded: edgesLoaded,
            maxNodes: maxNodes,
            maxLinks: maxLinks,
            includeAttributes: false
        )
    }
}
