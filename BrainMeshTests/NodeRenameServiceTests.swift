import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct NodeRenameServiceTests {

    @Test
    func entityRenameCommitsNodeAndEveryRelabeledLinkInOneStableBatch() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: renameUUID(1))
        let entity = fixtures.makeEntity(name: "Old", in: graph, id: renameUUID(2))
        let child = fixtures.makeAttribute(name: "Child", owner: entity, id: renameUUID(3))
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph, id: renameUUID(4))
        let incoming = fixtures.makeLink(
            source: .entity(survivor),
            target: .entity(entity),
            id: renameUUID(10)
        )
        let childOutgoing = fixtures.makeLink(
            source: .attribute(child),
            target: .entity(survivor),
            id: renameUUID(11)
        )
        let outgoing = fixtures.makeLink(
            source: .entity(entity),
            target: .entity(survivor),
            id: renameUUID(12)
        )
        let unrelated = fixtures.makeLink(
            source: .entity(survivor),
            target: .entity(survivor),
            id: renameUUID(13)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let didRename = try await NodeRenameService.renameEntity(
            entity,
            to: "  New  ",
            in: store.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )

        #expect(didRename)
        #expect(entity.name == "New")
        #expect(incoming.targetLabel == "New")
        #expect(childOutgoing.sourceLabel == "New · Child")
        #expect(outgoing.sourceLabel == "New")
        #expect(unrelated.sourceLabel == "Survivor")
        #expect(unrelated.targetLabel == "Survivor")

        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(
            batches.first?.events.map(\.kind)
                == [.entityUpdated, .linkUpdated, .linkUpdated, .linkUpdated]
        )
        #expect(
            batches.first?.events.dropFirst().compactMap(firstLinkID)
                == [incoming.id, childOutgoing.id, outgoing.id]
        )
    }

    @Test
    func attributeRenameUsesAttributeAndTechnicalLinkIDs() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: renameUUID(20))
        let owner = fixtures.makeEntity(name: "Owner", in: graph, id: renameUUID(21))
        let attribute = fixtures.makeAttribute(name: "Old", owner: owner, id: renameUUID(22))
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph, id: renameUUID(23))
        let firstLink = fixtures.makeLink(
            source: .attribute(attribute),
            target: .entity(survivor),
            id: renameUUID(24)
        )
        let secondLink = fixtures.makeLink(
            source: .entity(survivor),
            target: .attribute(attribute),
            id: renameUUID(25)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        try await NodeRenameService.renameAttribute(
            attribute,
            to: "New",
            in: store.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )

        #expect(attribute.name == "New")
        #expect(firstLink.sourceLabel == "Owner · New")
        #expect(secondLink.targetLabel == "Owner · New")

        let batches = await publisher.recordedBatches
        let batch = try #require(batches.first)
        #expect(batch.graphID == graph.id)
        #expect(batch.events.map(\.kind) == [.attributeUpdated, .linkUpdated, .linkUpdated])
        #expect(batch.events.first?.references == [.node(NodeRefKey(kind: .attribute, id: attribute.id))])
        #expect(batch.events.dropFirst().compactMap(firstLinkID) == [firstLink.id, secondLink.id])
    }

    @Test
    func renameSaveFailureRollsBackAndPublishesNothing() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: renameUUID(30))
        let entity = fixtures.makeEntity(name: "Old", in: graph, id: renameUUID(31))
        let survivor = fixtures.makeEntity(name: "Survivor", in: graph, id: renameUUID(32))
        let link = fixtures.makeLink(
            source: .entity(entity),
            target: .entity(survivor),
            id: renameUUID(33)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in throw RenameTestError.saveFailed }
        )

        await #expect(throws: RenameTestError.saveFailed) {
            _ = try await NodeRenameService.renameEntity(
                entity,
                to: "New",
                in: store.context,
                committer: committer
            )
        }
        #expect(await publisher.recordedBatches.isEmpty)

        let verificationContext = BrainMeshTestContainer.makeContext(for: store.container)
        let entityID = entity.id
        let linkID = link.id
        let storedEntity = try #require(
            verificationContext.fetch(
                FetchDescriptor<MetaEntity>(
                    predicate: #Predicate { candidate in candidate.id == entityID }
                )
            ).first
        )
        let storedLink = try #require(
            verificationContext.fetch(
                FetchDescriptor<MetaLink>(
                    predicate: #Predicate { candidate in candidate.id == linkID }
                )
            ).first
        )
        #expect(storedEntity.name == "Old")
        #expect(storedLink.sourceLabel == "Old")
    }

    private func firstLinkID(_ event: GraphMutationEvent) -> UUID? {
        guard case .link(let id, _, _) = event.references.first else { return nil }
        return id
    }
}

private enum RenameTestError: Error {
    case saveFailed
}

private func renameUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
