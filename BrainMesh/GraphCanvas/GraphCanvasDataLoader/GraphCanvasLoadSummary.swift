//
//  GraphCanvasLoadSummary.swift
//  BrainMesh
//

import Foundation

enum GraphCanvasLoadSummaryMode: String, CaseIterable, Sendable {
    case global
    case neighborhood

    var title: String {
        switch self {
        case .global:
            return "Global"
        case .neighborhood:
            return "Fokus-Umgebung"
        }
    }
}

struct GraphCanvasLoadSummary: Equatable, Sendable {
    let mode: GraphCanvasLoadSummaryMode
    let focusEntityID: UUID?
    let nodesLoaded: Int
    let edgesLoaded: Int
    let maxNodes: Int
    let maxLinks: Int
    let includeAttributes: Bool

    var possibleNodeLimitReached: Bool {
        maxNodes > 0 && nodesLoaded >= maxNodes
    }

    var possibleLinkLimitReached: Bool {
        maxLinks > 0 && edgesLoaded >= maxLinks
    }

    var hasPossibleLimitReached: Bool {
        possibleNodeLimitReached || possibleLinkLimitReached
    }

    var reasonText: String? {
        guard hasPossibleLimitReached else { return nil }
        return "Möglicherweise wird der Ausschnitt durch Limits begrenzt."
    }

    var noticeFingerprint: String {
        [
            mode.rawValue,
            focusEntityID?.uuidString ?? "-",
            String(nodesLoaded),
            String(edgesLoaded),
            String(maxNodes),
            String(maxLinks),
            String(includeAttributes)
        ].joined(separator: "|")
    }
}

struct GraphCanvasLimitNoticeModel: Equatable, Sendable {
    let title: String
    let message: String
    let modeText: String
    let detailItems: [String]
    let showsHideAttributesAction: Bool

    static func make(summary: GraphCanvasLoadSummary?) -> GraphCanvasLimitNoticeModel? {
        guard let summary, summary.hasPossibleLimitReached else { return nil }

        var details: [String] = []
        details.append("Lademodus: \(summary.mode.title).")

        if summary.possibleNodeLimitReached {
            details.append("Knoten: \(summary.nodesLoaded) von maximal \(summary.maxNodes) geladen.")
        }

        if summary.possibleLinkLimitReached {
            details.append("Links: \(summary.edgesLoaded) von maximal \(summary.maxLinks) geladen.")
        }

        if summary.includeAttributes {
            details.append("Attribute sind eingeblendet; ohne Attribute passt oft mehr vom Fokus-Ausschnitt ins Limit.")
        }

        return GraphCanvasLimitNoticeModel(
            title: "Ausschnitt kann begrenzt sein",
            message: summary.reasonText ?? "Möglicherweise wird der Ausschnitt durch Limits begrenzt.",
            modeText: summary.mode.title,
            detailItems: details,
            showsHideAttributesAction: summary.includeAttributes
        )
    }

    static func compactStatusText(summary: GraphCanvasLoadSummary?) -> String? {
        guard let summary, summary.hasPossibleLimitReached else { return nil }

        switch (summary.possibleNodeLimitReached, summary.possibleLinkLimitReached) {
        case (true, true):
            return "Limits?"
        case (true, false):
            return "Node-Limit?"
        case (false, true):
            return "Link-Limit?"
        case (false, false):
            return nil
        }
    }
}
