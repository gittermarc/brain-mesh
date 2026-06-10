//
//  GraphHealthIssueListPresentation.swift
//  BrainMesh
//
//  Pure presentation model for affected Graph Health issue items.
//

import Foundation

nonisolated struct GraphHealthIssueListPresentation: Equatable, Sendable {
    let title: String
    let subtitle: String
    let items: [GraphHealthIssueListItemPresentation]

    static func make(issue: GraphHealthIssue) -> GraphHealthIssueListPresentation {
        GraphHealthIssueListPresentation(
            title: issue.title,
            subtitle: subtitle(for: issue),
            items: issue.affectedItems.map { item in
                GraphHealthIssueListItemPresentation.make(item: item, issueKind: issue.kind)
            }
        )
    }

    private static func subtitle(for issue: GraphHealthIssue) -> String {
        if issue.affectedItems.isEmpty {
            return "Für diesen Hinweis gibt es keine konkrete Eintragsliste."
        }
        if issue.affectedItems.count == 1 {
            return "1 betroffener Eintrag"
        }
        return "\(issue.affectedItems.count) betroffene Einträge"
    }
}

nonisolated struct GraphHealthIssueListItemPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let typeText: String
    let reasonText: String
    let detailText: String
    let symbolName: String

    static func make(
        item: GraphHealthAffectedItem,
        issueKind: GraphHealthIssueKind
    ) -> GraphHealthIssueListItemPresentation {
        let typeText = itemTypeText(item)
        return GraphHealthIssueListItemPresentation(
            id: item.id,
            title: sanitizedTitle(item.label),
            typeText: typeText,
            reasonText: reasonText(issueKind: issueKind, item: item),
            detailText: detailText(item: item),
            symbolName: symbolName(item: item)
        )
    }

    private static func sanitizedTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Eintrag" : trimmed
    }

    private static func itemTypeText(_ item: GraphHealthAffectedItem) -> String {
        if item.byteCount != nil { return "Anhang" }

        if let nodeKindRaw = item.nodeKindRaw, let kind = NodeKind(rawValue: nodeKindRaw) {
            return nodeKindTitle(kind)
        }

        if let ownerKindRaw = item.ownerKindRaw, let kind = NodeKind(rawValue: ownerKindRaw) {
            return "Owner: \(nodeKindTitle(kind))"
        }

        return "Eintrag"
    }

    private static func reasonText(
        issueKind: GraphHealthIssueKind,
        item: GraphHealthAffectedItem
    ) -> String {
        switch issueKind {
        case .isolatedEntities:
            return "Keine sichtbaren Verbindungen"
        case .entitiesWithoutAttributes:
            return "Noch keine Attribute"
        case .entitiesWithoutDetailsSchema:
            return "Noch kein Detail-Schema"
        case .largeAttachments:
            return "Große Datei"
        case .topHubs:
            return item.count.map { "\($0) Verbindungen" } ?? "Viele Verbindungen"
        case .mediaRichNodes:
            return item.count.map { "\($0) Medien" } ?? "Viele Medien"
        case .lowLinkDensity:
            return "Wenige Verbindungen"
        }
    }

    private static func detailText(item: GraphHealthAffectedItem) -> String {
        var parts: [String] = []

        if let byteCount = item.byteCount {
            parts.append(byteCountText(byteCount))
        }

        if let ownerLabel = item.ownerLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           ownerLabel.isEmpty == false {
            parts.append("Owner: \(ownerLabel)")
        } else if let ownerID = item.ownerID {
            parts.append("Owner: \(shortID(ownerID))")
        }

        if let count = item.count, item.byteCount == nil {
            parts.append("Wert: \(count)")
        }

        return parts.isEmpty ? "Bereit für Review" : parts.joined(separator: " • ")
    }

    private static func symbolName(item: GraphHealthAffectedItem) -> String {
        if item.byteCount != nil { return "paperclip" }

        if let nodeKindRaw = item.nodeKindRaw, let kind = NodeKind(rawValue: nodeKindRaw) {
            return symbolName(kind)
        }

        if let ownerKindRaw = item.ownerKindRaw, let kind = NodeKind(rawValue: ownerKindRaw) {
            return symbolName(kind)
        }

        return "circle"
    }

    private static func nodeKindTitle(_ kind: NodeKind) -> String {
        switch kind {
        case .entity:
            return "Entität"
        case .attribute:
            return "Attribut"
        }
    }

    private static func symbolName(_ kind: NodeKind) -> String {
        switch kind {
        case .entity:
            return "cube"
        case .attribute:
            return "tag"
        }
    }

    private static func byteCountText(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    private static func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
