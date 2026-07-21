import Foundation
import Testing
@testable import BrainMesh

struct GraphSearchIndexPerformanceTests {
    @Test
    func severalThousandDocumentsStayBehindBoundedIndexCandidateLimit() async throws {
        let graphID = UUID()
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback
        )

        do {
            _ = try await store.open()
            let documents = Self.makeEntityDocuments(
                graphID: graphID,
                count: 3_000,
                queryPrefix: "Atlas"
            )
            try await store.replaceDocuments(in: graphID, with: documents)

            let provider = IndexedSearchCandidateProvider(store: store)
            let response = try await provider.candidates(
                graphIDs: [graphID],
                foldedQuery: "atlas",
                resultLimit: 100
            )

            #expect(documents.count == 3_000)
            #expect(response.indexDocumentCount <= IndexedSearchCandidateProvider.maximumDocumentCandidateCount)
            #expect(response.candidates.count <= IndexedSearchCandidateProvider.maximumDocumentCandidateCount)
            #expect(IndexedSearchCandidateProvider.documentCandidateLimit(for: 100) == 500)
            #expect(response.candidates.allSatisfy { $0.result.graphID == graphID })

            try await store.close()
            location.remove()
        } catch {
            do {
                try await store.close()
            } catch let closeError {
                Issue.record("Failed to close performance test store: \(closeError)")
            }
            location.remove()
            throw error
        }
    }

    @Test
    func explicitMultiGraphScopeNeverReturnsDocumentsFromOtherGraphs() async throws {
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let excludedGraphID = UUID()
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback
        )

        do {
            _ = try await store.open()
            try await store.replaceDocuments(
                in: firstGraphID,
                with: Self.makeEntityDocuments(
                    graphID: firstGraphID,
                    count: 100,
                    queryPrefix: "Atlas First"
                )
            )
            try await store.replaceDocuments(
                in: secondGraphID,
                with: Self.makeEntityDocuments(
                    graphID: secondGraphID,
                    count: 100,
                    queryPrefix: "Atlas Second"
                )
            )
            try await store.replaceDocuments(
                in: excludedGraphID,
                with: Self.makeEntityDocuments(
                    graphID: excludedGraphID,
                    count: 100,
                    queryPrefix: "Atlas Excluded"
                )
            )

            let provider = IndexedSearchCandidateProvider(store: store)
            let response = try await provider.candidates(
                graphIDs: [secondGraphID, firstGraphID, firstGraphID],
                foldedQuery: "atlas",
                resultLimit: 100
            )
            let resultGraphIDs = Set(response.candidates.compactMap { $0.result.graphID })

            #expect(resultGraphIDs == Set([firstGraphID, secondGraphID]))
            #expect(response.candidates.contains { $0.result.graphID == excludedGraphID } == false)

            try await store.close()
            location.remove()
        } catch {
            do {
                try await store.close()
            } catch let closeError {
                Issue.record("Failed to close scoped performance test store: \(closeError)")
            }
            location.remove()
            throw error
        }
    }

    @Test
    func largeCandidateProcessingHonorsCancellation() async throws {
        let graphID = UUID()
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let cancellationGate = SearchCancellationGate()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback,
            cancellationCheck: {
                try cancellationGate.check()
            }
        )

        do {
            _ = try await store.open()
            let documents = Self.makeEntityDocuments(
                graphID: graphID,
                count: 3_000,
                queryPrefix: "Atlas"
            )
            try await store.replaceDocuments(in: graphID, with: documents)
            cancellationGate.enableCancellation(afterChecks: 4)

            let provider = IndexedSearchCandidateProvider(store: store)
            await #expect(throws: CancellationError.self) {
                _ = try await provider.candidates(
                    graphIDs: [graphID],
                    foldedQuery: "atlas",
                    resultLimit: 100
                )
            }

            cancellationGate.disableCancellation()
            try await store.close()
            location.remove()
        } catch {
            cancellationGate.disableCancellation()
            do {
                try await store.close()
            } catch let closeError {
                Issue.record("Failed to close cancellation performance test store: \(closeError)")
            }
            location.remove()
            throw error
        }
    }

    @Test
    func internalCandidateExpansionIsBoundedAndProportional() {
        #expect(GraphSearchIndexStore.internalCandidateLimit(for: 1) == 64)
        #expect(GraphSearchIndexStore.internalCandidateLimit(for: 10) == 80)
        #expect(GraphSearchIndexStore.internalCandidateLimit(for: 100) == 500)
        #expect(GraphSearchIndexStore.internalCandidateLimit(for: Int.max) == 500)
    }

    private static func makeEntityDocuments(
        graphID: UUID,
        count: Int,
        queryPrefix: String
    ) -> [GraphSearchDocument] {
        let fixture = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        return (0..<count).map { index in
            let id = graphSearchIndexerTestUUID(graphID: graphID, value: 10_000 + index)
            return fixture.entity(
                id: id,
                title: "\(queryPrefix) \(String(format: "%05d", index))",
                contentHash: "hash-\(index)"
            )
        }
    }
}

private final class SearchCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationCheckLimit: Int?
    private var checkCount = 0

    func enableCancellation(afterChecks limit: Int) {
        lock.lock()
        cancellationCheckLimit = max(0, limit)
        checkCount = 0
        lock.unlock()
    }

    func disableCancellation() {
        lock.lock()
        cancellationCheckLimit = nil
        checkCount = 0
        lock.unlock()
    }

    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let cancellationCheckLimit else { return }
        checkCount += 1
        if checkCount > cancellationCheckLimit {
            throw CancellationError()
        }
    }
}
