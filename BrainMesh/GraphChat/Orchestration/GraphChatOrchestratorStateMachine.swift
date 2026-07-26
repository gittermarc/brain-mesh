//
//  GraphChatOrchestratorStateMachine.swift
//  BrainMesh
//
//  Graph-chat-specific lifecycle state with technical identities only.
//

import Foundation

nonisolated enum GraphChatOrchestratorLifecycleState: String, CaseIterable, Hashable, Sendable {
    case idle
    case prepared
    case running
    case cancelling
    case discarding
    case restoring
}

nonisolated struct GraphChatGenerationIdentity: Hashable, Sendable {
    let requestID: UUID
    let token: UUID

    init(
        requestID: UUID,
        token: UUID = UUID()
    ) {
        self.requestID = requestID
        self.token = token
    }
}

nonisolated struct GraphChatOrchestratorState: Hashable, Sendable {
    var lifecycle: GraphChatOrchestratorLifecycleState
    var scopeKey: GraphChatOrchestrationScopeKey?
    var preparedSessionID: GraphChatModelSessionID?
    var artifactSessionID: GraphChatAnswerArtifactSessionID?
    var generation: GraphChatGenerationIdentity?
    var activeSessionID: GraphChatModelSessionID?

    static let idle = GraphChatOrchestratorState(
        lifecycle: .idle,
        scopeKey: nil,
        preparedSessionID: nil,
        artifactSessionID: nil,
        generation: nil,
        activeSessionID: nil
    )
}

nonisolated enum GraphChatOrchestratorEvent: Hashable, Sendable {
    case prepared(
        key: GraphChatOrchestrationScopeKey,
        sessionID: GraphChatModelSessionID
    )
    case preparedConsumed(
        requestID: UUID,
        sessionID: GraphChatModelSessionID
    )
    case preparedDiscarded(sessionID: GraphChatModelSessionID)
    case artifactSessionInstalled(
        key: GraphChatOrchestrationScopeKey,
        sessionID: GraphChatAnswerArtifactSessionID
    )
    case artifactSessionDiscarded(sessionID: GraphChatAnswerArtifactSessionID)
    case requestStarted(
        key: GraphChatOrchestrationScopeKey,
        generation: GraphChatGenerationIdentity
    )
    case activeSessionChanged(
        requestID: UUID,
        sessionID: GraphChatModelSessionID
    )
    case cancellationRequested(requestID: UUID)
    case requestFinished(
        requestID: UUID,
        outcome: GraphChatRequestOutcome
    )
    case discardStarted(reason: GraphChatConversationResetReason)
    case resourcesDiscarded
    case discardFinished
    case restoreStarted
    case restoreFinished(key: GraphChatOrchestrationScopeKey)
}

nonisolated struct GraphChatOrchestratorTransition: Hashable, Sendable {
    let event: GraphChatOrchestratorEvent
    let previous: GraphChatOrchestratorState
    let current: GraphChatOrchestratorState
    let wasApplied: Bool
}

nonisolated struct GraphChatOrchestratorStateMachine: Sendable {
    private(set) var state: GraphChatOrchestratorState = .idle

    var activeRequestID: UUID? {
        state.generation?.requestID
    }

    func isCurrent(_ generation: GraphChatGenerationIdentity) -> Bool {
        state.generation == generation
    }

    @discardableResult
    mutating func transition(
        _ event: GraphChatOrchestratorEvent
    ) -> GraphChatOrchestratorTransition {
        let previous = state
        let wasApplied = reduce(event)
        return GraphChatOrchestratorTransition(
            event: event,
            previous: previous,
            current: state,
            wasApplied: wasApplied
        )
    }

    private mutating func reduce(
        _ event: GraphChatOrchestratorEvent
    ) -> Bool {
        switch event {
        case .prepared(let key, let sessionID):
            guard state.generation == nil,
                  state.lifecycle != .discarding,
                  state.lifecycle != .restoring else {
                return false
            }
            state.scopeKey = key
            state.preparedSessionID = sessionID
            state.lifecycle = .prepared
            return true

        case .preparedConsumed(let requestID, let sessionID):
            guard state.generation?.requestID == requestID,
                  state.preparedSessionID == sessionID else {
                return false
            }
            state.preparedSessionID = nil
            state.activeSessionID = sessionID
            return true

        case .preparedDiscarded(let sessionID):
            guard state.preparedSessionID == sessionID else {
                return false
            }
            state.preparedSessionID = nil
            if state.generation == nil,
               state.lifecycle == .prepared {
                state.lifecycle = .idle
            }
            return true

        case .artifactSessionInstalled(let key, let sessionID):
            guard state.lifecycle != .discarding,
                  state.lifecycle != .restoring else {
                return false
            }
            state.scopeKey = key
            state.artifactSessionID = sessionID
            return true

        case .artifactSessionDiscarded(let sessionID):
            guard state.artifactSessionID == sessionID else {
                return false
            }
            state.artifactSessionID = nil
            return true

        case .requestStarted(let key, let generation):
            guard state.generation == nil,
                  state.lifecycle != .discarding,
                  state.lifecycle != .restoring else {
                return false
            }
            state.scopeKey = key
            state.generation = generation
            state.activeSessionID = nil
            state.lifecycle = .running
            return true

        case .activeSessionChanged(let requestID, let sessionID):
            guard state.generation?.requestID == requestID else {
                return false
            }
            state.activeSessionID = sessionID
            return true

        case .cancellationRequested(let requestID):
            guard state.generation?.requestID == requestID else {
                return false
            }
            if state.lifecycle != .discarding,
               state.lifecycle != .restoring {
                state.lifecycle = .cancelling
            }
            return true

        case .requestFinished(let requestID, _):
            guard state.generation?.requestID == requestID else {
                return false
            }
            state.generation = nil
            state.activeSessionID = nil
            if state.lifecycle != .discarding,
               state.lifecycle != .restoring {
                state.lifecycle =
                    state.preparedSessionID == nil ? .idle : .prepared
            }
            return true

        case .discardStarted:
            state.lifecycle = .discarding
            return true

        case .resourcesDiscarded:
            state.preparedSessionID = nil
            state.artifactSessionID = nil
            state.generation = nil
            state.activeSessionID = nil
            if state.lifecycle != .discarding,
               state.lifecycle != .restoring {
                state.lifecycle = .idle
            }
            return true

        case .discardFinished:
            guard state.lifecycle == .discarding else {
                return false
            }
            state = .idle
            return true

        case .restoreStarted:
            state.lifecycle = .restoring
            return true

        case .restoreFinished(let key):
            guard state.lifecycle == .restoring else {
                return false
            }
            state = GraphChatOrchestratorState(
                lifecycle: .idle,
                scopeKey: key,
                preparedSessionID: nil,
                artifactSessionID: nil,
                generation: nil,
                activeSessionID: nil
            )
            return true
        }
    }
}
