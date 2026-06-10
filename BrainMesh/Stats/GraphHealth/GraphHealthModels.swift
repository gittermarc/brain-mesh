//
//  GraphHealthModels.swift
//  BrainMesh
//

import Foundation

nonisolated enum GraphHealthIssueKind: String, Codable, CaseIterable, Sendable {
    case isolatedEntities
    case entitiesWithoutAttributes
    case entitiesWithoutDetailsSchema
    case largeAttachments
    case topHubs
    case mediaRichNodes
    case lowLinkDensity

    var sortRank: Int {
        switch self {
        case .largeAttachments: return 0
        case .entitiesWithoutDetailsSchema: return 1
        case .entitiesWithoutAttributes: return 2
        case .isolatedEntities: return 3
        case .lowLinkDensity: return 4
        case .topHubs: return 5
        case .mediaRichNodes: return 6
        }
    }
}

nonisolated enum GraphHealthIssueSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case attention
    case warning

    var sortRank: Int {
        switch self {
        case .warning: return 0
        case .attention: return 1
        case .info: return 2
        }
    }

    var baseScorePenalty: Int {
        switch self {
        case .warning: return 14
        case .attention: return 9
        case .info: return 3
        }
    }
}

nonisolated enum GraphHealthActionHintKind: String, Codable, CaseIterable, Sendable {
    case openGraph
    case reviewDetails
    case reviewMedia
    case reviewStructure
}

nonisolated struct GraphHealthActionHint: Equatable, Codable, Sendable {
    let kind: GraphHealthActionHintKind
    let title: String
    let message: String
    let systemImage: String

    static func openGraph(title: String, message: String, systemImage: String = "circle.grid.cross") -> GraphHealthActionHint {
        GraphHealthActionHint(
            kind: .openGraph,
            title: title,
            message: message,
            systemImage: systemImage
        )
    }

    static func reviewDetails(title: String, message: String) -> GraphHealthActionHint {
        GraphHealthActionHint(
            kind: .reviewDetails,
            title: title,
            message: message,
            systemImage: "list.bullet.rectangle"
        )
    }

    static func reviewMedia(title: String, message: String) -> GraphHealthActionHint {
        GraphHealthActionHint(
            kind: .reviewMedia,
            title: title,
            message: message,
            systemImage: "paperclip"
        )
    }

    static func reviewStructure(title: String, message: String) -> GraphHealthActionHint {
        GraphHealthActionHint(
            kind: .reviewStructure,
            title: title,
            message: message,
            systemImage: "point.3.connected.trianglepath.dotted"
        )
    }
}

nonisolated struct GraphHealthAffectedItem: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let label: String
    let nodeKindRaw: Int?
    let nodeID: UUID?
    let ownerKindRaw: Int?
    let ownerID: UUID?
    let count: Int?
    let byteCount: Int64?

    static func node(
        id: UUID,
        label: String,
        kind: NodeKind,
        count: Int? = nil
    ) -> GraphHealthAffectedItem {
        GraphHealthAffectedItem(
            id: id,
            label: label,
            nodeKindRaw: kind.rawValue,
            nodeID: id,
            ownerKindRaw: nil,
            ownerID: nil,
            count: count,
            byteCount: nil
        )
    }

    static func attachment(
        id: UUID,
        label: String,
        ownerKindRaw: Int,
        ownerID: UUID,
        byteCount: Int64
    ) -> GraphHealthAffectedItem {
        GraphHealthAffectedItem(
            id: id,
            label: label,
            nodeKindRaw: nil,
            nodeID: nil,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            count: nil,
            byteCount: byteCount
        )
    }
}

nonisolated struct GraphHealthIssue: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let kind: GraphHealthIssueKind
    let severity: GraphHealthIssueSeverity
    let title: String
    let message: String
    let count: Int
    let primaryNodeKindRaw: Int?
    let primaryNodeID: UUID?
    let affectedItems: [GraphHealthAffectedItem]
    let actionHint: GraphHealthActionHint

    var affectedNodeIDs: [UUID] {
        affectedItems.compactMap(\.nodeID)
    }
}

nonisolated struct GraphHealthScore: Equatable, Codable, Sendable {
    let value: Int
    let title: String
    let message: String

    static func make(
        counts: GraphCounts,
        issues: [GraphHealthIssue]
    ) -> GraphHealthScore {
        let nodeCount = counts.entities + counts.attributes
        guard nodeCount > 0 else {
            return GraphHealthScore(
                value: 100,
                title: "Solide",
                message: "Noch keine Strukturpunkte. Der Graph wird bewertet, sobald Inhalte vorhanden sind."
            )
        }

        let rawPenalty = issues.reduce(into: 0) { partialResult, issue in
            let countPenalty = min(8, max(0, issue.count - 1) * 2)
            partialResult += issue.severity.baseScorePenalty + countPenalty
        }

        let maxPenalty: Int
        if nodeCount < 4 {
            maxPenalty = 18
        } else if nodeCount < 10 {
            maxPenalty = 45
        } else {
            maxPenalty = 75
        }

        let value = max(0, min(100, 100 - min(rawPenalty, maxPenalty)))
        return GraphHealthScore(
            value: value,
            title: title(for: value),
            message: message(for: value)
        )
    }

    private static func title(for value: Int) -> String {
        if value >= 80 { return "Solide" }
        if value >= 55 { return "Aufräumen lohnt sich" }
        return "Viele offene Strukturpunkte"
    }

    private static func message(for value: Int) -> String {
        if value >= 80 {
            return "Die Struktur wirkt insgesamt stabil. Einzelne Hinweise können trotzdem nützlich sein."
        }
        if value >= 55 {
            return "Ein paar gezielte Aufräumaktionen machen den Graph leichter lesbar."
        }
        return "Mehrere Strukturpunkte bremsen die Übersicht. Ein fokussierter Cleanup lohnt sich."
    }
}

nonisolated struct GraphHealthSnapshot: Equatable, Sendable {
    let graphID: UUID?
    let counts: GraphCounts
    let score: GraphHealthScore
    let issues: [GraphHealthIssue]

    static func empty(graphID: UUID?) -> GraphHealthSnapshot {
        let issues: [GraphHealthIssue] = []
        return GraphHealthSnapshot(
            graphID: graphID,
            counts: .zero,
            score: GraphHealthScore.make(counts: .zero, issues: issues),
            issues: issues
        )
    }

    var hasActionableIssues: Bool {
        issues.isEmpty == false
    }
}
