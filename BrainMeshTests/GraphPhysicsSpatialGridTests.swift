import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics spatial grid")
struct GraphPhysicsSpatialGridTests {
    private let tolerance: CGFloat = 1e-12

    @Test
    func coordinatesUseMathematicalFloorAcrossZeroAndBoundaries() {
        let cellSize: CGFloat = 76

        #expect(
            coordinate(12, 25, cellSize: cellSize)
                == GraphPhysicsGridCoordinate(x: 0, y: 0)
        )
        #expect(
            coordinate(0, 0, cellSize: cellSize)
                == GraphPhysicsGridCoordinate(x: 0, y: 0)
        )
        #expect(
            coordinate(-0.001, -0.001, cellSize: cellSize)
                == GraphPhysicsGridCoordinate(x: -1, y: -1)
        )
        #expect(
            coordinate(76, 152, cellSize: cellSize)
                == GraphPhysicsGridCoordinate(x: 1, y: 2)
        )
        #expect(
            coordinate(-76, -152, cellSize: cellSize)
                == GraphPhysicsGridCoordinate(x: -1, y: -2)
        )
        #expect(
            coordinate(-76.001, -152.001, cellSize: cellSize)
                == GraphPhysicsGridCoordinate(x: -2, y: -3)
        )
    }

    @Test
    func productionCellSizeCoversMaximumCollisionDistance() {
        let physics = GraphPhysicsConfiguration(
            collisionStrength: 0.030
        )
        let grid = physics.spatialGrid

        #expect(grid.maximumCollisionDistance == 50)
        #expect(grid.localInteractionReferenceDistance == 76)
        #expect(grid.cellSize == 76)
        #expect(grid.cellSize >= grid.maximumCollisionDistance)

        let defensive = GraphPhysicsSpatialGridConfiguration(
            cellSize: 10,
            maximumCollisionDistance: 50
        )
        #expect(defensive.cellSize == 50)
    }

    @Test
    func buildGroupsNodesAndOmitsMissingPositions() {
        let first = GraphPhysicsFixtures.node(2_000, kind: .entity)
        let second = GraphPhysicsFixtures.node(
            2_001,
            kind: .attribute
        )
        let missing = GraphPhysicsFixtures.node(
            2_002,
            kind: .entity
        )
        let grid = makeGrid(
            nodes: [first, second, missing],
            positions: [
                first.key: CGPoint(x: 10, y: 12),
                second.key: CGPoint(x: 20, y: 30)
            ]
        )

        #expect(grid.cells.count == 1)
        #expect(grid.cells[0].nodes.count == 2)
        #expect(grid.cells[0].aggregate.positionedNodeCount == 2)
        #expect(
            grid.cells[0].aggregate.centroid
                == CGPoint(x: 15, y: 21)
        )
        #expect(
            Set(grid.cells[0].nodes.map(\.key))
                == Set([first.key, second.key])
        )
    }

    @Test
    func emptyAndSingleNodeGridsAreControlled() {
        let empty = makeGrid(nodes: [], positions: [:])
        #expect(empty.cells.isEmpty)

        let node = GraphPhysicsFixtures.node(2_010, kind: .entity)
        let single = makeGrid(
            nodes: [node],
            positions: [node.key: CGPoint(x: -10, y: 90)]
        )
        #expect(single.cells.count == 1)
        #expect(single.cells[0].nodes.count == 1)
        #expect(single.cells[0].aggregate.positionedNodeCount == 1)
        #expect(
            single.cells[0].aggregate.centroid
                == CGPoint(x: -10, y: 90)
        )
    }

    @Test
    func cellsAndNodesHaveDeterministicTechnicalOrdering() {
        let first = GraphPhysicsFixtures.node(2_020, kind: .entity)
        let second = GraphPhysicsFixtures.node(
            2_021,
            kind: .attribute
        )
        let third = GraphPhysicsFixtures.node(2_022, kind: .entity)
        let nodes = [third, first, second]
        let positions: [NodeKey: CGPoint] = [
            first.key: CGPoint(x: 10, y: 10),
            second.key: CGPoint(x: 20, y: 10),
            third.key: CGPoint(x: -100, y: -100)
        ]

        let firstBuild = makeGrid(
            nodes: nodes,
            positions: positions
        )
        let secondBuild = makeGrid(
            nodes: nodes,
            positions: positions
        )
        let reorderedBuild = makeGrid(
            nodes: Array(nodes.reversed()),
            positions: positions
        )

        #expect(firstBuild == secondBuild)
        #expect(firstBuild == reorderedBuild)
        #expect(firstBuild.cells.map(\.coordinate).isSorted())
        for cell in firstBuild.cells {
            #expect(
                cell.nodes.map(\.key.identifier)
                    == cell.nodes.map(\.key.identifier).sorted()
            )
        }
    }

    @Test
    func collisionIsExactWithinSameCell() {
        assertCollision(
            firstKind: .entity,
            secondKind: .attribute,
            firstPosition: CGPoint(x: 10, y: 10),
            secondPosition: CGPoint(x: 12, y: 10)
        )
    }

    @Test
    func collisionIsExactAcrossHorizontalCellBoundary() {
        assertCollision(
            firstKind: .entity,
            secondKind: .attribute,
            firstPosition: CGPoint(x: 75, y: 10),
            secondPosition: CGPoint(x: 77, y: 10)
        )
    }

    @Test
    func collisionIsExactAcrossVerticalCellBoundary() {
        assertCollision(
            firstKind: .entity,
            secondKind: .attribute,
            firstPosition: CGPoint(x: 10, y: 75),
            secondPosition: CGPoint(x: 10, y: 77)
        )
    }

    @Test
    func collisionIsExactAcrossDiagonalCellBoundary() {
        assertCollision(
            firstKind: .entity,
            secondKind: .attribute,
            firstPosition: CGPoint(x: 75, y: 75),
            secondPosition: CGPoint(x: 77, y: 77)
        )
    }

    @Test
    func everyNodeKindCombinationUsesItsExactCollisionRadius() {
        let cases: [(NodeKind, NodeKind, CGFloat)] = [
            (.entity, .entity, 49),
            (.entity, .attribute, 45),
            (.attribute, .attribute, 41)
        ]

        for (firstKind, secondKind, distance) in cases {
            assertCollision(
                firstKind: firstKind,
                secondKind: secondKind,
                firstPosition: CGPoint(x: 0, y: 0),
                secondPosition: CGPoint(x: distance, y: 0)
            )
        }
    }

    @Test
    func exactGridCandidatePairsAreCheckedAtMostOnce() {
        let nodes = (0..<4).map {
            GraphPhysicsFixtures.node(
                2_100 + $0,
                kind: $0.isMultiple(of: 2) ? .entity : .attribute
            )
        }
        let input = makeInput(
            nodes: nodes,
            positions: [
                nodes[0].key: CGPoint(x: 10, y: 10),
                nodes[1].key: CGPoint(x: 20, y: 10),
                nodes[2].key: CGPoint(x: 80, y: 10),
                nodes[3].key: CGPoint(x: 90, y: 10)
            ],
            configuration: interactionOnlyConfiguration(),
            strategy: .spatialGrid
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.metrics.theoreticalExactPairCount == 6)
        #expect(result.metrics.exactCheckedNodePairCount == 6)
        #expect(result.metrics.neighboringCellPairCount == 1)
        #expect(result.metrics.approximatedDistantCellPairCount == 0)
    }

    @Test
    func collisionOutsideMaximumDistanceDoesNotApply() {
        let first = GraphPhysicsFixtures.node(2_120, kind: .entity)
        let second = GraphPhysicsFixtures.node(2_121, kind: .entity)
        let input = makeInput(
            nodes: [first, second],
            positions: [
                first.key: .zero,
                second.key: CGPoint(x: 51, y: 0)
            ],
            configuration: interactionOnlyConfiguration(),
            strategy: .spatialGrid
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.metrics.exactCheckedNodePairCount == 1)
        #expect(result.velocities[first.key] == CGVector.zero)
        #expect(result.velocities[second.key] == CGVector.zero)
    }

    @Test
    func fixedNodeAppliesCollisionButReceivesNoCollisionVelocity() {
        let fixed = GraphPhysicsFixtures.node(2_130, kind: .entity)
        let movable = GraphPhysicsFixtures.node(2_131, kind: .entity)
        let input = makeInput(
            nodes: [fixed, movable],
            positions: [
                fixed.key: .zero,
                movable.key: CGPoint(x: 40, y: 0)
            ],
            velocities: [
                fixed.key: CGVector(dx: 7, dy: -4)
            ],
            fixedNodeKeys: [fixed.key],
            configuration: interactionOnlyConfiguration(),
            strategy: .spatialGrid
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.velocities[fixed.key] == CGVector.zero)
        #expect(result.positions[fixed.key] == CGPoint.zero)
        #expect(result.velocities[movable.key, default: .zero].dx > 0)
    }

    @Test
    func nearbyRepulsionMatchesExactPairLoop() {
        let first = GraphPhysicsFixtures.node(2_140, kind: .entity)
        let second = GraphPhysicsFixtures.node(
            2_141,
            kind: .attribute
        )
        let base = makeInput(
            nodes: [first, second],
            positions: [
                first.key: CGPoint(x: 70, y: 20),
                second.key: CGPoint(x: 90, y: 30)
            ],
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0
            ),
            strategy: .exactPairLoop
        )
        let grid = replacingStrategy(base, with: .spatialGrid)

        let exactResult = GraphPhysicsEngine.step(input: base)
        let gridResult = GraphPhysicsEngine.step(input: grid)

        #expect(gridResult.positions == exactResult.positions)
        #expect(gridResult.velocities == exactResult.velocities)
        #expect(gridResult.maxSimSpeed == exactResult.maxSimSpeed)
        #expect(gridResult.metrics.exactCheckedNodePairCount == 1)
        #expect(
            gridResult.metrics.approximatedDistantCellPairCount == 0
        )
    }

    @Test
    func distantCellsUseOneSymmetricAggregateInteraction() {
        let nodes = (0..<4).map {
            GraphPhysicsFixtures.node(
                2_150 + $0,
                kind: $0.isMultiple(of: 2) ? .entity : .attribute
            )
        }
        let input = makeInput(
            nodes: nodes,
            positions: [
                nodes[0].key: CGPoint(x: -300, y: 0),
                nodes[1].key: CGPoint(x: -300, y: 0),
                nodes[2].key: CGPoint(x: 300, y: 0),
                nodes[3].key: CGPoint(x: 300, y: 0)
            ],
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0
            ),
            strategy: .spatialGrid
        )

        let first = GraphPhysicsEngine.step(input: input)
        let second = GraphPhysicsEngine.step(input: input)

        #expect(first == second)
        #expect(first.metrics.occupiedGridCellCount == 2)
        #expect(first.metrics.exactCheckedNodePairCount == 2)
        #expect(first.metrics.neighboringCellPairCount == 0)
        #expect(first.metrics.approximatedDistantCellPairCount == 1)

        let leftFirst = first.velocities[nodes[0].key, default: .zero]
        let leftSecond = first.velocities[nodes[1].key, default: .zero]
        let rightFirst = first.velocities[nodes[2].key, default: .zero]
        let rightSecond = first.velocities[nodes[3].key, default: .zero]
        expectClose(leftFirst.dx, leftSecond.dx)
        expectClose(rightFirst.dx, rightSecond.dx)
        expectClose(leftFirst.dx, -rightFirst.dx)
        #expect(leftFirst.dx < 0)
        #expect(rightFirst.dx > 0)
    }

    @Test
    func symmetricAggregateFixtureHasNoCentroidDrift() {
        let nodes = (0..<4).map {
            GraphPhysicsFixtures.node(2_170 + $0, kind: .entity)
        }
        var input = makeInput(
            nodes: nodes,
            positions: [
                nodes[0].key: CGPoint(x: -300, y: -300),
                nodes[1].key: CGPoint(x: -300, y: 300),
                nodes[2].key: CGPoint(x: 300, y: -300),
                nodes[3].key: CGPoint(x: 300, y: 300)
            ],
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0
            ),
            strategy: .spatialGrid
        )

        for _ in 0..<20 {
            let result = GraphPhysicsEngine.step(input: input)
            input = GraphPhysicsStepInput(
                nodes: input.nodes,
                edges: input.edges,
                positions: result.positions,
                velocities: result.velocities,
                fixedNodeKeys: input.fixedNodeKeys,
                physicsRelevant: input.physicsRelevant,
                configuration: input.configuration,
                diagnosticInteractionStrategyOverride: .spatialGrid
            )
        }

        let centroid = centroid(
            positions: input.positions,
            keys: nodes.map(\.key)
        )
        expectClose(centroid.x, 0)
        expectClose(centroid.y, 0)
    }

    @Test
    func distantFixedNodeRemainsARepulsionSource() {
        let fixed = GraphPhysicsFixtures.node(2_180, kind: .entity)
        let movable = GraphPhysicsFixtures.node(2_181, kind: .entity)
        let input = makeInput(
            nodes: [fixed, movable],
            positions: [
                fixed.key: CGPoint(x: -300, y: 0),
                movable.key: CGPoint(x: 300, y: 0)
            ],
            velocities: [
                fixed.key: CGVector(dx: 4, dy: 3)
            ],
            fixedNodeKeys: [fixed.key],
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0
            ),
            strategy: .spatialGrid
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.metrics.approximatedDistantCellPairCount == 1)
        #expect(result.velocities[fixed.key] == CGVector.zero)
        #expect(result.positions[fixed.key] == input.positions[fixed.key])
        #expect(result.velocities[movable.key, default: .zero].dx > 0)
    }

    @Test
    func missingSingleAndIdenticalPositionsNeverProduceInvalidValues() {
        let first = GraphPhysicsFixtures.node(2_190, kind: .entity)
        let second = GraphPhysicsFixtures.node(
            2_191,
            kind: .attribute
        )
        let missing = makeInput(
            nodes: [first],
            positions: [:],
            velocities: [
                first.key: CGVector(dx: 1, dy: -1)
            ],
            strategy: .spatialGrid
        )
        let identical = makeInput(
            nodes: [first, second],
            positions: [
                first.key: CGPoint(x: 50, y: -50),
                second.key: CGPoint(x: 50, y: -50)
            ],
            strategy: .spatialGrid
        )
        let missingExact = GraphPhysicsEngine.step(
            input: replacingStrategy(missing, with: .exactPairLoop)
        )
        let missingGrid = GraphPhysicsEngine.step(input: missing)

        #expect(missingGrid.positions == missingExact.positions)
        #expect(missingGrid.velocities == missingExact.velocities)
        #expect(missingGrid.maxSimSpeed == missingExact.maxSimSpeed)

        for input in [missing, identical] {
            let result = GraphPhysicsEngine.step(input: input)
            #expect(result.maxSimSpeed.isFinite)
            #expect(
                result.positions.values.allSatisfy {
                    $0.x.isFinite && $0.y.isFinite
                }
            )
            #expect(
                result.velocities.values.allSatisfy {
                    $0.dx.isFinite && $0.dy.isFinite
                }
            )
        }
    }

    @Test
    func identicalCellCentroidsProduceFiniteZeroAggregateForce() {
        let first = GraphPhysicsGridCellAggregate(
            coordinate: GraphPhysicsGridCoordinate(x: -2, y: 0),
            positionedNodeCount: 3,
            centroid: CGPoint(x: 10, y: -20)
        )
        let second = GraphPhysicsGridCellAggregate(
            coordinate: GraphPhysicsGridCoordinate(x: 2, y: 0),
            positionedNodeCount: 5,
            centroid: CGPoint(x: 10, y: -20)
        )

        let interaction = GraphPhysicsDistantCellRepulsion.calculate(
            first: first,
            second: second,
            configuration: GraphPhysicsFixtures.standardConfiguration
        )

        #expect(interaction.firstCellVelocityPerMovableNode == .zero)
        #expect(interaction.secondCellVelocityPerMovableNode == .zero)
        #expect(
            interaction.firstCellVelocityPerMovableNode.dx.isFinite
        )
        #expect(
            interaction.firstCellVelocityPerMovableNode.dy.isFinite
        )
        #expect(
            interaction.secondCellVelocityPerMovableNode.dx.isFinite
        )
        #expect(
            interaction.secondCellVelocityPerMovableNode.dy.isFinite
        )

        let empty = GraphPhysicsGridCellAggregate(
            coordinate: GraphPhysicsGridCoordinate(x: 5, y: 5),
            positionedNodeCount: 0,
            centroid: .zero
        )
        let emptyInteraction =
            GraphPhysicsDistantCellRepulsion.calculate(
                first: first,
                second: empty,
                configuration:
                    GraphPhysicsFixtures.standardConfiguration
            )
        #expect(
            emptyInteraction.firstCellVelocityPerMovableNode == .zero
        )
        #expect(
            emptyInteraction.secondCellVelocityPerMovableNode == .zero
        )
    }

    @Test
    func nodeInputOrderDoesNotChangeGridEngineResult() {
        let base = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 120
        )
        let forward = replacingStrategy(base, with: .spatialGrid)
        let reversed = GraphPhysicsStepInput(
            nodes: Array(base.nodes.reversed()),
            edges: base.edges,
            positions: base.positions,
            velocities: base.velocities,
            fixedNodeKeys: base.fixedNodeKeys,
            physicsRelevant: base.physicsRelevant,
            configuration: base.configuration,
            diagnosticInteractionStrategyOverride: .spatialGrid
        )

        let forwardResult = GraphPhysicsEngine.step(input: forward)
        let reversedResult = GraphPhysicsEngine.step(input: reversed)

        #expect(forwardResult == reversedResult)
    }

    @Test
    func gridStrategyLeavesEverySpringCalculationExact() {
        let configuration = GraphPhysicsConfiguration(
            collisionStrength: 0,
            repulsion: 0
        )
        let base = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 120,
            configuration: configuration
        )
        let exact = GraphPhysicsEngine.step(
            input: replacingStrategy(base, with: .exactPairLoop)
        )
        let grid = GraphPhysicsEngine.step(
            input: replacingStrategy(base, with: .spatialGrid)
        )

        #expect(exact.positions == grid.positions)
        #expect(exact.velocities == grid.velocities)
        #expect(exact.maxSimSpeed == grid.maxSimSpeed)
        #expect(exact.metrics.springCount == 119)
        #expect(grid.metrics.springCount == 119)
    }

    private func assertCollision(
        firstKind: NodeKind,
        secondKind: NodeKind,
        firstPosition: CGPoint,
        secondPosition: CGPoint
    ) {
        let first = GraphPhysicsFixtures.node(2_300, kind: firstKind)
        let second = GraphPhysicsFixtures.node(
            2_301,
            kind: secondKind
        )
        let input = makeInput(
            nodes: [first, second],
            positions: [
                first.key: firstPosition,
                second.key: secondPosition
            ],
            configuration: interactionOnlyConfiguration(),
            strategy: .spatialGrid
        )

        let result = GraphPhysicsEngine.step(input: input)
        let firstVelocity =
            result.velocities[first.key, default: .zero]
        let secondVelocity =
            result.velocities[second.key, default: .zero]

        #expect(result.metrics.exactCheckedNodePairCount == 1)
        #expect(firstVelocity != .zero)
        #expect(secondVelocity != .zero)
        expectClose(firstVelocity.dx, -secondVelocity.dx)
        expectClose(firstVelocity.dy, -secondVelocity.dy)
    }

    private func coordinate(
        _ x: CGFloat,
        _ y: CGFloat,
        cellSize: CGFloat
    ) -> GraphPhysicsGridCoordinate {
        GraphPhysicsGridCoordinate(
            position: CGPoint(x: x, y: y),
            cellSize: cellSize
        )
    }

    private func makeGrid(
        nodes: [GraphNode],
        positions: [NodeKey: CGPoint]
    ) -> GraphPhysicsSpatialGrid {
        GraphPhysicsSpatialGrid(
            nodes: nodes,
            positions: positions,
            configuration: GraphPhysicsFixtures
                .standardConfiguration.spatialGrid
        )
    }

    private func makeInput(
        nodes: [GraphNode],
        edges: [GraphEdge] = [],
        positions: [NodeKey: CGPoint],
        velocities: [NodeKey: CGVector] = [:],
        fixedNodeKeys: Set<NodeKey> = [],
        configuration:
            GraphPhysicsConfiguration = GraphPhysicsFixtures
                .standardConfiguration,
        strategy: GraphPhysicsInteractionStrategy
    ) -> GraphPhysicsStepInput {
        GraphPhysicsStepInput(
            nodes: nodes,
            edges: edges,
            positions: positions,
            velocities: velocities,
            fixedNodeKeys: fixedNodeKeys,
            physicsRelevant: nil,
            configuration: configuration,
            diagnosticInteractionStrategyOverride: strategy
        )
    }

    private func replacingStrategy(
        _ input: GraphPhysicsStepInput,
        with strategy: GraphPhysicsInteractionStrategy
    ) -> GraphPhysicsStepInput {
        GraphPhysicsStepInput(
            nodes: input.nodes,
            edges: input.edges,
            positions: input.positions,
            velocities: input.velocities,
            fixedNodeKeys: input.fixedNodeKeys,
            physicsRelevant: input.physicsRelevant,
            configuration: input.configuration,
            diagnosticInteractionStrategyOverride: strategy
        )
    }

    private func interactionOnlyConfiguration()
        -> GraphPhysicsConfiguration {
        GraphPhysicsConfiguration(
            collisionStrength: 0.030,
            repulsion: 0
        )
    }

    private func centroid(
        positions: [NodeKey: CGPoint],
        keys: [NodeKey]
    ) -> CGPoint {
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

    private func expectClose(
        _ actual: CGFloat,
        _ expected: CGFloat
    ) {
        #expect(abs(actual - expected) <= tolerance)
    }
}

private extension Array where Element: Comparable {
    func isSorted() -> Bool {
        zip(self, dropFirst()).allSatisfy {
            $0.0 <= $0.1
        }
    }
}
