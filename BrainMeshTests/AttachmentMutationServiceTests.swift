import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct AttachmentMutationServiceTests {
    @Test
    func createUpdateAndDeletePublishTechnicalAttachmentBatches() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: attachmentUUID(1))
        let owner = fixtures.makeEntity(
            name: "Owner",
            in: graph,
            id: attachmentUUID(2)
        )
        try fixtures.save()

        let attachment = MetaAttachment(
            id: attachmentUUID(3),
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: graph.id,
            contentKind: .galleryImage,
            title: "Private title",
            originalFilename: "private-name.jpg",
            contentTypeIdentifier: "image/jpeg",
            fileExtension: "jpg",
            byteCount: 4,
            fileData: Data([1, 2, 3, 4]),
            localPath: nil
        )
        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(publisher: publisher)

        let didInsert = try await AttachmentMutationService.insert(
            attachment,
            in: store.context,
            committer: committer
        )
        #expect(didInsert)

        attachment.title = "Changed private title"
        attachment.fileData = Data([5, 6, 7])
        attachment.byteCount = 3
        let didUpdate = try await AttachmentMutationService.commitUpdate(
            attachment,
            in: store.context,
            committer: committer
        )
        #expect(didUpdate)

        var deletedCacheReferences: [AttachmentCleanup.CacheReference] = []
        let didDelete = try await AttachmentMutationService.delete(
            attachment,
            in: store.context,
            committer: committer,
            cacheFileDeletion: { references in
                deletedCacheReferences = references
            }
        )
        #expect(didDelete)

        let batches = await publisher.recordedBatches
        #expect(batches.count == 3)
        #expect(
            batches.flatMap(\.events).map(\.kind) == [
                .attachmentCreated,
                .attachmentUpdated,
                .attachmentDeleted
            ]
        )
        let expectedReference = GraphMutationReference.attachment(
            id: attachment.id,
            owner: NodeRefKey(kind: .entity, id: owner.id)
        )
        #expect(
            batches.flatMap(\.events).map(\.references) == [
                [expectedReference],
                [expectedReference],
                [expectedReference]
            ]
        )
        #expect(batches.allSatisfy { $0.graphID == graph.id })
        #expect(batches.allSatisfy { attachmentBatchContainsUserPayload($0) == false })
        #expect(
            deletedCacheReferences
                == [
                    AttachmentCleanup.CacheReference(
                        attachmentID: attachment.id,
                        localPath: nil,
                        fileExtension: "jpg"
                    )
                ]
        )

        let attachmentID = attachment.id
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { candidate in
                candidate.id == attachmentID
            }
        )
        #expect(try store.context.fetchCount(descriptor) == 0)
    }

    @Test
    func insertSaveFailurePublishesNothingAndRemovesPreparedOrphanFiles() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = attachmentUUID(100)
        let ownerID = attachmentUUID(101)
        let attachment = MetaAttachment(
            id: attachmentUUID(102),
            ownerKind: .attribute,
            ownerID: ownerID,
            graphID: graphID,
            contentKind: .file,
            title: "Sensitive",
            originalFilename: "secret.pdf",
            contentTypeIdentifier: "application/pdf",
            fileExtension: "pdf",
            byteCount: 2,
            fileData: Data([1, 2]),
            localPath: "prepared.pdf"
        )
        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                throw GraphMutationServiceTestError.saveFailed
            }
        )
        var cleanedReferences: [AttachmentCleanup.CacheReference] = []

        await #expect(throws: GraphMutationServiceTestError.saveFailed) {
            _ = try await AttachmentMutationService.insert(
                attachment,
                in: store.context,
                committer: committer,
                orphanFileCleanup: { references in
                    cleanedReferences = references
                }
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(
            cleanedReferences
                == [
                    AttachmentCleanup.CacheReference(
                        attachmentID: attachment.id,
                        localPath: "prepared.pdf",
                        fileExtension: "pdf"
                    )
                ]
        )
        let attachmentID = attachment.id
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { candidate in
                candidate.id == attachmentID
            }
        )
        #expect(try store.context.fetchCount(descriptor) == 0)
    }

    @Test
    func deleteSaveFailurePublishesNothingAndKeepsExistingCacheFiles() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: attachmentUUID(200))
        let owner = fixtures.makeEntity(
            name: "Owner",
            in: graph,
            id: attachmentUUID(201)
        )
        let attachment = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Private title",
            originalFilename: "private.bin",
            fileExtension: "bin",
            fileData: Data([9]),
            localPath: "existing.bin",
            id: attachmentUUID(202)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                throw GraphMutationServiceTestError.saveFailed
            }
        )
        var didDeleteCacheFiles = false

        await #expect(throws: GraphMutationServiceTestError.saveFailed) {
            _ = try await AttachmentMutationService.delete(
                attachment,
                in: store.context,
                committer: committer,
                cacheFileDeletion: { _ in
                    didDeleteCacheFiles = true
                }
            )
        }

        #expect(await publisher.recordedBatches.isEmpty)
        #expect(didDeleteCacheFiles == false)
        let attachmentID = attachment.id
        let descriptor = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { candidate in
                candidate.id == attachmentID
            }
        )
        #expect(try store.context.fetchCount(descriptor) == 1)
    }

    @Test
    func previewCacheRehydrationDoesNotMutateModelOrPublishDomainEvent() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: attachmentUUID(300))
        let owner = fixtures.makeEntity(
            name: "Owner",
            in: graph,
            id: attachmentUUID(301)
        )
        let attachment = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Private title",
            originalFilename: "private.jpg",
            fileExtension: "jpg",
            fileData: Data([1, 2, 3]),
            localPath: nil,
            id: attachmentUUID(302)
        )
        try fixtures.save()

        let deterministicPath = AttachmentStore.makeLocalFilename(
            attachmentID: attachment.id,
            fileExtension: attachment.fileExtension
        )
        AttachmentStore.delete(localPath: deterministicPath)
        defer { AttachmentStore.delete(localPath: deterministicPath) }

        let previewURL = try #require(
            AttachmentStore.ensurePreviewURL(for: attachment)
        )

        #expect(FileManager.default.fileExists(atPath: previewURL.path))
        #expect(attachment.localPath == nil)
        #expect(store.context.hasChanges == false)
    }

    @Test
    func emptyAttachmentPlansAreNoOps() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(publisher: publisher)

        let didInsert = try await AttachmentMutationService.insert(
            [],
            in: store.context,
            committer: committer
        )
        let didUpdate = try await AttachmentMutationService.commitUpdates(
            [],
            in: store.context,
            committer: committer
        )
        let didDelete = try await AttachmentMutationService.delete(
            [],
            in: store.context,
            committer: committer
        )

        #expect(didInsert == false)
        #expect(didUpdate == false)
        #expect(didDelete == false)
        #expect(await publisher.recordedBatches.isEmpty)
        #expect(store.context.hasChanges == false)
    }
}

private func attachmentUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}

private func attachmentBatchContainsUserPayload(_ value: Any) -> Bool {
    if value is String || value is Data {
        return true
    }
    return Mirror(reflecting: value).children.contains { child in
        attachmentBatchContainsUserPayload(child.value)
    }
}
