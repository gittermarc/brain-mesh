//
//  GraphChatConversationCheckpointControllerTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat conversation checkpoint controller")
@MainActor
struct GraphChatConversationCheckpointControllerTests {
    @Test
    func initialStateProvidesAnInitialCheckpoint() {
        let setup = Self.makeController()

        let checkpoint = setup.controller.checkpointBeforeNextTurn()

        #expect(checkpoint.graphScope == setup.graphScope)
        #expect(checkpoint.chatScope == setup.chatScope)
        #expect(checkpoint.state == nil)
        #expect(setup.controller.committedCheckpoint == nil)
    }

    @Test
    func successfulTurnReplacesTheCommittedCheckpoint() {
        let setup = Self.makeController()
        let first = Self.state(
            graphScope: setup.graphScope,
            chatScope: setup.chatScope,
            conversationID: UUID()
        )
        let second = Self.state(
            graphScope: setup.graphScope,
            chatScope: setup.chatScope,
            conversationID: UUID()
        )

        _ = setup.controller.captureCommittedCheckpoint(
            state: first,
            outcome: .completed
        )
        let checkpoint = setup.controller.captureCommittedCheckpoint(
            state: second,
            outcome: .completed
        )

        #expect(checkpoint?.state == second)
        #expect(setup.controller.committedCheckpoint?.state == second)
        #expect(setup.controller.checkpointBeforeNextTurn().state == second)
    }

    @Test
    func failureDoesNotChangeTheCommittedCheckpoint() {
        let setup = Self.makeController()
        let committedState = Self.state(
            graphScope: setup.graphScope,
            chatScope: setup.chatScope,
            conversationID: UUID()
        )
        _ = setup.controller.captureCommittedCheckpoint(
            state: committedState,
            outcome: .completed
        )
        let original = setup.controller.committedCheckpoint
        let replacement = Self.state(
            graphScope: setup.graphScope,
            chatScope: setup.chatScope,
            conversationID: UUID()
        )

        let captured = setup.controller.captureCommittedCheckpoint(
            state: replacement,
            outcome: .failure(
                GraphChatError(
                    code: .unexpected,
                    message: "Failure"
                )
            )
        )

        #expect(captured == nil)
        #expect(setup.controller.committedCheckpoint == original)
    }

    @Test
    func cancellationDoesNotChangeTheCommittedCheckpoint() {
        let setup = Self.makeController()
        let committedState = Self.state(
            graphScope: setup.graphScope,
            chatScope: setup.chatScope,
            conversationID: UUID()
        )
        _ = setup.controller.captureCommittedCheckpoint(
            state: committedState,
            outcome: .completed
        )
        let original = setup.controller.committedCheckpoint

        let captured = setup.controller.captureCommittedCheckpoint(
            state: committedState,
            outcome: .cancelled
        )

        #expect(captured == nil)
        #expect(setup.controller.committedCheckpoint == original)
    }

    @Test
    func latestValidHistoryCheckpointIsRestored() async {
        let setup = Self.makeController()
        let firstState = Self.state(
            graphScope: setup.graphScope,
            chatScope: setup.chatScope,
            conversationID: UUID()
        )
        let latestState = Self.state(
            graphScope: setup.graphScope,
            chatScope: setup.chatScope,
            conversationID: UUID()
        )
        let first = GraphChatConversationCheckpoint.committed(firstState)
        let latest = GraphChatConversationCheckpoint.committed(latestState)
        let messages = [
            GraphChatTranscriptMessage(
                state: .userQuestion("First"),
                conversationCheckpointAfterTurn: first
            ),
            GraphChatTranscriptMessage(
                state: .userQuestion("Latest"),
                conversationCheckpointAfterTurn: latest
            ),
        ]
        var restored: [GraphChatConversationCheckpoint] = []
        var resetCount = 0

        let result = await setup.controller.restoreLatestCommittedCheckpoint(
            from: messages,
            shouldRestoreRuntime: true,
            restore: { checkpoint in
                restored.append(checkpoint)
            },
            controlledReset: {
                resetCount += 1
            }
        )

        #expect(result == .restored(latest))
        #expect(restored == [latest])
        #expect(resetCount == 0)
        #expect(setup.controller.committedCheckpoint == latest)
    }

