import Foundation
import Testing
@testable import BrainMesh

struct GraphChatSourceNavigationTests {
    private let graphID = UUID()

    @Test
    func entityAndAttributeSourcesOpenTheirExistingDetails() {
        let entityID = UUID()
        let attributeID = UUID()

        let entity = GraphSourceReference(
            graphID: graphID,
            sourceKind: .entity,
            sourceID: entityID
        )
        let attribute = GraphSourceReference(
            graphID: graphID,
            sourceKind: .attribute,
            sourceID: attributeID
        )

        #expect(
            GraphChatSourceNavigationResolver.openDestination(
                for: entity,
                activeGraphID: graphID
            ) == .nodeDetail(
                graphID: graphID,
                node: NodeRefKey(kind: .entity, id: entityID)
            )
        )
        #expect(
            GraphChatSourceNavigationResolver.openDestination(
                for: attribute,
                activeGraphID: graphID
            ) == .nodeDetail(
                graphID: graphID,
                node: NodeRefKey(kind: .attribute, id: attributeID)
            )
        )
    }


    @Test
    func entitySourceIdentityCannotBeRedirectedByMismatchedNodeMetadata() {
        let entityID = UUID()
        let reference = GraphSourceReference(
            graphID: graphID,
            sourceKind: .entity,
            sourceID: entityID,
            node: GraphSourceNodeReference(kind: .attribute, id: UUID())
        )

        #expect(
            GraphChatSourceNavigationResolver.openDestination(
                for: reference,
                activeGraphID: graphID
            ) == .nodeDetail(
                graphID: graphID,
                node: NodeRefKey(kind: .entity, id: entityID)
            )
        )
    }

    @Test
    func detailValueAndAttachmentOpenTheirOwnerNodes() {
        let attributeID = UUID()
        let entityID = UUID()
        let detail = GraphSourceReference(
            graphID: graphID,
            sourceKind: .detailValue,
            sourceID: UUID(),
            node: GraphSourceNodeReference(kind: .attribute, id: attributeID),
            owner: GraphSourceNodeReference(kind: .entity, id: entityID),
            fieldID: UUID()
        )
        let attachment = GraphSourceReference(
            graphID: graphID,
            sourceKind: .attachment,
            sourceID: UUID(),
            owner: GraphSourceNodeReference(kind: .entity, id: entityID),
            attachmentID: UUID()
        )

        #expect(
            GraphChatSourceNavigationResolver.openDestination(
                for: detail,
                activeGraphID: graphID
            ) == .nodeDetail(
                graphID: graphID,
                node: NodeRefKey(kind: .entity, id: entityID)
            )
        )
        #expect(
            GraphChatSourceNavigationResolver.openDestination(
                for: attachment,
                activeGraphID: graphID
            ) == .nodeDetail(
                graphID: graphID,
                node: NodeRefKey(kind: .entity, id: entityID)
            )
        )
    }

    @Test
    func detailValueGraphJumpUsesOwnerNode() throws {
        let attributeID = UUID()
        let entityID = UUID()
        let reference = GraphSourceReference(
            graphID: graphID,
            sourceKind: .detailValue,
            sourceID: UUID(),
            node: GraphSourceNodeReference(kind: .attribute, id: attributeID),
            owner: GraphSourceNodeReference(kind: .entity, id: entityID),
            fieldID: UUID()
        )

        let jump = try #require(
            GraphChatSourceNavigationResolver.graphJump(
                for: reference,
                activeGraphID: graphID
            )
        )

        #expect(jump.graphID == graphID)
        #expect(jump.nodeKey == NodeKey(kind: .entity, uuid: entityID))
    }

    @Test
    func linkEvidenceUsesEndpointRouteWithoutInventingLinkDetail() {
        let linkID = UUID()
        let reference = GraphSourceReference(
            graphID: graphID,
            sourceKind: .link,
            sourceID: linkID,
            node: GraphSourceNodeReference(kind: .entity, id: UUID()),
            linkID: linkID
        )

        #expect(
            GraphChatSourceNavigationResolver.openDestination(
                for: reference,
                activeGraphID: graphID
            ) == .linkEndpoints(graphID: graphID, linkID: linkID)
        )
    }

    @Test
    func graphJumpUsesExactGraphAndNode() throws {
        let nodeID = UUID()
        let reference = GraphSourceReference(
            graphID: graphID,
            sourceKind: .attribute,
            sourceID: nodeID,
            node: GraphSourceNodeReference(kind: .attribute, id: nodeID)
        )

        let jump = try #require(
            GraphChatSourceNavigationResolver.graphJump(
                for: reference,
                activeGraphID: graphID
            )
        )

        #expect(jump.graphID == graphID)
        #expect(jump.nodeKey == NodeKey(kind: .attribute, uuid: nodeID))
    }

    @Test
    func noForeignGraphSourceCanOpenOrJump() {
        let reference = GraphSourceReference(
            graphID: UUID(),
            sourceKind: .entity,
            sourceID: UUID()
        )

        #expect(
            GraphChatSourceNavigationResolver.openDestination(
                for: reference,
                activeGraphID: graphID
            ) == nil
        )
        #expect(
            GraphChatSourceNavigationResolver.graphJump(
                for: reference,
                activeGraphID: graphID
            ) == nil
        )
    }
}
