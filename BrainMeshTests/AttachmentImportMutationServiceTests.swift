import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct AttachmentImportMutationServiceTests {

    @Test
    func preparedImportPersistsOwnerGraphContentKindAndKeepsCache() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(
            name: "Graph",
            id: attachmentImportMutationUUID(1)
        )
        let owner = fixtures.makeEntity(
            name: "Owner",
            in: graph,
            id: attachmentImportMutationUUID(2)
        )
        try fixtures.save()

        let attachmentID = attachmentImportMutationUUID(3)
        let data = Data([1, 2, 3, 4])
        let localPath = try AttachmentStore.writeToCache(
            data: data,
            attachmentID: attachmentID,
            fileExtension: "jpg"
        )
        defer { AttachmentStore.delete(localPath: localPath) }

        let prepared = PreparedAttachmentImport(
            id: attachmentID,
            title: "Gallery image",
            originalFilename: "gallery.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            byteCount: data.count,
            inferredKind: .galleryImage,
            localPath: localPath,
            fileData: data
        )
        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(publisher: publisher)

        let attachment = try await AttachmentImportMutationService.insertPrepared(
            prepared,
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: graph.id,
            in: store.context,
            committer: committer
        )

        #expect(attachment.id == attachmentID)
        #expect(attachment.ownerKind == .entity)
        #expect(attachment.ownerID == owner.id)
        #expect(attachment.graphID == graph.id)
        #expect(attachment.contentKind == .galleryImage)
        #expect(attachment.fileData == data)
        #expect(attachment.localPath == localPath)
        #expect(AttachmentStore.fileExists(localPath: localPath))

        let fetched = try #require(
            store.context.fetch(
                FetchDescriptor<MetaAttachment>(
                    predicate: #Predicate { candidate in
                        candidate.id == attachmentID
                    }
                )
            ).first
        )
        #expect(fetched.ownerKind == .entity)
        #expect(fetched.ownerID == owner.id)
        #expect(fetched.graphID == graph.id)
        #expect(fetched.contentKind == .galleryImage)

        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.flatMap(\.events).map(\.kind) == [.attachmentCreated])
        #expect(
            batches.flatMap(\.events).flatMap(\.references) == [
                .attachment(
                    id: attachmentID,
                    owner: NodeRefKey(kind: .entity, id: owner.id)
                )
            ]
        )
        #expect(batches.allSatisfy { $0.graphID == graph.id })
    }

    @Test
    func entityAndAttributeOwnersRemainDistinct() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(
            name: "Graph",
            id: attachmentImportMutationUUID(10)
        )
        let entity = fixtures.makeEntity(
            name: "Entity",
            in: graph,
            id: attachmentImportMutationUUID(11)
        )
        let attribute = fixtures.makeAttribute(
            name: "Attribute",
            owner: entity,
            id: attachmentImportMutationUUID(12)
        )
        try fixtures.save()

        let entityPrepared = makePreparedAttachmentImport(
            id: attachmentImportMutationUUID(13),
            localPath: "entity-prepared.bin"
        )
        let attributePrepared = makePreparedAttachmentImport(
            id: attachmentImportMutationUUID(14),
            localPath: "attribute-prepared.bin"
        )
        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(publisher: publisher)

        let entityAttachment = try await AttachmentImportMutationService.insertPrepared(
            entityPrepared,
            ownerKind: .entity,
            ownerID: entity.id,
            graphID: graph.id,
            in: store.context,
            committer: committer
        )
        let attributeAttachment = try await AttachmentImportMutationService.insertPrepared(
            attributePrepared,
            ownerKind: .attribute,
            ownerID: attribute.id,
            graphID: graph.id,
            in: store.context,
            committer: committer
        )

        #expect(entityAttachment.ownerKind == .entity)
        #expect(entityAttachment.ownerID == entity.id)
        #expect(attributeAttachment.ownerKind == .attribute)
        #expect(attributeAttachment.ownerID == attribute.id)

        let batches = await publisher.recordedBatches
        let references = batches
            .flatMap(\.events)
            .flatMap(\.references)
        #expect(
            references == [
                .attachment(
                    id: entityPrepared.id,
                    owner: NodeRefKey(kind: .entity, id: entity.id)
                ),
                .attachment(
                    id: attributePrepared.id,
                    owner: NodeRefKey(kind: .attribute, id: attribute.id)
                )
            ]
        )
    }

    @Test
    func persistenceFailureRemovesPreparedCacheAndPublishesNoEvent() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = attachmentImportMutationUUID(20)
        let ownerID = attachmentImportMutationUUID(21)
        let attachmentID = attachmentImportMutationUUID(22)
        let data = Data([8, 9])
        let localPath = try AttachmentStore.writeToCache(
            data: data,
            attachmentID: attachmentID,
            fileExtension: "pdf"
        )
        defer { AttachmentStore.delete(localPath: localPath) }
        #expect(AttachmentStore.fileExists(localPath: localPath))

        let prepared = PreparedAttachmentImport(
            id: attachmentID,
            title: "Prepared",
            originalFilename: "prepared.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: data.count,
            inferredKind: .file,
            localPath: localPath,
            fileData: data
        )
        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                throw GraphMutationServiceTestError.saveFailed
            }
        )

        await #expect(throws: GraphMutationServiceTestError.saveFailed) {
            _ = try await AttachmentImportMutationService.insertPrepared(
                prepared,
                ownerKind: .attribute,
                ownerID: ownerID,
                graphID: graphID,
                in: store.context,
                committer: committer
            )
        }

        #expect(AttachmentStore.fileExists(localPath: localPath) == false)
        #expect(await publisher.recordedBatches.isEmpty)

        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { candidate in
                candidate.id == attachmentID
            }
        )
        #expect(try store.context.fetchCount(descriptor) == 0)
    }
}

private func makePreparedAttachmentImport(
    id: UUID,
    localPath: String
) -> PreparedAttachmentImport {
    let data = Data([5, 6, 7])
    return PreparedAttachmentImport(
        id: id,
        title: "Prepared",
        originalFilename: "prepared.bin",
        contentTypeIdentifier: "application/octet-stream",
        fileExtension: "bin",
        byteCount: data.count,
        inferredKind: .file,
        localPath: localPath,
        fileData: data
    )
}

private func attachmentImportMutationUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "10000000-0000-0000-0000-\(suffix)")!
}
