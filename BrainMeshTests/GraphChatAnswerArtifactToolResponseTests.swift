import Foundation
import Testing
@testable import BrainMesh

struct GraphChatAnswerArtifactToolResponseTests {
    @Test
    func responseCanCarryTextAndOneOpaqueArtifactID() {
        let artifactID = GraphChatAnswerArtifactID(
            rawValue: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
        )
        let response = GraphChatModelToolResponse(
            tool: .graphStats,
            state: .success,
            content: "Validated summary",
            evidenceIDs: [],
            artifactID: artifactID
        )

        #expect(response.content == "Validated summary")
        #expect(response.artifactID == artifactID)
        #expect(response.modelContent == "Validated summary\nartifactID=\(artifactID.rawValue.uuidString)")
    }

    @Test
    func responseWithoutArtifactRemainsTextCompatible() {
        let response = GraphChatModelToolResponse(
            tool: .describeGraphSchema,
            state: .success,
            content: "Schema summary",
            evidenceIDs: []
        )

        #expect(response.artifactID == nil)
        #expect(response.modelContent == response.content)
    }

    @Test
    func providerArtifactReferencesAreReducedToRegisteredIDs() async throws {
        let graphScope = GraphScope(
            graphID: UUID(uuidString: "C0000000-0000-0000-0000-000000000010")!
        )
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let sessionID = GraphChatAnswerArtifactSessionID(
            rawValue: UUID(uuidString: "C0000000-0000-0000-0000-000000000011")!
        )
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .graph,
                sourceID: graphScope.graphID
            ),
            summary: "Validated graph evidence",
            identitySuffix: "artifact-provider-contract"
        )
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: chatScope)
        try await evidenceRegistry.register([evidence])
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            sessionID: sessionID
        )
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let binding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [evidence.id]
        )
        let registeredID = try await registry.stage(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: "Count",
                payload: .metric(
                    GraphChatAnswerArtifactMetricPayload(
                        title: "Count",
                        value: .integer(7),
                        unit: nil,
                        contextDescription: nil,
                        evidence: binding
                    )
                ),
                evidence: binding
            ),
            transactionID: transactionID,
            evidenceRegistry: evidenceRegistry
        )
        let inventedID = GraphChatAnswerArtifactID()
        let providerAnswer = GraphChatProviderFinalAnswer(
            directAnswer: "Seven",
            sections: [],
            evidenceIDValues: [evidence.id.rawValue.uuidString],
            artifactIDValues: [
                registeredID.rawValue.uuidString,
                inventedID.rawValue.uuidString,
                "not-a-uuid"
            ],
            appliedFilters: [],
            followUpSuggestions: [],
            hasInsufficientEvidence: false
        )

        let artifacts = try await registry.validatedArtifacts(
            for: providerAnswer.artifactIDValues,
            graphScope: graphScope,
            sessionID: sessionID,
            transactionID: transactionID
        )

        #expect(artifacts.map(\.id) == [registeredID])
    }

    @Test
    func providerCannotReuseACommittedArtifactFromAnotherTurn() async throws {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let sessionID = GraphChatAnswerArtifactSessionID()
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .graph,
                sourceID: graphScope.graphID
            ),
            summary: "Validated graph evidence",
            identitySuffix: "previous-turn-artifact"
        )
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: chatScope)
        try await evidenceRegistry.register([evidence])
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            sessionID: sessionID
        )
        let firstTransactionID = GraphChatAnswerArtifactTransactionID()
        let binding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [evidence.id]
        )
        let committedID = try await registry.stage(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: "Previous turn",
                payload: .metric(
                    GraphChatAnswerArtifactMetricPayload(
                        title: "Previous turn",
                        value: .integer(1),
                        unit: nil,
                        contextDescription: nil,
                        evidence: binding
                    )
                ),
                evidence: binding
            ),
            transactionID: firstTransactionID,
            evidenceRegistry: evidenceRegistry
        )
        try await registry.commit(
            transactionID: firstTransactionID,
            retaining: [committedID]
        )

        let accepted = try await registry.validatedArtifacts(
            for: [committedID.rawValue.uuidString],
            graphScope: graphScope,
            sessionID: sessionID,
            transactionID: GraphChatAnswerArtifactTransactionID()
        )

        #expect(accepted.isEmpty)
    }

    @Test
    func artifactFromAnotherRegistryCannotCrossSessionBoundary() async throws {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .graph,
                sourceID: graphScope.graphID
            ),
            summary: "Validated graph evidence",
            identitySuffix: "foreign-artifact"
        )
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: chatScope)
        try await evidenceRegistry.register([evidence])
        let firstSessionID = GraphChatAnswerArtifactSessionID()
        let secondSessionID = GraphChatAnswerArtifactSessionID()
        let firstRegistry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            sessionID: firstSessionID
        )
        let secondRegistry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            sessionID: secondSessionID
        )
        let transactionID = GraphChatAnswerArtifactTransactionID()
        let binding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [evidence.id]
        )
        let foreignID = try await firstRegistry.stage(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: "Foreign",
                payload: .metric(
                    GraphChatAnswerArtifactMetricPayload(
                        title: "Foreign",
                        value: .integer(1),
                        unit: nil,
                        contextDescription: nil,
                        evidence: binding
                    )
                ),
                evidence: binding
            ),
            transactionID: transactionID,
            evidenceRegistry: evidenceRegistry
        )

        let accepted = try await secondRegistry.validatedArtifacts(
            for: [foreignID.rawValue.uuidString],
            graphScope: graphScope,
            sessionID: secondSessionID,
            transactionID: transactionID
        )

        #expect(accepted.isEmpty)
    }
}