    @Test
    func foreignGraphCheckpointIsRejected() async {
        let setup = Self.makeController()
        let foreignGraphScope = GraphScope(graphID: UUID())
        let foreignChatScope = GraphChatScope.entireGraph(foreignGraphScope)
        let foreignCheckpoint = GraphChatConversationCheckpoint.committed(
            Self.state(
                graphScope: foreignGraphScope,
                chatScope: foreignChatScope,
                conversationID: UUID()
            )
        )
        var restoreWasCalled = false

        let result = await setup.controller.restoreCheckpointForBranch(
            foreignCheckpoint,
            accessIsValid: { true },
            restore: { _ in
                restoreWasCalled = true
            }
        )

        guard case .rejected = result else {
            Issue.record("Expected the foreign graph checkpoint to be rejected.")
            return
        }
        #expect(restoreWasCalled == false)
        #expect(setup.controller.committedCheckpoint == nil)
    }

    @Test
    func foreignChatScopeCheckpointIsRejected() async {
        let setup = Self.makeController()
        let foreignChatScope = GraphChatScope.entity(
            UUID(),
            in: setup.graphScope
        )
        let foreignCheckpoint = GraphChatConversationCheckpoint.committed(
            Self.state(
                graphScope: setup.graphScope,
                chatScope: foreignChatScope,
                conversationID: UUID()
            )
        )
        var restoreWasCalled = false

        let result = await setup.controller.restoreCheckpointForBranch(
            foreignCheckpoint,
            accessIsValid: { true },
            restore: { _ in
                restoreWasCalled = true
            }
        )

        guard case .rejected = result else {
            Issue.record("Expected the foreign chat scope checkpoint to be rejected.")
            return
        }
        #expect(restoreWasCalled == false)
        #expect(setup.controller.committedCheckpoint == nil)
    }

    @Test
    func missingCheckpointStartsFromInitialState() async {
        let setup = Self.makeController()
        var restoreWasCalled = false
        var resetCount = 0

        let result = await setup.controller.restoreLatestCommittedCheckpoint(
            from: [
                GraphChatTranscriptMessage(
                    state: .userQuestion("No checkpoint")
                )
            ],
            shouldRestoreRuntime: true,
            restore: { _ in
                restoreWasCalled = true
            },
            controlledReset: {
                resetCount += 1
            }
        )

        guard case .startedFromInitial(let checkpoint) = result else {
            Issue.record("Expected an initial checkpoint.")
            return
        }
        #expect(checkpoint.state == nil)
        #expect(checkpoint.graphScope == setup.graphScope)
        #expect(checkpoint.chatScope == setup.chatScope)
        #expect(restoreWasCalled == false)
        #expect(resetCount == 0)
    }

    @Test
    func unrestorableCheckpointRunsTheControlledReset() async {
        let setup = Self.makeController()
        let committed = GraphChatConversationCheckpoint.committed(
            Self.state(
                graphScope: setup.graphScope,
                chatScope: setup.chatScope,
                conversationID: UUID()
            )
        )
        var resetCount = 0

        let result = await setup.controller.restoreLatestCommittedCheckpoint(
            from: [
                GraphChatTranscriptMessage(
                    state: .userQuestion("Stored"),
                    conversationCheckpointAfterTurn: committed
                )
            ],
            shouldRestoreRuntime: true,
            restore: { _ in
                throw GraphChatError(
                    code: .invalidRequest,
                    message: "Unrestorable"
                )
            },
            controlledReset: {
                resetCount += 1
            }
        )

        #expect(result == .controlledReset)
        #expect(resetCount == 1)
        #expect(setup.controller.committedCheckpoint == nil)
    }

    @Test
    func resetRemovesTheInternalCheckpointCompletely() {
        let setup = Self.makeController()
        let state = Self.state(
            graphScope: setup.graphScope,
            chatScope: setup.chatScope,
            conversationID: UUID()
        )
        _ = setup.controller.captureCommittedCheckpoint(
            state: state,
            outcome: .completed
        )

        setup.controller.reset()

        #expect(setup.controller.committedCheckpoint == nil)
        #expect(setup.controller.checkpointBeforeNextTurn().state == nil)
    }

    private static func makeController() -> (
        controller: GraphChatConversationCheckpointController,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        return (
            GraphChatConversationCheckpointController(
                graphScope: graphScope,
                chatScope: chatScope
            ),
            graphScope,
            chatScope
        )
    }

    private static func state(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        conversationID: UUID
    ) -> GraphChatConversationState {
        .initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: conversationID
        )
    }
}
