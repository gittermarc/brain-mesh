import Foundation
import Testing
@testable import BrainMesh

struct BrainMeshIndexedSearchServiceTests {
    @Test
    func healthyGraphUsesIndexWithoutCallingLegacyProvider() async throws {
        let graphID = UUID()
        let indexedResult = Self.result(
            kind: .entity,
            id: UUID(),
            graphID: graphID,
            title: "Atlas",
            matchReason: "Name"
        )
        let readiness = SearchReadinessStub(results: [graphID: .usable(graphID: graphID)])
        let indexed = IndexedCandidateStub(
            response: BrainMeshIndexedSearchCandidateResponse(
                candidates: [BrainMeshSearchCandidate(result: indexedResult, score: 0)],
                indexDocumentCount: 1
            )
        )
        let legacy = LegacyCandidateStub(candidates: [])
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: legacy
        )

        let snapshot = try await service.search(
            graphID: graphID,
            foldedQuery: "atlas",
            limit: 20
        )

        let legacyCalls = await legacy.callCount()
        let indexedScopes = await indexed.requestedGraphIDs()
        let readinessReasons = await readiness.reasons(for: graphID)
        #expect(snapshot.results == [indexedResult])
        #expect(legacyCalls == 0)
        #expect(indexedScopes == [[graphID]])
        #expect(readinessReasons == [.firstSearch])
    }

    @Test
    func unavailableGraphFallsBackWithoutCallingIndexProvider() async throws {
        let graphID = UUID()
        let legacyResult = Self.result(
            kind: .entity,
            id: UUID(),
            graphID: graphID,
            title: "Legacy Atlas",
            matchReason: "Name"
        )
        let readiness = SearchReadinessStub(results: [graphID: .unavailable(graphID: graphID)])
        let indexed = IndexedCandidateStub(response: .empty)
        let legacy = LegacyCandidateStub(
            candidates: [BrainMeshSearchCandidate(result: legacyResult, score: 0)]
        )
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: legacy
        )

        let snapshot = try await service.search(
            graphID: graphID,
            foldedQuery: "atlas",
            limit: 20
        )

        let indexedCalls = await indexed.callCount()
        let legacyCalls = await legacy.callCount()
        #expect(snapshot.results == [legacyResult])
        #expect(indexedCalls == 0)
        #expect(legacyCalls == 1)
    }

    @Test
    func failedIndexQueryInvalidatesGraphAndUsesTransparentFallback() async throws {
        let graphID = UUID()
        let legacyResult = Self.result(
            kind: .attribute,
            id: UUID(),
            graphID: graphID,
            title: "Launch Date",
            matchReason: "Attribut"
        )
        let readiness = SearchReadinessStub(results: [graphID: .usable(graphID: graphID)])
        let indexed = IndexedCandidateStub(
            response: .empty,
            shouldFail: true
        )
        let legacy = LegacyCandidateStub(
            candidates: [BrainMeshSearchCandidate(result: legacyResult, score: 0)]
        )
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: legacy
        )

        let snapshot = try await service.search(
            graphID: graphID,
            foldedQuery: "launch",
            limit: 20
        )

        let invalidations = await readiness.invalidations(for: graphID)
        let legacyCalls = await legacy.callCount()
        #expect(snapshot.results == [legacyResult])
        #expect(invalidations == [.indexFailure])
        #expect(legacyCalls == 1)
    }

    @Test
    func globalSearchUsesIndexOnlyWhenEveryRelevantGraphIsUsable() async throws {
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let firstResult = Self.result(
            kind: .entity,
            id: UUID(),
            graphID: firstGraphID,
            title: "Atlas Alpha",
            matchReason: "Name"
        )
        let secondResult = Self.result(
            kind: .entity,
            id: UUID(),
            graphID: secondGraphID,
            title: "Atlas Beta",
            matchReason: "Name"
        )
        let readiness = SearchReadinessStub(
            results: [
                firstGraphID: .usable(graphID: firstGraphID),
                secondGraphID: .usable(graphID: secondGraphID)
            ]
        )
        let indexed = IndexedCandidateStub(
            response: BrainMeshIndexedSearchCandidateResponse(
                candidates: [
                    BrainMeshSearchCandidate(result: secondResult, score: 0),
                    BrainMeshSearchCandidate(result: firstResult, score: 0)
                ],
                indexDocumentCount: 2
            )
        )
        let legacy = LegacyCandidateStub(candidates: [])
        let resolver = ScopeResolverStub(
            resolution: BrainMeshSearchGraphScopeResolution(
                graphIDs: [secondGraphID, firstGraphID],
                canUseIndex: true,
                fallbackReason: nil
            )
        )
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: legacy,
            resolver: resolver
        )

        let snapshot = try await service.search(
            graphID: nil,
            foldedQuery: "atlas",
            limit: 20
        )

        let requestedScopes = await indexed.requestedGraphIDs()
        let legacyCalls = await legacy.callCount()
        #expect(snapshot.results == [firstResult, secondResult])
        #expect(requestedScopes == [[firstGraphID, secondGraphID].sorted(by: Self.uuidSort)])
        #expect(legacyCalls == 0)
    }

    @Test
    func globalSearchFallsBackForWholeRequestWhenOneGraphIsUnavailable() async throws {
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let legacyResult = Self.result(
            kind: .link,
            id: UUID(),
            graphID: firstGraphID,
            title: "Atlas → Beacon",
            matchReason: "Verbindung"
        )
        let readiness = SearchReadinessStub(
            results: [
                firstGraphID: .usable(graphID: firstGraphID),
                secondGraphID: .unavailable(graphID: secondGraphID)
            ]
        )
        let indexed = IndexedCandidateStub(response: .empty)
        let legacy = LegacyCandidateStub(
            candidates: [BrainMeshSearchCandidate(result: legacyResult, score: 0)]
        )
        let resolver = ScopeResolverStub(
            resolution: BrainMeshSearchGraphScopeResolution(
                graphIDs: [firstGraphID, secondGraphID],
                canUseIndex: true,
                fallbackReason: nil
            )
        )
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: legacy,
            resolver: resolver
        )

        let snapshot = try await service.search(
            graphID: nil,
            foldedQuery: "atlas",
            limit: 20
        )

        let indexedCalls = await indexed.callCount()
        let legacyGraphIDs = await legacy.requestedGraphIDs()
        #expect(snapshot.results == [legacyResult])
        #expect(indexedCalls == 0)
        #expect(legacyGraphIDs == [nil])
    }

    @Test
    func unsafeGlobalScopeUsesLegacyWithoutReadinessWork() async throws {
        let graphID = UUID()
        let readiness = SearchReadinessStub(results: [graphID: .usable(graphID: graphID)])
        let indexed = IndexedCandidateStub(response: .empty)
        let legacy = LegacyCandidateStub(candidates: [])
        let resolver = ScopeResolverStub(
            resolution: BrainMeshSearchGraphScopeResolution(
                graphIDs: [graphID],
                canUseIndex: false,
                fallbackReason: .unscopedLegacySources
            )
        )
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: legacy,
            resolver: resolver
        )

        _ = try await service.search(
            graphID: nil,
            foldedQuery: "atlas",
            limit: 20
        )

        let readinessCalls = await readiness.totalEnsureCallCount()
        let indexedCalls = await indexed.callCount()
        let legacyCalls = await legacy.callCount()
        #expect(readinessCalls == 0)
        #expect(indexedCalls == 0)
        #expect(legacyCalls == 1)
    }

    @Test
    func indexCandidatesStillUseEstablishedRankingAndPublicLimit() async throws {
        let graphID = UUID()
        let beta = Self.result(
            kind: .entity,
            id: UUID(),
            graphID: graphID,
            title: "Atlas Beta",
            matchReason: "Name"
        )
        let exact = Self.result(
            kind: .attribute,
            id: UUID(),
            graphID: graphID,
            title: "Atlas",
            matchReason: "Attribut"
        )
        let alpha = Self.result(
            kind: .entity,
            id: UUID(),
            graphID: graphID,
            title: "Atlas Alpha",
            matchReason: "Name"
        )
        let readiness = SearchReadinessStub(results: [graphID: .usable(graphID: graphID)])
        let indexed = IndexedCandidateStub(
            response: BrainMeshIndexedSearchCandidateResponse(
                candidates: [
                    BrainMeshSearchCandidate(result: beta, score: 1),
                    BrainMeshSearchCandidate(result: exact, score: 0),
                    BrainMeshSearchCandidate(result: alpha, score: 1)
                ],
                indexDocumentCount: 3
            )
        )
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: LegacyCandidateStub(candidates: [])
        )

        let snapshot = try await service.search(
            graphID: graphID,
            foldedQuery: "atlas",
            limit: 2
        )

        #expect(snapshot.results == [exact, alpha])
    }

    @Test
    func searchCancellationDoesNotFallBackAsSuccessfulEmptySearch() async throws {
        let graphID = UUID()
        let readiness = SearchReadinessStub(
            results: [graphID: .usable(graphID: graphID)],
            delayNanoseconds: 1_000_000_000
        )
        let indexed = IndexedCandidateStub(response: .empty)
        let legacy = LegacyCandidateStub(candidates: [])
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: legacy
        )

        let task = Task {
            try await service.search(
                graphID: graphID,
                foldedQuery: "atlas",
                limit: 20
            )
        }
        await Task.yield()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        let indexedCalls = await indexed.callCount()
        let legacyCalls = await legacy.callCount()
        #expect(indexedCalls == 0)
        #expect(legacyCalls == 0)
    }

    @Test
    func legacyFallbackCancellationPropagatesWithoutSuccessfulSnapshot() async throws {
        let graphID = UUID()
        let readiness = SearchReadinessStub(
            results: [graphID: .unavailable(graphID: graphID)]
        )
        let indexed = IndexedCandidateStub(response: .empty)
        let legacy = LegacyCandidateStub(
            candidates: [],
            delayNanoseconds: 1_000_000_000
        )
        let service = try await Self.makeService(
            readiness: readiness,
            indexed: indexed,
            legacy: legacy
        )

        let task = Task {
            try await service.search(
                graphID: graphID,
                foldedQuery: "atlas",
                limit: 20
            )
        }
        await Task.yield()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        let indexedCalls = await indexed.callCount()
        #expect(indexedCalls == 0)
    }

    @Test
    func realIndexMatchesLegacyResultsForAllExistingResultKinds() async throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(
            name: "Project Atlas",
            in: graph,
            notes: "Orbit planning",
            iconSymbolName: "star"
        )
        let attribute = fixtures.makeAttribute(
            name: "Launch Date",
            owner: entity,
            notes: "Gold milestone",
            iconSymbolName: "calendar.badge.clock"
        )
        _ = fixtures.makeLink(
            source: .entity(entity),
            target: .attribute(attribute),
            note: "Beacon connection"
        )
        let field = fixtures.makeDetailField(
            owner: entity,
            name: "Risk Level",
            type: .singleLineText,
            sortIndex: 0
        )
        _ = fixtures.makeDetailValue(
            attribute: attribute,
            field: field,
            stringValue: "Critical"
        )
        _ = fixtures.makeAttachment(
            owner: .entity(entity),
            contentKind: .file,
            title: "Launch Blueprint",
            originalFilename: "blueprint.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf"
        )
        try fixtures.save()

        let location = try GraphSearchIndexTestSupport.makeLocation()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback
        )
        let repository = GraphReadRepository(
            container: AnyModelContainer(testStore.container)
        )
        let indexer = GraphSearchIndexer(
            sourceReader: repository,
            store: store,
            subscriber: GraphMutationEventBus()
        )
        let reconciler = GraphSearchIndexReconciler(
            sourceReader: repository,
            store: store,
            indexer: indexer
        )
        await indexer.setReadinessInvalidator(reconciler)

        let legacyService = BrainMeshSearchService()
        await legacyService.configure(container: AnyModelContainer(testStore.container))
        let indexedService = BrainMeshSearchService(
            dependencies: BrainMeshSearchServiceDependencies(
                readinessProvider: reconciler,
                indexedProvider: IndexedSearchCandidateProvider(store: store),
                legacyProvider: LiveBrainMeshLegacySearchCandidateProvider(),
                scopeResolver: LiveBrainMeshSearchGraphScopeResolver()
            )
        )
        await indexedService.configure(container: AnyModelContainer(testStore.container))

        do {
            let queries = [
                "project",
                "orbit",
                "launch",
                "gold",
                "beacon",
                "risk",
                "critical",
                "blueprint"
            ]
            for query in queries {
                let legacySnapshot = try await legacyService.search(
                    graphID: graph.id,
                    foldedQuery: query,
                    limit: 100
                )
                let indexedSnapshot = try await indexedService.search(
                    graphID: graph.id,
                    foldedQuery: query,
                    limit: 100
                )
                #expect(indexedSnapshot.results == legacySnapshot.results)
            }

            await reconciler.resetForTesting()
            await indexer.resetForTesting()
            try await store.close()
            location.remove()
        } catch {
            await reconciler.resetForTesting()
            await indexer.resetForTesting()
            do {
                try await store.close()
            } catch let closeError {
                Issue.record("Failed to close indexed search parity store: \(closeError)")
            }
            location.remove()
            throw error
        }
    }

    private static func makeService(
        readiness: any BrainMeshSearchIndexReadinessProviding,
        indexed: any BrainMeshIndexedSearchCandidateProviding,
        legacy: any BrainMeshLegacySearchCandidateProviding,
        resolver: (any BrainMeshSearchGraphScopeResolving)? = nil
    ) async throws -> BrainMeshSearchService {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let resolvedScopeResolver = resolver ?? ScopeResolverStub(
            resolution: BrainMeshSearchGraphScopeResolution(
                graphIDs: [],
                canUseIndex: true,
                fallbackReason: nil
            )
        )
        let service = BrainMeshSearchService(
            dependencies: BrainMeshSearchServiceDependencies(
                readinessProvider: readiness,
                indexedProvider: indexed,
                legacyProvider: legacy,
                scopeResolver: resolvedScopeResolver
            )
        )
        await service.configure(container: AnyModelContainer(testStore.container))
        return service
    }

    private static func result(
        kind: BrainMeshSearchResultKind,
        id: UUID,
        graphID: UUID,
        title: String,
        matchReason: String
    ) -> BrainMeshSearchResult {
        BrainMeshSearchResult(
            kind: kind,
            id: id,
            graphID: graphID,
            title: title,
            subtitle: kind == .entity ? "Entität" : "Subtitle",
            iconSymbolName: kind.defaultIconSymbolName,
            matchReason: matchReason,
            nodeKindRaw: kind == .entity ? NodeKind.entity.rawValue : nil,
            nodeID: kind == .entity ? id : nil,
            ownerKindRaw: nil,
            ownerID: nil
        )
    }

    private static func uuidSort(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

private actor SearchReadinessStub: BrainMeshSearchIndexReadinessProviding {
    private let results: [UUID: GraphSearchIndexReadinessResult]
    private let delayNanoseconds: UInt64
    private var ensureReasons: [UUID: [GraphSearchIndexReconciliationReason]] = [:]
    private var invalidationReasons: [UUID: [GraphSearchIndexReconciliationReason]] = [:]

    init(
        results: [UUID: GraphSearchIndexReadinessResult],
        delayNanoseconds: UInt64 = 0
    ) {
        self.results = results
        self.delayNanoseconds = delayNanoseconds
    }

    func ensureReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult {
        ensureReasons[scope.graphID, default: []].append(reason)
        if delayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return .cancelled(graphID: scope.graphID, reason: reason)
            }
        }
        return results[scope.graphID]
            ?? .unavailable(graphID: scope.graphID)
    }

    func invalidate(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async {
        invalidationReasons[scope.graphID, default: []].append(reason)
    }

    func reasons(for graphID: UUID) -> [GraphSearchIndexReconciliationReason] {
        ensureReasons[graphID, default: []]
    }

    func invalidations(for graphID: UUID) -> [GraphSearchIndexReconciliationReason] {
        invalidationReasons[graphID, default: []]
    }

    func totalEnsureCallCount() -> Int {
        ensureReasons.values.reduce(0) { $0 + $1.count }
    }
}

