//
//  GraphChatAnswerStateAndLanguageTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat answer states and language")
struct GraphChatAnswerStateAndLanguageTests {
    @Test
    func answerClarificationNoResultsAndUnsupportedStayTyped() {
        let clarification = GraphChatClarification(
            id: UUID(),
            question: "Which project?",
            options: [GraphChatClarificationOption(id: "CI_ONE", title: "Phoenix")]
        )
        let values: [GraphChatAnswerState] = [
            .answer,
            .clarification(clarification),
            .noResults,
            .unsupported(.multiHop),
        ]

        #expect(Set(values).count == 4)
    }

    @Test
    func presentationDoesNotInferNoResultsFromMissingEvidence() {
        var state = GraphChatAssistantMessageState(question: "Question")
        state.apply(
            .completed(
                GraphChatAnswer(
                    state: .answer,
                    directAnswer: "Evidence is incomplete.",
                    evidence: [],
                    hasInsufficientEvidence: true
                )
            )
        )

        #expect(state.phase == .final)
    }

    @Test
    func explicitNoResultsAndTechnicalFailureRemainDistinct() {
        var noResults = GraphChatAssistantMessageState(question: "Question")
        noResults.apply(
            .completed(
                GraphChatAnswer(
                    state: .noResults,
                    directAnswer: "No results.",
                    hasInsufficientEvidence: true
                )
            )
        )
        var technical = GraphChatAssistantMessageState(question: "Question")
        technical.apply(
            .failure(
                GraphChatError(
                    code: .toolFailure,
                    message: "Repository failed"
                )
            )
        )

        #expect(noResults.phase == .noResults)
        #expect(technical.phase == .technicalError)
    }

    @Test
    func germanAndEnglishQuestionsAreDetectedFromTheCurrentTurn() {
        let selector = GraphChatResponseLanguageSelector(fallback: .english)

        #expect(selector.language(for: "Welche davon sind überfällig?") == .german)
        #expect(selector.language(for: "Which of those are overdue?") == .english)
    }

    @Test
    func languageCanSwitchBetweenTwoTurns() {
        let selector = GraphChatResponseLanguageSelector(fallback: .german)

        let first = selector.language(for: "Zeige davon nur die wichtigen.")
        let second = selector.language(for: "Which one is the oldest?")

        #expect(first == .german)
        #expect(second == .english)
    }

    @Test
    func ambiguousLanguageUsesConfiguredFallback() {
        #expect(
            GraphChatResponseLanguageSelector(fallback: .german)
                .language(for: "Phoenix 2026") == .german
        )
        #expect(
            GraphChatResponseLanguageSelector(fallback: .english)
                .language(for: "Phoenix 2026") == .english
        )
    }

    @Test
    func unsupportedReadOnlyBoundariesAreDetectedDeterministically() {
        let detector = GraphChatUnsupportedRequestDetector()

        #expect(detector.capability(for: "Lösche den Node Phoenix") == .graphMutation)
        #expect(detector.capability(for: "Read the PDF attachment contents") == .attachmentContent)
        #expect(detector.capability(for: "Calculate the shortest path") == .multiHop)
        #expect(detector.capability(for: "Use Query Plan v2") == .queryPlanV2)
        #expect(detector.capability(for: "Show projects") == nil)
    }

    @Test
    func multiTurnPhrasesMapToTypedReferencesAndOperations() {
        let interpreter = GraphChatConversationReferenceInterpreter()

        #expect(
            interpreter.interpretation(for: "Zeige davon nur die wichtigen.")
                == GraphChatConversationReferenceInterpretation(
                    proposal: .latestResults,
                    operation: .filterReferenceSet
                )
        )
        #expect(
            interpreter.interpretation(for: "Öffne den zweiten.")
                == GraphChatConversationReferenceInterpretation(
                    proposal: .ordinal(2),
                    operation: .openReference
                )
        )
        #expect(
            interpreter.interpretation(for: "Wie viele davon sind überfällig?")
                == GraphChatConversationReferenceInterpretation(
                    proposal: .latestResults,
                    operation: .countReferenceSet
                )
        )
        #expect(
            interpreter.interpretation(for: "Gruppiere diese nach Status.")
                == GraphChatConversationReferenceInterpretation(
                    proposal: .latestResults,
                    operation: .groupReferenceSet
                )
        )
        #expect(
            interpreter.interpretation(for: "Nur die ersten drei.")
                == GraphChatConversationReferenceInterpretation(
                    proposal: .latestResultsSubset(offset: 0, limit: 3),
                    operation: .filterReferenceSet
                )
        )
        #expect(
            interpreter.interpretation(for: "Welches davon ist am ältesten?")
                == GraphChatConversationReferenceInterpretation(
                    proposal: .latestResults,
                    operation: .sortReferenceSet
                )
        )
    }
}
