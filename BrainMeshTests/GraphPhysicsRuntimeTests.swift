import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics adaptive runtime")
@MainActor
struct GraphPhysicsRuntimeTests {
    private let configuration =
        GraphPhysicsAdaptiveConfiguration.production

    @Test
    func firstTickBuildsWorkspaceFromExternalBindings() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)

        #expect(runtime.metrics.workspaceFullResetCount == 1)
        #expect(runtime.internalPositions == fixture.step.positions)
        #expect(runtime.internalVelocities == fixture.step.velocities)

        runtime.runNextScheduledTickForTesting()

        #expect(runtime.metrics.engineTickCount == 1)
        #expect(runtime.internalPositions != fixture.step.positions)
    }

    @Test
    func consecutiveTicksReuseOneWorkspace() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 8,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)

        for _ in 0..<5 {
            runtime.runNextScheduledTickForTesting()
        }

        #expect(runtime.metrics.workspaceFullResetCount == 1)
        #expect(runtime.metrics.workspaceReuseCount == 4)
    }

    @Test
    func externalPositionChangeResynchronizesExactlyOnce() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)

        let key = fixture.step.nodes[0].key
        harness.externalState = GraphPhysicsExternalState(
            positions: replacingPosition(
                harness.externalState.positions,
                key: key,
                position: CGPoint(x: 900, y: -700)
            ),
            velocities: harness.externalState.velocities
        )
        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .externalState
        )

        #expect(
            runtime.metrics.externalResynchronizationCount == 1
        )
        #expect(
            runtime.internalPositions[key]
                == CGPoint(x: 900, y: -700)
        )
        #expect(runtime.state.cadencePhase == .active)
        #expect(runtime.state.hasScheduledTick)
        #expect(runtime.metrics.forcedCommitCount == 1)

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .externalState
        )
        #expect(
            runtime.metrics.externalResynchronizationCount == 1
        )
    }

    @Test
    func externalVelocityChangeResynchronizesExactlyOnce() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)

        let key = fixture.step.nodes[0].key
        var velocities = harness.externalState.velocities
        velocities[key] = CGVector(dx: 7, dy: -4)
        harness.externalState = GraphPhysicsExternalState(
            positions: harness.externalState.positions,
            velocities: velocities
        )
        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .externalState
        )

        #expect(
            runtime.metrics.externalResynchronizationCount == 1
        )
        #expect(
            runtime.internalVelocities[key]
                == CGVector(dx: 7, dy: -4)
        )
    }

    @Test
    func ownCommitDoesNotCauseResynchronization() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)
        runtime.runNextScheduledTickForTesting()

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .externalState
        )

        #expect(
            runtime.metrics.externalResynchronizationCount == 0
        )
        #expect(runtime.metrics.workspaceFullResetCount == 1)
    }

    @Test
    func graphLoadAndLayoutResetReplaceInternalState() {
        let first = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let second = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 6,
            speed: 0.02
        )
        let runtime = makeRuntime()
        let harness = makeHarness(first.step)
        harness.connect(runtime, input: first.runtime)
        runtime.runNextScheduledTickForTesting()

        harness.externalState = GraphPhysicsExternalState(
            positions: second.step.positions,
            velocities: second.step.velocities
        )
        harness.connect(
            runtime,
            input: second.runtime,
            reason: .nodeSet
        )

        #expect(runtime.internalPositions == second.step.positions)
        #expect(runtime.internalVelocities == second.step.velocities)
        #expect(runtime.metrics.workspaceFullResetCount == 2)

        let resetKey = second.step.nodes[0].key
        let resetPositions = replacingPosition(
            second.step.positions,
            key: resetKey,
            position: CGPoint(x: -1_000, y: 500)
        )
        var resetVelocities = second.step.velocities
        resetVelocities[resetKey] = .zero
        harness.externalState = GraphPhysicsExternalState(
            positions: resetPositions,
            velocities: resetVelocities
        )
        harness.connect(
            runtime,
            input: second.runtime,
            reason: .externalState
        )

        #expect(runtime.internalPositions == resetPositions)
        #expect(runtime.internalVelocities == resetVelocities)
    }

    @Test
    func graphSwitchDiscardsPreviousWorkspaceAndReturnsToActive() {
        let first = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let secondGraphID = UUID(
            uuidString:
                "00000000-0000-0000-0000-00000000A099"
        )!
        let second = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 5,
            speed: 0.02,
            graphID: secondGraphID
        )
        let runtime = makeRuntime()
        let harness = makeHarness(first.step)
        harness.connect(runtime, input: first.runtime)
        let staleToken = runtime.scheduledTokenForTesting!

        harness.externalState = GraphPhysicsExternalState(
            positions: second.step.positions,
            velocities: second.step.velocities
        )
        harness.connect(
            runtime,
            input: second.runtime,
            reason: .graphChanged
        )

        #expect(runtime.state.identity == second.runtime.identity)
        #expect(runtime.state.cadencePhase == .active)
        #expect(runtime.internalPositions == second.step.positions)
        #expect(runtime.metrics.workspaceFullResetCount == 2)

        runtime.fireScheduledCallbackForTesting(staleToken)
        #expect(runtime.metrics.engineTickCount == 0)
    }

    @Test
    func draggingPinningSpotlightAndEdgesAreAppliedBeforeNextTick() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 6,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)

        let fixedKey = fixture.step.nodes[0].key
        let relevant = Set(
            fixture.step.nodes.prefix(3).map(\.key)
        )
        let updated = GraphPhysicsRuntimeInput(
            graphID: fixture.runtime.graphID,
            nodes: fixture.runtime.nodes,
            edges: [],
            fixedNodeKeys: [fixedKey],
            physicsRelevant: relevant,
            configuration: fixture.runtime.configuration,
            workMode: .organize,
            selection: fixedKey,
            isDragging: true
        )
        let fixedPosition = harness.externalState.positions[fixedKey]
        harness.connect(
            runtime,
            input: updated,
            reason: .draggingStarted
        )
        runtime.runNextScheduledTickForTesting()

        #expect(runtime.internalPositions[fixedKey] == fixedPosition)
        #expect(runtime.internalVelocities[fixedKey] == .zero)
        #expect(runtime.metrics.lastStepMetrics?.springCount == 0)
        #expect(
            runtime.metrics.lastStepMetrics?.simulatedNodeCount == 3
        )
        for node in fixture.step.nodes.dropFirst(3) {
            #expect(runtime.internalVelocities[node.key] == .zero)
        }
    }

    @Test
    func collisionStrengthChangeIsUsedOnNextTick() {
        let first = GraphPhysicsFixtures.node(
            7_000,
            kind: .entity
        )
        let second = GraphPhysicsFixtures.node(
            7_001,
            kind: .entity
        )
        let positions: [NodeKey: CGPoint] = [
            first.key: .zero,
            second.key: CGPoint(x: 40, y: 0)
        ]
        let zeroConfiguration = GraphPhysicsConfiguration(
            collisionStrength: 0,
            repulsion: 0,
            linkSpring: 0,
            containmentSpring: 0,
            damping: 1
        )
        let step = GraphPhysicsStepInput(
            nodes: [first, second],
            edges: [],
            positions: positions,
            velocities: [:],
            fixedNodeKeys: [],
            physicsRelevant: nil,
            configuration: zeroConfiguration
        )
        let graphID = UUID(
            uuidString:
                "00000000-0000-0000-0000-00000000A010"
        )!
        let runtime = makeRuntime()
        let harness = makeHarness(step)
        var input = GraphPhysicsRuntimeInput(
            graphID: graphID,
            stepInput: step
        )
        harness.connect(runtime, input: input)

        input = GraphPhysicsRuntimeTestInputs.replacing(
            input,
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0.09,
                repulsion: 0,
                linkSpring: 0,
                containmentSpring: 0,
                damping: 1
            )
        )
        harness.connect(
            runtime,
            input: input,
            reason: .collisionStrength
        )
        runtime.runNextScheduledTickForTesting()

        #expect(
            runtime.internalVelocities[first.key, default: .zero]
                .dx < 0
        )
        #expect(
            runtime.internalVelocities[second.key, default: .zero]
                .dx > 0
        )
    }

    @Test
    func staleCallbackCannotOverwriteRestartedRuntime() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)
        let staleToken = runtime.scheduledTokenForTesting!

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .selection
        )
        let currentToken = runtime.scheduledTokenForTesting!

        #expect(staleToken != currentToken)
        runtime.fireScheduledCallbackForTesting(staleToken)
        #expect(runtime.metrics.engineTickCount == 0)

        runtime.fireScheduledCallbackForTesting(currentToken)
        #expect(runtime.metrics.engineTickCount == 1)
        #expect(
            runtime.metrics
                .maximumSimultaneouslyScheduledTickCount == 1
        )
    }

    @Test
    func disablingSimulationCancelsSchedulingBeforeAnyEngineTick() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)
        let staleToken = runtime.scheduledTokenForTesting!

        harness.connect(
            runtime,
            input: fixture.runtime,
            simulationAllowed: false,
            reason: .simulationAllowed
        )
        runtime.fireScheduledCallbackForTesting(staleToken)

        #expect(runtime.metrics.engineTickCount == 0)
        #expect(!runtime.state.hasScheduledTick)
        #expect(!runtime.state.isRunning)
    }

    @Test
    func oneSlowTickDoesNotSleepAndInstabilityResetsCounter() {
        var policy = GraphPhysicsStabilityPolicy()
        let oneSlowTick = policy.observe(
            cadencePhase: .quiet,
            maxSimSpeed: 0.01,
            maximumUnpublishedPositionDelta: 0.01,
            isDragging: false,
            simulationAllowed: true,
            externalInputChangePending: false,
            configuration: configuration
        )

        #expect(!oneSlowTick)
        #expect(policy.stableQuietSamples == 1)

        _ = policy.observe(
            cadencePhase: .quiet,
            maxSimSpeed: 0.04,
            maximumUnpublishedPositionDelta: 0.01,
            isDragging: false,
            simulationAllowed: true,
            externalInputChangePending: false,
            configuration: configuration
        )
        #expect(policy.stableQuietSamples == 0)
    }

    @Test
    func draggingAndUnpublishedRelevantMovementPreventSleep() {
        var draggingPolicy = GraphPhysicsStabilityPolicy()
        for _ in 0..<configuration.stableQuietSamplesRequired {
            let shouldSleep = draggingPolicy.observe(
                cadencePhase: .quiet,
                maxSimSpeed: 0,
                maximumUnpublishedPositionDelta: 0,
                isDragging: true,
                simulationAllowed: true,
                externalInputChangePending: false,
                configuration: configuration
            )
            #expect(!shouldSleep)
        }

        var movementPolicy = GraphPhysicsStabilityPolicy()
        for _ in 0..<configuration.stableQuietSamplesRequired {
            let shouldSleep = movementPolicy.observe(
                cadencePhase: .quiet,
                maxSimSpeed: 0,
                maximumUnpublishedPositionDelta:
                    configuration.visualCommitEpsilon,
                isDragging: false,
                simulationAllowed: true,
                externalInputChangePending: false,
                configuration: configuration
            )
            #expect(!shouldSleep)
        }
    }

    @Test
    func stableQuietPathSleepsBeforeNinetyTicksAndFlushes() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 8,
            speed: 0.01
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)

        while !runtime.state.isSleeping,
              runtime.metrics.engineTickCount < 89 {
            runtime.runNextScheduledTickForTesting()
        }

        #expect(runtime.state.isSleeping)
        #expect(runtime.metrics.sleepCount == 1)
        #expect(runtime.metrics.engineTickCount < 90)
        #expect(runtime.metrics.activeTickCount > 0)
        #expect(runtime.metrics.settlingTickCount > 0)
        #expect(runtime.metrics.quietTickCount > 0)
        #expect(
            runtime.metrics.positionCommitCount
                < runtime.metrics.engineTickCount
        )
        #expect(runtime.metrics.forcedCommitCount == 1)
        #expect(
            harness.externalState.positions
                == runtime.internalPositions
        )
        #expect(
            harness.externalState.velocities
                == runtime.internalVelocities
        )
    }

    @Test
    func sleepNeverOccursAboveFormerIdleThreshold() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.031
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)

        for _ in 0..<80 {
            runtime.runNextScheduledTickForTesting()
        }

        #expect(!runtime.state.isSleeping)
        #expect(runtime.metrics.sleepCount == 0)
    }

    @Test
    func wakeAfterSleepReturnsImmediatelyToActiveWithOneTimer() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(runtime, input: fixture.runtime)
        while !runtime.state.isSleeping {
            runtime.runNextScheduledTickForTesting()
        }
        let wakeCountBefore = runtime.metrics.wakeCount

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .selection
        )

        #expect(runtime.state.cadencePhase == .active)
        #expect(runtime.state.hasScheduledTick)
        #expect(!runtime.state.isSleeping)
        #expect(runtime.metrics.wakeCount == wakeCountBefore + 1)
        #expect(
            runtime.metrics
                .maximumSimultaneouslyScheduledTickCount == 1
        )
    }

    @Test
    func dragEndForcesCommitAndRestoresActiveCadence() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let dragging = GraphPhysicsRuntimeTestInputs.replacing(
            fixture.runtime,
            fixedNodeKeys: [fixture.step.nodes[0].key],
            workMode: .organize,
            isDragging: true
        )
        let runtime = makeRuntime()
        let harness = makeHarness(fixture.step)
        harness.connect(
            runtime,
            input: dragging,
            reason: .draggingStarted
        )
        runtime.runNextScheduledTickForTesting()
        let commitsBeforeEnd =
            runtime.metrics.positionCommitCount

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .draggingEnded
        )

        #expect(
            runtime.metrics.positionCommitCount
                == commitsBeforeEnd + 1
        )
        #expect(runtime.metrics.forcedCommitCount == 1)
        #expect(runtime.state.cadencePhase == .active)
    }

    private func makeRuntime() -> GraphPhysicsRuntime {
        GraphPhysicsRuntime(automaticallySchedules: false)
    }

    private func makeHarness(
        _ input: GraphPhysicsStepInput
    ) -> GraphPhysicsRuntimeTestHarness {
        GraphPhysicsRuntimeTestHarness(stepInput: input)
    }

    private func replacingPosition(
        _ positions: [NodeKey: CGPoint],
        key: NodeKey,
        position: CGPoint
    ) -> [NodeKey: CGPoint] {
        var updated = positions
        updated[key] = position
        return updated
    }
}
