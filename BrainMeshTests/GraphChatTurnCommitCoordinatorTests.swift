import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph chat turn commit coordinator")
struct GraphChatTurnCommitCoordinatorTests {
    @Test
    func successfulTurnCommitsConversationStateAndArtifacts() async throws {
        let fixture = TurnCommitFixture()
        let staged = try await fixture.makeStagedArtifact()
        let transaction = fixture.makeConversationTransaction()
        let answer = GraphChatAnswer(
            directAnswer: "Committed",
            evidence: [staged.evidence],
            artifactIDs: [staged.artifactID],
            hasInsufficientEvidence: false
        )

        let turn = try await fixture.coordinator.commit(
            fixture.input(
                answer: answer,
                artifactContext: staged.artifactContext
            ),
            conversationTransaction: transaction,
            currentCommittedState: fixture.baseState,
            artifactRegistry: staged.registry
        )

        #expect(turn.answer.artifactIDs == [staged.artifactID])
        #expect(turn.committedArtifactIDs == [staged.artifactID])
        #expect(turn.conversationState.turnContexts.map(\.id) == [fixture.requestID])
        #expect(
            await staged.registry.snapshotForTesting().map(\.id)
                == [staged.artifactID]
        )
        #expect(
            await staged.registry.stagedSnapshotForTesting(
                transactionID: staged.artifactContext.transactionID
            ).isEmpty
        )
    }

    @Test
    func artifactCommitFailureCommitsNeitherStateNorArtifactsAndRollsBack() async throws {
        let fixture = TurnCommitFixture()
        let registry = TurnCommitRecordingArtifactRegistry(
            commitResult: .failure(.expectedCommitFailure)
        )
        let context = fixture.artifactContext()
        let transaction = fixture.makeConversationTransaction()
        let answer = GraphChatAnswer(
            directAnswer: "Must not commit",
            artifactIDs: [fixture.artifactID(1)],
            hasInsufficientEvidence: true
        )
        let previouslyCommittedState = fixture.baseState

        await #expect(throws: TurnCommitTestError.expectedCommitFailure) {
            _ = try await fixture.coordinator.commit(
                fixture.input(
                    answer: answer,
                    artifactContext: context
                ),
                conversationTransaction: transaction,
                currentCommittedState: previouslyCommittedState,
                artifactRegistry: registry
            )
        }

        let snapshot = await registry.snapshot()
        #expect(snapshot.commitCount == 1)
        #expect(snapshot.rollbackTransactionIDs == [context.transactionID])
        #expect(previouslyCommittedState == fixture.baseState)
    }

    @Test
    func cancellationCommitsNeitherStateNorArtifacts() async throws {
        let fixture = TurnCommitFixture()
        let context = fixture.artifactContext()
        let registry = TurnCommitRecordingArtifactRegistry(
            commitResult: .success([fixture.artifactID(2)])
        )
        let transaction = fixture.makeConversationTransaction()
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await fixture.coordinator.commit(
                fixture.input(
                    answer: GraphChatAnswer(
                        directAnswer: "Cancelled",
                        artifactIDs: [fixture.artifactID(2)],
                        hasInsufficientEvidence: true
                    ),
                    artifactContext: context
                ),
                conversationTransaction: transaction,
                currentCommittedState: fixture.baseState,
                artifactRegistry: registry
            )
        }

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        let snapshot = await registry.snapshot()
        #expect(snapshot.commitCount == 0)
        #expect(snapshot.rollbackTransactionIDs == [context.transactionID])
    }

    @Test
    func staleExpectedStateCommitsNeitherStateNorArtifacts() async throws {
        let fixture = TurnCommitFixture()
        let context = fixture.artifactContext()
        let registry = TurnCommitRecordingArtifactRegistry(
            commitResult: .success([fixture.artifactID(3)])
        )
        let staleCurrentState = GraphChatConversationState.initial(
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            conversationID: fixture.uuid(999)
        )

        await #expect(throws: CancellationError.self) {
            _ = try await fixture.coordinator.commit(
                fixture.input(
                    answer: GraphChatAnswer(
                        directAnswer: "Stale",
                        artifactIDs: [fixture.artifactID(3)],
                        hasInsufficientEvidence: true
                    ),
                    artifactContext: context
                ),
                conversationTransaction: fixture.makeConversationTransaction(),
                currentCommittedState: staleCurrentState,
                artifactRegistry: registry
            )
        }

        let snapshot = await registry.snapshot()
        #expect(snapshot.commitCount == 0)
        #expect(snapshot.rollbackTransactionIDs == [context.transactionID])
    }

    @Test
    func successfulCommitReducesTheAnswerToActuallyCommittedArtifactIDs() async throws {
        let fixture = TurnCommitFixture()
        let first = fixture.artifactID(4)
        let second = fixture.artifactID(5)
        let context = fixture.artifactContext()
        let registry = TurnCommitRecordingArtifactRegistry(
            commitResult: .success([second])
        )
        let answer = GraphChatAnswer(
            directAnswer: "Reduced",
            sections: [
                GraphChatAnswerSection(
                    text: "First",
                    artifactIDs: [first],
                    querySummary: fixture.querySummary()
                ),
                GraphChatAnswerSection(
                    text: "Second",
                    artifactIDs: [second],
                    querySummary: fixture.querySummary()
                ),
            ],
            artifactIDs: [first, second],
            hasInsufficientEvidence: true
        )

        let turn = try await fixture.coordinator.commit(
            fixture.input(
                answer: answer,
                artifactContext: context
            ),
            conversationTransaction: fixture.makeConversationTransaction(),
            currentCommittedState: fixture.baseState,
            artifactRegistry: registry
        )

        #expect(turn.answer.artifactIDs == [second])
        #expect(turn.answer.sections[0].artifactIDs.isEmpty)
        #expect(turn.answer.sections[0].querySummary == nil)
        #expect(turn.answer.sections[1].artifactIDs == [second])
        #expect(turn.answer.sections[1].querySummary != nil)
        #expect(turn.committedArtifactIDs == [second])
    }

    @Test
    func rollbackRemovesOnlyTheCurrentTransactionAndKeepsEarlierArtifacts() async throws {
        let fixture = TurnCommitFixture()
        let staged = try await fixture.makeStagedArtifact()
        try await staged.registry.commit(
            transactionID: staged.artifactContext.transactionID,
            retaining: [staged.artifactID]
        )

        let currentTransactionID = GraphChatAnswerArtifactTransactionID(
            rawValue: fixture.uuid(500)
        )
        let currentArtifactID = try await staged.registry.stage(
            fixture.artifactDraft(evidenceID: staged.evidence.id),
            transactionID: currentTransactionID,
            evidenceRegistry: staged.evidenceRegistry
        )
        let currentContext = GraphChatArtifactCommitContext(
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            sessionID: staged.artifactContext.sessionID,
            transactionID: currentTransactionID
        )
        let staleState = GraphChatConversationState.initial(
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            conversationID: fixture.uuid(501)
        )

        await #expect(throws: CancellationError.self) {
            _ = try await fixture.coordinator.commit(
                fixture.input(
                    answer: GraphChatAnswer(
                        directAnswer: "Stale current transaction",
                        artifactIDs: [currentArtifactID],
                        hasInsufficientEvidence: false
                    ),
                    artifactContext: currentContext
                ),
                conversationTransaction: fixture.makeConversationTransaction(),
                currentCommittedState: staleState,
                artifactRegistry: staged.registry
            )
        }

        #expect(
            await staged.registry.snapshotForTesting().map(\.id)
                == [staged.artifactID]
        )
        #expect(
            await staged.registry.stagedSnapshotForTesting(
                transactionID: currentTransactionID
            ).isEmpty
        )
    }

    @Test
    func localAnswerUsesTheSameStateCommitPathWithoutArtifacts() async throws {
        let fixture = TurnCommitFixture()
        let answer = GraphChatAnswer(
            state: .noResults,
            directAnswer: "Local no result",
            hasInsufficientEvidence: true
        )

        let turn = try await fixture.coordinator.commit(
            fixture.input(
                source: .local,
                answer: answer,
                artifactContext: nil
            ),
            conversationTransaction: fixture.makeConversationTransaction(),
            currentCommittedState: fixture.baseState
        )

        #expect(turn.answer == answer)
        #expect(turn.committedArtifactIDs.isEmpty)
        #expect(turn.completion.source == .local)
        #expect(turn.conversationState.turnContexts.map(\.id) == [fixture.requestID])
    }

    @Test
    func pendingClarificationIsCommittedWithTheTurn() async throws {
        let fixture = TurnCommitFixture()
        let pending = fixture.pendingClarification()
        let transaction = fixture.makeConversationTransaction()
        try await transaction.apply(
            GraphChatConversationTrustedEvent(
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                payload: .clarificationRequested(pending)
            )
        )
        let answer = GraphChatAnswer(
            state: .clarification(
                GraphChatClarification(
                    id: pending.id,
                    question: "Which one?",
                    options: pending.options.map {
                        GraphChatClarificationOption(
                            id: $0.id,
                            title: $0.title
                        )
                    }
                )
            ),
            directAnswer: "Which one?",
            hasInsufficientEvidence: true
        )

        let turn = try await fixture.coordinator.commit(
            fixture.input(
                source: .local,
                answer: answer,
                artifactContext: nil
            ),
            conversationTransaction: transaction,
            currentCommittedState: fixture.baseState
        )

        #expect(turn.conversationState.pendingClarification == pending)
        #expect(turn.conversationState.turnContexts.last?.id == fixture.requestID)
    }

    @Test
    func untrustedAssistantTextNeverEntersConversationState() async throws {
        let fixture = TurnCommitFixture()
        let untrustedText = "UNTRUSTED_ASSISTANT_TEXT_7D1F"
        let turn = try await fixture.coordinator.commit(
            fixture.input(
                source: .local,
                answer: GraphChatAnswer(
                    directAnswer: untrustedText,
                    hasInsufficientEvidence: true
                ),
                artifactContext: nil
            ),
            conversationTransaction: fixture.makeConversationTransaction(),
            currentCommittedState: fixture.baseState
        )

        let technicalDescription =
            turn.conversationState.turnContexts.last?.technicalDescription
            ?? ""
        #expect(String(reflecting: turn.conversationState).contains(untrustedText) == false)
        #expect(technicalDescription.contains(untrustedText) == false)
    }
}

