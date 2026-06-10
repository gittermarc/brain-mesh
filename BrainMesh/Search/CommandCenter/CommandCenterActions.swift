//
//  CommandCenterActions.swift
//  BrainMesh
//
//  Pure routing decisions for command center actions.
//

import Foundation

enum CommandCenterQuickAction: String, CaseIterable, Identifiable, Sendable {
    case addEntity
    case openGraph
    case openStats
    case graphTransfer
    case guide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addEntity:
            return "Neue Entität"
        case .openGraph:
            return "Zum Graph"
        case .openStats:
            return "Zu Stats"
        case .graphTransfer:
            return "Export & Import"
        case .guide:
            return "Anleitung öffnen"
        }
    }

    var subtitle: String {
        switch self {
        case .addEntity:
            return "Einen neuen Knoten im aktiven Graph anlegen"
        case .openGraph:
            return "Den aktuellen Graph visuell erkunden"
        case .openStats:
            return "Kennzahlen und Struktur prüfen"
        case .graphTransfer:
            return "Graph-Struktur sichern oder importieren"
        case .guide:
            return "Begriffe, Sync und Workflows nachlesen"
        }
    }

    var systemImage: String {
        switch self {
        case .addEntity:
            return "plus.circle"
        case .openGraph:
            return "circle.grid.cross"
        case .openStats:
            return "chart.bar"
        case .graphTransfer:
            return "square.and.arrow.up.on.square"
        case .guide:
            return "book"
        }
    }
}

enum CommandCenterResolvedAction: Equatable, Sendable {
    case present(CommandCenterDestination)
    case selectTab(RootTab)
    case jumpToGraph(graphID: UUID, nodeKey: NodeKey)
}

enum CommandCenterActionResolver {
    static func action(for quickAction: CommandCenterQuickAction) -> CommandCenterResolvedAction {
        switch quickAction {
        case .addEntity:
            return .present(.addEntity)
        case .openGraph:
            return .selectTab(.graph)
        case .openStats:
            return .selectTab(.stats)
        case .graphTransfer:
            return .present(.graphTransfer)
        case .guide:
            return .present(.guide)
        }
    }

    static func primaryAction(for result: BrainMeshSearchResult) -> CommandCenterResolvedAction {
        if let nodeKey = result.nodeKey {
            return .present(.nodeDetail(kind: nodeKey.kind, id: nodeKey.uuid))
        }

        if let ownerNodeKey = result.ownerNodeKey {
            return .present(.nodeDetail(kind: ownerNodeKey.kind, id: ownerNodeKey.uuid))
        }

        return .selectTab(.graph)
    }

    static func graphAction(for result: BrainMeshSearchResult) -> CommandCenterResolvedAction? {
        guard let graphID = result.graphID else { return nil }
        guard let nodeKey = result.nodeKey ?? result.ownerNodeKey else { return nil }
        return .jumpToGraph(graphID: graphID, nodeKey: nodeKey)
    }

    static func primaryAction(for recentItem: RecentNodeItem) -> CommandCenterResolvedAction? {
        guard let nodeKey = recentItem.nodeKey else { return nil }
        return .present(.nodeDetail(kind: nodeKey.kind, id: nodeKey.uuid))
    }

    static func graphAction(for recentItem: RecentNodeItem) -> CommandCenterResolvedAction? {
        guard let graphID = recentItem.graphID, let nodeKey = recentItem.nodeKey else { return nil }
        return .jumpToGraph(graphID: graphID, nodeKey: nodeKey)
    }
}
