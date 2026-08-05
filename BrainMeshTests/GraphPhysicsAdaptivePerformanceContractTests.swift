import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics operation contracts")
struct GraphPhysicsAdaptivePerformanceContractTests {
    private enum SyntheticIndexSourceKind: Int, Hashable, Sendable {
        case node
        case link
        case detailValue
        case media
    }

    private struct SyntheticIndexSource: Hashable, Sendable {
        let ordinal: Int
        let ownerNodeIndex: Int
        let kind: SyntheticIndexSourceKind
    }

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
    func exactAndGridOperationBaselinesRemainStable() {
        for expectation in expectedStrategies {
            let input = GraphPhysicsFixtures.deterministicInput(
                nodeCount: expectation.nodeCount
            )
            let result = GraphPhysicsEngine.step(input: input)
            let metrics = result.metrics

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
    }

    @Test
    @MainActor
    func activeFixturesCommitEveryChangedTick() async {
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

            await runtime.runNextScheduledTickForTesting()
            var debug = await runtime.debugSnapshotForTesting()
            #expect(debug.metrics.lastStepMetrics == directFirst.metrics)
            assertBaseline(
                debug.metrics.lastStepMetrics!,
                expectation: expectation
            )

            for _ in 1..<12 {
                await runtime.runNextScheduledTickForTesting()
            }
            debug = await runtime.debugSnapshotForTesting()

            #expect(debug.metrics.engineTickCount == 12)
            #expect(debug.metrics.positionCommitCount == 12)
            #expect(debug.metrics.velocityCommitCount == 0)
            #expect(debug.metrics.skippedCommitCount == 0)
            #expect(debug.metrics.activeTickCount == 12)
            #expect(debug.metrics.settlingTickCount == 0)
            #expect(debug.metrics.quietTickCount == 0)
            #expect(debug.metrics.workspaceFullResetCount == 1)
            #expect(debug.metrics.workspaceReuseCount == 11)
        }
    }

