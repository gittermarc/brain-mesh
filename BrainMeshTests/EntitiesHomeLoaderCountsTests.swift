import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeLoaderCountsTests {

    @Test
    func computeAttributeCounts_scopesToGraphAndCountsByOwner() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)

        let graphA = fixtures.makeGraph(name: "Graph A")
        let graphB = fixtures.makeGraph(name: "Graph B")

        let alpha = fixtures.makeEntity(name: "Alpha", in: graphA)
        let beta = fixtures.makeEntity(name: "Beta", in: graphA)
        let gamma = fixtures.makeEntity(name: "Gamma", in: graphB)

        let _ = fixtures.makeAttribute(name: "One", owner: alpha)
        let _ = fixtures.makeAttribute(name: "Two", owner: alpha)
        let _ = fixtures.makeAttribute(name: "Three", owner: beta)
        let _ = fixtures.makeAttribute(name: "Four", owner: gamma)
        let _ = fixtures.makeAttribute(name: "Five", owner: gamma)
        try fixtures.save()

        let graphACounts = try EntitiesHomeLoader.computeAttributeCounts(
            context: testStore.context,
            graphID: graphA.id
        )
        let allCounts = try EntitiesHomeLoader.computeAttributeCounts(
            context: testStore.context,
            graphID: nil
        )

        #expect(graphACounts[alpha.id] == 2)
        #expect(graphACounts[beta.id] == 1)
        #expect(graphACounts[gamma.id] == nil)

        #expect(allCounts[alpha.id] == 2)
        #expect(allCounts[beta.id] == 1)
        #expect(allCounts[gamma.id] == 2)
    }

    @Test
    func computeLinkCounts_countsOnlyEntityEndpointsWithinGraph() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)

        let graphA = fixtures.makeGraph(name: "Graph A")
        let graphB = fixtures.makeGraph(name: "Graph B")

        let alpha = fixtures.makeEntity(name: "Alpha", in: graphA)
        let beta = fixtures.makeEntity(name: "Beta", in: graphA)
        let betaAttribute = fixtures.makeAttribute(name: "Leaf", owner: beta)

        let gamma = fixtures.makeEntity(name: "Gamma", in: graphB)
        let gammaAttribute = fixtures.makeAttribute(name: "Other", owner: gamma)

        let _ = fixtures.makeLink(
            source: .entity(alpha),
            target: .entity(beta)
        )
        let _ = fixtures.makeLink(
            source: .entity(alpha),
            target: .attribute(betaAttribute)
        )
        let _ = fixtures.makeLink(
            source: .attribute(betaAttribute),
            target: .entity(beta)
        )
        let _ = fixtures.makeLink(
            source: .entity(gamma),
            target: .attribute(gammaAttribute)
        )
        try fixtures.save()

        let graphACounts = try EntitiesHomeLoader.computeLinkCounts(
            context: testStore.context,
            graphID: graphA.id
        )
        let allCounts = try EntitiesHomeLoader.computeLinkCounts(
            context: testStore.context,
            graphID: nil
        )

        #expect(graphACounts[alpha.id] == 2)
        #expect(graphACounts[beta.id] == 2)
        #expect(graphACounts[gamma.id] == nil)

        #expect(allCounts[alpha.id] == 2)
        #expect(allCounts[beta.id] == 2)
        #expect(allCounts[gamma.id] == 1)
    }

    @Test
    func loadSnapshot_reusesCountsCacheForRepeatedRequestsInSameGraph() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)

        let graph = fixtures.makeGraph(name: "Primary")
        let alpha = fixtures.makeEntity(name: "Alpha", in: graph)
        let beta = fixtures.makeEntity(name: "Beta", in: graph)
        let alphaAttribute = fixtures.makeAttribute(name: "Launch", owner: alpha)
        let _ = fixtures.makeAttribute(name: "Status", owner: alpha)
        let _ = fixtures.makeLink(source: .entity(alpha), target: .entity(beta))
        let _ = fixtures.makeLink(source: .entity(alpha), target: .attribute(alphaAttribute))
        try fixtures.save()

        let loader = EntitiesHomeLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let first = try await loader.loadSnapshot(
            activeGraphID: graph.id,
            foldedSearch: "",
            includeAttributeCounts: true,
            includeLinkCounts: true,
            includeNotesPreview: false
        )
        let second = try await loader.loadSnapshot(
            activeGraphID: graph.id,
            foldedSearch: "",
            includeAttributeCounts: true,
            includeLinkCounts: true,
            includeNotesPreview: false
        )

        #expect(first.rows == second.rows)
        #expect(await loader.countsCache.count == 1)
        #expect(await loader.linkCountsCache.count == 1)

        let attrEntry = await loader.cachedCountEntry(for: .attributes, graphID: graph.id)
        let linkEntry = await loader.cachedCountEntry(for: .links, graphID: graph.id)
        #expect(attrEntry?.countsByEntityID[alpha.id] == 2)
        #expect(linkEntry?.countsByEntityID[alpha.id] == 2)
        #expect(linkEntry?.countsByEntityID[beta.id] == 1)
    }

    @Test
    func loadSnapshot_separatesCachesByGraphAndInvalidatesOnlyRequestedGraph() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)

        let graphA = fixtures.makeGraph(name: "Graph A")
        let graphB = fixtures.makeGraph(name: "Graph B")

        let alpha = fixtures.makeEntity(name: "Alpha", in: graphA)
        let beta = fixtures.makeEntity(name: "Beta", in: graphB)
        let _ = fixtures.makeAttribute(name: "A-1", owner: alpha)
        let _ = fixtures.makeAttribute(name: "B-1", owner: beta)
        try fixtures.save()

        let loader = EntitiesHomeLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        _ = try await loader.loadSnapshot(
            activeGraphID: graphA.id,
            foldedSearch: "",
            includeAttributeCounts: true,
            includeLinkCounts: true,
            includeNotesPreview: false
        )
        _ = try await loader.loadSnapshot(
            activeGraphID: graphB.id,
            foldedSearch: "",
            includeAttributeCounts: true,
            includeLinkCounts: true,
            includeNotesPreview: false
        )

        #expect(await loader.countsCache.count == 2)
        #expect(await loader.linkCountsCache.count == 2)

        await loader.invalidateCache(for: graphA.id)

        #expect(await loader.cachedCountEntry(for: .attributes, graphID: graphA.id) == nil)
        #expect(await loader.cachedCountEntry(for: .links, graphID: graphA.id) == nil)
        #expect(await loader.cachedCountEntry(for: .attributes, graphID: graphB.id)?.countsByEntityID[beta.id] == 1)
    }

    @Test
    func loadSnapshot_withCountsEnabled_keepsSearchRowsUnchanged() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)

        let graph = fixtures.makeGraph(name: "Primary")
        let atlas = fixtures.makeEntity(name: "Project Atlas", in: graph)
        let _ = fixtures.makeAttribute(name: "Launch Date", owner: atlas)
        let _ = fixtures.makeEntity(name: "Project Beacon", in: graph)
        try fixtures.save()

        let loader = EntitiesHomeLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            activeGraphID: graph.id,
            foldedSearch: BMSearch.fold("launch"),
            includeAttributeCounts: true,
            includeLinkCounts: true,
            includeNotesPreview: false
        )

        #expect(snapshot.rows.map(\.id) == [atlas.id])
        #expect(snapshot.rows.first?.isNotesOnlyHit == false)
        #expect(snapshot.rows.first?.attributeCount == 1)
        #expect(snapshot.rows.first?.linkCount == 0)
    }
}
