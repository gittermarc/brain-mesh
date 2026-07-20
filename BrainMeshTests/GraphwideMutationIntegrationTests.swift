import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct GraphwideMutationIntegrationTests {

    @Test
    func graphDeletionPublishesOnlyAfterSaveThenRunsSideEffects() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let deletedGraph = fixtures.makeGraph(name: "Delete", id: graphwideTestUUID(1))
        let survivor = fixtures.makeGraph(name: "Keep", id: graphwideTestUUID(2))
        let entity = fixtures.makeEntity(name: "Entity", in: deletedGraph)
        entity.imagePath = "header-cache.jpg"
        let template = MetaDetailsTemplate(
            name: "Delete with graph",
            graphID: deletedGraph.id,
            fields: []
        )
        store.context.insert(template)
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(publisher: publisher)
        var lockedGraphIDs: [UUID] = []
        var attachmentCleanupCount = 0
        var deletedImagePaths: [String] = []
        let sideEffects = GraphDeletionPostCommitActions(
            lockGraph: { _, graphID in lockedGraphIDs.append(graphID) },
            deleteAttachmentCaches: { _ in attachmentCleanupCount += 1 },
            deleteImagePath: { path in deletedImagePaths.append(path) }
        )

        let result = try await GraphDeletionService.deleteGraphCompletely(
            graphToDelete: deletedGraph,
            currentActiveGraphID: deletedGraph.id,
            graphs: [deletedGraph, survivor],
            uniqueGraphs: [deletedGraph, survivor],
            modelContext: store.context,
            graphLock: GraphLockCoordinator(),
            committer: committer,
            postCommitActions: sideEffects
        )

        #expect(result.newActiveGraphID == survivor.id)
        #expect(await publisher.recordedBatches.count == 1)
        #expect(await publisher.recordedBatches.first?.graphID == deletedGraph.id)
        #expect(await publisher.recordedBatches.first?.events.map(\.kind) == [.graphDeleted])
        #expect(lockedGraphIDs == [deletedGraph.id])
        #expect(attachmentCleanupCount == 1)
        #expect(deletedImagePaths == ["header-cache.jpg"])

        let deletedID = deletedGraph.id
        let remainingDeletedGraphs = try store.context.fetch(
            FetchDescriptor<MetaGraph>(predicate: #Predicate { $0.id == deletedID })
        )
        #expect(remainingDeletedGraphs.isEmpty)
        #expect(
            try store.context.fetchCount(
                FetchDescriptor<MetaDetailsTemplate>(
                    predicate: #Predicate { $0.graphID == deletedID }
                )
            ) == 0
        )
    }

    @Test
    func deletingLastGraphUsesOneSaveAndPublishesOneSortedBatchPerGraph() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let deletedGraph = fixtures.makeGraph(
            name: "Only",
            id: graphwideTestUUID(8)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        var saveCallCount = 0
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { context in
                saveCallCount += 1
                try context.save()
            }
        )
        let noOpSideEffects = GraphDeletionPostCommitActions(
            lockGraph: { _, _ in },
            deleteAttachmentCaches: { _ in },
            deleteImagePath: { _ in }
        )

        let result = try await GraphDeletionService.deleteGraphCompletely(
            graphToDelete: deletedGraph,
            currentActiveGraphID: deletedGraph.id,
            graphs: [deletedGraph],
            uniqueGraphs: [deletedGraph],
            modelContext: store.context,
            graphLock: GraphLockCoordinator(),
            committer: committer,
            postCommitActions: noOpSideEffects
        )

        let replacementID = try #require(result.newActiveGraphID)
        let batches = await publisher.recordedBatches
        let expectedGraphIDs = [deletedGraph.id, replacementID].sorted {
            $0.uuidString < $1.uuidString
        }

        #expect(saveCallCount == 1)
        #expect(batches.map(\.graphID) == expectedGraphIDs)
        #expect(
            batches.first(where: { $0.graphID == deletedGraph.id })?.events.map(\.kind)
                == [.graphDeleted]
        )
        #expect(
            batches.first(where: { $0.graphID == replacementID })?.events.map(\.kind)
                == [.graphCreated]
        )
        #expect(
            batches.allSatisfy { batch in
                batch.events.allSatisfy { $0.graphID == batch.graphID }
            }
        )

        let graphs = try store.context.fetch(FetchDescriptor<MetaGraph>())
        #expect(graphs.map(\.id) == [replacementID])
    }

    @Test
    func graphDeletionSaveFailurePublishesNothingAndRunsNoSideEffects() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Protected", id: graphwideTestUUID(10))
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        entity.imagePath = "must-remain.jpg"
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in throw GraphMutationServiceTestError.saveFailed }
        )
        var sideEffectCount = 0
        let sideEffects = GraphDeletionPostCommitActions(
            lockGraph: { _, _ in sideEffectCount += 1 },
            deleteAttachmentCaches: { _ in sideEffectCount += 1 },
            deleteImagePath: { _ in sideEffectCount += 1 }
        )

        await #expect(throws: GraphMutationServiceTestError.saveFailed) {
            _ = try await GraphDeletionService.deleteGraphCompletely(
                graphToDelete: graph,
                currentActiveGraphID: graph.id,
                graphs: [graph],
                uniqueGraphs: [graph],
                modelContext: store.context,
                graphLock: GraphLockCoordinator(),
                committer: committer,
                postCommitActions: sideEffects
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(sideEffectCount == 0)
        let graphID = graph.id
        #expect(
            try store.context.fetchCount(
                FetchDescriptor<MetaGraph>(predicate: #Predicate { $0.id == graphID })
            ) == 1
        )
        #expect(try store.context.fetchCount(FetchDescriptor<MetaGraph>()) == 1)
    }

    @Test
    func dedupePublishesOneDeterministicRepairBatchPerAffectedGraph() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graphA = graphwideTestUUID(20)
        let graphB = graphwideTestUUID(21)
        let aOld = fixtures.makeGraph(name: "A Old", id: graphA)
        aOld.createdAt = Date(timeIntervalSince1970: 1)
        let aNew = fixtures.makeGraph(name: "A New", id: graphA)
        aNew.createdAt = Date(timeIntervalSince1970: 2)
        let bOld = fixtures.makeGraph(name: "B Old", id: graphB)
        bOld.createdAt = Date(timeIntervalSince1970: 1)
        let bNew = fixtures.makeGraph(name: "B New", id: graphB)
        bNew.createdAt = Date(timeIntervalSince1970: 2)
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let report = try await GraphDedupeService.removeDuplicateGraphs(
            using: store.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )

        #expect(report.removedGraphs == 2)
        #expect(report.affectedGraphIDs == [graphA, graphB])
        let batches = await publisher.recordedBatches
        #expect(batches.map(\.graphID) == [graphA, graphB])
        #expect(
            batches.allSatisfy { batch in
                batch.events.map(\.kind) == [
                    .graphRequiresFullRebuild(.integrityRepair)
                ] && batch.events.allSatisfy { $0.graphID == batch.graphID }
            }
        )
    }

    @Test
    func dedupeSaveFailurePublishesNothingAndRestoresDuplicateRecords() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graphID = graphwideTestUUID(22)
        let older = fixtures.makeGraph(name: "Older", id: graphID)
        older.createdAt = Date(timeIntervalSince1970: 1)
        let newer = fixtures.makeGraph(name: "Newer", id: graphID)
        newer.createdAt = Date(timeIntervalSince1970: 2)
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                throw GraphMutationServiceTestError.saveFailed
            }
        )

        await #expect(throws: GraphMutationServiceTestError.saveFailed) {
            _ = try await GraphDedupeService.removeDuplicateGraphs(
                using: store.context,
                committer: committer
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(
            try store.context.fetchCount(
                FetchDescriptor<MetaGraph>(predicate: #Predicate { $0.id == graphID })
            ) == 2
        )
    }

    @Test
    func detailsTemplateCreationPublishesItsTechnicalIdentityAfterSave() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Templates", id: graphwideTestUUID(30))
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        _ = fixtures.makeDetailField(
            owner: entity,
            name: "Field",
            type: .singleLineText,
            sortIndex: 0
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let didSave = try await DetailsSchemaActions.saveTemplate(
            from: entity,
            name: "Reusable",
            modelContext: store.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )

        let template = try #require(
            try store.context.fetch(FetchDescriptor<MetaDetailsTemplate>()).first
        )
        let batches = await publisher.recordedBatches
        #expect(didSave)
        #expect(batches.count == 1)
        #expect(batches.first?.graphID == graph.id)
        #expect(batches.first?.events.map(\.kind) == [.detailTemplateCreated])
        #expect(
            batches.first?.events.first?.references
                == [.detailTemplate(id: template.id)]
        )
    }

    @Test
    func detailsTemplateSaveFailurePublishesNothingAndRollsBackInsertion() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Templates", id: graphwideTestUUID(31))
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        _ = fixtures.makeDetailField(
            owner: entity,
            name: "Field",
            type: .singleLineText,
            sortIndex: 0
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                throw GraphMutationServiceTestError.saveFailed
            }
        )

        await #expect(throws: GraphMutationServiceTestError.saveFailed) {
            _ = try await DetailsSchemaActions.saveTemplate(
                from: entity,
                name: "Not persisted",
                modelContext: store.context,
                committer: committer
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(
            try store.context.fetchCount(FetchDescriptor<MetaDetailsTemplate>()) == 0
        )
    }

    @Test
    func structureImportPublishesExactlyOneFinalImportBatch() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let publisher = GraphMutationRecordingPublisher()
        let service = GraphTransferService(mutationPublisher: publisher)
        await service.configure(container: AnyModelContainer(store.container))
        let url = try writeImportFile(entityCount: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await service.importGraph(
            from: url,
            mode: .asNewGraphRemap,
            progress: nil
        )

        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.first?.graphID == result.newGraphID)
        #expect(
            batches.first?.events.map(\.kind) == [
                .graphImported,
                .graphRequiresFullRebuild(.graphImport)
            ]
        )
    }

    @Test
    func replacementImportPublishesExactlyOneFinalReplacementBatch() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let publisher = GraphMutationRecordingPublisher()
        let service = GraphTransferService(mutationPublisher: publisher)
        await service.configure(container: AnyModelContainer(store.container))
        let url = try writeImportFile(entityCount: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await service.importGraph(
            from: url,
            mode: .asReplacementRemap,
            progress: nil
        )

        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.first?.graphID == result.newGraphID)
        #expect(
            batches.first?.events.map(\.kind) == [
                .graphReplaced,
                .graphRequiresFullRebuild(.graphReplacement)
            ]
        )
    }

    @Test
    func fullBackupImportPublishesExactlyOneFinalImportBatch() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let sourceGraph = fixtures.makeGraph(name: "Backup Source")
        _ = fixtures.makeEntity(name: "Entity", in: sourceGraph)
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let service = GraphTransferService(mutationPublisher: publisher)
        await service.configure(container: AnyModelContainer(store.container))
        let backupURL = try await service.exportFullBackup(
            graphID: sourceGraph.id,
            options: .init()
        )
        defer { try? FileManager.default.removeItem(at: backupURL) }

        let result = try await service.importGraph(
            from: backupURL,
            mode: .asNewGraphRemap,
            progress: nil
        )

        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.first?.graphID == result.newGraphID)
        #expect(
            batches.first?.events.map(\.kind) == [
                .graphImported,
                .graphRequiresFullRebuild(.graphImport)
            ]
        )
    }

    @Test
    func replaceUsesTheActualDeleteAndImportSaveBoundaries() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graphToReplace = fixtures.makeGraph(
            name: "Old",
            id: graphwideTestUUID(40)
        )
        let survivor = fixtures.makeGraph(
            name: "Survivor",
            id: graphwideTestUUID(41)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let noOpSideEffects = GraphDeletionPostCommitActions(
            lockGraph: { _, _ in },
            deleteAttachmentCaches: { _ in },
            deleteImagePath: { _ in }
        )
        _ = try await GraphDeletionService.deleteGraphCompletely(
            graphToDelete: graphToReplace,
            currentActiveGraphID: survivor.id,
            graphs: [graphToReplace, survivor],
            uniqueGraphs: [graphToReplace, survivor],
            modelContext: store.context,
            graphLock: GraphLockCoordinator(),
            committer: GraphMutationCommitter(publisher: publisher),
            postCommitActions: noOpSideEffects
        )

        let service = GraphTransferService(mutationPublisher: publisher)
        await service.configure(container: AnyModelContainer(store.container))
        let url = try writeImportFile(entityCount: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await service.importGraph(
            from: url,
            mode: .asReplacementRemap,
            progress: nil
        )

        let batches = await publisher.recordedBatches
        #expect(batches.count == 2)
        #expect(batches[0].graphID == graphToReplace.id)
        #expect(batches[0].events.map(\.kind) == [.graphDeleted])
        #expect(batches[1].graphID == result.newGraphID)
        #expect(
            batches[1].events.map(\.kind) == [
                .graphReplaced,
                .graphRequiresFullRebuild(.graphReplacement)
            ]
        )
    }

    @Test
    func failedImportPublishesNothingAndLeavesNoVisiblePartialGraph() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let publisher = GraphMutationRecordingPublisher()
        let service = GraphTransferService(
            mutationPublisher: publisher,
            importSaveOperation: { _ in
                throw GraphMutationServiceTestError.saveFailed
            }
        )
        await service.configure(container: AnyModelContainer(store.container))
        let url = try writeImportFile(entityCount: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: GraphTransferError.self) {
            _ = try await service.importGraph(
                from: url,
                mode: .asNewGraphRemap,
                progress: nil
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(try store.context.fetchCount(FetchDescriptor<MetaGraph>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<MetaEntity>()) == 0)
    }

    @Test
    func cancelledCheckpointedImportPublishesNothingAndCleansPersistedRecords() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let publisher = GraphMutationRecordingPublisher()
        let service = GraphTransferService(mutationPublisher: publisher)
        await service.configure(container: AnyModelContainer(store.container))
        let url = try writeImportFile(entityCount: 600)
        defer { try? FileManager.default.removeItem(at: url) }

        let progress: @Sendable (GraphTransferProgress) -> Void = { progress in
            guard progress.phase == .entities,
                  progress.completed >= 501 else {
                return
            }
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
        }

        await #expect(throws: CancellationError.self) {
            _ = try await service.importGraph(
                from: url,
                mode: .asNewGraphRemap,
                progress: progress
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(try store.context.fetchCount(FetchDescriptor<MetaGraph>()) == 0)
        #expect(try store.context.fetchCount(FetchDescriptor<MetaEntity>()) == 0)
    }
}

private func writeImportFile(entityCount: Int) throws -> URL {
    let graphID = UUID()
    let date = Date(timeIntervalSince1970: 1_000)
    let entities = (0..<entityCount).map { index in
        EntityDTO(
            id: graphwideTestUUID(10_000 + index),
            createdAt: date.addingTimeInterval(TimeInterval(index)),
            graphID: graphID,
            name: "Entity \(index)",
            notes: "",
            iconSymbolName: nil,
            imageData: nil
        )
    }
    let file = GraphExportFileV1(
        exportedAt: date,
        counts: CountsDTO(graphs: 1, entities: entityCount),
        graph: GraphDTO(id: graphID, createdAt: date, name: "Import"),
        entities: entities,
        attributes: [],
        detailFieldDefinitions: [],
        detailFieldValues: [],
        links: []
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("BrainMesh-PR05C-\(UUID().uuidString).bmgraph")
    try GraphTransferCodec.encode(file).write(to: url, options: [.atomic])
    return url
}

private func graphwideTestUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
