import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct GraphMutationCacheInvalidationTests {

    @Test
    func graphScopedMutationPreservesOtherGraphCountCaches() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let container = AnyModelContainer(store.container)
        let bus = GraphMutationEventBus()
        let home = EntitiesHomeLoader()
        let stats = GraphStatsLoader()
        let coordinator = GraphMutationCacheInvalidationCoordinator(
            subscriber: bus,
            entitiesHomeLoader: home,
            graphStatsLoader: stats
        )
        let graphA = cacheTestUUID(1)
        let graphB = cacheTestUUID(2)

        await home.configure(container: container)
        await stats.configure(container: container)
        await seedHomeCaches(home, graphIDs: [graphA, graphB])
        await stats.seedCachesForTesting(graphID: graphA)
        await stats.seedCachesForTesting(graphID: graphB)
        await coordinator.configure(container: container)

        let batch = try GraphMutationBatchFactory.attributeCreated(
            graphID: graphA,
            attributeID: cacheTestUUID(3),
            ownerEntityID: cacheTestUUID(4)
        )
        _ = await bus.publishCommitted(batch)
        #expect(await waitForProcessedBatch(coordinator, expectedCount: 1))

        #expect(await home.hasCachedCountsForTesting(kind: .attributes, graphID: graphA) == false)
        #expect(await home.hasCachedCountsForTesting(kind: .links, graphID: graphA) == false)
        #expect(await home.hasCachedCountsForTesting(kind: .attributes, graphID: graphB))
        #expect(await home.hasCachedCountsForTesting(kind: .links, graphID: graphB))
        #expect(await stats.hasCountsCacheForTesting(graphID: graphA) == false)
        #expect(await stats.hasCountsCacheForTesting(graphID: graphB))
        #expect(await stats.hasTotalCountsCacheForTesting() == false)
        #expect(await stats.dashboardCacheEntryCountForTesting() == 0)

        await coordinator.stop()
        await bus.finish()
    }

    @Test
    func domainKindsProduceOnlyTheirRequiredCacheEffects() throws {
        let graphID = cacheTestUUID(10)
        let node = NodeRefKey(kind: .entity, id: cacheTestUUID(11))
        let owner = NodeRefKey(kind: .attribute, id: cacheTestUUID(12))
        let link = GraphMutationLinkReference(
            id: cacheTestUUID(13),
            source: node,
            target: owner
        )
        let attachment = GraphMutationAttachmentReference(
            id: cacheTestUUID(14),
            owner: node
        )
        let value = GraphMutationDetailValueReference(
            id: cacheTestUUID(15),
            ownerAttributeID: owner.id,
            fieldID: cacheTestUUID(16)
        )

        let cases: [(String, GraphMutationBatch, Bool)] = [
            (
                "entity",
                try GraphMutationBatchFactory.nodeUpdated(graphID: graphID, node: node),
                false
            ),
            (
                "attribute",
                try GraphMutationBatchFactory.attributeCreated(
                    graphID: graphID,
                    attributeID: owner.id,
                    ownerEntityID: node.id
                ),
                true
            ),
            (
                "link",
                try GraphMutationBatchFactory.linksCreated(graphID: graphID, links: [link]),
                true
            ),
            (
                "detail",
                try GraphMutationBatchFactory.detailValueChanged(graphID: graphID, value: value),
                false
            ),
            (
                "attachment",
                try GraphMutationBatchFactory.attachmentsCreated(
                    graphID: graphID,
                    attachments: [attachment]
                ),
                false
            )
        ]

        for (name, batch, expectedHomeInvalidation) in cases {
            let plan = try #require(GraphMutationCacheInvalidationPlan.make(for: batch))
            #expect(plan.graphID == graphID, Comment(rawValue: name))
            #expect(
                plan.invalidateEntitiesHomeCounts == expectedHomeInvalidation,
                Comment(rawValue: name)
            )
            #expect(plan.invalidateGraphStatsCounts, Comment(rawValue: name))
            #expect(plan.invalidateGraphStatsTotalAggregate, Comment(rawValue: name))
            #expect(plan.invalidateGraphStatsDashboards, Comment(rawValue: name))
        }
    }

    @Test
    func fullRebuildAndGraphDeletionFullyInvalidateOnlyTheirGraphCounts() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let container = AnyModelContainer(store.container)
        let bus = GraphMutationEventBus()
        let home = EntitiesHomeLoader()
        let stats = GraphStatsLoader()
        let coordinator = GraphMutationCacheInvalidationCoordinator(
            subscriber: bus,
            entitiesHomeLoader: home,
            graphStatsLoader: stats
        )
        let graphA = cacheTestUUID(20)
        let graphB = cacheTestUUID(21)

        await home.configure(container: container)
        await stats.configure(container: container)
        await seedHomeCaches(home, graphIDs: [graphA, graphB])
        await stats.seedCachesForTesting(graphID: graphA)
        await stats.seedCachesForTesting(graphID: graphB)
        await coordinator.configure(container: container)

        _ = await bus.publishCommitted(
            try GraphMutationBatchFactory.graphIntegrityRepair(graphID: graphA)
        )
        #expect(await waitForProcessedBatch(coordinator, expectedCount: 1))
        #expect(await home.hasCachedCountsForTesting(kind: .attributes, graphID: graphA) == false)
        #expect(await home.hasCachedCountsForTesting(kind: .attributes, graphID: graphB))
        #expect(await stats.hasCountsCacheForTesting(graphID: graphA) == false)
        #expect(await stats.hasCountsCacheForTesting(graphID: graphB))

        await seedHomeCaches(home, graphIDs: [graphA])
        await stats.seedCachesForTesting(graphID: graphA)
        _ = await bus.publishCommitted(
            try GraphMutationBatchFactory.graphDeleted(graphID: graphA)
        )
        #expect(await waitForProcessedBatch(coordinator, expectedCount: 2))
        #expect(await home.hasCachedCountsForTesting(kind: .links, graphID: graphA) == false)
        #expect(await home.hasCachedCountsForTesting(kind: .links, graphID: graphB))
        #expect(await stats.hasCountsCacheForTesting(graphID: graphA) == false)
        #expect(await stats.hasCountsCacheForTesting(graphID: graphB))
        #expect(await stats.hasTotalCountsCacheForTesting() == false)

        await coordinator.stop()
        await bus.finish()
    }

    @Test
    func configurationIsIdempotentAndReplacementStopsTheOldSubscription() async throws {
        let firstStore = try BrainMeshTestContainer.makeInMemoryStore()
        let secondStore = try BrainMeshTestContainer.makeInMemoryStore()
        let firstContainer = AnyModelContainer(firstStore.container)
        let secondContainer = AnyModelContainer(secondStore.container)
        let bus = GraphMutationEventBus()
        let coordinator = GraphMutationCacheInvalidationCoordinator(
            subscriber: bus,
            entitiesHomeLoader: EntitiesHomeLoader(),
            graphStatsLoader: GraphStatsLoader()
        )

        await coordinator.configure(container: firstContainer)
        await coordinator.configure(container: firstContainer)

        #expect(await coordinator.configurationStartCountForTesting() == 1)
        #expect(await coordinator.activeContainerIDForTesting() == firstContainer.identity)
        #expect(await bus.subscriberCountForTesting == 1)

        await coordinator.configure(container: secondContainer)

        #expect(await coordinator.configurationStartCountForTesting() == 2)
        #expect(await coordinator.activeContainerIDForTesting() == secondContainer.identity)
        #expect(await coordinator.hasActiveSubscriptionForTesting())
        #expect(await waitForSubscriberCount(bus, expectedCount: 1))

        await coordinator.stop()
        #expect(await waitForSubscriberCount(bus, expectedCount: 0))
        await bus.finish()
    }
}

private func seedHomeCaches(
    _ loader: EntitiesHomeLoader,
    graphIDs: [UUID]
) async {
    for graphID in graphIDs {
        await loader.storeCounts(
            [cacheTestUUID(900): 1],
            for: .attributes,
            graphID: graphID,
            now: Date()
        )
        await loader.storeCounts(
            [cacheTestUUID(901): 1],
            for: .links,
            graphID: graphID,
            now: Date()
        )
    }
}

private func waitForProcessedBatch(
    _ coordinator: GraphMutationCacheInvalidationCoordinator,
    expectedCount: Int
) async -> Bool {
    for _ in 0..<200 {
        if await coordinator.processedBatchCountForTesting() >= expectedCount {
            return true
        }
        await Task.yield()
    }
    return false
}

private func waitForSubscriberCount(
    _ bus: GraphMutationEventBus,
    expectedCount: Int
) async -> Bool {
    for _ in 0..<200 {
        if await bus.subscriberCountForTesting == expectedCount {
            return true
        }
        await Task.yield()
    }
    return false
}

private func cacheTestUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
