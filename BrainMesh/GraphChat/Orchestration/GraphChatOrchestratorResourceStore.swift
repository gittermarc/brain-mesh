//
//  GraphChatOrchestratorResourceStore.swift
//  BrainMesh
//
//  Concrete lifecycle resources kept separate from technical state.
//

import Foundation

nonisolated struct GraphChatActiveGenerationResources {
    let identity: GraphChatGenerationIdentity
    let task: Task<Void, Never>
    var providerResources: GraphChatProviderSessionResources?
}

nonisolated enum GraphChatPreparedSessionResolution {
    case missing
    case reused(GraphChatProviderSessionResources)
    case discarded(GraphChatProviderSessionResources)
}

nonisolated struct GraphChatDiscardedOrchestratorResources {
    let preparedSession: GraphChatProviderSessionResources?
    let artifactSession: GraphChatArtifactSessionResources?
}

nonisolated struct GraphChatOrchestratorResourceStore {
    private(set) var preparedSession: GraphChatProviderSessionResources?
    private(set) var artifactSession: GraphChatArtifactSessionResources?
    private(set) var activeGeneration: GraphChatActiveGenerationResources?

    var activeRequestID: UUID? {
        activeGeneration?.identity.requestID
    }

    mutating func installPreparedSession(
        _ resources: GraphChatProviderSessionResources
    ) {
        precondition(preparedSession == nil)
        preparedSession = resources
    }

    func preparedSessionMatches(
        key: GraphChatOrchestrationScopeKey,
        schemaContextIdentity: GraphSchemaContextIdentity,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage
    ) -> Bool {
        guard let preparedSession else {
            return false
        }
        return preparedSession.key == key
            && preparedSession.schemaContext.identity == schemaContextIdentity
            && preparedSession.conversationBaseState == conversationBaseState
            && preparedSession.conversationContext == conversationContext
            && preparedSession.responseLanguage == responseLanguage
    }

    mutating func takePreparedSession(
        matching key: GraphChatOrchestrationScopeKey,
        schemaContextIdentity: GraphSchemaContextIdentity,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage
    ) -> GraphChatPreparedSessionResolution {
        guard let preparedSession else {
            return .missing
        }
        self.preparedSession = nil
        guard preparedSession.key == key,
              preparedSession.schemaContext.identity == schemaContextIdentity,
              preparedSession.conversationBaseState == conversationBaseState,
              preparedSession.conversationContext == conversationContext,
              preparedSession.responseLanguage == responseLanguage else {
            return .discarded(preparedSession)
        }
        return .reused(preparedSession)
    }

    mutating func removePreparedSession() -> GraphChatProviderSessionResources? {
        defer { preparedSession = nil }
        return preparedSession
    }

    mutating func installArtifactSession(
        _ resources: GraphChatArtifactSessionResources
    ) {
        precondition(artifactSession == nil)
        artifactSession = resources
    }

    mutating func removeArtifactSession() -> GraphChatArtifactSessionResources? {
        defer { artifactSession = nil }
        return artifactSession
    }

    mutating func removeScopeMismatchedResources(
        matching key: GraphChatOrchestrationScopeKey
    ) -> GraphChatDiscardedOrchestratorResources {
        let removedPrepared: GraphChatProviderSessionResources?
        if let preparedSession,
           preparedSession.key != key {
            removedPrepared = removePreparedSession()
        } else {
            removedPrepared = nil
        }

        let removedArtifact: GraphChatArtifactSessionResources?
        if let artifactSession,
           artifactSession.key != key {
            removedArtifact = removeArtifactSession()
        } else {
            removedArtifact = nil
        }

        return GraphChatDiscardedOrchestratorResources(
            preparedSession: removedPrepared,
            artifactSession: removedArtifact
        )
    }

    mutating func installActiveGeneration(
        identity: GraphChatGenerationIdentity,
        task: Task<Void, Never>
    ) {
        precondition(activeGeneration == nil)
        activeGeneration = GraphChatActiveGenerationResources(
            identity: identity,
            task: task,
            providerResources: nil
        )
    }

    @discardableResult
    mutating func setActiveProviderResources(
        _ resources: GraphChatProviderSessionResources,
        requestID: UUID
    ) -> Bool {
        guard var activeGeneration,
              activeGeneration.identity.requestID == requestID else {
            return false
        }
        activeGeneration.providerResources = resources
        self.activeGeneration = activeGeneration
        return true
    }

    mutating func clearActiveGeneration(
        requestID: UUID
    ) -> GraphChatActiveGenerationResources? {
        guard activeGeneration?.identity.requestID == requestID else {
            return nil
        }
        defer { activeGeneration = nil }
        return activeGeneration
    }

    mutating func removeAll() -> GraphChatDiscardedOrchestratorResources {
        let resources = GraphChatDiscardedOrchestratorResources(
            preparedSession: preparedSession,
            artifactSession: artifactSession
        )
        preparedSession = nil
        artifactSession = nil
        activeGeneration = nil
        return resources
    }
}
