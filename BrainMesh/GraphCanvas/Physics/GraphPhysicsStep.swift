//
//  GraphPhysicsStep.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Complete immutable input for one deterministic physics step.
nonisolated struct GraphPhysicsStepInput: Equatable, Sendable {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let positions: [NodeKey: CGPoint]
    let velocities: [NodeKey: CGVector]
    let fixedNodeKeys: Set<NodeKey>
    let physicsRelevant: Set<NodeKey>?
    let configuration: GraphPhysicsConfiguration

    /// Internal diagnostic hook used by parity and tolerance tests.
    ///
    /// Production callers omit this value and always use deterministic
    /// node-count selection. It is deliberately not a visible canvas option.
    let diagnosticInteractionStrategyOverride:
        GraphPhysicsInteractionStrategy?

    init(
        nodes: [GraphNode],
        edges: [GraphEdge],
        positions: [NodeKey: CGPoint],
        velocities: [NodeKey: CGVector],
        fixedNodeKeys: Set<NodeKey>,
        physicsRelevant: Set<NodeKey>?,
        configuration: GraphPhysicsConfiguration,
        diagnosticInteractionStrategyOverride:
            GraphPhysicsInteractionStrategy? = nil
    ) {
        self.nodes = nodes
        self.edges = edges
        self.positions = positions
        self.velocities = velocities
        self.fixedNodeKeys = fixedNodeKeys
        self.physicsRelevant = physicsRelevant
        self.configuration = configuration
        self.diagnosticInteractionStrategyOverride =
            diagnosticInteractionStrategyOverride
    }
}

/// Technical-only operation counts produced by one physics step.
///
/// These values deliberately contain no graph IDs, node IDs, labels, or other
/// user data and never feed back into the simulation.
nonisolated struct GraphPhysicsStepMetrics: Equatable, Sendable {
    let interactionStrategy: GraphPhysicsInteractionStrategy
    let theoreticalExactPairCount: Int
    let exactCheckedNodePairCount: Int
    let occupiedGridCellCount: Int
    let neighboringCellPairCount: Int
    let approximatedDistantCellPairCount: Int
    let simulatedNodeCount: Int
    let springCount: Int

    /// Compatibility name retained for existing PR-12 instrumentation.
    var pairCount: Int {
        exactCheckedNodePairCount
    }

    init(
        interactionStrategy: GraphPhysicsInteractionStrategy,
        theoreticalExactPairCount: Int,
        exactCheckedNodePairCount: Int,
        occupiedGridCellCount: Int,
        neighboringCellPairCount: Int,
        approximatedDistantCellPairCount: Int,
        simulatedNodeCount: Int,
        springCount: Int
    ) {
        self.interactionStrategy = interactionStrategy
        self.theoreticalExactPairCount = theoreticalExactPairCount
        self.exactCheckedNodePairCount = exactCheckedNodePairCount
        self.occupiedGridCellCount = occupiedGridCellCount
        self.neighboringCellPairCount = neighboringCellPairCount
        self.approximatedDistantCellPairCount =
            approximatedDistantCellPairCount
        self.simulatedNodeCount = simulatedNodeCount
        self.springCount = springCount
    }

    /// PR-12 compatibility initializer for the exact reference implementation.
    init(
        simulatedNodeCount: Int,
        pairCount: Int,
        springCount: Int
    ) {
        self.init(
            interactionStrategy: .exactPairLoop,
            theoreticalExactPairCount: Self.theoreticalPairCount(
                simulatedNodeCount
            ),
            exactCheckedNodePairCount: pairCount,
            occupiedGridCellCount: 0,
            neighboringCellPairCount: 0,
            approximatedDistantCellPairCount: 0,
            simulatedNodeCount: simulatedNodeCount,
            springCount: springCount
        )
    }

    static func theoreticalPairCount(_ nodeCount: Int) -> Int {
        guard nodeCount > 1 else { return 0 }
        return nodeCount * (nodeCount - 1) / 2
    }
}

/// Complete value-only output of one deterministic physics step.
nonisolated struct GraphPhysicsStepResult: Equatable, Sendable {
    let positions: [NodeKey: CGPoint]
    let velocities: [NodeKey: CGVector]
    let maxSimSpeed: CGFloat
    let metrics: GraphPhysicsStepMetrics
}
