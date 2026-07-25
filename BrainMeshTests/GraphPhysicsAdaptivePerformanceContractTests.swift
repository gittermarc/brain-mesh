import Foundation
import Testing

@testable import BrainMesh
import CoreGraphics

@Suite("Graph physics adaptive performance contracts")
@MainActor
struct GraphPhysicsAdaptivePerformanceContractTests {
    private struct ExpectedStrategy {
        let nodeCount: Int
        let strategy: GraphPhysicsInteractionStrategy
        let theoreticalPairs: Int
        let exactPairs: Int
        let gridCells: Int
        let neighboringCellPairs: Int
        let distantCellPairs: Int
    }

    private let expectedStrategies = [
        ExpectedStrategy(
            nodeCount: 40,
            strategy: .exactPairLoop,
            theoreticalPairs: 780,
            exactPairs: 780,
            gridCells: 0,
            neighboringCellPairs: 0,
            distantCellPairs: 0
        ),
        ExpectedStrategy(
            nodeCount: 80,
            strategy: .exactPairLoop,
            theoreticalPairs: 3_160,
            exactPairs: 3_160,
            gridCells: 0,
            neighboringCellPairs: 0,
            distantCellPairs: 0
        ),
        ExpectedStrategy(
            nodeCount: 120,
            strategy: .spatialGrid,
            theoreticalPairs: 7_140,
            exactPairs: 923,
            gridCells: 59,
            neighboringCellPairs: 191,
            distantCellPairs: 1_520
        ),
        ExpectedStrategy(
            nodeCount: 140,
            strategy: .spatialGrid,
            theoreticalPairs: 9_730,
            exactPairs: 1_046,
            gridCells: 72,
            neighboringCellPairs: 239,
            distantCellPairs: 2_317
        )
    ]

