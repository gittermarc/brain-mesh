import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct GraphBootstrapTests {

    @Test
    func ensureAtLeastOneGraph_createsDefaultGraphWhenStoreIsEmpty() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()

        let publisher = GraphMutationRecordingPublisher()
        let graph = try await GraphBootstrap.ensureAtLeastOneGraph(
            using: testStore.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )
        let graphs = try testStore.context.fetch(FetchDescriptor<MetaGraph>())

        #expect(graph.name == "Default")
        #expect(graphs.count == 1)
        #expect(graphs.first?.id == graph.id)
        let batches = await publisher.recordedBatches
        #expect(batches.count == 1)
        #expect(batches.first?.graphID == graph.id)
        #expect(batches.first?.events.map(\.kind) == [.graphCreated])
    }

    @Test
    func ensureAtLeastOneGraph_reusesOldestExistingGraphWithoutCreatingAnother() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let older = fixtures.makeGraph(name: "Older")
        older.createdAt = Date(timeIntervalSince1970: 100)
        let newer = fixtures.makeGraph(name: "Newer")
        newer.createdAt = Date(timeIntervalSince1970: 200)
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        let graph = try await GraphBootstrap.ensureAtLeastOneGraph(
            using: testStore.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )
        let graphs = try testStore.context.fetch(FetchDescriptor<MetaGraph>())

        #expect(graph.id == older.id)
        #expect(graphs.count == 2)
        #expect(await publisher.recordedBatches.isEmpty)
    }

    @Test
    func migrateLegacyRecordsIfNeeded_assignsGraphIDsAndClearsLegacyDetection() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let defaultGraph = fixtures.makeGraph(name: "Default")
        let ownerGraph = fixtures.makeGraph(name: "Owner")
        let owner = fixtures.makeEntity(name: "Atlas", in: ownerGraph)

        let legacyEntity = MetaEntity(name: "Legacy Entity")
        let legacyAttribute = MetaAttribute(name: "Legacy Attribute", owner: owner)
        legacyAttribute.graphID = nil
        let legacyLink = MetaLink(
            sourceKind: .entity,
            sourceID: owner.id,
            sourceLabel: owner.name,
            targetKind: .entity,
            targetID: legacyEntity.id,
            targetLabel: legacyEntity.name,
            note: nil,
            graphID: nil
        )

        let legacyTemplate = MetaDetailsTemplate(
            name: "Legacy Template",
            graphID: nil,
            fields: []
        )

        testStore.context.insert(legacyEntity)
        testStore.context.insert(legacyAttribute)
        testStore.context.insert(legacyLink)
        testStore.context.insert(legacyTemplate)
        try fixtures.save()

        #expect(GraphBootstrap.hasLegacyRecords(using: testStore.context) == true)

        let publisher = GraphMutationRecordingPublisher()
        try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: defaultGraph.id,
            using: testStore.context,
            committer: GraphMutationCommitter(publisher: publisher)
        )

        #expect(legacyEntity.graphID == defaultGraph.id)
        #expect(legacyAttribute.graphID == ownerGraph.id)
        #expect(legacyLink.graphID == defaultGraph.id)
        #expect(legacyTemplate.graphID == defaultGraph.id)
        #expect(GraphBootstrap.hasLegacyRecords(using: testStore.context) == false)

        let batches = await publisher.recordedBatches
        let expectedGraphIDs = [defaultGraph.id, ownerGraph.id].sorted {
            $0.uuidString < $1.uuidString
        }
        #expect(batches.map(\.graphID) == expectedGraphIDs)
        #expect(
            batches.allSatisfy { batch in
                batch.events.map(\.kind)
                    == [.graphRequiresFullRebuild(.integrityRepair)]
            }
        )
    }

    @Test
    func backfillFoldedNotesIfNeeded_updatesMissingIndicesAndNormalizesEmptyLinkNotes() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Atlas", in: graph)
        let attribute = fixtures.makeAttribute(name: "Color", owner: entity)
        let link = fixtures.makeLink(source: .entity(entity), target: .attribute(attribute), note: "ÄÖ")
        let emptyLink = fixtures.makeLink(source: .attribute(attribute), target: .entity(entity), note: "")

        entity.notes = "Ärger"
        entity.notesFolded = ""
        attribute.notes = "Übergröße"
        attribute.notesFolded = ""
        link.noteFolded = ""
        emptyLink.noteFolded = ""
        try fixtures.save()

        #expect(GraphBootstrap.hasFoldedNotesBackfillNeeded(using: testStore.context) == true)

        try await GraphBootstrap.backfillFoldedNotesIfNeeded(using: testStore.context)

        #expect(entity.notesFolded == BMSearch.fold(entity.notes))
        #expect(attribute.notesFolded == BMSearch.fold(attribute.notes))
        #expect(link.noteFolded == BMSearch.fold(link.note ?? ""))
        #expect(emptyLink.note == nil)
        #expect(emptyLink.noteFolded == "")
        #expect(GraphBootstrap.hasFoldedNotesBackfillNeeded(using: testStore.context) == false)
    }

    @Test
    func foldedNotesPreflightFailureLeavesEveryRecordUnchangedAndPublishesNothing() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let valid = fixtures.makeEntity(name: "Valid", in: graph, notes: "Changed later")
        valid.notesFolded = ""
        let unscoped = MetaEntity(name: "Unscoped")
        unscoped.notes = "Must fail"
        unscoped.notesFolded = ""
        testStore.context.insert(unscoped)
        try fixtures.save()

        let publisher = GraphMutationRecordingPublisher()
        await #expect(throws: GraphBootstrapError.missingGraphScope) {
            try await GraphBootstrap.backfillFoldedNotesIfNeeded(
                using: testStore.context,
                committer: GraphMutationCommitter(publisher: publisher)
            )
        }

        #expect(valid.notesFolded == "")
        #expect(unscoped.notesFolded == "")
        #expect(await publisher.recordedBatches.isEmpty)
        testStore.context.rollback()
    }

    @Test
    func repairChecksStayNoOpWhenNothingNeedsRepair() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Atlas", in: graph, notes: "Ready")
        let attribute = fixtures.makeAttribute(name: "Color", owner: entity, notes: "Stable")
        let link = fixtures.makeLink(source: .entity(entity), target: .attribute(attribute), note: "Connected", graphID: graph.id)
        try fixtures.save()

        let graphIDsBefore = [entity.graphID, attribute.graphID, link.graphID]
        let notesBefore = [entity.notesFolded, attribute.notesFolded, link.noteFolded]

        #expect(GraphBootstrap.hasLegacyRecords(using: testStore.context) == false)
        #expect(GraphBootstrap.hasFoldedNotesBackfillNeeded(using: testStore.context) == false)

        try await GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID: graph.id, using: testStore.context)
        try await GraphBootstrap.backfillFoldedNotesIfNeeded(using: testStore.context)

        let graphIDsAfter = [entity.graphID, attribute.graphID, link.graphID]
        let notesAfter = [entity.notesFolded, attribute.notesFolded, link.noteFolded]

        #expect(graphIDsAfter == graphIDsBefore)
        #expect(notesAfter == notesBefore)
    }
}
