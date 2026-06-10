import Foundation
import Testing
@testable import BrainMesh

struct GraphCanvasLimitNoticeModelTests {

    @Test
    func noNoticeWhenLoadedValuesAreBelowLimits() {
        let summary = GraphCanvasLoadSummary(
            mode: .global,
            focusEntityID: nil,
            nodesLoaded: 25,
            edgesLoaded: 40,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: false
        )

        #expect(GraphCanvasLimitNoticeModel.make(summary: summary) == nil)
    }

    @Test
    func nodeLimitCreatesCautiousNotice() throws {
        let summary = GraphCanvasLoadSummary(
            mode: .global,
            focusEntityID: nil,
            nodesLoaded: 140,
            edgesLoaded: 40,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: false
        )

        let model = try #require(GraphCanvasLimitNoticeModel.make(summary: summary))

        #expect(model.title == "Ausschnitt kann begrenzt sein")
        #expect(model.message.contains("Möglicherweise"))
        #expect(model.message.contains("sicher") == false)
        #expect(model.detailItems.contains("Knoten: 140 von maximal 140 geladen."))
        #expect(model.showsHideAttributesAction == false)
    }

    @Test
    func linkLimitCreatesNoticeDetail() throws {
        let summary = GraphCanvasLoadSummary(
            mode: .global,
            focusEntityID: nil,
            nodesLoaded: 40,
            edgesLoaded: 800,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: false
        )

        let model = try #require(GraphCanvasLimitNoticeModel.make(summary: summary))

        #expect(model.detailItems.contains("Links: 800 von maximal 800 geladen."))
    }

    @Test
    func includeAttributesAddsHelpfulHintAndAction() throws {
        let summary = GraphCanvasLoadSummary(
            mode: .neighborhood,
            focusEntityID: UUID(),
            nodesLoaded: 140,
            edgesLoaded: 100,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: true
        )

        let model = try #require(GraphCanvasLimitNoticeModel.make(summary: summary))

        #expect(model.showsHideAttributesAction == true)
        #expect(model.detailItems.contains("Attribute sind eingeblendet; ohne Attribute passt oft mehr vom Fokus-Ausschnitt ins Limit."))
    }

    @Test
    func compactStatusTextNamesRelevantLimit() {
        let nodeSummary = GraphCanvasLoadSummary(
            mode: .global,
            focusEntityID: nil,
            nodesLoaded: 140,
            edgesLoaded: 10,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: false
        )
        let linkSummary = GraphCanvasLoadSummary(
            mode: .global,
            focusEntityID: nil,
            nodesLoaded: 10,
            edgesLoaded: 800,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: false
        )
        let bothSummary = GraphCanvasLoadSummary(
            mode: .neighborhood,
            focusEntityID: UUID(),
            nodesLoaded: 140,
            edgesLoaded: 800,
            maxNodes: 140,
            maxLinks: 800,
            includeAttributes: true
        )

        #expect(GraphCanvasLimitNoticeModel.compactStatusText(summary: nodeSummary) == "Node-Limit?")
        #expect(GraphCanvasLimitNoticeModel.compactStatusText(summary: linkSummary) == "Link-Limit?")
        #expect(GraphCanvasLimitNoticeModel.compactStatusText(summary: bothSummary) == "Limits?")
    }
}
