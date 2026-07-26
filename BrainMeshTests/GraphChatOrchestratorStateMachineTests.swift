import Foundation
import Testing

@testable import BrainMesh

struct GraphChatOrchestratorStateMachineTests {
    @Test
    func initialStateIsIdleWithoutTechnicalIdentities() {
        let machine = GraphChatOrchestratorStateMachine()

        #expect(machine.state.lifecycle == .idle)
        #expect(machine.state.scopeKey == nil)
        #expect(machine.state.preparedSessionID == nil)
        #expect(machine.state.artifactSessionID == nil)
        #expect(machine.state.generation == nil)
        #expect(machine.state.activeSessionID == nil)
    }

    @Test
    func prepareTransitionsToPrepared() {
        let fixture = Fixture()
        var machine = GraphChatOrchestratorStateMachine()

        let transition = machine.transition(
            .prepared(
                key: fixture.firstKey,
                sessionID: fixture.preparedSessionID
            )
        )

        #expect(transition.wasApplied)
        #expect(transition.previous.lifecycle == .idle)
        #expect(machine.state.lifecycle == .prepared)
        #expect(machine.state.scopeKey == fixture.firstKey)
        #expect(machine.state.preparedSessionID == fixture.preparedSessionID)
    }

    @Test
    func matchingRequestConsumesPreparedIdentity() {
        let fixture = Fixture()
        var machine = fixture.preparedMachine()
        let generation = fixture.generation()

        _ = machine.transition(
            .requestStarted(
                key: fixture.firstKey,
                generation: generation
            )
        )
        let transition = machine.transition(
            .preparedConsumed(
                requestID: generation.requestID,
                sessionID: fixture.preparedSessionID
            )
        )

        #expect(transition.wasApplied)
        #expect(machine.state.lifecycle == .running)
        #expect(machine.state.preparedSessionID == nil)
        #expect(machine.state.activeSessionID == fixture.preparedSessionID)
        #expect(machine.state.generation == generation)
    }

    @Test
    func nonmatchingRequestDiscardsPreparedIdentityBeforeStarting() {
        let fixture = Fixture()
        var machine = fixture.preparedMachine()
        let generation = fixture.generation()

        let discarded = machine.transition(
            .preparedDiscarded(sessionID: fixture.preparedSessionID)
        )
        let started = machine.transition(
            .requestStarted(
                key: fixture.secondKey,
                generation: generation
            )
        )

        #expect(discarded.wasApplied)
        #expect(started.wasApplied)
        #expect(machine.state.lifecycle == .running)
        #expect(machine.state.scopeKey == fixture.secondKey)
        #expect(machine.state.preparedSessionID == nil)
    }

    @Test
    func requestStartHoldsRequestAndGenerationIdentity() {
        let fixture = Fixture()
        let generation = fixture.generation()
        var machine = GraphChatOrchestratorStateMachine()

        let transition = machine.transition(
            .requestStarted(
                key: fixture.firstKey,
                generation: generation
            )
        )

        #expect(transition.wasApplied)
        #expect(machine.state.lifecycle == .running)
        #expect(machine.activeRequestID == generation.requestID)
        #expect(machine.state.generation?.token == generation.token)
    }

    @Test
    func completionFinishesOnlyTheMatchingRequest() {
        let fixture = Fixture()
        let generation = fixture.generation()
        var machine = fixture.runningMachine(generation: generation)

        let stale = machine.transition(
            .requestFinished(
                requestID: UUID(),
                outcome: .completed
            )
        )
        #expect(stale.wasApplied == false)
        #expect(machine.state.lifecycle == .running)

        let matching = machine.transition(
            .requestFinished(
                requestID: generation.requestID,
                outcome: .completed
            )
        )
        #expect(matching.wasApplied)
        #expect(machine.state.lifecycle == .idle)
        #expect(machine.state.generation == nil)
    }

