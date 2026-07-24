import CoreGraphics
import Foundation

@testable import BrainMesh

struct GraphPhysicsCharacterizationFixture {
    let name: String
    let input: GraphPhysicsStepInput
}

enum GraphPhysicsFixtures {
    static let standardConfiguration = GraphPhysicsConfiguration(
        collisionStrength: 0.030
    )

    static var characterization: [GraphPhysicsCharacterizationFixture] {
        let firstEntity = node(1, kind: .entity)
        let secondEntity = node(2, kind: .entity)
        let firstAttribute = node(3, kind: .attribute)
        let secondAttribute = node(4, kind: .attribute)
        let thirdEntity = node(5, kind: .entity)

        let twoEntityPositions: [NodeKey: CGPoint] = [
            firstEntity.key: CGPoint(x: -70, y: 18),
            secondEntity.key: CGPoint(x: 95, y: -26)
        ]
        let collisionPositions: [NodeKey: CGPoint] = [
            firstEntity.key: CGPoint(x: 12, y: -8),
            firstAttribute.key: CGPoint(x: 34, y: 5)
        ]
        let springPositions: [NodeKey: CGPoint] = [
            firstEntity.key: CGPoint(x: -20, y: 10),
            firstAttribute.key: CGPoint(x: 210, y: 45)
        ]

        return [
            fixture(
                "two entity nodes without edge",
                nodes: [firstEntity, secondEntity],
                positions: twoEntityPositions
            ),
            fixture(
                "entity and attribute with collision",
                nodes: [firstEntity, firstAttribute],
                positions: collisionPositions
            ),
            fixture(
                "two nodes at identical position",
                nodes: [firstEntity, firstAttribute],
                positions: [
                    firstEntity.key: CGPoint(x: 30, y: -15),
                    firstAttribute.key: CGPoint(x: 30, y: -15)
                ]
            ),
            fixture(
                "link spring",
                nodes: [firstEntity, firstAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .link
                    )
                ],
                positions: springPositions
            ),
            fixture(
                "containment spring",
                nodes: [firstEntity, firstAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .containment
                    )
                ],
                positions: springPositions
            ),
            fixture(
                "mixed link and containment edges",
                nodes: [firstEntity, firstAttribute, secondAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .containment
                    ),
                    GraphEdge(
                        a: firstAttribute.key,
                        b: secondAttribute.key,
                        type: .link
                    )
                ],
                positions: [
                    firstEntity.key: CGPoint(x: -120, y: 20),
                    firstAttribute.key: CGPoint(x: 0, y: -10),
                    secondAttribute.key: CGPoint(x: 170, y: 60)
                ]
            ),
            fixture(
                "fixed first node",
                nodes: [firstEntity, firstAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .link
                    )
                ],
                positions: collisionPositions,
                velocities: [
                    firstEntity.key: CGVector(dx: 3, dy: -2),
                    firstAttribute.key: CGVector(dx: -1, dy: 4)
                ],
                fixedNodeKeys: [firstEntity.key]
            ),
            fixture(
                "fixed second node",
                nodes: [firstEntity, firstAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .link
                    )
                ],
                positions: collisionPositions,
                velocities: [
                    firstEntity.key: CGVector(dx: 3, dy: -2),
                    firstAttribute.key: CGVector(dx: -1, dy: 4)
                ],
                fixedNodeKeys: [firstAttribute.key]
            ),
            fixture(
                "multiple fixed nodes",
                nodes: [
                    firstEntity,
                    firstAttribute,
                    secondAttribute,
                    thirdEntity
                ],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .containment
                    ),
                    GraphEdge(
                        a: firstAttribute.key,
                        b: secondAttribute.key,
                        type: .link
                    ),
                    GraphEdge(
                        a: secondAttribute.key,
                        b: thirdEntity.key,
                        type: .link
                    )
                ],
                positions: [
                    firstEntity.key: CGPoint(x: -100, y: -40),
                    firstAttribute.key: CGPoint(x: -25, y: 20),
                    secondAttribute.key: CGPoint(x: 55, y: -10),
                    thirdEntity.key: CGPoint(x: 145, y: 35)
                ],
                velocities: [
                    firstEntity.key: CGVector(dx: 4, dy: 2),
                    firstAttribute.key: CGVector(dx: -3, dy: 1),
                    secondAttribute.key: CGVector(dx: 2, dy: -2),
                    thirdEntity.key: CGVector(dx: -1, dy: 3)
                ],
                fixedNodeKeys: [firstEntity.key, secondAttribute.key]
            ),
            fixture(
                "dragged node in organize mode",
                nodes: [firstEntity, firstAttribute, secondAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .containment
                    ),
                    GraphEdge(
                        a: firstAttribute.key,
                        b: secondAttribute.key,
                        type: .link
                    )
                ],
                positions: [
                    firstEntity.key: CGPoint(x: -80, y: 0),
                    firstAttribute.key: CGPoint(x: 0, y: 0),
                    secondAttribute.key: CGPoint(x: 105, y: 30)
                ],
                velocities: [
                    firstAttribute.key: CGVector(dx: 12, dy: -8)
                ],
                fixedNodeKeys: [firstAttribute.key]
            ),
            fixture(
                "spotlight subset",
                nodes: [
                    firstEntity,
                    firstAttribute,
                    secondAttribute,
                    thirdEntity
                ],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .containment
                    ),
                    GraphEdge(
                        a: firstAttribute.key,
                        b: secondAttribute.key,
                        type: .link
                    ),
                    GraphEdge(
                        a: secondAttribute.key,
                        b: thirdEntity.key,
                        type: .link
                    )
                ],
                positions: [
                    firstEntity.key: CGPoint(x: -100, y: 0),
                    firstAttribute.key: CGPoint(x: 0, y: 0),
                    secondAttribute.key: CGPoint(x: 110, y: 0),
                    thirdEntity.key: CGPoint(x: 230, y: 0)
                ],
                physicsRelevant: [
                    firstEntity.key,
                    firstAttribute.key,
                    secondAttribute.key
                ]
            ),
            fixture(
                "spotlight with one node",
                nodes: [firstEntity, firstAttribute, secondAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .containment
                    ),
                    GraphEdge(
                        a: firstAttribute.key,
                        b: secondAttribute.key,
                        type: .link
                    )
                ],
                positions: [
                    firstEntity.key: CGPoint(x: -70, y: 0),
                    firstAttribute.key: CGPoint(x: 0, y: 0),
                    secondAttribute.key: CGPoint(x: 85, y: 0)
                ],
                velocities: [
                    firstEntity.key: CGVector(dx: 2, dy: 1),
                    firstAttribute.key: CGVector(dx: 4, dy: -3),
                    secondAttribute.key: CGVector(dx: -2, dy: 2)
                ],
                physicsRelevant: [firstAttribute.key]
            ),
            fixture(
                "nodes outside spotlight are stopped",
                nodes: [
                    firstEntity,
                    firstAttribute,
                    secondAttribute,
                    thirdEntity
                ],
                positions: [
                    firstEntity.key: CGPoint(x: -120, y: 0),
                    firstAttribute.key: CGPoint(x: -20, y: 0),
                    secondAttribute.key: CGPoint(x: 100, y: 0),
                    thirdEntity.key: CGPoint(x: 220, y: 0)
                ],
                velocities: [
                    firstEntity.key: CGVector(dx: 1, dy: 2),
                    firstAttribute.key: CGVector(dx: 3, dy: 4),
                    secondAttribute.key: CGVector(dx: 5, dy: 6),
                    thirdEntity.key: CGVector(dx: 7, dy: 8)
                ],
                physicsRelevant: [firstEntity.key, firstAttribute.key]
            ),
            fixture(
                "missing position",
                nodes: [firstEntity, firstAttribute, secondAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .link
                    ),
                    GraphEdge(
                        a: firstAttribute.key,
                        b: secondAttribute.key,
                        type: .containment
                    )
                ],
                positions: [
                    firstEntity.key: CGPoint(x: -80, y: 15),
                    secondAttribute.key: CGPoint(x: 90, y: -25)
                ],
                velocities: [
                    firstAttribute.key: CGVector(dx: 2, dy: -1)
                ]
            ),
            fixture(
                "missing velocity",
                nodes: [firstEntity, firstAttribute, secondAttribute],
                edges: [
                    GraphEdge(
                        a: firstEntity.key,
                        b: firstAttribute.key,
                        type: .containment
                    )
                ],
                positions: [
                    firstEntity.key: CGPoint(x: -60, y: 10),
                    firstAttribute.key: CGPoint(x: 30, y: 20),
                    secondAttribute.key: CGPoint(x: 150, y: -30)
                ],
                velocities: [
                    firstEntity.key: CGVector(dx: 1, dy: -1)
                ]
            ),
            fixture(
                "speed clamping",
                nodes: [firstEntity, firstAttribute],
                positions: twoEntityPositions,
                velocities: [
                    firstEntity.key: CGVector(dx: 900, dy: -700),
                    firstAttribute.key: CGVector(dx: -800, dy: 600)
                ]
            ),
            GraphPhysicsCharacterizationFixture(
                name: "five nodes",
                input: deterministicInput(nodeCount: 5)
            ),
            GraphPhysicsCharacterizationFixture(
                name: "twenty nodes",
                input: deterministicInput(nodeCount: 20)
            ),
            GraphPhysicsCharacterizationFixture(
                name: "forty nodes",
                input: deterministicInput(nodeCount: 40)
            )
        ]
    }

    static func deterministicInput(
        nodeCount: Int,
        configuration: GraphPhysicsConfiguration = standardConfiguration
    ) -> GraphPhysicsStepInput {
        let nodes = (0..<nodeCount).map { index in
            node(
                1_000 + index,
                kind: index.isMultiple(of: 2) ? .entity : .attribute
            )
        }
        var positions: [NodeKey: CGPoint] = [:]
        var velocities: [NodeKey: CGVector] = [:]
        positions.reserveCapacity(nodeCount)
        velocities.reserveCapacity(nodeCount)

        for (index, node) in nodes.enumerated() {
            let column = index % 14
            let row = index / 14
            positions[node.key] = CGPoint(
                x: CGFloat(column * 47 - 300)
                    + CGFloat(index % 3) * 0.125,
                y: CGFloat(row * 53 - 170)
                    + CGFloat(index % 5) * 0.2
            )
            velocities[node.key] = CGVector(
                dx: CGFloat(index % 7 - 3) * 0.17,
                dy: CGFloat(index % 9 - 4) * 0.11
            )
        }

        let edges: [GraphEdge]
        if nodeCount >= 2 {
            edges = (1..<nodeCount).map { index in
                GraphEdge(
                    a: nodes[index - 1].key,
                    b: nodes[index].key,
                    type: nodes[index].key.kind == .attribute
                        ? .containment
                        : .link
                )
            }
        } else {
            edges = []
        }

        return GraphPhysicsStepInput(
            nodes: nodes,
            edges: edges,
            positions: positions,
            velocities: velocities,
            fixedNodeKeys: [],
            physicsRelevant: nil,
            configuration: configuration
        )
    }

    static func node(
        _ value: Int,
        kind: NodeKind
    ) -> GraphNode {
        GraphNode(
            key: NodeKey(kind: kind, uuid: uuid(value)),
            label: "Physics Node \(value)"
        )
    }

    private static func fixture(
        _ name: String,
        nodes: [GraphNode],
        edges: [GraphEdge] = [],
        positions: [NodeKey: CGPoint],
        velocities: [NodeKey: CGVector] = [:],
        fixedNodeKeys: Set<NodeKey> = [],
        physicsRelevant: Set<NodeKey>? = nil,
        configuration: GraphPhysicsConfiguration = standardConfiguration
    ) -> GraphPhysicsCharacterizationFixture {
        GraphPhysicsCharacterizationFixture(
            name: name,
            input: GraphPhysicsStepInput(
                nodes: nodes,
                edges: edges,
                positions: positions,
                velocities: velocities,
                fixedNodeKeys: fixedNodeKeys,
                physicsRelevant: physicsRelevant,
                configuration: configuration
            )
        )
    }

    private static func uuid(_ value: Int) -> UUID {
        let suffix = String(format: "%012X", value)
        return UUID(
            uuidString: "00000000-0000-0000-0000-\(suffix)"
        )!
    }
}
