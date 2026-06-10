import Foundation
import Testing
@testable import BrainMesh

struct BrainMeshSearchServiceTests {

    @Test
    func graphScopedSearchFindsOnlyActiveGraphMatches() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let primary = fixtures.makeEntity(name: "Atlas", in: primaryGraph)
        let _ = fixtures.makeEntity(name: "Atlas", in: secondaryGraph)
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: primaryGraph.id, term: "atlas")

        #expect(snapshot.results.map(\.id) == [primary.id])
        #expect(snapshot.results.allSatisfy { $0.graphID == primaryGraph.id })
    }

    @Test
    func entityNameMatchRanksBeforeEntityNoteMatch() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let noteOnly = fixtures.makeEntity(name: "Alpha", in: graph, notes: "Atlas appears in notes")
        let nameMatch = fixtures.makeEntity(name: "Atlas", in: graph)
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "atlas")

        #expect(snapshot.results.first?.id == nameMatch.id)
        #expect(snapshot.results.contains { $0.id == noteOnly.id })
        #expect(snapshot.results.first?.matchReason == "Name")
    }

    @Test
    func attributeSearchLabelFindsAttributeResult() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Project Atlas", in: graph)
        let attribute = fixtures.makeAttribute(name: "Launch Date", owner: owner)
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "launch")
        let result = snapshot.results.first { $0.kind == .attribute }

        #expect(result?.id == attribute.id)
        #expect(result?.nodeKey == NodeKey(kind: .attribute, uuid: attribute.id))
        #expect(result?.subtitle == "Project Atlas")
    }

    @Test
    func linkNoteFindsLinkResult() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let source = fixtures.makeEntity(name: "Atlas", in: graph)
        let target = fixtures.makeEntity(name: "Beacon", in: graph)
        let link = fixtures.makeLink(source: .entity(source), target: .entity(target), note: "Orbit marker")
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "orbit")
        let result = snapshot.results.first { $0.kind == .link }

        #expect(result?.id == link.id)
        #expect(result?.title == "Atlas → Beacon")
        #expect(result?.matchReason == "Link-Notiz")
    }

    @Test
    func detailFieldDefinitionFindsDetailResult() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Project Atlas", in: graph)
        let field = fixtures.makeDetailField(owner: owner, name: "Risk Level", type: .singleLineText, sortIndex: 0)
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "risk")
        let result = snapshot.results.first { $0.kind == .detail && $0.id == field.id }

        #expect(result?.title == "Risk Level")
        #expect(result?.ownerNodeKey == NodeKey(kind: .entity, uuid: owner.id))
    }

    @Test
    func detailFieldValueStringFindsDetailResult() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Project Atlas", in: graph)
        let attribute = fixtures.makeAttribute(name: "Plan", owner: owner)
        let field = fixtures.makeDetailField(owner: owner, name: "Status", type: .singleLineText, sortIndex: 0)
        let value = fixtures.makeDetailValue(attribute: attribute, field: field, stringValue: "Gold rollout")
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "gold")
        let result = snapshot.results.first { $0.kind == .detail && $0.id == value.id }

        #expect(result?.title == "Status: Gold rollout")
        #expect(result?.ownerNodeKey == NodeKey(kind: .attribute, uuid: attribute.id))
        #expect(result?.matchReason == "Detailwert")
    }

    @Test
    func typedDetailValuesAreSearchable() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Project Atlas", in: graph)
        let attribute = fixtures.makeAttribute(name: "Budget", owner: owner)
        let field = fixtures.makeDetailField(owner: owner, name: "Amount", type: .numberInt, sortIndex: 0)
        let value = fixtures.makeDetailValue(attribute: attribute, field: field, intValue: 42)
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "42")
        let result = snapshot.results.first { $0.kind == .detail && $0.id == value.id }

        #expect(result?.title == "Amount: 42")
    }

    @Test
    func attachmentMetadataFindsAttachmentResultWithoutUsingFileData() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Project Atlas", in: graph)
        let attachment = fixtures.makeAttachment(
            owner: .entity(owner),
            title: "Launch Blueprint",
            originalFilename: "blueprint.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data(repeating: 7, count: 512)
        )
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "blueprint")
        let result = snapshot.results.first { $0.kind == .attachment }

        #expect(result?.id == attachment.id)
        #expect(result?.ownerNodeKey == NodeKey(kind: .entity, uuid: owner.id))
        #expect(result?.subtitle == "blueprint.pdf")
    }

    @Test
    func deterministicRankingSortsSameScoreAlphabetically() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let beta = fixtures.makeEntity(name: "Atlas Beta", in: graph)
        let alpha = fixtures.makeEntity(name: "Atlas Alpha", in: graph)
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "atlas")

        #expect(snapshot.entityResults.map(\.id) == [alpha.id, beta.id])
    }

    @Test
    func emptySearchDoesNotFetchLargeResultSet() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let _ = fixtures.makeEntity(name: "Atlas", in: graph)
        let _ = fixtures.makeEntity(name: "Beacon", in: graph)
        try fixtures.save()

        let snapshot = try await search(in: testStore, graphID: graph.id, term: "")

        #expect(snapshot.results.isEmpty)
    }

    private func search(
        in testStore: BrainMeshTestStore,
        graphID: UUID?,
        term: String,
        limit: Int = 20
    ) async throws -> BrainMeshSearchSnapshot {
        let service = BrainMeshSearchService()
        await service.configure(container: AnyModelContainer(testStore.container))
        return try await service.search(graphID: graphID, foldedQuery: BMSearch.fold(term), limit: limit)
    }
}
