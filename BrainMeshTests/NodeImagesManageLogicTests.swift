import Foundation
import SwiftData
import Testing
@testable import BrainMesh

struct NodeImagesManageListStateTests {

    @Test
    func markInitialLoadStarted_onlyReturnsTrueOnce() {
        var state = NodeImagesManageListState()

        let firstResult = state.markInitialLoadStarted()
        let secondResult = state.markInitialLoadStarted()

        #expect(firstResult)
        #expect(state.didLoadOnce)
        #expect(secondResult == false)
    }

    @Test
    func beginRefresh_resetsImagesPagingAndLoadingState() {
        var state = NodeImagesManageListState(
            images: [makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 100))],
            totalCount: 9,
            isLoading: false,
            hasMore: false,
            offset: 40,
            didLoadOnce: true
        )

        state.beginRefresh(totalCount: 3)

        #expect(state.images.isEmpty)
        #expect(state.totalCount == 3)
        #expect(state.isLoading)
        #expect(state.hasMore)
        #expect(state.offset == 0)
        #expect(state.didLoadOnce)
    }

    @Test
    func applyPage_dedupesAndAppendsWhileTrackingHasMore() {
        let existing = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), title: "Existing")
        let incoming = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 200), title: "Incoming")
        var state = NodeImagesManageListState(
            images: [existing],
            totalCount: 2,
            isLoading: true,
            hasMore: true,
            offset: 0,
            didLoadOnce: true
        )

        state.applyPage([existing, incoming])

        #expect(state.images.map(\.id) == [existing.id, incoming.id])
        #expect(state.offset == 2)
        #expect(state.hasMore == false)
        #expect(state.isLoading == false)
    }


    @Test
    func removeImage_preservesHasMoreWhenAdditionalItemsRemainOffscreen() {
        let first = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), title: "First")
        let second = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 200), title: "Second")
        var state = NodeImagesManageListState(
            images: [first, second],
            totalCount: 3,
            isLoading: false,
            hasMore: true,
            offset: 2,
            didLoadOnce: true
        )

        state.removeImage(attachmentID: first.id)

        #expect(state.images.map(\.id) == [second.id])
        #expect(state.totalCount == 2)
        #expect(state.hasMore)
    }

    @Test
    func removeImage_updatesTotalCountAndHasMore() {
        let first = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), title: "First")
        let second = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 200), title: "Second")
        var state = NodeImagesManageListState(
            images: [first, second],
            totalCount: 2,
            isLoading: false,
            hasMore: false,
            offset: 2,
            didLoadOnce: true
        )

        state.removeImage(attachmentID: first.id)

        #expect(state.images.map(\.id) == [second.id])
        #expect(state.totalCount == 1)
        #expect(state.hasMore == false)
    }
}

@MainActor
struct NodeImagesManageAttachmentResolverTests {

    @Test
    func resolveImageAttachment_returnsExactIDMatchWhenPresent() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)
        let attachment = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Gallery",
            originalFilename: "gallery.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x01])
        )
        attachment.createdAt = Date(timeIntervalSince1970: 100)
        try fixtures.save()

        let item = makeItem(from: attachment)
        let resolved = NodeImagesManageAttachmentResolver.resolveImageAttachment(
            in: testStore.context,
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: graph.id,
            item: item
        )

        #expect(resolved?.id == attachment.id)
    }

    @Test
    func resolveImageAttachment_fallsBackToOwnerScopedMetadataMatchWhenIDIsStale() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)
        let attachment = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Gallery",
            originalFilename: "gallery.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x01])
        )
        attachment.createdAt = Date(timeIntervalSince1970: 200)
        attachment.localPath = "gallery-path"
        try fixtures.save()

        let staleItem = AttachmentListItem(
            id: UUID(),
            createdAt: attachment.createdAt,
            graphID: attachment.graphID,
            ownerKindRaw: attachment.ownerKindRaw,
            ownerID: attachment.ownerID,
            contentKindRaw: attachment.contentKindRaw,
            title: attachment.title,
            originalFilename: attachment.originalFilename,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            byteCount: attachment.byteCount,
            localPath: attachment.localPath
        )

        let resolved = NodeImagesManageAttachmentResolver.resolveImageAttachment(
            in: testStore.context,
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: graph.id,
            item: staleItem
        )

        #expect(resolved?.id == attachment.id)
    }

    private func makeItem(from attachment: MetaAttachment) -> AttachmentListItem {
        AttachmentListItem(
            id: attachment.id,
            createdAt: attachment.createdAt,
            graphID: attachment.graphID,
            ownerKindRaw: attachment.ownerKindRaw,
            ownerID: attachment.ownerID,
            contentKindRaw: attachment.contentKindRaw,
            title: attachment.title,
            originalFilename: attachment.originalFilename,
            contentTypeIdentifier: attachment.contentTypeIdentifier,
            fileExtension: attachment.fileExtension,
            byteCount: attachment.byteCount,
            localPath: attachment.localPath
        )
    }
}

private func makeItem(
    id: UUID,
    createdAt: Date,
    title: String = "Image",
    originalFilename: String = "image.jpg",
    contentTypeIdentifier: String = "public.jpeg",
    fileExtension: String = "jpg",
    byteCount: Int = 1,
    localPath: String? = nil
) -> AttachmentListItem {
    AttachmentListItem(
        id: id,
        createdAt: createdAt,
        graphID: UUID(),
        ownerKindRaw: NodeKind.entity.rawValue,
        ownerID: UUID(),
        contentKindRaw: AttachmentContentKind.galleryImage.rawValue,
        title: title,
        originalFilename: originalFilename,
        contentTypeIdentifier: contentTypeIdentifier,
        fileExtension: fileExtension,
        byteCount: byteCount,
        localPath: localPath
    )
}
