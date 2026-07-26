import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph chat primary-result ledger")
struct GraphChatPrimaryResultLedgerTests {
    @Test
    func severalSuccessfulCallsUseStablePriorityAndLatestEqualKind() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)

        try await fixture.record(
            tool: .searchGraph,
            evidence: fixture.makeEvidence(1),
            in: ledger
        )
        try await fixture.record(
            tool: .queryDetailValues,
            evidence: fixture.makeEvidence(2),
            in: ledger
        )
        try await fixture.record(
            tool: .getNode,
            evidence: fixture.makeEvidence(3),
            in: ledger
        )
        let latestQueryEvidence = fixture.makeEvidence(4)
        try await fixture.record(
            tool: .queryDetailValues,
            evidence: latestQueryEvidence,
            in: ledger
        )

        let snapshot = await ledger.snapshotForTesting(
            transactionID: fixture.transactionID
        )
        #expect(snapshot.entries.count == 4)
        #expect(snapshot.primaryResult?.tool == .queryDetailValues)
        #expect(snapshot.primaryResult?.evidenceIDs == [latestQueryEvidence.id])
        #expect(snapshot.primaryResult?.metadata.sequence == 3)
    }

    @Test
    func successfulQueryAlwaysCarriesAuthoritativeEvidenceOrArtifact() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        let evidence = fixture.makeEvidence(5)
        try await fixture.record(
            tool: .queryDetailValues,
            evidence: evidence,
            in: ledger
        )

        let primary = await ledger.snapshotForTesting(
            transactionID: fixture.transactionID
        ).primaryResult

        #expect(primary?.completionStatus == .succeeded)
        #expect(primary?.hasAuthoritativeReferences == true)
        #expect(primary?.binding.request.graphScope == fixture.graphScope)
        #expect(primary?.binding.request.chatScope == fixture.chatScope)
    }

    @Test
    func emptyQueryCreatesTypedNoResultsPrimaryPath() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        try await ledger.record(
            response: GraphChatModelToolResponse(
                tool: .queryDetailValues,
                state: .noResults,
                content: "No matching rows.",
                evidenceIDs: []
            ),
            evidence: [],
            artifacts: [],
            transactionID: fixture.transactionID
        )

        let primary = await ledger.snapshotForTesting(
            transactionID: fixture.transactionID
        ).primaryResult

        #expect(primary?.kind == .query)
        #expect(primary?.completionStatus == .noResults)
        #expect(primary?.evidence.isEmpty == true)
        #expect(primary?.artifacts.isEmpty == true)
    }

    @Test
    func dataBearingSuccessIsNotReplacedByALaterEmptyExploratoryCall() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        let evidence = fixture.makeEvidence(10)
        try await fixture.record(
            tool: .queryDetailValues,
            evidence: evidence,
            in: ledger
        )
        try await ledger.record(
            response: GraphChatModelToolResponse(
                tool: .queryDetailValues,
                state: .noResults,
                content: "No matching rows.",
                evidenceIDs: []
            ),
            evidence: [],
            artifacts: [],
            transactionID: fixture.transactionID
        )

        let primary = await ledger.snapshotForTesting(
            transactionID: fixture.transactionID
        ).primaryResult

        #expect(primary?.tool == .queryDetailValues)
        #expect(primary?.evidenceIDs == [evidence.id])
    }

    @Test
    func failedToolNeverCreatesPrimaryResult() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        let wrapper = fixture.makeRecordingRunner(
            base: PrimaryResultThrowingRunner(error: .sourceUnavailable),
            ledger: ledger
        )

        await #expect(throws: GraphChatToolError.self) {
            _ = try await wrapper.run(
                .searchGraph(query: "project", limit: 10)
            )
        }
        #expect(
            await ledger.snapshotForTesting(
                transactionID: fixture.transactionID
            ).primaryResult == nil
        )
    }

    @Test
    func cancelledToolNeverCreatesPrimaryResult() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        let wrapper = fixture.makeRecordingRunner(
            base: PrimaryResultThrowingRunner(error: .cancelled),
            ledger: ledger
        )

        await #expect(throws: GraphChatToolError.self) {
            _ = try await wrapper.run(
                .queryDetailValues(
                    GraphChatModelQueryRequest(
                        entityAlias: "E1",
                        filters: [],
                        sortFieldAlias: nil,
                        sortDirection: nil,
                        projectionFieldAliases: [],
                        aggregation: nil,
                        aggregationFieldAlias: nil,
                        limit: 10
                    )
                )
            )
        }
        #expect(
            await ledger.snapshotForTesting(
                transactionID: fixture.transactionID
            ).entries.isEmpty
        )
    }

    @Test
    func failedAttemptTransactionIsDiscardedBeforeSelection() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        try await fixture.record(
            tool: .queryDetailValues,
            evidence: fixture.makeEvidence(6),
            transactionID: fixture.transactionID,
            in: ledger
        )
        await ledger.discard(transactionID: fixture.transactionID)
        let recoveryTransactionID = GraphChatAnswerArtifactTransactionID()
        let recoveryEvidence = fixture.makeEvidence(7)
        try await fixture.record(
            tool: .searchGraph,
            evidence: recoveryEvidence,
            transactionID: recoveryTransactionID,
            in: ledger
        )

        #expect(
            await ledger.snapshotForTesting(
                transactionID: fixture.transactionID
            ).entries.isEmpty
        )
        #expect(
            await ledger.snapshotForTesting(
                transactionID: recoveryTransactionID
            ).primaryResult?.evidenceIDs == [recoveryEvidence.id]
        )
    }

    @Test
    func earlierTurnSessionAndGraphLookupsCannotResolvePrimaryResult() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        try await fixture.record(
            tool: .queryDetailValues,
            evidence: fixture.makeEvidence(8),
            in: ledger
        )

        let earlierTurn = await ledger.primaryResult(
            requestID: fixture.uuid(808),
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            artifactSessionID: fixture.artifactSessionID,
            transactionID: fixture.transactionID
        )
        let foreignSession = await ledger.primaryResult(
            requestID: fixture.requestID,
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            artifactSessionID: GraphChatAnswerArtifactSessionID(
                rawValue: fixture.uuid(809)
            ),
            transactionID: fixture.transactionID
        )
        let foreignGraphScope = GraphScope(graphID: fixture.uuid(810))
        let foreignGraph = await ledger.primaryResult(
            requestID: fixture.requestID,
            graphScope: foreignGraphScope,
            chatScope: .entireGraph(foreignGraphScope),
            artifactSessionID: fixture.artifactSessionID,
            transactionID: fixture.transactionID
        )

        #expect(earlierTurn == nil)
        #expect(foreignSession == nil)
        #expect(foreignGraph == nil)
    }

    @Test
    func finishingARequestClearsEntriesBeforeAnotherTurnCanBind() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        try await fixture.record(
            tool: .queryDetailValues,
            evidence: fixture.makeEvidence(9),
            in: ledger
        )

        await ledger.finish(requestID: fixture.requestID)
        let nextRequestID = fixture.uuid(813)
        try await ledger.bind(requestID: nextRequestID)
        let snapshot = await ledger.snapshotForTesting()

        #expect(snapshot.requestBinding?.requestID == nextRequestID)
        #expect(snapshot.entries.isEmpty)
        #expect(snapshot.primaryResult == nil)
    }

    @Test
    func foreignGraphEvidenceCannotMakeASuccessfulRecordPrimary() async throws {
        let fixture = PrimaryResultLedgerFixture()
        let ledger = fixture.makeLedger()
        try await ledger.bind(requestID: fixture.requestID)
        let foreignEvidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: fixture.uuid(811),
                sourceKind: .entity,
                sourceID: fixture.uuid(812)
            ),
            summary: "Foreign graph",
            identitySuffix: "foreign"
        )
        try await fixture.record(
            tool: .queryDetailValues,
            evidence: foreignEvidence,
            in: ledger
        )

        let snapshot = await ledger.snapshotForTesting(
            transactionID: fixture.transactionID
        )
        #expect(snapshot.entries.first?.completionStatus == .unverified)
        #expect(snapshot.primaryResult == nil)
    }
}

