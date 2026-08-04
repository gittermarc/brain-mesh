import Foundation
import Testing
@testable import BrainMesh

struct GraphSearchIndexReconcilerTests {
    @Test
    func readyIndexUsesOnlyRevisionAndMetadataWithoutSourceWork() async throws {
        let fixture = GraphSearchIndexerFixture()
        let workRecorder = GraphSearchIndexWorkRecorder()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot],
            workInstrumentation: GraphSearchIndexWorkInstrumentation {
                workRecorder.record($0)
            }
        ) { reconciler, _, source, _, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            await source.clearReads()
            workRecorder.reset()

            for _ in 0..<3 {
                let result = await reconciler.ensureReady(
                    scope: fixture.scope,
                    reason: .chatSession
                )
                #expect(result.outcome == .ready)
                #expect(result.metrics?.checkedSourceCount == 0)
            }

            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 0)
            #expect(await source.readCount(for: .sourcePage(fixture.graphID)) == 0)
            #expect(
                await source.readCount(for: .sourceRevision(fixture.graphID)) == 3
            )
            #expect(workRecorder.count(.sourceDocumentsBuilt) == 0)
            #expect(workRecorder.count(.sourceDocumentsSorted) == 0)
            #expect(workRecorder.count(.sourceHashed) == 0)
            #expect(
                await reconciler.completedOperationCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
        }
    }

    @Test
    func firstEnsureReadyBuildsACompatibleSourceManifest() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, store, _ in
            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let manifest = try await store.sourceManifest(in: fixture.graphID)

            #expect(result.outcome == .rebuilt)
            #expect(result.isIndexUsable)
            #expect(result.documentCount == 22)
            #expect(result.metrics?.fullRebuild == true)
            #expect(manifest?.isCompatible == true)
            #expect(manifest?.sourceCount == fixture.snapshot.searchSourceCountForTesting)
            #expect(manifest?.documentCount == 22)
            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            )
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
        }
    }

    @Test
    func externalChangeWithoutMutationEventIsReconciledIncrementally() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let rebuildCountBefore = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )

            fixture.updatePrimaryEntityNotes("Externally changed notes")
            await source.setSnapshot(fixture.snapshot)
            await source.clearReads()

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let documents = try await store.documents(
                for: GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .entity,
                    sourceID: fixture.primaryEntityID
                )
            )

            #expect(result.outcome == .reconciled)
            #expect(result.metrics?.addedSourceCount == 0)
            #expect(result.metrics?.changedSourceCount == 1)
            #expect(result.metrics?.deletedSourceCount == 0)
            #expect(result.metrics?.fullRebuild == false)
            #expect(documents.contains {
                $0.documentKind == .entityNotes
                    && $0.normalizedSearchText.contains(
                        BMSearch.fold("Externally changed notes")
                    )
            })
            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            )
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCountBefore
            )
        }
    }

    @Test
    func mutationDrivenUpdateAdvancesPersistentReadinessToken() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let oldRevision = try #require(
                try await source.searchSourceRevision(in: fixture.scope)
            )

            fixture.updatePrimaryEntityNotes("Mutation driven token")
            let batch = try GraphMutationBatchFactory.nodeUpdated(
                graphID: fixture.graphID,
                node: NodeRefKey(
                    kind: .entity,
                    id: fixture.primaryEntityID
                )
            )
            await source.setSnapshot(
                fixture.snapshot,
                sourceRevision: batch.id
            )
            await indexer.processCommittedBatch(batch)

            let newRevision = try #require(
                try await source.searchSourceRevision(in: fixture.scope)
            )
            let token = try #require(
                try await store.readinessToken(
                    graphID: fixture.graphID,
                    sourceRevision: newRevision
                )
            )
            await source.clearReads()
            let readiness = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )

            #expect(newRevision != oldRevision)
            #expect(token.isReady)
            #expect(token.sourceRevision == newRevision)
            #expect(token.indexedSourceRevision == newRevision)
            #expect(readiness.outcome == .ready)
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 0)
            #expect(await source.readCount(for: .sourcePage(fixture.graphID)) == 0)
        }
    }

    @Test
    func pendingSuccessorMutationCannotBeCoveredByEarlierBatchRevision() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let firstBatch = try GraphMutationBatchFactory.nodeUpdated(
                graphID: fixture.graphID,
                node: NodeRefKey(kind: .entity, id: fixture.primaryEntityID)
            )
            let successorBatch = try GraphMutationBatchFactory.nodeUpdated(
                graphID: fixture.graphID,
                node: NodeRefKey(kind: .entity, id: fixture.primaryEntityID)
            )
            fixture.updatePrimaryEntityNotes("Successor mutation")
            await source.setSnapshot(
                fixture.snapshot,
                sourceRevision: successorBatch.id
            )

            await indexer.processCommittedBatch(firstBatch)
            let prematureToken = try await store.readinessToken(
                graphID: fixture.graphID,
                sourceRevision: successorBatch.id
            )
            let intermediateReadiness = await reconciler.readiness(
                for: fixture.scope
            )
            await indexer.processCommittedBatch(successorBatch)
            let finalToken = try await store.readinessToken(
                graphID: fixture.graphID,
                sourceRevision: successorBatch.id
            )

            #expect(prematureToken?.isReady == false)
            #expect(prematureToken?.indexedSourceRevision == firstBatch.id)
            #expect(intermediateReadiness.state == .notReady)
            #expect(intermediateReadiness.isIndexUsable)
            #expect(finalToken?.isReady == true)
            #expect(finalToken?.indexedSourceRevision == successorBatch.id)
        }
    }

    @Test
    func externalRevisionChangeCannotRemainReadyWithoutReconciliation() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            fixture.updatePrimaryEntityNotes("Imported from CloudKit")
            await source.setSnapshot(fixture.snapshot)
            await source.clearReads()

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let documents = try await store.documents(
                for: GraphSearchSourceReference(
                    graphID: fixture.graphID,
                    sourceKind: .entity,
                    sourceID: fixture.primaryEntityID
                )
            )

            #expect(result.outcome == .reconciled)
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 1)
            #expect(documents.contains {
                $0.normalizedSearchText.contains(BMSearch.fold("Imported from CloudKit"))
            })
        }
    }

    @Test
    func unknownSourceRevisionNeverUsesPersistentFastPath() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, _, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            await source.setSourceRevision(nil, graphID: fixture.graphID)
            await source.clearReads()

            let first = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let second = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )

            #expect(first.outcome == .ready)
            #expect(second.outcome == .ready)
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 2)
            #expect(await source.readCount(for: .sourcePage(fixture.graphID)) == 0)
        }
    }

    @Test
    func externalDeletionRemovesStaleDocumentsAndManifestEntry() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )

            let reducedSnapshot = graphSearchSnapshot(
                from: fixture,
                entities: [fixture.primaryEntity]
            )
            await source.setSnapshot(reducedSnapshot)

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let deletedReference = GraphSearchSourceReference(
                graphID: fixture.graphID,
                sourceKind: .entity,
                sourceID: fixture.secondaryEntityID
            )

            let deletedDocuments = try await store.documents(
                for: deletedReference
            )
            let deletedManifestEntry = try await store.sourceManifestEntry(
                for: deletedReference
            )
            let reconciledManifest = try await store.sourceManifest(
                in: fixture.graphID
            )

            #expect(result.outcome == .reconciled)
            #expect(result.metrics?.deletedSourceCount == 1)
            #expect(deletedDocuments.isEmpty)
            #expect(deletedManifestEntry == nil)
            #expect(
                reconciledManifest?.sourceCount
                    == reducedSnapshot.searchSourceCountForTesting
            )
        }
    }

    @Test
    func externalAdditionCreatesDocumentsAndManifestEntry() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )

            let addedID = graphSearchIndexerTestUUID(
                graphID: fixture.graphID,
                value: 900
            )
            let addedEntity = GraphEntityDTO(
                id: addedID,
                scope: fixture.scope,
                name: "External Entity",
                notes: "Added without a local mutation event",
                iconSymbolName: "sparkles",
                createdAt: Date(timeIntervalSince1970: 1_700_000_900)
            )
            let expandedSnapshot = graphSearchSnapshot(
                from: fixture,
                entities: [
                    fixture.primaryEntity,
                    fixture.secondaryEntity,
                    addedEntity
                ]
            )
            await source.setSnapshot(expandedSnapshot)

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .explicit
            )
            let addedReference = GraphSearchSourceReference(
                graphID: fixture.graphID,
                sourceKind: .entity,
                sourceID: addedID
            )

            let addedDocuments = try await store.documents(
                for: addedReference
            )
            let addedManifestEntry = try await store.sourceManifestEntry(
                for: addedReference
            )

            #expect(result.outcome == .reconciled)
            #expect(result.metrics?.addedSourceCount == 1)
            #expect(addedDocuments.count == 2)
            #expect(addedManifestEntry != nil)
        }
    }

    @Test
    func unchangedGraphDoesNoWritesAndNoFullRebuild() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, _, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let rebuildCount = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )
            await source.clearReads()

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .explicit
            )

            #expect(result.outcome == .ready)
            #expect(result.metrics?.changedSourceTotal == 0)
            #expect(result.metrics?.fullRebuild == false)
            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            )
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCount
            )
        }
    }

    @Test
    func incompatibleManifestVersionTriggersAtomicFullRebuild() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, _, store, location in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let rebuildCount = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )

            try updateStoredManifest(
                databaseURL: location.databaseURL,
                graphID: fixture.graphID,
                column: "format_version",
                integerValue: GraphSearchSourceManifestSchema.currentVersion + 1
            )

            let incompatible = try await store.sourceManifest(in: fixture.graphID)
            #expect(incompatible?.isCompatible == false)

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let repaired = try await store.sourceManifest(in: fixture.graphID)

            #expect(result.outcome == .rebuilt)
            #expect(result.metrics?.fullRebuild == true)
            #expect(repaired?.isCompatible == true)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCount + 1
            )
        }
    }

    @Test
    func missingManifestWithExistingDocumentsTriggersSafeRebuild() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, _, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let documents = try await store.documents(in: fixture.graphID)
            let rebuildCount = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )

            try await store.replaceDocuments(
                in: fixture.graphID,
                with: documents
            )
            let missingManifest = try await store.sourceManifest(
                in: fixture.graphID
            )
            #expect(missingManifest == nil)

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let repairedManifest = try await store.sourceManifest(
                in: fixture.graphID
            )

            #expect(result.outcome == .rebuilt)
            #expect(result.isIndexUsable)
            #expect(repairedManifest != nil)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCount + 1
            )
        }
    }

    @Test
    func corruptManifestTriggersSafeRebuildWithoutPublishingPartialState() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, _, store, location in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let expectedDocuments = try await store.documents(in: fixture.graphID)
            let rebuildCount = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )

            try updateStoredManifest(
                databaseURL: location.databaseURL,
                graphID: fixture.graphID,
                column: "aggregate_hash",
                textValue: "corrupt"
            )

            await #expect(throws: GraphSearchIndexStoreError.self) {
                _ = try await store.sourceManifest(in: fixture.graphID)
            }

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let repairedDocuments = try await store.documents(
                in: fixture.graphID
            )
            let repairedManifest = try await store.sourceManifest(
                in: fixture.graphID
            )

            #expect(result.outcome == .rebuilt)
            #expect(repairedDocuments == expectedDocuments)
            #expect(repairedManifest?.isCompatible == true)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCount + 1
            )
        }
    }

    @Test
    func corruptLifecycleMetadataTriggersSafeAtomicRebuild() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, _, store, location in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let expectedDocuments = try await store.documents(in: fixture.graphID)
            let rebuildCount = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )
            try updateStoredLifecycle(
                databaseURL: location.databaseURL,
                graphID: fixture.graphID,
                column: "active_generation",
                textValue: "not-a-generation"
            )

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let repairedLifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            #expect(result.outcome == .rebuilt)
            #expect(result.isIndexUsable)
            #expect(try await store.documents(in: fixture.graphID) == expectedDocuments)
            #expect(repairedLifecycle?.lifecycleState == .ready)
            #expect(repairedLifecycle?.activeGeneration != nil)
            #expect(repairedLifecycle?.stagingGeneration == nil)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCount + 1
            )
        }
    }

    @Test
    func missingActiveGenerationTriggersSafeAtomicRebuild() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, _, store, location in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            try updateStoredLifecycle(
                databaseURL: location.databaseURL,
                graphID: fixture.graphID,
                column: "active_generation",
                textValue: nil
            )

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let lifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            #expect(result.outcome == .rebuilt)
            #expect(result.isIndexUsable)
            #expect(lifecycle?.activeGeneration != nil)
            #expect(lifecycle?.lifecycleState == .ready)
        }
    }

    @Test
    func missingIndexRevisionForcesValidatedReconciliation() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, store, location in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            try updateStoredLifecycle(
                databaseURL: location.databaseURL,
                graphID: fixture.graphID,
                column: "index_revision",
                textValue: nil
            )
            await source.clearReads()

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let lifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )

            #expect(result.outcome == .ready)
            #expect(
                result.metrics?.checkedSourceCount
                    == fixture.snapshot.searchSourceCountForTesting
            )
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 1)
            #expect(lifecycle?.indexRevision != nil)
            #expect(lifecycle?.lifecycleState == .ready)
        }
    }

    @Test
    func semanticallyCorruptedStoredDocumentTriggersSafeFullRebuild() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, _, store, location in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let documents = try await store.documents(in: fixture.graphID)
            let document = try #require(documents.first)
            let rebuildCount = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )

            try updateStoredDocumentTitle(
                databaseURL: location.databaseURL,
                documentID: document.documentID,
                title: "Semantically corrupted title"
            )
            await #expect(throws: GraphSearchIndexStoreError.self) {
                _ = try await store.sourceManifest(in: fixture.graphID)
            }

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .indexFailure
            )
            let repairedDocuments = try await store.documents(
                in: fixture.graphID
            )
            let repairedManifest = try await store.sourceManifest(
                in: fixture.graphID
            )

            #expect(result.outcome == .rebuilt)
            #expect(result.isIndexUsable)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCount + 1
            )
            #expect(repairedDocuments == documents)
            #expect(repairedManifest != nil)
        }
    }

    @Test
    func failedIncrementalCommitRollsBackDocumentsAndManifestTogether() async throws {
        var fixture = GraphSearchIndexerFixture()
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let gate = GraphSearchIndexCancellationGate()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback,
            cancellationCheck: {
                try gate.check()
            }
        )

        do {
            _ = try await store.open()
            let builder = GraphSearchDocumentBuilder()
            let originalBuild = try builder.buildSnapshot(for: fixture.snapshot)
            try await store.replaceDocuments(
                in: fixture.graphID,
                with: originalBuild.documents,
                sourceManifest: originalBuild.sourceManifest
            )

            fixture.updatePrimaryEntityNotes("Transaction should roll back")
            let changedBuild = try builder.buildSnapshot(for: fixture.snapshot)
            let reference = GraphSearchSourceReference(
                graphID: fixture.graphID,
                sourceKind: .entity,
                sourceID: fixture.primaryEntityID
            )
            let replacementBuild = try #require(
                changedBuild.sourceBuilds.first { $0.reference == reference }
            )
            let replacement = GraphSearchIndexSourceReplacement(
                sourceReference: reference,
                documents: replacementBuild.documents,
                manifestEntry: replacementBuild.manifestEntry
            )

            gate.fail(afterSuccessfulChecks: 1)
            await #expect(throws: GraphSearchIndexerTestFailure.self) {
                try await store.reconcile(
                    graphID: fixture.graphID,
                    replacements: [replacement],
                    deletions: [],
                    expectedSourceManifest: originalBuild.sourceManifest,
                    sourceManifest: changedBuild.sourceManifest
                )
            }
            gate.disableFailure()

            let rolledBackDocuments = try await store.documents(
                in: fixture.graphID
            )
            let rolledBackManifest = try await store.sourceManifest(
                in: fixture.graphID
            )

            #expect(rolledBackDocuments == originalBuild.documents)
            #expect(rolledBackManifest == originalBuild.sourceManifest)

            try await store.close()
            location.remove()
        } catch {
            gate.disableFailure()
            do {
                try await store.close()
            } catch let closeError {
                Issue.record("Failed to close rollback test store: \(closeError)")
            }
            location.remove()
            throw error
        }
    }

    @Test
    func failedFullRebuildKeepsThePreviousValidIndexUsable() async throws {
        var fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let previousDocuments = try await store.documents(in: fixture.graphID)
            let previousManifest = try await store.sourceManifest(in: fixture.graphID)

            fixture.renameAttribute(to: "Unavailable Replacement")
            await source.setSnapshot(fixture.snapshot)
            await source.setFailure(true, graphID: fixture.graphID)
            await reconciler.invalidate(
                scope: fixture.scope,
                reason: .indexFailure
            )
            let invalidatedReadiness = await reconciler.readiness(
                for: fixture.scope
            )

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .explicit
            )
            let readiness = await reconciler.readiness(for: fixture.scope)
            let retainedDocuments = try await store.documents(
                in: fixture.graphID
            )
            let retainedManifest = try await store.sourceManifest(
                in: fixture.graphID
            )

            #expect(invalidatedReadiness.state == .unavailable)
            #expect(invalidatedReadiness.isIndexUsable == false)
            #expect(result.outcome == .failed)
            #expect(result.isIndexUsable)
            #expect(result.metrics?.fullRebuild == true)
            #expect(readiness.isIndexUsable)
            #expect(retainedDocuments == previousDocuments)
            #expect(retainedManifest == previousManifest)

            await source.setFailure(false, graphID: fixture.graphID)
            let retry = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .explicit
            )
            let rebuiltDocuments = try await store.documents(
                in: fixture.graphID
            )

            #expect(retry.outcome == .rebuilt)
            #expect(retry.isIndexUsable)
            #expect(
                rebuiltDocuments.contains {
                    $0.normalizedSearchText.contains(
                        BMSearch.fold("Unavailable Replacement")
                    )
                }
            )
        }
    }

    @Test
    func readinessTokenDoesNotSuppressAnExplicitIndexInvalidation() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, _, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .foreground
            )
            await source.clearReads()
            await reconciler.invalidate(
                scope: fixture.scope,
                reason: .indexFailure
            )
            let invalidatedReadiness = await reconciler.readiness(
                for: fixture.scope
            )

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .foreground
            )

            #expect(invalidatedReadiness.state == .unavailable)
            #expect(invalidatedReadiness.isIndexUsable == false)
            #expect(result.outcome == .rebuilt)
            #expect(result.isIndexUsable)
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 1)
            #expect(
                await reconciler.completedOperationCountForTesting(
                    graphID: fixture.graphID
                ) == 2
            )
        }
    }

    @Test
    func concurrentLocalManifestUpdateIsNeverOverwrittenByReconciliation() async throws {
        var externalFixture = GraphSearchIndexerFixture()
        var localFixture = externalFixture

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [externalFixture.snapshot]
        ) { reconciler, _, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: externalFixture.scope,
                reason: .firstSearch
            )

            externalFixture.updatePrimaryEntityNotes("External snapshot version")
            localFixture.updatePrimaryEntityNotes("Newer local index version")
            await source.setSnapshot(externalFixture.snapshot)
            await source.setSnapshotDelay(nanoseconds: 300_000_000)
            await source.clearReads()

            let operation = Task {
                await reconciler.ensureReady(
                    scope: externalFixture.scope,
                    reason: .explicit
                )
            }
            try await waitForGraphSearchIndexerCondition {
                await source.readCount(
                    for: .snapshot(externalFixture.graphID)
                ) == 1
            }

            let localBuild = try GraphSearchDocumentBuilder().sourceBuild(
                for: localFixture.primaryEntity
            )
            try await store.replaceDocuments(
                for: localBuild.reference,
                with: localBuild.documents,
                manifestEntry: localBuild.manifestEntry
            )
            let locallyUpdatedManifest = try await store.sourceManifest(
                in: externalFixture.graphID
            )

            let result = await operation.value
            let storedDocuments = try await store.documents(
                for: localBuild.reference
            )
            let storedManifest = try await store.sourceManifest(
                in: externalFixture.graphID
            )

            #expect(result.outcome == .failed)
            #expect(result.isIndexUsable)
            #expect(
                storedDocuments.contains {
                    $0.documentKind == .entityNotes
                        && $0.normalizedSearchText.contains(
                            BMSearch.fold("Newer local index version")
                        )
                }
            )
            #expect(
                storedDocuments.contains {
                    $0.normalizedSearchText.contains(
                        BMSearch.fold("External snapshot version")
                    )
                } == false
            )
            #expect(storedManifest == locallyUpdatedManifest)
        }
    }

    @Test
    func parallelReconciliationsOfTheSameGraphAreCoalesced() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, store, _ in
            await source.setSnapshotDelay(nanoseconds: 200_000_000)

            async let first = reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            async let second = reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )
            let results = await (first, second)
            let documentCount = try await store.documentCount(
                in: fixture.graphID
            )

            #expect(results.0.outcome == .rebuilt)
            #expect(results.1.outcome == .rebuilt)
            #expect(results.0.reason == .firstSearch)
            #expect(results.1.reason == .chatSession)
            #expect(
                await reconciler.completedOperationCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            )
            #expect(documentCount == 22)
        }
    }

    @Test
    func cancellingOneWaiterDoesNotCancelAnotherWaiter() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, _, _ in
            await source.setSnapshotDelay(nanoseconds: 300_000_000)

            let first = Task {
                await reconciler.ensureReady(
                    scope: fixture.scope,
                    reason: .firstSearch
                )
            }
            try await waitForGraphSearchIndexerCondition {
                await reconciler.hasActiveOperationForTesting(
                    graphID: fixture.graphID
                )
            }
            let second = Task {
                await reconciler.ensureReady(
                    scope: fixture.scope,
                    reason: .chatSession
                )
            }
            try await Task.sleep(nanoseconds: 25_000_000)
            first.cancel()

            let firstResult = await first.value
            let secondResult = await second.value

            #expect(firstResult.outcome == .cancelled)
            #expect(secondResult.outcome == .rebuilt)
            #expect(secondResult.isIndexUsable)
            #expect(
                await reconciler.completedOperationCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
        }
    }

    @Test
    func cancellingLastRequestWaiterCancelsWorkerAndNeverPublishesStage() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, store, _ in
            await source.setSnapshotDelay(nanoseconds: 500_000_000)
            let request = Task {
                await reconciler.ensureReady(
                    scope: fixture.scope,
                    reason: .firstSearch
                )
            }
            try await waitForGraphSearchIndexerCondition {
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            }
            request.cancel()
            let result = await request.value

            try await waitForGraphSearchIndexerCondition {
                let status = await indexer.status(for: fixture.scope)
                return status.state != .building
            }
            let lifecycle = try await store.storedLifecycle(
                graphID: fixture.graphID
            )
            let documents = try await store.documents(in: fixture.graphID)

            #expect(result.outcome == .cancelled)
            #expect(lifecycle?.activeGeneration == nil)
            #expect(lifecycle?.stagingGeneration == nil)
            #expect(documents.isEmpty)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 0
            )
        }
    }

    @Test
    func requestArrivingWhileCancelledWorkerDrainsStartsFreshWorker() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, store, _ in
            await source.setSnapshotDelay(nanoseconds: 5_000_000_000)
            let cancelledRequest = Task {
                await reconciler.ensureReady(
                    scope: fixture.scope,
                    reason: .firstSearch
                )
            }
            try await waitForGraphSearchIndexerCondition {
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            }
            cancelledRequest.cancel()
            let cancelledResult = await cancelledRequest.value
            await source.setSnapshotDelay(nanoseconds: 0)

            let retryResult = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .chatSession
            )

            #expect(cancelledResult.outcome == .cancelled)
            #expect(retryResult.outcome == .rebuilt)
            #expect(retryResult.isIndexUsable)
            #expect(try await store.documentCount(in: fixture.graphID) == 22)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
        }
    }

    @Test
    func explicitMaintenanceOwnerKeepsWorkerAliveAfterRequestCancellation() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, _, _ in
            await source.setSnapshotDelay(nanoseconds: 300_000_000)
            let request = Task {
                await reconciler.ensureReady(
                    scope: fixture.scope,
                    reason: .firstSearch
                )
            }
            try await waitForGraphSearchIndexerCondition {
                await reconciler.hasActiveOperationForTesting(
                    graphID: fixture.graphID
                )
            }
            let maintenance = Task {
                await reconciler.performMaintenance(
                    scope: fixture.scope,
                    reason: .explicit
                )
            }
            try await waitForGraphSearchIndexerCondition {
                let counts = await reconciler.waiterCountsForTesting(
                    graphID: fixture.graphID
                )
                return counts.request == 1 && counts.maintenance == 1
            }
            request.cancel()

            let requestResult = await request.value
            let maintenanceResult = await maintenance.value

            #expect(requestResult.outcome == .cancelled)
            #expect(maintenanceResult.outcome == .rebuilt)
            #expect(maintenanceResult.isIndexUsable)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
        }
    }

    @Test
    func twoGraphsReconcileIndependentlyWithoutCrossGraphLeakage() async throws {
        let firstFixture = GraphSearchIndexerFixture()
        var secondFixture = GraphSearchIndexerFixture()
        secondFixture.renamePrimaryEntity(to: "Second Graph Entity")

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [firstFixture.snapshot, secondFixture.snapshot]
        ) { reconciler, _, source, store, _ in
            await source.setSnapshotDelay(nanoseconds: 100_000_000)

            async let first = reconciler.ensureReady(
                scope: firstFixture.scope,
                reason: .explicit
            )
            async let second = reconciler.ensureReady(
                scope: secondFixture.scope,
                reason: .explicit
            )
            let results = await (first, second)

            let firstDocuments = try await store.documents(
                in: firstFixture.graphID
            )
            let secondDocuments = try await store.documents(
                in: secondFixture.graphID
            )

            #expect(results.0.outcome == .rebuilt)
            #expect(results.1.outcome == .rebuilt)
            #expect(firstDocuments.allSatisfy {
                $0.graphID == firstFixture.graphID
            })
            #expect(secondDocuments.allSatisfy {
                $0.graphID == secondFixture.graphID
            })
            #expect(Set(firstDocuments.map(\.documentID)).isDisjoint(
                with: Set(secondDocuments.map(\.documentID))
            ))
        }
    }

    @Test
    func foregroundEnsureReadyUsesPersistentFastPathPerGraph() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, _, _ in
            let first = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .foreground
            )
            await source.clearReads()

            let second = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .foreground
            )

            #expect(first.outcome == .rebuilt)
            #expect(second.outcome == .ready)
            #expect(second.isIndexUsable)
            #expect(await source.readCount(for: .snapshot(fixture.graphID)) == 0)
            #expect(await source.readCount(for: .sourcePage(fixture.graphID)) == 0)
            #expect(
                await source.readCount(for: .sourceRevision(fixture.graphID)) == 1
            )
            #expect(
                await reconciler.completedOperationCountForTesting(
                    graphID: fixture.graphID
                ) == 1
            )
        }
    }

    @Test
    func importReplaceDedupeAndIndexFailureReachTheReadinessBoundary() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, indexer, source, _, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let recorder = GraphSearchIndexReadinessInvalidationRecorder()
            await indexer.setReadinessInvalidator(recorder)

            await indexer.processCommittedBatch(
                try GraphMutationBatchFactory.graphImported(
                    graphID: fixture.graphID
                )
            )
            await indexer.processCommittedBatch(
                try GraphMutationBatchFactory.graphReplaced(
                    graphID: fixture.graphID
                )
            )
            await indexer.processCommittedBatch(
                try GraphMutationBatchFactory.graphIntegrityRepair(
                    graphID: fixture.graphID
                )
            )

            await source.removeSnapshot(graphID: fixture.graphID)
            await indexer.processCommittedBatch(
                try GraphMutationBatchFactory.nodeUpdated(
                    graphID: fixture.graphID,
                    node: NodeRefKey(
                        kind: .entity,
                        id: fixture.primaryEntityID
                    )
                )
            )

            #expect(await recorder.reasons(for: fixture.graphID) == [
                .importOrReplace,
                .importOrReplace,
                .dedupe,
                .indexFailure
            ])
        }
    }

    @Test
    func readinessReportsExistingIndexUsableWhileReconciliationRuns() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { reconciler, _, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )

            let secondaryIndexer = GraphSearchIndexer(
                sourceReader: source,
                store: store,
                subscriber: GraphMutationEventBus()
            )
            let secondaryReconciler = GraphSearchIndexReconciler(
                sourceReader: source,
                store: store,
                indexer: secondaryIndexer
            )
            await secondaryIndexer.setReadinessInvalidator(secondaryReconciler)
            await source.setSnapshotDelay(nanoseconds: 250_000_000)

            let operation = Task {
                await secondaryReconciler.ensureReady(
                    scope: fixture.scope,
                    reason: .explicit
                )
            }
            try await waitForGraphSearchIndexerCondition {
                await secondaryReconciler.hasActiveOperationForTesting(
                    graphID: fixture.graphID
                )
            }

            let readiness = await secondaryReconciler.readiness(
                for: fixture.scope
            )
            let result = await operation.value

            #expect(readiness.state == .reconciling)
            #expect(readiness.isIndexUsable)
            #expect(readiness.documentCount == 22)
            #expect(result.outcome == .ready)
            #expect(result.isIndexUsable)

            await secondaryReconciler.resetForTesting()
            await secondaryIndexer.resetForTesting()
        }
    }

    @Test
    func broadStructuralDriftTriggersAtomicFullRebuild() async throws {
        let fixture = GraphSearchIndexerFixture()
        let initialEntities = (0..<256).map { index in
            GraphEntityDTO(
                id: graphSearchIndexerTestUUID(
                    graphID: fixture.graphID,
                    value: 20_000 + index
                ),
                scope: fixture.scope,
                name: "Initial Entity \(index)",
                notes: "",
                iconSymbolName: "circle",
                createdAt: Date(timeIntervalSince1970: 1_700_200_000 + Double(index))
            )
        }
        let initialSnapshot = GraphSourceSnapshotDTO(
            scope: fixture.scope,
            graph: fixture.graph,
            entities: initialEntities,
            attributes: [],
            links: [],
            detailFieldDefinitions: [],
            detailValues: [],
            attachments: []
        )
        let reducedSnapshot = GraphSourceSnapshotDTO(
            scope: fixture.scope,
            graph: fixture.graph,
            entities: Array(initialEntities.prefix(128)),
            attributes: [],
            links: [],
            detailFieldDefinitions: [],
            detailValues: [],
            attachments: []
        )

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [initialSnapshot]
        ) { reconciler, indexer, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let rebuildCount = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )
            await source.setSnapshot(reducedSnapshot)

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .explicit
            )
            let documentCount = try await store.documentCount(
                in: fixture.graphID
            )

            #expect(result.outcome == .rebuilt)
            #expect(result.metrics?.fullRebuild == true)
            #expect(result.metrics?.checkedSourceCount == 128)
            #expect(result.metrics?.deletedSourceCount == 128)
            #expect(result.metrics?.changedSourceTotal == 128)
            #expect(documentCount == 128)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCount + 1
            )
        }
    }

    @Test
    func foregroundPolicyPreservesSystemModalAndGraphLockGuards() {
        let graphID = UUID()
        let graphIDString = graphID.uuidString

        #expect(
            GraphSearchIndexForegroundReconciliationPolicy.scope(
                activeGraphIDString: graphIDString,
                isSystemModalPresented: false,
                hasActiveGraphLockRequest: false
            ) == GraphScope(graphID: graphID)
        )
        #expect(
            GraphSearchIndexForegroundReconciliationPolicy.scope(
                activeGraphIDString: graphIDString,
                isSystemModalPresented: true,
                hasActiveGraphLockRequest: false
            ) == nil
        )
        #expect(
            GraphSearchIndexForegroundReconciliationPolicy.scope(
                activeGraphIDString: graphIDString,
                isSystemModalPresented: false,
                hasActiveGraphLockRequest: true
            ) == nil
        )
        #expect(
            GraphSearchIndexForegroundReconciliationPolicy.scope(
                activeGraphIDString: "00000000-0000-0000-0000-000000000000",
                isSystemModalPresented: false,
                hasActiveGraphLockRequest: false
            ) == nil
        )
        #expect(
            GraphSearchIndexForegroundReconciliationPolicy.scope(
                activeGraphIDString: "not-a-graph-id",
                isSystemModalPresented: false,
                hasActiveGraphLockRequest: false
            ) == nil
        )
    }

    @Test
    func largeUnchangedGraphUsesOneSnapshotAndNoPerSourceFetches() async throws {
        let fixture = GraphSearchIndexerFixture()
        let entityCount = 3_000
        let entities = (0..<entityCount).map { index in
            GraphEntityDTO(
                id: graphSearchIndexerTestUUID(
                    graphID: fixture.graphID,
                    value: 10_000 + index
                ),
                scope: fixture.scope,
                name: "Synthetic Entity \(index)",
                notes: "",
                iconSymbolName: "circle",
                createdAt: Date(timeIntervalSince1970: 1_700_100_000 + Double(index))
            )
        }
        let snapshot = GraphSourceSnapshotDTO(
            scope: fixture.scope,
            graph: fixture.graph,
            entities: entities,
            attributes: [],
            links: [],
            detailFieldDefinitions: [],
            detailValues: [],
            attachments: []
        )

        try await withGraphSearchReconcilerTestEnvironment(
            snapshots: [snapshot]
        ) { reconciler, indexer, source, store, _ in
            _ = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .firstSearch
            )
            let rebuildCount = await indexer.completedRebuildCountForTesting(
                graphID: fixture.graphID
            )
            let initialRebuildPageCount = await source.readCount(
                for: .sourcePage(fixture.graphID)
            )
            await source.clearReads()

            let result = await reconciler.ensureReady(
                scope: fixture.scope,
                reason: .explicit
            )
            let documentCount = try await store.documentCount(
                in: fixture.graphID
            )

            #expect(result.outcome == .ready)
            #expect(result.metrics?.checkedSourceCount == entityCount)
            #expect(result.metrics?.changedSourceTotal == 0)
            #expect(initialRebuildPageCount > 1)
            #expect(
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            )
            #expect(
                await source.readCount(for: .sourcePage(fixture.graphID)) == 0
            )
            #expect(documentCount == entityCount)
            #expect(
                await indexer.completedRebuildCountForTesting(
                    graphID: fixture.graphID
                ) == rebuildCount
            )
        }
    }

    @Test
    func manifestHashIsDeterministicAcrossRepeatedBuildsAndInputOrdering() throws {
        let fixture = GraphSearchIndexerFixture()
        let builder = GraphSearchDocumentBuilder()
        let original = try builder.buildSnapshot(for: fixture.snapshot)
        let reorderedSnapshot = GraphSourceSnapshotDTO(
            scope: fixture.scope,
            graph: fixture.graph,
            entities: [fixture.secondaryEntity, fixture.primaryEntity],
            attributes: [fixture.attribute],
            links: Array(fixture.links.reversed()),
            detailFieldDefinitions: Array(fixture.definitions.reversed()),
            detailValues: Array(fixture.values.reversed()),
            attachments: [fixture.attachment]
        )
        let reordered = try builder.buildSnapshot(for: reorderedSnapshot)

        #expect(original.sourceManifest == reordered.sourceManifest)
        #expect(
            original.sourceManifest.aggregateHash
                == reordered.sourceManifest.aggregateHash
        )
        #expect(original.documents == reordered.documents)
    }
}

