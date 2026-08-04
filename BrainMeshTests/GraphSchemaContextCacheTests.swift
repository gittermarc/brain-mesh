import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph schema context cache")
struct GraphSchemaContextCacheTests {
    @Test
    func narrowSourceAndCacheIdentityAreValueOnlySendableValues() {
        let scope = GraphScope(graphID: UUID())
        let source = Self.source(in: scope)
        requireGraphSchemaSendable(source)
        requireGraphSchemaSendable(source.sourceScope)
        #expect(Set([source]).count == 1)
    }

    @Test
    func suggestionsPreflightIntentAndSessionReuseOneContextLoad() async throws {
        let scope = GraphScope(graphID: UUID())
        let repository = GraphSchemaTestRepository(
            sources: [Self.source(in: scope)]
        )
        let revisions = GraphMutationEventBus()
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: revisions,
            cache: GraphSchemaContextCache()
        )

        let suggestionsContext = try await service.makeSnapshot(in: scope)
        _ = GraphMentionCatalog(schemaContext: suggestionsContext)
        let preflightContext = try await service.makeSnapshot(in: scope)
        let intentContext = try await service.makeSnapshot(in: scope)
        let sessionContext = try await service.makeSnapshot(in: scope)

        #expect(await repository.schemaLoadCount() == 1)
        #expect(preflightContext.identity == suggestionsContext.identity)
        #expect(intentContext.identity == suggestionsContext.identity)
        #expect(sessionContext.identity == suggestionsContext.identity)
    }

    @Test
    func parallelRequestsForSameKeyAreSingleFlight() async throws {
        let scope = GraphScope(graphID: UUID())
        let repository = GraphSchemaTestRepository(
            sources: [Self.source(in: scope)],
            delayNanoseconds: 80_000_000
        )
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: GraphMutationEventBus(),
            cache: GraphSchemaContextCache()
        )

        let contexts = try await withThrowingTaskGroup(
            of: GraphSchemaContext.self
        ) { group in
            for _ in 0..<24 {
                group.addTask {
                    try await service.makeSnapshot(in: scope)
                }
            }
            var result: [GraphSchemaContext] = []
            for try await context in group {
                result.append(context)
            }
            return result
        }

        #expect(await repository.schemaLoadCount() == 1)
        #expect(Set(contexts.map(\.identity)).count == 1)
    }

    @Test
    func graphAndRevisionAreHardCacheBoundaries() async throws {
        let firstScope = GraphScope(graphID: UUID())
        let secondScope = GraphScope(graphID: UUID())
        let repository = GraphSchemaTestRepository(
            sources: [
                Self.source(in: firstScope, graphName: "First"),
                Self.source(in: secondScope, graphName: "Second"),
            ]
        )
        let revisions = GraphMutationEventBus()
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: revisions,
            cache: GraphSchemaContextCache()
        )

        let first = try await service.makeSnapshot(in: firstScope)
        let second = try await service.makeSnapshot(in: secondScope)
        #expect(first.identity != second.identity)
        #expect(first.snapshot.graphName == "First")
        #expect(second.snapshot.graphName == "Second")

        let mutation = try GraphMutationBatchFactory.entityCreated(
            graphID: firstScope.graphID,
            entityID: UUID()
        )
        _ = await revisions.publishCommitted(mutation)
        let revisedFirst = try await service.makeSnapshot(in: firstScope)

        #expect(revisedFirst.identity != first.identity)
        #expect(await repository.schemaLoadCount() == 3)
    }

    @Test
    func linksAttachmentsAndOrdinaryValuesDoNotInvalidateBaseSchema() async throws {
        let scope = GraphScope(graphID: UUID())
        let source = Self.source(in: scope)
        let fieldID = try #require(source.fieldDefinitions.first?.id)
        let repository = GraphSchemaTestRepository(sources: [source])
        let revisions = GraphMutationEventBus()
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: revisions,
            cache: GraphSchemaContextCache()
        )
        let base = try await service.makeSnapshot(in: scope)

        let node = NodeRefKey(kind: .entity, id: UUID())
        _ = await revisions.publishCommitted(
            try GraphMutationBatchFactory.linksCreated(
                graphID: scope.graphID,
                links: [
                    GraphMutationLinkReference(
                        id: UUID(),
                        source: node,
                        target: node
                    ),
                ]
            )
        )
        _ = await revisions.publishCommitted(
            try GraphMutationBatchFactory.attachmentsCreated(
                graphID: scope.graphID,
                attachments: [
                    GraphMutationAttachmentReference(
                        id: UUID(),
                        owner: node
                    ),
                ]
            )
        )
        _ = await revisions.publishCommitted(
            try GraphMutationBatchFactory.detailValueChanged(
                graphID: scope.graphID,
                value: GraphMutationDetailValueReference(
                    id: UUID(),
                    ownerAttributeID: UUID(),
                    fieldID: fieldID
                )
            )
        )

        let unchangedBase = try await service.makeSnapshot(in: scope)
        #expect(unchangedBase.identity == base.identity)
        #expect(await repository.schemaLoadCount() == 1)

        let example = try await service.makeSnapshot(
            in: scope,
            exampleFieldIDs: [fieldID]
        )
        #expect(example.identity != base.identity)
        _ = await revisions.publishCommitted(
            try GraphMutationBatchFactory.detailValueChanged(
                graphID: scope.graphID,
                value: GraphMutationDetailValueReference(
                    id: UUID(),
                    ownerAttributeID: UUID(),
                    fieldID: fieldID
                )
            )
        )
        let revisedExample = try await service.makeSnapshot(
            in: scope,
            exampleFieldIDs: [fieldID]
        )
        #expect(revisedExample.identity != example.identity)
        #expect(await repository.schemaLoadCount() == 3)
    }

    @Test
    func importAndExternalReconciliationCannotLeaveCacheStale() async throws {
        let scope = GraphScope(graphID: UUID())
        let repository = GraphSchemaTestRepository(
            sources: [Self.source(in: scope, graphName: "Before")]
        )
        let revisions = GraphMutationEventBus()
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: revisions,
            cache: GraphSchemaContextCache()
        )
        let before = try await service.makeSnapshot(in: scope)

        _ = await revisions.publishCommitted(
            try GraphMutationBatchFactory.graphImported(
                graphID: scope.graphID
            )
        )
        let afterImport = try await service.makeSnapshot(in: scope)
        #expect(afterImport.identity != before.identity)

        #expect(
            try await service.reconcileExternalChanges(in: scope)
                == false
        )
        let afterUnrelatedRemoteChange = try await service.makeSnapshot(
            in: scope
        )
        #expect(afterUnrelatedRemoteChange.identity == afterImport.identity)

        await repository.replace(
            Self.source(in: scope, graphName: "Remote")
        )
        #expect(try await service.reconcileExternalChanges(in: scope))
        let afterRemote = try await service.makeSnapshot(in: scope)
        #expect(afterRemote.identity != afterImport.identity)
        #expect(afterRemote.snapshot.graphName == "Remote")
    }

    @Test
    func renameInvalidatesWhileNotesOrMediaNodeUpdateDoesNot() async throws {
        let scope = GraphScope(graphID: UUID())
        let source = Self.source(in: scope)
        let repository = GraphSchemaTestRepository(sources: [source])
        let revisions = GraphMutationEventBus()
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: revisions,
            cache: GraphSchemaContextCache()
        )
        let node = try #require(source.nodes.first?.nodeKey)
        let initial = try await service.makeSnapshot(in: scope)

        _ = await revisions.publishCommitted(
            try GraphMutationBatchFactory.nodeUpdated(
                graphID: scope.graphID,
                node: node
            )
        )
        let afterNonSchemaUpdate = try await service.makeSnapshot(in: scope)
        #expect(afterNonSchemaUpdate.identity == initial.identity)

        _ = await revisions.publishCommitted(
            try GraphMutationBatchFactory.nodeRenamed(
                graphID: scope.graphID,
                node: node,
                relabeledLinks: []
            )
        )
        let afterRename = try await service.makeSnapshot(in: scope)
        #expect(afterRename.identity != initial.identity)
        #expect(await repository.schemaLoadCount() == 2)
    }

    @Test
    func cancellingOneWaiterDoesNotCancelSharedLoad() async throws {
        let scope = GraphScope(graphID: UUID())
        let repository = GraphSchemaTestRepository(
            sources: [Self.source(in: scope)],
            delayNanoseconds: 300_000_000
        )
        let cache = GraphSchemaContextCache()
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: GraphMutationEventBus(),
            cache: cache
        )
        let cancelled = Task {
            try await service.makeSnapshot(in: scope)
        }
        let active = Task {
            try await service.makeSnapshot(in: scope)
        }
        await repository.waitUntilSchemaLoadCount(1)
        cancelled.cancel()

        do {
            _ = try await cancelled.value
            Issue.record("The cancelled waiter unexpectedly succeeded.")
        } catch is CancellationError {
            // Expected.
        }
        let context = try await active.value
        #expect(context.graphScope == scope)
        #expect(await repository.schemaLoadCount() == 1)
        #expect(await repository.cancelledLoadCount() == 0)
        #expect(await cache.entryCountForTesting == 1)
    }

    @Test
    func staleInFlightResultIsNeverPublished() async throws {
        let scope = GraphScope(graphID: UUID())
        let repository = GraphSchemaTestRepository(
            sources: [Self.source(in: scope)],
            delayNanoseconds: 100_000_000
        )
        let revisions = GraphMutationEventBus()
        let cache = GraphSchemaContextCache()
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: revisions,
            cache: cache
        )
        let task = Task {
            try await service.makeSnapshot(in: scope)
        }
        await repository.waitUntilSchemaLoadCount(1)
        _ = await revisions.publishCommitted(
            try GraphMutationBatchFactory.detailSchemaChanged(
                graphID: scope.graphID,
                ownerEntityID: UUID(),
                definitionIDs: [UUID()]
            )
        )

        let context = try await task.value
        #expect(await repository.schemaLoadCount() == 2)
        #expect(await cache.entryCountForTesting == 1)
        guard case .cached(let key) = context.identity else {
            Issue.record("Expected a cached context identity.")
            return
        }
        let currentRevision = await revisions.schemaRevision(
            in: scope,
            sourceScope: GraphSchemaSourceScope()
        )
        #expect(key.revision == currentRevision)
    }

    @Test
    func lastCancelledWaiterCancelsUnownedLoad() async throws {
        let scope = GraphScope(graphID: UUID())
        let repository = GraphSchemaTestRepository(
            sources: [Self.source(in: scope)],
            delayNanoseconds: 5_000_000_000
        )
        let cache = GraphSchemaContextCache()
        let service = GraphSchemaService(
            repository: repository,
            revisionProvider: GraphMutationEventBus(),
            cache: cache
        )
        let task = Task {
            try await service.makeSnapshot(in: scope)
        }
        await repository.waitUntilSchemaLoadCount(1)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("The only cancelled waiter unexpectedly succeeded.")
        } catch is CancellationError {
            // Expected.
        }
        await repository.waitUntilCancelledLoadCount(1)
        #expect(await cache.entryCountForTesting == 0)
        #expect(await cache.flightCountForTesting == 0)
    }

    private static func source(
        in scope: GraphScope,
        graphName: String = "Graph"
    ) -> GraphSchemaSourceSnapshotDTO {
        let entityID = UUID(
            uuidString: "10000000-0000-0000-0000-000000000001"
        )!
        let nodeID = UUID(
            uuidString: "20000000-0000-0000-0000-000000000001"
        )!
        let fieldID = UUID(
            uuidString: "30000000-0000-0000-0000-000000000001"
        )!
        return GraphSchemaSourceSnapshotDTO(
            scope: scope,
            sourceScope: GraphSchemaSourceScope(),
            graph: GraphMetadataDTO(
                id: scope.graphID,
                scope: scope,
                name: graphName,
                createdAt: .distantPast
            ),
            entities: [
                GraphSchemaSourceEntityDTO(
                    id: entityID,
                    scope: scope,
                    name: "Projects",
                    createdAt: .distantPast
                ),
            ],
            nodes: [
                GraphSchemaSourceNodeDTO(
                    id: nodeID,
                    scope: scope,
                    ownerEntityID: entityID,
                    name: "Atlas",
                    displayName: "Projects · Atlas"
                ),
            ],
            fieldDefinitions: [
                GraphSchemaSourceFieldDefinitionDTO(
                    id: fieldID,
                    scope: scope,
                    entityID: entityID,
                    name: "Status",
                    typeRaw: DetailFieldType.singleLineText.rawValue,
                    sortIndex: 0,
                    isPinned: true,
                    unit: nil,
                    options: []
                ),
            ],
            exampleValues: []
        )
    }
}

