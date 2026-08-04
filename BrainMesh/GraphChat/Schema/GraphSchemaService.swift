//
//  GraphSchemaService.swift
//  BrainMesh
//
//  Revision-aware graph-chat schema loading through the narrow source repository.
//

import Foundation

nonisolated enum GraphSchemaServiceError: LocalizedError, Equatable, Sendable {
    case repositoryScopeMismatch(expected: GraphScope, actual: GraphScope)
    case sourceScopeMismatch
    case schemaChangedDuringLoad

    var errorDescription: String? {
        switch self {
        case .repositoryScopeMismatch:
            return "Das geladene Graph-Schema gehört nicht zum angeforderten Graphen."
        case .sourceScopeMismatch:
            return "Der geladene Schema-Scope entspricht nicht der Anfrage."
        case .schemaChangedDuringLoad:
            return "Das Graph-Schema wurde während des Ladens geändert."
        }
    }
}

nonisolated protocol GraphSchemaReading: Sendable {
    func schemaSourceSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) async throws -> GraphSchemaSourceSnapshotDTO
}

extension GraphReadRepository: GraphSchemaReading {}

actor GraphSchemaService {
    static let shared = GraphSchemaService(
        repository: GraphReadRepository.shared
    )

    private let repository: any GraphSchemaReading
    private let revisionProvider: any GraphSchemaRevisionProviding
    private let cache: GraphSchemaContextCache
    private let builder: GraphSchemaContextBuilder
    private let fingerprintStore: GraphSchemaSourceFingerprintStore

    init(
        repository: any GraphSchemaReading,
        limits: GraphSchemaLimits = .default,
        revisionProvider: any GraphSchemaRevisionProviding =
            GraphMutationEventBus.shared,
        cache: GraphSchemaContextCache = GraphSchemaContextCache(),
        fingerprintStore: GraphSchemaSourceFingerprintStore =
            GraphSchemaSourceFingerprintStore()
    ) {
        self.repository = repository
        self.revisionProvider = revisionProvider
        self.cache = cache
        builder = GraphSchemaContextBuilder(limits: limits)
        self.fingerprintStore = fingerprintStore
    }

    func makeSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID> = []
    ) async throws -> GraphSchemaContext {
        let sourceScope = GraphSchemaSourceScope(
            exampleFieldIDs: exampleFieldIDs
        )

        // A mutation racing the read is retried under its new authoritative key. The bound keeps
        // a continuously mutating graph from monopolizing the caller indefinitely.
        for _ in 0..<4 {
            try Task.checkCancellation()
            let revision = await revisionProvider.schemaRevision(
                in: scope,
                sourceScope: sourceScope
            )
            let key = GraphSchemaContextCacheKey(
                graphID: scope.graphID,
                revision: revision,
                sourceScope: sourceScope,
                limits: builder.limits
            )
            let repository = self.repository
            let revisionProvider = self.revisionProvider
            let builder = self.builder
            let fingerprintStore = self.fingerprintStore

            do {
                let context = try await cache.value(for: key) {
                    try Task.checkCancellation()
                    let source = try await repository.schemaSourceSnapshot(
                        in: scope,
                        exampleFieldIDs: sourceScope.exampleFieldIDSet
                    )
                    try Task.checkCancellation()
                    guard source.scope == scope,
                          source.graph.scope == scope else {
                        throw GraphSchemaServiceError.repositoryScopeMismatch(
                            expected: scope,
                            actual: source.scope
                        )
                    }
                    guard source.sourceScope == sourceScope else {
                        throw GraphSchemaServiceError.sourceScopeMismatch
                    }
                    let revisionAfterRead = await revisionProvider.schemaRevision(
                        in: scope,
                        sourceScope: sourceScope
                    )
                    guard revisionAfterRead == revision else {
                        throw GraphSchemaContextCacheError.staleRevision
                    }

                    let context = try builder.build(
                        source: source,
                        cacheKey: key
                    )
                    try Task.checkCancellation()
                    let revisionAfterBuild = await revisionProvider.schemaRevision(
                        in: scope,
                        sourceScope: sourceScope
                    )
                    guard revisionAfterBuild == revision else {
                        throw GraphSchemaContextCacheError.staleRevision
                    }
                    await fingerprintStore.record(source)
                    return context
                }
                try Task.checkCancellation()
                let currentRevision = await revisionProvider.schemaRevision(
                    in: scope,
                    sourceScope: sourceScope
                )
                guard currentRevision == revision else {
                    continue
                }
                return context
            } catch GraphSchemaContextCacheError.staleRevision {
                continue
            }
        }
        throw GraphSchemaServiceError.schemaChangedDuringLoad
    }

    /// Reconciles CloudKit or import writes that did not traverse the local mutation bus.
    /// Only the narrow schema rows and previously requested example-field scopes are fetched.
    @discardableResult
    func reconcileExternalChanges(
        in scope: GraphScope
    ) async throws -> Bool {
        try Task.checkCancellation()
        var sourceScopes = await fingerprintStore.sourceScopes(
            for: scope.graphID
        )
        let baseScope = GraphSchemaSourceScope()
        if sourceScopes.contains(baseScope) == false {
            sourceScopes.insert(baseScope, at: 0)
        }

        var loadedSources: [GraphSchemaSourceSnapshotDTO] = []
        loadedSources.reserveCapacity(sourceScopes.count)
        var structureChanged = false
        var changedExampleFieldIDs = Set<UUID>()
        for sourceScope in sourceScopes {
            try Task.checkCancellation()
            let source = try await repository.schemaSourceSnapshot(
                in: scope,
                exampleFieldIDs: sourceScope.exampleFieldIDSet
            )
            guard source.scope == scope,
                  source.graph.scope == scope else {
                throw GraphSchemaServiceError.repositoryScopeMismatch(
                    expected: scope,
                    actual: source.scope
                )
            }
            let changes = await fingerprintStore.changes(in: source)
            structureChanged = structureChanged || changes.structure
            changedExampleFieldIDs.formUnion(
                changes.exampleFieldIDs
            )
            loadedSources.append(source)
        }

        if structureChanged {
            await revisionProvider.recordExternalSchemaChange(in: scope)
            await cache.invalidate(graphID: scope.graphID)
        } else if changedExampleFieldIDs.isEmpty == false {
            await revisionProvider.recordExternalExampleValueChanges(
                fieldIDs: changedExampleFieldIDs,
                in: scope
            )
        }
        for source in loadedSources {
            await fingerprintStore.record(source)
        }
        return structureChanged || changedExampleFieldIDs.isEmpty == false
    }

    func invalidateForGraphSwitch(from graphID: UUID?) async {
        guard let graphID else { return }
        await cache.invalidate(graphID: graphID)
    }
}
