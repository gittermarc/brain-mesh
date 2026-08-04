//
//  GraphChatGenerationModels.swift
//  BrainMesh
//
//  Value-only lifecycle domain for one technical graph-chat generation.
//

import Foundation

nonisolated struct GraphChatGenerationOperationID:
    RawRepresentable,
    Hashable,
    Sendable,
    Identifiable
{
    let rawValue: UUID

    var id: UUID {
        rawValue
    }

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

nonisolated enum GraphChatGenerationMode: String, CaseIterable, Hashable, Sendable {
    case newTurn
    case regeneration
    case technicalRetry
    case branchReplacement

    var isRegeneration: Bool {
        self == .regeneration || self == .technicalRetry
    }
}

nonisolated struct GraphChatGenerationRequest: Hashable, Sendable {
    let question: String
    let assistantMessageID: UUID
    let mode: GraphChatGenerationMode
    let usedIndexFallback: Bool

    init(
        question: String,
        assistantMessageID: UUID,
        mode: GraphChatGenerationMode,
        usedIndexFallback: Bool
    ) {
        self.question = question
        self.assistantMessageID = assistantMessageID
        self.mode = mode
        self.usedIndexFallback = usedIndexFallback
    }
}

nonisolated struct GraphChatActiveGeneration: Hashable, Sendable {
    let operationID: GraphChatGenerationOperationID
    let assistantMessageID: UUID
    let mode: GraphChatGenerationMode
}

nonisolated enum GraphChatGenerationState: Hashable, Sendable {
    case idle
    case generating(GraphChatActiveGeneration)

    var activeGeneration: GraphChatActiveGeneration? {
        guard case .generating(let generation) = self else {
            return nil
        }
        return generation
    }

    var isGenerating: Bool {
        activeGeneration != nil
    }
}

nonisolated enum GraphChatGenerationOutcome: Hashable, Sendable {
    case completed
    case noResults
    case cancelled
    case failure(GraphChatError)

    var isSuccessful: Bool {
        switch self {
        case .completed, .noResults:
            return true
        case .cancelled, .failure:
            return false
        }
    }
}

@MainActor
struct GraphChatGenerationCallbacks {
    let messageSnapshot: () -> [GraphChatTranscriptMessage]
    let operationWillCancel: (
        _ operationID: GraphChatGenerationOperationID,
        _ assistantMessageID: UUID
    ) -> Void
    let publicationDidArrive: (
        _ publication: GraphChatStreamingUIPublication,
        _ operationID: GraphChatGenerationOperationID,
        _ assistantMessageID: UUID
    ) -> Void
    let completedTurnDidArrive: (
        _ operationID: GraphChatGenerationOperationID,
        _ assistantMessageID: UUID
    ) async -> Void
    let outcomeDidResolve: (
        _ operationID: GraphChatGenerationOperationID,
        _ assistantMessageID: UUID,
        _ outcome: GraphChatGenerationOutcome
    ) -> Void
    let generationStateDidChange: (_ isGenerating: Bool) -> Void

    init(
        messageSnapshot: @escaping () -> [GraphChatTranscriptMessage],
        operationWillCancel: @escaping (
            _ operationID: GraphChatGenerationOperationID,
            _ assistantMessageID: UUID
        ) -> Void = { _, _ in },
        publicationDidArrive: @escaping (
            _ publication: GraphChatStreamingUIPublication,
            _ operationID: GraphChatGenerationOperationID,
            _ assistantMessageID: UUID
        ) -> Void,
        completedTurnDidArrive: @escaping (
            _ operationID: GraphChatGenerationOperationID,
            _ assistantMessageID: UUID
        ) async -> Void = { _, _ in },
        outcomeDidResolve: @escaping (
            _ operationID: GraphChatGenerationOperationID,
            _ assistantMessageID: UUID,
            _ outcome: GraphChatGenerationOutcome
        ) -> Void = { _, _, _ in },
        generationStateDidChange: @escaping (_ isGenerating: Bool) -> Void
    ) {
        self.messageSnapshot = messageSnapshot
        self.operationWillCancel = operationWillCancel
        self.publicationDidArrive = publicationDidArrive
        self.completedTurnDidArrive = completedTurnDidArrive
        self.outcomeDidResolve = outcomeDidResolve
        self.generationStateDidChange = generationStateDidChange
    }
}
