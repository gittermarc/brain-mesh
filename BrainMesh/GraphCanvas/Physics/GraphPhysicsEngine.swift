//
//  GraphPhysicsEngine.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Pure, deterministic graph-physics calculation.
///
/// The engine owns no lifecycle, timer, view, or mutable global state. The
/// calculation order intentionally matches the former
/// `GraphCanvasView.stepSimulation()` implementation.
nonisolated enum GraphPhysicsEngine {
    static func step(input: GraphPhysicsStepInput) -> GraphPhysicsStepResult {
        let configuration = input.configuration
        var positions = input.positions
        var velocities = input.velocities
        let relevant = input.physicsRelevant
        let simulatedNodes = relevant == nil
            ? input.nodes
            : input.nodes.filter { relevant!.contains($0.key) }
        let interactionStrategy =
            GraphPhysicsInteractionStrategySelector.strategy(
                simulatedNodeCount: simulatedNodes.count,
                configuration: configuration.interactionStrategy,
                diagnosticOverride:
                    input.diagnosticInteractionStrategyOverride
            )

        if let relevant {
            for node in input.nodes where !relevant.contains(node.key) {
                velocities[node.key] = .zero
            }
        }

        let interactionMetrics: InteractionMetrics

        switch interactionStrategy {
        case .exactPairLoop:
            var pairCount = 0

            // This loop and its calculation order intentionally remain
            // identical to the engine extracted in PR 12.
            for i in 0..<simulatedNodes.count {
                let firstKey = simulatedNodes[i].key
                guard let firstPosition = positions[firstKey] else {
                    continue
                }

                if (i + 1) >= simulatedNodes.count { continue }
                for j in (i + 1)..<simulatedNodes.count {
                    let secondKey = simulatedNodes[j].key
                    guard let secondPosition = positions[secondKey] else {
                        continue
                    }
                    pairCount += 1

                    let dx = firstPosition.x - secondPosition.x
                    let dy = firstPosition.y - secondPosition.y
                    let distanceSquared = max(
                        dx * dx + dy * dy,
                        configuration.minimumPairDistanceSquared
                    )
                    let distance = sqrt(distanceSquared)

                    let repulsionForce =
                        configuration.repulsion / distanceSquared
                    let repulsionX =
                        dx * repulsionForce * configuration.repulsionScale
                    let repulsionY =
                        dy * repulsionForce * configuration.repulsionScale
                    addVelocity(
                        firstKey,
                        dx: repulsionX,
                        dy: repulsionY,
                        fixedNodeKeys: input.fixedNodeKeys,
                        velocities: &velocities
                    )
                    addVelocity(
                        secondKey,
                        dx: -repulsionX,
                        dy: -repulsionY,
                        fixedNodeKeys: input.fixedNodeKeys,
                        velocities: &velocities
                    )

                    let minimumDistance = radius(
                        for: firstKey,
                        configuration: configuration
                    ) + radius(
                        for: secondKey,
                        configuration: configuration
                    ) + configuration.collisionPadding

                    if distance < minimumDistance {
                        let overlap = minimumDistance - distance
                        let normalX =
                            distance > 0.01 ? dx / distance : 1
                        let normalY =
                            distance > 0.01 ? dy / distance : 0
                        let collisionX =
                            normalX * overlap * configuration.collisionStrength
                        let collisionY =
                            normalY * overlap * configuration.collisionStrength
                        addVelocity(
                            firstKey,
                            dx: collisionX,
                            dy: collisionY,
                            fixedNodeKeys: input.fixedNodeKeys,
                            velocities: &velocities
                        )
                        addVelocity(
                            secondKey,
                            dx: -collisionX,
                            dy: -collisionY,
                            fixedNodeKeys: input.fixedNodeKeys,
                            velocities: &velocities
                        )
                    }
                }
            }

            interactionMetrics = InteractionMetrics(
                exactCheckedNodePairCount: pairCount,
                occupiedGridCellCount: 0,
                neighboringCellPairCount: 0,
                approximatedDistantCellPairCount: 0
            )

        case .spatialGrid:
            interactionMetrics = applySpatialGridInteractions(
                nodes: simulatedNodes,
                positions: positions,
                fixedNodeKeys: input.fixedNodeKeys,
                configuration: configuration,
                velocities: &velocities
            )
        }

        var springCount = 0

        for edge in input.edges {
            if let relevant {
                if !relevant.contains(edge.a) || !relevant.contains(edge.b) {
                    continue
                }
            }
            guard let firstPosition = positions[edge.a],
                  let secondPosition = positions[edge.b] else {
                continue
            }
            springCount += 1

            let dx = secondPosition.x - firstPosition.x
            let dy = secondPosition.y - firstPosition.y
            let distance = max(
                sqrt(dx * dx + dy * dy),
                configuration.minimumSpringDistance
            )

            let spring = edge.type == .containment
                ? configuration.containmentSpring
                : configuration.linkSpring
            let restDistance = edge.type == .containment
                ? configuration.containmentRestDistance
                : configuration.linkRestDistance

            let difference = distance - restDistance
            let forceX = dx / distance * difference * spring
            let forceY = dy / distance * difference * spring

            addVelocity(
                edge.a,
                dx: forceX,
                dy: forceY,
                fixedNodeKeys: input.fixedNodeKeys,
                velocities: &velocities
            )
            addVelocity(
                edge.b,
                dx: -forceX,
                dy: -forceY,
                fixedNodeKeys: input.fixedNodeKeys,
                velocities: &velocities
            )
        }

        var maxSimSpeed: CGFloat = 0

        for node in simulatedNodes {
            let key = node.key

            if input.fixedNodeKeys.contains(key) {
                velocities[key] = .zero
                continue
            }

            var velocity = velocities[key, default: .zero]
            velocity.dx *= configuration.damping
            velocity.dy *= configuration.damping

            let speed = sqrt(
                velocity.dx * velocity.dx + velocity.dy * velocity.dy
            )
            if speed > configuration.maximumSpeed {
                velocity.dx =
                    velocity.dx / speed * configuration.maximumSpeed
                velocity.dy =
                    velocity.dy / speed * configuration.maximumSpeed
            }

            let clampedSpeed = sqrt(
                velocity.dx * velocity.dx + velocity.dy * velocity.dy
            )
            if clampedSpeed > maxSimSpeed {
                maxSimSpeed = clampedSpeed
            }

            var position = positions[key, default: .zero]
            position.x += velocity.dx
            position.y += velocity.dy

            positions[key] = position
            velocities[key] = velocity
        }

        return GraphPhysicsStepResult(
            positions: positions,
            velocities: velocities,
            maxSimSpeed: maxSimSpeed,
            metrics: GraphPhysicsStepMetrics(
                interactionStrategy: interactionStrategy,
                theoreticalExactPairCount:
                    GraphPhysicsStepMetrics.theoreticalPairCount(
                        simulatedNodes.count
                    ),
                exactCheckedNodePairCount:
                    interactionMetrics.exactCheckedNodePairCount,
                occupiedGridCellCount:
                    interactionMetrics.occupiedGridCellCount,
                neighboringCellPairCount:
                    interactionMetrics.neighboringCellPairCount,
                approximatedDistantCellPairCount:
                    interactionMetrics.approximatedDistantCellPairCount,
                simulatedNodeCount: simulatedNodes.count,
                springCount: springCount
            )
        )
    }

    private struct InteractionMetrics {
        let exactCheckedNodePairCount: Int
        let occupiedGridCellCount: Int
        let neighboringCellPairCount: Int
        let approximatedDistantCellPairCount: Int
    }

    private static func applySpatialGridInteractions(
        nodes: [GraphNode],
        positions: [NodeKey: CGPoint],
        fixedNodeKeys: Set<NodeKey>,
        configuration: GraphPhysicsConfiguration,
        velocities: inout [NodeKey: CGVector]
    ) -> InteractionMetrics {
        let grid = GraphPhysicsSpatialGrid(
            nodes: nodes,
            positions: positions,
            configuration: configuration.spatialGrid
        )
        let cells = grid.cells
        var exactCheckedNodePairCount = 0
        var neighboringCellPairCount = 0
        var approximatedDistantCellPairCount = 0
        var distantVelocityByCell:
            [GraphPhysicsGridCoordinate: CGVector] = [:]
        distantVelocityByCell.reserveCapacity(cells.count)

        for cellIndex in cells.indices {
            let firstCell = cells[cellIndex]

            if firstCell.nodes.count >= 2 {
                for firstNodeIndex in 0..<(firstCell.nodes.count - 1) {
                    let firstNode = firstCell.nodes[firstNodeIndex]
                    for secondNodeIndex in
                        (firstNodeIndex + 1)..<firstCell.nodes.count {
                        let secondNode = firstCell.nodes[secondNodeIndex]
                        exactCheckedNodePairCount += 1
                        applyExactPairInteraction(
                            firstNode,
                            secondNode,
                            fixedNodeKeys: fixedNodeKeys,
                            configuration: configuration,
                            velocities: &velocities
                        )
                    }
                }
            }

            guard cellIndex < cells.count - 1 else { continue }

            for secondCellIndex in (cellIndex + 1)..<cells.count {
                let secondCell = cells[secondCellIndex]

                if firstCell.coordinate.isImmediatelyNeighboring(
                    secondCell.coordinate
                ) {
                    neighboringCellPairCount += 1
                    for firstNode in firstCell.nodes {
                        for secondNode in secondCell.nodes {
                            exactCheckedNodePairCount += 1
                            applyExactPairInteraction(
                                firstNode,
                                secondNode,
                                fixedNodeKeys: fixedNodeKeys,
                                configuration: configuration,
                                velocities: &velocities
                            )
                        }
                    }
                } else {
                    approximatedDistantCellPairCount += 1
                    accumulateDistantCellRepulsion(
                        firstCell,
                        secondCell,
                        configuration: configuration,
                        velocityByCell: &distantVelocityByCell
                    )
                }
            }
        }

        // Every distant cell-pair contribution is accumulated first. Each
        // movable node receives its cell delta exactly once per tick.
        for cell in cells {
            guard let velocity = distantVelocityByCell[cell.coordinate]
            else {
                continue
            }
            for node in cell.nodes {
                addVelocity(
                    node.key,
                    dx: velocity.dx,
                    dy: velocity.dy,
                    fixedNodeKeys: fixedNodeKeys,
                    velocities: &velocities
                )
            }
        }

        return InteractionMetrics(
            exactCheckedNodePairCount: exactCheckedNodePairCount,
            occupiedGridCellCount: cells.count,
            neighboringCellPairCount: neighboringCellPairCount,
            approximatedDistantCellPairCount:
                approximatedDistantCellPairCount
        )
    }

    private static func applyExactPairInteraction(
        _ firstNode: GraphPhysicsGridNode,
        _ secondNode: GraphPhysicsGridNode,
        fixedNodeKeys: Set<NodeKey>,
        configuration: GraphPhysicsConfiguration,
        velocities: inout [NodeKey: CGVector]
    ) {
        let dx = firstNode.position.x - secondNode.position.x
        let dy = firstNode.position.y - secondNode.position.y
        let distanceSquared = max(
            dx * dx + dy * dy,
            configuration.minimumPairDistanceSquared
        )
        let distance = sqrt(distanceSquared)

        let repulsionForce = configuration.repulsion / distanceSquared
        let repulsionX =
            dx * repulsionForce * configuration.repulsionScale
        let repulsionY =
            dy * repulsionForce * configuration.repulsionScale
        addVelocity(
            firstNode.key,
            dx: repulsionX,
            dy: repulsionY,
            fixedNodeKeys: fixedNodeKeys,
            velocities: &velocities
        )
        addVelocity(
            secondNode.key,
            dx: -repulsionX,
            dy: -repulsionY,
            fixedNodeKeys: fixedNodeKeys,
            velocities: &velocities
        )

        let minimumDistance = radius(
            for: firstNode.key,
            configuration: configuration
        ) + radius(
            for: secondNode.key,
            configuration: configuration
        ) + configuration.collisionPadding

        if distance < minimumDistance {
            let overlap = minimumDistance - distance
            let normalX = distance > 0.01 ? dx / distance : 1
            let normalY = distance > 0.01 ? dy / distance : 0
            let collisionX =
                normalX * overlap * configuration.collisionStrength
            let collisionY =
                normalY * overlap * configuration.collisionStrength
            addVelocity(
                firstNode.key,
                dx: collisionX,
                dy: collisionY,
                fixedNodeKeys: fixedNodeKeys,
                velocities: &velocities
            )
            addVelocity(
                secondNode.key,
                dx: -collisionX,
                dy: -collisionY,
                fixedNodeKeys: fixedNodeKeys,
                velocities: &velocities
            )
        }
    }

    private static func accumulateDistantCellRepulsion(
        _ firstCell: GraphPhysicsGridCell,
        _ secondCell: GraphPhysicsGridCell,
        configuration: GraphPhysicsConfiguration,
        velocityByCell:
            inout [GraphPhysicsGridCoordinate: CGVector]
    ) {
        let firstCount = firstCell.aggregate.positionedNodeCount
        let secondCount = secondCell.aggregate.positionedNodeCount
        guard firstCount > 0, secondCount > 0 else { return }

        let interaction = GraphPhysicsDistantCellRepulsion.calculate(
            first: firstCell.aggregate,
            second: secondCell.aggregate,
            configuration: configuration
        )

        velocityByCell[firstCell.coordinate, default: .zero].dx +=
            interaction.firstCellVelocityPerMovableNode.dx
        velocityByCell[firstCell.coordinate, default: .zero].dy +=
            interaction.firstCellVelocityPerMovableNode.dy
        velocityByCell[secondCell.coordinate, default: .zero].dx +=
            interaction.secondCellVelocityPerMovableNode.dx
        velocityByCell[secondCell.coordinate, default: .zero].dy +=
            interaction.secondCellVelocityPerMovableNode.dy
    }

    private static func addVelocity(
        _ key: NodeKey,
        dx: CGFloat,
        dy: CGFloat,
        fixedNodeKeys: Set<NodeKey>,
        velocities: inout [NodeKey: CGVector]
    ) {
        guard !fixedNodeKeys.contains(key) else { return }
        velocities[key, default: .zero].dx += dx
        velocities[key, default: .zero].dy += dy
    }

    private static func radius(
        for key: NodeKey,
        configuration: GraphPhysicsConfiguration
    ) -> CGFloat {
        switch key.kind {
        case .entity:
            return configuration.entityRadius
        case .attribute:
            return configuration.attributeRadius
        }
    }
}
