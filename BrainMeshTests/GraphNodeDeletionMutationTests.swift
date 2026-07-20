import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct GraphNodeDeletionMutationTests {

    @Test
    func entityCleanupPublishesOneStableDependencyOrderedBatch() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: deletionUUID(1))
        let target = fixtures.makeEntity(name: "Target", in: graph, id: deletionUUID(2))
        let child = fixtures.makeAttribute(name: "Child", owner: target, id: deletionUUID(3))
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph, id: deletionUUID(4))
        let field = fixtures.makeDetailField(
            owner: target,
            name: "Field",
            type: .singleLineText,
            sortIndex: 0,
            id: deletionUUID(5)
        )
        let value = fixtures.makeDetailValue(
            attribute: child,
            field: field,
            stringValue: "Private value",
            id: deletionUUID(6)
        )
        let link = fixtures.makeLink(
            source: .entity(survivor),
            target: .attribute(child),
            id: deletionUUID(7)
        )
        let entityAttachment = fixtures.makeAttachment(
            owner: .entity(target),
            id: deletionUUID(9)
        )
        let attributeAttachment = fixtures.makeAttachment(
            owner: .attribute(child),
            id: deletionUUID(8)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        var attachmentCleanupCount = 0
        var headerCleanupPaths: [String] = []

        _ = try await GraphNodeDeletionService.deleteEntity(
            target,
            in: store.context,
            committer: GraphMutationCommitter(publisher: publisher),
            cacheFileDeletion: { result in
                attachmentCleanupCount += result.deletedCount
            },
            headerImageDeletion: { paths in
                headerCleanupPaths = paths
            }
        )

        let batches = await publisher.recordedBatches
        let batch = try #require(batches.first)
        #expect(batches.count == 1)
        #expect(batch.graphID == graph.id)
        #expect(
            batch.events.map(\.kind) == [
                .linkDeleted,
                .detailValueDeleted,
                .detailSchemaChanged,
                .attachmentDeleted,
                .attachmentDeleted,
                .attributeDeleted,
                .entityDeleted
            ]
        )
        #expect(batch.events[0].references == [
            .link(
                id: link.id,
                source: NodeRefKey(kind: .entity, id: survivor.id),
                target: NodeRefKey(kind: .attribute, id: child.id)
            )
        ])
        #expect(batch.events[1].references == [
            .detailValue(
                id: value.id,
                ownerAttributeID: child.id,
                fieldID: field.id
            )
        ])
        #expect(batch.events[2].references == [
            .detailFieldDefinition(id: field.id, ownerEntityID: target.id)
        ])
        #expect(
            batch.events[3...4].compactMap(firstAttachmentID)
                == [attributeAttachment.id, entityAttachment.id]
        )
        #expect(batch.events[5].references == [
            .node(NodeRefKey(kind: .attribute, id: child.id))
        ])
        #expect(batch.events[6].references == [
            .node(NodeRefKey(kind: .entity, id: target.id))
        ])
        #expect(attachmentCleanupCount == 2)
        #expect(headerCleanupPaths.isEmpty)
    }

    @Test
    func attributeBatchDeletionPublishesExactlyOneBatch() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: deletionUUID(10))
        let owner = fixtures.makeEntity(name: "Owner", in: graph, id: deletionUUID(11))
        let laterAttribute = fixtures.makeAttribute(
            name: "Later",
            owner: owner,
            id: deletionUUID(13)
        )
        let earlierAttribute = fixtures.makeAttribute(
            name: "Earlier",
            owner: owner,
            id: deletionUUID(12)
        )
        try fixtures.save()
        let earlierAttributeID = earlierAttribute.id
        let laterAttributeID = laterAttribute.id

        let publisher = GraphMutationRecordingPublisher()
        let result = try await GraphNodeDeletionService.deleteAttributes(
            [laterAttribute, earlierAttribute],
            in: store.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )

        #expect(result.deletedAttributeCount == 2)
        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.first?.events.map(\.kind) == [.attributeDeleted, .attributeDeleted])
        #expect(
            batches.first?.events.compactMap(firstNodeID)
                == [earlierAttributeID, laterAttributeID]
        )
    }

    @Test
    func entityDeletionExplicitlyRemovesOrphanedDetailDefinitions() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: deletionUUID(14))
        let target = fixtures.makeEntity(name: "Target", in: graph, id: deletionUUID(15))
        let orphanedField = fixtures.makeDetailField(
            owner: target,
            name: "Orphan",
            type: .singleLineText,
            sortIndex: 0,
            id: deletionUUID(16)
        )
        try fixtures.save()

        target.removeDetailField(orphanedField)
        orphanedField.entityID = target.id
        orphanedField.graphID = graph.id
        try fixtures.save()

        let fieldID = orphanedField.id
        let entityID = target.id
        let publisher = GraphMutationRecordingPublisher()
        let result = try await GraphNodeDeletionService.deleteEntity(
            target,
            in: store.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )

        #expect(result.deletedDetailFieldCount == 1)
        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.first?.events.map(\.kind) == [.detailSchemaChanged, .entityDeleted])
        #expect(
            batches.first?.events.first?.references == [
                .detailFieldDefinition(id: fieldID, ownerEntityID: entityID)
            ]
        )

        let verificationContext = BrainMeshTestContainer.makeContext(for: store.container)
        #expect(
            try verificationContext.fetchCount(
                FetchDescriptor<MetaDetailFieldDefinition>(
                    predicate: #Predicate { definition in definition.id == fieldID }
                )
            ) == 0
        )
    }

    @Test
    func failedDeletePublishesNothingAndDoesNotDeleteLocalFiles() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: deletionUUID(20))
        let target = fixtures.makeEntity(name: "Target", in: graph, id: deletionUUID(21))
        target.imagePath = "existing-header.jpg"
        let attachment = fixtures.makeAttachment(
            owner: .entity(target),
            localPath: "existing-attachment.bin",
            id: deletionUUID(22)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in throw DeletionMutationTestError.saveFailed }
        )
        var attachmentCleanupCount = 0
        var headerCleanupCount = 0

        await #expect(throws: GraphNodeDeletionService.DeletionError.persistenceFailure) {
            _ = try await GraphNodeDeletionService.deleteEntity(
                target,
                in: store.context,
                committer: committer,
                cacheFileDeletion: { result in
                    attachmentCleanupCount += result.deletedCount
                },
                headerImageDeletion: { paths in
                    headerCleanupCount += paths.count
                }
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(attachmentCleanupCount == 0)
        #expect(headerCleanupCount == 0)

        let verificationContext = BrainMeshTestContainer.makeContext(for: store.container)
        let targetID = target.id
        let attachmentID = attachment.id
        #expect(
            try verificationContext.fetchCount(
                FetchDescriptor<MetaEntity>(
                    predicate: #Predicate { candidate in candidate.id == targetID }
                )
            ) == 1
        )
        #expect(
            try verificationContext.fetchCount(
                FetchDescriptor<MetaAttachment>(
                    predicate: #Predicate { candidate in candidate.id == attachmentID }
                )
            ) == 1
        )
    }

    private func firstNodeID(_ event: GraphMutationEvent) -> UUID? {
        guard case .node(let node) = event.references.first else { return nil }
        return node.id
    }

    private func firstAttachmentID(_ event: GraphMutationEvent) -> UUID? {
        guard case .attachment(let id, _) = event.references.first else { return nil }
        return id
    }
}

private enum DeletionMutationTestError: Error {
    case saveFailed
}

private func deletionUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
