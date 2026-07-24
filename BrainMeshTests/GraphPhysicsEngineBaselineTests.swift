import Dispatch
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics engine operation baselines")
struct GraphPhysicsEngineBaselineTests {
    @Test
    func deterministicLargeGraphBaselinesCaptureOperationsAndRuntime() {
        for nodeCount in [40, 80, 120, 140] {
            let input = GraphPhysicsFixtures.deterministicInput(
                nodeCount: nodeCount
            )
            let theoreticalPairCount = nodeCount * (nodeCount - 1) / 2
            let expectedSpringCount = max(0, nodeCount - 1)
            let start = DispatchTime.now().uptimeNanoseconds
            let result = GraphPhysicsEngine.step(input: input)
            let runtimeNanoseconds =
                DispatchTime.now().uptimeNanoseconds &- start
            let expectedStrategy: GraphPhysicsInteractionStrategy =
                nodeCount <= 80 ? .exactPairLoop : .spatialGrid

            #expect(
                result.metrics.interactionStrategy == expectedStrategy,
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
            #expect(
                result.metrics.theoreticalExactPairCount
                    == theoreticalPairCount,
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
            if expectedStrategy == .exactPairLoop {
                #expect(
                    result.metrics.exactCheckedNodePairCount
                        == theoreticalPairCount,
                    Comment(rawValue: "nodeCount=\(nodeCount)")
                )
            } else {
                #expect(
                    result.metrics.exactCheckedNodePairCount
                        < theoreticalPairCount,
                    Comment(rawValue: "nodeCount=\(nodeCount)")
                )
                #expect(
                    result.metrics.occupiedGridCellCount > 0,
                    Comment(rawValue: "nodeCount=\(nodeCount)")
                )
                #expect(
                    result.metrics.approximatedDistantCellPairCount > 0,
                    Comment(rawValue: "nodeCount=\(nodeCount)")
                )
            }
            #expect(
                result.metrics.springCount == expectedSpringCount,
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
            #expect(
                result.metrics.simulatedNodeCount == nodeCount,
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
            #expect(
                result.positions.values.allSatisfy {
                    $0.x.isFinite && $0.y.isFinite
                },
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
            #expect(
                result.velocities.values.allSatisfy {
                    $0.dx.isFinite && $0.dy.isFinite
                },
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )

            print(
                "GraphPhysics baseline nodes=\(nodeCount) "
                    + "strategy=\(result.metrics.interactionStrategy.rawValue) "
                    + "theoreticalPairs=\(theoreticalPairCount) "
                    + "exactPairs=\(result.metrics.exactCheckedNodePairCount) "
                    + "gridCells=\(result.metrics.occupiedGridCellCount) "
                    + "neighborCellPairs=\(result.metrics.neighboringCellPairCount) "
                    + "distantCellPairs=\(result.metrics.approximatedDistantCellPairCount) "
                    + "springs=\(result.metrics.springCount) "
                    + "simulatedNodes=\(result.metrics.simulatedNodeCount) "
                    + "runtimeNs=\(runtimeNanoseconds)"
            )
        }
    }
}
