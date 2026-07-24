import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeIndexedMatchProviderTests {
    @Test
    func entityNameProducesStrongMatch() async throws {
        let graphID = UUID()
        let entityID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)

        try await withProvider(
            graphID: graphID,
            documents: [
                fixtures.entity(
                    id: entityID,
                    title: "Atlas",
                    searchableText: "Atlas"
                )
            ]
        ) { provider, _ in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "atlas"
            )

            #expect(result.completeness == .complete)
            #expect(result.matches == [
                EntitiesHomeIndexedMatch(
                    entityID: entityID,
                    classification: .strong,
                    origins: [.entitySource]
                )
            ])
        }
    }

    @Test
    func entityNotesProduceNotesOnlyMatch() async throws {
        let graphID = UUID()
        let entityID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)

        try await withProvider(
            graphID: graphID,
            documents: [
                fixtures.entityNotes(
                    entityID: entityID,
                    entityTitle: "Atlas",
                    notes: "Hidden comet detail"
                )
            ]
        ) { provider, _ in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "comet"
            )

            #expect(result.matches.first?.entityID == entityID)
            #expect(result.matches.first?.classification == .notesOnly)
            #expect(result.matches.first?.origins == [.entityNotes])
        }
    }

    @Test
    func attributeLabelProducesStrongOwnerMatch() async throws {
        let graphID = UUID()
        let entityID = UUID()
        let attributeID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)

        try await withProvider(
            graphID: graphID,
            documents: [
                fixtures.attribute(
                    id: attributeID,
                    ownerID: entityID,
                    ownerTitle: "Project Atlas",
                    title: "Launch Date"
                )
            ],
            ownerEntityIDsByAttributeID: [attributeID: entityID]
        ) { provider, resolver in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "launch"
            )

            #expect(result.matches.first?.entityID == entityID)
            #expect(result.matches.first?.classification == .strong)
            #expect(result.matches.first?.origins == [.attributeSource])
            let resolverCallCount = await resolver.callCount()
            #expect(resolverCallCount == 1)
        }
    }

    @Test
    func attributeNotesProduceNotesOnlyOwnerMatch() async throws {
        let graphID = UUID()
        let entityID = UUID()
        let attributeID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)

        try await withProvider(
            graphID: graphID,
            documents: [
                fixtures.attributeNotes(
                    attributeID: attributeID,
                    ownerID: entityID,
                    ownerTitle: "Project Atlas",
                    attributeTitle: "Status",
                    notes: "Requires ember follow-up"
                )
            ],
            ownerEntityIDsByAttributeID: [attributeID: entityID]
        ) { provider, _ in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "ember"
            )

            #expect(result.matches.first?.entityID == entityID)
            #expect(result.matches.first?.classification == .notesOnly)
            #expect(result.matches.first?.origins == [.attributeNotes])
        }
    }

    @Test
    func linkNotesWithTwoEntityEndpointsProduceBothEntities() async throws {
        let graphID = UUID()
        let sourceID = UUID()
        let targetID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let linkNotes = fixtures.linkNotes(
            linkID: UUID(),
            source: GraphSearchNodeReference(
                kind: .entity,
                id: sourceID,
                label: "Alpha"
            ),
            target: GraphSearchNodeReference(
                kind: .entity,
                id: targetID,
                label: "Beta"
            ),
            notes: "Shared bridge context"
        )

        try await withProvider(
            graphID: graphID,
            documents: [linkNotes]
        ) { provider, resolver in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "bridge"
            )

            #expect(
                Set(result.matches.map(\.entityID))
                    == Set([sourceID, targetID])
            )
            #expect(result.matches.allSatisfy {
                $0.classification == .notesOnly
                    && $0.origins == [.linkNotes]
            })
            let resolverCallCount = await resolver.callCount()
            #expect(resolverCallCount == 0)
        }
    }

    @Test
    func linkNotesWithEntityAndAttributeResolveAttributeOwnerOnce() async throws {
        let graphID = UUID()
        let sourceEntityID = UUID()
        let attributeID = UUID()
        let ownerEntityID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let linkNotes = fixtures.linkNotes(
            linkID: UUID(),
            source: GraphSearchNodeReference(
                kind: .entity,
                id: sourceEntityID,
                label: "Alpha"
            ),
            target: GraphSearchNodeReference(
                kind: .attribute,
                id: attributeID,
                label: "Gamma · Leaf"
            ),
            notes: "Shared bridge context"
        )

        try await withProvider(
            graphID: graphID,
            documents: [linkNotes],
            ownerEntityIDsByAttributeID: [attributeID: ownerEntityID]
        ) { provider, resolver in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "bridge"
            )

            #expect(
                Set(result.matches.map(\.entityID))
                    == Set([sourceEntityID, ownerEntityID])
            )
            let resolverCallCount = await resolver.callCount()
            let resolverRequests = await resolver.requestedAttributeIDs()
            #expect(resolverCallCount == 1)
            #expect(resolverRequests == [[attributeID]])
        }
    }

    @Test
    func linkNotesWithTwoAttributesResolveBothOwnersInOneRequest() async throws {
        let graphID = UUID()
        let firstAttributeID = UUID()
        let secondAttributeID = UUID()
        let firstOwnerID = UUID()
        let secondOwnerID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let linkNotes = fixtures.linkNotes(
            linkID: UUID(),
            source: GraphSearchNodeReference(
                kind: .attribute,
                id: firstAttributeID,
                label: "Alpha · Leaf"
            ),
            target: GraphSearchNodeReference(
                kind: .attribute,
                id: secondAttributeID,
                label: "Beta · Leaf"
            ),
            notes: "Shared bridge context"
        )

        try await withProvider(
            graphID: graphID,
            documents: [linkNotes],
            ownerEntityIDsByAttributeID: [
                firstAttributeID: firstOwnerID,
                secondAttributeID: secondOwnerID
            ]
        ) { provider, resolver in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "bridge"
            )

            #expect(
                Set(result.matches.map(\.entityID))
                    == Set([firstOwnerID, secondOwnerID])
            )
            let resolverCallCount = await resolver.callCount()
            let resolverRequests = await resolver.requestedAttributeIDs()
            #expect(resolverCallCount == 1)
            #expect(
                Set(resolverRequests.first ?? [])
                    == Set([firstAttributeID, secondAttributeID])
            )
        }
    }

    @Test
    func matchesAreDeduplicatedAndStrongOverridesNotesOnly() async throws {
        let graphID = UUID()
        let entityID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let documents = [
            fixtures.entity(
                id: entityID,
                title: "Bridge Atlas",
                searchableText: "Bridge Atlas"
            ),
            fixtures.entityNotes(
                entityID: entityID,
                entityTitle: "Bridge Atlas",
                notes: "Bridge notes"
            ),
            fixtures.linkNotes(
                linkID: UUID(),
                source: GraphSearchNodeReference(
                    kind: .entity,
                    id: entityID,
                    label: "Bridge Atlas"
                ),
                target: GraphSearchNodeReference(
                    kind: .entity,
                    id: entityID,
                    label: "Bridge Atlas"
                ),
                notes: "Bridge relationship"
            )
        ]

        try await withProvider(
            graphID: graphID,
            documents: documents
        ) { provider, _ in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "bridge"
            )

            #expect(result.matches.count == 1)
            #expect(result.matches.first?.entityID == entityID)
            #expect(result.matches.first?.classification == .strong)
            #expect(
                result.matches.first?.origins
                    == [.entitySource, .entityNotes, .linkNotes]
            )
        }
    }

    @Test
    func foreignGraphsAreExcludedCompletely() async throws {
        let graphID = UUID()
        let otherGraphID = UUID()
        let includedID = UUID()
        let excludedID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let otherFixtures = GraphSearchIndexDocumentFixtureBuilder(
            graphID: otherGraphID
        )

        try await withProvider(
            graphID: graphID,
            documents: [
                fixtures.entity(
                    id: includedID,
                    title: "Atlas Primary"
                ),
                otherFixtures.entity(
                    id: excludedID,
                    title: "Atlas Foreign"
                )
            ]
        ) { provider, _ in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "atlas"
            )

            #expect(result.matches.map(\.entityID) == [includedID])
        }
    }

    @Test
    func missingOrDeletedAttributeMakesOwnerResolutionIncomplete() async throws {
        let graphID = UUID()
        let attributeID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let linkNotes = fixtures.linkNotes(
            linkID: UUID(),
            source: GraphSearchNodeReference(
                kind: .attribute,
                id: attributeID,
                label: "Deleted Attribute"
            ),
            target: GraphSearchNodeReference(
                kind: .attribute,
                id: attributeID,
                label: "Deleted Attribute"
            ),
            notes: "Orphan bridge"
        )

        try await withProvider(
            graphID: graphID,
            documents: [linkNotes],
            ownerEntityIDsByAttributeID: [:]
        ) { provider, _ in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "orphan"
            )

            #expect(result.matches.isEmpty)
            #expect(result.completeness == .ownerResolutionIncomplete)
        }
    }

    @Test
    func detailAttachmentAndLinkLabelDocumentsCannotProduceMatches() async throws {
        let graphID = UUID()
        let ownerID = UUID()
        let fieldID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let source = GraphSearchNodeReference(
            kind: .entity,
            id: ownerID,
            label: "Forbidden token"
        )
        let target = GraphSearchNodeReference(
            kind: .entity,
            id: UUID(),
            label: "Target"
        )
        let documents = [
            fixtures.detailField(
                id: fieldID,
                ownerID: ownerID,
                ownerTitle: "Owner",
                name: "Forbidden token"
            ),
            fixtures.detailValue(
                fieldID: fieldID,
                fieldName: "Field",
                ownerAttributeID: UUID(),
                ownerAttributeTitle: "Attribute",
                valueText: "Forbidden token"
            ),
            fixtures.attachment(
                ownerKind: .entity,
                ownerID: ownerID,
                title: "Forbidden token",
                originalFilename: "forbidden-token.pdf"
            ),
            fixtures.link(
                source: source,
                target: target,
                note: ""
            )
        ]

        try await withProvider(
            graphID: graphID,
            documents: documents
        ) { provider, resolver in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "forbidden"
            )

            #expect(result.completeness == .complete)
            #expect(result.matches.isEmpty)
            let resolverCallCount = await resolver.callCount()
            #expect(resolverCallCount == 0)
        }
    }

    @Test
    func repeatedQueriesReturnDeterministicResults() async throws {
        let graphID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let documents = [
            fixtures.entity(id: secondID, title: "Atlas Two"),
            fixtures.entity(id: firstID, title: "Atlas One")
        ]

        try await withProvider(
            graphID: graphID,
            documents: documents
        ) { provider, _ in
            let first = try await provider.matches(
                graphID: graphID,
                foldedQuery: "atlas"
            )
            let second = try await provider.matches(
                graphID: graphID,
                foldedQuery: "atlas"
            )

            #expect(first.matches == second.matches)
            let expectedEntityIDs = [firstID, secondID].sorted {
                $0.uuidString < $1.uuidString
            }
            #expect(first.matches.map(\.entityID) == expectedEntityIDs)
        }
    }

    @Test
    func potentialIndexTruncationIsReportedAsIncomplete() async throws {
        let graphID = UUID()
        let fixtures = GraphSearchIndexDocumentFixtureBuilder(graphID: graphID)
        let documents = [
            fixtures.entity(title: "Atlas One"),
            fixtures.entity(title: "Atlas Two")
        ]

        try await withProvider(
            graphID: graphID,
            documents: documents,
            maximumDocumentCount: 1
        ) { provider, _ in
            let result = try await provider.matches(
                graphID: graphID,
                foldedQuery: "atlas"
            )

            #expect(result.matches.isEmpty)
            #expect(result.completeness == .potentiallyTruncated)
            #expect(result.indexDocumentCount == 1)
        }
    }

    @Test
    func unavailableAndFailedReadinessRemainDistinct() async throws {
        let graphID = UUID()

        try await withProvider(
            graphID: graphID,
            documents: [],
            readinessOutcome: .unavailable,
            readinessIsUsable: false
        ) { provider, _ in
            let unavailable = try await provider.matches(
                graphID: graphID,
                foldedQuery: "atlas"
            )
            #expect(unavailable.completeness == .indexUnavailable)
        }

        try await withProvider(
            graphID: graphID,
            documents: [],
            readinessOutcome: .failed,
            readinessIsUsable: true
        ) { provider, _ in
            let failed = try await provider.matches(
                graphID: graphID,
                foldedQuery: "atlas"
            )
            #expect(failed.completeness == .reconciliationFailed)
        }
    }

    private func withProvider<T>(
        graphID: UUID,
        documents: [GraphSearchDocument],
        ownerEntityIDsByAttributeID: [UUID: UUID] = [:],
        readinessOutcome: GraphSearchIndexReadinessOutcome = .ready,
        readinessIsUsable: Bool = true,
        maximumDocumentCount: Int = GraphSearchIndexStore.maximumSearchLimit,
        operation: (
            EntitiesHomeIndexedMatchProvider,
            EntitiesHomeAttributeOwnerResolverStub
        ) async throws -> T
    ) async throws -> T {
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback
        )
        let readiness = EntitiesHomeReadinessStub(
            graphID: graphID,
            outcome: readinessOutcome,
            isIndexUsable: readinessIsUsable
        )
        let resolver = EntitiesHomeAttributeOwnerResolverStub(
            ownerEntityIDsByAttributeID: ownerEntityIDsByAttributeID
        )
        let provider = EntitiesHomeIndexedMatchProvider(
            store: store,
            readinessProvider: readiness,
            attributeOwnerResolver: resolver,
            maximumDocumentCount: maximumDocumentCount
        )

        do {
            _ = try await store.open()
            if documents.isEmpty == false {
                try await store.upsert(documents)
            }
            let result = try await operation(provider, resolver)
            try await store.close()
            location.remove()
            return result
        } catch {
            do {
                try await store.close()
            } catch let closeError {
                Issue.record(
                    "Failed to close Entities Home index test store: \(closeError)"
                )
            }
            location.remove()
            throw error
        }
    }
}