    @Test
    @MainActor
    func nearlyStableFixturesCoalesceAndSleep() async {
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

            var debug = await runtime.debugSnapshotForTesting()
            while !debug.state.isSleeping,
                  debug.metrics.engineTickCount < 89 {
                await runtime.runNextScheduledTickForTesting()
                debug = await runtime.debugSnapshotForTesting()
            }

            #expect(debug.state.isSleeping)
            #expect(debug.metrics.engineTickCount < 90)
            #expect(
                debug.metrics.positionCommitCount
                    < debug.metrics.engineTickCount
            )
            #expect(debug.metrics.coalescedSnapshotCount > 0)
            #expect(debug.metrics.settlingTickCount > 0)
            #expect(debug.metrics.quietTickCount > 0)
            #expect(debug.metrics.workspaceFullResetCount == 1)
            #expect(
                debug.metrics.workspaceReuseCount
                    == debug.metrics.engineTickCount - 1
            )
            #expect(
                debug.metrics.lastStepMetrics?.interactionStrategy
                    == expectation.strategy
            )
            #expect(
                debug.metrics.lastStepMetrics?
                    .theoreticalExactPairCount
                    == expectation.theoreticalPairs
            )
        }
    }

    @Test
    @MainActor
    func internalTicksMatchPureEngineDespiteFewerSnapshots() async {
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
                await runtime.runNextScheduledTickForTesting()
                directResult = GraphPhysicsEngine.step(
                    input: directInput
                )
                directInput = GraphPhysicsStepInput(
                    nodes: fixture.step.nodes,
                    edges: fixture.step.edges,
                    positions: directResult!.positions,
                    velocities: directResult!.velocities,
                    fixedNodeKeys: fixture.step.fixedNodeKeys,
                    physicsRelevant: fixture.step.physicsRelevant,
                    configuration: fixture.step.configuration
                )
            }
            let debug = await runtime.debugSnapshotForTesting()

            #expect(debug.positions == directResult?.positions)
            #expect(debug.velocities == directResult?.velocities)
            #expect(debug.metrics.lastStepMetrics == directResult?.metrics)
            #expect(
                debug.metrics.positionCommitCount
                    < debug.metrics.engineTickCount
            )
        }
    }

    @Test
    @MainActor
    func fixedAndSpotlightSemanticsRemainEquivalent() async {
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
        let input = GraphPhysicsRuntimeInput(
            graphID: base.runtime.graphID,
            stepInput: step
        )
        let runtime = GraphPhysicsRuntime(
            automaticallySchedules: false
        )
        let harness = GraphPhysicsRuntimeTestHarness(stepInput: step)
        harness.connect(runtime, input: input)

        var directInput = step
        var directResult: GraphPhysicsStepResult?
        for _ in 0..<10 {
            await runtime.runNextScheduledTickForTesting()
            directResult = GraphPhysicsEngine.step(input: directInput)
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
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.positions == directResult?.positions)
        #expect(debug.velocities == directResult?.velocities)
        #expect(
            debug.metrics.lastStepMetrics?.interactionStrategy
                == .spatialGrid
        )
        for key in fixedNodeKeys {
            #expect(debug.positions[key] == step.positions[key])
            #expect(debug.velocities[key] == .zero)
        }
        for node in step.nodes.dropFirst(100) {
            #expect(debug.velocities[node.key] == .zero)
            #expect(debug.positions[node.key] == step.positions[node.key])
        }
    }

    @Test("169 nodes / 433 links / 1,330 sources / 399 media")
    @MainActor
    func realisticSyntheticLoadHasDeterministicBounds() async {
        let reference = syntheticReferenceLoad()
        let runtime = GraphPhysicsRuntime(
            automaticallySchedules: false
        )
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: reference.stepInput
        )
        let input = GraphPhysicsRuntimeInput(
            graphID: UUID(
                uuidString:
                    "00000000-0000-0000-0000-00000000B169"
            )!,
            stepInput: reference.stepInput
        )
        harness.connect(runtime, input: input)

        for _ in 0..<80 {
            await runtime.runNextScheduledTickForTesting()
        }
        let debug = await runtime.debugSnapshotForTesting()
        let metrics = debug.metrics

        #expect(reference.stepInput.nodes.count == 169)
        #expect(reference.stepInput.edges.count == 433)
        #expect(reference.indexSources.count == 1_330)
        #expect(Set(reference.indexSources).count == 1_330)
        #expect(
            reference.indexSources.allSatisfy {
                reference.stepInput.nodes.indices.contains(
                    $0.ownerNodeIndex
                )
            }
        )
        #expect(
            reference.indexSources.lazy.filter {
                $0.kind == .media
            }.count == 399
        )
        #expect(metrics.engineTickCount >= 30)
        #expect(metrics.engineTickCount < 80)
        #expect(metrics.positionCommitCount * 2 < metrics.engineTickCount)
        #expect(metrics.velocityCommitCount == 0)
        #expect(metrics.coalescedSnapshotCount > 0)
        #expect(
            metrics.lastStepMetrics?.interactionStrategy
                == .spatialGrid
        )
        #expect(metrics.lastStepMetrics?.simulatedNodeCount == 169)
        #expect(metrics.lastStepMetrics?.springCount == 433)
        #expect(
            metrics.totalSpringCount
                == metrics.engineTickCount * 433
        )
        #expect(
            metrics.totalExactCheckedNodePairCount
                < metrics.totalTheoreticalExactPairCount
        )
        #expect(
            metrics.maximumSimultaneouslyScheduledTickCount == 1
        )
        #expect(debug.state.isSleeping)
        #expect(!debug.state.hasScheduledTick)
        #expect(debug.indexByNodeKey.count == 169)
        #expect(debug.positions.count == 169)
    }

    private func syntheticReferenceLoad() -> (
        stepInput: GraphPhysicsStepInput,
        indexSources: [SyntheticIndexSource]
    ) {
        let base = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 169,
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0,
                repulsion: 0,
                linkSpring: 0,
                containmentSpring: 0,
                damping: 1
            )
        )
        var edges: [GraphEdge] = []
        var seen = Set<GraphEdge>()
        var offset = 1
        while edges.count < 433 {
            for index in base.nodes.indices {
                let otherIndex = (index + offset) % base.nodes.count
                let edge = GraphEdge(
                    a: base.nodes[index].key,
                    b: base.nodes[otherIndex].key,
                    type: offset.isMultiple(of: 3)
                        ? .containment
                        : .link
                )
                if seen.insert(edge).inserted {
                    edges.append(edge)
                    if edges.count == 433 { break }
                }
            }
            offset += 1
        }

        let velocities = Dictionary(
            uniqueKeysWithValues: base.nodes.map {
                ($0.key, CGVector(dx: 0.01, dy: 0))
            }
        )
        var indexSources: [SyntheticIndexSource] = []
        indexSources.reserveCapacity(1_330)
        func appendSources(
            count: Int,
            kind: SyntheticIndexSourceKind
        ) {
            for _ in 0..<count {
                let ordinal = indexSources.count
                indexSources.append(
                    SyntheticIndexSource(
                        ordinal: ordinal,
                        ownerNodeIndex: ordinal % base.nodes.count,
                        kind: kind
                    )
                )
            }
        }
        appendSources(count: 169, kind: .node)
        appendSources(count: 433, kind: .link)
        appendSources(count: 329, kind: .detailValue)
        appendSources(count: 399, kind: .media)

        return (
            stepInput: GraphPhysicsStepInput(
                nodes: base.nodes,
                edges: edges,
                positions: base.positions,
                velocities: velocities,
                fixedNodeKeys: [],
                physicsRelevant: nil,
                configuration: base.configuration
            ),
            indexSources: indexSources
        )
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
        #expect(metrics.occupiedGridCellCount == expectation.gridCells)
        #expect(
            metrics.neighboringCellPairCount
                == expectation.neighboringCellPairs
        )
        #expect(
            metrics.approximatedDistantCellPairCount
                == expectation.distantCellPairs
        )
    }
}