private struct PrimaryResultLedgerFixture {
    let graphScope = GraphScope(
        graphID: UUID(
            uuidString: "F4000000-0000-0000-0000-000000000001"
        )!
    )
    let requestID = UUID(
        uuidString: "F4000000-0000-0000-0000-000000000002"
    )!
    let artifactSessionID = GraphChatAnswerArtifactSessionID(
        rawValue: UUID(
            uuidString: "F4000000-0000-0000-0000-000000000003"
        )!
    )
    let transactionID = GraphChatAnswerArtifactTransactionID(
        rawValue: UUID(
            uuidString: "F4000000-0000-0000-0000-000000000004"
        )!
    )

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    func makeLedger() -> GraphChatPrimaryResultLedger {
        GraphChatPrimaryResultLedger(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: artifactSessionID
        )
    }

    func makeEvidence(_ index: Int) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .entity,
                sourceID: uuid(100 + index)
            ),
            summary: "Evidence \(index)",
            identitySuffix: String(index)
        )
    }

    func record(
        tool: GraphChatToolKind,
        evidence: GraphEvidence,
        transactionID: GraphChatAnswerArtifactTransactionID? = nil,
        in ledger: GraphChatPrimaryResultLedger
    ) async throws {
        try await ledger.record(
            response: GraphChatModelToolResponse(
                tool: tool,
                state: .success,
                content: "Validated result",
                evidenceIDs: [evidence.id]
            ),
            evidence: [evidence],
            artifacts: [],
            transactionID: transactionID ?? self.transactionID
        )
    }

    func makeRecordingRunner(
        base: any GraphChatModelToolRunning,
        ledger: GraphChatPrimaryResultLedger
    ) -> GraphChatPrimaryResultRecordingToolRunner {
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: chatScope)
        let artifactRegistry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            scope: chatScope,
            sessionID: artifactSessionID
        )
        return GraphChatPrimaryResultRecordingToolRunner(
            base: base,
            ledger: ledger,
            graphScope: graphScope,
            artifactSessionID: artifactSessionID,
            transactionID: transactionID,
            evidenceRegistry: evidenceRegistry,
            artifactRegistry: artifactRegistry
        )
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "F4000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    }
}

private struct PrimaryResultThrowingRunner: GraphChatModelToolRunning {
    let error: GraphChatToolErrorCode

    func registeredToolKinds() async -> Set<GraphChatToolKind> {
        Set(GraphChatToolKind.allCases)
    }

    func run(
        _ request: GraphChatModelToolRequest
    ) async throws -> GraphChatModelToolResponse {
        throw GraphChatToolError(
            code: error,
            message: "Expected test failure."
        )
    }
}
