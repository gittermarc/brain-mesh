import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeIndexedSearchParityTests {
    @Test
    func indexedAndSwiftDataPathsHaveParityForAllSupportedMatchFamilies() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let alpha = fixtures.makeEntity(
            name: "Alpha",
            in: graph,
            notes: "Contains hidden comet detail"
        )
        let atlas = fixtures.makeEntity(
            name: "Project Atlas",
            in: graph
        )
        let launchDate = fixtures.makeAttribute(
            name: "Launch Date",
            owner: atlas,
            notes: "Requires ember follow-up"
        )
        let zeta = fixtures.makeEntity(name: "Zeta", in: graph)
        let link = fixtures.makeLink(
            source: .entity(alpha),
            target: .attribute(launchDate),
            note: "Shared bridge context"
        )
        try fixtures.save()

        let indexFixtures = GraphSearchIndexDocumentFixtureBuilder(
            graphID: graph.id
        )
        let indexedDocuments = [
            indexFixtures.entity(id: alpha.id, title: alpha.name),
            indexFixtures.entityNotes(
                entityID: alpha.id,
                entityTitle: alpha.name,
                notes: alpha.notes
            ),
            indexFixtures.entity(id: atlas.id, title: atlas.name),
            indexFixtures.entity(id: zeta.id, title: zeta.name),
            indexFixtures.attribute(
                id: launchDate.id,
                ownerID: atlas.id,
                ownerTitle: atlas.name,
                title: launchDate.name
            ),
            indexFixtures.attributeNotes(
                attributeID: launchDate.id,
                ownerID: atlas.id,
                ownerTitle: atlas.name,
                attributeTitle: launchDate.name,
                notes: launchDate.notes
            ),
            indexFixtures.linkNotes(
                linkID: link.id,
                source: GraphSearchNodeReference(
                    kind: .entity,
                    id: alpha.id,
                    label: alpha.name
                ),
                target: GraphSearchNodeReference(
                    kind: .attribute,
                    id: launchDate.id,
                    label: launchDate.displayName
                ),
                notes: link.note ?? ""
            )
        ]

        try await withIndexedLoader(
            testStore: testStore,
            graphID: graph.id,
            documents: indexedDocuments
        ) { loader in
            let queries = [
                "alpha",
                "comet",
                "launch",
                "ember",
                "bridge",
                "project"
            ]

            for query in queries {
                let foldedQuery = BMSearch.fold(query)
                let fallback = try EntitiesHomeLoader
                    .fetchEntitiesUsingSwiftDataFallback(
                        context: testStore.context,
                        graphID: graph.id,
                        foldedSearch: foldedQuery
                    )
                let indexed = try await loader.loadSnapshot(
                    activeGraphID: graph.id,
                    foldedSearch: foldedQuery,
                    includeAttributeCounts: false,
                    includeLinkCounts: false,
                    includeNotesPreview: false
                )

                let fallbackMatches = fallback.map {
                    ComparableEntityMatch(
                        entityID: $0.entity.id,
                        isNotesOnly: $0.isNotesOnlyHit
                    )
                }
                let indexedMatches = indexed.rows.map {
                    ComparableEntityMatch(
                        entityID: $0.id,
                        isNotesOnly: $0.isNotesOnlyHit
                    )
                }
                #expect(
                    indexedMatches == fallbackMatches,
                    "Parity mismatch for query \(query)"
                )
            }
        }
    }

    @Test
    func incompleteUnavailableAndFailedIndexResultsUseSwiftDataFallback() async throws {
        let completenessValues: [EntitiesHomeIndexedResultCompleteness] = [
            .potentiallyTruncated,
            .indexUnavailable,
            .reconciliationFailed,
            .ownerResolutionIncomplete
        ]

        for completeness in completenessValues {
            let testStore = try BrainMeshTestContainer.makeInMemoryStore()
            let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
            let graph = fixtures.makeGraph(name: "Primary")
            let entity = fixtures.makeEntity(name: "Legacy Atlas", in: graph)
            try fixtures.save()

            let provider = EntitiesHomeIndexedProviderStub(
                behavior: .result(
                    EntitiesHomeIndexedMatchResult(
                        matches: [],
                        completeness: completeness,
                        indexDocumentCount: 0
                    )
                )
            )
            let loader = EntitiesHomeLoader(indexedMatchProvider: provider)
            await loader.configure(
                container: AnyModelContainer(testStore.container)
            )

            let snapshot = try await loader.loadSnapshot(
                activeGraphID: graph.id,
                foldedSearch: BMSearch.fold("atlas"),
                includeAttributeCounts: false,
                includeLinkCounts: false,
                includeNotesPreview: false
            )

            #expect(
                snapshot.rows.map(\.id) == [entity.id],
                "Fallback mismatch for \(completeness.rawValue)"
            )
        }
    }

    @Test
    func indexQueryFailureUsesSwiftDataFallback() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Legacy Atlas", in: graph)
        try fixtures.save()

        let provider = EntitiesHomeIndexedProviderStub(
            behavior: .failure
        )
        let loader = EntitiesHomeLoader(indexedMatchProvider: provider)
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            activeGraphID: graph.id,
            foldedSearch: BMSearch.fold("atlas"),
            includeAttributeCounts: false,
            includeLinkCounts: false,
            includeNotesPreview: false
        )

        #expect(snapshot.rows.map(\.id) == [entity.id])
    }

    @Test
    func unopenedIndexStoreUsesSwiftDataFallback() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Legacy Atlas", in: graph)
        try fixtures.save()

        let location = try GraphSearchIndexTestSupport.makeLocation()
        defer { location.remove() }
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback
        )
        let readiness = EntitiesHomeParityReadinessStub(graphID: graph.id)
        let ownerResolver = EntitiesHomeAttributeOwnerResolver()
        await ownerResolver.configure(
            container: AnyModelContainer(testStore.container)
        )
        let provider = EntitiesHomeIndexedMatchProvider(
            store: store,
            readinessProvider: readiness,
            attributeOwnerResolver: ownerResolver
        )
        let loader = EntitiesHomeLoader(indexedMatchProvider: provider)
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            activeGraphID: graph.id,
            foldedSearch: BMSearch.fold("atlas"),
            includeAttributeCounts: false,
            includeLinkCounts: false,
            includeNotesPreview: false
        )

        #expect(snapshot.rows.map(\.id) == [entity.id])
    }

    @Test
    func cancellationIsPropagatedWithoutStartingFallback() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let _ = fixtures.makeEntity(name: "Legacy Atlas", in: graph)
        try fixtures.save()

        let provider = EntitiesHomeIndexedProviderStub(
            behavior: .cancellation
        )
        let loader = EntitiesHomeLoader(indexedMatchProvider: provider)
        await loader.configure(container: AnyModelContainer(testStore.container))

        await #expect(throws: CancellationError.self) {
            try await loader.loadSnapshot(
                activeGraphID: graph.id,
                foldedSearch: BMSearch.fold("atlas"),
                includeAttributeCounts: false,
                includeLinkCounts: false,
                includeNotesPreview: false
            )
        }
    }

    @Test
    func indexedResolutionIgnoresDeletedAndForeignEntities() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let primaryGraph = fixtures.makeGraph(name: "Primary")
        let foreignGraph = fixtures.makeGraph(name: "Foreign")
        let current = fixtures.makeEntity(name: "Current", in: primaryGraph)
        let foreign = fixtures.makeEntity(name: "Foreign", in: foreignGraph)
        let deletedID = UUID()
        try fixtures.save()

        let provider = EntitiesHomeIndexedProviderStub(
            behavior: .result(
                EntitiesHomeIndexedMatchResult(
                    matches: [
                        EntitiesHomeIndexedMatch(
                            entityID: current.id,
                            classification: .strong,
                            origins: [.entitySource]
                        ),
                        EntitiesHomeIndexedMatch(
                            entityID: foreign.id,
                            classification: .strong,
                            origins: [.entitySource]
                        ),
                        EntitiesHomeIndexedMatch(
                            entityID: deletedID,
                            classification: .notesOnly,
                            origins: [.linkNotes]
                        )
                    ],
                    completeness: .complete,
                    indexDocumentCount: 3
                )
            )
        )
        let loader = EntitiesHomeLoader(indexedMatchProvider: provider)
        await loader.configure(container: AnyModelContainer(testStore.container))

        let snapshot = try await loader.loadSnapshot(
            activeGraphID: primaryGraph.id,
            foldedSearch: "current",
            includeAttributeCounts: false,
            includeLinkCounts: false,
            includeNotesPreview: false
        )

        #expect(snapshot.rows.map(\.id) == [current.id])
    }

    @Test
    func emptyAndLegacyUnscopedSearchesDoNotUseIndexProvider() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Atlas", in: graph)
        try fixtures.save()

        let provider = EntitiesHomeIndexedProviderStub(
            behavior: .failure
        )
        let loader = EntitiesHomeLoader(indexedMatchProvider: provider)
        await loader.configure(container: AnyModelContainer(testStore.container))

        let emptySearch = try await loader.loadSnapshot(
            activeGraphID: graph.id,
            foldedSearch: "",
            includeAttributeCounts: false,
            includeLinkCounts: false,
            includeNotesPreview: false
        )
        let unscopedSearch = try await loader.loadSnapshot(
            activeGraphID: nil,
            foldedSearch: BMSearch.fold("atlas"),
            includeAttributeCounts: false,
            includeLinkCounts: false,
            includeNotesPreview: false
        )
        let providerCallCount = await provider.callCount()

        #expect(emptySearch.rows.map(\.id) == [entity.id])
        #expect(unscopedSearch.rows.map(\.id) == [entity.id])
        #expect(providerCallCount == 0)
    }

    private func withIndexedLoader<T>(
        testStore: BrainMeshTestStore,
        graphID: UUID,
        documents: [GraphSearchDocument],
        operation: (EntitiesHomeLoader) async throws -> T
    ) async throws -> T {
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback
        )
        let readiness = EntitiesHomeParityReadinessStub(graphID: graphID)
        let ownerResolver = EntitiesHomeAttributeOwnerResolver()
        await ownerResolver.configure(
            container: AnyModelContainer(testStore.container)
        )
        let provider = EntitiesHomeIndexedMatchProvider(
            store: store,
            readinessProvider: readiness,
            attributeOwnerResolver: ownerResolver
        )
        let loader = EntitiesHomeLoader(indexedMatchProvider: provider)
        await loader.configure(container: AnyModelContainer(testStore.container))

        do {
            _ = try await store.open()
            try await store.upsert(documents)
            let result = try await operation(loader)
            try await store.close()
            location.remove()
            return result
        } catch {
            do {
                try await store.close()
            } catch let closeError {
                Issue.record(
                    "Failed to close Entities Home parity store: \(closeError)"
                )
            }
            location.remove()
            throw error
        }
    }
}

