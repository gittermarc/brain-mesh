import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct GraphStatsServiceCountsTests {

    @Test
    func totalCounts_countsAcrossGraphsAndLegacyData() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)

        let graph = builder.makeGraph(name: "Work")
        let entity = builder.makeEntity(
            name: "Entity With Image",
            in: graph,
            notes: "Entity Note",
            imageData: Data([0x01])
        )
        let attribute = builder.makeAttribute(
            name: "Attribute With Image",
            owner: entity,
            notes: "Attribute Note",
            imageData: Data([0x02])
        )
        _ = builder.makeLink(
            source: .entity(entity),
            target: .attribute(attribute),
            note: "Link Note",
            graphID: graph.id
        )
        _ = builder.makeAttachment(
            owner: .entity(entity),
            title: "Doc",
            originalFilename: "doc.pdf",
            contentTypeIdentifier: "application/pdf",
            fileExtension: "pdf",
            byteCount: 25
        )

        let legacyEntity = builder.makeEntity(
            name: "Legacy Entity",
            notes: "Legacy Note"
        )
        _ = builder.makeAttachment(
            owner: .entity(legacyEntity),
            contentKind: .video,
            title: "Legacy Clip",
            originalFilename: "clip.mov",
            contentTypeIdentifier: "video/quicktime",
            fileExtension: "mov",
            byteCount: 75
        )

        try builder.save()

        let service = GraphStatsService(context: store.context)
        let counts = try service.totalCounts()

        #expect(counts == GraphCounts(
            entities: 2,
            attributes: 1,
            links: 1,
            notes: 4,
            images: 2,
            attachments: 2,
            attachmentBytes: 100
        ))
    }

    @Test
    func countsForGraph_returnsExactGraphScopedCounts() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)

        let graph = builder.makeGraph(name: "Scope")
        let otherGraph = builder.makeGraph(name: "Other")

        let entity = builder.makeEntity(
            name: "Scoped Entity",
            in: graph,
            notes: "Entity Note",
            imageData: Data([0x01])
        )
        let attribute = builder.makeAttribute(
            name: "Scoped Attribute",
            owner: entity,
            notes: "Attribute Note"
        )
        _ = builder.makeLink(
            source: .entity(entity),
            target: .attribute(attribute),
            note: "Scoped Link Note",
            graphID: graph.id
        )
        _ = builder.makeAttachment(
            owner: .attribute(attribute),
            contentKind: .file,
            title: "Scoped Doc",
            originalFilename: "scoped.pdf",
            contentTypeIdentifier: "application/pdf",
            fileExtension: "pdf",
            byteCount: 42
        )

        let otherEntity = builder.makeEntity(name: "Other Entity", in: otherGraph, notes: "Other Note")
        _ = builder.makeAttachment(
            owner: .entity(otherEntity),
            title: "Other Doc",
            originalFilename: "other.pdf",
            contentTypeIdentifier: "application/pdf",
            fileExtension: "pdf",
            byteCount: 999
        )

        try builder.save()

        let service = GraphStatsService(context: store.context)
        let counts = try service.counts(for: graph.id)

        #expect(counts == GraphCounts(
            entities: 1,
            attributes: 1,
            links: 1,
            notes: 3,
            images: 1,
            attachments: 1,
            attachmentBytes: 42
        ))
    }

    @Test
    func countsForNil_returnsLegacyCountsOnly() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)

        let graph = builder.makeGraph(name: "Scoped")
        let scopedEntity = builder.makeEntity(name: "Scoped Entity", in: graph, notes: "Scoped Note")
        _ = builder.makeAttachment(
            owner: .entity(scopedEntity),
            title: "Scoped File",
            originalFilename: "scoped.bin",
            contentTypeIdentifier: "application/octet-stream",
            fileExtension: "bin",
            byteCount: 88
        )

        let legacyEntity = builder.makeEntity(
            name: "Legacy Entity",
            notes: "Legacy Entity Note",
            imageData: Data([0x01])
        )
        let legacyAttribute = builder.makeAttribute(
            name: "Legacy Attribute",
            owner: legacyEntity,
            notes: "Legacy Attribute Note"
        )
        _ = builder.makeLink(
            source: .entity(legacyEntity),
            target: .attribute(legacyAttribute),
            note: "Legacy Link Note",
            graphID: nil
        )
        _ = builder.makeAttachment(
            owner: .attribute(legacyAttribute),
            contentKind: .galleryImage,
            title: "Legacy Gallery",
            originalFilename: "legacy.jpg",
            contentTypeIdentifier: "image/jpeg",
            fileExtension: "jpg",
            byteCount: 12
        )

        try builder.save()

        let service = GraphStatsService(context: store.context)
        let counts = try service.counts(for: nil)

        #expect(counts == GraphCounts(
            entities: 1,
            attributes: 1,
            links: 1,
            notes: 3,
            images: 1,
            attachments: 1,
            attachmentBytes: 12
        ))
    }

    @Test
    func repeatedCountQueries_reusePerServiceCache() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)

        let graph = builder.makeGraph(name: "Cache")
        let entity = builder.makeEntity(name: "Cache Entity", in: graph, notes: "Entity Note")
        _ = builder.makeAttachment(
            owner: .entity(entity),
            title: "Cache File",
            originalFilename: "cache.txt",
            contentTypeIdentifier: "text/plain",
            fileExtension: "txt",
            byteCount: 10
        )
        try builder.save()

        let service = GraphStatsService(context: store.context)

        let firstGraphCounts = try service.counts(for: graph.id)
        let secondGraphCounts = try service.counts(for: graph.id)
        let firstTotalCounts = try service.totalCounts()
        let secondTotalCounts = try service.totalCounts()
        let firstLegacyCounts = try service.counts(for: nil)
        let secondLegacyCounts = try service.counts(for: nil)

        #expect(firstGraphCounts == secondGraphCounts)
        #expect(firstTotalCounts == secondTotalCounts)
        #expect(firstLegacyCounts == secondLegacyCounts)
        #expect(service.countsCacheEntryCountForTesting() == 3)
    }
}
