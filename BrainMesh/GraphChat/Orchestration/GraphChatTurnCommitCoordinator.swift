//
//  GraphChatTurnCommitCoordinator.swift
//  BrainMesh
//
//  Atomic request-scoped completion of conversation state and answer artifacts.
//

import Foundation

nonisolated protocol GraphChatAnswerArtifactFinalizationRegistry: Sendable {
    func validatedArtifacts(
        for rawValues: [String],
        graphScope: GraphScope,
        sessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async throws -> [GraphChatAnswerArtifact]

    func commit(
        transactionID: GraphChatAnswerArtifactTransactionID,
        retaining artifactIDs: [GraphChatAnswerArtifactID]
    ) async throws -> [GraphChatAnswerArtifactID]

    func commitDeferred(
        transactionID: GraphChatAnswerArtifactTransactionID,
        retaining artifactIDs: [GraphChatAnswerArtifactID],
        replacing replacedArtifactIDs:
            [GraphChatAnswerArtifactID]
    ) async throws -> [GraphChatAnswerArtifactID]

    func finalizeDeferredCommit(
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async -> [GraphChatAnswerArtifactID]

    func rollbackDeferredCommit(
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async

    func rollback(
        transactionID: GraphChatAnswerArtifactTransactionID
    ) async
}

extension GraphChatAnswerArtifactRegistry: GraphChatAnswerArtifactFinalizationRegistry {}

nonisolated struct GraphChatArtifactCommitContext: Hashable, Sendable {
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let sessionID: GraphChatAnswerArtifactSessionID
    let transactionID: GraphChatAnswerArtifactTransactionID
    let readPlanVersion:
        GraphChatComposableReadPlanVersion?

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        sessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID,
        readPlanVersion:
            GraphChatComposableReadPlanVersion? = nil
    ) {
        precondition(graphScope == chatScope.graphScope)
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.sessionID = sessionID
        self.transactionID = transactionID
        self.readPlanVersion =
            readPlanVersion
    }
}

nonisolated enum GraphChatFinalizedTurnSource: String, CaseIterable, Hashable, Sendable {
    case provider
    case local
}

nonisolated enum GraphChatArtifactCommitBehavior:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case immediate
    case deferred
}

nonisolated struct GraphChatDeferredArtifactCommit:
    Hashable,
    Sendable
{
    let context: GraphChatArtifactCommitContext
    let artifactIDs: [GraphChatAnswerArtifactID]
    let replacedArtifactIDs:
        [GraphChatAnswerArtifactID]

    init(
        context: GraphChatArtifactCommitContext,
        artifactIDs: [GraphChatAnswerArtifactID],
        replacedArtifactIDs:
            [GraphChatAnswerArtifactID] = []
    ) {
        self.context = context
        self.artifactIDs = artifactIDs
        self.replacedArtifactIDs =
            replacedArtifactIDs
    }
}

nonisolated struct GraphChatTurnCompletionInfo: Hashable, Sendable {
    let requestID: UUID
    let completedAt: Date
    let source: GraphChatFinalizedTurnSource
    let evidenceCount: Int
    let requestedArtifactCount: Int
    let committedArtifactCount: Int
}

nonisolated struct GraphChatFinalizedTurn: Hashable, Sendable {
    let answer: GraphChatAnswer
    let conversationState: GraphChatConversationState
    let committedArtifactIDs: [GraphChatAnswerArtifactID]
    let completion: GraphChatTurnCompletionInfo
    let deferredArtifactCommit: GraphChatDeferredArtifactCommit?

    init(
        answer: GraphChatAnswer,
        conversationState: GraphChatConversationState,
        committedArtifactIDs: [GraphChatAnswerArtifactID],
        completion: GraphChatTurnCompletionInfo,
        deferredArtifactCommit:
            GraphChatDeferredArtifactCommit? = nil
    ) {
        self.answer = answer
        self.conversationState = conversationState
        self.committedArtifactIDs = committedArtifactIDs
        self.completion = completion
        self.deferredArtifactCommit =
            deferredArtifactCommit
    }
}

nonisolated struct GraphChatTurnCommitInput: Hashable, Sendable {
    let requestID: UUID
    let completedAt: Date
    let source: GraphChatFinalizedTurnSource
    let answer: GraphChatAnswer
    let expectedCommittedState: GraphChatConversationState
    let artifactContext: GraphChatArtifactCommitContext?
    let artifactCommitBehavior:
        GraphChatArtifactCommitBehavior
    let artifactIDsToReplace:
        [GraphChatAnswerArtifactID]

    init(
        requestID: UUID,
        completedAt: Date,
        source: GraphChatFinalizedTurnSource,
        answer: GraphChatAnswer,
        expectedCommittedState:
            GraphChatConversationState,
        artifactContext:
            GraphChatArtifactCommitContext?,
        artifactCommitBehavior:
            GraphChatArtifactCommitBehavior = .immediate,
        artifactIDsToReplace:
            [GraphChatAnswerArtifactID] = []
    ) {
        self.requestID = requestID
        self.completedAt = completedAt
        self.source = source
        self.answer = answer
        self.expectedCommittedState =
            expectedCommittedState
        self.artifactContext = artifactContext
        self.artifactCommitBehavior =
            artifactCommitBehavior
        self.artifactIDsToReplace =
            artifactIDsToReplace
    }
}

nonisolated enum GraphChatTurnCommitError: Error, LocalizedError, Hashable, Sendable {
    case artifactRegistryUnavailable
    case artifactContextMismatch
    case artifactReplacementMismatch
    case localAnswerContainsArtifacts

    var errorDescription: String? {
        switch self {
        case .artifactRegistryUnavailable:
            return "Für den Artifact-Commit ist keine aktuelle Registry verfügbar."
        case .artifactContextMismatch:
            return "Die Artifact-Transaktion gehört nicht zum aktuellen Graph-Chat-Turn."
        case .artifactReplacementMismatch:
            return "Der Artifact-Ersatz gehört nicht zum aktuellen Graph-Chat-Turn."
        case .localAnswerContainsArtifacts:
            return "Eine lokale Antwort ohne Artifact-Transaktion darf keine Artifacts enthalten."
        }
    }
}

nonisolated struct GraphChatTurnCommitCoordinator: Sendable {
    func commit(
        _ input: GraphChatTurnCommitInput,
        conversationTransaction: GraphChatConversationStateTransaction,
        currentCommittedState: GraphChatConversationState,
        artifactRegistry: (any GraphChatAnswerArtifactFinalizationRegistry)? = nil
    ) async throws -> GraphChatFinalizedTurn {
        var artifactCommitSucceeded = false
        do {
            let transactionBaseState = await conversationTransaction.baseSnapshot()
            try validateScopes(
                input: input,
                transactionBaseState: transactionBaseState
            )
            try validateReplacementBinding(
                input
            )
            let candidateState = try await conversationTransaction.finalizedState(
                requestID: input.requestID,
                completedAt: input.completedAt,
                validatedEvidenceIDs: input.answer.evidenceIDs
            )
            try Task.checkCancellation()
            guard currentCommittedState == input.expectedCommittedState else {
                throw CancellationError()
            }
            try Task.checkCancellation()

            let committedArtifactIDs: [GraphChatAnswerArtifactID]
            let deferredArtifactCommit:
                GraphChatDeferredArtifactCommit?
            if let artifactContext = input.artifactContext {
                guard let artifactRegistry else {
                    throw GraphChatTurnCommitError.artifactRegistryUnavailable
                }
                switch input.artifactCommitBehavior {
                case .immediate:
                    committedArtifactIDs =
                        try await artifactRegistry.commit(
                            transactionID:
                                artifactContext
                                    .transactionID,
                            retaining:
                                input.answer.artifactIDs
                        )
                    deferredArtifactCommit = nil
                case .deferred:
                    committedArtifactIDs =
                        try await artifactRegistry
                            .commitDeferred(
                                transactionID:
                                    artifactContext
                                        .transactionID,
                                retaining:
                                    input.answer.artifactIDs,
                                replacing:
                                    input
                                        .artifactIDsToReplace
                            )
                    deferredArtifactCommit =
                        GraphChatDeferredArtifactCommit(
                            context: artifactContext,
                            artifactIDs:
                                committedArtifactIDs,
                            replacedArtifactIDs:
                                input
                                    .artifactIDsToReplace
                        )
                }
                artifactCommitSucceeded = true
            } else {
                guard input.answer.artifactIDs.isEmpty,
                      input.answer.sections.allSatisfy(\.artifactIDs.isEmpty) else {
                    throw GraphChatTurnCommitError.localAnswerContainsArtifacts
                }
                committedArtifactIDs = []
                deferredArtifactCommit = nil
            }

            let committedSet = Set(committedArtifactIDs)
            let finalAnswer = input.answer.retainingArtifactIDs(committedSet)
            return GraphChatFinalizedTurn(
                answer: finalAnswer,
                conversationState: candidateState,
                committedArtifactIDs: committedArtifactIDs,
                completion: GraphChatTurnCompletionInfo(
                    requestID: input.requestID,
                    completedAt: input.completedAt,
                    source: input.source,
                    evidenceCount: finalAnswer.evidence.count,
                    requestedArtifactCount: input.answer.artifactIDs.count,
                    committedArtifactCount: committedArtifactIDs.count
                ),
                deferredArtifactCommit:
                    deferredArtifactCommit
            )
        } catch {
            if let artifactContext = input.artifactContext,
               artifactCommitSucceeded == false,
               let artifactRegistry {
                switch input.artifactCommitBehavior {
                case .immediate:
                    await artifactRegistry.rollback(
                        transactionID:
                            artifactContext.transactionID
                    )
                case .deferred:
                    await artifactRegistry
                        .rollbackDeferredCommit(
                            transactionID:
                                artifactContext
                                    .transactionID
                        )
                }
            }
            throw error
        }
    }

    func rollback(
        _ context: GraphChatArtifactCommitContext,
        artifactRegistry: any GraphChatAnswerArtifactFinalizationRegistry
    ) async {
        await artifactRegistry.rollback(transactionID: context.transactionID)
    }

    private func validateScopes(
        input: GraphChatTurnCommitInput,
        transactionBaseState: GraphChatConversationState
    ) throws {
        guard transactionBaseState.graphScope == input.expectedCommittedState.graphScope,
              transactionBaseState.chatScope == input.expectedCommittedState.chatScope else {
            throw GraphChatTurnCommitError.artifactContextMismatch
        }
        guard let artifactContext = input.artifactContext else {
            return
        }
        guard artifactContext.graphScope == transactionBaseState.graphScope,
              artifactContext.chatScope == transactionBaseState.chatScope else {
            throw GraphChatTurnCommitError.artifactContextMismatch
        }
    }

    private func validateReplacementBinding(
        _ input: GraphChatTurnCommitInput
    ) throws {
        let replaced = input.artifactIDsToReplace
        guard
            Set(replaced).count == replaced.count,
            Set(replaced).isDisjoint(
                with:
                    Set(input.answer.artifactIDs)
            ),
            replaced.isEmpty
                || (
                    input.artifactContext != nil
                        && input.artifactCommitBehavior
                            == .deferred
                )
        else {
            throw GraphChatTurnCommitError
                .artifactReplacementMismatch
        }
    }
}
