import Foundation
import Testing
@testable import BrainMesh

struct GraphChatMessageStateTests {
    @Test
    func streamEventsReduceInDeterministicOrder() throws {
        let activityID = UUID()
        let evidence = makeEvidence(index: 1)
        var state = GraphChatAssistantMessageState(question: "Wie ist der Status?")

        state.apply(.started(requestID: UUID()))
        state.apply(
            .toolActivity(
                GraphChatToolActivity(
                    id: activityID,
                    tool: .searchGraph,
                    state: .started
                )
            )
        )
        state.apply(.partialAnswer("Projekt Atlas"))

        #expect(state.phase == .partial)
        #expect(state.text == "Projekt Atlas")
        #expect(state.allowsEvidenceActions == false)
        #expect(state.toolActivities.count == 1)
        #expect(state.toolActivities.first?.state == .started)

        state.apply(
            .toolActivity(
                GraphChatToolActivity(
                    id: activityID,
                    tool: .searchGraph,
                    state: .finished
                )
            )
        )
        state.apply(
            .completed(
                GraphChatUITestSupport.finalAnswer(
                    state: .answer,
                    directAnswer: "Projekt Atlas ist offen.",
                    evidence: [evidence]
                )
            )
        )

        #expect(state.phase == .final)
        #expect(state.text == "Projekt Atlas ist offen.")
        #expect(state.toolActivities.count == 1)
        #expect(state.toolActivities.first?.state == .finished)
        #expect(state.allowsEvidenceActions)
        #expect(state.answer?.evidence == [evidence])
    }

    @Test
    func partialAnswerNeverOffersSourceActions() {
        var state = GraphChatAssistantMessageState(question: "Frage")

        state.apply(.partialAnswer("Eine partielle Antwort"))

        #expect(state.phase == .partial)
        #expect(state.answer == nil)
        #expect(state.allowsEvidenceActions == false)
    }

    @Test
    func finalPresentationBoundsLargeAnswersAndEvidenceCollections() {
        let oversizedEvidenceCount =
            GraphChatAssistantMessageState
                .maximumEvidence + 1
        let evidence = (
            0..<oversizedEvidenceCount
        ).map(makeEvidence)
        let filters = (0..<20).map { index in
            GraphChatAppliedFilter(
                fieldName: "Feld \(index)",
                operationDescription: "entspricht",
                valueDescription: "Wert \(index)"
            )
        }
        let followUps = (0..<10).map { index in
            GraphChatFollowUpSuggestion(
                title: "Folgefrage \(index)",
                prompt: "Prompt \(index)"
            )
        }
        let oversizedTextLength =
            GraphChatAssistantMessageState
                .maximumTextLength + 1
        let sections = (0..<12).map { index in
            GraphChatAnswerSection(
                title: "Abschnitt \(index)",
                text: String(
                    repeating: "A",
                    count: oversizedTextLength
                )
            )
        }
        var state = GraphChatAssistantMessageState(question: "Frage")

        state.apply(
            .completed(
                GraphChatAnswer(
                    directAnswer: String(
                        repeating: "B",
                        count: oversizedTextLength
                    ),
                    sections: sections,
                    evidence: evidence,
                    appliedFilters: filters,
                    followUpSuggestions: followUps,
                    hasInsufficientEvidence: false
                )
            )
        )

        #expect(state.answer?.directAnswer.count == GraphChatAssistantMessageState.maximumTextLength)
        #expect(state.answer?.sections.count == GraphChatAssistantMessageState.maximumSections)
        #expect(state.answer?.sections.first?.text.count == GraphChatAssistantMessageState.maximumTextLength)
        #expect(state.answer?.evidence.count == GraphChatAssistantMessageState.maximumEvidence)
        #expect(state.answer?.appliedFilters.count == GraphChatAssistantMessageState.maximumFilters)
        #expect(state.answer?.followUpSuggestions.count == GraphChatAssistantMessageState.maximumFollowUps)
    }

    @Test
    func insufficientAnswerWithoutEvidenceBecomesNoResults() {
        var state = GraphChatAssistantMessageState(question: "Unbekannt?")

        state.apply(
            .completed(
                GraphChatUITestSupport.finalAnswer(
                    state: .noResults,
                    directAnswer: "Dafür wurden keine verlässlichen Daten gefunden.",
                    insufficient: true
                )
            )
        )

        #expect(state.phase == .noResults)
        #expect(state.allowsEvidenceActions == false)
    }

    @Test
    func availabilityTechnicalAndCancellationStatesStayDistinct() {
        var availability = GraphChatAssistantMessageState(question: "Frage")
        availability.apply(
            .failure(
                GraphChatError(
                    code: .modelUnavailable,
                    message: "Modell nicht verfügbar"
                )
            )
        )

        var technical = GraphChatAssistantMessageState(question: "Frage")
        technical.apply(
            .failure(
                GraphChatError(
                    code: .toolFailure,
                    message: "Tool fehlgeschlagen"
                )
            )
        )

        var cancelled = GraphChatAssistantMessageState(question: "Frage")
        cancelled.apply(.partialAnswer("Begonnene Antwort"))
        cancelled.apply(.cancelled)

        #expect(availability.phase == .availabilityError)
        #expect(availability.canRetry == false)
        #expect(technical.phase == .technicalError)
        #expect(technical.canRetry)
        #expect(cancelled.phase == .cancelled)
        #expect(cancelled.text == "Begonnene Antwort")
    }

    private func makeEvidence(index: Int) -> GraphEvidence {
        let sourceID = UUID(
            uuidString: String(
                format: "D0000000-0000-0000-0000-%012d",
                index + 1
            )
        )!
        return GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: GraphChatTestSupport.graphID,
                sourceKind: .entity,
                sourceID: sourceID
            ),
            summary: "Quelle \(index)",
            navigationTitle: "Quelle \(index)",
            identitySuffix: "message-state-\(index)"
        )
    }
}
