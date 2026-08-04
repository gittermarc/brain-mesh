//
//  GraphChatTranscriptControllerTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat transcript scrolling")
@MainActor
struct GraphChatTranscriptControllerTests {
    @Test
    func partialRequestsAutoScrollOnlyWhileViewportIsAtBottom() {
        let setup = makeSetup()

        #expect(
            setup.controller.apply(
                publication(
                    events: [.partialAnswer("Safe partial")],
                    reason: .partial
                ),
                toAssistantMessageID: setup.assistantID
            )
        )
        #expect(setup.controller.scrollRequest?.trigger == .partial)

        let priorRequest = setup.controller.scrollRequest
        setup.controller.updateViewport(isAtBottom: false)
        #expect(
            setup.controller.apply(
                publication(
                    events: [.partialAnswer("Newer safe partial")],
                    reason: .partial
                ),
                toAssistantMessageID: setup.assistantID
            )
        )
        #expect(setup.controller.scrollRequest == priorRequest)
    }

    @Test
    func manualUpwardNavigationSuppressesTerminalPositioning() {
        let setup = makeSetup()
        setup.controller.userDidNavigateTranscript()

        _ = setup.controller.apply(
            publication(
                events: [
                    .completed(
                        GraphChatUITestSupport.finalAnswer(
                            directAnswer: "Safe final"
                        )
                    )
                ],
                reason: .terminal
            ),
            toAssistantMessageID: setup.assistantID
        )

        #expect(setup.controller.scrollRequest == nil)
    }

    @Test
    func contentGrowthAloneDoesNotDisableBottomFollowing() {
        let setup = makeSetup()

        setup.controller.updateViewport(
            isAtBottom: false,
            userInitiated: false
        )
        _ = setup.controller.apply(
            publication(
                events: [.partialAnswer("A taller safe partial")],
                reason: .partial
            ),
            toAssistantMessageID: setup.assistantID
        )

        #expect(setup.controller.isAtBottom)
        #expect(setup.controller.scrollRequest?.trigger == .partial)
    }

    @Test
    func partialScrollingNeverAnimatesAndReduceMotionDisablesAllAnimation() {
        #expect(
            GraphChatTranscriptScrollPolicy.animation(
                for: .partial,
                reduceMotion: false
            ) == .none
        )
        #expect(
            GraphChatTranscriptScrollPolicy.animation(
                for: .terminal,
                reduceMotion: false
            ) == .subtle
        )
        for trigger in [
            GraphChatTranscriptScrollTrigger.turnStarted,
            .partial,
            .terminal,
            .conversationMutation,
        ] {
            #expect(
                GraphChatTranscriptScrollPolicy.animation(
                    for: trigger,
                    reduceMotion: true
                ) == .none
            )
        }
    }

    @Test
    func terminalRequestsSubtlePositioningWhenStillAtBottom() {
        let setup = makeSetup()

        _ = setup.controller.apply(
            publication(
                events: [
                    .partialAnswer("Latest safe partial"),
                    .completed(
                        GraphChatUITestSupport.finalAnswer(
                            directAnswer: "Safe final"
                        )
                    ),
                ],
                reason: .terminal
            ),
            toAssistantMessageID: setup.assistantID
        )

        #expect(setup.controller.scrollRequest?.trigger == .terminal)
        #expect(
            GraphChatTranscriptScrollPolicy.animation(
                for: .terminal,
                reduceMotion: false
            ) == .subtle
        )
    }

    private func makeSetup() -> (
        controller: GraphChatTranscriptController,
        assistantID: UUID
    ) {
        let controller = GraphChatTranscriptController()
        let assistantID = UUID()
        controller.replaceMessages(
            [
                GraphChatTranscriptMessage(
                    id: assistantID,
                    state: .assistant(
                        GraphChatAssistantMessageState(
                            question: "Question"
                        )
                    )
                )
            ]
        )
        return (controller, assistantID)
    }

    private func publication(
        events: [GraphChatStreamEvent],
        reason: GraphChatStreamingUIPublicationReason
    ) -> GraphChatStreamingUIPublication {
        GraphChatStreamingUIPublication(
            events: events,
            reason: reason,
            firstSourceSequence: 1,
            lastSourceSequence: UInt64(events.count)
        )
    }
}
