import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeRecentNodesLoaderTests {

    @Test
    func loaderReturnsOnlyRequestedIDsInHistoryOrder() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let first = fixtures.makeEntity(name: "First", in: graph)
        let second = fixtures.makeEntity(name: "Second", in: graph)
        let unrequested = fixtures.makeEntity(name: "Unrequested", in: graph)
        try fixtures.save()

        let history = [
            recent(
                graphID: graph.id,
                kind: .entity,
                nodeID: second.id,
                openedAt: 300
            ),
            recent(
                graphID: graph.id,
                kind: .entity,
                nodeID: first.id,
                openedAt: 200
            )
        ]
        let loader = await configuredLoader(testStore)

        let nodes = try await loader.load(
            graphID: graph.id,
            recentItems: history,
            limit: 8
        )

        #expect(nodes.map(\.nodeID) == [second.id, first.id])
        #expect(nodes.contains { $0.nodeID == unrequested.id } == false)
        let metrics = await loader.lastLoadMetricsForTesting()
        #expect(metrics.requestedEntityCount == 2)
        #expect(metrics.requestedAttributeCount == 0)
        #expect(metrics.entityFetchCount == 1)
        #expect(metrics.attributeFetchCount == 0)
    }

    @Test
    func historyIsDeduplicatedBeforeTheUILimitIsApplied() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let first = fixtures.makeEntity(name: "First", in: graph)
        let second = fixtures.makeEntity(name: "Second", in: graph)
        try fixtures.save()

        let history = [
            recent(
                graphID: graph.id,
                kind: .entity,
                nodeID: first.id,
                openedAt: 400
            ),
            recent(
                graphID: graph.id,
                kind: .entity,
                nodeID: first.id,
                openedAt: 300
            ),
            recent(
                graphID: graph.id,
                kind: .entity,
                nodeID: second.id,
                openedAt: 200
            )
        ]
        let loader = await configuredLoader(testStore)

        let nodes = try await loader.load(
            graphID: graph.id,
            recentItems: history,
            limit: 2
        )

        #expect(nodes.map(\.nodeID) == [first.id, second.id])
        #expect(nodes.first?.openedAt == Date(timeIntervalSince1970: 400))
    }

    @Test
    func deletedAndForeignGraphNodesAreSkipped() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graphA = fixtures.makeGraph(name: "A")
        let graphB = fixtures.makeGraph(name: "B")
        let valid = fixtures.makeEntity(name: "Valid", in: graphA)
        let foreign = fixtures.makeEntity(name: "Foreign", in: graphB)
        try fixtures.save()

        let history = [
            recent(
                graphID: graphA.id,
                kind: .entity,
                nodeID: UUID(),
                openedAt: 500
            ),
            recent(
                graphID: graphA.id,
                kind: .entity,
                nodeID: foreign.id,
                openedAt: 400
            ),
            recent(
                graphID: graphA.id,
                kind: .entity,
                nodeID: valid.id,
                openedAt: 300
            )
        ]
        let loader = await configuredLoader(testStore)

        let nodes = try await loader.load(
            graphID: graphA.id,
            recentItems: history,
            limit: 8
        )

        #expect(nodes.map(\.nodeID) == [valid.id])
    }

    @Test
    func currentEntityNameAndIconReplaceStoredHistoryPresentation() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(
            name: "Old",
            in: graph,
            iconSymbolName: "circle"
        )
        try fixtures.save()

        let history = [
            RecentNodeItem(
                graphID: graph.id,
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: entity.id,
                label: "Stored Old",
                iconSymbolName: "xmark",
                openedAt: Date(timeIntervalSince1970: 100)
            )
        ]
        entity.name = "Renamed"
        entity.iconSymbolName = "star"
        entity.nameFolded = BMSearch.fold(entity.name)
        try fixtures.save()

        let loader = await configuredLoader(testStore)
        let nodes = try await loader.load(
            graphID: graph.id,
            recentItems: history,
            limit: 8
        )

        #expect(nodes.first?.label == "Renamed")
        #expect(nodes.first?.iconSymbolName == "star")
    }

    @Test
    func attributeUsesCurrentOwnerEntityAndPresentation() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let owner = fixtures.makeEntity(name: "Old Owner", in: graph)
        let attribute = fixtures.makeAttribute(
            name: "Current Attribute",
            owner: owner,
            iconSymbolName: "person"
        )
        try fixtures.save()

        let history = [
            recent(
                graphID: graph.id,
                kind: .attribute,
                nodeID: attribute.id,
                openedAt: 100
            )
        ]
        owner.name = "Current Owner"
        owner.nameFolded = BMSearch.fold(owner.name)
        try fixtures.save()

        let loader = await configuredLoader(testStore)
        let nodes = try await loader.load(
            graphID: graph.id,
            recentItems: history,
            limit: 8
        )

        #expect(nodes.first?.label == "Current Attribute")
        #expect(nodes.first?.subtitle == "Current Owner")
        #expect(nodes.first?.ownerEntityID == owner.id)
        #expect(nodes.first?.iconSymbolName == "person")
    }

    @Test
    func loaderNeverFetchesLinksDetailsOrAttachments() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Entity", in: graph)
        let attribute = fixtures.makeAttribute(
            name: "Attribute",
            owner: entity
        )
        _ = fixtures.makeLink(
            source: .entity(entity),
            target: .attribute(attribute),
            graphID: graph.id
        )
        _ = fixtures.makeDetailField(
            owner: entity,
            name: "Status",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeAttachment(owner: .entity(entity))
        try fixtures.save()

        let loader = await configuredLoader(testStore)
        _ = try await loader.load(
            graphID: graph.id,
            recentItems: [
                recent(
                    graphID: graph.id,
                    kind: .attribute,
                    nodeID: attribute.id,
                    openedAt: 100
                )
            ],
            limit: 8
        )

        let metrics = await loader.lastLoadMetricsForTesting()
        #expect(metrics.fullGraphFetchCount == 0)
        #expect(metrics.linkFetchCount == 0)
        #expect(metrics.detailFieldFetchCount == 0)
        #expect(metrics.attachmentFetchCount == 0)
    }

    @Test
    func emptyHistoryNeedsNoConfiguredContainerOrFetch() async throws {
        let loader = EntitiesHomeRecentNodesLoader()

        let nodes = try await loader.load(
            graphID: UUID(),
            recentItems: [],
            limit: 8
        )

        #expect(nodes.isEmpty)
        #expect(
            await loader.lastLoadMetricsForTesting()
                == EntitiesHomeRecentNodesLoadMetrics.zero
        )
    }

    private func configuredLoader(
        _ testStore: BrainMeshTestStore
    ) async -> EntitiesHomeRecentNodesLoader {
        let loader = EntitiesHomeRecentNodesLoader()
        await loader.configure(
            container: AnyModelContainer(testStore.container)
        )
        return loader
    }

    private func recent(
        graphID: UUID,
        kind: NodeKind,
        nodeID: UUID,
        openedAt: TimeInterval
    ) -> RecentNodeItem {
        RecentNodeItem(
            graphID: graphID,
            nodeKindRaw: kind.rawValue,
            nodeID: nodeID,
            label: "Stored",
            iconSymbolName: "circle",
            openedAt: Date(timeIntervalSince1970: openedAt)
        )
    }
}
