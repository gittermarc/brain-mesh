import Dispatch
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics performance contracts")
struct GraphPhysicsPerformanceContractTests {
    private struct ExpectedOperations {
        let nodeCount: Int
        let strategy: GraphPhysicsInteractionStrategy
        let theoreticalPairs: Int
        let exactPairs: Int
        let gridCells: Int
        let neighboringCellPairs: Int
        let distantCellPairs: Int
        let springs: Int
    }

    @Test
    func deterministicFixturesHaveStableOperationCounts() {
        let expectations = [
            ExpectedOperations(
                nodeCount: 40,
                strategy: .exactPairLoop,
                theoreticalPairs: 780,
                exactPairs: 780,
                gridCells: 0,
                neighboringCellPairs: 0,
                distantCellPairs: 0,
                springs: 39
            ),
            ExpectedOperations(
                nodeCount: 80,
                strategy: .exactPairLoop,
                theoreticalPairs: 3_160,
                exactPairs: 3_160,
                gridCells: 0,
                neighboringCellPairs: 0,
                distantCellPairs: 0,
                springs: 79
            ),
            ExpectedOperations(
                nodeCount: 120,
                strategy: .spatialGrid,
                theoreticalPairs: 7_140,
                exactPairs: 923,
                gridCells: 59,
                neighboringCellPairs: 191,
                distantCellPairs: 1_520,
                springs: 119
            ),
            ExpectedOperations(
                nodeCount: 140,
                strategy: .spatialGrid,
                theoreticalPairs: 9_730,
                exactPairs: 1_046,
                gridCells: 72,
                neighboringCellPairs: 239,
                distantCellPairs: 2_317,
                springs: 139
            )
        ]

        for expectation in expectations {
            let input = GraphPhysicsFixtures.deterministicInput(
                nodeCount: expectation.nodeCount
            )
            let start = DispatchTime.now().uptimeNanoseconds
            let result = GraphPhysicsEngine.step(input: input)
            let runtimeNanoseconds =
                DispatchTime.now().uptimeNanoseconds &- start
            let metrics = result.metrics

            #expect(
                metrics.interactionStrategy == expectation.strategy,
                comment(expectation, "strategy")
            )
            #expect(
                metrics.theoreticalExactPairCount
                    == expectation.theoreticalPairs,
                comment(expectation, "theoretical pairs")
            )
            #expect(
                metrics.exactCheckedNodePairCount
                    == expectation.exactPairs,
                comment(expectation, "exact pairs")
            )
            #expect(
                metrics.occupiedGridCellCount
                    == expectation.gridCells,
                comment(expectation, "grid cells")
            )
            #expect(
                metrics.neighboringCellPairCount
                    == expectation.neighboringCellPairs,
                comment(expectation, "neighbor cell pairs")
            )
            #expect(
                metrics.approximatedDistantCellPairCount
                    == expectation.distantCellPairs,
                comment(expectation, "distant cell pairs")
            )
            #expect(
                metrics.springCount == expectation.springs,
                comment(expectation, "springs")
            )

            print(
                "GraphPhysics performance "
                    + "nodes=\(expectation.nodeCount) "
                    + "strategy=\(metrics.interactionStrategy.rawValue) "
                    + "theoreticalPairs=\(metrics.theoreticalExactPairCount) "
                    + "exactPairs=\(metrics.exactCheckedNodePairCount) "
                    + "gridCells=\(metrics.occupiedGridCellCount) "
                    + "neighborCellPairs=\(metrics.neighboringCellPairCount) "
                    + "distantCellPairs=\(metrics.approximatedDistantCellPairCount) "
                    + "springs=\(metrics.springCount) "
                    + "runtimeNs=\(runtimeNanoseconds)"
            )
        }
    }

    @Test
    func largeFixturesReduceExactPairChecksByMoreThanSeventyFivePercent() {
        for nodeCount in [120, 140] {
            let result = GraphPhysicsEngine.step(
                input: GraphPhysicsFixtures.deterministicInput(
                    nodeCount: nodeCount
                )
            )
            let metrics = result.metrics

            #expect(metrics.interactionStrategy == .spatialGrid)
            #expect(
                metrics.exactCheckedNodePairCount * 4
                    < metrics.theoreticalExactPairCount,
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
            #expect(metrics.approximatedDistantCellPairCount > 0)
        }
    }

    private func comment(
        _ expectation: ExpectedOperations,
        _ metric: String
    ) -> Comment {
        Comment(
            rawValue: "nodes=\(expectation.nodeCount) metric=\(metric)"
        )
    }
}