    @Test
    func failureFinishesOnlyTheMatchingRequest() {
        let fixture = Fixture()
        let generation = fixture.generation()
        var machine = fixture.runningMachine(generation: generation)

        #expect(
            machine.transition(
                .requestFinished(
                    requestID: UUID(),
                    outcome: .failed
                )
            ).wasApplied == false
        )
        #expect(
            machine.transition(
                .requestFinished(
                    requestID: generation.requestID,
                    outcome: .failed
                )
            ).wasApplied
        )
        #expect(machine.state.lifecycle == .idle)
    }

    @Test
    func cancellationFinishesOnlyTheMatchingRequest() {
        let fixture = Fixture()
        let generation = fixture.generation()
        var machine = fixture.runningMachine(generation: generation)

        let cancellation = machine.transition(
            .cancellationRequested(requestID: generation.requestID)
        )
        #expect(cancellation.wasApplied)
        #expect(machine.state.lifecycle == .cancelling)

        #expect(
            machine.transition(
                .requestFinished(
                    requestID: UUID(),
                    outcome: .cancelled
                )
            ).wasApplied == false
        )
        #expect(
            machine.transition(
                .requestFinished(
                    requestID: generation.requestID,
                    outcome: .cancelled
                )
            ).wasApplied
        )
        #expect(machine.state.lifecycle == .idle)
    }

    @Test
    func repeatedCancellationIsIdempotent() {
        let fixture = Fixture()
        let generation = fixture.generation()
        var machine = fixture.runningMachine(generation: generation)

        let first = machine.transition(
            .cancellationRequested(requestID: generation.requestID)
        )
        let firstState = machine.state
        let second = machine.transition(
            .cancellationRequested(requestID: generation.requestID)
        )

        #expect(first.wasApplied)
        #expect(second.wasApplied)
        #expect(machine.state == firstState)
        #expect(
            machine.transition(
                .cancellationRequested(requestID: UUID())
            ).wasApplied == false
        )
    }

    @Test
    func discardClearsPreparedActiveAndArtifactIdentities() {
        let fixture = Fixture()
        let generation = fixture.generation()
        var machine = fixture.preparedMachine()
        _ = machine.transition(
            .artifactSessionInstalled(
                key: fixture.firstKey,
                sessionID: fixture.artifactSessionID
            )
        )
        _ = machine.transition(
            .requestStarted(
                key: fixture.firstKey,
                generation: generation
            )
        )
        _ = machine.transition(
            .preparedConsumed(
                requestID: generation.requestID,
                sessionID: fixture.preparedSessionID
            )
        )

        _ = machine.transition(.discardStarted(reason: .sessionDiscarded))
        _ = machine.transition(
            .requestFinished(
                requestID: generation.requestID,
                outcome: .cancelled
            )
        )
        _ = machine.transition(.resourcesDiscarded)
        _ = machine.transition(.discardFinished)

        #expect(machine.state == .idle)
    }

    @Test
    func restoreRemainsRestoringUntilResourcesAreDiscarded() {
        let fixture = Fixture()
        let generation = fixture.generation()
        var machine = fixture.runningMachine(generation: generation)

        _ = machine.transition(.restoreStarted)
        #expect(machine.state.lifecycle == .restoring)
        _ = machine.transition(
            .cancellationRequested(requestID: generation.requestID)
        )
        _ = machine.transition(
            .requestFinished(
                requestID: generation.requestID,
                outcome: .cancelled
            )
        )
        #expect(machine.state.lifecycle == .restoring)
        _ = machine.transition(.resourcesDiscarded)
        _ = machine.transition(.restoreFinished(key: fixture.firstKey))

        #expect(machine.state.lifecycle == .idle)
        #expect(machine.state.scopeKey == fixture.firstKey)
        #expect(machine.state.generation == nil)
    }

    @Test
    func graphChangeCreatesFreshConversationState() throws {
        let fixture = Fixture()
        var runtime = GraphChatOrchestratorConversationRuntime()
        let reducer = GraphChatConversationStateReducer()
        let first = runtime.stateForTurn(
            key: fixture.firstKey,
            reducer: reducer
        ).state
        try runtime.commit(
            first,
            expectedCommittedState: nil
        )
        let second = runtime.stateForTurn(
            key: fixture.secondKey,
            reducer: reducer
        ).state

        #expect(second.graphScope == fixture.secondKey.graphScope)
        #expect(second.chatScope == fixture.secondKey.chatScope)
        #expect(second.conversationID != first.conversationID)
        #expect(second.lastResetReason == .graphChanged)
        #expect(second.turnContexts.isEmpty)
        #expect(second.resultContexts.isEmpty)
    }

    @Test
    func scopeChangeCreatesCleanScopeBoundConversationState() throws {
        let fixture = Fixture()
        var runtime = GraphChatOrchestratorConversationRuntime()
        let reducer = GraphChatConversationStateReducer()
        let first = runtime.stateForTurn(
            key: fixture.firstKey,
            reducer: reducer
        ).state
        try runtime.commit(
            first,
            expectedCommittedState: nil
        )
        let scopedKey = GraphChatOrchestrationScopeKey(
            graphScope: fixture.firstKey.graphScope,
            chatScope: .entity(
                UUID(
                    uuidString: "92000000-0000-0000-0000-000000000001"
                )!,
                in: fixture.firstKey.graphScope
            )
        )
        let scoped = runtime.stateForTurn(
            key: scopedKey,
            reducer: reducer
        ).state

        #expect(scoped.conversationID == first.conversationID)
        #expect(scoped.chatScope == scopedKey.chatScope)
        #expect(scoped.lastResetReason == .scopeChanged)
        #expect(scoped.turnContexts.isEmpty)
        #expect(scoped.resultContexts.isEmpty)
        #expect(scoped.pendingClarification == nil)
    }

    @Test
    func pendingScopeChangeDoesNotReplaceCommittedStateBeforeCommit() throws {
        let fixture = Fixture()
        var runtime = GraphChatOrchestratorConversationRuntime()
        let reducer = GraphChatConversationStateReducer()
        let committed = runtime.stateForTurn(
            key: fixture.firstKey,
            reducer: reducer
        ).state
        try runtime.commit(
            committed,
            expectedCommittedState: nil
        )

        _ = runtime.stateForTurn(
            key: fixture.secondKey,
            reducer: reducer
        )

        #expect(runtime.snapshot() == committed)
    }

    @Test
    func foreignCheckpointScopeIsRejectedByRuntimeBoundary() {
        let fixture = Fixture()
        var runtime = GraphChatOrchestratorConversationRuntime()
        _ = runtime.stateForTurn(
            key: fixture.firstKey,
            reducer: GraphChatConversationStateReducer()
        )

        #expect(
            runtime.acceptsRestore(
                for: fixture.secondKey,
                lifecycleKey: fixture.firstKey
            ) == false
        )
    }

    @Test
    func artifactClearReasonMapsEveryConversationResetReason() {
        let expected: [
            GraphChatConversationResetReason:
                GraphChatAnswerArtifactRegistryClearReason
        ] = [
            .newConversation: .newConversation,
            .graphChanged: .graphChanged,
            .scopeChanged: .scopeChanged,
            .graphLocked: .graphLocked,
            .accessRevoked: .graphLocked,
            .graphDeleted: .graphDeleted,
            .sessionDiscarded: .sessionDiscarded,
        ]

        #expect(Set(expected.keys) == Set(GraphChatConversationResetReason.allCases))
        for (resetReason, clearReason) in expected {
            #expect(
                GraphChatArtifactClearReasonMapper.reason(
                    for: resetReason
                ) == clearReason
            )
        }
        #expect(
            GraphChatArtifactClearReasonMapper.restoredCheckpoint
                == .restoredCheckpoint
        )
    }

    @Test
    func requestStreamEmitsOneStartOneTerminalAndOneFinish() async {
        let requestID = UUID()
        let pair = GraphChatEventStream.makeStream()
        let controller = GraphChatRequestStreamController(
            requestID: requestID,
            continuation: pair.continuation
        )
        let collector = Task {
            await GraphChatProviderTestSupport.collect(pair.stream)
        }
        let answer = GraphChatAnswer(
            directAnswer: "Completed",
            hasInsufficientEvidence: true
        )

        await controller.start()
        await controller.start()
        await controller.complete(answer)
        await controller.complete(answer)
        await controller.cancel()
        await controller.fail(
            GraphChatError(
                code: .unexpected,
                message: "Must not be emitted"
            )
        )
        await controller.finish()
        await controller.finish()

        let events = await collector.value
        let snapshot = await controller.snapshotForTesting()
        #expect(events.count == 2)
        #expect(events.first == .started(requestID: requestID))
        #expect(events.last == .completed(answer))
        #expect(snapshot.startedCount == 1)
        #expect(snapshot.terminalEventCount == 1)
        #expect(snapshot.finishCount == 1)
    }
}