private extension GraphSourceSnapshotDTO {
    nonisolated var searchSourceCountForTesting: Int {
        entities.count
            + attributes.count
            + links.count
            + detailFieldDefinitions.count
            + detailValues.count
            + attachments.count
    }
}

private func graphSearchSnapshot(
    from fixture: GraphSearchIndexerFixture,
    entities: [GraphEntityDTO]? = nil,
    attributes: [GraphAttributeDTO]? = nil,
    links: [GraphLinkDTO]? = nil,
    definitions: [GraphDetailFieldDefinitionDTO]? = nil,
    values: [GraphDetailValueDTO]? = nil,
    attachments: [GraphAttachmentMetadataDTO]? = nil
) -> GraphSourceSnapshotDTO {
    GraphSourceSnapshotDTO(
        scope: fixture.scope,
        graph: fixture.graph,
        entities: entities ?? [fixture.primaryEntity, fixture.secondaryEntity],
        attributes: attributes ?? [fixture.attribute],
        links: links ?? fixture.links,
        detailFieldDefinitions: definitions ?? fixture.definitions,
        detailValues: values ?? fixture.values,
        attachments: attachments ?? [fixture.attachment]
    )
}

private func updateStoredManifest(
    databaseURL: URL,
    graphID: UUID,
    column: String,
    integerValue: Int
) throws {
    let supportedColumns = Set(["format_version", "index_schema_version"])
    guard supportedColumns.contains(column) else {
        throw GraphSearchIndexStoreError.invalidSourceManifest(
            reason: "Unsupported integer test mutation column."
        )
    }

    let connection = try GraphSearchSQLiteConnection(databaseURL: databaseURL)
    do {
        try connection.setBusyTimeout(milliseconds: 2_000)
        do {
            let statement = try connection.prepare(
                "UPDATE graph_search_source_manifests SET \(column) = ? WHERE graph_id = ?",
                operation: "test-update-source-manifest-integer"
            )
            try statement.bind(integerValue, at: 1)
            try statement.bind(graphID.uuidString.lowercased(), at: 2)
            try statement.stepExpectingDone()
        }
        try connection.close()
    } catch {
        do {
            try connection.close()
        } catch {
            Issue.record("Failed to close manifest mutation connection: \(error)")
        }
        throw error
    }
}

