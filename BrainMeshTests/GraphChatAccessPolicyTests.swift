import Foundation
import Testing
@testable import BrainMesh

struct GraphChatAccessPolicyTests {
    private let graphID = UUID()

    @Test
    func entitlementAndGraphPreconditionsAreDeterministic() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))

        #expect(decision(scope: scope, entitlement: .unknown).route == .entitlementLoading)
        #expect(decision(scope: scope, entitlement: .free).route == .proRequired)
        #expect(decision(scope: scope, entitlement: .pro).route == .ready)
        #expect(decision(scope: scope, entitlement: .pro, graphExists: false).route == .graphNotFound)
        #expect(decision(scope: scope, entitlement: .pro, unlocked: false).route == .graphLocked)
        #expect(
            decision(
                scope: .entireGraph(GraphScope(graphID: UUID())),
                entitlement: .pro
            ).route == .noActiveGraph
        )
    }

    @Test
    func everyModelAvailabilityStateHasOneConcreteRoute() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))

        #expect(decision(scope: scope, availability: .loading).route == .modelAvailabilityLoading)
        #expect(decision(scope: scope, availability: .available).route == .ready)
        for reason in GraphChatModelUnavailableReason.allCases {
            #expect(
                decision(
                    scope: scope,
                    availability: .unavailable(reason: reason)
                ).route == .modelUnavailable(reason)
            )
        }
        #expect(
            decision(
                scope: scope,
                availability: .failed(message: "availability-code-7")
            ).route == .modelAvailabilityFailed("availability-code-7")
        )
    }

    @Test
    func indexBuildReadyStaleFailedAndReconciliationAreDistinguished() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let preparingStates: [GraphChatIndexPresentationState] = [
            .loading,
            .notReady(documentCount: nil),
            .building(processed: 42, estimated: 100, documentCount: 42),
            .stale(documentCount: 500)
        ]

        for state in preparingStates {
            #expect(decision(scope: scope, indexState: state).route == .indexPreparing(state))
        }

        let ready = decision(scope: scope, indexState: .ready(documentCount: 800))
        #expect(ready.route == .ready)
        #expect(ready.canPresentChat)
        #expect(ready.canStartGeneration)
        #expect(ready.usesIndexFallback == false)

        #expect(
            decision(
                scope: scope,
                indexState: .reconciling(documentCount: 720)
            ).route == .reconciliationRunning(documentCount: 720)
        )
        #expect(
            decision(
                scope: scope,
                indexState: .ready(documentCount: 800),
                reconciliationRunning: true
            ).route == .reconciliationRunning(documentCount: 800)
        )

        let usableFailure = decision(
            scope: scope,
            indexState: .failed(
                message: "index-code-stale",
                isUsable: true,
                documentCount: 700
            )
        )
        #expect(usableFailure.route == .ready)
        #expect(usableFailure.usesIndexFallback)

        #expect(
            decision(
                scope: scope,
                indexState: .failed(
                    message: "index-code-corrupt",
                    isUsable: false,
                    documentCount: nil
                )
            ).route == .indexUnavailable(message: "index-code-corrupt")
        )
    }

    @Test
    func runningGenerationAllowsCancellationButBlocksSecondSend() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let running = decision(
            scope: scope,
            generationRunning: true
        )

        #expect(running.route == .ready)
        #expect(running.canPresentChat)
        #expect(running.canStartGeneration == false)
        #expect(running.canCancelGeneration)
    }

    private func decision(
        scope: GraphChatScope,
        entitlement: GraphChatEntitlementAccessState = .pro,
        graphExists: Bool = true,
        unlocked: Bool = true,
        availability: GraphChatAvailabilityPresentationState = .available,
        indexState: GraphChatIndexPresentationState = .ready(documentCount: 100),
        reconciliationRunning: Bool = false,
        generationRunning: Bool = false
    ) -> GraphChatAccessDecision {
        GraphChatAccessPolicy.evaluate(
            GraphChatAccessPolicyInput(
                activeGraphID: graphID,
                graphExists: graphExists,
                requestedScope: scope,
                entitlement: entitlement,
                graphRequiresUnlock: true,
                isGraphUnlocked: unlocked,
                availability: availability,
                indexState: indexState,
                isReconciliationRunning: reconciliationRunning,
                isGenerationRunning: generationRunning
            )
        )
    }
}
