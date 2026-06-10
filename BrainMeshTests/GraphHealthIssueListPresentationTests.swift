import Foundation
import Testing
@testable import BrainMesh

struct GraphHealthIssueListPresentationTests {

    @Test
    func largeAttachmentPresentationShowsSizeAndOwner() throws {
        let attachmentID = UUID()
        let ownerID = UUID()
        let issue = GraphHealthIssue(
            id: "large-attachments",
            kind: .largeAttachments,
            severity: .warning,
            title: "Große Anhänge",
            message: "Große Dateien prüfen.",
            count: 1,
            primaryNodeKindRaw: NodeKind.entity.rawValue,
            primaryNodeID: ownerID,
            affectedItems: [
                .attachment(
                    id: attachmentID,
                    label: "Roadmap.pdf",
                    ownerKindRaw: NodeKind.entity.rawValue,
                    ownerID: ownerID,
                    ownerLabel: "Roadmap",
                    byteCount: 35 * 1_024 * 1_024
                )
            ],
            actionHint: .reviewMedia(title: "Anhänge prüfen", message: "Große Dateien ansehen.")
        )

        let presentation = GraphHealthIssueListPresentation.make(issue: issue)
        let item = try #require(presentation.items.first)

        #expect(presentation.title == "Große Anhänge")
        #expect(presentation.subtitle == "1 betroffener Eintrag")
        #expect(item.id == attachmentID)
        #expect(item.title == "Roadmap.pdf")
        #expect(item.typeText == "Anhang")
        #expect(item.reasonText == "Große Datei")
        #expect(item.detailText.contains("Owner: Roadmap"))
        #expect(item.symbolName == "paperclip")
    }

    @Test
    func topHubPresentationShowsConnectionReason() throws {
        let hubID = UUID()
        let issue = GraphHealthIssue(
            id: "top-hubs",
            kind: .topHubs,
            severity: .info,
            title: "Top-Hubs im Graph",
            message: "Hub prüfen.",
            count: 1,
            primaryNodeKindRaw: NodeKind.entity.rawValue,
            primaryNodeID: hubID,
            affectedItems: [
                .node(id: hubID, label: "Atlas", kind: .entity, count: 7)
            ],
            actionHint: .reviewStructure(title: "Hub fokussieren", message: "Im Graph ansehen.")
        )

        let presentation = GraphHealthIssueListPresentation.make(issue: issue)
        let item = try #require(presentation.items.first)

        #expect(item.title == "Atlas")
        #expect(item.typeText == "Entität")
        #expect(item.reasonText == "7 Verbindungen")
        #expect(item.detailText == "Wert: 7")
        #expect(item.symbolName == "cube")
    }

    @Test
    func emptyIssueListCopyIsStable() {
        let issue = GraphHealthIssue(
            id: "low-density",
            kind: .lowLinkDensity,
            severity: .info,
            title: "Niedrige Link-Dichte",
            message: "Mehr Verbindungen helfen.",
            count: 2,
            primaryNodeKindRaw: nil,
            primaryNodeID: nil,
            affectedItems: [],
            actionHint: .reviewStructure(title: "Verbindungen ergänzen", message: "Links nachtragen.")
        )

        let presentation = GraphHealthIssueListPresentation.make(issue: issue)

        #expect(presentation.subtitle == "Für diesen Hinweis gibt es keine konkrete Eintragsliste.")
        #expect(presentation.items.isEmpty)
    }
}
