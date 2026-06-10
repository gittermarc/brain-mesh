//
//  GraphHealthCenterPresentation.swift
//  BrainMesh
//

import Foundation

nonisolated enum GraphHealthScoreBand: Equatable, Sendable {
    case solid
    case cleanupWorthwhile
    case manyOpenStructurePoints

    static func make(for value: Int) -> GraphHealthScoreBand {
        if value >= 80 { return .solid }
        if value >= 55 { return .cleanupWorthwhile }
        return .manyOpenStructurePoints
    }

    var title: String {
        switch self {
        case .solid:
            return "Solide"
        case .cleanupWorthwhile:
            return "Aufräumen lohnt sich"
        case .manyOpenStructurePoints:
            return "Viele offene Strukturpunkte"
        }
    }
}

nonisolated struct GraphHealthCenterPresentation: Equatable, Sendable {
    let scoreValue: Int
    let scoreTitle: String
    let scoreMessage: String
    let statusText: String
    let issueSectionTitle: String
    let visibleIssues: [GraphHealthIssuePresentation]
    let hiddenIssueCount: Int
    let showsSmallGraphNote: Bool
    let smallGraphNote: String?
    let isGoodState: Bool

    static func make(
        snapshot: GraphHealthSnapshot,
        maxVisibleIssues: Int = 5
    ) -> GraphHealthCenterPresentation {
        let orderedIssues = sortedIssues(snapshot.issues)
        let visibleLimit = max(0, maxVisibleIssues)
        let visibleIssues = Array(orderedIssues.prefix(visibleLimit)).map(GraphHealthIssuePresentation.make(issue:))
        let hiddenIssueCount = max(0, orderedIssues.count - visibleIssues.count)
        let nodeCount = snapshot.counts.entities + snapshot.counts.attributes
        let isSmallGraph = nodeCount < 4
        let hasIssues = snapshot.issues.isEmpty == false

        return GraphHealthCenterPresentation(
            scoreValue: snapshot.score.value,
            scoreTitle: scoreBandTitle(for: snapshot.score.value),
            scoreMessage: snapshot.score.message,
            statusText: statusText(
                hasIssues: hasIssues,
                warningCount: warningCount(in: snapshot.issues),
                issueCount: snapshot.issues.count,
                isSmallGraph: isSmallGraph
            ),
            issueSectionTitle: hasIssues ? "Empfohlene nächste Schritte" : "Keine akuten Strukturpunkte",
            visibleIssues: visibleIssues,
            hiddenIssueCount: hiddenIssueCount,
            showsSmallGraphNote: isSmallGraph,
            smallGraphNote: isSmallGraph ? "Health wird mit wachsendem Graph nützlicher. Kleine Graphen werden bewusst vorsichtig bewertet." : nil,
            isGoodState: hasIssues == false
        )
    }

    static func sortedIssues(_ issues: [GraphHealthIssue]) -> [GraphHealthIssue] {
        issues.sorted { lhs, rhs in
            if lhs.severity.sortRank != rhs.severity.sortRank {
                return lhs.severity.sortRank < rhs.severity.sortRank
            }
            if lhs.kind.sortRank != rhs.kind.sortRank {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.id < rhs.id
        }
    }

    static func scoreBandTitle(for value: Int) -> String {
        GraphHealthScoreBand.make(for: value).title
    }

    private static func warningCount(in issues: [GraphHealthIssue]) -> Int {
        issues.filter { $0.severity == .warning }.count
    }

    private static func statusText(
        hasIssues: Bool,
        warningCount: Int,
        issueCount: Int,
        isSmallGraph: Bool
    ) -> String {
        if hasIssues == false {
            if isSmallGraph {
                return "Der Graph ist noch klein und wirkt unauffällig."
            }
            return "Der Graph sieht solide aus."
        }

        if warningCount > 0 || issueCount >= 4 {
            return "Hier gibt es mehrere gute nächste Schritte."
        }

        return "Ein paar Strukturpunkte lohnen sich."
    }
}

nonisolated struct GraphHealthIssuePresentation: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let message: String
    let countText: String
    let severityTitle: String
    let severitySystemImage: String
    let actionTitle: String
    let actionMessage: String
    let actionSystemImage: String

    static func make(issue: GraphHealthIssue) -> GraphHealthIssuePresentation {
        GraphHealthIssuePresentation(
            id: issue.id,
            title: issue.title,
            message: issue.message,
            countText: countText(for: issue),
            severityTitle: severityTitle(for: issue.severity),
            severitySystemImage: severitySystemImage(for: issue.severity),
            actionTitle: issue.actionHint.title,
            actionMessage: issue.actionHint.message,
            actionSystemImage: issue.actionHint.systemImage
        )
    }

    private static func countText(for issue: GraphHealthIssue) -> String {
        switch issue.kind {
        case .largeAttachments:
            return issue.count == 1 ? "1 Anhang" : "\(issue.count) Anhänge"
        case .entitiesWithoutAttributes, .entitiesWithoutDetailsSchema, .isolatedEntities:
            return issue.count == 1 ? "1 Entität" : "\(issue.count) Entitäten"
        case .topHubs, .mediaRichNodes:
            return issue.count == 1 ? "1 Knoten" : "\(issue.count) Knoten"
        case .lowLinkDensity:
            return issue.count == 1 ? "1 Link" : "\(issue.count) Links"
        }
    }

    private static func severityTitle(for severity: GraphHealthIssueSeverity) -> String {
        switch severity {
        case .warning:
            return "Wichtig"
        case .attention:
            return "Aufmerksamkeit"
        case .info:
            return "Hinweis"
        }
    }

    private static func severitySystemImage(for severity: GraphHealthIssueSeverity) -> String {
        switch severity {
        case .warning:
            return "exclamationmark.triangle"
        case .attention:
            return "circle.dashed"
        case .info:
            return "info.circle"
        }
    }
}