private extension GraphChatOrchestratorStateMachineTests {
    struct Fixture {
        let firstGraphScope = GraphScope(
            graphID: UUID(
                uuidString: "90000000-0000-0000-0000-000000000001"
            )!
        )
        let secondGraphScope = GraphScope(
            graphID: UUID(
                uuidString: "90000000-0000-0000-0000-000000000002"
            )!
        )
        let preparedSessionID = GraphChatModelSessionID(
            rawValue: UUID(
                uuidString: "90000000-0000-0000-0000-000000000003"
            )!
        )
        let artifactSessionID = GraphChatAnswerArtifactSessionID(
            rawValue: UUID(
                uuidString: "90000000-0000-0000-0000-000000000004"
            )!
        )

        var firstKey: GraphChatOrchestrationScopeKey {
            GraphChatOrchestrationScopeKey(
                graphScope: firstGraphScope,
                chatScope: .entireGraph(firstGraphScope)
            )
        }

        var secondKey: GraphChatOrchestrationScopeKey {
            GraphChatOrchestrationScopeKey(
                graphScope: secondGraphScope,
                chatScope: .entireGraph(secondGraphScope)
            )
        }

        func generation() -> GraphChatGenerationIdentity {
            GraphChatGenerationIdentity(
                requestID: UUID(
                    uuidString: "90000000-0000-0000-0000-000000000005"
                )!,
                token: UUID(
                    uuidString: "90000000-0000-0000-0000-000000000006"
                )!
            )
        }

        func preparedMachine() -> GraphChatOrchestratorStateMachine {
            var machine = GraphChatOrchestratorStateMachine()
            _ = machine.transition(
                .prepared(
                    key: firstKey,
                    sessionID: preparedSessionID
                )
            )
            return machine
        }

        func runningMachine(
            generation: GraphChatGenerationIdentity
        ) -> GraphChatOrchestratorStateMachine {
            var machine = GraphChatOrchestratorStateMachine()
            _ = machine.transition(
                .requestStarted(
                    key: firstKey,
                    generation: generation
                )
            )
            return machine
        }
    }
}
