//
//  GraphChatClarificationLifecycleTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat clarification lifecycle")
struct GraphChatClarificationLifecycleTests {
    @Test
    func newConversationStartsWithoutAPendingClarification() {
        let graphScope = GraphScope(graphID: UUID())
        let state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope),
            resetReason: .newConversation
        )

        #expect(state.pendingClarification == nil)
        #expect(state.lastResetReason == .newConversation)
    }

    @Test
    func scopeAndGraphTransitionsDiscardPendingClarifications() {
        let firstGraph = GraphScope(graphID: UUID())
        let firstScope = GraphChatScope.entireGraph(firstGraph)
        let pending = makePending(graphScope: firstGraph, chatScope: firstScope)
        var state = GraphChatConversationState.initial(
            graphScope: firstGraph,
            chatScope: firstScope
        )
        state.pendingClarification = pending
        let reducer = GraphChatConversationStateReducer()

        let entityScope = GraphChatScope.entity(UUID(), in: firstGraph)
        let scoped = reducer.transition(state, to: entityScope)
        #expect(scoped.state.pendingClarification == nil)
        #expect(scoped.state.lastResetReason == .scopeChanged)

        let secondGraph = GraphScope(graphID: UUID())
        let graphChanged = reducer.transition(
            state,
            to: .entireGraph(secondGraph)
        )
        #expect(graphChanged.state.pendingClarification == nil)
        #expect(graphChanged.state.lastResetReason == .graphChanged)
        #expect(graphChanged.state.conversationID != state.conversationID)
    }

    @Test
    func reducerBoundsClarificationOptionsAndContinuationQuestion() throws {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        let pending = GraphChatPendingClarification(
            id: UUID(),
            decision: .conversationReference,
            options: (0..<12).map { index in
                GraphChatPendingClarificationOption(
                    id: "OPTION_\(index)",
                    title: "Option \(index)",
                    proposal: .alias("CI_\(index)")
                )
            },
            sourceTurnID: UUID(),
            graphScope: graphScope,
            chatScope: chatScope,
            continuationOperation: .filterReferenceSet,
            continuationQuestion: String(repeating: "Q", count: 800),
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        let reduced = try GraphChatConversationStateReducer().reduce(
            state,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .clarificationRequested(pending)
            )
        )

        #expect(reduced.state.pendingClarification?.options.count == 8)
        #expect(reduced.state.pendingClarification?.continuationQuestion.count == 500)
    }

    private func makePending(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> GraphChatPendingClarification {
        GraphChatPendingClarification(
            id: UUID(),
            decision: .conversationReference,
            options: [
                GraphChatPendingClarificationOption(
                    id: "CI_ONE",
                    title: "Phoenix",
                    proposal: .alias("CI_ONE")
                )
            ],
            sourceTurnID: UUID(),
            graphScope: graphScope,
            chatScope: chatScope,
            continuationOperation: .openReference,
            continuationQuestion: "Öffne den ausgewählten Node.",
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}