private enum TurnCommitTestError: Error, Hashable, Sendable {
    case expectedCommitFailure
}

private actor TurnCommitRecordingArtifactRegistry:
    GraphChatAnswerArtifactFinalizationRegistry
{
    enum CommitResult: Sendable {
        case success([GraphChatAnswerArtifactID])
        case failure(TurnCommitTestError)
    }

    struct Snapshot: Sendable {
        let commitCount: Int
        let rollbackTransactionIDs: [GraphChatAnswerArtifactTransactionID]
    }

    private let commitResult: CommitResult
    private var commitCount = 0
    private var rollbackTransactionIDs: [GraphChatAnswerArtifactTransactionID] = []

    init(commitResult: CommitResult) {
        self.commitResult = commitResult
    }

    func validatedArtifacts(
        for rawValues: [String],
        graphScope: GraphScope,
        sessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async throws -> [GraphChatAnswerArtifact] {
        []
    }

    func commit(
        transactionID: GraphChatAnswerArtifactTransactionID,
        retaining artifactIDs: [GraphChatAnswerArtifactID]
    ) async throws -> [GraphChatAnswerArtifactID] {
        commitCount += 1
        switch commitResult {
        case .success(let ids):
            return ids
        case .failure(let error):
            throw error
        }
    }

    func rollback(
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async {
        rollbackTransactionIDs.append(transactionID)
    }

    func snapshot() -> Snapshot {
        Snapshot(
            commitCount: commitCount,
            rollbackTransactionIDs: rollbackTransactionIDs
        )
    }
}

private struct TurnCommitFixture {
    struct StagedArtifact {
        let evidence: GraphEvidence
        let evidenceRegistry: GraphChatEvidenceRegistry
        let registry: GraphChatAnswerArtifactRegistry
        let artifactID: GraphChatAnswerArtifactID
        let artifactContext: GraphChatArtifactCommitContext
    }

    let graphScope = GraphScope(
        graphID: UUID(uuidString: "F2000000-0000-0000-0000-000000000001")!
    )
    let requestID = UUID(
        uuidString: "F2000000-0000-0000-0000-000000000002"
    )!
    let completedAt = Date(timeIntervalSince1970: 1_800_000_100)
    let coordinator = GraphChatTurnCommitCoordinator()

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    var baseState: GraphChatConversationState {
        .initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: uuid(3)
        )
    }

    func makeConversationTransaction() -> GraphChatConversationStateTransaction {
        GraphChatConversationStateTransaction(
            baseState: baseState,
            reducer: GraphChatConversationStateReducer()
        )
    }

    func input(
        source: GraphChatFinalizedTurnSource = .provider,
        answer: GraphChatAnswer,
        artifactContext: GraphChatArtifactCommitContext?
    ) -> GraphChatTurnCommitInput {
        GraphChatTurnCommitInput(
            requestID: requestID,
            completedAt: completedAt,
            source: source,
            answer: answer,
            expectedCommittedState: baseState,
            artifactContext: artifactContext
        )
    }

    func artifactContext() -> GraphChatArtifactCommitContext {
        GraphChatArtifactCommitContext(
            graphScope: graphScope,
            chatScope: chatScope,
            sessionID: GraphChatAnswerArtifactSessionID(rawValue: uuid(10)),
            transactionID: GraphChatAnswerArtifactTransactionID(rawValue: uuid(11))
        )
    }

    func makeStagedArtifact() async throws -> StagedArtifact {
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .entity,
                sourceID: uuid(20)
            ),
            summary: "Committed evidence",
            identitySuffix: "commit"
        )
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: chatScope)
        try await evidenceRegistry.register([evidence])
        let context = artifactContext()
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: graphScope,
            scope: chatScope,
            sessionID: context.sessionID
        )
        let artifactID = try await registry.stage(
            artifactDraft(evidenceID: evidence.id),
            transactionID: context.transactionID,
            evidenceRegistry: evidenceRegistry
        )
        return StagedArtifact(
            evidence: evidence,
            evidenceRegistry: evidenceRegistry,
            registry: registry,
            artifactID: artifactID,
            artifactContext: context
        )
    }

    func artifactDraft(
        evidenceID: GraphEvidenceID
    ) -> GraphChatAnswerArtifactDraft {
        let binding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [evidenceID]
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: "Metric",
            payload: .metric(
                GraphChatAnswerArtifactMetricPayload(
                    title: "Count",
                    value: .integer(1),
                    unit: nil,
                    contextDescription: nil,
                    evidence: binding
                )
            ),
            evidence: binding
        )
    }

    func pendingClarification() -> GraphChatPendingClarification {
        GraphChatPendingClarification(
            id: uuid(30),
            decision: .conversationReference,
            options: [
                GraphChatPendingClarificationOption(
                    id: "A1",
                    title: "Entity",
                    proposal: .alias("A1")
                )
            ],
            sourceTurnID: nil,
            graphScope: graphScope,
            chatScope: chatScope,
            continuationOperation: .answerAboutReference,
            continuationQuestion: "Continue",
            createdAt: completedAt,
            expiresAt: completedAt.addingTimeInterval(600)
        )
    }

    func artifactID(_ suffix: Int) -> GraphChatAnswerArtifactID {
        GraphChatAnswerArtifactID(rawValue: uuid(100 + suffix))
    }

    func querySummary() -> GraphChatAnswerArtifactQuerySummary {
        GraphChatAnswerArtifactQuerySummary(
            language: .english,
            entityID: uuid(200),
            entityLabel: "Projects",
            filters: [],
            grouping: nil,
            sorting: [],
            projection: [],
            includesNodeIdentity: true,
            limit: 10,
            aggregation: nil,
            displayText: "Projects"
        )
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "F2000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    }
}
