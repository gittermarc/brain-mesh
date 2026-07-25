//
//  GraphPhysicsRuntimeState.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

nonisolated struct GraphPhysicsExternalState:
    Equatable,
    Sendable
{
    let positions: [NodeKey: CGPoint]
    let velocities: [NodeKey: CGVector]
}

nonisolated struct GraphPhysicsRuntimeIdentity:
    Equatable,
    Hashable,
    Sendable
{
    let graphID: UUID?
    let orderedNodeKeys: [NodeKey]
}

nonisolated struct GraphPhysicsRuntimeInput:
    Equatable,
    Sendable
{
    let graphID: UUID?
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let fixedNodeKeys: Set<NodeKey>
    let physicsRelevant: Set<NodeKey>?
    let configuration: GraphPhysicsConfiguration
    let workMode: WorkMode
    let selection: NodeKey?
    let isDragging: Bool
    let diagnosticInteractionStrategyOverride:
        GraphPhysicsInteractionStrategy?

    init(
        graphID: UUID?,
        nodes: [GraphNode],
        edges: [GraphEdge],
        fixedNodeKeys: Set<NodeKey>,
        physicsRelevant: Set<NodeKey>?,
        configuration: GraphPhysicsConfiguration,
        workMode: WorkMode,
        selection: NodeKey?,
        isDragging: Bool,
        diagnosticInteractionStrategyOverride:
            GraphPhysicsInteractionStrategy? = nil
    ) {
        self.graphID = graphID
        self.nodes = nodes
        self.edges = edges
        self.fixedNodeKeys = fixedNodeKeys
        self.physicsRelevant = physicsRelevant
        self.configuration = configuration
        self.workMode = workMode
        self.selection = selection
        self.isDragging = isDragging
        self.diagnosticInteractionStrategyOverride =
            diagnosticInteractionStrategyOverride
    }

    init(
        graphID: UUID?,
        stepInput: GraphPhysicsStepInput,
        workMode: WorkMode = .explore,
        selection: NodeKey? = nil,
        isDragging: Bool = false
    ) {
        self.init(
            graphID: graphID,
            nodes: stepInput.nodes,
            edges: stepInput.edges,
            fixedNodeKeys: stepInput.fixedNodeKeys,
            physicsRelevant: stepInput.physicsRelevant,
            configuration: stepInput.configuration,
            workMode: workMode,
            selection: selection,
            isDragging: isDragging,
            diagnosticInteractionStrategyOverride:
                stepInput.diagnosticInteractionStrategyOverride
        )
    }

    var identity: GraphPhysicsRuntimeIdentity {
        GraphPhysicsRuntimeIdentity(
            graphID: graphID,
            orderedNodeKeys: nodes.map(\.key)
        )
    }

    var workspaceStepInput: GraphPhysicsWorkspaceStepInput {
        GraphPhysicsWorkspaceStepInput(
            nodes: nodes,
            edges: edges,
            fixedNodeKeys: fixedNodeKeys,
            physicsRelevant: physicsRelevant,
            configuration: configuration,
            diagnosticInteractionStrategyOverride:
                diagnosticInteractionStrategyOverride
        )
    }
}

nonisolated enum GraphPhysicsRuntimeWakeReason:
    String,
    Equatable,
    Sendable
{
    case initial
    case simulationAllowed
    case nodeSet
    case edges
    case spotlight
    case selection
    case pinning
    case draggingStarted
    case draggingEnded
    case workMode
    case collisionStrength
    case externalState
    case graphChanged
}

nonisolated struct GraphPhysicsSchedulingToken:
    Equatable,
    Hashable,
    Sendable
{
    let lifecycleGeneration: UInt64
    let sequence: UInt64
}

nonisolated struct GraphPhysicsRuntimeMetrics:
    Equatable,
    Sendable
{
    var engineTickCount = 0
    var positionCommitCount = 0
    var skippedCommitCount = 0
    var velocityCommitCount = 0
    var forcedCommitCount = 0
    var activeTickCount = 0
    var settlingTickCount = 0
    var quietTickCount = 0
    var sleepCount = 0
    var wakeCount = 0
    var workspaceFullResetCount = 0
    var workspaceReuseCount = 0
    var externalResynchronizationCount = 0
    var maximumSimultaneouslyScheduledTickCount = 0
    var lastSleepEngineTick: Int?
    var lastStepMetrics: GraphPhysicsStepMetrics?

    var averageTicksPerUICommit: Double {
        guard positionCommitCount > 0 else { return 0 }
        return Double(engineTickCount)
            / Double(positionCommitCount)
    }
}

nonisolated struct GraphPhysicsRuntimeState:
    Equatable,
    Sendable
{
    let identity: GraphPhysicsRuntimeIdentity?
    let cadencePhase: GraphPhysicsCadencePhase
    let isRunning: Bool
    let isSleeping: Bool
    let hasScheduledTick: Bool
    let ticksSinceLastCommit: Int
    let maximumCumulativeUnpublishedPositionDelta: CGFloat
    let stableQuietSamples: Int
}
