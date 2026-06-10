import Foundation
import Testing
@testable import BrainMesh

struct GraphHealthIssuePresentationTests {

    @Test
    func actionHintsAreShownFromIssue() {
        let issue = GraphHealthIssue(
            id: "media-rich",
            kind: .mediaRichNodes,
            severity: .info,
            title: "Medienreiche Knoten",
            message: "Einige Knoten haben viele Medien.",
            count: 3,
            primaryNodeKindRaw: NodeKind.entity.rawValue,
            primaryNodeID: UUID(uuidString: "00000000-0000-0000-0000-000000000011"),
            affectedItems: [],
            actionHint: .reviewMedia(title: "Medien prüfen", message: "Anhänge kuratieren.")
        )

        let presentation = GraphHealthIssuePresentation.make(issue: issue)

        #expect(presentation.id == "media-rich")
        #expect(presentation.actionTitle == "Medien prüfen")
        #expect(presentation.actionMessage == "Anhänge kuratieren.")
        #expect(presentation.actionSystemImage == "paperclip")
    }

    @Test
    func countTextUsesIssueSpecificNouns() {
        let attachment = GraphHealthIssuePresentation.make(
            issue: makePresentationIssue(kind: .largeAttachments, count: 2)
        )
        let entity = GraphHealthIssuePresentation.make(
            issue: makePresentationIssue(kind: .isolatedEntities, count: 1)
        )
        let hub = GraphHealthIssuePresentation.make(
            issue: makePresentationIssue(kind: .topHubs, count: 4)
        )
        let lowDensity = GraphHealthIssuePresentation.make(
            issue: makePresentationIssue(kind: .lowLinkDensity, count: 1)
        )

        #expect(attachment.countText == "2 Anhänge")
        #expect(entity.countText == "1 Entität")
        #expect(hub.countText == "4 Knoten")
        #expect(lowDensity.countText == "1 Link")
    }

    @Test
    func severityCopyIsStable() {
        let warning = GraphHealthIssuePresentation.make(
            issue: makePresentationIssue(kind: .largeAttachments, severity: .warning)
        )
        let attention = GraphHealthIssuePresentation.make(
            issue: makePresentationIssue(kind: .entitiesWithoutAttributes, severity: .attention)
        )
        let info = GraphHealthIssuePresentation.make(
            issue: makePresentationIssue(kind: .topHubs, severity: .info)
        )

        #expect(warning.severityTitle == "Wichtig")
        #expect(warning.severitySystemImage == "exclamationmark.triangle")
        #expect(attention.severityTitle == "Aufmerksamkeit")
        #expect(info.severityTitle == "Hinweis")
    }
}

private func makePresentationIssue(
    kind: GraphHealthIssueKind,
    severity: GraphHealthIssueSeverity = .info,
    count: Int = 1
) -> GraphHealthIssue {
    GraphHealthIssue(
        id: "presentation-\(kind.rawValue)",
        kind: kind,
        severity: severity,
        title: "Titel",
        message: "Beschreibung",
        count: count,
        primaryNodeKindRaw: NodeKind.entity.rawValue,
        primaryNodeID: UUID(uuidString: "00000000-0000-0000-0000-000000000012"),
        affectedItems: [],
        actionHint: .reviewStructure(title: "Prüfen", message: "Im Graph ansehen.")
    )
}
