//
//  GraphChatOrchestratorConversationRuntime.swift
//  BrainMesh
//
//  In-memory conversation-state ownership for the lifecycle actor.
//

import Foundation

nonisolated struct GraphChatConversationTurnStateTransition: Hashable, Sendable {
    let state: GraphChatConversationState
    let committedStateSnapshot: GraphChatConversationState?
    let previousScopeKey: GraphChatOrchestrationScopeKey?
    let resetReason: GraphChatConversationResetReason?
}

private nonisolated struct GraphChatPendingConversationTurnState {
    let key: GraphChatOrchestrationScopeKey
    let state: GraphChatConversationState
    let committedStateSnapshot: GraphChatConversationState?
    let previousScopeKey: GraphChatOrchestrationScopeKey?
    let resetReason: GraphChatConversationResetReason?
}

nonisolated struct GraphChatOrchestratorConversationRuntime {
    private(set) var committedState: GraphChatConversationState?
    private(set) var pendingResetReason: GraphChatConversationResetReason =
        .newConversation
    private var pendingTurnState: GraphChatPendingConversationTurnState?

    func snapshot() -> GraphChatConversationState? {
        committedState
    }

    func acceptsRestore(
        for key: GraphChatOrchestrationScopeKey,
        lifecycleKey: GraphChatOrchestrationScopeKey?
    ) -> Bool {
        if let committedState {
            return committedState.graphScope == key.graphScope
                && committedState.chatScope == key.chatScope
        }
        if let lifecycleKey {
            return lifecycleKey == key
        }
        return true
    }

    mutating func stateForTurn(
        key: GraphChatOrchestrationScopeKey,
        reducer: GraphChatConversationStateReducer
    ) -> GraphChatConversationTurnStateTransition {
        if let pendingTurnState,
           pendingTurnState.key == key,
           pendingTurnState.committedStateSnapshot == committedState {
            return transition(from: pendingTurnState)
        }

        let pending: GraphChatPendingConversationTurnState
        if let committedState {
            let previousKey = GraphChatOrchestrationScopeKey(
                graphScope: committedState.graphScope,
                chatScope: committedState.chatScope
            )
            if previousKey == key {
                pending = GraphChatPendingConversationTurnState(
                    key: key,
                    state: committedState,
                    committedStateSnapshot: committedState,
                    previousScopeKey: previousKey,
                    resetReason: nil
                )
            } else {
                let transition = reducer.transition(
                    committedState,
                    to: key.chatScope
                )
                pending = GraphChatPendingConversationTurnState(
                    key: key,
                    state: transition.state,
                    committedStateSnapshot: committedState,
                    previousScopeKey: previousKey,
                    resetReason: transition.state.lastResetReason
                )
            }
        } else {
            let initial = GraphChatConversationState.initial(
                graphScope: key.graphScope,
                chatScope: key.chatScope,
                resetReason: pendingResetReason
            )
            pending = GraphChatPendingConversationTurnState(
                key: key,
                state: initial,
                committedStateSnapshot: nil,
                previousScopeKey: nil,
                resetReason: initial.lastResetReason
            )
        }
        pendingTurnState = pending
        return transition(from: pending)
    }

    mutating func commit(
        _ state: GraphChatConversationState,
        expectedCommittedState: GraphChatConversationState?
    ) throws {
        guard committedState == expectedCommittedState else {
            throw CancellationError()
        }
        committedState = state
        pendingTurnState = nil
        pendingResetReason = .newConversation
    }

    mutating func discard(
        reason: GraphChatConversationResetReason
    ) {
        committedState = nil
        pendingTurnState = nil
        pendingResetReason = reason
    }

    mutating func restore(
        _ checkpoint: GraphChatConversationCheckpoint,
        key: GraphChatOrchestrationScopeKey
    ) throws {
        if let state = checkpoint.state {
            guard state.graphScope == key.graphScope,
                  state.chatScope == key.chatScope else {
                throw GraphChatError(
                    code: .invalidRequest,
                    message: "Der wiederherzustellende Conversation-State ist scopefremd."
                )
            }
            committedState = state
        } else {
            committedState = GraphChatConversationState.initial(
                graphScope: key.graphScope,
                chatScope: key.chatScope,
                resetReason: .newConversation
            )
        }
        pendingTurnState = nil
        pendingResetReason = .newConversation
    }

    private func transition(
        from pending: GraphChatPendingConversationTurnState
    ) -> GraphChatConversationTurnStateTransition {
        GraphChatConversationTurnStateTransition(
            state: pending.state,
            committedStateSnapshot: pending.committedStateSnapshot,
            previousScopeKey: pending.previousScopeKey,
            resetReason: pending.resetReason
        )
    }
}

nonisolated enum GraphChatArtifactClearReasonMapper {
    static let restoredCheckpoint:
        GraphChatAnswerArtifactRegistryClearReason = .restoredCheckpoint

    static func reason(
        for resetReason: GraphChatConversationResetReason
    ) -> GraphChatAnswerArtifactRegistryClearReason {
        switch resetReason {
        case .newConversation:
            return .newConversation
        case .graphChanged:
            return .graphChanged
        case .scopeChanged:
            return .scopeChanged
        case .graphLocked, .accessRevoked:
            return .graphLocked
        case .graphDeleted:
            return .graphDeleted
        case .sessionDiscarded:
            return .sessionDiscarded
        }
    }

    static func scopeChangeReason(
        from oldKey: GraphChatOrchestrationScopeKey,
        to newKey: GraphChatOrchestrationScopeKey
    ) -> GraphChatAnswerArtifactRegistryClearReason {
        oldKey.graphScope == newKey.graphScope
            ? .scopeChanged
            : .graphChanged
    }
}
