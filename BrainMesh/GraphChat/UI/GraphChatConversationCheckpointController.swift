//
//  GraphChatConversationCheckpointController.swift
//  BrainMesh
//
//  Scope-safe ownership and restoration of trusted conversation checkpoints.
//

import Foundation

nonisolated enum GraphChatConversationHistoryRestoreResult: Hashable, Sendable {
    case startedFromInitial(GraphChatConversationCheckpoint)
    case deferred(GraphChatConversationCheckpoint)
    case restored(GraphChatConversationCheckpoint)
    case controlledReset
}

nonisolated enum GraphChatConversationBranchRestoreResult: Hashable, Sendable {
    case restored(GraphChatConversationCheckpoint)
    case rejected(message: String)
}

@MainActor
final class GraphChatConversationCheckpointController {
    typealias RestoreOperation = @MainActor (
        _ checkpoint: GraphChatConversationCheckpoint
    ) async throws -> Void
    typealias ControlledReset = @MainActor () async -> Void
    typealias AccessValidation = @MainActor () -> Bool

    let graphScope: GraphScope
    let chatScope: GraphChatScope

    private(set) var committedCheckpoint: GraphChatConversationCheckpoint?

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) {
        precondition(
            graphScope == chatScope.graphScope,
            "GraphChatConversationCheckpointController requires matching graph and chat scopes."
        )
        self.graphScope = graphScope
        self.chatScope = chatScope
    }

    func checkpointBeforeNextTurn() -> GraphChatConversationCheckpoint {
        if let committedCheckpoint,
           validates(committedCheckpoint) {
            return committedCheckpoint
        }
        return initialCheckpoint
    }

    @discardableResult
    func captureCommittedCheckpoint(
        state: GraphChatConversationState?,
        outcome: GraphChatGenerationOutcome
    ) -> GraphChatConversationCheckpoint? {
        guard outcome.isSuccessful,
              let state,
              state.graphScope == graphScope,
              state.chatScope == chatScope else {
            return nil
        }
        let checkpoint = GraphChatConversationCheckpoint.committed(state)
        committedCheckpoint = checkpoint
        return checkpoint
    }

    func restoreLatestCommittedCheckpoint(
        from history: [GraphChatTranscriptMessage],
        shouldRestoreRuntime: Bool,
        restore: RestoreOperation,
        controlledReset: ControlledReset
    ) async -> GraphChatConversationHistoryRestoreResult {
        let historyCheckpoints = history.reversed().compactMap(
            \.conversationCheckpointAfterTurn
        )
        guard historyCheckpoints.isEmpty == false else {
            committedCheckpoint = nil
            return .startedFromInitial(initialCheckpoint)
        }

        guard let checkpoint = historyCheckpoints.first(where: { checkpoint in
            checkpoint.state != nil && validates(checkpoint)
        }) else {
            committedCheckpoint = nil
            await controlledReset()
            return .controlledReset
        }

        committedCheckpoint = checkpoint
        guard shouldRestoreRuntime else {
            return .deferred(checkpoint)
        }

        do {
            try await restore(checkpoint)
            return .restored(checkpoint)
        } catch {
            committedCheckpoint = nil
            await controlledReset()
            return .controlledReset
        }
    }

    func restoreCheckpointForBranch(
        _ checkpoint: GraphChatConversationCheckpoint,
        accessIsValid: AccessValidation,
        restore: RestoreOperation
    ) async -> GraphChatConversationBranchRestoreResult {
        guard validates(checkpoint) else {
            return .rejected(
                message: "Der gespeicherte Gesprächskontext gehört nicht zum aktiven Graph-Chat."
            )
        }
        guard Task.isCancelled == false,
              accessIsValid() else {
            return .rejected(
                message: "Der aktive Graph-Chat-Kontext hat sich geändert."
            )
        }

        do {
            try await restore(checkpoint)
        } catch {
            return .rejected(message: error.localizedDescription)
        }

        guard Task.isCancelled == false,
              accessIsValid() else {
            return .rejected(
                message: "Der aktive Graph-Chat-Kontext hat sich geändert."
            )
        }

        committedCheckpoint = checkpoint
        return .restored(checkpoint)
    }

    func reset() {
        committedCheckpoint = nil
    }

    func validates(
        _ checkpoint: GraphChatConversationCheckpoint
    ) -> Bool {
        checkpoint.belongsTo(
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    private var initialCheckpoint: GraphChatConversationCheckpoint {
        .initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
    }
}
