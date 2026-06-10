import Foundation
import Testing
@testable import BrainMesh

struct GraphHealthCenterPresentationTests {

    @Test
    func issuesAreSortedBySeverityAndPriority() {
        let warning = makeIssue(kind: .largeAttachments, severity: .warning, count: 1, idSuffix: "warning")
        let attention = makeIssue(kind: .entitiesWithoutAttributes, severity: .attention, count: 9, idSuffix: "attention")
        let info = makeIssue(kind: .topHubs, severity: .info, count: 20, idSuffix: "info")
        let snapshot = makeSnapshot(issues: [info, attention, warning])

        let presentation = GraphHealthCenterPresentation.make(snapshot: snapshot)

        #expect(presentation.visibleIssues.map(\.id) == [warning.id, attention.id, info.id])
        #expect(presentation.statusText == "Hier gibt es mehrere gute nächste Schritte.")
    }

    @Test
    func maxVisibleIssuesIsRespected() {
        let issues = [
            makeIssue(kind: .largeAttachments, severity: .warning, count: 1, idSuffix: "0"),
            makeIssue(kind: .entitiesWithoutDetailsSchema, severity: .attention, count: 2, idSuffix: "1"),
            makeIssue(kind: .entitiesWithoutAttributes, severity: .attention, count: 3, idSuffix: "2"),
            makeIssue(kind: .isolatedEntities, severity: .info, count: 4, idSuffix: "3"),
            makeIssue(kind: .topHubs, severity: .info, count: 5, idSuffix: "4")
        ]
        let snapshot = makeSnapshot(issues: issues)

        let presentation = GraphHealthCenterPresentation.make(snapshot: snapshot, maxVisibleIssues: 3)

        #expect(presentation.visibleIssues.count == 3)
        #expect(presentation.hiddenIssueCount == 2)
    }

    @Test
    func emptyGoodStateCopyIsCalm() {
        let snapshot = makeSnapshot(counts: populatedCounts(), issues: [])

        let presentation = GraphHealthCenterPresentation.make(snapshot: snapshot)

        #expect(presentation.isGoodState)
        #expect(presentation.statusText == "Der Graph sieht solide aus.")
        #expect(presentation.issueSectionTitle == "Keine akuten Strukturpunkte")
        #expect(presentation.visibleIssues.isEmpty)
    }

    @Test
    func smallGraphReceivesHelpfulNote() {
        let snapshot = makeSnapshot(counts: .zero, issues: [])

        let presentation = GraphHealthCenterPresentation.make(snapshot: snapshot)

        #expect(presentation.showsSmallGraphNote)
        #expect(presentation.statusText == "Der Graph ist noch klein und wirkt unauffällig.")
        #expect(presentation.smallGraphNote == "Health wird mit wachsendem Graph nützlicher. Kleine Graphen werden bewusst vorsichtig bewertet.")
    }

    @Test
    func scoreBandsReturnExpectedLabels() {
        #expect(GraphHealthCenterPresentation.scoreBandTitle(for: 91) == "Solide")
        #expect(GraphHealthCenterPresentation.scoreBandTitle(for: 65) == "Aufräumen lohnt sich")
        #expect(GraphHealthCenterPresentation.scoreBandTitle(for: 24) == "Viele offene Strukturpunkte")
    }
}

private func makeSnapshot(
    counts: GraphCounts = populatedCounts(),
    issues: [GraphHealthIssue]
) -> GraphHealthSnapshot {
    GraphHealthSnapshot(
        graphID: UUID(uuidString: "00000000-0000-0000-0000-000000000100"),
        counts: counts,
        score: GraphHealthScore.make(counts: counts, issues: issues),
        issues: issues
    )
}

private func populatedCounts() -> GraphCounts {
    GraphCounts(
        entities: 8,
        attributes: 4,
        links: 6,
        notes: 1,
        images: 0,
        attachments: 0,
        attachmentBytes: 0
    )
}

private func makeIssue(
    kind: GraphHealthIssueKind,
    severity: GraphHealthIssueSeverity,
    count: Int,
    idSuffix: String
) -> GraphHealthIssue {
    GraphHealthIssue(
        id: "issue-\(idSuffix)",
        kind: kind,
        severity: severity,
        title: title(for: kind),
        message: "Ruhige Erklärung für \(kind.rawValue).",
        count: count,
        primaryNodeKindRaw: NodeKind.entity.rawValue,
        primaryNodeID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
        affectedItems: [],
        actionHint: .reviewStructure(title: "Im Graph prüfen", message: "Den betroffenen Bereich im Graph ansehen.")
    )
}

private func title(for kind: GraphHealthIssueKind) -> String {
    switch kind {
    case .isolatedEntities:
        return "Isolierte Entitäten"
    case .entitiesWithoutAttributes:
        return "Entitäten ohne Attribute"
    case .entitiesWithoutDetailsSchema:
        return "Entitäten ohne Detail-Schema"
    case .largeAttachments:
        return "Große Anhänge"
    case .topHubs:
        return "Top-Hubs im Graph"
    case .mediaRichNodes:
        return "Medienreiche Knoten"
    case .lowLinkDensity:
        return "Niedrige Link-Dichte"
    }
}
