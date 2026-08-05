//
//  GraphPhysicsRuntimeState.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// The only dynamic physics value allowed to cross into SwiftUI.
///
/// Storage stays contiguous while it crosses the actor boundary. The
/// Main-Actor adapter materializes the dictionary exactly once, immediately
/// before committing a relevant snapshot to the view state.
nonisolated struct GraphPhysicsPositionSnapshot:
    Equatable,
    Sendable
{
    let graphID: UUID?
    let identity: GraphPhysicsRuntimeIdentity
    let commandRevision: UInt64
    let snapshotRevision: UInt64
    let orderedNodeKeys: [NodeKey]
    let positions: [CGPoint]
    let positionPresence: [Bool]

    var positionsByNodeKey: [NodeKey: CGPoint] {
        var result: [NodeKey: CGPoint] = [:]
        result.reserveCapacity(orderedNodeKeys.count)
        for index in orderedNodeKeys.indices
        where positionPresence.indices.contains(index)
            && positionPresence[index]
            && positions.indices.contains(index) {
            result[orderedNodeKeys[index]] = positions[index]
        }
        return result
    }
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
    case memoryPressure
}

nonisolated struct GraphPhysicsSchedulingToken:
    Equatable,
    Hashable,
    Sendable
{
    let lifecycleGeneration: UInt64
    let sequence: UInt64
}

/// Diagnostic counters are actor-owned. They contain no graph content.
nonisolated struct GraphPhysicsRuntimeMetrics:
    Equatable,
    Sendable
{
    var engineTickCount = 0
    var positionCommitCount = 0
    var skippedCommitCount = 0
    /// Kept as a migration assertion: this must remain zero.
    var velocityCommitCount = 0
    var forcedCommitCount = 0
    var activeTickCount = 0
    var settlingTickCount = 0
    var quietTickCount = 0
    var sleepCount = 0
    var wakeCount = 0
    var pauseCount = 0
    var resumeCount = 0
    var graphSwitchCount = 0
    var memoryPressureCount = 0
    var coalescedSnapshotCount = 0
    var droppedSnapshotCount = 0
    var workspaceFullResetCount = 0
    var workspaceReuseCount = 0
    var externalResynchronizationCount = 0
    var maximumSimultaneouslyScheduledTickCount = 0
    var totalTheoreticalExactPairCount = 0
    var totalExactCheckedNodePairCount = 0
    var totalSpringCount = 0
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
    let commandRevision: UInt64
}

/// Full internal state exists only for deterministic tests and diagnostics.
/// It is never accepted by GraphPhysicsRuntime's SwiftUI commit boundary.
nonisolated struct GraphPhysicsSimulationDebugSnapshot:
    Equatable,
    Sendable
{
    let positions: [NodeKey: CGPoint]
    let velocities: [NodeKey: CGVector]
    let indexByNodeKey: [NodeKey: Int]
    let state: GraphPhysicsRuntimeState
    let metrics: GraphPhysicsRuntimeMetrics
    let workspaceCapacity:
        GraphPhysicsWorkspaceCapacitySnapshot
}

nonisolated struct GraphPhysicsSimulationCommand: Sendable {
    let input: GraphPhysicsRuntimeInput
    let identity: GraphPhysicsRuntimeIdentity
    let externalPositions: [NodeKey: CGPoint]
    let initialVelocities: [NodeKey: CGVector]
    let simulationAllowed: Bool
    let reason: GraphPhysicsRuntimeWakeReason
    let commandRevision: UInt64
}

nonisolated protocol GraphPhysicsRuntimeClock: Sendable {
    func sleep(for interval: TimeInterval) async throws
}

nonisolated struct ContinuousGraphPhysicsRuntimeClock:
    GraphPhysicsRuntimeClock
{
    func sleep(for interval: TimeInterval) async throws {
        try await ContinuousClock().sleep(
            for: .seconds(interval)
        )
    }
}
