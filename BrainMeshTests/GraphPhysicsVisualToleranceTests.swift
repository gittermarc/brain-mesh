import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics visual tolerance")
struct GraphPhysicsVisualToleranceTests {
    /// Deterministic comparison window long enough for approximation effects
    /// to accumulate without relying on the later runtime sleep policy.
    private let tickCount = 30

    /// Product-level visual contracts for the deterministic 120/140 fixtures:
    /// centroid <= 1 point, mean link length <= 15%, median link length <= 15%,
    /// bounding radius <= 20%, and collision overlap count no more than 5%
    /// above exact (with a three-overlap allowance for discrete rounding).
    @Test
    func largeGridLayoutsStayWithinDocumentedVisualTolerance() {
        for nodeCount in [120, 140] {
            let fixture = GraphPhysicsFixtures.deterministicInput(
                nodeCount: nodeCount
            )
            let exact = run(
                fixture,
                strategy: .exactPairLoop,
                tickCount: tickCount
            )
            let grid = run(
                fixture,
                strategy: .spatialGrid,
                tickCount: tickCount
            )
            let exactSummary = summarize(
                exact,
                input: fixture
            )
            let gridSummary = summarize(
                grid,
                input: fixture
            )

            #expect(
                distance(
                    exactSummary.centroid,
                    gridSummary.centroid
                ) <= 1,
                comment(nodeCount, "centroid")
            )
            #expect(
                relativeDifference(
                    exactSummary.averageLinkLength,
                    gridSummary.averageLinkLength
                ) <= 0.15,
                comment(nodeCount, "average link length")
            )
            #expect(
                relativeDifference(
                    exactSummary.medianLinkLength,
                    gridSummary.medianLinkLength
                ) <= 0.15,
                comment(nodeCount, "median link length")
            )
            #expect(
                relativeDifference(
                    exactSummary.boundingRadius,
                    gridSummary.boundingRadius
                ) <= 0.20,
                comment(nodeCount, "bounding radius")
            )

            let collisionAllowance = max(
                3,
                Int(
                    ceil(
                        Double(exactSummary.collisionOverlapCount)
                            * 0.05
                    )
                )
            )
            #expect(
                gridSummary.collisionOverlapCount
                    <= exactSummary.collisionOverlapCount
                        + collisionAllowance,
                comment(nodeCount, "collision overlaps")
            )
            #expect(
                exact.maxSimSpeed
                    <= fixture.configuration.maximumSpeed,
                comment(nodeCount, "exact maximum speed")
            )
            #expect(
                grid.maxSimSpeed
                    <= fixture.configuration.maximumSpeed,
                comment(nodeCount, "grid maximum speed")
            )
            #expect(exactSummary.allValuesFinite)
            #expect(gridSummary.allValuesFinite)
            #expect(exact.metrics.springCount == nodeCount - 1)
            #expect(grid.metrics.springCount == nodeCount - 1)

            print(
                "GraphPhysics visualTolerance "
                    + "nodes=\(nodeCount) "
                    + "ticks=\(tickCount) "
                    + "centroidDelta=\(distance(exactSummary.centroid, gridSummary.centroid)) "
                    + "averageLinkDelta=\(relativeDifference(exactSummary.averageLinkLength, gridSummary.averageLinkLength)) "
                    + "medianLinkDelta=\(relativeDifference(exactSummary.medianLinkLength, gridSummary.medianLinkLength)) "
                    + "boundingRadiusDelta=\(relativeDifference(exactSummary.boundingRadius, gridSummary.boundingRadius)) "
                    + "exactOverlaps=\(exactSummary.collisionOverlapCount) "
                    + "gridOverlaps=\(gridSummary.collisionOverlapCount) "
                    + "exactMaxSpeed=\(exact.maxSimSpeed) "
                    + "gridMaxSpeed=\(grid.maxSimSpeed)"
            )
        }
    }

    @Test
    func repeatedGridRunsAreExactlyDeterministic() {
        for nodeCount in [120, 140] {
            let fixture = GraphPhysicsFixtures.deterministicInput(
                nodeCount: nodeCount
            )
            let first = run(
                fixture,
                strategy: .spatialGrid,
                tickCount: tickCount
            )
            let second = run(
                fixture,
                strategy: .spatialGrid,
                tickCount: tickCount
            )

            #expect(
                first == second,
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
        }
    }

    private struct LayoutSummary {
        let centroid: CGPoint
        let boundingRadius: CGFloat
        let averageLinkLength: CGFloat
        let medianLinkLength: CGFloat
        let collisionOverlapCount: Int
        let allValuesFinite: Bool
    }

    private func run(
        _ initialInput: GraphPhysicsStepInput,
        strategy: GraphPhysicsInteractionStrategy,
        tickCount: Int
    ) -> GraphPhysicsStepResult {
        var input = GraphPhysicsStepInput(
            nodes: initialInput.nodes,
            edges: initialInput.edges,
            positions: initialInput.positions,
            velocities: initialInput.velocities,
            fixedNodeKeys: initialInput.fixedNodeKeys,
            physicsRelevant: initialInput.physicsRelevant,
            configuration: initialInput.configuration,
            diagnosticInteractionStrategyOverride: strategy
        )
        var result = GraphPhysicsEngine.step(input: input)

        guard tickCount > 1 else { return result }

        for _ in 1..<tickCount {
            input = GraphPhysicsStepInput(
                nodes: input.nodes,
                edges: input.edges,
                positions: result.positions,
                velocities: result.velocities,
                fixedNodeKeys: input.fixedNodeKeys,
                physicsRelevant: input.physicsRelevant,
                configuration: input.configuration,
                diagnosticInteractionStrategyOverride: strategy
            )
            result = GraphPhysicsEngine.step(input: input)
        }

        return result
    }

    private func summarize(
        _ result: GraphPhysicsStepResult,
        input: GraphPhysicsStepInput
    ) -> LayoutSummary {
        let keys = input.nodes.map(\.key).filter {
            result.positions[$0] != nil
        }
        let centroid = centroid(
            positions: result.positions,
            keys: keys
        )
        let boundingRadius = keys.reduce(CGFloat.zero) {
            max(
                $0,
                distance(
                    result.positions[$1, default: .zero],
                    centroid
                )
            )
        }
        let linkLengths = input.edges.compactMap { edge
            -> CGFloat? in
            guard let first = result.positions[edge.a],
                  let second = result.positions[edge.b] else {
                return nil
            }
            return distance(first, second)
        }.sorted()
        let averageLinkLength =
            linkLengths.isEmpty
                ? 0
                : linkLengths.reduce(0, +)
                    / CGFloat(linkLengths.count)
        let medianLinkLength = median(linkLengths)

        var collisionOverlapCount = 0
        if input.nodes.count >= 2 {
            for firstIndex in 0..<(input.nodes.count - 1) {
                let first = input.nodes[firstIndex]
                guard let firstPosition = result.positions[first.key]
                else {
                    continue
                }
                for secondIndex in
                    (firstIndex + 1)..<input.nodes.count {
                    let second = input.nodes[secondIndex]
                    guard let secondPosition =
                            result.positions[second.key] else {
                        continue
                    }
                    let minimumDistance =
                        radius(
                            first.key,
                            configuration: input.configuration
                        )
                        + radius(
                            second.key,
                            configuration: input.configuration
                        )
                        + input.configuration.collisionPadding
                    if distance(firstPosition, secondPosition)
                        < minimumDistance {
                        collisionOverlapCount += 1
                    }
                }
            }
        }

        return LayoutSummary(
            centroid: centroid,
            boundingRadius: boundingRadius,
            averageLinkLength: averageLinkLength,
            medianLinkLength: medianLinkLength,
            collisionOverlapCount: collisionOverlapCount,
            allValuesFinite:
                result.maxSimSpeed.isFinite
                && result.positions.values.allSatisfy {
                    $0.x.isFinite && $0.y.isFinite
                }
                && result.velocities.values.allSatisfy {
                    $0.dx.isFinite && $0.dy.isFinite
                }
        )
    }

    private func centroid(
        positions: [NodeKey: CGPoint],
        keys: [NodeKey]
    ) -> CGPoint {
        guard !keys.isEmpty else { return .zero }

        var x: CGFloat = 0
        var y: CGFloat = 0
        for key in keys {
            let position = positions[key, default: .zero]
            x += position.x
            y += position.y
        }
        let count = CGFloat(keys.count)
        return CGPoint(x: x / count, y: y / count)
    }

    private func median(_ sortedValues: [CGFloat]) -> CGFloat {
        guard !sortedValues.isEmpty else { return 0 }
        let midpoint = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (
                sortedValues[midpoint - 1]
                    + sortedValues[midpoint]
            ) / 2
        }
        return sortedValues[midpoint]
    }

    private func relativeDifference(
        _ baseline: CGFloat,
        _ comparison: CGFloat
    ) -> CGFloat {
        guard baseline != 0 else {
            return comparison == 0 ? 0 : .infinity
        }
        return abs(comparison - baseline) / abs(baseline)
    }

    private func distance(
        _ first: CGPoint,
        _ second: CGPoint
    ) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return sqrt(dx * dx + dy * dy)
    }

    private func radius(
        _ key: NodeKey,
        configuration: GraphPhysicsConfiguration
    ) -> CGFloat {
        switch key.kind {
        case .entity:
            return configuration.entityRadius
        case .attribute:
            return configuration.attributeRadius
        }
    }

    private func comment(
        _ nodeCount: Int,
        _ metric: String
    ) -> Comment {
        Comment(rawValue: "nodes=\(nodeCount) metric=\(metric)")
    }
}
