//
//  GraphMutationCacheInvalidationCoordinator.swift
//  BrainMesh
//
//  One process-wide subscription that applies graph-scoped cache invalidation.
//

import Foundation

actor GraphMutationCacheInvalidationCoordinator {
    static let shared = GraphMutationCacheInvalidationCoordinator()

    private let subscriber: any GraphMutationSubscribing
    private let entitiesHomeLoader: EntitiesHomeLoader
    private let entitiesHomeHealthProvider: EntitiesHomeHealthSummaryProvider
    private let graphStatsLoader: GraphStatsLoader

    private var subscriptionTask: Task<Void, Never>?
    private var configuredContainerID: ObjectIdentifier?
    private var generation: UInt = 0
    private var configurationStartCount: Int = 0
    private var processedBatchCount: Int = 0

    init(
        subscriber: any GraphMutationSubscribing = GraphMutationEventBus.shared,
        entitiesHomeLoader: EntitiesHomeLoader = .shared,
        entitiesHomeHealthProvider: EntitiesHomeHealthSummaryProvider = .shared,
        graphStatsLoader: GraphStatsLoader = .shared
    ) {
        self.subscriber = subscriber
        self.entitiesHomeLoader = entitiesHomeLoader
        self.entitiesHomeHealthProvider = entitiesHomeHealthProvider
        self.graphStatsLoader = graphStatsLoader
    }

    func configure(container: AnyModelContainer) async {
        if configuredContainerID == container.identity,
           subscriptionTask != nil {
            return
        }

        let predecessor = subscriptionTask
        subscriptionTask = nil
        configuredContainerID = nil
        predecessor?.cancel()
        if let predecessor {
            await predecessor.value
        }

        generation &+= 1
        let currentGeneration = generation
        configuredContainerID = container.identity
        configurationStartCount += 1

        let stream = await subscriber.mutationBatches(bufferingPolicy: .unbounded)
        let entitiesHomeLoader = entitiesHomeLoader
        let entitiesHomeHealthProvider = entitiesHomeHealthProvider
        let graphStatsLoader = graphStatsLoader

        subscriptionTask = Task.detached { [weak self] in
            for await delivery in stream {
                guard Task.isCancelled == false else {
                    break
                }

                guard let plan = GraphMutationCacheInvalidationPlan.make(
                    for: delivery.batch
                ) else {
                    await self?.recordProcessedBatch(generation: currentGeneration)
                    continue
                }

                if plan.invalidateEntitiesHomeCounts {
                    await entitiesHomeLoader.invalidateCaches(
                        forGraphID: plan.graphID
                    )
                }
                if plan.invalidateEntitiesHomeHealth {
                    await entitiesHomeHealthProvider.invalidate(
                        for: plan.graphID
                    )
                }
                await graphStatsLoader.invalidateCaches(using: plan)
                await self?.recordProcessedBatch(generation: currentGeneration)
            }

            await self?.subscriptionDidFinish(generation: currentGeneration)
        }
    }

    func stop() async {
        generation &+= 1
        configuredContainerID = nil
        let task = subscriptionTask
        subscriptionTask = nil
        task?.cancel()
        if let task {
            await task.value
        }
    }

    func activeContainerIDForTesting() -> ObjectIdentifier? {
        configuredContainerID
    }

    func configurationStartCountForTesting() -> Int {
        configurationStartCount
    }

    func processedBatchCountForTesting() -> Int {
        processedBatchCount
    }

    func hasActiveSubscriptionForTesting() -> Bool {
        subscriptionTask != nil
    }

    func resetForTesting() async {
        await stop()
        configurationStartCount = 0
        processedBatchCount = 0
    }

    private func recordProcessedBatch(generation: UInt) {
        guard generation == self.generation else {
            return
        }
        processedBatchCount += 1
    }

    private func subscriptionDidFinish(generation: UInt) {
        guard generation == self.generation else {
            return
        }
        subscriptionTask = nil
        configuredContainerID = nil
    }
}
