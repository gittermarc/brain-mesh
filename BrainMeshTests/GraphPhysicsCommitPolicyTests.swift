import CoreGraphics
import Testing

@testable import BrainMesh

@Suite("Graph physics commit policy")
struct GraphPhysicsCommitPolicyTests {
    private let configuration =
        GraphPhysicsAdaptiveConfiguration.production

    @Test
    func productionCommitBoundaryAndCadenceAreStable() {
        #expect(configuration.visualCommitEpsilon == 0.20)
        #expect(configuration.maximumTicksWithoutCommit == 3)
        #expect(GraphPhysicsCadencePhase.active.framesPerSecond == 30)
        #expect(GraphPhysicsCadencePhase.settling.framesPerSecond == 20)
        #expect(GraphPhysicsCadencePhase.quiet.framesPerSecond == 12)
    }

    @Test
    func activePhaseCommitsEveryChangedTick() {
        #expect(shouldCommit(phase: .active, delta: 0, ticks: 1))
    }

    @Test
    func settlingAndQuietBundleSubEpsilonChanges() {
        #expect(
            !shouldCommit(
                phase: .settling,
                delta: 0.19,
                ticks: 1
            )
        )
        #expect(
            !shouldCommit(
                phase: .quiet,
                delta: 0.19,
                ticks: 2
            )
        )
    }

    @Test
    func epsilonAndMaximumTickCountPublish() {
        #expect(
            shouldCommit(
                phase: .quiet,
                delta: configuration.visualCommitEpsilon,
                ticks: 1
            )
        )
        #expect(
            shouldCommit(
                phase: .settling,
                delta: 0,
                ticks: configuration.maximumTicksWithoutCommit
            )
        )
    }

    @Test
    func forcedReasonsAndDraggingOverrideBundling() {
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
    func deferredTickKeepsExternalPositionSnapshot() async {
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
            await runtime.runNextScheduledTickForTesting()
        }
        let externalBefore = harness.externalPositions
        let internalSnapshotBefore =
            await runtime.debugSnapshotForTesting()
        let internalBefore = internalSnapshotBefore.positions
        await runtime.runNextScheduledTickForTesting()
        let after = await runtime.debugSnapshotForTesting()

        #expect(after.metrics.skippedCommitCount > 0)
        #expect(harness.externalPositions == externalBefore)
        #expect(after.positions != internalBefore)
        #expect(after.positions != harness.externalPositions)
    }

    @Test
    @MainActor
    func stopFlushesPositionsWithoutPublishingInternalState() async {
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
            await runtime.runNextScheduledTickForTesting()
        }

        let before = await runtime.debugSnapshotForTesting()
        runtime.stop()
        let after = await runtime.debugSnapshotForTesting()

        #expect(
            after.metrics.positionCommitCount
                == before.metrics.positionCommitCount + 1
        )
        #expect(after.metrics.velocityCommitCount == 0)
        #expect(harness.externalPositions == after.positions)
        #expect(!after.state.hasScheduledTick)
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
