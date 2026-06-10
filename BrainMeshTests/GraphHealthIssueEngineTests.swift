import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct GraphHealthIssueEngineTests {

    @Test
    func isolatedEntityCreatesIssue() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)
        let graph = builder.makeGraph(name: "Health")
        let isolated = builder.makeEntity(name: "Isolated", in: graph)
        try builder.save()

        let snapshot = try GraphStatsService(context: store.context).healthSnapshot(for: graph.id)
        let issue = try #require(snapshot.issues.first { $0.kind == .isolatedEntities })

        #expect(issue.count == 1)
        #expect(issue.primaryNodeID == isolated.id)
        #expect(issue.primaryNodeKindRaw == NodeKind.entity.rawValue)
        #expect(issue.affectedNodeIDs == [isolated.id])
    }

    @Test
    func entityWithoutAttributesCreatesIssue() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)
        let graph = builder.makeGraph(name: "Health")
        let entity = builder.makeEntity(name: "No Attributes", in: graph)
        try builder.save()

        let snapshot = try GraphStatsService(context: store.context).healthSnapshot(for: graph.id)
        let issue = try #require(snapshot.issues.first { $0.kind == .entitiesWithoutAttributes })

        #expect(issue.count == 1)
        #expect(issue.affectedNodeIDs == [entity.id])
    }

    @Test
    func entityWithoutDetailFieldsCreatesIssue() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)
        let graph = builder.makeGraph(name: "Health")
        let entity = builder.makeEntity(name: "No Schema", in: graph)
        _ = builder.makeAttribute(name: "Status", owner: entity)
        try builder.save()

        let snapshot = try GraphStatsService(context: store.context).healthSnapshot(for: graph.id)
        let issue = try #require(snapshot.issues.first { $0.kind == .entitiesWithoutDetailsSchema })

        #expect(issue.count == 1)
        #expect(issue.affectedNodeIDs == [entity.id])
    }

    @Test
    func largeAttachmentCreatesIssueWithOwnerInformationWithoutFileData() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)
        let graph = builder.makeGraph(name: "Health")
        let entity = builder.makeEntity(name: "Media Owner", in: graph)
        let largeByteCount = Int(GraphHealthIssueEngine.largeAttachmentByteThreshold) + 1
        let attachment = builder.makeAttachment(
            owner: .entity(entity),
            contentKind: .file,
            title: "Large PDF",
            originalFilename: "large.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: largeByteCount,
            fileData: nil
        )
        try builder.save()

        let snapshot = try GraphStatsService(context: store.context).healthSnapshot(for: graph.id)
        let issue = try #require(snapshot.issues.first { $0.kind == .largeAttachments })
        let item = try #require(issue.affectedItems.first)

        #expect(issue.count == 1)
        #expect(item.id == attachment.id)
        #expect(item.ownerKindRaw == NodeKind.entity.rawValue)
        #expect(item.ownerID == entity.id)
        #expect(item.ownerLabel == "Media Owner")
        #expect(item.byteCount == Int64(largeByteCount))
    }

    @Test
    func topHubIssueContainsNodeData() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)
        let graph = builder.makeGraph(name: "Health")
        let hub = builder.makeEntity(name: "Hub", in: graph)
        let first = builder.makeEntity(name: "First", in: graph)
        let second = builder.makeEntity(name: "Second", in: graph)
        let third = builder.makeEntity(name: "Third", in: graph)
        _ = builder.makeLink(source: .entity(hub), target: .entity(first), graphID: graph.id)
        _ = builder.makeLink(source: .entity(hub), target: .entity(second), graphID: graph.id)
        _ = builder.makeLink(source: .entity(hub), target: .entity(third), graphID: graph.id)
        try builder.save()

        let snapshot = try GraphStatsService(context: store.context).healthSnapshot(for: graph.id)
        let issue = try #require(snapshot.issues.first { $0.kind == .topHubs })
        let item = try #require(issue.affectedItems.first)

        #expect(issue.count == 1)
        #expect(item.nodeID == hub.id)
        #expect(item.nodeKindRaw == NodeKind.entity.rawValue)
        #expect(item.count == 3)
    }

    @Test
    func mediaRichNodeIssueContainsNodeData() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)
        let graph = builder.makeGraph(name: "Health")
        let entity = builder.makeEntity(name: "Media Rich", in: graph)
        _ = builder.makeAttachment(
            owner: .entity(entity),
            contentKind: .file,
            title: "First",
            originalFilename: "first.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            byteCount: 1_000
        )
        _ = builder.makeAttachment(
            owner: .entity(entity),
            contentKind: .galleryImage,
            title: "Second",
            originalFilename: "second.jpg",
            contentTypeIdentifier: "public.jpeg",
            fileExtension: "jpg",
            byteCount: 2_000
        )
        try builder.save()

        let snapshot = try GraphStatsService(context: store.context).healthSnapshot(for: graph.id)
        let issue = try #require(snapshot.issues.first { $0.kind == .mediaRichNodes })
        let item = try #require(issue.affectedItems.first)

        #expect(issue.count == 1)
        #expect(item.nodeID == entity.id)
        #expect(item.nodeKindRaw == NodeKind.entity.rawValue)
        #expect(item.count == 2)
    }

    @Test
    func healthSnapshotIsGraphScoped() throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: store.context)
        let graphA = builder.makeGraph(name: "A")
        let graphB = builder.makeGraph(name: "B")
        let entityA = builder.makeEntity(name: "Scoped A", in: graphA)
        let entityB = builder.makeEntity(name: "Scoped B", in: graphB)
        try builder.save()

        let snapshot = try GraphStatsService(context: store.context).healthSnapshot(for: graphA.id)
        let allAffectedNodeIDs = Set(snapshot.issues.flatMap(\.affectedNodeIDs))

        #expect(snapshot.graphID == graphA.id)
        #expect(allAffectedNodeIDs.contains(entityA.id))
        #expect(allAffectedNodeIDs.contains(entityB.id) == false)
    }
}
