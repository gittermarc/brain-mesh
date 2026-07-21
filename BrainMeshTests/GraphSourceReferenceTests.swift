import Foundation
import Testing

@testable import BrainMesh

struct GraphSourceReferenceTests {

    @Test
    func referencesAreUniqueAcrossTechnicalSourceIdentity() {
        let sourceID = UUID()
        let first = GraphSourceReference(
            graphID: GraphChatTestSupport.graphID,
            sourceKind: .detailValue,
            sourceID: sourceID,
            node: GraphSourceNodeReference(
                kind: .attribute,
                id: GraphChatTestSupport.projectAttributeID
            ),
            owner: GraphSourceNodeReference(
                kind: .entity,
                id: GraphChatTestSupport.projectEntityID
            ),
            fieldID: UUID()
        )
        let identical = first
        let different = GraphSourceReference(
            graphID: GraphChatTestSupport.graphID,
            sourceKind: .detailValue,
            sourceID: UUID(),
            node: first.node,
            owner: first.owner,
            fieldID: first.fieldID
        )

        #expect(first == identical)
        #expect(first != different)
        #expect(Set([first, identical, different]).count == 2)
    }

    @Test
    func navigationUsesNodeThenOwnerThenSourceFallback() {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let attributeNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let entityNode = NodeRefKey(
            kind: .entity,
            id: GraphChatTestSupport.projectEntityID
        )

        let directNode = GraphSourceReference(
            graphID: graphScope.graphID,
            sourceKind: .detailValue,
            sourceID: UUID(),
            node: GraphSourceNodeReference(
                kind: attributeNode.kind,
                id: attributeNode.id
            ),
            owner: GraphSourceNodeReference(
                kind: entityNode.kind,
                id: entityNode.id
            )
        )
        let ownerFallback = GraphSourceReference(
            graphID: graphScope.graphID,
            sourceKind: .detailField,
            sourceID: UUID(),
            owner: GraphSourceNodeReference(
                kind: entityNode.kind,
                id: entityNode.id
            )
        )
        let sourceFallback = GraphSourceReference(
            graphID: graphScope.graphID,
            sourceKind: .attribute,
            sourceID: attributeNode.id
        )

        #expect(directNode.navigationTarget == .node(graphScope, attributeNode))
        #expect(ownerFallback.navigationTarget == .node(graphScope, entityNode))
        #expect(sourceFallback.navigationTarget == .node(graphScope, attributeNode))
        #expect(directNode.nodeKind == .attribute)
        #expect(directNode.ownerKind == .entity)
    }
}
