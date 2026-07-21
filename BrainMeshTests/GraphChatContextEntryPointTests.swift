import Foundation
import Testing
@testable import BrainMesh

struct GraphChatContextEntryPointTests {
    private let graphID = UUID()

    @Test
    func entityAndAttributeEntriesUseCorrectScopes() {
        let entityID = UUID()
        let attributeID = UUID()

        let entity = GraphChatContextEntryPoint.entity(
            graphID: graphID,
            entityID: entityID
        )
        let attribute = GraphChatContextEntryPoint.attribute(
            graphID: graphID,
            attributeID: attributeID
        )

        #expect(
            entity.scope == .entity(
                entityID,
                in: GraphScope(graphID: graphID)
            )
        )
        #expect(
            attribute.scope == .node(
                NodeRefKey(kind: .attribute, id: attributeID),
                in: GraphScope(graphID: graphID)
            )
        )
    }

    @Test
    func canvasSelectionUsesSelectedNodeScope() {
        let selected = NodeKey(kind: .entity, uuid: UUID())
        let launch = GraphChatContextEntryPoint.graphNode(
            graphID: graphID,
            node: selected
        )

        #expect(
            launch.scope == .node(
                NodeRefKey(kind: .entity, id: selected.uuid),
                in: GraphScope(graphID: graphID)
            )
        )
    }

    @Test
    func statsFindingCreatesValueOnlyPrefilledQuestionAndBestScope() throws {
        let selected = NodeKey(kind: .attribute, uuid: UUID())
        let launch = GraphChatContextEntryPoint.statsFinding(
            graphID: graphID,
            title: "Verwaiste Attribute",
            message: "Mehrere Attribute haben keine Entität.",
            count: 4,
            primaryNode: selected
        )

        #expect(
            launch.scope == .node(
                NodeRefKey(kind: .attribute, id: selected.uuid),
                in: GraphScope(graphID: graphID)
            )
        )
        let question = try #require(launch.prefilledQuestion)
        #expect(question.contains("Verwaiste Attribute"))
        #expect(question.contains("4"))
        #expect(question.contains("Mehrere Attribute haben keine Entität."))
    }

    @Test
    func statsFindingWithoutNodeUsesWholeGraphScope() {
        let launch = GraphChatContextEntryPoint.statsFinding(
            graphID: graphID,
            title: "Große Attachments",
            message: "Der Speicherbedarf ist hoch.",
            count: 2,
            primaryNode: nil
        )

        #expect(
            launch.scope == .entireGraph(GraphScope(graphID: graphID))
        )
    }
}
