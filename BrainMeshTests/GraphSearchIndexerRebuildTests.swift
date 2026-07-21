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

            try await indexer.rebuild(scope: fixture.scope)
            let secondDocuments = try await store.documents(in: fixture.graphID)
            let secondStatus = await indexer.status(for: fixture.scope)

            #expect(firstDocuments.count == 22)
            #expect(firstDocuments == secondDocuments)
            #expect(firstStatus == .ready(documentCount: firstDocuments.count))
            #expect(secondStatus == .ready(documentCount: secondDocuments.count))
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

            await indexer.cancelIndexing(scope: fixture.scope)
            await #expect(throws: CancellationError.self) {
                try await rebuild.value
            }

            let documentsAfterCancellation = try await store.documents(
                in: fixture.graphID
            )
            let status = await indexer.status(for: fixture.scope)

            #expect(documentsAfterCancellation == previousDocuments)
            #expect(status == .ready(documentCount: previousDocuments.count))
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
            #expect(await indexer.status(for: fixture.scope).state == .failed)
        }
    }
}