private actor EntitiesHomeReadinessStub:
    BrainMeshSearchIndexReadinessProviding
{
    private let result: GraphSearchIndexReadinessResult
    private var invalidationReasons: [GraphSearchIndexReconciliationReason] = []

    init(
        graphID: UUID,
        outcome: GraphSearchIndexReadinessOutcome,
        isIndexUsable: Bool
    ) {
        self.result = GraphSearchIndexReadinessResult(
            graphID: graphID,
            reason: .firstSearch,
            outcome: outcome,
            isIndexUsable: isIndexUsable,
            documentCount: nil,
            metrics: nil,
            failure: nil
        )
    }

    func ensureReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult {
        result.replacingReason(with: reason)
    }

    func invalidate(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async {
        invalidationReasons.append(reason)
    }
}

private actor EntitiesHomeAttributeOwnerResolverStub:
    EntitiesHomeAttributeOwnerResolving
{
    private let ownerEntityIDsByAttributeID: [UUID: UUID]
    private var requests: [[UUID]] = []

    init(ownerEntityIDsByAttributeID: [UUID: UUID]) {
        self.ownerEntityIDsByAttributeID = ownerEntityIDsByAttributeID
    }

    func ownerEntityIDs(
        graphID: UUID,
        attributeIDs: [UUID]
    ) async throws -> [UUID: UUID] {
        requests.append(attributeIDs)
        return ownerEntityIDsByAttributeID.filter {
            attributeIDs.contains($0.key)
        }
    }

    func callCount() -> Int {
        requests.count
    }

    func requestedAttributeIDs() -> [[UUID]] {
        requests
    }
}
