//
//  GraphChatRegistryCacheTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat registry caches")
struct GraphChatRegistryCacheTests {
    @Test
    func presentationSnapshotInvalidatesOnlyForAGenuineRevision() async {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let registry = GraphChatPresentationRegistry(
            schemaContext: GraphChatTestSupport.makeSchemaContext(),
            conversationContext: emptyConversationContext(
                graphScope: graphScope,
                chatScope: chatScope
            ),
            language: .english
        )

        let initial = await registry.snapshot()
        let initialDiagnostics = await registry.cacheDiagnosticsForTesting()
        let repeated = await registry.snapshot()
        let repeatedDiagnostics = await registry.cacheDiagnosticsForTesting()
        #expect(repeated == initial)
        #expect(repeated.revision == initial.revision)
        #expect(initialDiagnostics.snapshotBuildCount == 1)
        #expect(repeatedDiagnostics.snapshotBuildCount == 1)

        let node = NodeRefKey(kind: .attribute, id: UUID())
        await registry.registerValidatedNode(
            alias: "N77",
            node: node,
            displayName: "Validated node"
        )
        let changed = await registry.snapshot()
        let changedDiagnostics = await registry.cacheDiagnosticsForTesting()
        #expect(changed.revision.rawValue == initial.revision.rawValue + 1)
        #expect(changedDiagnostics.snapshotBuildCount == 2)

        await registry.registerValidatedNode(
            alias: "N77",
            node: node,
            displayName: "Validated node"
        )
        let duplicate = await registry.snapshot()
        let duplicateDiagnostics = await registry.cacheDiagnosticsForTesting()
        #expect(duplicate.revision == changed.revision)
        #expect(duplicateDiagnostics.snapshotBuildCount == 2)
        #expect(
            duplicate.entries.map(\.identifier)
                == duplicate.entries.map(\.identifier).sorted()
        )
        for entry in duplicate.entries {
            #expect(
                duplicate.displayName(for: entry.identifier)
                    == entry.displayName
            )
        }
    }

    @Test
    func evidenceAndResolutionLookupsPreserveDeterministicCallerOrder() async throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let first = makePresentationEvidence(
            graphID: graphScope.graphID,
            sourceID: UUID(),
            navigationTitle: "First source"
        )
        let second = makePresentationEvidence(
            graphID: graphScope.graphID,
            sourceID: UUID(),
            navigationTitle: "Second source"
        )
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: chatScope)

        try await evidenceRegistry.register([second, first])
        let firstSnapshot = await evidenceRegistry.snapshotForTesting()
        let firstDiagnostics =
            await evidenceRegistry.cacheDiagnosticsForTesting()
        let repeatedSnapshot = await evidenceRegistry.snapshotForTesting()
        try await evidenceRegistry.register([second, first])
        let duplicateDiagnostics =
            await evidenceRegistry.cacheDiagnosticsForTesting()

        #expect(firstDiagnostics.revision == 1)
        #expect(firstDiagnostics.snapshotBuildCount == 1)
        #expect(duplicateDiagnostics.revision == firstDiagnostics.revision)
        #expect(duplicateDiagnostics.snapshotBuildCount == 1)
        #expect(firstSnapshot == repeatedSnapshot)
        #expect(
            firstSnapshot.map { $0.id.rawValue.uuidString }
                == firstSnapshot.map { $0.id.rawValue.uuidString }.sorted()
        )
        let requestedIDs = [second.id, first.id, second.id]
        #expect(
            await evidenceRegistry.evidence(for: requestedIDs)
                == [second, first]
        )

        let third = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(),
            summary: "Third source"
        )
        try await evidenceRegistry.register([third])
        _ = await evidenceRegistry.snapshotForTesting()
        let changedDiagnostics =
            await evidenceRegistry.cacheDiagnosticsForTesting()
        #expect(
            changedDiagnostics.revision
                == firstDiagnostics.revision + 1
        )
        #expect(changedDiagnostics.snapshotBuildCount == 2)

        let resolution = GraphChatAnswerPresentationResolution(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: nil,
            requestedArtifactIDs: [],
            artifacts: [],
            evidence: [second, first, second]
        )
        #expect(resolution.evidence == [second, first])
        #expect(resolution.evidence(for: requestedIDs) == [second, first])
        #expect(resolution.evidenceByID[first.id] == first)
        #expect(resolution.evidenceByID[second.id] == second)

        let presentation = GraphChatValidatedPresentationRegistry(
            evidence: [second, first],
            language: .english
        )
        #expect(
            presentation.displayName(
                for: first.sourceReference.sourceID.uuidString
            ) == "First source"
        )
        #expect(
            presentation.displayName(
                for: second.sourceReference.sourceID.uuidString
            ) == "Second source"
        )
    }

    private func makePresentationEvidence(
        graphID: UUID,
        sourceID: UUID,
        navigationTitle: String
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphID,
                sourceKind: .entity,
                sourceID: sourceID
            ),
            summary: "Internal evidence payload",
            navigationTitle: navigationTitle,
            identitySuffix: sourceID.uuidString
        )
    }

    private func emptyConversationContext(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> GraphChatConversationContextSnapshot {
        GraphChatConversationContextSnapshot(
            conversationID: UUID(),
            graphScope: graphScope,
            chatScope: chatScope,
            aliases: [],
            results: [],
            turns: [],
            latestResultAlias: nil,
            lastEntityAlias: nil,
            lastFieldAlias: nil,
            lastGroupAlias: nil,
            lastNodeAlias: nil,
            lastComparisonAlias: nil,
            currentReferenceAlias: nil,
            lastValidatedQuery: nil,
            resultRevalidations: [],
            pendingClarificationID: nil
        )
    }
}
