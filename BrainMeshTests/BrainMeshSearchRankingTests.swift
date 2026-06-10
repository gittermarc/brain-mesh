import Foundation
import Testing
@testable import BrainMesh

struct BrainMeshSearchRankingTests {

    @Test
    func primaryLabelContainsBeatsExactNotesMatch() {
        let query = BMSearch.fold("atlas")
        let match = BrainMeshSearchRanking.bestMatch(
            foldedQuery: query,
            fields: [
                BrainMeshSearchRankingField(text: "Atlas appears in a note", reason: "Notiz", priority: .notes),
                BrainMeshSearchRankingField(text: "Project Atlas", reason: "Name", priority: .primaryLabel)
            ]
        )

        #expect(match?.matchReason == "Name")
    }

    @Test
    func exactLabelBeatsPrefixAndContainsMatches() {
        let exact = BrainMeshSearchRanking.bestMatch(
            foldedQuery: BMSearch.fold("atlas"),
            fields: [BrainMeshSearchRankingField(text: "Atlas", reason: "Name", priority: .primaryLabel)]
        )
        let prefix = BrainMeshSearchRanking.bestMatch(
            foldedQuery: BMSearch.fold("atlas"),
            fields: [BrainMeshSearchRankingField(text: "Atlas Map", reason: "Name", priority: .primaryLabel)]
        )
        let contains = BrainMeshSearchRanking.bestMatch(
            foldedQuery: BMSearch.fold("atlas"),
            fields: [BrainMeshSearchRankingField(text: "Project Atlas", reason: "Name", priority: .primaryLabel)]
        )

        #expect(exact?.score == 0)
        #expect(prefix?.score == 1)
        #expect(contains?.score == 2)
    }

    @Test
    func deterministicSortUsesKindThenFoldedTitleThenID() {
        let sharedScore = 0
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let attributeID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let secondEntityID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        let candidates = [
            makeCandidate(kind: .attribute, id: attributeID, title: "Alpha", score: sharedScore),
            makeCandidate(kind: .entity, id: secondEntityID, title: "Beta", score: sharedScore),
            makeCandidate(kind: .entity, id: entityID, title: "Alpha", score: sharedScore)
        ]

        let sorted = BrainMeshSearchRanking.sortedCandidates(candidates)

        #expect(sorted.map(\.result.id) == [entityID, secondEntityID, attributeID])
    }

    private func makeCandidate(
        kind: BrainMeshSearchResultKind,
        id: UUID,
        title: String,
        score: Int
    ) -> BrainMeshSearchCandidate {
        let result = BrainMeshSearchResult(
            kind: kind,
            id: id,
            graphID: nil,
            title: title,
            subtitle: "Test",
            iconSymbolName: kind.defaultIconSymbolName,
            matchReason: "Name",
            nodeKindRaw: kind == .entity ? NodeKind.entity.rawValue : nil,
            nodeID: kind == .entity ? id : nil,
            ownerKindRaw: nil,
            ownerID: nil
        )
        return BrainMeshSearchCandidate(result: result, score: score)
    }
}
