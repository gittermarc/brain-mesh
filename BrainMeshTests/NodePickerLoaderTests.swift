import Foundation
import Testing
@testable import BrainMesh

struct NodePickerLoaderTests {

    @Test
    func entitySearchIsGraphScoped() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let primary = fixtures.makeEntity(name: "Atlas", in: primaryGraph)
        let _ = fixtures.makeEntity(name: "Atlas", in: secondaryGraph)
        try fixtures.save()

        let rows = try await loadEntities(in: testStore, graphID: primaryGraph.id, term: "atlas", limit: 20)

        #expect(rows.map(\.id) == [primary.id])
        #expect(rows.allSatisfy { $0.kindRaw == NodeKind.entity.rawValue })
    }

    @Test
    func attributeSearchIsGraphScoped() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let primaryEntity = fixtures.makeEntity(name: "Project Atlas", in: primaryGraph)
        let secondaryEntity = fixtures.makeEntity(name: "Project Beacon", in: secondaryGraph)
        let primaryAttribute = fixtures.makeAttribute(name: "Launch Date", owner: primaryEntity)
        let _ = fixtures.makeAttribute(name: "Launch Date", owner: secondaryEntity)
        try fixtures.save()

        let rows = try await loadAttributes(in: testStore, graphID: primaryGraph.id, term: "launch", limit: 20)

        #expect(rows.map(\.id) == [primaryAttribute.id])
        #expect(rows.allSatisfy { $0.kindRaw == NodeKind.attribute.rawValue })
    }

    @Test
    func searchLimitIsRespected() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let _ = fixtures.makeEntity(name: "Atlas Alpha", in: graph)
        let _ = fixtures.makeEntity(name: "Atlas Beta", in: graph)
        try fixtures.save()

        let rows = try await loadEntities(in: testStore, graphID: graph.id, term: "atlas", limit: 1)

        #expect(rows.count == 1)
    }

    @Test
    func emptySearchReturnsLimitedRows() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let alpha = fixtures.makeEntity(name: "Alpha", in: graph)
        let _ = fixtures.makeEntity(name: "Bravo", in: graph)
        try fixtures.save()

        let rows = try await loadEntities(in: testStore, graphID: graph.id, term: "", limit: 1)

        #expect(rows.map(\.id) == [alpha.id])
    }

    @Test
    func existingRowsForRecentsKeepRecentOrderAndFilterMissingNodes() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let first = fixtures.makeEntity(name: "Alpha", in: graph)
        let second = fixtures.makeEntity(name: "Bravo", in: graph)
        let missingID = UUID()
        try fixtures.save()

        let loader = NodePickerLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))
        let rows = try await loader.loadExistingRows(
            graphID: graph.id,
            kind: .entity,
            ids: [second.id, missingID, first.id, second.id]
        )

        #expect(rows.map(\.id) == [second.id, first.id])
    }

    private func loadEntities(
        in testStore: BrainMeshTestStore,
        graphID: UUID?,
        term: String,
        limit: Int
    ) async throws -> [NodePickerRowDTO] {
        let loader = NodePickerLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))
        return try await loader.loadEntities(graphID: graphID, foldedSearch: BMSearch.fold(term), limit: limit)
    }

    private func loadAttributes(
        in testStore: BrainMeshTestStore,
        graphID: UUID?,
        term: String,
        limit: Int
    ) async throws -> [NodePickerRowDTO] {
        let loader = NodePickerLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))
        return try await loader.loadAttributes(graphID: graphID, foldedSearch: BMSearch.fold(term), limit: limit)
    }
}
