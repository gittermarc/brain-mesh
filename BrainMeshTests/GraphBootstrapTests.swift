import Foundation
import SwiftData
import Testing
@testable import BrainMesh

@MainActor
struct GraphBootstrapTests {

    @Test
    func ensureAtLeastOneGraph_createsDefaultGraphWhenStoreIsEmpty() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()

        let graph = GraphBootstrap.ensureAtLeastOneGraph(using: testStore.context)
        let graphs = try testStore.context.fetch(FetchDescriptor<MetaGraph>())

        #expect(graph.name == "Default")
        #expect(graphs.count == 1)
        #expect(graphs.first?.id == graph.id)
    }

    @Test
    func ensureAtLeastOneGraph_reusesOldestExistingGraphWithoutCreatingAnother() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let older = fixtures.makeGraph(name: "Older")
        older.createdAt = Date(timeIntervalSince1970: 100)
        let newer = fixtures.makeGraph(name: "Newer")
        newer.createdAt = Date(timeIntervalSince1970: 200)
        try fixtures.save()

        let graph = GraphBootstrap.ensureAtLeastOneGraph(using: testStore.context)
        let graphs = try testStore.context.fetch(FetchDescriptor<MetaGraph>())

        #expect(graph.id == older.id)
        #expect(graphs.count == 2)
    }

    @Test
    func migrateLegacyRecordsIfNeeded_assignsGraphIDsAndClearsLegacyDetection() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let defaultGraph = fixtures.makeGraph(name: "Default")
        let ownerGraph = fixtures.makeGraph(name: "Owner")
        let owner = fixtures.makeEntity(name: "Atlas", in: ownerGraph)

        let legacyEntity = MetaEntity(name: "Legacy Entity")
        let legacyAttribute = MetaAttribute(name: "Legacy Attribute", owner: owner)
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

        testStore.context.insert(legacyEntity)
        testStore.context.insert(legacyAttribute)
        testStore.context.insert(legacyLink)
        try fixtures.save()

        #expect(GraphBootstrap.hasLegacyRecords(using: testStore.context) == true)

        GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID: defaultGraph.id, using: testStore.context)

        #expect(legacyEntity.graphID == defaultGraph.id)
        #expect(legacyAttribute.graphID == ownerGraph.id)
        #expect(legacyLink.graphID == defaultGraph.id)
        #expect(GraphBootstrap.hasLegacyRecords(using: testStore.context) == false)
    }

    @Test
    func backfillFoldedNotesIfNeeded_updatesMissingIndicesAndNormalizesEmptyLinkNotes() throws {
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

        GraphBootstrap.backfillFoldedNotesIfNeeded(using: testStore.context)

        #expect(entity.notesFolded == BMSearch.fold(entity.notes))
        #expect(attribute.notesFolded == BMSearch.fold(attribute.notes))
        #expect(link.noteFolded == BMSearch.fold(link.note ?? ""))
        #expect(emptyLink.note == nil)
        #expect(emptyLink.noteFolded == "")
        #expect(GraphBootstrap.hasFoldedNotesBackfillNeeded(using: testStore.context) == false)
    }

    @Test
    func repairChecksStayNoOpWhenNothingNeedsRepair() throws {
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

        GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID: graph.id, using: testStore.context)
        GraphBootstrap.backfillFoldedNotesIfNeeded(using: testStore.context)

        let graphIDsAfter = [entity.graphID, attribute.graphID, link.graphID]
        let notesAfter = [entity.notesFolded, attribute.notesFolded, link.noteFolded]

        #expect(graphIDsAfter == graphIDsBefore)
        #expect(notesAfter == notesBefore)
    }
}
