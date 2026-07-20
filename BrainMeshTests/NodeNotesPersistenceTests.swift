import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct NodeNotesPersistenceTests {

    @Test
    func draftKeystrokesProduceOnlyTheLatestExplicitCommitCandidate() {
        var state = NodeNotesCommitState(initialNotes: "Initial")

        state.updateDraft("I")
        state.updateDraft("In")
        state.updateDraft("Final")

        #expect(state.hasPendingChanges)
        #expect(state.commitCandidate == "Final")

        state.markCommitted("Final")
        #expect(state.hasPendingChanges == false)
        #expect(state.commitCandidate == nil)
    }

    @Test
    func draftChangedDuringCommitRemainsPendingAfterEarlierCandidateCompletes() throws {
        var state = NodeNotesCommitState(initialNotes: "Initial")
        state.updateDraft("First candidate")
        let firstCandidate = try #require(state.commitCandidate)

        state.updateDraft("Latest candidate")
        state.markCommitted(firstCandidate)

        #expect(state.hasPendingChanges)
        #expect(state.commitCandidate == "Latest candidate")
    }

    @Test
    func finalEntityDraftCommitsOnceAndUnchangedDraftIsNoOp() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: notesUUID(1))
        let entity = fixtures.makeEntity(
            name: "Entity",
            in: graph,
            notes: "Initial",
            id: notesUUID(2)
        )
        try fixtures.save()

        var state = NodeNotesCommitState(initialNotes: entity.notes)
        state.updateDraft("First keystroke")
        state.updateDraft("Last draft")

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(publisher: publisher)
        let candidate = try #require(state.commitCandidate)
        let didCommit = try await NodeNotesPersistence.commitEntityNotes(
            candidate,
            entity: entity,
            in: store.context,
            committer: committer
        )
        state.markCommitted(candidate)

        #expect(didCommit)
        #expect(entity.notes == "Last draft")
        #expect(entity.notesFolded == BMSearch.fold("Last draft"))
        #expect(state.commitCandidate == nil)

        let didCommitAgain = try await NodeNotesPersistence.commitEntityNotes(
            "Last draft",
            entity: entity,
            in: store.context,
            committer: committer
        )
        #expect(didCommitAgain == false)

        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.first?.graphID == graph.id)
        #expect(batches.first?.events.map(\.kind) == [.entityUpdated])
        #expect(
            batches.first?.events.first?.references
                == [.node(NodeRefKey(kind: .entity, id: entity.id))]
        )
    }

    @Test
    func attributeNotesUseAttributeUpdateAndSaveFailurePublishesNothing() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Graph", id: notesUUID(10))
        let entity = fixtures.makeEntity(name: "Entity", in: graph, id: notesUUID(11))
        let attribute = fixtures.makeAttribute(
            name: "Attribute",
            owner: entity,
            notes: "Old",
            id: notesUUID(12)
        )
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in throw NotesTestError.saveFailed }
        )

        await #expect(throws: NotesTestError.saveFailed) {
            _ = try await NodeNotesPersistence.commitAttributeNotes(
                "New",
                attribute: attribute,
                in: store.context,
                committer: committer
            )
        }
        #expect(await publisher.recordedBatches.isEmpty)

        let verificationContext = BrainMeshTestContainer.makeContext(for: store.container)
        let attributeID = attribute.id
        let storedAttribute = try #require(
            verificationContext.fetch(
                FetchDescriptor<MetaAttribute>(
                    predicate: #Predicate { candidate in candidate.id == attributeID }
                )
            ).first
        )
        #expect(storedAttribute.notes == "Old")
    }
}

private enum NotesTestError: Error {
    case saveFailed
}

private func notesUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