private struct ComparableEntityMatch: Equatable {
    let entityID: UUID
    let isNotesOnly: Bool
}

private actor EntitiesHomeParityReadinessStub:
    BrainMeshSearchIndexReadinessProviding
{
    private let graphID: UUID

    init(graphID: UUID) {
        self.graphID = graphID
    }

    func ensureReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult {
        GraphSearchIndexReadinessResult(
            graphID: graphID,
            reason: reason,
            outcome: .ready,
            isIndexUsable: true,
            documentCount: nil,
            metrics: nil,
            failure: nil
        )
    }

    func invalidate(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async {}
}

private actor EntitiesHomeIndexedProviderStub:
    EntitiesHomeIndexedMatchProviding
{
    enum Behavior: Sendable {
        case result(EntitiesHomeIndexedMatchResult)
        case failure
        case cancellation
    }

    private let behavior: Behavior
    private var calls = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func matches(
        graphID: UUID,
        foldedQuery: String
    ) async throws -> EntitiesHomeIndexedMatchResult {
        calls += 1
        switch behavior {
        case .result(let result):
            return result
        case .failure:
            throw EntitiesHomeIndexedProviderStubError.injected
        case .cancellation:
            throw CancellationError()
        }
    }

    func callCount() -> Int {
        calls
    }
}

private enum EntitiesHomeIndexedProviderStubError: Error, Sendable {
    case injected
}
