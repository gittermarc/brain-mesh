//
//  GraphChatTabLaunchValidationControllerTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph Chat tab launch validation")
@MainActor
struct GraphChatTabLaunchValidationControllerTests {
    private let graphID = UUID()

    @Test
    func noRequestCreatesNeutralState() {
        #expect(
            GraphChatTabLaunchValidationController.plan(
                activeGraphID: graphID,
                sourceRequest: nil,
                isGraphUnlocked: true
            ) == .noRequest
        )
        #expect(
            GraphChatTabLaunchValidationController.pendingState(
                activeGraphID: graphID,
                sourceRequest: nil
            ) == .noRequest
        )
    }

    @Test
    func lockedGraphAcceptsRequestWithoutProtectedDataValidation() {
        let request = makeRequest()

        #expect(
            GraphChatTabLaunchValidationController.plan(
                activeGraphID: graphID,
                sourceRequest: request,
                isGraphUnlocked: false
            ) == .acceptWithoutProtectedDataAccess(request)
        )
    }

    @Test
    func unchangedValidRequestRemainsAndNeedsNoCoordinatorReplacement() {
        let request = makeRequest()
        let outcome = GraphChatTabLaunchValidationController.outcome(
            sourceRequest: request,
            result: .valid(request),
            language: .german
        )

        #expect(
            outcome.state == .valid(
                sourceRequestID: request.id,
                request: request
            )
        )
        #expect(outcome.replacementRequest == nil)
    }

    @Test
    func sanitizedValidRequestIsReturnedForCoordinatorReplacement() {
        let request = makeRequest()
        let sanitized = GraphChatLaunchRequest(
            id: request.id,
            scope: request.scope,
            context: .graph(name: "Aktualisierter Graph"),
            prefilledQuestion: request.prefilledQuestion,
            presentationStyle: request.presentationStyle
        )
        let outcome = GraphChatTabLaunchValidationController.outcome(
            sourceRequest: request,
            result: .valid(sanitized),
            language: .german
        )

        #expect(
            outcome.state == .valid(
                sourceRequestID: request.id,
                request: sanitized
            )
        )
        #expect(outcome.replacementRequest == sanitized)
    }

    @Test
    func validationFailuresKeepTheirExactLocalizedPresentation() {
        let germanExpectations: [(GraphChatLaunchValidationFailure, String)] = [
            (
                .graphMismatch,
                "Der Einstieg gehört zu einem anderen Graphen. Öffne den gewünschten Kontext im aktiven Graphen erneut."
            ),
            (
                .emptySelection,
                "Die Canvas-Auswahl ist leer oder enthält keine noch vorhandenen Nodes."
            ),
            (
                .contextUnavailable,
                "Mindestens ein referenziertes Element wurde gelöscht oder ist im aktiven Graphen nicht mehr zugänglich."
            )
        ]

        for (failure, message) in germanExpectations {
            let presentation = GraphChatTabLaunchValidationErrorPresentation.make(
                failure: failure,
                language: .german
            )
            #expect(presentation.failure == failure)
            #expect(presentation.title == "Chat-Kontext nicht mehr verfügbar")
            #expect(presentation.message == message)
            #expect(presentation.continueTitle == "Mit gesamtem Graphen fortfahren")
        }

        let english = GraphChatTabLaunchValidationErrorPresentation.make(
            failure: .contextUnavailable,
            language: .english
        )
        #expect(english.title == "Chat context is no longer available")
        #expect(
            english.message
                == "At least one referenced item was deleted or is no longer accessible in the active graph."
        )
        #expect(english.continueTitle == "Continue with entire graph")
    }

    @Test
    func graphChangeMakesOldValidationStateStaleAndResetReturnsNeutralState() {
        let oldRequest = makeRequest()
        let newRequest = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: UUID()))
        )
        let oldState = GraphChatTabLaunchValidationState.valid(
            sourceRequestID: oldRequest.id,
            request: oldRequest
        )
        let oldPendingState = GraphChatTabLaunchValidationState.pending(
            sourceRequestID: oldRequest.id
        )

        #expect(oldState.effectiveRequest(matching: newRequest) == nil)
        #expect(oldState.isPending(matching: newRequest))
        #expect(oldPendingState.isPending(matching: newRequest))
        #expect(
            GraphChatTabLaunchValidationState.afterActiveGraphChange()
                == .noRequest
        )
    }

    private func makeRequest() -> GraphChatLaunchRequest {
        GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            context: .graph(name: "Portfolio"),
            prefilledQuestion: "Welche Projekte sind offen?"
        )
    }
}
