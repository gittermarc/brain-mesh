//
//  GraphPhysicsEngine.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Pure, deterministic graph-physics calculation.
///
/// The convenience API keeps the immutable PR-12 contract. The workspace API
/// executes the same formulas and ordering while allowing the adaptive runtime
/// to retain mutable buffers between ticks.
nonisolated enum GraphPhysicsEngine {
    static func step(input: GraphPhysicsStepInput) -> GraphPhysicsStepResult {
        var workspace = GraphPhysicsWorkspace()
        workspace.fullReset(
            positions: input.positions,
            velocities: input.velocities
        )
        let workspaceResult = step(
            input: GraphPhysicsWorkspaceStepInput(stepInput: input),
            workspace: &workspace
        )

        return GraphPhysicsStepResult(
            positions: workspace.positions,
            velocities: workspace.velocities,
            maxSimSpeed: workspaceResult.maxSimSpeed,
            metrics: workspaceResult.metrics
        )
    }

    static func step(
        input: GraphPhysicsWorkspaceStepInput,
        workspace: inout GraphPhysicsWorkspace
    ) -> GraphPhysicsWorkspaceStepResult {
        let configuration = input.configuration
        workspace.prepareStep(
            nodes: input.nodes,
            fixedNodeKeys: input.fixedNodeKeys,
            physicsRelevant: input.physicsRelevant
        )
        let simulatedNodes = workspace.simulatedNodes
        let interactionStrategy =
            GraphPhysicsInteractionStrategySelector.strategy(
                simulatedNodeCount: simulatedNodes.count,
                configuration: configuration.interactionStrategy,
                diagnosticOverride:
                    input.diagnosticInteractionStrategyOverride
            )

        if let relevant = input.physicsRelevant {
            workspace.stopNonRelevantNodes(
                allNodes: input.nodes,
                physicsRelevant: relevant
            )
        }

        let interactionMetrics: InteractionMetrics

        switch interactionStrategy {
        case .exactPairLoop:
            interactionMetrics = applyExactPairLoopInteractions(
                nodes: simulatedNodes,
                configuration: configuration,
                workspace: &workspace
            )

        case .spatialGrid:
            interactionMetrics = applySpatialGridInteractions(
                configuration: configuration,
                workspace: &workspace
            )
        }

        var springCount = 0

        for edge in input.edges {
            if let relevant = input.physicsRelevant {
                if !relevant.contains(edge.a)
                    || !relevant.contains(edge.b) {
                    continue
                }
            }
            guard let firstPosition = workspace.positions[edge.a],
                  let secondPosition = workspace.positions[edge.b] else {
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

            workspace.addVelocity(
                edge.a,
                dx: forceX,
                dy: forceY
            )
            workspace.addVelocity(
                edge.b,
                dx: -forceX,
                dy: -forceY
            )
        }

        var maxSimSpeed: CGFloat = 0

        for node in simulatedNodes {
            let key = node.key

            if workspace.fixedNodeKeys.contains(key) {
                workspace.setVelocity(.zero, for: key)
                continue
            }

            var velocity = workspace.velocities[key, default: .zero]
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

            var position = workspace.positions[key, default: .zero]
            position.x += velocity.dx
            position.y += velocity.dy

            workspace.setPosition(position, for: key)
            workspace.setVelocity(velocity, for: key)
        }

        return GraphPhysicsWorkspaceStepResult(
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

    private static func applyExactPairLoopInteractions(
        nodes: [GraphNode],
        configuration: GraphPhysicsConfiguration,
        workspace: inout GraphPhysicsWorkspace
    ) -> InteractionMetrics {
        var pairCount = 0

        // This loop and its calculation order intentionally remain identical
        // to the engine extracted in PR 12.
        for i in 0..<nodes.count {
            let firstKey = nodes[i].key
            guard let firstPosition = workspace.positions[firstKey] else {
                continue
            }

            if (i + 1) >= nodes.count { continue }
            for j in (i + 1)..<nodes.count {
                let secondKey = nodes[j].key
                guard let secondPosition =
                        workspace.positions[secondKey] else {
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
                workspace.addVelocity(
                    firstKey,
                    dx: repulsionX,
                    dy: repulsionY
                )
                workspace.addVelocity(
                    secondKey,
                    dx: -repulsionX,
                    dy: -repulsionY
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
                        normalX
                        * overlap
                        * configuration.collisionStrength
                    let collisionY =
                        normalY
                        * overlap
                        * configuration.collisionStrength
                    workspace.addVelocity(
                        firstKey,
                        dx: collisionX,
                        dy: collisionY
                    )
                    workspace.addVelocity(
                        secondKey,
                        dx: -collisionX,
                        dy: -collisionY
                    )
                }
            }
        }

        return InteractionMetrics(
            exactCheckedNodePairCount: pairCount,
            occupiedGridCellCount: 0,
            neighboringCellPairCount: 0,
            approximatedDistantCellPairCount: 0
        )
    }

    private static func applySpatialGridInteractions(
        configuration: GraphPhysicsConfiguration,
        workspace: inout GraphPhysicsWorkspace
    ) -> InteractionMetrics {
        workspace.prepareSpatialGrid(
            configuration: configuration.spatialGrid
        )
        let coordinates = workspace.activeGridCoordinates
        let aggregates = workspace.gridAggregates
        var exactCheckedNodePairCount = 0
        var neighboringCellPairCount = 0
        var approximatedDistantCellPairCount = 0

        for cellIndex in coordinates.indices {
            let firstCoordinate = coordinates[cellIndex]
            let firstNodes = workspace.gridNodes(
                at: firstCoordinate
            )

            if firstNodes.count >= 2 {
                for firstNodeIndex in 0..<(firstNodes.count - 1) {
                    let firstNode = firstNodes[firstNodeIndex]
                    for secondNodeIndex in
                        (firstNodeIndex + 1)..<firstNodes.count {
                        let secondNode = firstNodes[secondNodeIndex]
                        exactCheckedNodePairCount += 1
                        applyExactPairInteraction(
                            firstNode,
                            secondNode,
                            configuration: configuration,
                            workspace: &workspace
                        )
                    }
                }
            }

            guard cellIndex < coordinates.count - 1 else {
                continue
            }

            for secondCellIndex in
                (cellIndex + 1)..<coordinates.count {
                let secondCoordinate =
                    coordinates[secondCellIndex]

                if firstCoordinate.isImmediatelyNeighboring(
                    secondCoordinate
                ) {
                    neighboringCellPairCount += 1
                    let secondNodes = workspace.gridNodes(
                        at: secondCoordinate
                    )
                    for firstNode in firstNodes {
                        for secondNode in secondNodes {
                            exactCheckedNodePairCount += 1
                            applyExactPairInteraction(
                                firstNode,
                                secondNode,
                                configuration: configuration,
                                workspace: &workspace
                            )
                        }
                    }
                } else {
                    approximatedDistantCellPairCount += 1
                    accumulateDistantCellRepulsion(
                        first: aggregates[cellIndex],
                        second: aggregates[secondCellIndex],
                        configuration: configuration,
                        workspace: &workspace
                    )
                }
            }
        }

        // Every distant cell-pair contribution is accumulated first. Each
        // movable node receives its cell delta exactly once per tick.
        for coordinate in coordinates {
            guard let velocity =
                    workspace.distantVelocityByCell[coordinate] else {
                continue
            }
            let nodes = workspace.gridNodes(at: coordinate)
            for node in nodes {
                workspace.addVelocity(
                    node.key,
                    dx: velocity.dx,
                    dy: velocity.dy
                )
            }
        }

        return InteractionMetrics(
            exactCheckedNodePairCount:
                exactCheckedNodePairCount,
            occupiedGridCellCount: coordinates.count,
            neighboringCellPairCount:
                neighboringCellPairCount,
            approximatedDistantCellPairCount:
                approximatedDistantCellPairCount
        )
    }

    private static func applyExactPairInteraction(
        _ firstNode: GraphPhysicsGridNode,
        _ secondNode: GraphPhysicsGridNode,
        configuration: GraphPhysicsConfiguration,
        workspace: inout GraphPhysicsWorkspace
    ) {
        let dx = firstNode.position.x - secondNode.position.x
        let dy = firstNode.position.y - secondNode.position.y
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
        workspace.addVelocity(
            firstNode.key,
            dx: repulsionX,
            dy: repulsionY
        )
        workspace.addVelocity(
            secondNode.key,
            dx: -repulsionX,
            dy: -repulsionY
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
            workspace.addVelocity(
                firstNode.key,
                dx: collisionX,
                dy: collisionY
            )
            workspace.addVelocity(
                secondNode.key,
                dx: -collisionX,
                dy: -collisionY
            )
        }
    }

    private static func accumulateDistantCellRepulsion(
        first: GraphPhysicsGridCellAggregate,
        second: GraphPhysicsGridCellAggregate,
        configuration: GraphPhysicsConfiguration,
        workspace: inout GraphPhysicsWorkspace
    ) {
        guard first.positionedNodeCount > 0,
              second.positionedNodeCount > 0 else {
            return
        }

        let interaction = GraphPhysicsDistantCellRepulsion.calculate(
            first: first,
            second: second,
            configuration: configuration
        )

        workspace.accumulateDistantVelocity(
            interaction.firstCellVelocityPerMovableNode,
            for: first.coordinate
        )
        workspace.accumulateDistantVelocity(
            interaction.secondCellVelocityPerMovableNode,
            for: second.coordinate
        )
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
