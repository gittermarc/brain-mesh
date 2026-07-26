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
    case modelUnavailable
    case toolFailure
    case toolBudgetExceeded
    case contextWindowExceeded
    case concurrentRequest
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
    let artifactIDs: [GraphChatAnswerArtifactID]
    let querySummary: GraphChatAnswerArtifactQuerySummary?
    let state: GraphChatAnswerState

    init(
        id: UUID = UUID(),
        title: String? = nil,
        text: String,
        evidenceIDs: [GraphEvidenceID] = [],
        artifactIDs: [GraphChatAnswerArtifactID] = [],
        querySummary: GraphChatAnswerArtifactQuerySummary? = nil,
        state: GraphChatAnswerState = .answer
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.evidenceIDs = evidenceIDs
        var seenArtifactIDs = Set<GraphChatAnswerArtifactID>()
        self.artifactIDs = artifactIDs.filter {
            seenArtifactIDs.insert($0).inserted
        }
        self.querySummary = querySummary
        self.state = state
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

nonisolated struct GraphChatAnswer: Hashable, Sendable {
    let state: GraphChatAnswerState
    let directAnswer: String
    let sections: [GraphChatAnswerSection]
    let evidence: [GraphEvidence]
    let artifactIDs: [GraphChatAnswerArtifactID]
    let appliedFilters: [GraphChatAppliedFilter]
    let followUpSuggestions: [GraphChatFollowUpSuggestion]
    let hasInsufficientEvidence: Bool
    let presentationContext: GraphChatPresentationContext?

    var evidenceIDs: [GraphEvidenceID] {
        evidence.map(\.id)
    }

    init(
        state: GraphChatAnswerState = .answer,
        directAnswer: String,
        sections: [GraphChatAnswerSection] = [],
        evidence: [GraphEvidence] = [],
        artifactIDs: [GraphChatAnswerArtifactID] = [],
        appliedFilters: [GraphChatAppliedFilter] = [],
        followUpSuggestions: [GraphChatFollowUpSuggestion] = [],
        hasInsufficientEvidence: Bool,
        presentationContext: GraphChatPresentationContext? = nil
    ) {
        self.state = state
        self.directAnswer = directAnswer
        self.sections = sections
        self.evidence = GraphEvidenceCollection(evidence).values
        var seenArtifactIDs = Set<GraphChatAnswerArtifactID>()
        self.artifactIDs = artifactIDs.filter { seenArtifactIDs.insert($0).inserted }
        self.appliedFilters = appliedFilters
        self.followUpSuggestions = followUpSuggestions
        self.hasInsufficientEvidence = hasInsufficientEvidence
        self.presentationContext = presentationContext
    }

    func retainingArtifactIDs(
        _ retainedIDs: Set<GraphChatAnswerArtifactID>
    ) -> GraphChatAnswer {
        let retainedSections = sections.map { section in
            let retainedSectionIDs = section.artifactIDs.filter {
                retainedIDs.contains($0)
            }
            return GraphChatAnswerSection(
                id: section.id,
                title: section.title,
                text: section.text,
                evidenceIDs: section.evidenceIDs,
                artifactIDs: retainedSectionIDs,
                querySummary: retainedSectionIDs.isEmpty ? nil : section.querySummary,
                state: section.state
            )
        }
        return GraphChatAnswer(
            state: state,
            directAnswer: directAnswer,
            sections: retainedSections,
            evidence: evidence,
            artifactIDs: artifactIDs.filter { retainedIDs.contains($0) },
            appliedFilters: appliedFilters,
            followUpSuggestions: followUpSuggestions,
            hasInsufficientEvidence: hasInsufficientEvidence,
            presentationContext: presentationContext
        )
    }
}

nonisolated enum GraphChatStreamEvent: Hashable, Sendable {
    case started(requestID: UUID)
    case toolActivity(GraphChatToolActivity)
    case partialAnswer(String)
    case completed(GraphChatAnswer)
    case cancelled
    case failure(GraphChatError)
}

typealias GraphChatEventStream = AsyncStream<GraphChatStreamEvent>
