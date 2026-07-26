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

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        sessionID: GraphChatAnswerArtifactSessionID,
        transactionID: GraphChatAnswerArtifactTransactionID
    ) {
        precondition(graphScope == chatScope.graphScope)
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.sessionID = sessionID
        self.transactionID = transactionID
    }
}

nonisolated enum GraphChatFinalizedTurnSource: String, CaseIterable, Hashable, Sendable {
    case provider
    case local
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
}

nonisolated struct GraphChatTurnCommitInput: Hashable, Sendable {
    let requestID: UUID
    let completedAt: Date
    let source: GraphChatFinalizedTurnSource
    let answer: GraphChatAnswer
    let expectedCommittedState: GraphChatConversationState
    let artifactContext: GraphChatArtifactCommitContext?
}

nonisolated enum GraphChatTurnCommitError: Error, LocalizedError, Hashable, Sendable {
    case artifactRegistryUnavailable
    case artifactContextMismatch
    case localAnswerContainsArtifacts

    var errorDescription: String? {
        switch self {
        case .artifactRegistryUnavailable:
            return "Für den Artifact-Commit ist keine aktuelle Registry verfügbar."
        case .artifactContextMismatch:
            return "Die Artifact-Transaktion gehört nicht zum aktuellen Graph-Chat-Turn."
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
            if let artifactContext = input.artifactContext {
                guard let artifactRegistry else {
                    throw GraphChatTurnCommitError.artifactRegistryUnavailable
                }
                committedArtifactIDs = try await artifactRegistry.commit(
                    transactionID: artifactContext.transactionID,
                    retaining: input.answer.artifactIDs
                )
                artifactCommitSucceeded = true
            } else {
                guard input.answer.artifactIDs.isEmpty,
                      input.answer.sections.allSatisfy(\.artifactIDs.isEmpty) else {
                    throw GraphChatTurnCommitError.localAnswerContainsArtifacts
                }
                committedArtifactIDs = []
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
                )
            )
        } catch {
            if let artifactContext = input.artifactContext,
               artifactCommitSucceeded == false,
               let artifactRegistry {
                await artifactRegistry.rollback(
                    transactionID: artifactContext.transactionID
                )
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
}
