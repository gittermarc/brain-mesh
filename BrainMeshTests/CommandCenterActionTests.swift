import Foundation
import Testing
@testable import BrainMesh

struct CommandCenterActionTests {

    @Test
    func quickActionOpenGraphSelectsGraphTab() {
        let action = CommandCenterActionResolver.action(for: .openGraph)

        #expect(action == .selectTab(.graph))
    }

    @Test
    func quickActionOpenStatsSelectsStatsTab() {
        let action = CommandCenterActionResolver.action(for: .openStats)

        #expect(action == .selectTab(.stats))
    }

    @Test
    func quickActionAddEntityPresentsAddEntityDestination() {
        let action = CommandCenterActionResolver.action(for: .addEntity)

        #expect(action == .present(.addEntity))
    }

    @Test
    func entityResultOpensEntityDetail() {
        let graphID = UUID()
        let entityID = UUID()
        let result = BrainMeshSearchResult(
            kind: .entity,
            id: entityID,
            graphID: graphID,
            title: "Atlas",
            subtitle: "Entität",
            iconSymbolName: "cube",
            matchReason: "Name",
            nodeKindRaw: NodeKind.entity.rawValue,
            nodeID: entityID,
            ownerKindRaw: nil,
            ownerID: nil
        )

        let action = CommandCenterActionResolver.primaryAction(for: result)

        #expect(action == .present(.nodeDetail(kind: .entity, id: entityID)))
    }

    @Test
    func detailResultOpensOwnerDetail() {
        let graphID = UUID()
        let detailID = UUID()
        let ownerID = UUID()
        let result = BrainMeshSearchResult(
            kind: .detail,
            id: detailID,
            graphID: graphID,
            title: "Status: Gold",
            subtitle: "Atlas Plan",
            iconSymbolName: "text.badge.checkmark",
            matchReason: "Detailwert",
            nodeKindRaw: nil,
            nodeID: nil,
            ownerKindRaw: NodeKind.attribute.rawValue,
            ownerID: ownerID
        )

        let action = CommandCenterActionResolver.primaryAction(for: result)

        #expect(action == .present(.nodeDetail(kind: .attribute, id: ownerID)))
    }

    @Test
    func resultGraphActionUsesDirectNodeBeforeOwner() {
        let graphID = UUID()
        let attributeID = UUID()
        let ownerID = UUID()
        let result = BrainMeshSearchResult(
            kind: .attribute,
            id: attributeID,
            graphID: graphID,
            title: "Launch Date",
            subtitle: "Atlas",
            iconSymbolName: "tag",
            matchReason: "Attribut",
            nodeKindRaw: NodeKind.attribute.rawValue,
            nodeID: attributeID,
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: ownerID
        )

        let action = CommandCenterActionResolver.graphAction(for: result)

        #expect(action == .jumpToGraph(graphID: graphID, nodeKey: NodeKey(kind: .attribute, uuid: attributeID)))
    }

    @Test
    func recentItemOpensNodeDetail() {
        let graphID = UUID()
        let entityID = UUID()
        let item = RecentNodeItem(
            graphID: graphID,
            nodeKindRaw: NodeKind.entity.rawValue,
            nodeID: entityID,
            label: "Atlas",
            iconSymbolName: "cube",
            openedAt: Date(timeIntervalSince1970: 10)
        )

        let action = CommandCenterActionResolver.primaryAction(for: item)

        #expect(action == .present(.nodeDetail(kind: .entity, id: entityID)))
    }
}
