//
//  GraphChatToolCore.swift
//  BrainMesh
//
//  Provider-independent, read-only graph chat tool boundary.
//

import Foundation

nonisolated enum GraphChatToolKind: String, CaseIterable, Hashable, Sendable {
    case describeGraphSchema
    case searchGraph
    case queryDetailValues
    case getNode
    case getNeighbors
    case graphStats
}

nonisolated enum GraphChatToolResultState: String, Hashable, Sendable {
    case success
    case noResults
    case noEvidence
}

nonisolated struct GraphChatToolResult<Payload: Sendable>: Sendable {
    let state: GraphChatToolResultState
    let payload: Payload?
    let evidence: [GraphEvidence]

    static func success(
        _ payload: Payload,
        evidence: [GraphEvidence]
    ) -> GraphChatToolResult<Payload> {
        GraphChatToolResult(
            state: evidence.isEmpty ? .noEvidence : .success,
            payload: payload,
            evidence: evidence
        )
    }

    static func noResults() -> GraphChatToolResult<Payload> {
        GraphChatToolResult(state: .noResults, payload: nil, evidence: [])
    }

    static func noEvidence(_ payload: Payload? = nil) -> GraphChatToolResult<Payload> {
        GraphChatToolResult(state: .noEvidence, payload: payload, evidence: [])
    }
}

nonisolated protocol GraphChatTool: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var kind: GraphChatToolKind { get }

    func execute(
        _ input: Input,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<Output>
}

nonisolated struct GraphChatToolContext: Sendable {
    let scope: GraphChatScope
    let budget: GraphChatToolBudget

    init(
        scope: GraphChatScope,
        budget: GraphChatToolBudget
    ) {
        self.scope = scope
        self.budget = budget
    }
}

nonisolated enum GraphChatToolErrorCode: String, CaseIterable, Hashable, Sendable {
    case invalidInput
    case graphScopeMismatch
    case budgetExceeded
    case indexUnavailable
    case sourceUnavailable
    case cancelled
    case unavailable
}

nonisolated struct GraphChatToolError: Error, LocalizedError, Equatable, Sendable {
    let code: GraphChatToolErrorCode
    let message: String

    var errorDescription: String? {
        message
    }

    static func cancelled() -> GraphChatToolError {
        GraphChatToolError(
            code: .cancelled,
            message: "Die Graph-Chat-Operation wurde abgebrochen."
        )
    }
}
