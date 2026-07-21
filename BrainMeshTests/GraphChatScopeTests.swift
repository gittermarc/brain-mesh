import Foundation
import Testing

@testable import BrainMesh

struct GraphChatScopeTests {

    @Test
    func graphEntityAndNodeScopesRetainExactlyOneGraphBoundary() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let entityScope = GraphChatScope.entity(
            GraphChatTestSupport.projectEntityID,
            in: graphScope
        )
        let node = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let nodeScope = GraphChatScope.node(node, in: graphScope)

        #expect(GraphChatScope.entireGraph(graphScope).graphScope == graphScope)
        #expect(entityScope.graphScope == graphScope)
        #expect(entityScope.target == .entity(GraphChatTestSupport.projectEntityID))
        #expect(nodeScope.graphScope == graphScope)
        #expect(nodeScope.nodeReferences == [node])
    }

    @Test
    func selectionIsCanonicalAndRejectsInvalidMembershipLists() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let entityNode = NodeRefKey(
            kind: .entity,
            id: GraphChatTestSupport.projectEntityID
        )
        let attributeNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let selection = try GraphChatScope.selection(
            [attributeNode, entityNode],
            in: graphScope
        )

        #expect(selection.nodeReferences == [entityNode, attributeNode])
        #expect(throws: GraphChatScopeError.emptySelection) {
            try GraphChatScope.selection([], in: graphScope)
        }
        #expect(throws: GraphChatScopeError.duplicateNode(entityNode)) {
            try GraphChatScope.selection([entityNode, entityNode], in: graphScope)
        }
    }
}
