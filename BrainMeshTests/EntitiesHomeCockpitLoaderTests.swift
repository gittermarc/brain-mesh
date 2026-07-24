import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeCockpitLoaderTests {

    @Test
    func snapshotCountsGraphScopedObjects() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")

        let primaryEntity = fixtures.makeEntity(name: "Atlas", in: primaryGraph)
        let primaryIsolated = fixtures.makeEntity(name: "Beacon", in: primaryGraph)
        let primaryAttribute = fixtures.makeAttribute(name: "Owner", owner: primaryEntity)
        let _ = fixtures.makeLink(
            source: .entity(primaryEntity),
            target: .attribute(primaryAttribute),
            graphID: primaryGraph.id
        )
        let _ = fixtures.makeAttachment(
            owner: .entity(primaryIsolated),
            title: "Briefing",
            byteCount: 1_024,
            fileData: Data(repeating: 7, count: 16)
        )

        let secondaryEntity = fixtures.makeEntity(name: "Other", in: secondaryGraph)
        let secondaryAttribute = fixtures.makeAttribute(name: "Other Attribute", owner: secondaryEntity)
        let _ = fixtures.makeLink(
            source: .entity(secondaryEntity),
            target: .attribute(secondaryAttribute),
            graphID: secondaryGraph.id
        )
        let _ = fixtures.makeAttachment(owner: .entity(secondaryEntity), byteCount: 2_048)
        try fixtures.save()

        let snapshot = try await loadSnapshot(in: testStore, graphID: primaryGraph.id, recentItems: [], limit: 5)

        #expect(snapshot.healthSummary.counts.entities == 2)
        #expect(snapshot.healthSummary.counts.attributes == 1)
        #expect(snapshot.healthSummary.counts.links == 1)
        #expect(snapshot.healthSummary.counts.attachments == 1)
        #expect(snapshot.healthSummary.counts.attachmentBytes == 1_024)
        #expect(Set(snapshot.healthSummary.isolatedEntityIDs) == [primaryIsolated.id])
    }

    @Test
    func snapshotDetectsEntitiesWithoutAttributesAndDetails() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let complete = fixtures.makeEntity(name: "Complete", in: graph)
        let noAttributes = fixtures.makeEntity(name: "No Attributes", in: graph)
        let noDetails = fixtures.makeEntity(name: "No Details", in: graph)
        let _ = fixtures.makeAttribute(name: "Status", owner: complete)
        let _ = fixtures.makeAttribute(name: "Risk", owner: noDetails)
        let _ = fixtures.makeDetailField(owner: complete, name: "Status", type: .singleLineText, sortIndex: 0)
        let _ = fixtures.makeDetailField(owner: noAttributes, name: "Owner", type: .singleLineText, sortIndex: 1)
        try fixtures.save()

        let snapshot = try await loadSnapshot(in: testStore, graphID: graph.id, recentItems: [], limit: 5)

        #expect(Set(snapshot.healthSummary.entityIDsWithoutAttributes) == [noAttributes.id])
        #expect(Set(snapshot.healthSummary.entityIDsWithoutDetails) == [noDetails.id])

        let withoutAttributes = try #require(snapshot.quickFilterSnapshot(for: .entitiesWithoutAttributes))
        let withoutDetails = try #require(snapshot.quickFilterSnapshot(for: .entitiesWithoutDetails))
        #expect(withoutAttributes.matchingEntityIDs == [noAttributes.id])
        #expect(withoutDetails.matchingEntityIDs == [noDetails.id])
    }

    @Test
    func mediaRichFilterIncludesEntityAndAttributeOwnedMedia() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entityHeaderImage = fixtures.makeEntity(name: "Header", in: graph, imageData: Data([1]))
        let attributeMediaOwner = fixtures.makeEntity(name: "Attribute Media", in: graph)
        let plain = fixtures.makeEntity(name: "Plain", in: graph)
        let attribute = fixtures.makeAttribute(name: "Photo", owner: attributeMediaOwner)
        let _ = fixtures.makeAttachment(owner: .attribute(attribute), contentKind: .galleryImage, byteCount: 300)
        try fixtures.save()

        let snapshot = try await loadSnapshot(in: testStore, graphID: graph.id, recentItems: [], limit: 5)
        let media = try #require(snapshot.quickFilterSnapshot(for: .mediaRich))

        #expect(media.matchingEntityIDs == [entityHeaderImage.id, attributeMediaOwner.id])
        #expect(media.matchingEntityIDs.contains(plain.id) == false)
    }

    @Test
    func recentItemsAreGraphScopedValidatedAndLimited() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let entity = fixtures.makeEntity(name: "Atlas Current", in: primaryGraph, iconSymbolName: "cube")
        let owner = fixtures.makeEntity(name: "System", in: primaryGraph)
        let attribute = fixtures.makeAttribute(name: "Owner", owner: owner, iconSymbolName: "person")
        let secondaryEntity = fixtures.makeEntity(name: "Wrong Graph", in: secondaryGraph)
        try fixtures.save()

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let recentItems = [
            RecentNodeItem(
                graphID: primaryGraph.id,
                nodeKindRaw: NodeKind.attribute.rawValue,
                nodeID: attribute.id,
                label: "Old Attribute Label",
                iconSymbolName: "tag",
                openedAt: baseDate.addingTimeInterval(30)
            ),
            RecentNodeItem(
                graphID: primaryGraph.id,
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: entity.id,
                label: "Old Entity Label",
                iconSymbolName: "circle",
                openedAt: baseDate.addingTimeInterval(20)
            ),
            RecentNodeItem(
                graphID: primaryGraph.id,
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: UUID(),
                label: "Missing",
                iconSymbolName: "xmark",
                openedAt: baseDate.addingTimeInterval(40)
            ),
            RecentNodeItem(
                graphID: secondaryGraph.id,
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: secondaryEntity.id,
                label: "Wrong Graph",
                iconSymbolName: "circle",
                openedAt: baseDate.addingTimeInterval(50)
            )
        ]

        let snapshot = try await loadSnapshot(in: testStore, graphID: primaryGraph.id, recentItems: recentItems, limit: 3)

        #expect(snapshot.recentNodes.map(\.nodeID) == [attribute.id, entity.id])
        #expect(snapshot.recentNodes.map(\.label) == ["Owner", "Atlas Current"])
        #expect(snapshot.recentNodes.first?.subtitle == "System")
        #expect(snapshot.recentNodes.first?.iconSymbolName == "person")
    }

    private func loadSnapshot(
        in testStore: BrainMeshTestStore,
        graphID: UUID?,
        recentItems: [RecentNodeItem],
        limit: Int
    ) async throws -> EntitiesHomeCockpitSnapshot {
        let loader = EntitiesHomeCockpitLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))
        return try await loader.loadSnapshot(graphID: graphID, recentItems: recentItems, limit: limit)
    }
}
