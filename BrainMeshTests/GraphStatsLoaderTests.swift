import Foundation
import Testing
@testable import BrainMesh

struct GraphStatsLoaderTests {

    @Test
    func loadDashboardSnapshot_reusesCachedSnapshotWhenRevisionIsUnchanged() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Atlas", in: graph, notes: "Entity Note", imageData: Data([0x01]))
        let attribute = fixtures.makeAttribute(name: "Status", owner: entity, notes: "Attribute Note")
        _ = fixtures.makeLink(source: .entity(entity), target: .attribute(attribute), note: "Connected", graphID: graph.id)
        _ = fixtures.makeAttachment(
            owner: .entity(entity),
            contentKind: .file,
            title: "Spec",
            originalFilename: "spec.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 12,
            fileData: Data([0x01, 0x02])
        )
        try fixtures.save()

        let loader = GraphStatsLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let first = try await loader.loadDashboardSnapshot(
            graphIDs: [graph.id],
            activeGraphID: graph.id,
            days: 7
        )
        let second = try await loader.loadDashboardSnapshot(
            graphIDs: [graph.id],
            activeGraphID: graph.id,
            days: 7
        )

        #expect(first.total == second.total)
        #expect(first.perGraph == second.perGraph)
        #expect(first.dashboardGraphID == second.dashboardGraphID)
        #expect(first.activeMedia == second.activeMedia)
        #expect(first.activeStructure == second.activeStructure)
        #expect(first.activeTrends == second.activeTrends)
        #expect(await loader.dashboardCacheEntryCountForTesting() == 1)
        #expect(await loader.dashboardCacheHitsForTesting() == 1)
    }

    @Test
    func loadPerGraphCounts_keepsCachesSeparatedPerGraph() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graphA = fixtures.makeGraph(name: "A")
        let graphB = fixtures.makeGraph(name: "B")

        let entityA = fixtures.makeEntity(name: "EntityA", in: graphA, notes: "Note A")
        _ = fixtures.makeAttribute(name: "AttributeA", owner: entityA)
        _ = fixtures.makeAttachment(
            owner: .entity(entityA),
            contentKind: .file,
            title: "DocA",
            originalFilename: "a.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 10,
            fileData: Data([0x01])
        )

        let entityB = fixtures.makeEntity(name: "EntityB", in: graphB)
        _ = fixtures.makeAttachment(
            owner: .entity(entityB),
            contentKind: .video,
            title: "ClipB",
            originalFilename: "b.mov",
            contentTypeIdentifier: "public.movie",
            fileExtension: "mov",
            byteCount: 20,
            fileData: Data([0x02])
        )
        _ = fixtures.makeAttachment(
            owner: .entity(entityB),
            contentKind: .file,
            title: "DocB",
            originalFilename: "b.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 30,
            fileData: Data([0x03])
        )
        try fixtures.save()

        let loader = GraphStatsLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let first = try await loader.loadPerGraphCounts(graphIDs: [graphA.id])
        let second = try await loader.loadPerGraphCounts(graphIDs: [graphB.id])
        let combined = try await loader.loadPerGraphCounts(graphIDs: [graphA.id, graphB.id])

        #expect(first[graphA.id]?.entities == 1)
        #expect(second[graphB.id]?.attachments == 2)
        #expect(combined[graphA.id]?.attachments == 1)
        #expect(combined[graphB.id]?.attachments == 2)
        #expect(await loader.countsCacheEntryCountForTesting() == 2)
        #expect(await loader.countsCacheHitsForTesting() == 2)
    }

    @Test
    func loadDashboardSnapshot_invalidatesCachedSnapshotAfterRelevantChange() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        _ = fixtures.makeEntity(name: "Atlas", in: graph)
        try fixtures.save()

        let loader = GraphStatsLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let first = try await loader.loadDashboardSnapshot(
            graphIDs: [graph.id],
            activeGraphID: graph.id,
            days: 7
        )

        _ = fixtures.makeEntity(name: "Nova", in: graph, notes: "Fresh")
        try fixtures.save()

        let second = try await loader.loadDashboardSnapshot(
            graphIDs: [graph.id],
            activeGraphID: graph.id,
            days: 7
        )

        #expect(first.total.entities == 1)
        #expect(second.total.entities == 2)
        #expect(second.perGraph[graph.id]?.entities == 2)
        #expect(await loader.dashboardCacheHitsForTesting() == 0)
    }

    @Test
    func loadDashboardSnapshot_forceReloadBypassesCacheEvenWhenDataDidNotChange() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        _ = fixtures.makeEntity(name: "Atlas", in: graph)
        try fixtures.save()

        let loader = GraphStatsLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        _ = try await loader.loadDashboardSnapshot(
            graphIDs: [graph.id],
            activeGraphID: graph.id,
            days: 7
        )
        _ = try await loader.loadDashboardSnapshot(
            graphIDs: [graph.id],
            activeGraphID: graph.id,
            days: 7
        )
        _ = try await loader.loadDashboardSnapshot(
            graphIDs: [graph.id],
            activeGraphID: graph.id,
            days: 7,
            forceReload: true
        )

        #expect(await loader.dashboardCacheEntryCountForTesting() == 1)
        #expect(await loader.dashboardCacheHitsForTesting() == 1)
    }
}
