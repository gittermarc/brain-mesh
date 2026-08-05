//
//  GraphPhysicsEngine.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Pure deterministic graph-physics calculation.
///
/// The immutable convenience API retains the established test contract. The
/// actor runtime uses the prepared overload so topology resolution happens
/// only when inputs change and every tick operates on contiguous arrays.
nonisolated enum GraphPhysicsEngine {
    static func step(input: GraphPhysicsStepInput)
        -> GraphPhysicsStepResult {
        var workspace = GraphPhysicsWorkspace()
        workspace.fullReset(
            positions: input.positions,
            velocities: input.velocities
        )
        let workspaceResult = step(
            input: GraphPhysicsWorkspaceStepInput(stepInput: input),
            workspace: &workspace
        )

        // The former dictionary-based algorithm preserved input entries that
        // were outside the current node topology. Keep that immutable API
        // contract without carrying unrelated keys into the actor workspace.
        var resultPositions = input.positions
        resultPositions.merge(workspace.positions) { _, stepped in stepped }
        var resultVelocities = input.velocities
        resultVelocities.merge(workspace.velocities) { _, stepped in stepped }

        return GraphPhysicsStepResult(
            positions: resultPositions,
            velocities: resultVelocities,
            maxSimSpeed: workspaceResult.maxSimSpeed,
            metrics: workspaceResult.metrics
        )
    }

    static func step(
        input: GraphPhysicsWorkspaceStepInput,
        workspace: inout GraphPhysicsWorkspace
    ) -> GraphPhysicsWorkspaceStepResult {
        step(
            preparedInput: GraphPhysicsPreparedStepInput(input: input),
            workspace: &workspace
        )
    }

    static func step(
        preparedInput: GraphPhysicsPreparedStepInput,
        workspace: inout GraphPhysicsWorkspace
    ) -> GraphPhysicsWorkspaceStepResult {
        workspace.prepareStep(preparedInput: preparedInput)
        return stepPreparedWorkspace(
            preparedInput: preparedInput,
            workspace: &workspace
        )
    }

    /// Actor hot path. Topology, masks, and stable indices must already have
    /// been reconciled at the command boundary.
    static func stepPreparedWorkspace(
        preparedInput: GraphPhysicsPreparedStepInput,
        workspace: inout GraphPhysicsWorkspace
    ) -> GraphPhysicsWorkspaceStepResult {
        let simulatedIndices = workspace.simulationIndices
        let configuration = preparedInput.configuration
        let interactionStrategy =
            GraphPhysicsInteractionStrategySelector.strategy(
                simulatedNodeCount: simulatedIndices.count,
                configuration: configuration.interactionStrategy,
                diagnosticOverride:
                    preparedInput
                        .diagnosticInteractionStrategyOverride
            )

        if simulatedIndices.count != preparedInput.nodes.count {
            workspace.stopNonRelevantNodes()
        }

        let interactionMetrics: InteractionMetrics
        switch interactionStrategy {
        case .exactPairLoop:
            interactionMetrics = applyExactPairLoopInteractions(
                nodeIndices: simulatedIndices,
                orderedNodeKeys: preparedInput.orderedNodeKeys,
                configuration: configuration,
                workspace: &workspace
            )

        case .spatialGrid:
            interactionMetrics = applySpatialGridInteractions(
                orderedNodeKeys: preparedInput.orderedNodeKeys,
                configuration: configuration,
                workspace: &workspace
            )
        }

        var springCount = 0
        for edge in preparedInput.edges {
            guard let firstPosition = workspace.position(
                    at: edge.firstIndex
                  ),
                  let secondPosition = workspace.position(
                    at: edge.secondIndex
                  ) else {
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
                at: edge.firstIndex,
                dx: forceX,
                dy: forceY
            )
            workspace.addVelocity(
                at: edge.secondIndex,
                dx: -forceX,
                dy: -forceY
            )
        }

        var maxSimSpeed: CGFloat = 0
        for nodeIndex in simulatedIndices {
            if workspace.isFixed(at: nodeIndex) {
                workspace.setVelocity(.zero, at: nodeIndex)
                continue
            }

            var velocity = workspace.velocity(at: nodeIndex)
            velocity.dx *= configuration.damping
            velocity.dy *= configuration.damping

            let speed = sqrt(
                velocity.dx * velocity.dx
                    + velocity.dy * velocity.dy
            )
            if speed > configuration.maximumSpeed {
                velocity.dx =
                    velocity.dx / speed * configuration.maximumSpeed
                velocity.dy =
                    velocity.dy / speed * configuration.maximumSpeed
            }

            let clampedSpeed = sqrt(
                velocity.dx * velocity.dx
                    + velocity.dy * velocity.dy
            )
            maxSimSpeed = max(maxSimSpeed, clampedSpeed)

            var position = workspace.position(at: nodeIndex) ?? .zero
            position.x += velocity.dx
            position.y += velocity.dy

            workspace.setPosition(position, at: nodeIndex)
            workspace.setVelocity(velocity, at: nodeIndex)
        }

        return GraphPhysicsWorkspaceStepResult(
            maxSimSpeed: maxSimSpeed,
            metrics: GraphPhysicsStepMetrics(
                interactionStrategy: interactionStrategy,
                theoreticalExactPairCount:
                    GraphPhysicsStepMetrics.theoreticalPairCount(
                        simulatedIndices.count
                    ),
                exactCheckedNodePairCount:
                    interactionMetrics.exactCheckedNodePairCount,
                occupiedGridCellCount:
                    interactionMetrics.occupiedGridCellCount,
                neighboringCellPairCount:
                    interactionMetrics.neighboringCellPairCount,
                approximatedDistantCellPairCount:
                    interactionMetrics
                        .approximatedDistantCellPairCount,
                simulatedNodeCount: simulatedIndices.count,
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
        nodeIndices: [Int],
        orderedNodeKeys: [NodeKey],
        configuration: GraphPhysicsConfiguration,
        workspace: inout GraphPhysicsWorkspace
    ) -> InteractionMetrics {
        var pairCount = 0

        // Calculation and iteration order intentionally match the extracted
        // reference engine. Only key lookup has been replaced by stable index
        // access.
        for firstOffset in nodeIndices.indices {
            let firstIndex = nodeIndices[firstOffset]
            guard let firstPosition = workspace.position(
                    at: firstIndex
                  ) else {
                continue
            }

            let secondStart = firstOffset + 1
            guard secondStart < nodeIndices.count else { continue }
            for secondOffset in secondStart..<nodeIndices.count {
                let secondIndex = nodeIndices[secondOffset]
                guard let secondPosition = workspace.position(
                        at: secondIndex
                      ) else {
                    continue
                }
                pairCount += 1

                applyExactPairInteraction(
                    firstIndex: firstIndex,
                    firstPosition: firstPosition,
                    secondIndex: secondIndex,
                    secondPosition: secondPosition,
                    orderedNodeKeys: orderedNodeKeys,
                    configuration: configuration,
                    workspace: &workspace
                )
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
        orderedNodeKeys: [NodeKey],
        configuration: GraphPhysicsConfiguration,
        workspace: inout GraphPhysicsWorkspace
    ) -> InteractionMetrics {
        workspace.prepareSpatialGrid(
            configuration: configuration.spatialGrid
        )
        let cellCount = workspace.gridCellCount
        var exactCheckedNodePairCount = 0
        var neighboringCellPairCount = 0
        var approximatedDistantCellPairCount = 0

        for firstCellIndex in 0..<cellCount {
            let firstCoordinate = workspace.gridCoordinate(
                at: firstCellIndex
            )
            let firstNodeCount = workspace.gridNodeCount(
                at: firstCellIndex
            )

            if firstNodeCount >= 2 {
                for firstOffset in 0..<(firstNodeCount - 1) {
                    let firstNodeIndex = workspace.gridNodeIndex(
                        at: firstCellIndex,
                        offset: firstOffset
                    )
                    guard let firstPosition = workspace.position(
                            at: firstNodeIndex
                          ) else {
                        continue
                    }
                    for secondOffset in
                        (firstOffset + 1)..<firstNodeCount {
                        let secondNodeIndex = workspace.gridNodeIndex(
                            at: firstCellIndex,
                            offset: secondOffset
                        )
                        guard let secondPosition = workspace.position(
                                at: secondNodeIndex
                              ) else {
                            continue
                        }
                        exactCheckedNodePairCount += 1
                        applyExactPairInteraction(
                            firstIndex: firstNodeIndex,
                            firstPosition: firstPosition,
                            secondIndex: secondNodeIndex,
                            secondPosition: secondPosition,
                            orderedNodeKeys: orderedNodeKeys,
                            configuration: configuration,
                            workspace: &workspace
                        )
                    }
                }
            }

            let secondCellStart = firstCellIndex + 1
            guard secondCellStart < cellCount else { continue }

            for secondCellIndex in secondCellStart..<cellCount {
                let secondCoordinate = workspace.gridCoordinate(
                    at: secondCellIndex
                )

                if firstCoordinate.isImmediatelyNeighboring(
                    secondCoordinate
                ) {
                    neighboringCellPairCount += 1
                    let secondNodeCount = workspace.gridNodeCount(
                        at: secondCellIndex
                    )
                    for firstOffset in 0..<firstNodeCount {
                        let firstNodeIndex = workspace.gridNodeIndex(
                            at: firstCellIndex,
                            offset: firstOffset
                        )
                        guard let firstPosition = workspace.position(
                                at: firstNodeIndex
                              ) else {
                            continue
                        }
                        for secondOffset in 0..<secondNodeCount {
                            let secondNodeIndex = workspace.gridNodeIndex(
                                at: secondCellIndex,
                                offset: secondOffset
                            )
                            guard let secondPosition = workspace.position(
                                    at: secondNodeIndex
                                  ) else {
                                continue
                            }
                            exactCheckedNodePairCount += 1
                            applyExactPairInteraction(
                                firstIndex: firstNodeIndex,
                                firstPosition: firstPosition,
                                secondIndex: secondNodeIndex,
                                secondPosition: secondPosition,
                                orderedNodeKeys: orderedNodeKeys,
                                configuration: configuration,
                                workspace: &workspace
                            )
                        }
                    }
                } else {
                    approximatedDistantCellPairCount += 1
                    accumulateDistantCellRepulsion(
                        firstCellIndex: firstCellIndex,
                        secondCellIndex: secondCellIndex,
                        configuration: configuration,
                        workspace: &workspace
                    )
                }
            }
        }

        // Distant contributions are accumulated by contiguous cell index and
        // then applied once to every movable node in that cell.
        for cellIndex in 0..<cellCount {
            let velocity = workspace.distantVelocity(at: cellIndex)
            let nodeCount = workspace.gridNodeCount(at: cellIndex)
            for offset in 0..<nodeCount {
                workspace.addVelocity(
                    at: workspace.gridNodeIndex(
                        at: cellIndex,
                        offset: offset
                    ),
                    dx: velocity.dx,
                    dy: velocity.dy
                )
            }
        }

        return InteractionMetrics(
            exactCheckedNodePairCount:
                exactCheckedNodePairCount,
            occupiedGridCellCount: cellCount,
            neighboringCellPairCount:
                neighboringCellPairCount,
            approximatedDistantCellPairCount:
                approximatedDistantCellPairCount
        )
    }

    private static func applyExactPairInteraction(
        firstIndex: Int,
        firstPosition: CGPoint,
        secondIndex: Int,
        secondPosition: CGPoint,
        orderedNodeKeys: [NodeKey],
        configuration: GraphPhysicsConfiguration,
        workspace: inout GraphPhysicsWorkspace
    ) {
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
            at: firstIndex,
            dx: repulsionX,
            dy: repulsionY
        )
        workspace.addVelocity(
            at: secondIndex,
            dx: -repulsionX,
            dy: -repulsionY
        )

        let minimumDistance = radius(
            for: orderedNodeKeys[firstIndex],
            configuration: configuration
        ) + radius(
            for: orderedNodeKeys[secondIndex],
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
                at: firstIndex,
                dx: collisionX,
                dy: collisionY
            )
            workspace.addVelocity(
                at: secondIndex,
                dx: -collisionX,
                dy: -collisionY
            )
        }
    }

    private static func accumulateDistantCellRepulsion(
        firstCellIndex: Int,
        secondCellIndex: Int,
        configuration: GraphPhysicsConfiguration,
        workspace: inout GraphPhysicsWorkspace
    ) {
        let first = workspace.gridAggregate(at: firstCellIndex)
        let second = workspace.gridAggregate(at: secondCellIndex)
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
            forCellAt: firstCellIndex
        )
        workspace.accumulateDistantVelocity(
            interaction.secondCellVelocityPerMovableNode,
            forCellAt: secondCellIndex
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
