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

        if let relevant {
            for node in input.nodes where !relevant.contains(node.key) {
                velocities[node.key] = .zero
            }
        }

        var pairCount = 0

        for i in 0..<simulatedNodes.count {
            let firstKey = simulatedNodes[i].key
            guard let firstPosition = positions[firstKey] else { continue }

            if (i + 1) >= simulatedNodes.count { continue }
            for j in (i + 1)..<simulatedNodes.count {
                let secondKey = simulatedNodes[j].key
                guard let secondPosition = positions[secondKey] else { continue }
                pairCount += 1

                let dx = firstPosition.x - secondPosition.x
                let dy = firstPosition.y - secondPosition.y
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
                    let normalX = distance > 0.01 ? dx / distance : 1
                    let normalY = distance > 0.01 ? dy / distance : 0
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
                simulatedNodeCount: simulatedNodes.count,
                pairCount: pairCount,
                springCount: springCount
            )
        )
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
