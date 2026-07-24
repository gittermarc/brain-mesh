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
}

/// Technical-only operation counts produced by one physics step.
///
/// These values deliberately contain no graph IDs, node IDs, labels, or other
/// user data and never feed back into the simulation.
nonisolated struct GraphPhysicsStepMetrics: Equatable, Sendable {
    let simulatedNodeCount: Int
    let pairCount: Int
    let springCount: Int
}

/// Complete value-only output of one deterministic physics step.
nonisolated struct GraphPhysicsStepResult: Equatable, Sendable {
    let positions: [NodeKey: CGPoint]
    let velocities: [NodeKey: CGVector]
    let maxSimSpeed: CGFloat
    let metrics: GraphPhysicsStepMetrics
}