private actor IndexedCandidateStub: BrainMeshIndexedSearchCandidateProviding {
    private let response: BrainMeshIndexedSearchCandidateResponse
    private let shouldFail: Bool
    private var graphIDRequests: [[UUID]] = []

    init(
        response: BrainMeshIndexedSearchCandidateResponse = .empty,
        shouldFail: Bool = false
    ) {
        self.response = response
        self.shouldFail = shouldFail
    }

    func candidates(
        graphIDs: [UUID],
        foldedQuery: String,
        resultLimit: Int
    ) async throws -> BrainMeshIndexedSearchCandidateResponse {
        graphIDRequests.append(graphIDs)
        if shouldFail {
            throw IndexedCandidateStubFailure.injected
        }
        return response
    }

    func callCount() -> Int {
        graphIDRequests.count
    }

    func requestedGraphIDs() -> [[UUID]] {
        graphIDRequests
    }
}

private enum IndexedCandidateStubFailure: Error, Sendable {
    case injected
}

private actor LegacyCandidateStub: BrainMeshLegacySearchCandidateProviding {
    private let storedCandidates: [BrainMeshSearchCandidate]
    private let delayNanoseconds: UInt64
    private var graphIDRequests: [UUID?] = []

    init(
        candidates: [BrainMeshSearchCandidate],
        delayNanoseconds: UInt64 = 0
    ) {
        storedCandidates = candidates
        self.delayNanoseconds = delayNanoseconds
    }

    func candidates(
        container: AnyModelContainer,
        graphID: UUID?,
        foldedQuery: String
    ) async throws -> [BrainMeshSearchCandidate] {
        graphIDRequests.append(graphID)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return storedCandidates
    }

    func callCount() -> Int {
        graphIDRequests.count
    }

    func requestedGraphIDs() -> [UUID?] {
        graphIDRequests
    }
}

