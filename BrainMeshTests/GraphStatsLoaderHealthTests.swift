import Foundation
import Testing
@testable import BrainMesh

struct GraphStatsLoaderHealthTests {

    @Test
    func loadDashboardSnapshotIncludesActiveHealth() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Health")
        let entity = fixtures.makeEntity(name: "Isolated", in: graph)
        try fixtures.save()

        let loader = GraphStatsLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadDashboardSnapshot(
            graphIDs: [graph.id],
            activeGraphID: graph.id,
            days: 7
        )
        let health = try #require(snapshot.activeHealth)
        let issue = try #require(health.issues.first { $0.kind == .isolatedEntities })

        #expect(health.graphID == graph.id)
        #expect(issue.affectedNodeIDs == [entity.id])
    }

    @Test
    func loadDashboardSnapshotHealthIsScopedToDashboardGraph() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graphA = fixtures.makeGraph(name: "A")
        let graphB = fixtures.makeGraph(name: "B")
        let entityA = fixtures.makeEntity(name: "A Entity", in: graphA)
        let entityB = fixtures.makeEntity(name: "B Entity", in: graphB)
        try fixtures.save()

        let loader = GraphStatsLoader()
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadDashboardSnapshot(
            graphIDs: [graphA.id, graphB.id],
            activeGraphID: graphA.id,
            days: 7
        )
        let health = try #require(snapshot.activeHealth)
        let affectedNodeIDs = Set(health.issues.flatMap(\.affectedNodeIDs))

        #expect(health.graphID == graphA.id)
        #expect(affectedNodeIDs.contains(entityA.id))
        #expect(affectedNodeIDs.contains(entityB.id) == false)
    }
}
