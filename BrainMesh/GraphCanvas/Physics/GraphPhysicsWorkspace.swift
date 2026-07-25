//
//  GraphPhysicsWorkspace.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Reusable mutable storage for consecutive deterministic physics steps.
///
/// The workspace owns only technical simulation buffers. A full reset removes
/// every graph-dependent value while retaining collection capacity where the
/// standard library supports it.
nonisolated struct GraphPhysicsWorkspace: Sendable {
    private(set) var positions: [NodeKey: CGPoint] = [:]
    private(set) var velocities: [NodeKey: CGVector] = [:]
    private(set) var simulatedNodes: [GraphNode] = []
    private(set) var fixedNodeKeys: Set<NodeKey> = []

    private(set) var positionedGridNodes: [GraphPhysicsGridNode] = []
    private(set) var activeGridCoordinates:
        [GraphPhysicsGridCoordinate] = []
    private(set) var gridAggregates:
        [GraphPhysicsGridCellAggregate] = []
    private(set) var gridBuckets:
        [GraphPhysicsGridCoordinate: [GraphPhysicsGridNode]] = [:]
    private(set) var distantVelocityByCell:
        [GraphPhysicsGridCoordinate: CGVector] = [:]

    private(set) var hasSynchronizedState = false

    mutating func fullReset(
        positions newPositions: [NodeKey: CGPoint],
        velocities newVelocities: [NodeKey: CGVector]
    ) {
        removeAllSemanticContent()

        positions.reserveCapacity(newPositions.count)
        for (key, position) in newPositions {
            positions[key] = position
        }

        velocities.reserveCapacity(newVelocities.count)
        for (key, velocity) in newVelocities {
            velocities[key] = velocity
        }

        hasSynchronizedState = true
    }

    mutating func removeAllSemanticContent() {
        positions.removeAll(keepingCapacity: true)
        velocities.removeAll(keepingCapacity: true)
        simulatedNodes.removeAll(keepingCapacity: true)
        fixedNodeKeys.removeAll(keepingCapacity: true)
        positionedGridNodes.removeAll(keepingCapacity: true)
        activeGridCoordinates.removeAll(keepingCapacity: true)
        gridAggregates.removeAll(keepingCapacity: true)
        gridBuckets.removeAll(keepingCapacity: true)
        distantVelocityByCell.removeAll(keepingCapacity: true)
        hasSynchronizedState = false
    }

    mutating func prepareStep(
        nodes: [GraphNode],
        fixedNodeKeys newFixedNodeKeys: Set<NodeKey>,
        physicsRelevant: Set<NodeKey>?
    ) {
        simulatedNodes.removeAll(keepingCapacity: true)
        simulatedNodes.reserveCapacity(nodes.count)

        if let physicsRelevant {
            for node in nodes where physicsRelevant.contains(node.key) {
                simulatedNodes.append(node)
            }
        } else {
            simulatedNodes.append(contentsOf: nodes)
        }

        fixedNodeKeys.removeAll(keepingCapacity: true)
        fixedNodeKeys.reserveCapacity(newFixedNodeKeys.count)
        fixedNodeKeys.formUnion(newFixedNodeKeys)
    }

    mutating func prepareSpatialGrid(
        configuration: GraphPhysicsSpatialGridConfiguration
    ) {
        for coordinate in activeGridCoordinates {
            gridBuckets[coordinate]?.removeAll(keepingCapacity: true)
        }

        positionedGridNodes.removeAll(keepingCapacity: true)
        activeGridCoordinates.removeAll(keepingCapacity: true)
        gridAggregates.removeAll(keepingCapacity: true)
        distantVelocityByCell.removeAll(keepingCapacity: true)

        positionedGridNodes.reserveCapacity(simulatedNodes.count)
        for node in simulatedNodes {
            guard let position = positions[node.key],
                  position.x.isFinite,
                  position.y.isFinite else {
                continue
            }
            positionedGridNodes.append(
                GraphPhysicsGridNode(
                    key: node.key,
                    position: position
                )
            )
        }
        positionedGridNodes.sort {
            $0.key.identifier < $1.key.identifier
        }

        gridBuckets.reserveCapacity(positionedGridNodes.count)
        activeGridCoordinates.reserveCapacity(positionedGridNodes.count)

        for node in positionedGridNodes {
            let coordinate = GraphPhysicsGridCoordinate(
                position: node.position,
                cellSize: configuration.cellSize
            )

            if gridBuckets[coordinate] == nil {
                gridBuckets[coordinate] = []
            }
            if gridBuckets[coordinate]?.isEmpty == true {
                activeGridCoordinates.append(coordinate)
            }
            gridBuckets[coordinate, default: []].append(node)
        }

        activeGridCoordinates.sort()
        gridAggregates.reserveCapacity(activeGridCoordinates.count)
        distantVelocityByCell.reserveCapacity(activeGridCoordinates.count)

        for coordinate in activeGridCoordinates {
            let nodes = gridBuckets[coordinate, default: []]
            var x: CGFloat = 0
            var y: CGFloat = 0
            for node in nodes {
                x += node.position.x
                y += node.position.y
            }

            let count = nodes.count
            let centroid: CGPoint
            if count > 0 {
                let divisor = CGFloat(count)
                centroid = CGPoint(
                    x: x / divisor,
                    y: y / divisor
                )
            } else {
                centroid = .zero
            }

            gridAggregates.append(
                GraphPhysicsGridCellAggregate(
                    coordinate: coordinate,
                    positionedNodeCount: count,
                    centroid: centroid
                )
            )
        }
    }

    mutating func stopNonRelevantNodes(
        allNodes: [GraphNode],
        physicsRelevant: Set<NodeKey>
    ) {
        for node in allNodes where !physicsRelevant.contains(node.key) {
            velocities[node.key] = .zero
        }
    }

    mutating func addVelocity(
        _ key: NodeKey,
        dx: CGFloat,
        dy: CGFloat
    ) {
        guard !fixedNodeKeys.contains(key) else { return }
        velocities[key, default: .zero].dx += dx
        velocities[key, default: .zero].dy += dy
    }

    mutating func accumulateDistantVelocity(
        _ velocity: CGVector,
        for coordinate: GraphPhysicsGridCoordinate
    ) {
        distantVelocityByCell[coordinate, default: .zero].dx +=
            velocity.dx
        distantVelocityByCell[coordinate, default: .zero].dy +=
            velocity.dy
    }

    mutating func setVelocity(
        _ velocity: CGVector,
        for key: NodeKey
    ) {
        velocities[key] = velocity
    }

    mutating func setPosition(
        _ position: CGPoint,
        for key: NodeKey
    ) {
        positions[key] = position
    }

    func gridNodes(
        at coordinate: GraphPhysicsGridCoordinate
    ) -> [GraphPhysicsGridNode] {
        gridBuckets[coordinate] ?? []
    }

    var capacitySnapshot: GraphPhysicsWorkspaceCapacitySnapshot {
        GraphPhysicsWorkspaceCapacitySnapshot(
            simulatedNodeCapacity: simulatedNodes.capacity,
            positionedGridNodeCapacity: positionedGridNodes.capacity,
            activeGridCoordinateCapacity:
                activeGridCoordinates.capacity,
            gridAggregateCapacity: gridAggregates.capacity
        )
    }
}

