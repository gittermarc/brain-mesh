//
//  NodeConnectionsLoaderTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh
import SwiftData

@Suite("Node connections background loader")
struct NodeConnectionsLoaderTests {
    @Test
    func entityOwnerReturnsOutgoingAndIncomingPreviews() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let targetEntity = fixtures.makeEntity(
            name: "Stored Target Entity",
            in: graph
        )
        let targetAttributeOwner = fixtures.makeEntity(
            name: "Target Owner",
            in: graph
        )
        let targetAttribute = fixtures.makeAttribute(
            name: "Stored Target Attribute",
            owner: targetAttributeOwner
        )
        let sourceEntity = fixtures.makeEntity(
            name: "Stored Source Entity",
            in: graph
        )
        let sourceAttributeOwner = fixtures.makeEntity(
            name: "Source Owner",
            in: graph
        )
        let sourceAttribute = fixtures.makeAttribute(
            name: "Stored Source Attribute",
            owner: sourceAttributeOwner
        )

        _ = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(targetEntity),
            note: "Entity outgoing",
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .entity(owner),
            target: .attribute(targetAttribute),
            note: "Attribute outgoing",
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .entity(sourceEntity),
            target: .entity(owner),
            note: "Entity incoming",
            graphID: graph.id
        )
        _ = fixtures.makeLink(
            source: .attribute(sourceAttribute),
            target: .entity(owner),
            note: "Attribute incoming",
            graphID: graph.id
        )

        targetEntity.name = "Current Target Entity"
        targetAttribute.name = "Current Target Attribute"
        sourceEntity.name = "Current Source Entity"
        sourceAttribute.name = "Current Source Attribute"
        try fixtures.save()

        let snapshot = try await makeLoader(store)
            .loadPreviewSnapshot(
                ownerKind: .entity,
                ownerID: owner.id,
                graphID: graph.id,
                previewLimit: 12
            )

        #expect(snapshot.outgoingCount == 2)
        #expect(snapshot.incomingCount == 2)
        #expect(
            Set(snapshot.outgoingPreview.map(\.peerKindRaw))
                == Set([
                    NodeKind.entity.rawValue,
                    NodeKind.attribute.rawValue
                ])
        )
        #expect(
            Set(snapshot.incomingPreview.map(\.peerKindRaw))
                == Set([
                    NodeKind.entity.rawValue,
                    NodeKind.attribute.rawValue
                ])
        )
        #expect(
            Set(snapshot.outgoingPreview.map(\.peerLabel))
                == Set([
                    "Current Target Entity",
                    "Target Owner · Current Target Attribute"
                ])
        )
        #expect(
            Set(snapshot.incomingPreview.map(\.peerLabel))
                == Set([
                    "Current Source Entity",
                    "Source Owner · Current Source Attribute"
                ])
        )
        #expect(
            Set(snapshot.outgoingPreview.compactMap(\.note))
                == Set(["Entity outgoing", "Attribute outgoing"])
        )
        #expect(
            Set(snapshot.incomingPreview.compactMap(\.note))
                == Set(["Entity incoming", "Attribute incoming"])
        )
    }

    @Test
    func attributeOwnerReturnsOutgoingAndIncomingPreviews() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let ownerEntity = fixtures.makeEntity(
            name: "Owner Entity",
            in: graph
        )
        let owner = fixtures.makeAttribute(
            name: "Owner Attribute",
            owner: ownerEntity
        )
        let targetEntity = fixtures.makeEntity(
            name: "Target Entity",
            in: graph
        )
        let targetAttributeOwner = fixtures.makeEntity(
            name: "Target Owner",
            in: graph
        )
        let targetAttribute = fixtures.makeAttribute(
            name: "Target Attribute",
            owner: targetAttributeOwner
        )
        let sourceEntity = fixtures.makeEntity(
            name: "Source Entity",
            in: graph
        )
        let sourceAttributeOwner = fixtures.makeEntity(
            name: "Source Owner",
            in: graph
        )
        let sourceAttribute = fixtures.makeAttribute(
            name: "Source Attribute",
            owner: sourceAttributeOwner
        )

        _ = fixtures.makeLink(
            source: .attribute(owner),
            target: .entity(targetEntity),
            note: "Attribute to entity"
        )
        _ = fixtures.makeLink(
            source: .attribute(owner),
            target: .attribute(targetAttribute),
            note: "Attribute to attribute"
        )
        _ = fixtures.makeLink(
            source: .entity(sourceEntity),
            target: .attribute(owner),
            note: "Entity to attribute"
        )
        _ = fixtures.makeLink(
            source: .attribute(sourceAttribute),
            target: .attribute(owner),
            note: "Attribute to attribute incoming"
        )
        try fixtures.save()

        let snapshot = try await makeLoader(store)
            .loadPreviewSnapshot(
                ownerKind: .attribute,
                ownerID: owner.id,
                graphID: graph.id,
                previewLimit: 12
            )

        #expect(snapshot.outgoingCount == 2)
        #expect(snapshot.incomingCount == 2)
        #expect(
            Set(snapshot.outgoingPreview.map(\.peerID))
                == Set([targetEntity.id, targetAttribute.id])
        )
        #expect(
            Set(snapshot.incomingPreview.map(\.peerID))
                == Set([sourceEntity.id, sourceAttribute.id])
        )
    }

    @Test
    func allFourEndpointKindCombinationsResolveCorrectly() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let firstEntity = fixtures.makeEntity(
            name: "Entity A",
            in: graph
        )
        let secondEntity = fixtures.makeEntity(
            name: "Entity B",
            in: graph
        )
        let firstAttribute = fixtures.makeAttribute(
            name: "Attribute A",
            owner: firstEntity
        )
        let secondAttribute = fixtures.makeAttribute(
            name: "Attribute B",
            owner: secondEntity
        )

        _ = fixtures.makeLink(
            source: .entity(firstEntity),
            target: .entity(secondEntity),
            note: "entity-entity"
        )
        _ = fixtures.makeLink(
            source: .entity(firstEntity),
            target: .attribute(secondAttribute),
            note: "entity-attribute"
        )
        _ = fixtures.makeLink(
            source: .attribute(firstAttribute),
            target: .entity(secondEntity),
            note: "attribute-entity"
        )
        _ = fixtures.makeLink(
            source: .attribute(firstAttribute),
            target: .attribute(secondAttribute),
            note: "attribute-attribute"
        )
        try fixtures.save()

        let loader = makeLoader(store)
        let entitySnapshot = try await loader.loadPreviewSnapshot(
            ownerKind: .entity,
            ownerID: firstEntity.id,
            graphID: graph.id,
            previewLimit: 12
        )
        let attributeSnapshot = try await loader.loadPreviewSnapshot(
            ownerKind: .attribute,
            ownerID: firstAttribute.id,
            graphID: graph.id,
            previewLimit: 12
        )

        let entityNotes = Set(
            entitySnapshot.outgoingPreview.compactMap(\.note)
        )
        let attributeNotes = Set(
            attributeSnapshot.outgoingPreview.compactMap(\.note)
        )

        #expect(
            entityNotes
                == Set(["entity-entity", "entity-attribute"])
        )
        #expect(
            attributeNotes
                == Set([
                    "attribute-entity",
                    "attribute-attribute"
                ])
        )
        #expect(
            entitySnapshot.outgoingPreview
                .first { $0.note == "entity-attribute" }?
                .peerLabel
                == "Entity B · Attribute B"
        )
        #expect(
            attributeSnapshot.outgoingPreview
                .first { $0.note == "attribute-entity" }?
                .peerLabel
                == "Entity B"
        )
    }

    @Test
    func exactCountsRemainCompleteWhenPreviewIsLimited() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)

        for index in 0..<7 {
            let outgoingTarget = fixtures.makeEntity(
                name: "Outgoing \(index)",
                in: graph
            )
            let incomingSource = fixtures.makeEntity(
                name: "Incoming \(index)",
                in: graph
            )
            _ = fixtures.makeLink(
                source: .entity(owner),
                target: .entity(outgoingTarget)
            )
            _ = fixtures.makeLink(
                source: .entity(incomingSource),
                target: .entity(owner)
            )
        }
        try fixtures.save()

        let snapshot = try await makeLoader(store)
            .loadPreviewSnapshot(
                ownerKind: .entity,
                ownerID: owner.id,
                graphID: graph.id,
                previewLimit: 2
            )

        #expect(snapshot.outgoingCount == 7)
        #expect(snapshot.incomingCount == 7)
        #expect(snapshot.outgoingPreview.count == 2)
        #expect(snapshot.incomingPreview.count == 2)
        #expect(snapshot.totalCount == 14)
    }

    @Test
    func zeroPreviewLimitReturnsOnlyExactCounts() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let outgoingTarget = fixtures.makeEntity(
            name: "Outgoing",
            in: graph
        )
        let incomingSource = fixtures.makeEntity(
            name: "Incoming",
            in: graph
        )
        _ = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(outgoingTarget)
        )
        _ = fixtures.makeLink(
            source: .entity(incomingSource),
            target: .entity(owner)
        )
        try fixtures.save()

        let probe = NodeConnectionsCancellationProbe()
        let loader = NodeConnectionsLoader(
            container: AnyModelContainer(store.container),
            cancellationCheck: {
                try probe.check()
            }
        )
        let snapshot = try await loader.loadPreviewSnapshot(
            ownerKind: .entity,
            ownerID: owner.id,
            graphID: graph.id,
            previewLimit: 0
        )

        #expect(snapshot.outgoingCount == 1)
        #expect(snapshot.incomingCount == 1)
        #expect(snapshot.outgoingPreview.isEmpty)
        #expect(snapshot.incomingPreview.isEmpty)
        #expect(probe.checkCount == 4)
    }

    @Test
    func previewsKeepNewestFirstSorting() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let oldestTarget = fixtures.makeEntity(
            name: "Oldest",
            in: graph
        )
        let middleTarget = fixtures.makeEntity(
            name: "Middle",
            in: graph
        )
        let newestTarget = fixtures.makeEntity(
            name: "Newest",
            in: graph
        )
        let oldest = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(oldestTarget)
        )
        let middle = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(middleTarget)
        )
        let newest = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(newestTarget)
        )
        oldest.createdAt = Date(timeIntervalSince1970: 100)
        middle.createdAt = Date(timeIntervalSince1970: 200)
        newest.createdAt = Date(timeIntervalSince1970: 300)
        try fixtures.save()

        let snapshot = try await makeLoader(store)
            .loadPreviewSnapshot(
                ownerKind: .entity,
                ownerID: owner.id,
                graphID: graph.id,
                previewLimit: 3
            )

        #expect(
            snapshot.outgoingPreview.map(\.id)
                == [newest.id, middle.id, oldest.id]
        )
    }

    @Test
    func foreignGraphsAreExcludedEvenWhenNodeIDsCollide() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let foreignGraph = fixtures.makeGraph(name: "Foreign")
        let sharedOwnerID = UUID()
        let primaryOwner = fixtures.makeEntity(
            name: "Primary Owner",
            in: primaryGraph,
            id: sharedOwnerID
        )
        let foreignOwner = fixtures.makeEntity(
            name: "Foreign Owner",
            in: foreignGraph,
            id: sharedOwnerID
        )
        let primaryTarget = fixtures.makeEntity(
            name: "Primary Target",
            in: primaryGraph
        )
        let foreignTarget = fixtures.makeEntity(
            name: "Foreign Target",
            in: foreignGraph
        )
        _ = fixtures.makeLink(
            source: .entity(primaryOwner),
            target: .entity(primaryTarget),
            note: "primary",
            graphID: primaryGraph.id
        )
        _ = fixtures.makeLink(
            source: .entity(foreignOwner),
            target: .entity(foreignTarget),
            note: "foreign",
            graphID: foreignGraph.id
        )
        try fixtures.save()

        let snapshot = try await makeLoader(store)
            .loadPreviewSnapshot(
                ownerKind: .entity,
                ownerID: sharedOwnerID,
                graphID: primaryGraph.id,
                previewLimit: 12
            )

        #expect(snapshot.outgoingCount == 1)
        #expect(
            snapshot.outgoingPreview.compactMap(\.note)
                == ["primary"]
        )
        #expect(
            snapshot.outgoingPreview.map(\.peerLabel)
                == ["Primary Target"]
        )
    }

    @Test
    func deletedAndInvalidPeersAreHandledWithoutUnsafeNavigation()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let deletedTarget = fixtures.makeEntity(
            name: "Deleted Target",
            in: graph
        )
        let deletedPeerLink = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(deletedTarget),
            note: "deleted"
        )
        let invalidPeerLink = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(deletedTarget),
            note: "invalid"
        )
        invalidPeerLink.targetKindRaw = 999
        invalidPeerLink.targetLabel = "Invalid Peer"
        invalidPeerLink.targetID = UUID()
        try fixtures.save()

        store.context.delete(deletedTarget)
        try store.context.save()

        let snapshot = try await makeLoader(store)
            .loadPreviewSnapshot(
                ownerKind: .entity,
                ownerID: owner.id,
                graphID: graph.id,
                previewLimit: 12
            )

        let deletedRow = try #require(
            snapshot.outgoingPreview.first {
                $0.id == deletedPeerLink.id
            }
        )
        let invalidRow = try #require(
            snapshot.outgoingPreview.first {
                $0.id == invalidPeerLink.id
            }
        )

        #expect(deletedRow.peerLabel == "Deleted Target")
        #expect(
            deletedRow.navigationTarget
                == NodeRefKey(
                    kind: .entity,
                    id: deletedPeerLink.targetID
                )
        )
        #expect(invalidRow.peerLabel == "Invalid Peer")
        #expect(invalidRow.peerKind == nil)
        #expect(invalidRow.navigationTarget == nil)
    }

    @Test
    func largeLinkSetsRemainBoundedByTheDefensivePreviewLimit()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let target = fixtures.makeEntity(name: "Target", in: graph)

        for index in 0..<120 {
            let link = fixtures.makeLink(
                source: .entity(owner),
                target: .entity(target),
                note: "Link \(index)"
            )
            link.createdAt = Date(
                timeIntervalSince1970: TimeInterval(index)
            )
        }
        try fixtures.save()

        let snapshot = try await makeLoader(store)
            .loadPreviewSnapshot(
                ownerKind: .entity,
                ownerID: owner.id,
                graphID: graph.id,
                previewLimit: 10_000
            )

        #expect(snapshot.outgoingCount == 120)
        #expect(
            snapshot.outgoingPreview.count
                == NodeConnectionsPreviewSnapshot.maximumPreviewLimit
        )
        #expect(snapshot.incomingPreview.isEmpty)
    }

    @Test
    func cancellationIsPropagatedFromTheBackgroundRead() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph")
        let owner = fixtures.makeEntity(name: "Owner", in: graph)
        let target = fixtures.makeEntity(name: "Target", in: graph)
        _ = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(target)
        )
        try fixtures.save()

        let probe = NodeConnectionsCancellationProbe(
            cancellationCheck: 3
        )
        let loader = NodeConnectionsLoader(
            container: AnyModelContainer(store.container),
            cancellationCheck: {
                try probe.check()
            }
        )

        await #expect(throws: CancellationError.self) {
            _ = try await loader.loadPreviewSnapshot(
                ownerKind: .entity,
                ownerID: owner.id,
                graphID: graph.id,
                previewLimit: 12
            )
        }
        #expect(probe.checkCount == 3)
    }
}

private func makeLoader(
    _ store: BrainMeshTestStore
) -> NodeConnectionsLoader {
    NodeConnectionsLoader(
        container: AnyModelContainer(store.container)
    )
}

private nonisolated final class NodeConnectionsCancellationProbe:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let cancellationCheck: Int?
    private var storedCheckCount: Int = 0

    init(cancellationCheck: Int? = nil) {
        self.cancellationCheck = cancellationCheck
    }

    var checkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCheckCount
    }

    func check() throws {
        let shouldCancel: Bool

        lock.lock()
        storedCheckCount += 1
        shouldCancel = storedCheckCount == cancellationCheck
        lock.unlock()

        if shouldCancel {
            throw CancellationError()
        }
    }
}
