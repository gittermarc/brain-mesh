//
//  GraphChatMessageActionUIContractTests.swift
//  BrainMeshTests
//

import SwiftUI
import Testing
import UIKit

@testable import BrainMesh

@Suite("Graph chat message action UI contracts")
@MainActor
struct GraphChatMessageActionUIContractTests {
    @Test
    func actionAndAccessibilityLabelsAreExplicitAndUnique() {
        let fixedActions: [GraphChatMessageAction] = [
            .copy,
            .editAndResend,
            .regenerate,
            .startNewChat,
            .removeFeedback,
        ]
        let feedbackActions = GraphChatFeedbackCategory.allCases.map {
            GraphChatMessageAction.feedback($0)
        }
        let actions = fixedActions + feedbackActions

        #expect(actions.allSatisfy { $0.title.isEmpty == false })
        #expect(actions.allSatisfy { $0.systemImage.isEmpty == false })
        #expect(Set(actions.map(\.title)).count == actions.count)
        #expect(GraphChatMessageActionAccessibility.userMessageMenuLabel.isEmpty == false)
        #expect(GraphChatMessageActionAccessibility.userMessageMenuHint.isEmpty == false)
        #expect(GraphChatMessageActionAccessibility.assistantMessageMenuLabel.isEmpty == false)
        #expect(GraphChatMessageActionAccessibility.assistantMessageMenuHint.isEmpty == false)
        #expect(GraphChatMessageActionAccessibility.newChatLabel.isEmpty == false)
        #expect(GraphChatMessageActionAccessibility.newChatHint.isEmpty == false)
    }

    @Test
    func messageActionSurfacesRenderForPhoneAndPadAtAccessibilityDynamicType() throws {
        var assistantState = GraphChatAssistantMessageState(
            question: "Welche offenen Punkte gibt es?"
        )
        let interpretation = try
            GraphChatIntentInterpretationTestFixture()
                .filteredCollection(
                    language: .german
                )
        assistantState.apply(
            .completed(
                GraphChatAnswer(
                    directAnswer:
                        "Es gibt zwei offene Punkte mit einer ausführlichen Beschreibung für den Dynamic-Type-Test.",
                    hasInsufficientEvidence: false,
                    presentationContext:
                        GraphChatPresentationContext(
                            registry: .empty,
                            language: .german
                        ),
                    interpretation:
                        interpretation
                )
            )
        )
        let assistantMessage = GraphChatTranscriptMessage(
            state: .assistant(assistantState)
        )
        let userMessage = GraphChatTranscriptMessage(
            state: .userQuestion(
                "Bitte prüfe die offenen Punkte und erkläre die wichtigsten Zusammenhänge ausführlich."
            )
        )

        let configurations: [(width: CGFloat, dynamicTypeSize: DynamicTypeSize)] = [
            (390, .accessibility3),
            (1_024, .accessibility5),
        ]

        for configuration in configurations {
            let assistantImage = try #require(
                renderedImage(
                    message: assistantMessage,
                    availability: GraphChatMessageActionAvailability(
                        canCopy: true,
                        canEditAndResend: false,
                        canRegenerate: true,
                        canGiveFeedback: true
                    ),
                    selectedFeedback: .helpful,
                    width: configuration.width,
                    dynamicTypeSize: configuration.dynamicTypeSize
                )
            )
            let userImage = try #require(
                renderedImage(
                    message: userMessage,
                    availability: GraphChatMessageActionAvailability(
                        canCopy: false,
                        canEditAndResend: true,
                        canRegenerate: false,
                        canGiveFeedback: false
                    ),
                    selectedFeedback: nil,
                    width: configuration.width,
                    dynamicTypeSize: configuration.dynamicTypeSize
                )
            )

            #expect(assistantImage.size.width > 0)
            #expect(assistantImage.size.height > 0)
            #expect(userImage.size.width > 0)
            #expect(userImage.size.height > 0)
        }
    }

    private func renderedImage(
        message: GraphChatTranscriptMessage,
        availability: GraphChatMessageActionAvailability,
        selectedFeedback: GraphChatFeedbackCategory?,
        width: CGFloat,
        dynamicTypeSize: DynamicTypeSize
    ) -> UIImage? {
        let content = GraphChatMessageView(
            message: message,
            actionAvailability: availability,
            selectedFeedback: selectedFeedback,
            onAction: { _ in },
            onRetry: { _ in },
            onOpenEvidence: { _ in },
            onShowEvidenceInGraph: { _ in },
            onUseFollowUp: { _ in }
        )
        .padding()
        .frame(width: width, alignment: .leading)
        .environment(\.dynamicTypeSize, dynamicTypeSize)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 1
        return renderer.uiImage
    }
}
