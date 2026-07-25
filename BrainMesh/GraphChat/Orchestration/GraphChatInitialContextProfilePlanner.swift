//
//  GraphChatInitialContextProfilePlanner.swift
//  BrainMesh
//
//  Pure initial standard/compact model-context selection.
//

import Foundation

nonisolated struct GraphChatInitialContextProfileInput: Hashable, Sendable {
    let schemaPrompt: String
    let conversationContext: String
    let question: String
    let systemInstructions: String

    var estimatedCharacterCount: Int {
        schemaPrompt.count
            + conversationContext.count
            + min(
                question.count,
                GraphChatModelContextProfile.standard.maximumQuestionCharacters
            )
            + systemInstructions.count
    }
}

nonisolated struct GraphChatInitialContextProfilePlanner: Hashable, Sendable {
    let compactThreshold: Int

    init(compactThreshold: Int = 5_000) {
        precondition(compactThreshold > 0)
        self.compactThreshold = compactThreshold
    }

    func profile(
        for input: GraphChatInitialContextProfileInput
    ) -> GraphChatModelContextProfile {
        input.estimatedCharacterCount > compactThreshold
            ? .compact
            : .standard
    }
}
