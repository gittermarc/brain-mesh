//
//  GraphChatConversationTrustedEvents.swift
//  BrainMesh
//
//  Trusted, value-only events accepted by the conversation-state reducer.
//

import Foundation

nonisolated enum GraphChatConversationStateError: Error, LocalizedError, Equatable, Sendable {
    case graphScopeMismatch
    case chatScopeMismatch
    case evidenceGraphMismatch
    case schemaGraphMismatch

    var errorDescription: String? {
        switch self {
        case .graphScopeMismatch:
            return "Das Conversation-State-Ereignis gehört nicht zum aktiven Graphen."
        case .chatScopeMismatch:
            return "Das Conversation-State-Ereignis gehört nicht zum aktiven Chat-Scope."
        case .evidenceGraphMismatch:
            return "Das Conversation-State-Ereignis enthält Evidence aus einem anderen Graphen."
        case .schemaGraphMismatch:
            return "Das Conversation-State-Ereignis enthält ein Schema aus einem anderen Graphen."
        }
    }
}

nonisolated struct GraphChatConversationTurnCompletion: Sendable {
    let requestID: UUID
    let completedAt: Date
    let toolKinds: [GraphChatToolKind]
    let resultContextIDs: [UUID]
    let evidenceIDs: [GraphEvidenceID]
}

nonisolated enum GraphChatConversationTrustedPayload: Sendable {
    case schemaResolved(
        schemaContext: GraphSchemaContext,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case searchResolved(
        output: SearchGraphOutput,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case queryResolved(
        plan: ValidatedGraphQueryPlan,
        result: GraphChatQueryResult,
        schemaContext: GraphSchemaContext
    )
    case nodeResolved(
        output: GetNodeOutput,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case neighborsResolved(
        output: GetNeighborsOutput,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case statsResolved(
        output: GraphStatsOutput,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case validatedEvidence(
        tool: GraphChatToolKind,
        state: GraphChatToolResultState,
        evidence: [GraphEvidence]
    )
    case comparisonResolved(
        references: [GraphChatConversationReference],
        technicalDescription: String
    )
    case clarificationRequested(GraphChatPendingClarification)
    case clarificationResolved
    case turnCompleted(GraphChatConversationTurnCompletion)

    var toolKind: GraphChatToolKind? {
        switch self {
        case .schemaResolved:
            return .describeGraphSchema
        case .searchResolved:
            return .searchGraph
        case .queryResolved:
            return .queryDetailValues
        case .nodeResolved:
            return .getNode
        case .neighborsResolved:
            return .getNeighbors
        case .statsResolved:
            return .graphStats
        case .validatedEvidence(let tool, _, _):
            return tool
        case .comparisonResolved, .clarificationRequested, .clarificationResolved, .turnCompleted:
            return nil
        }
    }
}

nonisolated struct GraphChatConversationTrustedEvent: Sendable {
    let id: UUID
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let payload: GraphChatConversationTrustedPayload

    init(
        id: UUID = UUID(),
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        payload: GraphChatConversationTrustedPayload
    ) {
        self.id = id
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.payload = payload
    }
}

nonisolated struct GraphChatConversationStateReduction: Sendable {
    let state: GraphChatConversationState
    let evictedItemCount: Int
}

