import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics interaction strategy selection")
struct GraphPhysicsStrategySelectionTests {
    @Test
    func productionThresholdUsesExactThroughEightyAndGridFromEightyOne() {
        let expectations:
            [(nodeCount: Int, strategy: GraphPhysicsInteractionStrategy)] = [
                (0, .exactPairLoop),
                (1, .exactPairLoop),
                (40, .exactPairLoop),
                (80, .exactPairLoop),
                (81, .spatialGrid),
                (120, .spatialGrid),
                (140, .spatialGrid)
            ]

        for expectation in expectations {
            let result = GraphPhysicsEngine.step(
                input: GraphPhysicsFixtures.deterministicInput(
                    nodeCount: expectation.nodeCount
                )
            )

            #expect(
                result.metrics.interactionStrategy
                    == expectation.strategy,
                Comment(
                    rawValue: "nodeCount=\(expectation.nodeCount)"
                )
            )
            #expect(
                result.metrics.simulatedNodeCount
                    == expectation.nodeCount,
                Comment(
                    rawValue: "nodeCount=\(expectation.nodeCount)"
                )
            )
        }
    }

    @Test
    func spotlightSelectionUsesFilteredSimulatedNodeCount() {
        let base = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 140
        )
        let relevant = Set(base.nodes.prefix(40).map(\.key))
        let input = replacing(
            base,
            physicsRelevant: relevant
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.metrics.simulatedNodeCount == 40)
        #expect(result.metrics.interactionStrategy == .exactPairLoop)
        #expect(result.metrics.theoreticalExactPairCount == 780)
        #expect(result.metrics.exactCheckedNodePairCount == 780)
        #expect(result.metrics.occupiedGridCellCount == 0)
        for node in base.nodes.dropFirst(40) {
            #expect(result.velocities[node.key] == CGVector.zero)
            #expect(result.positions[node.key] == base.positions[node.key])
        }
    }

    @Test
    func diagnosticOverrideCanCompareBothStrategiesWithSameInput() {
        let base = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 120
        )
        let exact = GraphPhysicsEngine.step(
            input: replacing(
                base,
                diagnosticOverride: .exactPairLoop
            )
        )
        let grid = GraphPhysicsEngine.step(
            input: replacing(
                base,
                diagnosticOverride: .spatialGrid
            )
        )

        #expect(exact.metrics.interactionStrategy == .exactPairLoop)
        #expect(grid.metrics.interactionStrategy == .spatialGrid)
        #expect(exact.metrics.simulatedNodeCount == 120)
        #expect(grid.metrics.simulatedNodeCount == 120)
        #expect(exact.metrics.theoreticalExactPairCount == 7_140)
        #expect(grid.metrics.theoreticalExactPairCount == 7_140)
        #expect(exact.metrics.exactCheckedNodePairCount == 7_140)
        #expect(grid.metrics.exactCheckedNodePairCount < 7_140)
    }

    @Test
    func automaticPathIsExactlyIdenticalToPr12ThroughEightyNodes() {
        for nodeCount in [0, 1, 40, 80] {
            let input = GraphPhysicsFixtures.deterministicInput(
                nodeCount: nodeCount
            )
            let automatic = GraphPhysicsEngine.step(input: input)
            let exactOverride = GraphPhysicsEngine.step(
                input: replacing(
                    input,
                    diagnosticOverride: .exactPairLoop
                )
            )
            let legacy = LegacyGraphPhysicsReference.step(input: input)

            #expect(
                automatic == exactOverride,
                Comment(rawValue: "override nodeCount=\(nodeCount)")
            )
            #expect(
                automatic.positions == legacy.positions,
                Comment(rawValue: "positions nodeCount=\(nodeCount)")
            )
            #expect(
                automatic.velocities == legacy.velocities,
                Comment(rawValue: "velocities nodeCount=\(nodeCount)")
            )
            #expect(
                automatic.maxSimSpeed == legacy.maxSimSpeed,
                Comment(rawValue: "speed nodeCount=\(nodeCount)")
            )
            #expect(
                automatic.metrics.pairCount
                    == legacy.metrics.pairCount,
                Comment(rawValue: "pairs nodeCount=\(nodeCount)")
            )
            #expect(
                automatic.metrics.springCount
                    == legacy.metrics.springCount,
                Comment(rawValue: "springs nodeCount=\(nodeCount)")
            )
        }
    }

    private func replacing(
        _ input: GraphPhysicsStepInput,
        physicsRelevant: Set<NodeKey>? = nil,
        diagnosticOverride:
            GraphPhysicsInteractionStrategy? = nil
    ) -> GraphPhysicsStepInput {
        let resolvedRelevant: Set<NodeKey>?
        if let physicsRelevant {
            resolvedRelevant = physicsRelevant
        } else {
            resolvedRelevant = input.physicsRelevant
        }

        return GraphPhysicsStepInput(
            nodes: input.nodes,
            edges: input.edges,
            positions: input.positions,
            velocities: input.velocities,
            fixedNodeKeys: input.fixedNodeKeys,
            physicsRelevant: resolvedRelevant,
            configuration: input.configuration,
            diagnosticInteractionStrategyOverride: diagnosticOverride
        )
    }
}
