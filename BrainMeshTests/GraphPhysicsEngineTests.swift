import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics engine contracts")
struct GraphPhysicsEngineTests {
    private let tolerance: CGFloat = 1e-12

    @Test
    func configurationPreservesAllFormerCanvasConstants() {
        let configuration = GraphPhysicsConfiguration(
            collisionStrength: 0.030
        )

        #expect(configuration.repulsion == 8_800)
        #expect(configuration.linkSpring == 0.018)
        #expect(configuration.containmentSpring == 0.040)
        #expect(configuration.linkRestDistance == 130)
        #expect(configuration.containmentRestDistance == 76)
        #expect(configuration.damping == 0.85)
        #expect(configuration.maximumSpeed == 18)
        #expect(configuration.collisionPadding == 6)
        #expect(configuration.entityRadius == 22)
        #expect(configuration.attributeRadius == 18)
        #expect(configuration.minimumPairDistanceSquared == 40)
        #expect(configuration.minimumSpringDistance == 1)
        #expect(configuration.repulsionScale == 0.00002)
        #expect(configuration.collisionStrength == 0.030)
        #expect(
            configuration.interactionStrategy
                .exactPairLoopMaximumSimulatedNodeCount == 80
        )
        #expect(configuration.spatialGrid.maximumCollisionDistance == 50)
        #expect(
            configuration.spatialGrid
                .localInteractionReferenceDistance == 76
        )
        #expect(configuration.spatialGrid.cellSize == 76)
        #expect(
            GraphPhysicsConfiguration(
                collisionStrength: -0.5
            ).collisionStrength == 0
        )
    }

    @Test
    func domainValuesAreSendable() {
        assertSendable(GraphPhysicsConfiguration.self)
        assertSendable(GraphPhysicsInteractionStrategy.self)
        assertSendable(
            GraphPhysicsInteractionStrategyConfiguration.self
        )
        assertSendable(GraphPhysicsSpatialGridConfiguration.self)
        assertSendable(GraphPhysicsGridCoordinate.self)
        assertSendable(GraphPhysicsGridNode.self)
        assertSendable(GraphPhysicsGridCellAggregate.self)
        assertSendable(GraphPhysicsDistantCellRepulsion.self)
        assertSendable(GraphPhysicsGridCell.self)
        assertSendable(GraphPhysicsSpatialGrid.self)
        assertSendable(GraphPhysicsStepInput.self)
        assertSendable(GraphPhysicsStepMetrics.self)
        assertSendable(GraphPhysicsStepResult.self)
    }

    @Test
    func identicalInputsProduceIdenticalOutputs() {
        let input = GraphPhysicsFixtures.deterministicInput(nodeCount: 20)

        let first = GraphPhysicsEngine.step(input: input)
        let second = GraphPhysicsEngine.step(input: input)

        #expect(first == second)
    }

    @Test
    func inputDictionariesAreNotMutated() {
        let base = GraphPhysicsFixtures.deterministicInput(nodeCount: 5)
        var positions = base.positions
        var velocities = base.velocities
        let positionsBefore = positions
        let velocitiesBefore = velocities
        let input = GraphPhysicsStepInput(
            nodes: base.nodes,
            edges: base.edges,
            positions: positions,
            velocities: velocities,
            fixedNodeKeys: base.fixedNodeKeys,
            physicsRelevant: base.physicsRelevant,
            configuration: base.configuration
        )

        _ = GraphPhysicsEngine.step(input: input)

        #expect(positions == positionsBefore)
        #expect(velocities == velocitiesBefore)
        #expect(input.positions == positionsBefore)
        #expect(input.velocities == velocitiesBefore)

        positions.removeAll()
        velocities.removeAll()
        #expect(input.positions == positionsBefore)
        #expect(input.velocities == velocitiesBefore)
    }

    @Test
    func everyFullyPositionedPairIsCheckedExactlyOnce() {
        for nodeCount in [0, 1, 2, 5, 40] {
            let input = GraphPhysicsFixtures.deterministicInput(
                nodeCount: nodeCount
            )
            let result = GraphPhysicsEngine.step(input: input)
            let theoreticalPairCount = nodeCount * (nodeCount - 1) / 2

            #expect(
                result.metrics.pairCount == theoreticalPairCount,
                Comment(rawValue: "nodeCount=\(nodeCount)")
            )
        }
    }

    @Test
    func repulsionForTwoMovableNodesIsEqualAndOpposite() {
        let first = GraphPhysicsFixtures.node(100, kind: .entity)
        let second = GraphPhysicsFixtures.node(101, kind: .entity)
        let input = makeInput(
            nodes: [first, second],
            positions: [
                first.key: CGPoint(x: 0, y: 0),
                second.key: CGPoint(x: 100, y: 0)
            ],
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0
            )
        )

        let result = GraphPhysicsEngine.step(input: input)
        let firstVelocity = result.velocities[first.key, default: .zero]
        let secondVelocity = result.velocities[second.key, default: .zero]

        expectClose(firstVelocity.dx, -secondVelocity.dx)
        expectClose(firstVelocity.dy, -secondVelocity.dy)
        #expect(firstVelocity.dx < 0)
        #expect(secondVelocity.dx > 0)
    }

    @Test
    func fixedNodesAreZeroedButStillRepelMovableNodes() {
        let fixed = GraphPhysicsFixtures.node(110, kind: .entity)
        let movable = GraphPhysicsFixtures.node(111, kind: .entity)
        let input = makeInput(
            nodes: [fixed, movable],
            positions: [
                fixed.key: CGPoint(x: 0, y: 0),
                movable.key: CGPoint(x: 100, y: 0)
            ],
            velocities: [
                fixed.key: CGVector(dx: 8, dy: -5)
            ],
            fixedNodeKeys: [fixed.key],
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0
            )
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.velocities[fixed.key] == CGVector.zero)
        #expect(result.positions[fixed.key] == input.positions[fixed.key])
        #expect(result.velocities[movable.key, default: .zero].dx > 0)
    }

    @Test
    func nonRelevantNodesReceiveZeroVelocityAndKeepPosition() {
        let first = GraphPhysicsFixtures.node(120, kind: .entity)
        let second = GraphPhysicsFixtures.node(121, kind: .attribute)
        let outside = GraphPhysicsFixtures.node(122, kind: .entity)
        let outsidePosition = CGPoint(x: 240, y: -40)
        let input = makeInput(
            nodes: [first, second, outside],
            positions: [
                first.key: CGPoint(x: -80, y: 0),
                second.key: CGPoint(x: 20, y: 0),
                outside.key: outsidePosition
            ],
            velocities: [
                outside.key: CGVector(dx: 12, dy: -9)
            ],
            physicsRelevant: [first.key, second.key]
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.velocities[outside.key] == CGVector.zero)
        #expect(result.positions[outside.key] == outsidePosition)
        #expect(result.metrics.simulatedNodeCount == 2)
        #expect(result.metrics.pairCount == 1)
    }

    @Test
    func springForcesAreEqualAndOpposite() {
        let first = GraphPhysicsFixtures.node(130, kind: .entity)
        let second = GraphPhysicsFixtures.node(131, kind: .attribute)
        let input = makeInput(
            nodes: [first, second],
            edges: [
                GraphEdge(a: first.key, b: second.key, type: .link)
            ],
            positions: [
                first.key: CGPoint(x: 0, y: 0),
                second.key: CGPoint(x: 200, y: 0)
            ],
            configuration: springOnlyConfiguration()
        )

        let result = GraphPhysicsEngine.step(input: input)
        let firstVelocity = result.velocities[first.key, default: .zero]
        let secondVelocity = result.velocities[second.key, default: .zero]

        expectClose(firstVelocity.dx, -secondVelocity.dx)
        expectClose(firstVelocity.dy, -secondVelocity.dy)
        #expect(result.metrics.springCount == 1)
    }

    @Test
    func springsRequireBothEndpointsToBePhysicsRelevant() {
        let first = GraphPhysicsFixtures.node(135, kind: .entity)
        let second = GraphPhysicsFixtures.node(136, kind: .attribute)
        let firstPosition = CGPoint(x: 0, y: 0)
        let secondPosition = CGPoint(x: 200, y: 0)
        let input = makeInput(
            nodes: [first, second],
            edges: [
                GraphEdge(a: first.key, b: second.key, type: .link)
            ],
            positions: [
                first.key: firstPosition,
                second.key: secondPosition
            ],
            velocities: [
                first.key: .zero,
                second.key: CGVector(dx: 9, dy: -4)
            ],
            physicsRelevant: [first.key],
            configuration: springOnlyConfiguration()
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.metrics.springCount == 0)
        #expect(result.velocities[first.key, default: .zero] == .zero)
        #expect(result.positions[first.key] == firstPosition)
        #expect(result.velocities[second.key] == CGVector.zero)
        #expect(result.positions[second.key] == secondPosition)
    }

    @Test
    func linkAndContainmentSpringsUseTheirOwnConstants() {
        let first = GraphPhysicsFixtures.node(140, kind: .entity)
        let second = GraphPhysicsFixtures.node(141, kind: .attribute)
        let positions: [NodeKey: CGPoint] = [
            first.key: CGPoint(x: 0, y: 0),
            second.key: CGPoint(x: 200, y: 0)
        ]
        let linkResult = GraphPhysicsEngine.step(
            input: makeInput(
                nodes: [first, second],
                edges: [
                    GraphEdge(a: first.key, b: second.key, type: .link)
                ],
                positions: positions,
                configuration: springOnlyConfiguration()
            )
        )
        let containmentResult = GraphPhysicsEngine.step(
            input: makeInput(
                nodes: [first, second],
                edges: [
                    GraphEdge(
                        a: first.key,
                        b: second.key,
                        type: .containment
                    )
                ],
                positions: positions,
                configuration: springOnlyConfiguration()
            )
        )
        let expectedLinkVelocity: CGFloat =
            (200 - 130) * 0.018 * 0.85
        let expectedContainmentVelocity: CGFloat =
            (200 - 76) * 0.040 * 0.85

        expectClose(
            linkResult.velocities[first.key, default: .zero].dx,
            expectedLinkVelocity
        )
        expectClose(
            containmentResult.velocities[first.key, default: .zero].dx,
            expectedContainmentVelocity
        )
        #expect(
            containmentResult.velocities[first.key, default: .zero].dx
                > linkResult.velocities[first.key, default: .zero].dx
        )
    }

    @Test
    func maximumSpeedIsNeverExceeded() {
        let node = GraphPhysicsFixtures.node(150, kind: .entity)
        let input = makeInput(
            nodes: [node],
            positions: [node.key: .zero],
            velocities: [
                node.key: CGVector(dx: 10_000, dy: -8_000)
            ]
        )

        let result = GraphPhysicsEngine.step(input: input)
        let velocity = result.velocities[node.key, default: .zero]
        let speed = sqrt(
            velocity.dx * velocity.dx + velocity.dy * velocity.dy
        )

        #expect(speed <= input.configuration.maximumSpeed)
        expectClose(speed, input.configuration.maximumSpeed)
        expectClose(
            result.maxSimSpeed,
            input.configuration.maximumSpeed
        )
    }

    @Test
    func finiteInputsAcrossNegativeLargeAndSmallCoordinatesStayFinite() {
        let first = GraphPhysicsFixtures.node(160, kind: .entity)
        let second = GraphPhysicsFixtures.node(161, kind: .attribute)
        let third = GraphPhysicsFixtures.node(162, kind: .entity)
        let fourth = GraphPhysicsFixtures.node(163, kind: .attribute)
        let coordinateInput = makeInput(
            nodes: [first, second, third, fourth],
            edges: [
                GraphEdge(
                    a: first.key,
                    b: second.key,
                    type: .containment
                ),
                GraphEdge(a: second.key, b: third.key, type: .link),
                GraphEdge(
                    a: third.key,
                    b: fourth.key,
                    type: .containment
                )
            ],
            positions: [
                first.key: CGPoint(x: -1_000_000_000, y: 0.000000001),
                second.key: CGPoint(x: 1_000_000_000, y: -0.000000001),
                third.key: CGPoint(x: -0.000000001, y: -1_000_000_000),
                fourth.key: CGPoint(x: 0.000000001, y: 1_000_000_000)
            ],
            velocities: [
                first.key: CGVector(dx: -0.000000001, dy: 0.000000001),
                second.key: CGVector(dx: 0.000000001, dy: -0.000000001)
            ]
        )
        let inputs = [
            coordinateInput,
            GraphPhysicsFixtures.deterministicInput(nodeCount: 40)
        ]

        for input in inputs {
            let result = GraphPhysicsEngine.step(input: input)
            expectFinite(result)
        }
    }

    @Test
    func negativeCoordinatesAreIntegratedNormally() {
        let node = GraphPhysicsFixtures.node(170, kind: .entity)
        let input = makeInput(
            nodes: [node],
            positions: [
                node.key: CGPoint(x: -500, y: -300)
            ],
            velocities: [
                node.key: CGVector(dx: -2, dy: -4)
            ]
        )

        let result = GraphPhysicsEngine.step(input: input)
        let position = result.positions[node.key, default: .zero]

        #expect(position.x < -500)
        #expect(position.y < -300)
        expectFinite(result)
    }

    @Test
    func emptyInputReturnsControlledEmptyResult() {
        let input = makeInput(nodes: [], positions: [:])

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.positions.isEmpty)
        #expect(result.velocities.isEmpty)
        #expect(result.maxSimSpeed == 0)
        #expect(
            result.metrics == GraphPhysicsStepMetrics(
                simulatedNodeCount: 0,
                pairCount: 0,
                springCount: 0
            )
        )
    }

    @Test
    func singleNodeInputIntegratesWithoutPairsOrSprings() {
        let node = GraphPhysicsFixtures.node(180, kind: .entity)
        let input = makeInput(
            nodes: [node],
            positions: [node.key: CGPoint(x: 10, y: 20)],
            velocities: [node.key: CGVector(dx: 3, dy: -4)]
        )

        let result = GraphPhysicsEngine.step(input: input)

        #expect(result.metrics.simulatedNodeCount == 1)
        #expect(result.metrics.pairCount == 0)
        #expect(result.metrics.springCount == 0)
        #expect(result.positions[node.key] != input.positions[node.key])
        expectFinite(result)
    }

    private func makeInput(
        nodes: [GraphNode],
        edges: [GraphEdge] = [],
        positions: [NodeKey: CGPoint],
        velocities: [NodeKey: CGVector] = [:],
        fixedNodeKeys: Set<NodeKey> = [],
        physicsRelevant: Set<NodeKey>? = nil,
        configuration: GraphPhysicsConfiguration = GraphPhysicsConfiguration(
            collisionStrength: 0.030
        )
    ) -> GraphPhysicsStepInput {
        GraphPhysicsStepInput(
            nodes: nodes,
            edges: edges,
            positions: positions,
            velocities: velocities,
            fixedNodeKeys: fixedNodeKeys,
            physicsRelevant: physicsRelevant,
            configuration: configuration
        )
    }

    private func springOnlyConfiguration() -> GraphPhysicsConfiguration {
        GraphPhysicsConfiguration(
            collisionStrength: 0,
            repulsion: 0
        )
    }

    private func expectClose(
        _ actual: CGFloat,
        _ expected: CGFloat
    ) {
        #expect(abs(actual - expected) <= tolerance)
    }

    private func expectFinite(_ result: GraphPhysicsStepResult) {
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

private func assertSendable<T: Sendable>(_: T.Type) {
}