private nonisolated func requireGraphSchemaSendable<T: Sendable>(
    _ value: T
) {
    _ = value
}

private actor GraphSchemaTestRepository: GraphSchemaReading {
    private var sourcesByGraphID: [UUID: GraphSchemaSourceSnapshotDTO]
    private let delayNanoseconds: UInt64
    private var schemaLoads = 0
    private var cancelledLoads = 0

    init(
        sources: [GraphSchemaSourceSnapshotDTO],
        delayNanoseconds: UInt64 = 0
    ) {
        sourcesByGraphID = Dictionary(
            uniqueKeysWithValues: sources.map {
                ($0.scope.graphID, $0)
            }
        )
        self.delayNanoseconds = delayNanoseconds
    }

    func schemaSourceSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) async throws -> GraphSchemaSourceSnapshotDTO {
        schemaLoads += 1
        if delayNanoseconds > 0 {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                cancelledLoads += 1
                throw error
            }
        }
        try Task.checkCancellation()
        guard let source = sourcesByGraphID[scope.graphID] else {
            throw GraphReadRepositoryError.graphNotFound(scope)
        }
        let sourceScope = GraphSchemaSourceScope(
            exampleFieldIDs: exampleFieldIDs
        )
        let requestedValues = source.exampleValues.filter {
            exampleFieldIDs.contains($0.fieldID)
        }
        return GraphSchemaSourceSnapshotDTO(
            scope: source.scope,
            sourceScope: sourceScope,
            graph: source.graph,
            entities: source.entities,
            nodes: source.nodes,
            fieldDefinitions: source.fieldDefinitions,
            exampleValues: requestedValues
        )
    }

    func replace(_ source: GraphSchemaSourceSnapshotDTO) {
        sourcesByGraphID[source.scope.graphID] = source
    }

    func schemaLoadCount() -> Int { schemaLoads }
    func cancelledLoadCount() -> Int { cancelledLoads }

    func waitUntilSchemaLoadCount(_ minimum: Int) async {
        while schemaLoads < minimum {
            await Task.yield()
        }
    }

    func waitUntilCancelledLoadCount(_ minimum: Int) async {
        while cancelledLoads < minimum {
            await Task.yield()
        }
    }
}
