//
//  GraphChatModels.swift
//  BrainMesh
//
//  Provider-independent and UI-independent graph chat core models.
//

import Foundation

nonisolated struct GraphEvidenceID: RawRepresentable, Hashable, Sendable, Identifiable {
    let rawValue: UUID

    var id: UUID {
        rawValue
    }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated enum GraphChatRole: String, CaseIterable, Hashable, Sendable {
    case system
    case user
    case assistant
}

nonisolated struct GraphChatMessage: Hashable, Sendable, Identifiable {
    let id: UUID
    let role: GraphChatRole
    let text: String
    let createdAt: Date
    let evidenceIDs: [GraphEvidenceID]

    init(
        id: UUID = UUID(),
        role: GraphChatRole,
        text: String,
        createdAt: Date = Date(),
        evidenceIDs: [GraphEvidenceID] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.evidenceIDs = evidenceIDs
    }
}

nonisolated struct GraphChatRequest: Hashable, Sendable, Identifiable {
    let id: UUID
    let scope: GraphChatScope
    let messages: [GraphChatMessage]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        scope: GraphChatScope,
        messages: [GraphChatMessage],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.scope = scope
        self.messages = messages
        self.createdAt = createdAt
    }
}

nonisolated enum GraphChatErrorCode: String, CaseIterable, Hashable, Sendable {
    case invalidRequest
    case schemaUnavailable
    case invalidQueryPlan
    case cancelled
    case unavailable
    case unexpected
}

nonisolated struct GraphChatError: Error, LocalizedError, Hashable, Sendable {
    let code: GraphChatErrorCode
    let message: String
    let recoverySuggestion: String?

    var errorDescription: String? {
        message
    }

    init(
        code: GraphChatErrorCode,
        message: String,
        recoverySuggestion: String? = nil
    ) {
        self.code = code
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

nonisolated struct GraphChatAnswerSection: Hashable, Sendable, Identifiable {
    let id: UUID
    let title: String?
    let text: String
    let evidenceIDs: [GraphEvidenceID]

    init(
        id: UUID = UUID(),
        title: String? = nil,
        text: String,
        evidenceIDs: [GraphEvidenceID] = []
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.evidenceIDs = evidenceIDs
    }
}

nonisolated struct GraphChatAppliedFilter: Hashable, Sendable, Identifiable {
    let id: UUID
    let fieldName: String
    let operationDescription: String
    let valueDescription: String?

    init(
        id: UUID = UUID(),
        fieldName: String,
        operationDescription: String,
        valueDescription: String? = nil
    ) {
        self.id = id
        self.fieldName = fieldName
        self.operationDescription = operationDescription
        self.valueDescription = valueDescription
    }
}

nonisolated struct GraphChatFollowUpSuggestion: Hashable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let prompt: String

    init(
        id: UUID = UUID(),
        title: String,
        prompt: String
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
    }
}
