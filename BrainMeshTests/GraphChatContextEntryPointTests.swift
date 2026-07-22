import Foundation
import Testing
@testable import BrainMesh

struct GraphChatContextEntryPointTests {
    private let graphID = UUID()

    @Test
    func entityAndAttributeEntriesUseCorrectScopesAndContexts() {
        let entityID = UUID()
        let attributeID = UUID()

        let entity = GraphChatContextEntryPoint.entity(
            graphID: graphID,
            entityID: entityID,
            entityName: "Projekte"
        )
        let attribute = GraphChatContextEntryPoint.attribute(
            graphID: graphID,
            attributeID: attributeID,
            attributeName: "Apollo",
            entityID: entityID,
            entityName: "Projekte"
        )

        #expect(entity.scope == .entity(entityID, in: GraphScope(graphID: graphID)))
        #expect(entity.context == .entity(GraphChatEntityContextReference(id: entityID, name: "Projekte")))
        #expect(attribute.scope == .node(NodeRefKey(kind: .attribute, id: attributeID), in: GraphScope(graphID: graphID)))
        #expect(attribute.context.nodeReferences.first?.label == "Apollo")
    }

    @Test
    func detailFieldEntryCreatesFieldSpecificScopeIdentity() {
        let entityID = UUID()
        let fieldID = UUID()
        let launch = GraphChatContextEntryPoint.detailField(
            graphID: graphID,
            entityID: entityID,
            entityName: "Projekte",
            fieldID: fieldID,
            fieldName: "Status",
            fieldType: .singleChoice
        )

        #expect(launch.scope.target == .entity(entityID))
        #expect(launch.scope.context == .detailField(entityID: entityID, fieldID: fieldID))
    }


    @Test
    func canvasNodeEntryUsesTheExactStableNodeScope() {
        let node = NodeKey(kind: .entity, uuid: UUID())
        let launch = GraphChatContextEntryPoint.graphNode(
            graphID: graphID,
            node: node,
            label: "Projects",
            entityID: node.uuid,
            entityName: "Projects"
        )

        let expected = NodeRefKey(kind: .entity, id: node.uuid)
        #expect(launch.scope == .node(expected, in: GraphScope(graphID: graphID)))
        #expect(launch.context.nodeReferences == [
            GraphChatNodeContextReference(
                node: expected,
                label: "Projects",
                entityID: node.uuid,
                entityName: "Projects"
            )
        ])
    }

    @Test
    func canvasSelectionUsesActualStableNodeReferences() throws {
        let first = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .entity, id: UUID()),
            label: "Projekte"
        )
        let second = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: UUID()),
            label: "Apollo"
        )
        let launch = try #require(
            GraphChatContextEntryPoint.selection(
                graphID: graphID,
                nodes: [second, first]
            )
        )

        #expect(Set(launch.scope.nodeReferences) == Set([first.node, second.node]))
        #expect(launch.context.nodeReferences.count == 2)
        #expect(launch.prefilledQuestion == nil)
    }

    @Test
    func emptySelectionDoesNotCreateLaunch() {
        #expect(GraphChatContextEntryPoint.selection(graphID: graphID, nodes: []) == nil)
    }

    @Test
    func healthFindingUsesFindingIdentityAndAffectedSelection() throws {
        let node = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: UUID()),
            label: "Apollo"
        )
        let launch = GraphChatContextEntryPoint.statsFinding(
            graphID: graphID,
            findingID: "missing-status",
            title: "Fehlender Status",
            message: "Status fehlt.",
            count: 1,
            affectedNodes: [node]
        )

        #expect(launch.scope.context == .healthFinding(id: "missing-status", affectedNodes: [node.node]))
        #expect(launch.scope.target == .selection([node.node]))
        #expect(launch.prefilledQuestion == nil)
    }
}
