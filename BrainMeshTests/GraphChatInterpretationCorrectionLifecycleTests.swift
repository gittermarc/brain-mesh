//
//  GraphChatInterpretationCorrectionLifecycleTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

private nonisolated struct
    GraphChatCorrectionLifecycleScript:
    Sendable
{
    let events: [GraphChatStreamEvent]
    let waitsForCancellation: Bool

    init(
        events: [GraphChatStreamEvent],
        waitsForCancellation: Bool = false
    ) {
        self.events = events
        self.waitsForCancellation =
            waitsForCancellation
    }
}

private nonisolated struct
    GraphChatCorrectionLifecycleOrchestratorSnapshot:
    Sendable
{
    let answerQuestions: [String]
    let correctionRequests:
        [GraphChatInterpretationCorrectionRequest]
    let correctionStreamAttemptCount: Int
    let cancellationCount: Int
    let conversationState:
        GraphChatConversationState?
}

private actor
    GraphChatCorrectionLifecycleOrchestrator:
    GraphChatOrchestrating
{
    private var scripts:
        [GraphChatCorrectionLifecycleScript]
    private var artifactSessionID:
        GraphChatAnswerArtifactSessionID
    private var answerQuestions: [String] = []
    private var correctionRequests:
        [GraphChatInterpretationCorrectionRequest] = []
    private var correctionStreamAttemptCount = 0
    private var cancellationCount = 0
    private var conversationState:
        GraphChatConversationState?
    private var activeTask:
        Task<Void, Never>?
    private let correctionStreamStartDelayNanoseconds:
        UInt64

    init(
        scripts:
            [GraphChatCorrectionLifecycleScript],
        artifactSessionID:
            GraphChatAnswerArtifactSessionID,
        correctionStreamStartDelayNanoseconds:
            UInt64 = 0
    ) {
        self.scripts = scripts
        self.artifactSessionID =
            artifactSessionID
        self.correctionStreamStartDelayNanoseconds =
            correctionStreamStartDelayNanoseconds
    }

    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream {
        answerQuestions.append(question)
        let pair = GraphChatEventStream.makeStream()
        pair.continuation.yield(
            .failure(
                GraphChatError(
                    code: .unexpected,
                    message:
                        "A correction test must not request a free answer."
                )
            )
        )
        pair.continuation.finish()
        return pair.stream
    }

    func streamCorrectedIntent(
        _ request:
            GraphChatInterpretationCorrectionRequest
    ) async -> GraphChatEventStream {
        correctionStreamAttemptCount += 1
        if correctionStreamStartDelayNanoseconds > 0 {
            do {
                try await Task.sleep(
                    nanoseconds:
                        correctionStreamStartDelayNanoseconds
                )
                try Task.checkCancellation()
            } catch {
                let pair =
                    GraphChatEventStream.makeStream()
                pair.continuation.yield(
                    .cancelled
                )
                pair.continuation.finish()
                return pair.stream
            }
        }
        correctionRequests.append(request)
        let script =
            scripts.isEmpty
            ? GraphChatCorrectionLifecycleScript(
                events: [
                    .failure(
                        GraphChatError(
                            code: .unexpected,
                            message:
                                "Missing correction test script."
                        )
                    ),
                ]
            )
            : scripts.removeFirst()
        let pair = GraphChatEventStream.makeStream()
        let task = Task { [weak self] in
            do {
                for event in script.events {
                    try Task.checkCancellation()
                    if case .completed(let answer) =
                            event {
                        await self?
                            .commitCorrectedTurn(
                                answer: answer,
                                request: request
                            )
                    }
                    pair.continuation.yield(event)
                }
                if script.waitsForCancellation {
                    try await Task.sleep(
                        nanoseconds: UInt64.max
                    )
                }
                pair.continuation.finish()
            } catch is CancellationError {
                pair.continuation.yield(.cancelled)
                pair.continuation.finish()
            } catch {
                pair.continuation.yield(
                    .failure(
                        GraphChatError(
                            code: .unexpected,
                            message:
                                "Correction test stream failed."
                        )
                    )
                )
                pair.continuation.finish()
            }
            await self?.clearActiveTask()
        }
        activeTask = task
        pair.continuation.onTermination = {
            @Sendable _ in
            task.cancel()
        }
        return pair.stream
    }

    func cancelCurrentGeneration() async {
        cancellationCount += 1
        let task = activeTask
        task?.cancel()
        await task?.value
    }

    func discardSession() async {
        conversationState = nil
    }

    func discardSession(
        reason:
            GraphChatConversationResetReason
    ) async {
        conversationState = nil
    }

    func conversationStateSnapshot()
        async -> GraphChatConversationState?
    {
        conversationState
    }

    func restoreConversationState(
        from checkpoint:
            GraphChatConversationCheckpoint
    ) async throws {
        guard
            checkpoint.belongsTo(
                graphScope:
                    checkpoint.graphScope,
                chatScope:
                    checkpoint.chatScope
            )
        else {
            throw GraphChatError(
                code: .invalidRequest,
                message:
                    "Invalid correction test checkpoint."
            )
        }
        conversationState =
            checkpoint.state
    }

    func resolveAnswerPresentation(
        artifactIDs:
            [GraphChatAnswerArtifactID],
        evidence: [GraphEvidence],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async
        -> GraphChatAnswerPresentationResolution
    {
        GraphChatAnswerPresentationResolution(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID:
                artifactSessionID,
            requestedArtifactIDs:
                artifactIDs,
            artifacts: [],
            evidence: evidence
        )
    }

    func snapshot()
        -> GraphChatCorrectionLifecycleOrchestratorSnapshot
    {
        GraphChatCorrectionLifecycleOrchestratorSnapshot(
            answerQuestions: answerQuestions,
            correctionRequests:
                correctionRequests,
            correctionStreamAttemptCount:
                correctionStreamAttemptCount,
            cancellationCount:
                cancellationCount,
            conversationState:
                conversationState
        )
    }

    private func commitCorrectedTurn(
        answer: GraphChatAnswer,
        request:
            GraphChatInterpretationCorrectionRequest
    ) {
        guard
            let interpretation =
                answer.interpretation
        else {
            return
        }
        var state =
            GraphChatConversationState.initial(
                graphScope:
                    request.binding.graphScope,
                chatScope:
                    request.binding.chatScope,
                conversationID:
                    request.binding
                        .conversationID
            )
        state.turnContexts = [
            GraphChatConversationTurnContext(
                id:
                    interpretation
                        .turnBinding.turnID,
                completedAt:
                    Date(
                        timeIntervalSince1970:
                            400
                    ),
                toolKinds: [],
                resultContextIDs: [],
                evidenceIDs:
                    answer.evidenceIDs,
                technicalDescription:
                    "Committed corrected local turn"
            ),
        ]
        if let replacementSessionID =
                interpretation
                    .correctionOrigin?
                    .artifactSessionID {
            artifactSessionID =
                replacementSessionID
        }
        conversationState = state
    }

    private func clearActiveTask() {
        activeTask = nil
    }
}

private nonisolated struct
    GraphChatCorrectionLifecycleHistory:
    Sendable
{
    let messages: [GraphChatTranscriptMessage]
    let originalUserID: UUID
    let originalAssistantID: UUID
    let suffixUserID: UUID?
    let suffixAssistantID: UUID?
}

private nonisolated enum
    GraphChatCorrectionLifecycleFixtureError:
    Error
{
    case interpretationCouldNotBeBuilt
}

private nonisolated struct
    GraphChatCorrectionLifecycleFixture
{
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let conversationID: UUID
    let originalTurnID: UUID
    let suffixTurnID: UUID
    let replacementTurnID: UUID
    let originalUserID: UUID
    let originalAssistantID: UUID
    let suffixUserID: UUID
    let suffixAssistantID: UUID
    let artifactSessionID:
        GraphChatAnswerArtifactSessionID
    let replacementArtifactSessionID:
        GraphChatAnswerArtifactSessionID

    init() {
        let resolvedGraphScope =
            GraphScope(graphID: UUID())
        graphScope = resolvedGraphScope
        chatScope =
            .entireGraph(
                resolvedGraphScope
            )
        conversationID = UUID()
        originalTurnID = UUID()
        suffixTurnID = UUID()
        replacementTurnID = UUID()
        originalUserID = UUID()
        originalAssistantID = UUID()
        suffixUserID = UUID()
        suffixAssistantID = UUID()
        artifactSessionID =
            GraphChatAnswerArtifactSessionID()
        replacementArtifactSessionID =
            GraphChatAnswerArtifactSessionID()
    }

    func history(
        trusted: Bool,
        includesSuffix: Bool
    ) throws
        -> GraphChatCorrectionLifecycleHistory
    {
        let initial =
            GraphChatConversationCheckpoint
                .initial(
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        let firstCommitted =
            GraphChatConversationCheckpoint
                .committed(
                    conversationState(
                        turnIDs: [
                            originalTurnID,
                        ]
                    )
                )
        let interpretation =
            try makeGraphStateInterpretation(
                turnID: originalTurnID,
                aspect: .health,
                artifactSessionID:
                    trusted
                    ? artifactSessionID
                    : nil
            )
        var originalAssistantState =
            GraphChatAssistantMessageState(
                question: originalQuestion
            )
        originalAssistantState.apply(
            .completed(
                GraphChatAnswer(
                    directAnswer:
                        originalAnswer,
                    hasInsufficientEvidence:
                        false,
                    interpretation:
                        interpretation
                )
            )
        )
        var messages = [
            GraphChatTranscriptMessage(
                id: originalUserID,
                createdAt:
                    Date(
                        timeIntervalSince1970:
                            100
                    ),
                state:
                    .userQuestion(
                        originalQuestion
                    ),
                conversationCheckpointBeforeTurn:
                    initial
            ),
            GraphChatTranscriptMessage(
                id: originalAssistantID,
                createdAt:
                    Date(
                        timeIntervalSince1970:
                            101
                    ),
                state:
                    .assistant(
                        originalAssistantState
                    ),
                conversationCheckpointBeforeTurn:
                    initial,
                conversationCheckpointAfterTurn:
                    firstCommitted
            ),
        ]

        guard includesSuffix else {
            return GraphChatCorrectionLifecycleHistory(
                messages: messages,
                originalUserID:
                    originalUserID,
                originalAssistantID:
                    originalAssistantID,
                suffixUserID: nil,
                suffixAssistantID: nil
            )
        }

        let suffixCommitted =
            GraphChatConversationCheckpoint
                .committed(
                    conversationState(
                        turnIDs: [
                            originalTurnID,
                            suffixTurnID,
                        ]
                    )
                )
        var suffixAssistantState =
            GraphChatAssistantMessageState(
                question: suffixQuestion
            )
        suffixAssistantState.apply(
            .completed(
                GraphChatAnswer(
                    directAnswer:
                        suffixAnswer,
                    hasInsufficientEvidence:
                        false
                )
            )
        )
        messages.append(
            GraphChatTranscriptMessage(
                id: suffixUserID,
                createdAt:
                    Date(
                        timeIntervalSince1970:
                            200
                    ),
                state:
                    .userQuestion(
                        suffixQuestion
                    ),
                conversationCheckpointBeforeTurn:
                    firstCommitted
            )
        )
        messages.append(
            GraphChatTranscriptMessage(
                id: suffixAssistantID,
                createdAt:
                    Date(
                        timeIntervalSince1970:
                            201
                    ),
                state:
                    .assistant(
                        suffixAssistantState
                    ),
                conversationCheckpointBeforeTurn:
                    firstCommitted,
                conversationCheckpointAfterTurn:
                    suffixCommitted
            )
        )
        return GraphChatCorrectionLifecycleHistory(
            messages: messages,
            originalUserID:
                originalUserID,
            originalAssistantID:
                originalAssistantID,
            suffixUserID:
                suffixUserID,
            suffixAssistantID:
                suffixAssistantID
        )
    }

    func replacementAnswer()
        throws -> GraphChatAnswer
    {
        GraphChatAnswer(
            directAnswer: replacementAnswerText,
            hasInsufficientEvidence: false,
            interpretation:
                try makeGraphStateInterpretation(
                    turnID:
                        replacementTurnID,
                    aspect: .overview,
                    artifactSessionID:
                        replacementArtifactSessionID
                )
        )
    }

    var originalQuestion: String {
        "Wie ist der Zustand des Graphen?"
    }

    var originalAnswer: String {
        "Der Graph ist gesund."
    }

    var suffixQuestion: String {
        "Und wie viele Einträge gibt es?"
    }

    var suffixAnswer: String {
        "Es gibt mehrere Einträge."
    }

    var replacementAnswerText: String {
        "Hier ist die korrigierte Übersicht."
    }

    private func makeGraphStateInterpretation(
        turnID: UUID,
        aspect:
            GraphChatGraphStateAspect,
        artifactSessionID:
            GraphChatAnswerArtifactSessionID?
    ) throws
        -> GraphChatIntentInterpretation
    {
        let action =
            GraphChatLocalGraphStateAction(
                aspect: aspect,
                hubLimit:
                    GraphChatAdvancedIntentPolicy
                        .default.graphHubLimit
            )
        let intent = try GraphChatTypedIntent(
            version: .v1,
            scope:
                GraphChatTypedIntentScope(
                    graphScope: graphScope,
                    chatScope: chatScope,
                    queryScope: chatScope
                ),
            responseLanguage: .german,
            binding:
                GraphChatTypedIntentBinding(
                    requestID: turnID,
                    conversationID:
                        conversationID,
                    turnID: turnID,
                    sourceTurnID: nil,
                    clarificationID: nil
                ),
            resolution:
                GraphChatTypedIntentResolution(
                    source:
                        .appSemanticResolution,
                    origin: .appRule,
                    quality: .exact
                ),
            expectedCardinality:
                .exactlyOne,
            factExpectation: .none,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit:
                        action.hubLimit,
                    maximumResultLimit:
                        GraphQueryPlanLimits
                            .maximumResultLimit,
                    maximumEvidenceCount:
                        GraphChatAdvancedIntentPolicy
                            .default
                            .maximumEvidenceCount,
                    maximumArtifactCount:
                        GraphChatAdvancedIntentPolicy
                            .default
                            .maximumArtifactCount
                ),
            payload:
                .inspectGraphState(
                    GraphChatTypedInspectGraphStateIntent(
                        aspect: aspect
                    )
                )
        )
        let origin =
            artifactSessionID.map {
                GraphChatInterpretationCorrectionOrigin(
                    adaptation:
                        GraphChatTypedIntentAdaptation(
                            intent: intent,
                            action:
                                .inspectGraphState(
                                    action
                                )
                        ),
                    artifactSessionID: $0,
                    requestQuestion:
                        originalQuestion
                )
            }
        guard
            let interpretation =
                GraphChatIntentInterpretationBuilder(
                    timeZone:
                        TimeZone(
                            secondsFromGMT: 0
                        )!
                )
                .graphStateInterpretation(
                    intent: intent,
                    action: action,
                    correctionOrigin:
                        origin
                )
        else {
            throw GraphChatCorrectionLifecycleFixtureError
                .interpretationCouldNotBeBuilt
        }
        return interpretation
    }

    private func conversationState(
        turnIDs: [UUID]
    ) -> GraphChatConversationState {
        var state =
            GraphChatConversationState.initial(
                graphScope: graphScope,
                chatScope: chatScope,
                conversationID:
                    conversationID
            )
        state.turnContexts =
            turnIDs.enumerated().map {
                index,
                turnID in
                GraphChatConversationTurnContext(
                    id: turnID,
                    completedAt:
                        Date(
                            timeIntervalSince1970:
                                Double(
                                    index + 1
                                )
                        ),
                    toolKinds: [],
                    resultContextIDs: [],
                    evidenceIDs: [],
                    technicalDescription:
                        "Committed turn \(index + 1)"
                )
            }
        return state
    }
}

@MainActor
private struct
    GraphChatCorrectionLifecycleSetup
{
    let viewModel: GraphChatViewModel
    let orchestrator:
        GraphChatCorrectionLifecycleOrchestrator
    let historyStore:
        InMemoryGraphChatHistoryStore
    let feedbackStore:
        InMemoryGraphChatFeedbackStore
}

@MainActor
private final class
    GraphChatCorrectionLifecycleAccessDecisionBox
{
    var decision:
        GraphChatAccessDecision

    init(
        decision:
            GraphChatAccessDecision
    ) {
        self.decision = decision
    }
}

@Suite(
    "Graph chat interpretation correction lifecycle"
)
@MainActor
struct GraphChatInterpretationCorrectionLifecycleTests {
    @Test
    func editorOpensOnlyForTrustedEditableInterpretation()
        async throws
    {
        let fixture =
            GraphChatCorrectionLifecycleFixture()
        let trustedHistory =
            try fixture.history(
                trusted: true,
                includesSuffix: false
            )
        let trusted =
            await makeSetup(
                fixture: fixture,
                history: trustedHistory
            )

        trusted.viewModel
            .openInterpretationCorrection(
                messageID:
                    trustedHistory
                        .originalAssistantID
            )
        await waitForEditor(
            trusted.viewModel
        )

        let trustedSession =
            try #require(
                trusted.viewModel
                    .correctionEditorSession
            )
        #expect(
            trustedSession.validationState
                == .ready
        )
        #expect(
            trustedSession.capabilities
                .isEditable
        )
        trusted.viewModel
            .cancelInterpretationCorrection()

        let legacyHistory =
            try fixture.history(
                trusted: false,
                includesSuffix: false
            )
        let legacy =
            await makeSetup(
                fixture: fixture,
                history: legacyHistory
            )

        legacy.viewModel
            .openInterpretationCorrection(
                messageID:
                    legacyHistory
                        .originalAssistantID
            )
        await Task.yield()

        #expect(
            legacy.viewModel
                .correctionEditorSession
                == nil
        )
    }

    @Test
    func cancelLeavesTranscriptCheckpointAndRuntimeStateUnchanged()
        async throws
    {
        let fixture =
            GraphChatCorrectionLifecycleFixture()
        let history =
            try fixture.history(
                trusted: true,
                includesSuffix: true
            )
        let setup =
            await makeSetup(
                fixture: fixture,
                history: history
            )
        let transcriptBefore =
            setup.viewModel.messages
        let runtimeBefore =
            await setup.orchestrator
                .snapshot()
                .conversationState

        setup.viewModel
            .openInterpretationCorrection(
                messageID:
                    history.originalAssistantID
            )
        await waitForEditor(
            setup.viewModel
        )
        setup.viewModel
            .cancelInterpretationCorrection()

        #expect(
            setup.viewModel.messages
                == transcriptBefore
        )
        #expect(
            setup.viewModel
                .correctionEditorSession
                == nil
        )
        #expect(
            await setup.historyStore
                .messages(
                    for: fixture.chatScope
                )
                == transcriptBefore
        )
        #expect(
            await setup.orchestrator
                .snapshot()
                .conversationState
                == runtimeBefore
        )
    }

    @Test
    func preflightRejectionDoesNotFinishAnotherActiveSessionMutation()
        async throws
    {
        let fixture =
            GraphChatCorrectionLifecycleFixture()
        let history =
            try fixture.history(
                trusted: true,
                includesSuffix: false
            )
        let orchestrator =
            GraphChatCorrectionLifecycleOrchestrator(
                scripts: [],
                artifactSessionID:
                    fixture.artifactSessionID
            )
        let harness =
            GraphChatMessageActionControllerHarness(
                graphScope:
                    fixture.graphScope,
                chatScope:
                    fixture.chatScope,
                orchestrator:
                    orchestrator,
                messages: history.messages
            )
        let plan = try #require(
            GraphChatInterpretationCorrectionPlanner
                .plan(
                    messages: history.messages,
                    assistantMessageID:
                        history.originalAssistantID,
                    graphScope:
                        fixture.graphScope,
                    chatScope:
                        fixture.chatScope
                )
        )
        let request =
            GraphChatInterpretationCorrectionRequest(
                binding: plan.binding,
                selection:
                    GraphChatInterpretationCorrectionSelection(
                        graphStateAspect:
                            .overview
                    )
            )
        harness.isPerformingSessionMutation =
            true

        harness.controller
            .applyInterpretationCorrection(
                request,
                snapshot: harness.snapshot
            )
        await Task.yield()

        #expect(
            harness.isPerformingSessionMutation
        )
        #expect(
            await orchestrator
                .snapshot()
                .correctionRequests
                .isEmpty
        )
    }

    @Test
    func repeatedApplySubmitsOnceAndCancellationKeepsOldAnswer()
        async throws
    {
        let fixture =
            GraphChatCorrectionLifecycleFixture()
        let history =
            try fixture.history(
                trusted: true,
                includesSuffix: false
            )
        let setup =
            await makeSetup(
                fixture: fixture,
                history: history,
                scripts: [
                    GraphChatCorrectionLifecycleScript(
                        events: [],
                        waitsForCancellation: true
                    ),
                ]
            )
        setup.viewModel
            .openInterpretationCorrection(
                messageID:
                    history.originalAssistantID
            )
        await waitForEditor(
            setup.viewModel
        )
        let selection =
            try #require(
                setup.viewModel
                    .correctionEditorSession
            ).selection

        setup.viewModel
            .applyInterpretationCorrection(
                selection
            )
        setup.viewModel
            .applyInterpretationCorrection(
                selection
            )
        await GraphChatUITestSupport
            .waitUntil(
                maximumYields: 20_000
            ) {
                setup.viewModel
                    .correctionEditorSession?
                    .isApplying == true
            }
        await waitForCorrectionRequest(
            setup.orchestrator
        )

        #expect(
            await setup.orchestrator
                .snapshot()
                .correctionRequests
                .count == 1
        )

        setup.viewModel
            .cancelInterpretationCorrection()
        await GraphChatUITestSupport
            .waitUntil(
                maximumYields: 20_000
            ) {
                setup.viewModel
                    .correctionEditorSession
                    == nil
                    && setup.viewModel
                        .isPerformingSessionMutation
                        == false
            }

        #expect(
            setup.viewModel.messages
                == history.messages
        )
        #expect(
            answerText(
                in: setup.viewModel.messages,
                messageID:
                    history.originalAssistantID
            ) == fixture.originalAnswer
        )
        #expect(
            await setup.orchestrator
                .snapshot()
                .cancellationCount >= 2
        )
    }

    @Test
    func cancellationBeforeCorrectionStreamInstallationPreventsLateRerun()
        async throws
    {
        let fixture =
            GraphChatCorrectionLifecycleFixture()
        let history =
            try fixture.history(
                trusted: true,
                includesSuffix: false
            )
        let setup =
            await makeSetup(
                fixture: fixture,
                history: history,
                correctionStreamStartDelayNanoseconds:
                    200_000_000
            )
        setup.viewModel
            .openInterpretationCorrection(
                messageID:
                    history.originalAssistantID
            )
        await waitForEditor(
            setup.viewModel
        )
        let selection =
            try #require(
                setup.viewModel
                    .correctionEditorSession
            ).selection

        setup.viewModel
            .applyInterpretationCorrection(
                selection
            )
        await GraphChatProviderTestSupport
            .waitUntil {
                await setup.orchestrator
                    .snapshot()
                    .correctionStreamAttemptCount
                    == 1
            }
        setup.viewModel
            .cancelInterpretationCorrection()
        await GraphChatUITestSupport
            .waitUntil(
                maximumYields: 20_000
            ) {
                setup.viewModel
                    .correctionEditorSession
                    == nil
                    && setup.viewModel
                        .isPerformingSessionMutation
                        == false
            }
        await Task.yield()

        let orchestratorSnapshot =
            await setup.orchestrator
                .snapshot()
        #expect(
            orchestratorSnapshot
                .correctionRequests
                .isEmpty
        )
        #expect(
            orchestratorSnapshot
                .cancellationCount >= 1
        )
        #expect(
            setup.viewModel.messages
                == history.messages
        )
    }

    @Test
    func correctionFailureKeepsOldSuccessfulAnswer()
        async throws
    {
        let fixture =
            GraphChatCorrectionLifecycleFixture()
        let history =
            try fixture.history(
                trusted: true,
                includesSuffix: false
            )
        let setup =
            await makeSetup(
                fixture: fixture,
                history: history,
                scripts: [
                    GraphChatCorrectionLifecycleScript(
                        events: [
                            .failure(
                                GraphChatError(
                                    code:
                                        .toolFailure,
                                    message:
                                        "internal failure detail"
                                )
                            ),
                        ]
                    ),
                ]
            )
        setup.viewModel
            .openInterpretationCorrection(
                messageID:
                    history.originalAssistantID
            )
        await waitForEditor(
            setup.viewModel
        )
        let selection =
            try #require(
                setup.viewModel
                    .correctionEditorSession
            ).selection

        setup.viewModel
            .applyInterpretationCorrection(
                selection
            )
        await GraphChatUITestSupport
            .waitUntil(
                maximumYields: 20_000
            ) {
                setup.viewModel
                    .correctionEditorSession?
                    .isApplying == false
                    && setup.viewModel
                        .isPerformingSessionMutation
                        == false
                    && setup.viewModel
                        .correctionEditorSession
                        != nil
            }

        #expect(
            setup.viewModel.messages
                == history.messages
        )
        #expect(
            answerText(
                in: setup.viewModel.messages,
                messageID:
                    history.originalAssistantID
            ) == fixture.originalAnswer
        )
        #expect(
            setup.viewModel
                .correctionEditorSession?
                .validationState
                == .stale(
                    .schemaChanged
                )
        )
        #expect(
            setup.viewModel.actionNotice?
                .message.contains(
                    "internal failure detail"
                ) != true
        )
        setup.viewModel
            .cancelInterpretationCorrection()
    }

    @Test
    func graphChangeAndLockInvalidateAnOpenEditorWithoutChangingTranscript()
        async throws
    {
        let fixture =
            GraphChatCorrectionLifecycleFixture()
        let history =
            try fixture.history(
                trusted: true,
                includesSuffix: true
            )
        let access =
            GraphChatCorrectionLifecycleAccessDecisionBox(
                decision:
                    readyAccessDecision
            )
        let setup =
            await makeSetup(
                fixture: fixture,
                history: history,
                accessDecisionBox: access
            )
        let transcriptBefore =
            setup.viewModel.messages

        setup.viewModel
            .openInterpretationCorrection(
                messageID:
                    history.originalAssistantID
            )
        await waitForEditor(
            setup.viewModel
        )

        access.decision =
            GraphChatAccessDecision(
                route: .noActiveGraph,
                canPresentChat: false,
                canStartGeneration: false,
                canCancelGeneration: true,
                usesIndexFallback: false
            )
        setup.viewModel
            .notifyGenerationAccessChanged()

        #expect(
            setup.viewModel
                .correctionEditorSession?
                .validationState
                == .stale(.scopeChanged)
        )
        #expect(
            setup.viewModel.messages
                == transcriptBefore
        )

        access.decision =
            GraphChatAccessDecision(
                route: .graphLocked,
                canPresentChat: false,
                canStartGeneration: false,
                canCancelGeneration: true,
                usesIndexFallback: false
            )
        setup.viewModel
            .notifyGenerationAccessChanged()

        #expect(
            setup.viewModel
                .correctionEditorSession?
                .validationState
                == .stale(.graphLocked)
        )
        #expect(
            setup.viewModel.messages
                == transcriptBefore
        )
        #expect(
            await setup.historyStore
                .messages(
                    for: fixture.chatScope
                )
                == transcriptBefore
        )

        setup.viewModel
            .cancelInterpretationCorrection()
    }

    @Test
    func successfulCorrectionReplacesSuffixAndRemovesFeedback()
        async throws
    {
        let fixture =
            GraphChatCorrectionLifecycleFixture()
        let history =
            try fixture.history(
                trusted: true,
                includesSuffix: true
            )
        let replacementAnswer =
            try fixture.replacementAnswer()
        let suffixUserID =
            try #require(
                history.suffixUserID
            )
        let suffixAssistantID =
            try #require(
                history.suffixAssistantID
            )
        let feedbackIDs = [
            history.originalAssistantID,
            suffixAssistantID,
        ]
        let setup =
            await makeSetup(
                fixture: fixture,
                history: history,
                scripts: [
                    GraphChatCorrectionLifecycleScript(
                        events: [
                            .started(
                                requestID:
                                    fixture
                                        .replacementTurnID
                            ),
                            .partialAnswer(
                                "Korrigierte "
                            ),
                            .completed(
                                replacementAnswer
                            ),
                        ]
                    ),
                ],
                feedbackMessageIDs:
                    feedbackIDs
            )
        #expect(
            setup.viewModel
                .feedbackByMessageID
                .count == 2
        )
        setup.viewModel
            .openInterpretationCorrection(
                messageID:
                    history.originalAssistantID
            )
        await waitForEditor(
            setup.viewModel
        )
        var selection =
            try #require(
                setup.viewModel
                    .correctionEditorSession
            ).selection
        selection.graphStateAspect =
            .overview

        setup.viewModel
            .applyInterpretationCorrection(
                selection
            )
        await GraphChatUITestSupport
            .waitUntil(
                maximumYields: 20_000
            ) {
                setup.viewModel
                    .correctionEditorSession
                    == nil
                    && setup.viewModel
                        .isPerformingSessionMutation
                        == false
                    && setup.viewModel
                        .messages.count == 2
            }

        #expect(
            setup.viewModel.messages
                .first?.id
                == history.originalUserID
        )
        #expect(
            setup.viewModel.messages
                .contains {
                    $0.id
                        == history
                            .originalAssistantID
                } == false
        )
        #expect(
            setup.viewModel.messages
                .contains {
                    $0.id
                        == suffixUserID
                } == false
        )
        #expect(
            setup.viewModel.messages
                .contains {
                    $0.id
                        == suffixAssistantID
                } == false
        )
        #expect(
            answerText(
                in: setup.viewModel.messages,
                messageID:
                    setup.viewModel.messages[1]
                        .id
            )
                == fixture
                    .replacementAnswerText
        )
        #expect(
            setup.viewModel.messages[1]
                .conversationCheckpointBeforeTurn
                == history.messages[0]
                    .conversationCheckpointBeforeTurn
        )
        #expect(
            setup.viewModel.messages[1]
                .conversationCheckpointAfterTurn?
                .state?
                .turnContexts.map(\.id)
                == [
                    fixture
                        .replacementTurnID,
                ]
        )
        #expect(
            setup.viewModel
                .feedbackByMessageID
                .isEmpty
        )
        #expect(
            await setup.feedbackStore
                .records(
                    for: fixture.chatScope
                )
                .isEmpty
        )
        #expect(
            await setup.historyStore
                .messages(
                    for: fixture.chatScope
                )
                == setup.viewModel.messages
        )
        let orchestratorSnapshot =
            await setup.orchestrator
                .snapshot()
        #expect(
            orchestratorSnapshot
                .correctionRequests.count
                == 1
        )
        #expect(
            orchestratorSnapshot
                .answerQuestions.isEmpty
        )
    }

    private static func makeSetup(
        fixture:
            GraphChatCorrectionLifecycleFixture,
        history:
            GraphChatCorrectionLifecycleHistory,
        scripts:
            [GraphChatCorrectionLifecycleScript] = [],
        feedbackMessageIDs: [UUID] = [],
        accessDecisionBox:
            GraphChatCorrectionLifecycleAccessDecisionBox? = nil,
        correctionStreamStartDelayNanoseconds:
            UInt64 = 0
    ) async
        -> GraphChatCorrectionLifecycleSetup
    {
        let historyStore =
            InMemoryGraphChatHistoryStore()
        let feedbackStore =
            InMemoryGraphChatFeedbackStore()
        await historyStore.save(
            history.messages,
            for: fixture.chatScope
        )
        for messageID in feedbackMessageIDs {
            await feedbackStore.save(
                GraphChatFeedbackRecord(
                    localMessageID:
                        messageID,
                    category: .helpful,
                    answerState: .answer,
                    scopeType: .graph,
                    toolCategories: []
                ),
                for: fixture.chatScope
            )
        }
        let orchestrator =
            GraphChatCorrectionLifecycleOrchestrator(
                scripts: scripts,
                artifactSessionID:
                    fixture
                        .artifactSessionID,
                correctionStreamStartDelayNanoseconds:
                    correctionStreamStartDelayNanoseconds
            )
        let context =
            GraphChatTestSupport
                .makeSchemaContext(
                    graphID:
                        fixture.graphScope
                            .graphID
                )
        let viewModel =
            GraphChatViewModel(
                graphScope:
                    fixture.graphScope,
                chatScope:
                    fixture.chatScope,
                graphName:
                    context.snapshot
                        .graphName,
                interfaceLanguage:
                    .german,
                orchestrator:
                    orchestrator,
                schemaProvider:
                    GraphChatUIFakeSchemaProvider(
                        contexts: [context]
                    ),
                availabilityProvider:
                    GraphChatUIFakeAvailabilityProvider(
                        value: .available
                    ),
                indexStatusProvider:
                    GraphChatUIFakeIndexProvider(
                        value:
                            .ready(
                                documentCount:
                                    12
                            )
                    ),
                historyStore:
                    historyStore,
                feedbackStore:
                    feedbackStore,
                clipboardWriter:
                    GraphChatUITestClipboardWriter(),
                accessibilityAnnouncer:
                    GraphChatUITestAccessibilityAnnouncer(),
                navigationActions:
                    .disabled,
                accessDecisionProvider: {
                    accessDecisionBox?
                        .decision
                    ?? readyAccessDecision
                }
            )
        await viewModel.load()
        return GraphChatCorrectionLifecycleSetup(
            viewModel: viewModel,
            orchestrator: orchestrator,
            historyStore: historyStore,
            feedbackStore: feedbackStore
        )
    }

    private static func waitForEditor(
        _ viewModel: GraphChatViewModel
    ) async {
        await GraphChatUITestSupport
            .waitUntil(
                maximumYields: 20_000
            ) {
                viewModel
                    .correctionEditorSession
                    != nil
            }
    }

    private static func waitForCorrectionRequest(
        _ orchestrator:
            GraphChatCorrectionLifecycleOrchestrator
    ) async {
        await GraphChatProviderTestSupport
            .waitUntil {
                await orchestrator
                    .snapshot()
                    .correctionRequests
                    .isEmpty == false
            }
    }

    private static func answerText(
        in messages:
            [GraphChatTranscriptMessage],
        messageID: UUID
    ) -> String? {
        guard
            let message =
                messages.first(
                    where: {
                        $0.id == messageID
                    }
                ),
            case .assistant(let state) =
                message.state
        else {
            return nil
        }
        return state.answer?
            .directAnswer
    }

    private nonisolated static var
        readyAccessDecision:
        GraphChatAccessDecision
    {
        GraphChatAccessDecision(
            route: .ready,
            canPresentChat: true,
            canStartGeneration: true,
            canCancelGeneration: true,
            usesIndexFallback: false
        )
    }
}
