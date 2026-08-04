//
//  GraphChatSuggestionsSnapshot.swift
//  BrainMesh
//
//  Immutable, schema-bound suggestions prepared outside SwiftUI rendering.
//

import Foundation

nonisolated struct GraphChatSuggestionsAliasMapRevision:
    Hashable,
    Sendable
{
    nonisolated struct EntityBinding:
        Hashable,
        Sendable
    {
        let alias: GraphEntityAlias
        let resolution: GraphSchemaEntityResolution
    }

    nonisolated struct FieldBinding:
        Hashable,
        Sendable
    {
        let alias: GraphFieldAlias
        let resolution: GraphSchemaFieldResolution
    }

    nonisolated struct NodeEntityBinding:
        Hashable,
        Sendable
    {
        let node: NodeRefKey
        let entityID: UUID
    }

    nonisolated struct NodeResolutionBinding:
        Hashable,
        Sendable
    {
        let node: NodeRefKey
        let resolution: GraphSchemaNodeResolution
    }

    let graphScope: GraphScope
    let entities: [EntityBinding]
    let fields: [FieldBinding]
    let nodeEntityBindings: [NodeEntityBinding]
    let nodes: [NodeResolutionBinding]

    init(_ aliases: GraphSchemaAliasMap) {
        graphScope = aliases.graphScope
        entities = aliases.entitiesByAlias.map {
            EntityBinding(alias: $0.key, resolution: $0.value)
        }.sorted {
            if $0.alias.rawValue != $1.alias.rawValue {
                return $0.alias.rawValue < $1.alias.rawValue
            }
            return $0.resolution.entityID.uuidString <
                $1.resolution.entityID.uuidString
        }
        fields = aliases.fieldsByAlias.map {
            FieldBinding(alias: $0.key, resolution: $0.value)
        }.sorted {
            if $0.alias.rawValue != $1.alias.rawValue {
                return $0.alias.rawValue < $1.alias.rawValue
            }
            if $0.resolution.entityID
                != $1.resolution.entityID {
                return $0.resolution.entityID.uuidString <
                    $1.resolution.entityID.uuidString
            }
            return $0.resolution.fieldID.uuidString <
                $1.resolution.fieldID.uuidString
        }
        nodeEntityBindings = aliases.nodeEntityIDs.map {
            NodeEntityBinding(node: $0.key, entityID: $0.value)
        }.sorted {
            Self.nodeOrder($0.node, $1.node)
        }
        nodes = aliases.nodesByKey.map {
            NodeResolutionBinding(
                node: $0.key,
                resolution: $0.value
            )
        }.sorted {
            if $0.node != $1.node {
                return Self.nodeOrder($0.node, $1.node)
            }
            return $0.resolution.ownerEntityID.uuidString <
                $1.resolution.ownerEntityID.uuidString
        }
    }

    private static func nodeOrder(
        _ lhs: NodeRefKey,
        _ rhs: NodeRefKey
    ) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

nonisolated struct GraphChatSuggestionsSchemaRevision:
    Hashable,
    Sendable
{
    let snapshot: GraphSchemaSnapshot
    let promptAliases: GraphChatSuggestionsAliasMapRevision
    let foundationalAliases: GraphChatSuggestionsAliasMapRevision

    init(_ context: GraphSchemaContext) {
        snapshot = context.snapshot
        promptAliases = GraphChatSuggestionsAliasMapRevision(
            context.aliases
        )
        foundationalAliases = GraphChatSuggestionsAliasMapRevision(
            context.foundationalAliases
        )
    }
}

/// Exact identity for every input that can change candidate generation,
/// production validation, localization, or compiler output.
nonisolated struct GraphChatSuggestionsSnapshotKey:
    Hashable,
    Sendable
{
    let graphID: UUID
    let schemaRevision: GraphChatSuggestionsSchemaRevision
    let chatScope: GraphChatScope
    let launchContext: GraphChatLaunchContext
    let localeIdentifier: String
    let language: GraphChatResponseLanguage
    let availableTools: Set<GraphChatToolKind>
    let modelAvailability: GraphChatAvailabilityPresentationState
    let capabilities: [GraphChatCapability]
    let mentionResolverVersion: GraphMentionResolverVersion
    let mentionResolverPolicy: GraphMentionResolverPolicy
    let mentionLexicon: GraphMentionLexicon
    let intentLimits: GraphChatIntentLimitPolicy
    let semanticIntentLimits: GraphChatSemanticIntentLimitPolicy
    let composableReadPlanVersion: GraphChatComposableReadPlanVersion
    let queryPlanVersion: Int
    let maximumSuggestions: Int
    let maximumCandidateAttemptsPerCapability: Int

    init(context: GraphChatSuggestionContext) {
        graphID = context.schema.graphScope.graphID
        schemaRevision = GraphChatSuggestionsSchemaRevision(
            context.schema
        )
        chatScope = context.scope
        launchContext = context.launchContext
        localeIdentifier = context.localeIdentifier
        language = context.language
        availableTools = context.availableTools
        modelAvailability = context.modelAvailability
        capabilities = GraphChatCapabilityCatalog.stable
        mentionResolverVersion = .v1
        mentionResolverPolicy = .default
        mentionLexicon = .appOwned
        intentLimits = .default
        semanticIntentLimits = .default
        composableReadPlanVersion = .current
        queryPlanVersion = GraphQueryPlan.currentVersion
        maximumSuggestions =
            GraphChatEmptyStateSuggestionBuilder.maximumSuggestions
        maximumCandidateAttemptsPerCapability =
            GraphChatEmptyStateSuggestionBuilder
                .maximumCandidateAttemptsPerCapability
    }
}

nonisolated struct GraphChatSuggestionsSnapshotRequest:
    Sendable
{
    let key: GraphChatSuggestionsSnapshotKey
    let context: GraphChatSuggestionContext

    init(context: GraphChatSuggestionContext) {
        key = GraphChatSuggestionsSnapshotKey(context: context)
        self.context = context
    }
}

nonisolated struct GraphChatSuggestionsSnapshot:
    Hashable,
    Sendable
{
    let key: GraphChatSuggestionsSnapshotKey
    let suggestions: [GraphChatEmptyStateSuggestion]
}

nonisolated protocol GraphChatSuggestionsSnapshotBuilding:
    Sendable
{
    func makeSnapshot(
        for request: GraphChatSuggestionsSnapshotRequest
    ) async throws -> GraphChatSuggestionsSnapshot
}

nonisolated struct GraphChatProductionSuggestionsSnapshotBuilder:
    GraphChatSuggestionsSnapshotBuilding,
    Sendable
{
    private let instrumentation:
        GraphChatSuggestionsInstrumentation

    init(
        instrumentation: GraphChatSuggestionsInstrumentation = .disabled
    ) {
        self.instrumentation = instrumentation
    }

    func makeSnapshot(
        for request: GraphChatSuggestionsSnapshotRequest
    ) async throws -> GraphChatSuggestionsSnapshot {
        instrumentation.record(.snapshotBuild)
        try Task.checkCancellation()

        guard request.context.modelAvailability.isAvailable else {
            return GraphChatSuggestionsSnapshot(
                key: request.key,
                suggestions: []
            )
        }

        instrumentation.record(.mentionCatalogBuild)
        let mentionCatalog = GraphMentionCatalog(
            schemaContext: request.context.schema
        )
        try Task.checkCancellation()

        let suggestions = try GraphChatEmptyStateSuggestionBuilder
            .validatedSuggestions(
                for: request.context,
                mentionCatalog: mentionCatalog,
                validator: GraphChatCapabilityQuestionValidator(
                    instrumentation: instrumentation
                )
            )
        try Task.checkCancellation()
        return GraphChatSuggestionsSnapshot(
            key: request.key,
            suggestions: suggestions
        )
    }
}

/// Main-actor owner for one cancellable build and one exact-key snapshot.
/// Builder work executes in an owned detached task so compiler and resolver
/// work never inherits the UI actor.
@MainActor
final class GraphChatSuggestionsSnapshotController {
    private let builder: any GraphChatSuggestionsSnapshotBuilding
    private var buildTask:
        Task<GraphChatSuggestionsSnapshot, Error>?
    private var buildingKey: GraphChatSuggestionsSnapshotKey?
    private var storedSnapshot: GraphChatSuggestionsSnapshot?
    private var generation: UInt64 = 0

    init(
        builder: any GraphChatSuggestionsSnapshotBuilding =
            GraphChatProductionSuggestionsSnapshotBuilder()
    ) {
        self.builder = builder
    }

    deinit {
        buildTask?.cancel()
    }

    func snapshot(
        for request: GraphChatSuggestionsSnapshotRequest
    ) async throws -> GraphChatSuggestionsSnapshot {
        if let storedSnapshot,
           storedSnapshot.key == request.key {
            return storedSnapshot
        }

        let task: Task<GraphChatSuggestionsSnapshot, Error>
        let requestGeneration: UInt64
        if let buildTask,
           buildingKey == request.key {
            task = buildTask
            requestGeneration = generation
        } else {
            generation &+= 1
            requestGeneration = generation
            buildTask?.cancel()
            let builder = self.builder
            task = Task.detached(priority: .userInitiated) {
                try await builder.makeSnapshot(for: request)
            }
            buildTask = task
            buildingKey = request.key
        }

        do {
            let result = try await task.value
            if let storedSnapshot,
               storedSnapshot.key == request.key,
               generation == requestGeneration {
                return storedSnapshot
            }
            guard generation == requestGeneration,
                  buildingKey == request.key,
                  result.key == request.key else {
                throw CancellationError()
            }
            storedSnapshot = result
            buildTask = nil
            buildingKey = nil
            return result
        } catch {
            if generation == requestGeneration,
               buildingKey == request.key {
                buildTask = nil
                buildingKey = nil
            }
            throw error
        }
    }

    func cachedSnapshot(
        for key: GraphChatSuggestionsSnapshotKey
    ) -> GraphChatSuggestionsSnapshot? {
        guard storedSnapshot?.key == key else {
            return nil
        }
        return storedSnapshot
    }

    func cancel(clearCachedSnapshot: Bool) {
        generation &+= 1
        buildTask?.cancel()
        buildTask = nil
        buildingKey = nil
        if clearCachedSnapshot {
            storedSnapshot = nil
        }
    }
}
