//
//  GraphChatModelProvider.swift
//  BrainMesh
//
//  Provider-independent model availability, session, and streaming contracts.
//

import Foundation

nonisolated enum GraphChatModelUnavailableReason: String, CaseIterable, Hashable, Sendable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

nonisolated enum GraphChatModelAvailability: Hashable, Sendable {
    case available
    case unavailable(GraphChatModelUnavailableReason)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
}

nonisolated struct GraphChatModelSessionID: RawRepresentable, Hashable, Sendable, Identifiable {
    let rawValue: UUID

    var id: UUID {
        rawValue
    }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated struct GraphChatModelSessionConfiguration: Sendable {
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let schemaContext: GraphSchemaContext
    let instructions: String
    let toolRunner: any GraphChatModelToolRunning

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        instructions: String,
        toolRunner: any GraphChatModelToolRunning
    ) {
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.schemaContext = schemaContext
        self.instructions = instructions
        self.toolRunner = toolRunner
    }
}

nonisolated struct GraphChatModelRequest: Hashable, Sendable, Identifiable {
    let id: UUID
    let question: String
    let schemaPrompt: String
    let conversationSummary: String?

    init(
        id: UUID = UUID(),
        question: String,
        schemaPrompt: String,
        conversationSummary: String? = nil
    ) {
        self.id = id
        self.question = question
        self.schemaPrompt = schemaPrompt
        self.conversationSummary = conversationSummary
    }
}

nonisolated enum GraphChatToolActivityState: String, CaseIterable, Hashable, Sendable {
    case started
    case finished
}

nonisolated struct GraphChatToolActivity: Hashable, Sendable, Identifiable {
    let id: UUID
    let tool: GraphChatToolKind
    let state: GraphChatToolActivityState

    init(
        id: UUID = UUID(),
        tool: GraphChatToolKind,
        state: GraphChatToolActivityState
    ) {
        self.id = id
        self.tool = tool
        self.state = state
    }
}

nonisolated struct GraphChatProviderPartialAnswer: Hashable, Sendable {
    let directAnswer: String
    let hasInsufficientEvidence: Bool?
}

nonisolated struct GraphChatProviderAnswerSection: Hashable, Sendable {
    let title: String?
    let text: String
    let evidenceIDValues: [String]
}

nonisolated struct GraphChatProviderAppliedFilter: Hashable, Sendable {
    let fieldName: String
    let operationDescription: String
    let valueDescription: String?
}

nonisolated struct GraphChatProviderFollowUpSuggestion: Hashable, Sendable {
    let title: String
    let prompt: String
}

nonisolated struct GraphChatProviderFinalAnswer: Hashable, Sendable {
    let directAnswer: String
    let sections: [GraphChatProviderAnswerSection]
    let evidenceIDValues: [String]
    let appliedFilters: [GraphChatProviderAppliedFilter]
    let followUpSuggestions: [GraphChatProviderFollowUpSuggestion]
    let hasInsufficientEvidence: Bool
}

nonisolated enum GraphChatProviderStreamEvent: Hashable, Sendable {
    case toolActivity(GraphChatToolActivity)
    case partialAnswer(GraphChatProviderPartialAnswer)
    case completed(GraphChatProviderFinalAnswer)
}

nonisolated enum GraphChatProviderErrorCode: String, CaseIterable, Hashable, Sendable {
    case unavailable
    case invalidSession
    case concurrentRequest
    case contextWindowExceeded
    case cancelled
    case toolBudgetExceeded
    case toolFailure
    case unsupportedLanguage
    case safetyGuardrail
    case unexpected
}

nonisolated struct GraphChatProviderError: Error, LocalizedError, Hashable, Sendable {
    let code: GraphChatProviderErrorCode
    let message: String

    var errorDescription: String? {
        message
    }

    static func cancelled() -> GraphChatProviderError {
        GraphChatProviderError(
            code: .cancelled,
            message: "Die Modellgenerierung wurde abgebrochen."
        )
    }
}

typealias GraphChatProviderEventStream = AsyncThrowingStream<GraphChatProviderStreamEvent, Error>

nonisolated protocol GraphChatModelProvider: Sendable {
    func availability() async -> GraphChatModelAvailability

    func createSession(
        configuration: GraphChatModelSessionConfiguration
    ) async throws -> GraphChatModelSessionID

    func prewarm(
        sessionID: GraphChatModelSessionID,
        promptPrefix: String?
    ) async throws

    func streamResponse(
        sessionID: GraphChatModelSessionID,
        request: GraphChatModelRequest
    ) async throws -> GraphChatProviderEventStream

    func cancelGeneration(sessionID: GraphChatModelSessionID) async

    func discardSession(sessionID: GraphChatModelSessionID) async
}
