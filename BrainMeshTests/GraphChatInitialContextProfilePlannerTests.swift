//
//  GraphChatInitialContextProfilePlannerTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat initial context profile planner")
struct GraphChatInitialContextProfilePlannerTests {
    @Test
    func thresholdAndBelowUseStandardWhileLargerInputUsesCompact() {
        let planner = GraphChatInitialContextProfilePlanner(
            compactThreshold: 5_000
        )
        let exactlyAtThreshold = GraphChatInitialContextProfileInput(
            schemaPrompt: String(repeating: "S", count: 3_000),
            conversationContext: String(repeating: "C", count: 1_000),
            question: String(repeating: "Q", count: 500),
            systemInstructions: String(repeating: "I", count: 500)
        )
        let aboveThreshold = GraphChatInitialContextProfileInput(
            schemaPrompt: exactlyAtThreshold.schemaPrompt + "S",
            conversationContext: exactlyAtThreshold.conversationContext,
            question: exactlyAtThreshold.question,
            systemInstructions: exactlyAtThreshold.systemInstructions
        )

        #expect(exactlyAtThreshold.estimatedCharacterCount == 5_000)
        #expect(planner.profile(for: exactlyAtThreshold) == .standard)
        #expect(aboveThreshold.estimatedCharacterCount == 5_001)
        #expect(planner.profile(for: aboveThreshold) == .compact)
    }

    @Test
    func questionEstimateUsesTheExistingStandardQuestionLimit() {
        let input = GraphChatInitialContextProfileInput(
            schemaPrompt: "",
            conversationContext: "",
            question: String(repeating: "Q", count: 4_000),
            systemInstructions: ""
        )

        #expect(
            input.estimatedCharacterCount
                == GraphChatModelContextProfile.standard.maximumQuestionCharacters
        )
    }

    @Test
    func identicalInputsAlwaysProduceTheSameInitialProfile() {
        let planner = GraphChatInitialContextProfilePlanner()
        let input = GraphChatInitialContextProfileInput(
            schemaPrompt: String(repeating: "S", count: 2_000),
            conversationContext: String(repeating: "C", count: 900),
            question: "Which projects are open?",
            systemInstructions: String(repeating: "I", count: 700)
        )

        #expect(planner.profile(for: input) == planner.profile(for: input))
        #expect(planner.profile(for: input) != .recovery)
    }
}
