import Foundation
import Testing
@testable import BrainMesh

struct GraphHealthActionResolverTests {

    @Test
    func isolatedEntitiesIssueRoutesToEntitiesQuickFilter() {
        let graphID = UUID()
        let issue = makeActionIssue(kind: .isolatedEntities)

        let action = GraphHealthActionResolver.primaryAction(for: issue, dashboardGraphID: graphID)

        #expect(action == .openEntitiesQuickFilter(graphID: graphID, filter: .isolatedEntities))
        #expect(GraphHealthActionResolver.callToActionTitle(for: issue, action: action) == "Isolierte Entitäten anzeigen")
    }

    @Test
    func entitiesWithoutAttributesIssueRoutesToQuickFilter() {
        let graphID = UUID()
        let issue = makeActionIssue(kind: .entitiesWithoutAttributes)

        let action = GraphHealthActionResolver.primaryAction(for: issue, dashboardGraphID: graphID)

        #expect(action == .openEntitiesQuickFilter(graphID: graphID, filter: .entitiesWithoutAttributes))
    }

    @Test
    func entitiesWithoutDetailsIssueRoutesToQuickFilter() {
        let graphID = UUID()
        let issue = makeActionIssue(kind: .entitiesWithoutDetailsSchema)

        let action = GraphHealthActionResolver.primaryAction(for: issue, dashboardGraphID: graphID)

        #expect(action == .openEntitiesQuickFilter(graphID: graphID, filter: .entitiesWithoutDetails))
        #expect(GraphHealthActionResolver.callToActionTitle(for: issue, action: action) == "Detail-Lücken öffnen")
    }

    @Test
    func topHubIssueRoutesToGraphJump() throws {
        let graphID = UUID()
        let hubID = UUID()
        let issue = makeActionIssue(
            kind: .topHubs,
            primaryNodeKindRaw: NodeKind.entity.rawValue,
            primaryNodeID: hubID,
            affectedItems: [
                .node(id: hubID, label: "Hub", kind: .entity, count: 4)
            ]
        )

        let action = GraphHealthActionResolver.primaryAction(for: issue, dashboardGraphID: graphID)
        guard case .jumpToGraph(let plan) = action else {
            Issue.record("Expected graph jump action")
            return
        }

        #expect(plan.graphID == graphID)
        #expect(plan.nodeKey == NodeKey(kind: .entity, uuid: hubID))
        #expect(plan.tab == .graph)
    }



    @Test
    func multipleTopHubsRouteToIssueList() {
        let first = UUID()
        let second = UUID()
        let issue = makeActionIssue(
            kind: .topHubs,
            affectedItems: [
                .node(id: first, label: "First", kind: .entity, count: 6),
                .node(id: second, label: "Second", kind: .attribute, count: 5)
            ]
        )

        let action = GraphHealthActionResolver.primaryAction(for: issue, dashboardGraphID: UUID())

        #expect(action == .showIssueList(issueID: issue.id))
    }

    @Test
    func largeAttachmentSingleItemRoutesToOwnerNodeDetail() throws {
        let ownerID = UUID()
        let item = GraphHealthAffectedItem.attachment(
            id: UUID(),
            label: "Large PDF",
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: ownerID,
            ownerLabel: "Owner Entity",
            byteCount: 40 * 1_024 * 1_024
        )
        let issue = makeActionIssue(
            kind: .largeAttachments,
            primaryNodeKindRaw: NodeKind.entity.rawValue,
            primaryNodeID: ownerID,
            affectedItems: [item]
        )

        let action = GraphHealthActionResolver.primaryAction(for: issue, dashboardGraphID: UUID())

        #expect(action == .openNodeDetail(kind: .entity, id: ownerID))
    }

    @Test
    func largeAttachmentMultipleItemsRoutesToIssueList() {
        let issue = makeActionIssue(
            kind: .largeAttachments,
            affectedItems: [
                .attachment(
                    id: UUID(),
                    label: "First",
                    ownerKindRaw: NodeKind.entity.rawValue,
                    ownerID: UUID(),
                    byteCount: 40 * 1_024 * 1_024
                ),
                .attachment(
                    id: UUID(),
                    label: "Second",
                    ownerKindRaw: NodeKind.attribute.rawValue,
                    ownerID: UUID(),
                    byteCount: 45 * 1_024 * 1_024
                )
            ]
        )

        let action = GraphHealthActionResolver.primaryAction(for: issue, dashboardGraphID: UUID())

        #expect(action == .showIssueList(issueID: issue.id))
    }

    @Test
    func affectedAttachmentBuildsOwnerGraphJumpWhenGraphIDExists() throws {
        let graphID = UUID()
        let ownerID = UUID()
        let item = GraphHealthAffectedItem.attachment(
            id: UUID(),
            label: "Movie",
            ownerKindRaw: NodeKind.attribute.rawValue,
            ownerID: ownerID,
            byteCount: 80 * 1_024 * 1_024
        )

        let action = GraphHealthActionResolver.graphAction(for: item, dashboardGraphID: graphID)
        guard case .jumpToGraph(let plan) = action else {
            Issue.record("Expected graph jump action")
            return
        }

        #expect(plan.graphID == graphID)
        #expect(plan.nodeKey == NodeKey(kind: .attribute, uuid: ownerID))
    }

    @Test
    func missingGraphIDBuildsNoGraphJump() {
        let item = GraphHealthAffectedItem.node(
            id: UUID(),
            label: "Hub",
            kind: .entity,
            count: 5
        )

        let action = GraphHealthActionResolver.graphAction(for: item, dashboardGraphID: nil)

        #expect(action == .none)
    }

    @Test
    func incompleteAffectedItemDoesNotCrashAndBuildsNoAction() {
        let item = GraphHealthAffectedItem(
            id: UUID(),
            label: "Broken",
            nodeKindRaw: nil,
            nodeID: nil,
            ownerKindRaw: nil,
            ownerID: nil,
            ownerLabel: nil,
            count: nil,
            byteCount: nil
        )

        #expect(GraphHealthActionResolver.nodeDetailAction(for: item) == .none)
        #expect(GraphHealthActionResolver.graphAction(for: item, dashboardGraphID: UUID()) == .none)
    }
}

private func makeActionIssue(
    kind: GraphHealthIssueKind,
    primaryNodeKindRaw: Int? = nil,
    primaryNodeID: UUID? = nil,
    affectedItems: [GraphHealthAffectedItem] = []
) -> GraphHealthIssue {
    GraphHealthIssue(
        id: "action-\(kind.rawValue)",
        kind: kind,
        severity: .attention,
        title: "Issue",
        message: "Message",
        count: max(1, affectedItems.count),
        primaryNodeKindRaw: primaryNodeKindRaw,
        primaryNodeID: primaryNodeID,
        affectedItems: affectedItems,
        actionHint: .reviewStructure(title: "Prüfen", message: "Ansehen")
    )
}
