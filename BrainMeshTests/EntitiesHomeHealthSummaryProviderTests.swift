import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeHealthSummaryProviderTests {

    @Test
    func sameGraphAndRevisionReturnsCachedValue() async throws {
        let setup = try await makeConfiguredProvider()

        let first = try await setup.provider.summary(
            for: setup.graphID
        )
        let second = try await setup.provider.summary(
            for: setup.graphID
        )

        #expect(first == second)
        #expect(await setup.provider.computeCountForTesting() == 1)
        #expect(await setup.provider.cacheHitCountForTesting() == 1)
    }

    @Test
    func changedStatsRevisionStartsNewHealthComputation() async throws {
        let setup = try await makeConfiguredProvider()
        _ = try await setup.provider.summary(for: setup.graphID)

        let fixtures = BrainMeshFixtureBuilder(
            context: setup.testStore.context
        )
        _ = fixtures.makeEntity(
            name: "Revision Change",
            in: setup.graph
        )
        try fixtures.save()

        let refreshed = try await setup.provider.summary(
            for: setup.graphID
        )

        #expect(refreshed.summary.counts.entities == 2)
        #expect(await setup.provider.computeCountForTesting() == 2)
    }

    @Test
    func concurrentIdenticalRequestsShareOneFullComputation() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = UUID()
        let revision = healthTestRevision(entityCount: 1)
        let probe = HealthSummaryComputationProbe()
        let provider = EntitiesHomeHealthSummaryProvider(
            revisionLoader: { _, _ in revision },
            summaryLoader: { _, _ in
                try await probe.compute()
            }
        )
        await provider.configure(
            container: AnyModelContainer(testStore.container)
        )

        async let first = provider.summary(for: graphID)
        async let second = provider.summary(for: graphID)
        let results = try await (first, second)

        #expect(results.0 == results.1)
        #expect(await probe.count == 1)
        #expect(await provider.computeCountForTesting() == 1)
    }

    @Test
    func graphScopedInvalidationPreservesOtherGraphCache() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let revision = healthTestRevision(entityCount: 0)
        let provider = EntitiesHomeHealthSummaryProvider(
            revisionLoader: { _, _ in revision },
            summaryLoader: { _, _ in .empty }
        )
        await provider.configure(
            container: AnyModelContainer(testStore.container)
        )
        let graphA = UUID()
        let graphB = UUID()

        let cachedA = try await provider.summary(for: graphA)
        let cachedB = try await provider.summary(for: graphB)
        await provider.invalidate(for: graphA)

        #expect(cachedA.graphID == graphA)
        #expect(cachedB.graphID == graphB)
        #expect(
            await provider.hasCachedSummaryForTesting(graphID: graphA)
                == false
        )
        #expect(
            await provider.hasCachedSummaryForTesting(graphID: graphB)
        )
        #expect(await provider.computeCountForTesting() == 2)
    }

    @Test
    func recentHistoryLoadDoesNotIncreaseHealthComputeCount() async throws {
        let setup = try await makeConfiguredProvider()
        let recentLoader = EntitiesHomeRecentNodesLoader()
        await recentLoader.configure(
            container: AnyModelContainer(setup.testStore.container)
        )
        _ = try await setup.provider.summary(for: setup.graphID)

        _ = try await recentLoader.load(
            graphID: setup.graphID,
            recentItems: [
                RecentNodeItem(
                    graphID: setup.graphID,
                    nodeKindRaw: NodeKind.entity.rawValue,
                    nodeID: setup.entityID,
                    label: "Stored",
                    iconSymbolName: "circle",
                    openedAt: Date()
                )
            ],
            limit: 8
        )
        _ = try await setup.provider.summary(for: setup.graphID)

        #expect(await setup.provider.computeCountForTesting() == 1)
        #expect(await setup.provider.cacheHitCountForTesting() == 1)
    }

    @Test
    func fullQuickFilterIDSetsAreNotLimitedToEightFindings() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Large")
        var entityIDs = Set<UUID>()
        for index in 0..<12 {
            let entity = fixtures.makeEntity(
                name: "Entity \(index)",
                in: graph
            )
            entityIDs.insert(entity.id)
        }
        try fixtures.save()

        let provider = EntitiesHomeHealthSummaryProvider()
        await provider.configure(
            container: AnyModelContainer(testStore.container)
        )
        let snapshot = try await provider.summary(for: graph.id)

        #expect(Set(snapshot.summary.isolatedEntityIDs) == entityIDs)
        #expect(
            Set(snapshot.summary.entityIDsWithoutAttributes) == entityIDs
        )
        #expect(Set(snapshot.summary.entityIDsWithoutDetails) == entityIDs)
        #expect(
            EntitiesHomeQuickFilterSnapshot.snapshots(
                from: snapshot.summary
            )
            .first(where: { $0.filter == .isolatedEntities })?
                .matchingEntityIDs == entityIDs
        )
    }

    @Test
    func summaryCountsUseTheSameStatsRevisionTotals() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Counts")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(
            name: "Attribute",
            owner: entity
        )
        _ = fixtures.makeLink(
            source: .entity(entity),
            target: .attribute(attribute),
            graphID: graph.id
        )
        _ = fixtures.makeAttachment(
            owner: .entity(entity),
            byteCount: 512
        )
        try fixtures.save()

        let provider = EntitiesHomeHealthSummaryProvider()
        await provider.configure(
            container: AnyModelContainer(testStore.container)
        )
        let home = try await provider.summary(for: graph.id)
        let stats = try GraphStatsService(
            context: testStore.context
        ).counts(for: graph.id)

        #expect(home.summary.counts.entities == stats.entities)
        #expect(home.summary.counts.attributes == stats.attributes)
        #expect(home.summary.counts.links == stats.links)
        #expect(home.summary.counts.attachments == stats.attachments)
        #expect(
            home.summary.counts.attachmentBytes
                == stats.attachmentBytes
        )
    }

    private func makeConfiguredProvider() async throws -> HealthProviderSetup {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Health")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        try fixtures.save()

        let provider = EntitiesHomeHealthSummaryProvider()
        await provider.configure(
            container: AnyModelContainer(testStore.container)
        )
        return HealthProviderSetup(
            testStore: testStore,
            graph: graph,
            graphID: graph.id,
            entityID: entity.id,
            provider: provider
        )
    }
}

private struct HealthProviderSetup {
    let testStore: BrainMeshTestStore
    let graph: MetaGraph
    let graphID: UUID
    let entityID: UUID
    let provider: EntitiesHomeHealthSummaryProvider
}

private actor HealthSummaryComputationProbe {
    private(set) var count = 0

    func compute() async throws -> GraphHealthSummary {
        count += 1
        try await Task.sleep(nanoseconds: 50_000_000)
        return .empty
    }
}

private func healthTestRevision(
    entityCount: Int
) -> GraphStatsScopeRevision {
    GraphStatsScopeRevision(
        counts: GraphCounts(
            entities: entityCount,
            attributes: 0,
            links: 0,
            notes: 0,
            images: 0,
            attachments: 0,
            attachmentBytes: 0
        ),
        detailFieldCount: 0,
        newestEntityCreatedAt: nil,
        newestLinkCreatedAt: nil,
        newestAttachmentCreatedAt: nil
    )
}
