import Foundation
import Testing
@testable import BrainMesh

struct GraphHealthScoreTests {

    @Test
    func scoreIsDeterministicForSameInputs() {
        let counts = GraphCounts(
            entities: 8,
            attributes: 4,
            links: 2,
            notes: 0,
            images: 0,
            attachments: 0,
            attachmentBytes: 0
        )
        let issue = GraphHealthIssue(
            id: "deterministic-isolated",
            kind: .isolatedEntities,
            severity: .attention,
            title: "Isolierte Entitäten",
            message: "Mehrere Entitäten sind noch nicht verbunden.",
            count: 3,
            primaryNodeKindRaw: NodeKind.entity.rawValue,
            primaryNodeID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            affectedItems: [],
            actionHint: .reviewStructure(title: "Prüfen", message: "Verbindungen ergänzen.")
        )

        let first = GraphHealthScore.make(counts: counts, issues: [issue])
        let second = GraphHealthScore.make(counts: counts, issues: [issue])

        #expect(first == second)
        #expect(first.value >= 0)
        #expect(first.value <= 100)
    }

    @Test
    func smallEmptyGraphIsNotRatedAsBroken() {
        let score = GraphHealthScore.make(counts: .zero, issues: [])

        #expect(score.value > 0)
        #expect(score.title == "Solide")
    }

    @Test
    func severeIssuesLowerScoreButStayWithinRange() {
        let counts = GraphCounts(
            entities: 20,
            attributes: 10,
            links: 5,
            notes: 0,
            images: 0,
            attachments: 4,
            attachmentBytes: 400_000_000
        )
        let issue = GraphHealthIssue(
            id: "large-attachments",
            kind: .largeAttachments,
            severity: .warning,
            title: "Große Anhänge",
            message: "Einige Anhänge sind groß.",
            count: 4,
            primaryNodeKindRaw: NodeKind.entity.rawValue,
            primaryNodeID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            affectedItems: [],
            actionHint: .reviewMedia(title: "Prüfen", message: "Anhänge prüfen.")
        )

        let score = GraphHealthScore.make(counts: counts, issues: [issue])

        #expect(score.value < 100)
        #expect(score.value >= 0)
        #expect(score.value <= 100)
    }
}
