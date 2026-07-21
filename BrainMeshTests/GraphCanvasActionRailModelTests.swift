import Testing
@testable import BrainMesh

struct GraphCanvasActionRailModelTests {

    @Test
    func focusActionIsOnlyVisibleForEntities() {
        let entityModel = GraphCanvasActionRailModel(
            nodeKind: .entity,
            isPinned: false,
            hiddenLinkCount: 0,
            showsAllLinks: false
        )
        let attributeModel = GraphCanvasActionRailModel(
            nodeKind: .attribute,
            isPinned: false,
            hiddenLinkCount: 0,
            showsAllLinks: false
        )

        #expect(kinds(entityModel).contains(.setFocus) == true)
        #expect(kinds(attributeModel).contains(.setFocus) == false)
    }

    @Test
    func graphChatActionIsAvailableForEntityAndAttributeSelections() {
        let entityModel = GraphCanvasActionRailModel(
            nodeKind: .entity,
            isPinned: false,
            hiddenLinkCount: 0,
            showsAllLinks: false
        )
        let attributeModel = GraphCanvasActionRailModel(
            nodeKind: .attribute,
            isPinned: false,
            hiddenLinkCount: 0,
            showsAllLinks: false
        )

        #expect(kinds(entityModel).contains(.askGraph))
        #expect(kinds(attributeModel).contains(.askGraph))
    }

    @Test
    func linkToggleIsVisibleOnlyWhenHiddenLinksExist() {
        let noHiddenLinks = GraphCanvasActionRailModel(
            nodeKind: .entity,
            isPinned: false,
            hiddenLinkCount: 0,
            showsAllLinks: false
        )
        let showMore = GraphCanvasActionRailModel(
            nodeKind: .entity,
            isPinned: false,
            hiddenLinkCount: 3,
            showsAllLinks: false
        )
        let showFewer = GraphCanvasActionRailModel(
            nodeKind: .entity,
            isPinned: false,
            hiddenLinkCount: 3,
            showsAllLinks: true
        )

        #expect(kinds(noHiddenLinks).contains(.showMoreLinks) == false)
        #expect(kinds(noHiddenLinks).contains(.showFewerLinks) == false)
        #expect(kinds(showMore).contains(.showMoreLinks) == true)
        #expect(kinds(showMore).contains(.showFewerLinks) == false)
        #expect(kinds(showFewer).contains(.showMoreLinks) == false)
        #expect(kinds(showFewer).contains(.showFewerLinks) == true)
    }

    @Test
    func pinActionSwitchesLabelAndIcon() throws {
        let unpinned = GraphCanvasActionRailModel(
            nodeKind: .attribute,
            isPinned: false,
            hiddenLinkCount: 0,
            showsAllLinks: false
        )
        let pinned = GraphCanvasActionRailModel(
            nodeKind: .attribute,
            isPinned: true,
            hiddenLinkCount: 0,
            showsAllLinks: false
        )

        let pinAction = try #require(action(.pin, in: unpinned))
        let unpinAction = try #require(action(.unpin, in: pinned))

        #expect(pinAction.title == "Anpinnen")
        #expect(pinAction.systemImage == "pin")
        #expect(unpinAction.title == "Pin lösen")
        #expect(unpinAction.systemImage == "pin.slash")
    }

    private func kinds(_ model: GraphCanvasActionRailModel) -> [GraphCanvasActionRailActionKind] {
        model.actions.map(\.kind)
    }

    private func action(
        _ kind: GraphCanvasActionRailActionKind,
        in model: GraphCanvasActionRailModel
    ) -> GraphCanvasActionRailAction? {
        model.actions.first { $0.kind == kind }
    }
}