private func updateStoredManifest(
    databaseURL: URL,
    graphID: UUID,
    column: String,
    textValue: String
) throws {
    guard column == "aggregate_hash" else {
        throw GraphSearchIndexStoreError.invalidSourceManifest(
            reason: "Unsupported text test mutation column."
        )
    }

    let connection = try GraphSearchSQLiteConnection(databaseURL: databaseURL)
    do {
        try connection.setBusyTimeout(milliseconds: 2_000)
        do {
            let statement = try connection.prepare(
                "UPDATE graph_search_source_manifests SET aggregate_hash = ? WHERE graph_id = ?",
                operation: "test-update-source-manifest-text"
            )
            try statement.bind(textValue, at: 1)
            try statement.bind(graphID.uuidString.lowercased(), at: 2)
            try statement.stepExpectingDone()
        }
        try connection.close()
    } catch {
        do {
            try connection.close()
        } catch {
            Issue.record("Failed to close manifest mutation connection: \(error)")
        }
        throw error
    }
}

private func updateStoredDocumentTitle(
    databaseURL: URL,
    documentID: String,
    title: String
) throws {
    let connection = try GraphSearchSQLiteConnection(databaseURL: databaseURL)
    do {
        try connection.setBusyTimeout(milliseconds: 2_000)
        do {
            let statement = try connection.prepare(
                "UPDATE graph_search_documents SET title = ? WHERE document_id = ?",
                operation: "test-update-document-title"
            )
            try statement.bind(title, at: 1)
            try statement.bind(documentID, at: 2)
            try statement.stepExpectingDone()
        }
        try connection.close()
    } catch {
        do {
            try connection.close()
        } catch {
            Issue.record("Failed to close document title mutation connection: \(error)")
        }
        throw error
    }
}

