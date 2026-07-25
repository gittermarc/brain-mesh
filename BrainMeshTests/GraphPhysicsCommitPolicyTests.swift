import CoreGraphics
import Testing

@testable import BrainMesh

@Suite("Graph physics commit policy")
struct GraphPhysicsCommitPolicyTests {
    private let configuration =
        GraphPhysicsAdaptiveConfiguration.production

    @Test
    func productionCommitBoundaryIsStable() {
        #expect(configuration.visualCommitEpsilon == 0.20)
        #expect(configuration.maximumTicksWithoutCommit == 3)
    }

    @Test
    func activePhaseCommitsEveryTick() {
        #expect(
            shouldCommit(
                phase: .active,
                delta: 0,
                ticks: 1
            )
        )
    }

    @Test
    func settlingPhaseBundlesSubEpsilonChanges() {
        #expect(
            !shouldCommit(
                phase: .settling,
                delta: 0.19,
                ticks: 1
            )
        )
    }

    @Test
    func quietPhaseBundlesSubEpsilonChanges() {
        #expect(
            !shouldCommit(
                phase: .quiet,
                delta: 0.19,
                ticks: 2
            )
        )
    }

    @Test
    func exceedingPositionEpsilonCommits() {
        #expect(
            shouldCommit(
                phase: .quiet,
                delta: configuration.visualCommitEpsilon,
                ticks: 1
            )
        )
    }

    @Test
    func maximumTickCountCommits() {
        #expect(
            shouldCommit(
                phase: .settling,
                delta: 0,
                ticks:
                    configuration.maximumTicksWithoutCommit
            )
        )
    }

    @Test
    func forcedReasonsOverrideBundling() {
        for reason in [
            GraphPhysicsForcedCommitReason.stop,
            .sleep,
            .externalInputChange,
            .graphChange,
            .dragEnd,
            .beforeDiscard
        ] {
            #expect(
                shouldCommit(
                    phase: .quiet,
                    delta: 0,
                    ticks: 0,
                    forcedReason: reason
                ),
                Comment(rawValue: reason.rawValue)
            )
        }
    }

    @Test
    func draggingAlwaysCommits() {
        #expect(
            shouldCommit(
                phase: .quiet,
                delta: 0,
                ticks: 1,
                isDragging: true
            )
        )
    }

    @Test
    @MainActor
    func skippedCommitKeepsExternalStateWhileInternalStateAdvances() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let runtime = GraphPhysicsRuntime(
            automaticallySchedules: false
        )
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)

        for _ in 0..<6 {
            runtime.runNextScheduledTickForTesting()
        }

        let externalBeforeSkippedTick = harness.externalState
        let internalBeforeSkippedTick =
            runtime.internalPositions
        runtime.runNextScheduledTickForTesting()

        #expect(runtime.metrics.skippedCommitCount == 1)
        #expect(harness.externalState == externalBeforeSkippedTick)
        #expect(
            runtime.internalPositions
                != internalBeforeSkippedTick
        )
        #expect(
            runtime.internalPositions
                != harness.externalState.positions
        )
    }

    @Test
    @MainActor
    func positionsAndVelocitiesCommitTogether() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = GraphPhysicsRuntime(
            automaticallySchedules: false
        )
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        runtime.runNextScheduledTickForTesting()

        #expect(runtime.metrics.positionCommitCount == 1)
        #expect(runtime.metrics.velocityCommitCount == 1)
        #expect(harness.committedStates.count == 1)
        #expect(
            harness.committedStates[0].positions
                == runtime.internalPositions
        )
        #expect(
            harness.committedStates[0].velocities
                == runtime.internalVelocities
        )
    }

    @Test
    @MainActor
    func stopFlushesADeferredCommit() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let runtime = GraphPhysicsRuntime(
            automaticallySchedules: false
        )
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        for _ in 0..<7 {
            runtime.runNextScheduledTickForTesting()
        }

        let commitsBeforeStop =
            runtime.metrics.positionCommitCount
        runtime.stop()

        #expect(
            runtime.metrics.positionCommitCount
                == commitsBeforeStop + 1
        )
        #expect(runtime.metrics.forcedCommitCount == 1)
        #expect(
            harness.externalState.positions
                == runtime.internalPositions
        )
    }

    private func shouldCommit(
        phase: GraphPhysicsCadencePhase,
        delta: CGFloat,
        speed: CGFloat = 0,
        ticks: Int,
        forcedReason: GraphPhysicsForcedCommitReason? = nil,
        isDragging: Bool = false
    ) -> Bool {
        GraphPhysicsCommitPolicy.shouldCommit(
            GraphPhysicsCommitPolicyInput(
                cadencePhase: phase,
                maximumCumulativePositionDelta: delta,
                maxSimSpeed: speed,
                ticksSinceLastCommit: ticks,
                forcedReason: forcedReason,
                isDragging: isDragging
            ),
            configuration: configuration
        )
    }
}
