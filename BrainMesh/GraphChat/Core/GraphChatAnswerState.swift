//
//  GraphChatAnswerState.swift
//  BrainMesh
//
//  Explicit value-only answer states for deterministic UI and test behavior.
//

import Foundation

nonisolated enum GraphChatUnsupportedCapability: String, CaseIterable, Hashable, Sendable {
    case graphMutation
    case attachmentContent
    case multiHop
    case queryPlanV2
    case other
}

nonisolated struct GraphChatClarificationOption: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
}

nonisolated struct GraphChatClarification: Hashable, Sendable {
    let id: UUID
    let question: String
    let options: [GraphChatClarificationOption]
}

nonisolated enum GraphChatAnswerState: Hashable, Sendable {
    case answer
    case clarification(GraphChatClarification)
    case noResults
    case unsupported(GraphChatUnsupportedCapability)
}
