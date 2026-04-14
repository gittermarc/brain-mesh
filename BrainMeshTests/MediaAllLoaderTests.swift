import Foundation
import Testing
@testable import BrainMesh
import SwiftData

struct MediaAllLoaderTests {

    @Test
    func fetchCounts_separatesGalleryImagesAndAttachments() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)

        let _ = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Document",
            originalFilename: "doc.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x01])
        )
        let _ = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .video,
            title: "Clip",
            originalFilename: "clip.mov",
            contentTypeIdentifier: "public.movie",
            fileExtension: "mov",
            fileData: Data([0x02])
        )
        let _ = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Gallery",
            originalFilename: "gallery.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x03])
        )
        try fixtures.save()

        let loader = MediaAllLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))
        let counts = await loader.fetchCounts(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: graph.id
        )

        #expect(counts.attachments == 2)
        #expect(counts.gallery == 1)
    }

    @Test
    func fetchAttachmentPage_excludesGalleryImages_andSortsNewestFirst() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)

        let oldest = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Oldest",
            originalFilename: "old.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x01])
        )
        oldest.createdAt = Date(timeIntervalSince1970: 100)

        let middle = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Middle",
            originalFilename: "middle.txt",
            contentTypeIdentifier: "public.plain-text",
            fileExtension: "txt",
            fileData: Data([0x02])
        )
        middle.createdAt = Date(timeIntervalSince1970: 200)

        let newest = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .video,
            title: "Newest",
            originalFilename: "new.mov",
            contentTypeIdentifier: "public.movie",
            fileExtension: "mov",
            fileData: Data([0x03])
        )
        newest.createdAt = Date(timeIntervalSince1970: 300)

        let gallery = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Gallery",
            originalFilename: "gallery.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x04])
        )
        gallery.createdAt = Date(timeIntervalSince1970: 400)

        try fixtures.save()

        let loader = MediaAllLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))
        let page = await loader.fetchAttachmentPage(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: graph.id,
            offset: 0,
            limit: 2
        )

        let pageTitles = page.map { $0.title }
        let containsGalleryImage = page.contains { item in
            item.contentKind == .galleryImage
        }

        #expect(pageTitles == ["Newest", "Middle"])
        #expect(containsGalleryImage == false)
    }

    @Test
    func fetchAttachmentPage_respectsOffset_andGraphScope() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let owner = fixtures.makeEntity(name: "Atlas", in: primaryGraph)

        let first = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "First",
            originalFilename: "first.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x01])
        )
        first.createdAt = Date(timeIntervalSince1970: 100)

        let second = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Second",
            originalFilename: "second.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x02])
        )
        second.createdAt = Date(timeIntervalSince1970: 200)

        let crossGraph = MetaAttachment(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: secondaryGraph.id,
            contentKind: .file,
            title: "CrossGraph",
            originalFilename: "cross.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 3,
            fileData: Data([0x03]),
            localPath: nil
        )
        crossGraph.createdAt = Date(timeIntervalSince1970: 300)
        testStore.context.insert(crossGraph)

        try fixtures.save()

        let loader = MediaAllLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))
        let page = await loader.fetchAttachmentPage(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: primaryGraph.id,
            offset: 1,
            limit: 1
        )

        let pageTitles = page.map { $0.title }
        #expect(pageTitles == ["First"])
    }


    @Test
    func fetchGalleryPage_includesOnlyGalleryImages_andRespectsOffset() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Atlas", in: graph)

        let oldest = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Oldest Gallery",
            originalFilename: "oldest.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x01])
        )
        oldest.createdAt = Date(timeIntervalSince1970: 100)

        let middle = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Middle Gallery",
            originalFilename: "middle.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x02])
        )
        middle.createdAt = Date(timeIntervalSince1970: 200)

        let newest = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .galleryImage,
            title: "Newest Gallery",
            originalFilename: "newest.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            fileData: Data([0x03])
        )
        newest.createdAt = Date(timeIntervalSince1970: 300)

        let fileAttachment = fixtures.makeAttachment(
            owner: .entity(owner),
            contentKind: .file,
            title: "Document",
            originalFilename: "doc.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data([0x04])
        )
        fileAttachment.createdAt = Date(timeIntervalSince1970: 400)

        try fixtures.save()

        let loader = MediaAllLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))
        let page = await loader.fetchGalleryPage(
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: owner.id,
            graphID: graph.id,
            offset: 1,
            limit: 1
        )

        let pageTitles = page.map { $0.title }
        let containsNonGalleryItem = page.contains { item in
            item.contentKind != .galleryImage
        }

        #expect(pageTitles == ["Middle Gallery"])
        #expect(containsNonGalleryItem == false)
    }

}
