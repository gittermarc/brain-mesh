//
//  GraphHealthActionResolver.swift
//  BrainMesh
//
//  Pure routing decisions for Graph Health recommendations.
//

import Foundation

nonisolated enum GraphHealthResolvedAction: Equatable, Sendable {
    case openEntitiesQuickFilter(graphID: UUID, filter: EntitiesHomeQuickFilter)
    case openNodeDetail(kind: NodeKind, id: UUID)
    case jumpToGraph(GraphCanvasJumpActionPlan)
    case showIssueList(issueID: String)
    case none

    var isActionable: Bool {
        self != .none
    }
}

nonisolated enum GraphHealthActionResolver {
    static func primaryAction(
        for issue: GraphHealthIssue,
        dashboardGraphID: UUID?
    ) -> GraphHealthResolvedAction {
        switch issue.kind {
        case .isolatedEntities:
            return quickFilterAction(graphID: dashboardGraphID, filter: .isolatedEntities)

        case .entitiesWithoutAttributes:
            return quickFilterAction(graphID: dashboardGraphID, filter: .entitiesWithoutAttributes)

        case .entitiesWithoutDetailsSchema:
            return quickFilterAction(graphID: dashboardGraphID, filter: .entitiesWithoutDetails)

        case .largeAttachments:
            if issue.affectedItems.count > 1 {
                return .showIssueList(issueID: issue.id)
            }
            return nodeDetailAction(for: issue.affectedItems.first)

        case .topHubs:
            if issue.affectedItems.count > 1 {
                return .showIssueList(issueID: issue.id)
            }
            if let action = graphAction(
                nodeKindRaw: issue.primaryNodeKindRaw,
                nodeID: issue.primaryNodeID,
                dashboardGraphID: dashboardGraphID
            ) {
                return action
            }
            return .none

        case .mediaRichNodes:
            if issue.affectedItems.count > 1 {
                return .showIssueList(issueID: issue.id)
            }
            return nodeDetailAction(for: issue.affectedItems.first)

        case .lowLinkDensity:
            return .none
        }
    }

    static func nodeDetailAction(for item: GraphHealthAffectedItem?) -> GraphHealthResolvedAction {
        guard let item else { return .none }

        if let nodeKindRaw = item.nodeKindRaw,
           let nodeKind = NodeKind(rawValue: nodeKindRaw),
           let nodeID = item.nodeID {
            return .openNodeDetail(kind: nodeKind, id: nodeID)
        }

        if let ownerKindRaw = item.ownerKindRaw,
           let ownerKind = NodeKind(rawValue: ownerKindRaw),
           let ownerID = item.ownerID {
            return .openNodeDetail(kind: ownerKind, id: ownerID)
        }

        return .none
    }

    static func graphAction(
        for item: GraphHealthAffectedItem?,
        dashboardGraphID: UUID?
    ) -> GraphHealthResolvedAction {
        guard let item else { return .none }

        if let action = graphAction(
            nodeKindRaw: item.nodeKindRaw,
            nodeID: item.nodeID,
            dashboardGraphID: dashboardGraphID
        ) {
            return action
        }

        if let action = graphAction(
            nodeKindRaw: item.ownerKindRaw,
            nodeID: item.ownerID,
            dashboardGraphID: dashboardGraphID
        ) {
            return action
        }

        return .none
    }

    static func callToActionTitle(for issue: GraphHealthIssue, action: GraphHealthResolvedAction) -> String? {
        guard action.isActionable else { return nil }

        switch issue.kind {
        case .isolatedEntities:
            return "Isolierte Entitäten anzeigen"
        case .entitiesWithoutAttributes:
            return "Entitäten ohne Attribute anzeigen"
        case .entitiesWithoutDetailsSchema:
            return "Detail-Lücken öffnen"
        case .largeAttachments:
            return "Große Anhänge prüfen"
        case .topHubs:
            return "Im Graph fokussieren"
        case .mediaRichNodes:
            return "Medienknoten prüfen"
        case .lowLinkDensity:
            return nil
        }
    }

    static func actionTitle(for action: GraphHealthResolvedAction) -> String? {
        switch action {
        case .openEntitiesQuickFilter(_, let filter):
            switch filter {
            case .all:
                return "Entitäten anzeigen"
            case .isolatedEntities:
                return "Isolierte Entitäten anzeigen"
            case .entitiesWithoutAttributes:
                return "Entitäten ohne Attribute anzeigen"
            case .entitiesWithoutDetails:
                return "Detail-Lücken öffnen"
            case .mediaRich:
                return "Medienknoten prüfen"
            }
        case .openNodeDetail:
            return "Details öffnen"
        case .jumpToGraph:
            return "Im Graph zeigen"
        case .showIssueList:
            return "Betroffene Einträge anzeigen"
        case .none:
            return nil
        }
    }

    private static func quickFilterAction(
        graphID: UUID?,
        filter: EntitiesHomeQuickFilter
    ) -> GraphHealthResolvedAction {
        guard let graphID else { return .none }
        return .openEntitiesQuickFilter(graphID: graphID, filter: filter)
    }

    private static func graphAction(
        nodeKindRaw: Int?,
        nodeID: UUID?,
        dashboardGraphID: UUID?
    ) -> GraphHealthResolvedAction? {
        guard let plan = GraphCanvasJumpActionResolver.resolve(
            graphID: dashboardGraphID,
            nodeKindRaw: nodeKindRaw,
            nodeID: nodeID
        ) else {
            return nil
        }
        return .jumpToGraph(plan)
    }
}
