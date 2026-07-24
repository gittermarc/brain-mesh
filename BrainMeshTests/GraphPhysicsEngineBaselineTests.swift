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

            #expect(
                result.metrics.pairCount == theoreticalPairCount,
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
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
                    + "theoreticalPairs=\(theoreticalPairCount) "
                    + "checkedPairs=\(result.metrics.pairCount) "
                    + "springs=\(result.metrics.springCount) "
                    + "simulatedNodes=\(result.metrics.simulatedNodeCount) "
                    + "runtimeNs=\(runtimeNanoseconds)"
            )
        }
    }
}
