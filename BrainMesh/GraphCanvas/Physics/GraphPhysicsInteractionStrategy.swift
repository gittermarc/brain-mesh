//
//  GraphPhysicsInteractionStrategy.swift
//  BrainMesh
//

import Foundation

/// Pair-interaction implementation used for one physics step.
///
/// This is a technical engine decision. It is intentionally not exposed as a
/// user-facing canvas preference.
nonisolated enum GraphPhysicsInteractionStrategy:
    String,
    Equatable,
    Sendable
{
    case exactPairLoop = "exact-pair-loop"
    case spatialGrid = "spatial-grid"
}

/// Named production boundary for selecting the pair-interaction algorithm.
nonisolated struct GraphPhysicsInteractionStrategyConfiguration:
    Equatable,
    Sendable
{
    static let production = GraphPhysicsInteractionStrategyConfiguration(
        exactPairLoopMaximumSimulatedNodeCount: 80
    )

    let exactPairLoopMaximumSimulatedNodeCount: Int

    init(exactPairLoopMaximumSimulatedNodeCount: Int) {
        self.exactPairLoopMaximumSimulatedNodeCount = max(
            0,
            exactPairLoopMaximumSimulatedNodeCount
        )
    }
}

/// Pure, deterministic selection based only on the post-spotlight node count.
nonisolated enum GraphPhysicsInteractionStrategySelector {
    static func strategy(
        simulatedNodeCount: Int,
        configuration: GraphPhysicsInteractionStrategyConfiguration,
        diagnosticOverride: GraphPhysicsInteractionStrategy? = nil
    ) -> GraphPhysicsInteractionStrategy {
        if let diagnosticOverride {
            return diagnosticOverride
        }

        return simulatedNodeCount
            <= configuration.exactPairLoopMaximumSimulatedNodeCount
            ? .exactPairLoop
            : .spatialGrid
    }
}