private func updateStoredLifecycle(
    databaseURL: URL,
    graphID: UUID,
    column: String,
    textValue: String?
) throws {
    let supportedColumns = Set(["active_generation", "index_revision"])
    guard supportedColumns.contains(column) else {
        throw GraphSearchIndexStoreError.invalidSourceManifest(
            reason: "Unsupported lifecycle test mutation column."
        )
    }

    let connection = try GraphSearchSQLiteConnection(databaseURL: databaseURL)
    do {
        try connection.setBusyTimeout(milliseconds: 2_000)
        do {
            let statement = try connection.prepare(
                "UPDATE graph_search_index_lifecycle SET \(column) = ? WHERE graph_id = ?",
                operation: "test-update-index-lifecycle"
            )
            try statement.bind(textValue, at: 1)
            try statement.bind(graphID.uuidString.lowercased(), at: 2)
            try statement.stepExpectingDone()
        }
        try connection.close()
    } catch {
        do {
            try connection.close()
        } catch {
            Issue.record("Failed to close lifecycle mutation connection: \(error)")
        }
        throw error
    }
}

private final class GraphSearchIndexCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var successfulChecksBeforeFailure: Int?

    func fail(afterSuccessfulChecks count: Int) {
        lock.lock()
        successfulChecksBeforeFailure = max(0, count)
        lock.unlock()
    }

    func disableFailure() {
        lock.lock()
        successfulChecksBeforeFailure = nil
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let remaining = successfulChecksBeforeFailure else {
            return
        }
        guard remaining > 0 else {
            throw GraphSearchIndexerTestFailure.injected
        }
        successfulChecksBeforeFailure = remaining - 1
    }
}
