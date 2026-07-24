//
//  GraphChatTabPresentationModelTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph Chat tab presentation")
struct GraphChatTabPresentationModelTests {
    private let graphID = UUID()

    @Test
    func everyAccessRouteMapsToItsDedicatedContentState() {
        let preview = GraphChatTabFreePreviewPresentation(
            showsDraft: true,
            suggestions: [],
            errorMessage: nil
        )
        let indexState = GraphChatIndexPresentationState.stale(documentCount: 12)
        let readyState = GraphChatTabReadyContentState.preparingSession
        let cases: [(GraphChatAccessRoute, GraphChatTabAccessContentState)] = [
            (.noActiveGraph, .noActiveGraph),
            (.graphNotFound, .graphNotFound),
            (.entitlementLoading, .entitlementLoading),
            (.proRequired, .proRequired(preview)),
            (.graphLocked, .graphLocked),
            (.modelAvailabilityLoading, .modelAvailabilityLoading),
            (
                .modelUnavailable(.deviceNotEligible),
                .modelUnavailable(.deviceNotEligible)
            ),
            (
                .modelAvailabilityFailed("availability-code"),
                .modelAvailabilityFailed
            ),
            (.indexPreparing(indexState), .indexPreparing(indexState)),
            (
                .reconciliationRunning(documentCount: 12),
                .reconciliationRunning(indexState)
            ),
            (
                .indexUnavailable(message: "index-code"),
                .indexUnavailable(message: "index-code")
            ),
            (.ready, .ready(readyState))
        ]

        for (route, expected) in cases {
            #expect(
                GraphChatTabAccessContentState.make(
                    route: route,
                    indexState: indexState,
                    freePreview: preview,
                    readyState: readyState
                ) == expected
            )
        }
    }

    @Test
    func validationPendingTakesPriorityOverAccessContent() {
        let request = makeRequest()
        let model = makeModel(
            request: request,
            validationState: .pending(sourceRequestID: request.id),
            entitlement: .pro
        )

        #expect(model.contentState == .launchValidationPending)
    }

    @Test
    func validationErrorTakesPriorityOverAccessContent() {
        let request = makeRequest()
        let error = GraphChatTabLaunchValidationErrorPresentation.make(
            failure: .contextUnavailable,
            language: .english
        )
        let model = makeModel(
            request: request,
            validationState: .invalid(
                sourceRequestID: request.id,
                presentation: error
            ),
            entitlement: .pro
        )

        #expect(model.contentState == .invalidLaunch(error))
    }

    @Test
    func readyChatRequiresMatchingGraphRequestScopeContextAndViewModelIdentity() {
        let request = makeRequest()
        let matchingIdentity = GraphChatTabPresentedSessionIdentity(
            requestID: request.id,
            graphScope: request.scope.graphScope,
            chatScope: request.scope,
            launchContext: request.context
        )
        let matching = makeModel(
            request: request,
            validationState: .valid(
                sourceRequestID: request.id,
                request: request
            ),
            entitlement: .pro,
            presentedSessionIdentity: matchingIdentity
        )
        #expect(
            matching.contentState == .access(
                .ready(.chat(requestID: request.id))
            )
        )

        let mismatched = makeModel(
            request: request,
            validationState: .valid(
                sourceRequestID: request.id,
                request: request
            ),
            entitlement: .pro,
            presentedSessionIdentity: GraphChatTabPresentedSessionIdentity(
                requestID: UUID(),
                graphScope: request.scope.graphScope,
                chatScope: request.scope,
                launchContext: request.context
            )
        )
        #expect(
            mismatched.contentState == .access(
                .ready(.preparingSession)
            )
        )
    }

    @Test
    func draftPreservationMatchesEveryExistingAccessRoute() {
        let preserved: [GraphChatAccessRoute] = [
            .modelAvailabilityLoading,
            .modelUnavailable(.unknown),
            .modelAvailabilityFailed("availability-code"),
            .indexPreparing(.notReady(documentCount: nil)),
            .reconciliationRunning(documentCount: nil),
            .indexUnavailable(message: "index-code"),
            .proRequired,
            .entitlementLoading
        ]
        let discarded: [GraphChatAccessRoute] = [
            .noActiveGraph,
            .graphNotFound,
            .graphLocked,
            .ready
        ]

        for route in preserved {
            #expect(GraphChatTabAccessCoordinator.shouldPreserveDraft(for: route))
        }
        for route in discarded {
            #expect(
                GraphChatTabAccessCoordinator.shouldPreserveDraft(for: route) == false
            )
        }
    }


    @Test
    func runtimeIndexPreparationRequiresProUnlockAndAvailableModel() {
        #expect(
            GraphChatTabAccessCoordinator.shouldPrepareIndexDuringRuntimeRefresh(
                entitlement: .pro,
                isGraphUnlocked: true,
                availability: .available
            )
        )
        #expect(
            GraphChatTabAccessCoordinator.shouldPrepareIndexDuringRuntimeRefresh(
                entitlement: .free,
                isGraphUnlocked: true,
                availability: .available
            ) == false
        )
        #expect(
            GraphChatTabAccessCoordinator.shouldPrepareIndexDuringRuntimeRefresh(
                entitlement: .pro,
                isGraphUnlocked: false,
                availability: .available
            ) == false
        )
        #expect(
            GraphChatTabAccessCoordinator.shouldPrepareIndexDuringRuntimeRefresh(
                entitlement: .pro,
                isGraphUnlocked: true,
                availability: .loading
            ) == false
        )
    }

    @Test
    func taskIdentitiesChangeOnlyWithTheirRelevantInputs() {
        let request = makeRequest()
        let initial = makeModel(
            request: request,
            validationState: .valid(
                sourceRequestID: request.id,
                request: request
            ),
            entitlement: .pro
        )
        let changedRequest = GraphChatLaunchRequest(
            scope: request.scope,
            context: request.context
        )
        let updated = makeModel(
            request: changedRequest,
            validationState: .valid(
                sourceRequestID: changedRequest.id,
                request: changedRequest
            ),
            entitlement: .pro
        )

        #expect(initial.runtimeTaskIdentity == updated.runtimeTaskIdentity)
        #expect(initial.accessTaskIdentity != updated.accessTaskIdentity)
        #expect(
            initial.launchValidationTaskIdentity
                != updated.launchValidationTaskIdentity
        )
    }

    private func makeRequest() -> GraphChatLaunchRequest {
        GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            context: .graph(name: "Portfolio")
        )
    }

    private func makeModel(
        request: GraphChatLaunchRequest,
        validationState: GraphChatTabLaunchValidationState,
        entitlement: GraphChatEntitlementAccessState,
        presentedSessionIdentity: GraphChatTabPresentedSessionIdentity? = nil
    ) -> GraphChatTabPresentationModel {
        GraphChatTabPresentationModel(
            activeGraphIDString: graphID.uuidString,
            activeGraph: GraphChatTabActiveGraphPresentation(
                id: graphID,
                name: "Portfolio",
                isProtected: false
            ),
            sourceRequest: request,
            launchValidationState: validationState,
            entitlement: entitlement,
            lockRevision: 1,
            graphUnlockGranted: false,
            availability: .available,
            indexState: .ready(documentCount: 10),
            isReconciliationRunning: false,
            isGenerationRunning: false,
            presentedSessionIdentity: presentedSessionIdentity,
            previewSuggestions: [],
            previewGraphID: nil,
            previewErrorMessage: nil,
            language: .german
        )
    }
}
