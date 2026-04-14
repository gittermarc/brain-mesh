import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeLoaderSearchTests {

    @Test
    func entityNameMatch_returnsEntityAndIsNotNotesOnly() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let matched = fixtures.makeEntity(name: "Alpha Node", in: graph)
        let _ = fixtures.makeEntity(name: "Bravo Node", in: graph)
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: graph.id, term: "alpha")

        #expect(results.map(\.entity.id) == [matched.id])
        #expect(results.first?.isNotesOnlyHit == false)
    }

    @Test
    func entityNotesMatch_returnsNotesOnlyHit() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let matched = fixtures.makeEntity(name: "Alpha Node", in: graph, notes: "Contains hidden comet detail")
        let _ = fixtures.makeEntity(name: "Bravo Node", in: graph)
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: graph.id, term: "comet")

        #expect(results.map(\.entity.id) == [matched.id])
        #expect(results.first?.isNotesOnlyHit == true)
    }

    @Test
    func attributeLabelMatch_returnsOwnerAndIsNotNotesOnly() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Project Atlas", in: graph)
        let _ = fixtures.makeAttribute(name: "Launch Date", owner: owner)
        let _ = fixtures.makeEntity(name: "Project Beacon", in: graph)
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: graph.id, term: "launch")

        #expect(results.map(\.entity.id) == [owner.id])
        #expect(results.first?.isNotesOnlyHit == false)
    }

    @Test
    func attributeNotesMatch_returnsOwnerAsNotesOnlyHit() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Project Atlas", in: graph)
        let _ = fixtures.makeAttribute(name: "Status", owner: owner, notes: "Requires ember follow-up")
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: graph.id, term: "ember")

        #expect(results.map(\.entity.id) == [owner.id])
        #expect(results.first?.isNotesOnlyHit == true)
    }

    @Test
    func linkNotesMatch_resolvesEntityAndAttributeEndpoints() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let sourceEntity = fixtures.makeEntity(name: "Alpha", in: graph)
        let ownerEntity = fixtures.makeEntity(name: "Gamma", in: graph)
        let targetAttribute = fixtures.makeAttribute(name: "Leaf", owner: ownerEntity)
        let _ = fixtures.makeLink(
            source: .entity(sourceEntity),
            target: .attribute(targetAttribute),
            note: "Shared bridge context"
        )
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: graph.id, term: "bridge")

        #expect(results.map(\.entity.name) == ["Alpha", "Gamma"])
        #expect(results.contains { $0.isNotesOnlyHit == false } == false)
    }


    @Test
    func linkNotesMatch_deduplicatesEntityAndOwnedAttributeEndpoints() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Alpha", in: graph)
        let ownedAttribute = fixtures.makeAttribute(name: "Leaf", owner: owner)
        let _ = fixtures.makeLink(
            source: .entity(owner),
            target: .attribute(ownedAttribute),
            note: "Shared bridge context"
        )
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: graph.id, term: "bridge")

        #expect(results.map(\.entity.id) == [owner.id])
        #expect(results.first?.isNotesOnlyHit == true)
    }

    @Test
    func strongMatchesStayDeduplicatedWhenAlsoMatchedViaLinkNotes() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Bridge Atlas", in: graph)
        let target = fixtures.makeEntity(name: "Target", in: graph)
        let _ = fixtures.makeLink(
            source: .entity(owner),
            target: .entity(target),
            note: "Bridge alignment"
        )
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: graph.id, term: "bridge")

        #expect(results.map(\.entity.name) == ["Bridge Atlas", "Target"])
        #expect(results.first?.isNotesOnlyHit == false)
        #expect(results.last?.isNotesOnlyHit == true)
    }

    @Test
    func linkNotesMatch_returnsStableAlphabeticalSortAcrossEntityAndAttributeEndpoints() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let zeta = fixtures.makeEntity(name: "Zeta", in: graph)
        let alpha = fixtures.makeEntity(name: "Alpha", in: graph)
        let betaOwner = fixtures.makeEntity(name: "Beta", in: graph)
        let betaAttribute = fixtures.makeAttribute(name: "Leaf", owner: betaOwner)
        let _ = fixtures.makeLink(
            source: .entity(zeta),
            target: .attribute(betaAttribute),
            note: "Orbit marker"
        )
        let _ = fixtures.makeLink(
            source: .entity(alpha),
            target: .entity(zeta),
            note: "Orbit marker"
        )
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: graph.id, term: "orbit")

        #expect(results.map(\.entity.name) == ["Alpha", "Beta", "Zeta"])
        #expect(results.allSatisfy { $0.isNotesOnlyHit })
    }

    @Test
    func graphScoping_excludesMatchesFromOtherGraphs() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let secondaryGraph = fixtures.makeGraph(name: "Secondary")

        let primaryEntity = fixtures.makeEntity(name: "Atlas", in: primaryGraph)
        let primaryAttribute = fixtures.makeAttribute(name: "Milestone", owner: primaryEntity)
        let _ = fixtures.makeLink(
            source: .entity(primaryEntity),
            target: .attribute(primaryAttribute),
            note: "Scoped meteor note"
        )

        let secondaryEntity = fixtures.makeEntity(name: "Meteor Hub", in: secondaryGraph, notes: "Scoped meteor note")
        let _ = fixtures.makeAttribute(name: "Meteor Attribute", owner: secondaryEntity, notes: "Scoped meteor note")
        let _ = fixtures.makeLink(
            source: .entity(secondaryEntity),
            target: .entity(secondaryEntity),
            note: "Scoped meteor note"
        )
        try fixtures.save()

        let results = try searchEntities(in: testStore, graphID: primaryGraph.id, term: "meteor")

        #expect(results.map(\.entity.id) == [primaryEntity.id])
        #expect(results.first?.isNotesOnlyHit == true)
    }

    private func searchEntities(
        in testStore: BrainMeshTestStore,
        graphID: UUID?,
        term: String
    ) throws -> [EntitiesHomeLoader.MatchedEntity] {
        try EntitiesHomeLoader.fetchEntities(
            context: testStore.context,
            graphID: graphID,
            foldedSearch: BMSearch.fold(term)
        )
    }
}
