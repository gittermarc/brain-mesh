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
    func responseCanCarryMultipleArtifactIDsWithoutRepeatingStructuredRows() {
        let first = GraphChatAnswerArtifactID(
            rawValue: UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!
        )
        let second = GraphChatAnswerArtifactID(
            rawValue: UUID(uuidString: "C0000000-0000-0000-0000-000000000003")!
        )
        let response = GraphChatModelToolResponse(
            tool: .graphStats,
            state: .success,
            content: "Validated interpretation",
            evidenceIDs: [],
            artifactIDs: [first, second, first]
        )

        #expect(response.artifactIDs == [first, second])
        #expect(response.artifactID == first)
        #expect(response.modelContent == [
            "Validated interpretation",
            "artifactID=\(first.rawValue.uuidString)",
            "artifactID=\(second.rawValue.uuidString)"
        ].joined(separator: "\n"))
    }

    @Test
    func answerSectionsKeepOnlyCommittedArtifactReferencesAndTheirQuerySummary() {
        let retained = GraphChatAnswerArtifactID(
            rawValue: UUID(uuidString: "C0000000-0000-0000-0000-000000000004")!
        )
        let removed = GraphChatAnswerArtifactID(
            rawValue: UUID(uuidString: "C0000000-0000-0000-0000-000000000005")!
        )
        let summary = GraphChatAnswerArtifactQuerySummary(
            language: .english,
            entityID: UUID(uuidString: "C0000000-0000-0000-0000-000000000006")!,
            entityLabel: "Projects",
            filters: [],
            grouping: nil,
            sorting: [],
            projection: [],
            includesNodeIdentity: true,
            limit: 10,
            aggregation: nil,
            displayText: "Entity: Projects; Limit: 10"
        )
        let answer = GraphChatAnswer(
            directAnswer: "Validated interpretation",
            sections: [
                GraphChatAnswerSection(
                    title: "Retained",
                    text: "First result",
                    artifactIDs: [retained, removed],
                    querySummary: summary,
                    state: .answer
                ),
                GraphChatAnswerSection(
                    title: "Removed",
                    text: "Fallback text",
                    artifactIDs: [removed],
                    querySummary: summary,
                    state: .answer
                )
            ],
            artifactIDs: [retained, removed],
            hasInsufficientEvidence: false
        ).retainingArtifactIDs([retained])

        #expect(answer.artifactIDs == [retained])
        #expect(answer.sections[0].artifactIDs == [retained])
        #expect(answer.sections[0].querySummary == summary)
        #expect(answer.sections[1].artifactIDs.isEmpty)
        #expect(answer.sections[1].querySummary == nil)
        #expect(answer.sections[1].text == "Fallback text")
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
    func multipleToolCallsCanBindDifferentArtifactsToDifferentAnswerSections() async throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let firstEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "C0000000-0000-0000-0000-000000000020")!,
            summary: "Search result"
        )
        let secondEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "C0000000-0000-0000-0000-000000000021")!,
            summary: "Stats result"
        )
        let firstSummary = makeQuerySummary(
            graphScope: graphScope,
            label: "Search",
            limit: 5
        )
        let secondSummary = makeQuerySummary(
            graphScope: graphScope,
            label: "Statistics",
            limit: 10
        )
        let firstBinding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [firstEvidence.id]
        )
        let secondBinding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [secondEvidence.id]
        )
        let factory = EvidenceRegisteringFakeToolRunnerFactory(
            evidenceByTool: [
                .searchGraph: [firstEvidence],
                .graphStats: [secondEvidence]
            ],
            artifactDraftsByTool: [
                .searchGraph: [
                    GraphChatAnswerArtifactDraft(
                        graphScope: graphScope,
                        title: "Search",
                        payload: .metric(
                            GraphChatAnswerArtifactMetricPayload(
                                title: "Search",
                                value: .integer(1),
                                unit: nil,
                                contextDescription: firstSummary.displayText,
                                evidence: firstBinding
                            )
                        ),
                        evidence: firstBinding,
                        querySummary: firstSummary
                    )
                ],
                .graphStats: [
                    GraphChatAnswerArtifactDraft(
                        graphScope: graphScope,
                        title: "Statistics",
                        payload: .metric(
                            GraphChatAnswerArtifactMetricPayload(
                                title: "Statistics",
                                value: .integer(2),
                                unit: nil,
                                contextDescription: secondSummary.displayText,
                                evidence: secondBinding
                            )
                        ),
                        evidence: secondBinding,
                        querySummary: secondSummary
                    )
                ]
            ]
        )
        let provider = SectionArtifactEchoProvider()
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: factory,
            artifactRevalidator: GraphChatRegistryAnswerArtifactRevalidator()
        )
        let stream = await orchestrator.streamAnswer(
            question: "Compare search and statistics",
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )
        let events = await GraphChatProviderTestSupport.collect(stream)
        let answer = try #require(events.compactMap { event -> GraphChatAnswer? in
            if case .completed(let answer) = event {
                return answer
            }
            return nil
        }.last)

        #expect(answer.artifactIDs.count == 2)
        #expect(answer.sections.count == 2)
        #expect(answer.sections[0].artifactIDs.count == 1)
        #expect(answer.sections[1].artifactIDs.count == 1)
        #expect(answer.sections[0].artifactIDs[0] != answer.sections[1].artifactIDs[0])
        #expect(answer.sections[0].querySummary?.entityLabel == "Search")
        #expect(answer.sections[1].querySummary?.entityLabel == "Statistics")
        #expect(answer.sections[0].evidenceIDs == [firstEvidence.id])
        #expect(answer.sections[1].evidenceIDs == [secondEvidence.id])
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

    private func makeQuerySummary(
        graphScope: GraphScope,
        label: String,
        limit: Int
    ) -> GraphChatAnswerArtifactQuerySummary {
        GraphChatAnswerArtifactQuerySummary(
            language: .english,
            entityID: graphScope.graphID,
            entityLabel: label,
            filters: [],
            grouping: nil,
            sorting: [],
            projection: [],
            includesNodeIdentity: true,
            limit: limit,
            aggregation: nil,
            displayText: "Entity: \(label); Limit: \(limit)"
        )
    }

}


