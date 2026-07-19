import Foundation
import Testing

@testable import BrainMesh

struct NodeRepositoryTests {

    @Test
    func entityAndAttributeLookupsNeverCrossGraphBoundaries() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")
        let sharedEntityID = UUID()
        let sharedAttributeID = UUID()

        let primaryEntity = fixtures.makeEntity(
            name: "Primary Entity",
            in: primaryGraph,
            notes: "Primary Notes",
            id: sharedEntityID
        )
        _ = fixtures.makeAttribute(
            name: "Primary Attribute",
            owner: primaryEntity,
            notes: "Primary Attribute Notes",
            id: sharedAttributeID
        )

        let secondaryEntity = fixtures.makeEntity(
            name: "Secondary Entity",
            in: secondaryGraph,
            notes: "Secondary Notes",
            id: sharedEntityID
        )
        _ = fixtures.makeAttribute(
            name: "Secondary Attribute",
            owner: secondaryEntity,
            notes: "Secondary Attribute Notes",
            id: sharedAttributeID
        )
        try fixtures.save()

        let repository = NodeRepository(container: AnyModelContainer(store.container))
        let primaryScope = GraphScope(graphID: primaryGraph.id)
        let entity = try await repository.entity(id: sharedEntityID, in: primaryScope)
        let attribute = try await repository.attribute(id: sharedAttributeID, in: primaryScope)
        let summary = try await repository.node(
            NodeRefKey(kind: .attribute, id: sharedAttributeID),
            in: primaryScope
        )

        #expect(entity?.name == "Primary Entity")
        #expect(entity?.notes == "Primary Notes")
        #expect(attribute?.name == "Primary Attribute")
        #expect(attribute?.ownerLabel == "Primary Entity")
        #expect(summary?.label == "Primary Entity · Primary Attribute")
        #expect(summary?.scope == primaryScope)
    }

    @Test
    func directNeighborhoodContainsIncomingOutgoingAndScopedPeerSummaries() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")

        let sharedCenterID = UUID()
        let sharedSourceID = UUID()
        let sharedTargetID = UUID()
        let sharedOutgoingLinkID = UUID()
        let sharedIncomingLinkID = UUID()

        let primaryCenter = fixtures.makeEntity(
            name: "Primary Center",
            in: primaryGraph,
            id: sharedCenterID
        )
        let primarySource = fixtures.makeEntity(
            name: "Primary Source",
            in: primaryGraph,
            id: sharedSourceID
        )
        let primaryTarget = fixtures.makeAttribute(
            name: "Primary Target",
            owner: primaryCenter,
            id: sharedTargetID
        )
        _ = fixtures.makeLink(
            source: .entity(primaryCenter),
            target: .attribute(primaryTarget),
            note: "Primary Outgoing",
            graphID: primaryGraph.id,
            id: sharedOutgoingLinkID
        )
        _ = fixtures.makeLink(
            source: .entity(primarySource),
            target: .entity(primaryCenter),
            note: "Primary Incoming",
            graphID: primaryGraph.id,
            id: sharedIncomingLinkID
        )

        let secondaryCenter = fixtures.makeEntity(
            name: "Secondary Center",
            in: secondaryGraph,
            id: sharedCenterID
        )
        let secondarySource = fixtures.makeEntity(
            name: "Secondary Source",
            in: secondaryGraph,
            id: sharedSourceID
        )
        let secondaryTarget = fixtures.makeAttribute(
            name: "Secondary Target",
            owner: secondaryCenter,
            id: sharedTargetID
        )
        _ = fixtures.makeLink(
            source: .entity(secondaryCenter),
            target: .attribute(secondaryTarget),
            note: "Secondary Outgoing",
            graphID: secondaryGraph.id,
            id: sharedOutgoingLinkID
        )
        _ = fixtures.makeLink(
            source: .entity(secondarySource),
            target: .entity(secondaryCenter),
            note: "Secondary Incoming",
            graphID: secondaryGraph.id,
            id: sharedIncomingLinkID
        )
        try fixtures.save()

        let repository = NodeRepository(container: AnyModelContainer(store.container))
        let scope = GraphScope(graphID: primaryGraph.id)
        let neighborhood = try await repository.directNeighborhood(
            of: NodeRefKey(kind: .entity, id: sharedCenterID),
            in: scope
        )

        #expect(neighborhood?.scope == scope)
        #expect(neighborhood?.center.label == "Primary Center")
        #expect(neighborhood?.outgoingLinks.map(\.note) == ["Primary Outgoing"])
        #expect(neighborhood?.incomingLinks.map(\.note) == ["Primary Incoming"])
        #expect(
            Set(neighborhood?.neighbors.map(\.label) ?? [])
                == Set(["Primary Source", "Primary Center · Primary Target"])
        )
        #expect(neighborhood?.neighbors.allSatisfy { $0.scope == scope } == true)
    }

    @Test
    func missingNodeReturnsNoSummaryOrNeighborhood() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Primary")
        try fixtures.save()

        let repository = NodeRepository(container: AnyModelContainer(store.container))
        let scope = GraphScope(graphID: graph.id)
        let missing = NodeRefKey(kind: .entity, id: UUID())

        let summary = try await repository.node(missing, in: scope)
        let neighborhood = try await repository.directNeighborhood(of: missing, in: scope)

        #expect(summary == nil)
        #expect(neighborhood == nil)
    }
}
