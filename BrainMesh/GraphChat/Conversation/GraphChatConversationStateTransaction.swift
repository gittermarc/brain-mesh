//
//  GraphChatConversationStateTransaction.swift
//  BrainMesh
//
//  Transactional actor for atomic conversation-state application and finalization.
//

import Foundation

actor GraphChatConversationStateTransaction {
    private let baseState: GraphChatConversationState
    private let reducer: GraphChatConversationStateReducer
    private var candidateState: GraphChatConversationState
    private var appliedToolKinds: [GraphChatToolKind] = []
    private var resultContextIDs: [UUID] = []

    init(
        baseState: GraphChatConversationState,
        reducer: GraphChatConversationStateReducer
    ) {
        self.baseState = baseState
        self.reducer = reducer
        self.candidateState = baseState
    }

    func apply(_ event: GraphChatConversationTrustedEvent) throws {
        let previousResultIDs = Set(candidateState.resultContexts.map(\.id))
        let reduction = try reducer.reduce(candidateState, event: event)
        candidateState = reduction.state
        if let toolKind = event.payload.toolKind {
            appliedToolKinds.append(toolKind)
        }
        let addedResultIDs = candidateState.resultContexts
            .map(\.id)
            .filter { previousResultIDs.contains($0) == false }
        resultContextIDs.append(contentsOf: addedResultIDs)
    }

    func resetToBase() {
        candidateState = baseState
        appliedToolKinds = []
        resultContextIDs = []
    }

    func snapshot() -> GraphChatConversationState {
        candidateState
    }

    func baseSnapshot() -> GraphChatConversationState {
        baseState
    }

    func finalizedState(
        requestID: UUID,
        completedAt: Date,
        validatedEvidenceIDs: [GraphEvidenceID]
    ) throws -> GraphChatConversationState {
        let event = GraphChatConversationTrustedEvent(
            id: requestID,
            graphScope: candidateState.graphScope,
            chatScope: candidateState.chatScope,
            payload: .turnCompleted(
                GraphChatConversationTurnCompletion(
                    requestID: requestID,
                    completedAt: completedAt,
                    toolKinds: appliedToolKinds,
                    resultContextIDs: resultContextIDs,
                    evidenceIDs: validatedEvidenceIDs
                )
            )
        )
        candidateState = try reducer.reduce(candidateState, event: event).state
        return candidateState
    }
}
