//
//  GraphPhysicsConfiguration.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Value-only tuning values for one graph-physics step.
///
/// The defaults preserve the canvas algorithm that existed before the pure
/// engine extraction. `collisionStrength` remains the only value supplied by
/// the current Inspector or view preset.
nonisolated struct GraphPhysicsConfiguration: Equatable, Sendable {
    let repulsion: CGFloat
    let linkSpring: CGFloat
    let containmentSpring: CGFloat
    let linkRestDistance: CGFloat
    let containmentRestDistance: CGFloat
    let damping: CGFloat
    let maximumSpeed: CGFloat
    let collisionPadding: CGFloat
    let entityRadius: CGFloat
    let attributeRadius: CGFloat
    let minimumPairDistanceSquared: CGFloat
    let minimumSpringDistance: CGFloat
    let repulsionScale: CGFloat
    let collisionStrength: CGFloat
    let interactionStrategy:
        GraphPhysicsInteractionStrategyConfiguration

    init(
        collisionStrength: CGFloat,
        repulsion: CGFloat = 8_800,
        linkSpring: CGFloat = 0.018,
        containmentSpring: CGFloat = 0.040,
        linkRestDistance: CGFloat = 130,
        containmentRestDistance: CGFloat = 76,
        damping: CGFloat = 0.85,
        maximumSpeed: CGFloat = 18,
        collisionPadding: CGFloat = 6,
        entityRadius: CGFloat = 22,
        attributeRadius: CGFloat = 18,
        minimumPairDistanceSquared: CGFloat = 40,
        minimumSpringDistance: CGFloat = 1,
        repulsionScale: CGFloat = 0.00002,
        interactionStrategy:
            GraphPhysicsInteractionStrategyConfiguration = .production
    ) {
        self.repulsion = repulsion
        self.linkSpring = linkSpring
        self.containmentSpring = containmentSpring
        self.linkRestDistance = linkRestDistance
        self.containmentRestDistance = containmentRestDistance
        self.damping = damping
        self.maximumSpeed = maximumSpeed
        self.collisionPadding = collisionPadding
        self.entityRadius = entityRadius
        self.attributeRadius = attributeRadius
        self.minimumPairDistanceSquared = minimumPairDistanceSquared
        self.minimumSpringDistance = minimumSpringDistance
        self.repulsionScale = repulsionScale
        self.collisionStrength = max(0, collisionStrength)
        self.interactionStrategy = interactionStrategy
    }

    var spatialGrid: GraphPhysicsSpatialGridConfiguration {
        GraphPhysicsSpatialGridConfiguration(
            physicsConfiguration: self
        )
    }
}
