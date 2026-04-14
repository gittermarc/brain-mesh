import Foundation
import SwiftData
import Testing
@testable import BrainMesh

struct NodeMediaPreviewLoaderTests {

    @Test
    func loadSnapshot_scopesToGraphAndIncludesLegacyFallbackWithoutCrossGraphLeakage() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let owner = fixtures.makeEntity(name: "Atlas", in: primaryGraph)

        let scopedGallery = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Scoped Gallery",
            originalFilename: "scoped-gallery.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x01])
        )
        scopedGallery.createdAt = Date(timeIntervalSince1970: 100)

        let scopedFile = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Scoped File",
            originalFilename: "scoped.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x02])
        )
        scopedFile.createdAt = Date(timeIntervalSince1970: 200)

        let legacyGallery = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: nil,
            contentKind: .galleryImage,
            title: "Legacy Gallery",
            originalFilename: "legacy-gallery.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            byteCount: 1,
            fileData: Data([0x03]),
            localPath: nil
        )
        legacyGallery.createdAt = Date(timeIntervalSince1970: 300)
        testStore.context.insert(legacyGallery)

        let legacyVideo = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: nil,
            contentKind: .video,
            title: "Legacy Video",
            originalFilename: "legacy.mov",
            contentTypeIdentifier: "public.movie",
            fileExtension: "mov",
            byteCount: 1,
            fileData: Data([0x04]),
            localPath: nil
        )
        legacyVideo.createdAt = Date(timeIntervalSince1970: 400)
        testStore.context.insert(legacyVideo)

        let crossGraphAttachment = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: secondaryGraph.id,
            contentKind: .file,
            title: "Cross Graph",
            originalFilename: "cross.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 1,
            fileData: Data([0x05]),
            localPath: nil
        )
        crossGraphAttachment.createdAt = Date(timeIntervalSince1970: 500)
        testStore.context.insert(crossGraphAttachment)

        try fixtures.save()

        let loader = NodeMediaPreviewLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: primaryGraph.id,
            galleryLimit: 6,
            attachmentLimit: 3
        )

        #expect(snapshot.galleryCount == 2)
        #expect(snapshot.attachmentCount == 2)
        #expect(snapshot.galleryPreviewIDs == [legacyGallery.id, scopedGallery.id])
        #expect(snapshot.attachmentPreviewIDs == [legacyVideo.id, scopedFile.id])
        #expect(snapshot.galleryPreviewIDs.contains(crossGraphAttachment.id) == false)
        #expect(snapshot.attachmentPreviewIDs.contains(crossGraphAttachment.id) == false)
    }


    @Test
    func loadSnapshot_mergesScopedAndLegacyPreviewRecordsBeforeApplyingLimit() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let owner = fixtures.makeEntity(name: "Atlas", in: primaryGraph)

        let scopedOldest = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Scoped Oldest",
            originalFilename: "scoped-oldest.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x11])
        )
        scopedOldest.createdAt = Date(timeIntervalSince1970: 100)

        let legacySecondOldest = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: nil,
            contentKind: .file,
            title: "Legacy Second Oldest",
            originalFilename: "legacy-second-oldest.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 1,
            fileData: Data([0x12]),
            localPath: nil
        )
        legacySecondOldest.createdAt = Date(timeIntervalSince1970: 200)
        testStore.context.insert(legacySecondOldest)

        let scopedMiddle = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .video,
            title: "Scoped Middle",
            originalFilename: "scoped-middle.mov",
            contentTypeIdentifier: "public.movie",
            fileExtension: "mov",
            fileData: Data([0x13])
        )
        scopedMiddle.createdAt = Date(timeIntervalSince1970: 300)

        let legacySecondNewest = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: nil,
            contentKind: .file,
            title: "Legacy Second Newest",
            originalFilename: "legacy-second-newest.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 1,
            fileData: Data([0x14]),
            localPath: nil
        )
        legacySecondNewest.createdAt = Date(timeIntervalSince1970: 400)
        testStore.context.insert(legacySecondNewest)

        let scopedNewest = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Scoped Newest",
            originalFilename: "scoped-newest.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x15])
        )
        scopedNewest.createdAt = Date(timeIntervalSince1970: 500)

        let legacyNewest = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: nil,
            contentKind: .video,
            title: "Legacy Newest",
            originalFilename: "legacy-newest.mov",
            contentTypeIdentifier: "public.movie",
            fileExtension: "mov",
            byteCount: 1,
            fileData: Data([0x16]),
            localPath: nil
        )
        legacyNewest.createdAt = Date(timeIntervalSince1970: 600)
        testStore.context.insert(legacyNewest)

        let crossGraphNewest = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: secondaryGraph.id,
            contentKind: .file,
            title: "Cross Graph Newest",
            originalFilename: "cross-graph-newest.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 1,
            fileData: Data([0x17]),
            localPath: nil
        )
        crossGraphNewest.createdAt = Date(timeIntervalSince1970: 700)
        testStore.context.insert(crossGraphNewest)

        try fixtures.save()

        let loader = NodeMediaPreviewLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: primaryGraph.id,
            galleryLimit: 0,
            attachmentLimit: 4
        )

        #expect(snapshot.galleryCount == 0)
        #expect(snapshot.attachmentCount == 6)
        #expect(snapshot.attachmentPreviewIDs == [
            legacyNewest.id,
            scopedNewest.id,
            legacySecondNewest.id,
            scopedMiddle.id
        ])
        #expect(snapshot.attachmentPreviewIDs.contains(crossGraphNewest.id) == false)
    }

    @Test
    func loadSnapshot_respectsPreviewLimitsAndKeepsNewestItems() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)

        var expectedGalleryIDs: [UUID] = []
        for index in 0..<8 {
            let attachment = fixtures.makeAttachment(
                owner: .entity(owner),
                contentKind: .galleryImage,
                title: "Gallery \(index)",
                originalFilename: "gallery-\(index).jpg",
                contentTypeIdentifier: "public.jpeg",
                fileExtension: "jpg",
                fileData: Data([UInt8(index)])
            )
            attachment.createdAt = Date(timeIntervalSince1970: TimeInterval(100 + index))
            expectedGalleryIDs.append(attachment.id)
        }

        var expectedAttachmentIDs: [UUID] = []
        for index in 0..<5 {
            let attachment = fixtures.makeAttachment(
                owner: .entity(owner),
                contentKind: index.isMultiple(of: 2) ? .file : .video,
                title: "Attachment \(index)",
                originalFilename: "attachment-\(index).bin",
                contentTypeIdentifier: index.isMultiple(of: 2) ? "com.adobe.pdf" : "public.movie",
                fileExtension: index.isMultiple(of: 2) ? "pdf" : "mov",
                fileData: Data([UInt8(20 + index)])
            )
            attachment.createdAt = Date(timeIntervalSince1970: TimeInterval(200 + index))
            expectedAttachmentIDs.append(attachment.id)
        }

        try fixtures.save()

        let loader = NodeMediaPreviewLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: graph.id,
            galleryLimit: 6,
            attachmentLimit: 3
        )

        #expect(snapshot.galleryCount == 8)
        #expect(snapshot.attachmentCount == 5)
        #expect(snapshot.galleryPreviewIDs == Array(expectedGalleryIDs.reversed().prefix(6)))
        #expect(snapshot.attachmentPreviewIDs == Array(expectedAttachmentIDs.reversed().prefix(3)))
    }

    @Test
    func loadSnapshot_separatesGalleryAndAttachmentsForCounts() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)

        _ = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Gallery",
            originalFilename: "gallery.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x01])
        )
        _ = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Document",
            originalFilename: "doc.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x02])
        )
        _ = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .video,
            title: "Video",
            originalFilename: "clip.mov",
            contentTypeIdentifier: "public.movie",
            fileExtension: "mov",
            fileData: Data([0x03])
        )
        try fixtures.save()

        let loader = NodeMediaPreviewLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: graph.id,
            galleryLimit: 6,
            attachmentLimit: 3
        )

        #expect(snapshot.galleryCount == 1)
        #expect(snapshot.attachmentCount == 2)
    }

    @Test
    func loadSnapshot_withNilGraphIDUsesAllOwnerAttachments() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graphA = fixtures.makeGraph(name: "A")
        let graphB = fixtures.makeGraph(name: "B")
        let owner = fixtures.makeEntity(name: "Atlas", in: graphA)

        let first = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Graph A",
            originalFilename: "a.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x01])
        )
        first.createdAt = Date(timeIntervalSince1970: 100)

        let second = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: graphB.id,
            contentKind: .file,
            title: "Graph B",
            originalFilename: "b.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 1,
            fileData: Data([0x02]),
            localPath: nil
        )
        second.createdAt = Date(timeIntervalSince1970: 200)
        testStore.context.insert(second)

        let third = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: nil,
            contentKind: .file,
            title: "Legacy",
            originalFilename: "legacy.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 1,
            fileData: Data([0x03]),
            localPath: nil
        )
        third.createdAt = Date(timeIntervalSince1970: 300)
        testStore.context.insert(third)

        try fixtures.save()

        let loader = NodeMediaPreviewLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: nil,
            galleryLimit: 6,
            attachmentLimit: 3
        )

        #expect(snapshot.galleryCount == 0)
        #expect(snapshot.attachmentCount == 3)
        #expect(snapshot.attachmentPreviewIDs == [third.id, second.id, first.id])
    }

    @Test
    func loadSnapshot_keepsLegacyRowsUntouchedWhileStillReturningThem() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)

        let legacyAttachment = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: nil,
            contentKind: .file,
            title: "Legacy",
            originalFilename: "legacy.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 1,
            fileData: Data([0x01]),
            localPath: nil
        )
        legacyAttachment.createdAt = Date(timeIntervalSince1970: 100)
        testStore.context.insert(legacyAttachment)
        try fixtures.save()

        let loader = NodeMediaPreviewLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: graph.id,
            galleryLimit: 6,
            attachmentLimit: 3
        )

        let verificationContext = BrainMeshTestContainer.makeContext(for: testStore.container)
        let storedLegacy = try #require(
            try verificationContext
                .fetch(FetchDescriptor<MetaAttachment>())
                .first(where: { $0.id == legacyAttachment.id })
        )

        #expect(snapshot.attachmentCount == 1)
        #expect(snapshot.attachmentPreviewIDs == [legacyAttachment.id])
        #expect(storedLegacy.graphID == nil)
    }
}