private actor ScopeResolverStub: BrainMeshSearchGraphScopeResolving {
    private let resolution: BrainMeshSearchGraphScopeResolution

    init(resolution: BrainMeshSearchGraphScopeResolution) {
        self.resolution = resolution
    }

    func resolveGlobalScope(
        container: AnyModelContainer
    ) async throws -> BrainMeshSearchGraphScopeResolution {
        resolution
    }
}

private extension GraphSearchIndexReadinessResult {
    static func usable(graphID: UUID) -> GraphSearchIndexReadinessResult {
        GraphSearchIndexReadinessResult(
            graphID: graphID,
            reason: .firstSearch,
            outcome: .ready,
            isIndexUsable: true,
            documentCount: 1,
            metrics: nil,
            failure: nil
        )
    }

    static func unavailable(graphID: UUID) -> GraphSearchIndexReadinessResult {
        GraphSearchIndexReadinessResult(
            graphID: graphID,
            reason: .firstSearch,
            outcome: .unavailable,
            isIndexUsable: false,
            documentCount: nil,
            metrics: nil,
            failure: nil
        )
    }
}

private extension BrainMeshIndexedSearchCandidateResponse {
    static let empty = BrainMeshIndexedSearchCandidateResponse(
        candidates: [],
        indexDocumentCount: 0
    )
}