    @Test
    func activeFixturesStayResponsiveAndCommitEveryTick() {
        for expectation in expectedStrategies {
            let fixture = GraphPhysicsRuntimeTestInputs.controlled(
                nodeCount: expectation.nodeCount,
                speed: 1
            )
            let directFirst = GraphPhysicsEngine.step(
                input: fixture.step
            )
            let runtime = GraphPhysicsRuntime(
                automaticallySchedules: false
            )
            let harness = GraphPhysicsRuntimeTestHarness(
                stepInput: fixture.step
            )
            harness.connect(runtime, input: fixture.runtime)
            runtime.runNextScheduledTickForTesting()

            #expect(
                runtime.metrics.lastStepMetrics
                    == directFirst.metrics
            )
            assertBaseline(
                runtime.metrics.lastStepMetrics!,
                expectation: expectation
            )

            for _ in 1..<12 {
                runtime.runNextScheduledTickForTesting()
            }

            #expect(runtime.metrics.engineTickCount == 12)
            #expect(runtime.metrics.positionCommitCount == 12)
            #expect(runtime.metrics.velocityCommitCount == 12)
            #expect(runtime.metrics.skippedCommitCount == 0)
            #expect(runtime.metrics.activeTickCount == 12)
            #expect(runtime.metrics.settlingTickCount == 0)
            #expect(runtime.metrics.quietTickCount == 0)
            #expect(runtime.metrics.workspaceFullResetCount == 1)
            #expect(runtime.metrics.workspaceReuseCount == 11)

            printMetrics(
                label: "active",
                nodeCount: expectation.nodeCount,
                metrics: runtime.metrics
            )
        }
    }

    @Test
    func nearlyStableFixturesBundleCommitsUseAdaptiveCadenceAndSleep() {
        for expectation in expectedStrategies {
            let fixture = GraphPhysicsRuntimeTestInputs.controlled(
                nodeCount: expectation.nodeCount,
                speed: 0.01
            )
            let runtime = GraphPhysicsRuntime(
                automaticallySchedules: false
            )
            let harness = GraphPhysicsRuntimeTestHarness(
                stepInput: fixture.step
            )
            harness.connect(runtime, input: fixture.runtime)

            while !runtime.state.isSleeping,
                  runtime.metrics.engineTickCount < 89 {
                runtime.runNextScheduledTickForTesting()
            }

            #expect(runtime.state.isSleeping)
            #expect(runtime.metrics.engineTickCount < 90)
            #expect(
                runtime.metrics.positionCommitCount
                    < runtime.metrics.engineTickCount
            )
            #expect(runtime.metrics.skippedCommitCount > 0)
            #expect(runtime.metrics.settlingTickCount > 0)
            #expect(runtime.metrics.quietTickCount > 0)
            #expect(runtime.metrics.workspaceFullResetCount == 1)
            #expect(
                runtime.metrics.workspaceReuseCount
                    == runtime.metrics.engineTickCount - 1
            )
            #expect(
                runtime.metrics.lastStepMetrics?
                    .interactionStrategy
                    == expectation.strategy
            )
            #expect(
                runtime.metrics.lastStepMetrics?
                    .theoreticalExactPairCount
                    == expectation.theoreticalPairs
            )

            printMetrics(
                label: "stable",
                nodeCount: expectation.nodeCount,
                metrics: runtime.metrics
            )
        }
    }

    @Test
    func runtimeInternalTicksMatchDirectEngineTicksDespiteFewerCommits() {
        for nodeCount in [40, 120] {
            let fixture = GraphPhysicsRuntimeTestInputs.controlled(
                nodeCount: nodeCount,
                speed: 0.01
            )
            let runtime = GraphPhysicsRuntime(
                automaticallySchedules: false
            )
            let harness = GraphPhysicsRuntimeTestHarness(
                stepInput: fixture.step
            )
            harness.connect(runtime, input: fixture.runtime)

            var directInput = fixture.step
            var directResult: GraphPhysicsStepResult?
            for _ in 0..<20 {
                runtime.runNextScheduledTickForTesting()
                directResult = GraphPhysicsEngine.step(
                    input: directInput
                )
                directInput = GraphPhysicsStepInput(
                    nodes: fixture.step.nodes,
                    edges: fixture.step.edges,
                    positions: directResult!.positions,
                    velocities: directResult!.velocities,
                    fixedNodeKeys: fixture.step.fixedNodeKeys,
                    physicsRelevant:
                        fixture.step.physicsRelevant,
                    configuration: fixture.step.configuration
                )
            }

            #expect(
                runtime.internalPositions
                    == directResult?.positions
            )
            #expect(
                runtime.internalVelocities
                    == directResult?.velocities
            )
            #expect(
                runtime.metrics.lastStepMetrics
                    == directResult?.metrics
            )
            #expect(
                runtime.metrics.positionCommitCount
                    < runtime.metrics.engineTickCount
            )
        }
    }

    @Test
    func parityPreservesFixedAndSpotlightSemantics() {
        let base = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 120,
            speed: 0.01
        )
        let fixedNodeKeys = Set(
            base.step.nodes.prefix(2).map(\.key)
        )
        let relevant = Set(
            base.step.nodes.prefix(100).map(\.key)
        )
        let step = GraphPhysicsStepInput(
            nodes: base.step.nodes,
            edges: base.step.edges,
            positions: base.step.positions,
            velocities: base.step.velocities,
            fixedNodeKeys: fixedNodeKeys,
            physicsRelevant: relevant,
            configuration: base.step.configuration
        )
        let runtimeInput = GraphPhysicsRuntimeInput(
            graphID: base.runtime.graphID,
            stepInput: step
        )
        let runtime = GraphPhysicsRuntime(
            automaticallySchedules: false
        )
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: step
        )
        harness.connect(runtime, input: runtimeInput)

        var directInput = step
        var directResult: GraphPhysicsStepResult?
        for _ in 0..<10 {
            runtime.runNextScheduledTickForTesting()
            directResult = GraphPhysicsEngine.step(
                input: directInput
            )
            directInput = GraphPhysicsStepInput(
                nodes: step.nodes,
                edges: step.edges,
                positions: directResult!.positions,
                velocities: directResult!.velocities,
                fixedNodeKeys: fixedNodeKeys,
                physicsRelevant: relevant,
                configuration: step.configuration
            )
        }

        #expect(runtime.internalPositions == directResult?.positions)
        #expect(runtime.internalVelocities == directResult?.velocities)
        #expect(
            runtime.metrics.lastStepMetrics?
                .interactionStrategy == .spatialGrid
        )
        for key in fixedNodeKeys {
            #expect(
                runtime.internalPositions[key]
                    == step.positions[key]
            )
            #expect(runtime.internalVelocities[key] == .zero)
        }
        for node in step.nodes.dropFirst(100) {
            #expect(runtime.internalVelocities[node.key] == .zero)
            #expect(
                runtime.internalPositions[node.key]
                    == step.positions[node.key]
            )
        }
    }

    private func assertBaseline(
        _ metrics: GraphPhysicsStepMetrics,
        expectation: ExpectedStrategy
    ) {
        #expect(metrics.interactionStrategy == expectation.strategy)
        #expect(
            metrics.theoreticalExactPairCount
                == expectation.theoreticalPairs
        )
        #expect(
            metrics.exactCheckedNodePairCount
                == expectation.exactPairs
        )
        #expect(
            metrics.occupiedGridCellCount
                == expectation.gridCells
        )
        #expect(
            metrics.neighboringCellPairCount
                == expectation.neighboringCellPairs
        )
        #expect(
            metrics.approximatedDistantCellPairCount
                == expectation.distantCellPairs
        )
    }

    private func printMetrics(
        label: String,
        nodeCount: Int,
        metrics: GraphPhysicsRuntimeMetrics
    ) {
        let step = metrics.lastStepMetrics
        print(
            "GraphPhysics adaptive "
                + "scenario=\(label) "
                + "nodes=\(nodeCount) "
                + "engineTicks=\(metrics.engineTickCount) "
                + "positionCommits=\(metrics.positionCommitCount) "
                + "velocityCommits=\(metrics.velocityCommitCount) "
                + "skipped=\(metrics.skippedCommitCount) "
                + "active=\(metrics.activeTickCount) "
                + "settling=\(metrics.settlingTickCount) "
                + "quiet=\(metrics.quietTickCount) "
                + "sleepTick=\(metrics.lastSleepEngineTick ?? 0) "
                + "workspaceResets=\(metrics.workspaceFullResetCount) "
                + "workspaceReuse=\(metrics.workspaceReuseCount) "
                + "strategy=\(step?.interactionStrategy.rawValue ?? "-") "
                + "theoreticalPairs=\(step?.theoreticalExactPairCount ?? 0) "
                + "exactPairs=\(step?.exactCheckedNodePairCount ?? 0) "
                + "gridCells=\(step?.occupiedGridCellCount ?? 0) "
                + "neighborCellPairs=\(step?.neighboringCellPairCount ?? 0) "
                + "distantCellPairs=\(step?.approximatedDistantCellPairCount ?? 0)"
        )
    }
}
