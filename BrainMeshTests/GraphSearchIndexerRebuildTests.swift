import Foundation
import Testing
@testable import BrainMesh

struct GraphSearchIndexerRebuildTests {
    @Test
    func fullRebuildCreatesAllDocumentsAndSecondBuildIsSemanticallyIdentical() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let firstDocuments = try await store.documents(in: fixture.graphID)
            let firstStatus = await indexer.status(for: fixture.scope)
            let firstLifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            try await indexer.rebuild(scope: fixture.scope)
            let secondDocuments = try await store.documents(in: fixture.graphID)
            let secondStatus = await indexer.status(for: fixture.scope)
            let secondLifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            #expect(firstDocuments.count == 22)
            #expect(firstDocuments == secondDocuments)
            #expect(firstStatus == .ready(documentCount: firstDocuments.count))
            #expect(secondStatus == .ready(documentCount: secondDocuments.count))
            #expect(firstLifecycle?.lifecycleState == .ready)
            #expect(secondLifecycle?.lifecycleState == .ready)
            #expect(firstLifecycle?.activeGeneration != secondLifecycle?.activeGeneration)
            #expect(secondLifecycle?.stagingGeneration == nil)
            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 2
            )
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 2
            )
        }
    }

    @Test
    func twoGraphsRemainStrictlySeparated() async throws {
        let firstFixture = GraphSearchIndexerFixture()
        var mutableSecondFixture = GraphSearchIndexerFixture()
        mutableSecondFixture.renamePrimaryEntity(to: "Second Graph Person")
        let secondFixture = mutableSecondFixture

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [firstFixture.snapshot, secondFixture.snapshot]
        ) { indexer, _, store in
            async let firstBuild: Void = indexer.ensureIndexed(
                scope: firstFixture.scope
            )
            async let secondBuild: Void = indexer.ensureIndexed(
                scope: secondFixture.scope
            )
            _ = try await (firstBuild, secondBuild)

            let firstDocuments = try await store.documents(
                in: firstFixture.graphID
            )
            let secondDocuments = try await store.documents(
                in: secondFixture.graphID
            )

            #expect(firstDocuments.allSatisfy { $0.graphID == firstFixture.graphID })
            #expect(secondDocuments.allSatisfy { $0.graphID == secondFixture.graphID })
            #expect(Set(firstDocuments.map(\.documentID)).isDisjoint(
                with: Set(secondDocuments.map(\.documentID))
            ))
            #expect(firstDocuments.contains { $0.title == "Person" })
            #expect(secondDocuments.contains { $0.title == "Second Graph Person" })
        }
    }

    @Test
    func parallelEnsureIndexedCallsAreCoalescedPerGraph() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            await source.setSnapshotDelay(nanoseconds: 200_000_000)

            let first = Task {
                try await indexer.ensureIndexed(scope: fixture.scope)
            }
            let second = Task {
                try await indexer.ensureIndexed(scope: fixture.scope)
            }

            try await first.value
            try await second.value

            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            )
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
            #expect(try await store.documentCount(in: fixture.graphID) == 22)
        }
    }

    @Test
    func cancellationLeavesThePreviousCompleteIndexAtomicallyIntact() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let previousDocuments = try await store.documents(in: fixture.graphID)
            let previousLifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            fixture.updatePrimaryEntityNotes("Replacement notes")
            await source.setSnapshot(fixture.snapshot)
            await source.setSnapshotDelay(nanoseconds: 5_000_000_000)

            let rebuildScope = fixture.scope
            let rebuildGraphID = fixture.graphID
            let rebuild = Task {
                try await indexer.rebuild(scope: rebuildScope)
            }
            try await waitForGraphSearchIndexerCondition {
                await source.readCount(for: .snapshot(rebuildGraphID)) >= 2
            }

            let lifecycleDuringRebuild = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            let replacementHitsDuringRebuild = try await store.search(
                in: fixture.graphID,
                text: "Replacement notes",
                limit: 20
            )

            await indexer.cancelIndexing(scope: fixture.scope)
            await #expect(throws: CancellationError.self) {
                try await rebuild.value
            }

            let documentsAfterCancellation = try await store.documents(
                in: fixture.graphID
            )
            let status = await indexer.status(for: fixture.scope)
            let lifecycleAfterCancellation = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            #expect(lifecycleDuringRebuild?.lifecycleState == .rebuilding)
            #expect(lifecycleDuringRebuild?.stagingGeneration != nil)
            #expect(
                lifecycleDuringRebuild?.activeGeneration
                    == previousLifecycle?.activeGeneration
            )
            #expect(replacementHitsDuringRebuild.isEmpty)
            #expect(documentsAfterCancellation == previousDocuments)
            #expect(status == .ready(documentCount: previousDocuments.count))
            #expect(
                lifecycleAfterCancellation?.activeGeneration
                    == previousLifecycle?.activeGeneration
            )
            #expect(lifecycleAfterCancellation?.stagingGeneration == nil)
        }
    }

    @Test
    func rebuildFailureDoesNotDestroyAPreviousValidIndex() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let previousDocuments = try await store.documents(in: fixture.graphID)
            let previousLifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            fixture.renameAttribute(to: "Changed After Failure")
            await source.setSnapshot(fixture.snapshot)
            await source.setFailure(true, graphID: fixture.graphID)

            await #expect(throws: GraphSearchIndexerTestFailure.self) {
                try await indexer.rebuild(scope: fixture.scope)
            }

            #expect(
                try await store.documents(in: fixture.graphID)
                    == previousDocuments
            )
            let lifecycleAfterFailure = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            #expect(
                lifecycleAfterFailure?.activeGeneration
                    == previousLifecycle?.activeGeneration
            )
            #expect(lifecycleAfterFailure?.stagingGeneration == nil)
            #expect(await indexer.status(for: fixture.scope).state == .failed)
        }
    }

    @Test
    func cutoverFailureRollsBackBeforePublishingStagingGeneration() async throws {
        var fixture = GraphSearchIndexerFixture()
        let gate = GraphSearchCutoverFailureGate()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot],
            storeCancellationCheck: {
                try gate.check()
            }
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let previousDocuments = try await store.documents(in: fixture.graphID)
            let previousLifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            fixture.updatePrimaryEntityNotes("Must not cut over")
            let sourceRevision = UUID()
            await source.setSnapshot(
                fixture.snapshot,
                sourceRevision: sourceRevision
            )
            let build = try GraphSearchDocumentBuilder().buildSnapshot(
                for: fixture.snapshot
            )
            let staging = try await store.beginStagingGeneration(
                graphID: fixture.graphID,
                sourceRevision: sourceRevision
            )
            try await store.append(build.sourceBuilds, to: staging)
            try await store.completeStagingGeneration(
                staging,
                sourceManifest: build.sourceManifest
            )
            gate.fail(afterSuccessfulChecks: 3)

            await #expect(throws: GraphSearchIndexerTestFailure.self) {
                _ = try await store.cutOver(
                    staging,
                    sourceManifest: build.sourceManifest
                )
            }
            gate.disableFailure()

            let lifecycleAfterFailure = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            #expect(try await store.documents(in: fixture.graphID) == previousDocuments)
            #expect(
                lifecycleAfterFailure?.activeGeneration
                    == previousLifecycle?.activeGeneration
            )
            #expect(lifecycleAfterFailure?.stagingGeneration == staging.generationID)

            try await store.abortStagingGeneration(staging)
            let lifecycleAfterAbort = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            #expect(lifecycleAfterAbort?.stagingGeneration == nil)
            #expect(
                lifecycleAfterAbort?.activeGeneration
                    == previousLifecycle?.activeGeneration
            )
        }
    }

    @Test
    func incompleteStagingGenerationCannotCutOver() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let activeBefore = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            let manifest = try #require(
                try await store.sourceManifest(in: fixture.graphID)
            )
            let sourceRevision = try #require(
                try await source.searchSourceRevision(in: fixture.scope)
            )
            let staging = try await store.beginStagingGeneration(
                graphID: fixture.graphID,
                sourceRevision: sourceRevision
            )

            await #expect(throws: GraphSearchIndexStoreError.self) {
                _ = try await store.cutOver(
                    staging,
                    sourceManifest: manifest
                )
            }
            let lifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            #expect(lifecycle?.activeGeneration == activeBefore?.activeGeneration)
            #expect(lifecycle?.stagingGeneration == staging.generationID)
            try await store.abortStagingGeneration(staging)
        }
    }

    @Test
    func openingStoreCleansOrphanStageAndRestoresReadyActiveGeneration() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let sourceRevision = try #require(
                try await source.searchSourceRevision(in: fixture.scope)
            )
            let activeBefore = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            _ = try await store.beginStagingGeneration(
                graphID: fixture.graphID,
                sourceRevision: sourceRevision
            )
            let staged = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            try await store.close()
            _ = try await store.open()
            let recovered = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            #expect(staged?.lifecycleState == .rebuilding)
            #expect(staged?.stagingGeneration != nil)
            #expect(recovered?.lifecycleState == .ready)
            #expect(recovered?.stagingGeneration == nil)
            #expect(recovered?.activeGeneration == activeBefore?.activeGeneration)
        }
    }

    @Test
    func invalidationArrivingDuringRebuildSurvivesStageAbort() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            let sourceRevision = try #require(
                try await source.searchSourceRevision(in: fixture.scope)
            )
            let activeBefore = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            let staging = try await store.beginStagingGeneration(
                graphID: fixture.graphID,
                sourceRevision: sourceRevision
            )
            try await store.invalidateLifecycle(
                graphID: fixture.graphID,
                reason: .importOrReplace
            )

            try await store.abortStagingGeneration(staging)
            let lifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            #expect(lifecycle?.lifecycleState == .invalidated)
            #expect(lifecycle?.invalidationReason == .importOrReplace)
            #expect(lifecycle?.stagingGeneration == nil)
            #expect(lifecycle?.activeGeneration == activeBefore?.activeGeneration)
        }
    }
}

private nonisolated final class GraphSearchCutoverFailureGate: @unchecked Sendable {
    private let lock = NSLock()
    private var successfulChecksBeforeFailure: Int?

    func fail(afterSuccessfulChecks count: Int) {
        lock.withLock {
            successfulChecksBeforeFailure = max(0, count)
        }
    }

    func disableFailure() {
        lock.withLock {
            successfulChecksBeforeFailure = nil
        }
    }

    func check() throws {
        try lock.withLock {
            guard let remaining = successfulChecksBeforeFailure else {
                return
            }
            guard remaining > 0 else {
                throw GraphSearchIndexerTestFailure.injected
            }
            successfulChecksBeforeFailure = remaining - 1
        }
    }
}