nonisolated struct GraphPhysicsWorkspaceCapacitySnapshot:
    Equatable,
    Sendable
{
    let simulatedNodeCapacity: Int
    let positionedGridNodeCapacity: Int
    let activeGridCoordinateCapacity: Int
    let gridAggregateCapacity: Int
}

/// Immutable engine input whose mutable positions and velocities live in a
/// caller-owned workspace.
nonisolated struct GraphPhysicsWorkspaceStepInput:
    Equatable,
    Sendable
{
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let fixedNodeKeys: Set<NodeKey>
    let physicsRelevant: Set<NodeKey>?
    let configuration: GraphPhysicsConfiguration
    let diagnosticInteractionStrategyOverride:
        GraphPhysicsInteractionStrategy?

    init(
        nodes: [GraphNode],
        edges: [GraphEdge],
        fixedNodeKeys: Set<NodeKey>,
        physicsRelevant: Set<NodeKey>?,
        configuration: GraphPhysicsConfiguration,
        diagnosticInteractionStrategyOverride:
            GraphPhysicsInteractionStrategy? = nil
    ) {
        self.nodes = nodes
        self.edges = edges
        self.fixedNodeKeys = fixedNodeKeys
        self.physicsRelevant = physicsRelevant
        self.configuration = configuration
        self.diagnosticInteractionStrategyOverride =
            diagnosticInteractionStrategyOverride
    }

    init(stepInput: GraphPhysicsStepInput) {
        self.init(
            nodes: stepInput.nodes,
            edges: stepInput.edges,
            fixedNodeKeys: stepInput.fixedNodeKeys,
            physicsRelevant: stepInput.physicsRelevant,
            configuration: stepInput.configuration,
            diagnosticInteractionStrategyOverride:
                stepInput.diagnosticInteractionStrategyOverride
        )
    }
}

/// Value-only result for the workspace path. Positions and velocities remain
/// in the workspace and are copied only when a caller explicitly publishes or
/// requests the pure convenience result.
nonisolated struct GraphPhysicsWorkspaceStepResult:
    Equatable,
    Sendable
{
    let maxSimSpeed: CGFloat
    let metrics: GraphPhysicsStepMetrics
}