private actor SectionArtifactEchoProvider: GraphChatModelProvider {
    private var configurations: [GraphChatModelSessionID: GraphChatModelSessionConfiguration] = [:]

    func availability() async -> GraphChatModelAvailability {
        .available
    }

    func createSession(
        configuration: GraphChatModelSessionConfiguration
    ) async throws -> GraphChatModelSessionID {
        let sessionID = GraphChatModelSessionID()
        configurations[sessionID] = configuration
        return sessionID
    }

    func prewarm(
        sessionID: GraphChatModelSessionID,
        promptPrefix: String?
    ) async throws {
        guard configurations[sessionID] != nil else {
            throw GraphChatProviderError(
                code: .invalidSession,
                message: "Missing test session."
            )
        }
    }

    func streamResponse(
        sessionID: GraphChatModelSessionID,
        request: GraphChatModelRequest
    ) async throws -> GraphChatProviderEventStream {
        guard let configuration = configurations[sessionID] else {
            throw GraphChatProviderError(
                code: .invalidSession,
                message: "Missing test session."
            )
        }
        return GraphChatProviderEventStream { continuation in
            let task = Task {
                do {
                    let search = try await configuration.toolRunner.run(
                        .searchGraph(query: "alpha", limit: 5)
                    )
                    let stats = try await configuration.toolRunner.run(
                        .graphStats(hubLimit: 10)
                    )
                    continuation.yield(
                        .completed(
                            GraphChatProviderFinalAnswer(
                                directAnswer: "Two validated structured results.",
                                sections: [
                                    GraphChatProviderAnswerSection(
                                        title: "Search",
                                        text: "Search interpretation.",
                                        evidenceIDValues: search.evidenceIDs.map { $0.rawValue.uuidString },
                                        artifactIDValues: search.artifactIDs.map { $0.rawValue.uuidString }
                                    ),
                                    GraphChatProviderAnswerSection(
                                        title: "Statistics",
                                        text: "Statistics interpretation.",
                                        evidenceIDValues: stats.evidenceIDs.map { $0.rawValue.uuidString },
                                        artifactIDValues: stats.artifactIDs.map { $0.rawValue.uuidString }
                                    )
                                ],
                                evidenceIDValues: (search.evidenceIDs + stats.evidenceIDs).map {
                                    $0.rawValue.uuidString
                                },
                                artifactIDValues: (search.artifactIDs + stats.artifactIDs).map {
                                    $0.rawValue.uuidString
                                },
                                appliedFilters: [],
                                followUpSuggestions: [],
                                hasInsufficientEvidence: false
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func cancelGeneration(sessionID: GraphChatModelSessionID) async {
    }

    func discardSession(sessionID: GraphChatModelSessionID) async {
        configurations.removeValue(forKey: sessionID)
    }
}
