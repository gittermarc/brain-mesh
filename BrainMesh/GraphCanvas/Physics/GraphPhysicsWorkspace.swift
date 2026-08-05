//
//  GraphPhysicsWorkspace.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// A graph edge resolved once to stable contiguous node indices.
nonisolated struct GraphPhysicsIndexedEdge: Equatable, Sendable {
    let firstIndex: Int
    let secondIndex: Int
    let type: GraphEdgeType
}

/// Immutable, value-only topology prepared outside the per-tick hot path.
///
/// The node-to-index dictionary is used only while inputs are reconciled. The
/// actual physics step works exclusively with contiguous arrays and integer
/// indices.
nonisolated struct GraphPhysicsPreparedStepInput: Equatable, Sendable {
    let nodes: [GraphNode]
    let orderedNodeKeys: [NodeKey]
    let nodeIndexByKey: [NodeKey: Int]
    let edges: [GraphPhysicsIndexedEdge]
    let fixedNodeMask: [Bool]
    let simulatedNodeIndices: [Int]
    let configuration: GraphPhysicsConfiguration
    let diagnosticInteractionStrategyOverride:
        GraphPhysicsInteractionStrategy?

    init(input: GraphPhysicsWorkspaceStepInput) {
        nodes = input.nodes
        let orderedKeys = input.nodes.map(\.key)
        orderedNodeKeys = orderedKeys

        var indexByKey: [NodeKey: Int] = [:]
        indexByKey.reserveCapacity(input.nodes.count)
        for (index, node) in input.nodes.enumerated() {
            indexByKey[node.key] = index
        }
        nodeIndexByKey = indexByKey

        var resolvedEdges: [GraphPhysicsIndexedEdge] = []
        resolvedEdges.reserveCapacity(input.edges.count)
        for edge in input.edges {
            if let relevant = input.physicsRelevant,
               (!relevant.contains(edge.a)
                || !relevant.contains(edge.b)) {
                continue
            }
            guard let firstIndex = indexByKey[edge.a],
                  let secondIndex = indexByKey[edge.b] else {
                continue
            }
            resolvedEdges.append(
                GraphPhysicsIndexedEdge(
                    firstIndex: firstIndex,
                    secondIndex: secondIndex,
                    type: edge.type
                )
            )
        }
        edges = resolvedEdges

        fixedNodeMask = orderedKeys.map {
            input.fixedNodeKeys.contains($0)
        }

        if let relevant = input.physicsRelevant {
            simulatedNodeIndices = orderedKeys.indices.filter {
                relevant.contains(orderedKeys[$0])
            }
        } else {
            simulatedNodeIndices = Array(orderedKeys.indices)
        }

        configuration = input.configuration
        diagnosticInteractionStrategyOverride =
            input.diagnosticInteractionStrategyOverride
    }
}

private nonisolated struct GraphPhysicsIndexedGridNode:
    Equatable,
    Sendable
{
    let nodeIndex: Int
    let key: NodeKey
    let position: CGPoint
    let coordinate: GraphPhysicsGridCoordinate
}

private nonisolated struct GraphPhysicsIndexedGridCell:
    Equatable,
    Sendable
{
    let coordinate: GraphPhysicsGridCoordinate
    let nodeRange: Range<Int>
    let aggregate: GraphPhysicsGridCellAggregate
}

/// Reusable contiguous storage for deterministic graph-physics steps.
///
/// Node keys are resolved to indices at an input boundary. Positions,
/// velocities, fixed-state, grid nodes, grid cells, and distant-cell deltas
/// remain in arrays for every subsequent tick. Dictionary materialization is
/// reserved for explicit diagnostics and pure API output.
nonisolated struct GraphPhysicsWorkspace: Sendable {
    private(set) var orderedNodes: [GraphNode] = []
    private(set) var orderedNodeKeys: [NodeKey] = []
    private(set) var nodeIndexByKey: [NodeKey: Int] = [:]

    private var positionValues: [CGPoint] = []
    private var positionPresence: [Bool] = []
    private var velocityValues: [CGVector] = []
    private var simulatedNodeIndices: [Int] = []
    private var fixedNodeMask: [Bool] = []

    private var pendingPositions: [NodeKey: CGPoint] = [:]
    private var pendingVelocities: [NodeKey: CGVector] = [:]

    private var indexedGridNodes: [GraphPhysicsIndexedGridNode] = []
    private var indexedGridCells: [GraphPhysicsIndexedGridCell] = []
    private var distantVelocityByCellIndex: [CGVector] = []

    private(set) var hasSynchronizedState = false

    /// Compatibility projection used by the immutable engine result and tests.
    /// The actor runtime never calls this property per tick.
    var positions: [NodeKey: CGPoint] {
        if orderedNodeKeys.isEmpty {
            return pendingPositions
        }

        var result: [NodeKey: CGPoint] = [:]
        result.reserveCapacity(orderedNodeKeys.count)
        for index in orderedNodeKeys.indices where positionPresence[index] {
            result[orderedNodeKeys[index]] = positionValues[index]
        }
        return result
    }

    /// Compatibility projection used by deterministic tests and the pure API.
    /// Simulation snapshots deliberately never expose this value to SwiftUI.
    var velocities: [NodeKey: CGVector] {
        if orderedNodeKeys.isEmpty {
            return pendingVelocities
        }

        var result: [NodeKey: CGVector] = [:]
        result.reserveCapacity(orderedNodeKeys.count)
        for index in orderedNodeKeys.indices {
            result[orderedNodeKeys[index]] = velocityValues[index]
        }
        return result
    }

    var simulatedNodes: [GraphNode] {
        simulatedNodeIndices.map { orderedNodes[$0] }
    }

    var fixedNodeKeys: Set<NodeKey> {
        var result = Set<NodeKey>()
        result.reserveCapacity(fixedNodeMask.count)
        for index in fixedNodeMask.indices where fixedNodeMask[index] {
            result.insert(orderedNodeKeys[index])
        }
        return result
    }

    var positionedGridNodes: [GraphPhysicsGridNode] {
        indexedGridNodes.map {
            GraphPhysicsGridNode(
                key: $0.key,
                position: $0.position
            )
        }
    }

    var activeGridCoordinates: [GraphPhysicsGridCoordinate] {
        indexedGridCells.map(\.coordinate)
    }

    var gridAggregates: [GraphPhysicsGridCellAggregate] {
        indexedGridCells.map(\.aggregate)
    }

    var gridBuckets:
        [GraphPhysicsGridCoordinate: [GraphPhysicsGridNode]] {
        var result: [
            GraphPhysicsGridCoordinate: [GraphPhysicsGridNode]
        ] = [:]
        result.reserveCapacity(indexedGridCells.count)
        for cell in indexedGridCells {
            result[cell.coordinate] = cell.nodeRange.map {
                GraphPhysicsGridNode(
                    key: indexedGridNodes[$0].key,
                    position: indexedGridNodes[$0].position
                )
            }
        }
        return result
    }

    var distantVelocityByCell:
        [GraphPhysicsGridCoordinate: CGVector] {
        var result: [GraphPhysicsGridCoordinate: CGVector] = [:]
        result.reserveCapacity(indexedGridCells.count)
        for cellIndex in indexedGridCells.indices {
            result[indexedGridCells[cellIndex].coordinate] =
                distantVelocityByCellIndex[cellIndex]
        }
        return result
    }

    mutating func fullReset(
        positions newPositions: [NodeKey: CGPoint],
        velocities newVelocities: [NodeKey: CGVector]
    ) {
        removeAllSemanticContent()
        pendingPositions.reserveCapacity(newPositions.count)
        pendingPositions.merge(newPositions) { _, latest in latest }
        pendingVelocities.reserveCapacity(newVelocities.count)
        pendingVelocities.merge(newVelocities) { _, latest in latest }
        hasSynchronizedState = true
    }

    /// Reconciles a new prepared topology while preserving state for retained
    /// node IDs when requested. Additions receive their supplied initial
    /// position and zero velocity; removals are deterministically compacted.
    mutating func synchronize(
        preparedInput: GraphPhysicsPreparedStepInput,
        positions externalPositions: [NodeKey: CGPoint],
        initialVelocities: [NodeKey: CGVector],
        preservesRetainedState: Bool
    ) {
        let oldIndexByKey = nodeIndexByKey
        let oldPositionValues = positionValues
        let oldPositionPresence = positionPresence
        let oldVelocityValues = velocityValues

        orderedNodes.removeAll(keepingCapacity: true)
        orderedNodes.append(contentsOf: preparedInput.nodes)
        orderedNodeKeys.removeAll(keepingCapacity: true)
        orderedNodeKeys.append(contentsOf: preparedInput.orderedNodeKeys)
        nodeIndexByKey.removeAll(keepingCapacity: true)
        nodeIndexByKey.reserveCapacity(preparedInput.nodeIndexByKey.count)
        nodeIndexByKey.merge(preparedInput.nodeIndexByKey) { _, latest in
            latest
        }

        positionValues.removeAll(keepingCapacity: true)
        positionPresence.removeAll(keepingCapacity: true)
        velocityValues.removeAll(keepingCapacity: true)
        positionValues.reserveCapacity(orderedNodeKeys.count)
        positionPresence.reserveCapacity(orderedNodeKeys.count)
        velocityValues.reserveCapacity(orderedNodeKeys.count)

        for key in orderedNodeKeys {
            let oldIndex = oldIndexByKey[key]
            let externalPosition = externalPositions[key]
            let externalOverridesRetainedPosition: Bool
            if preservesRetainedState, let externalPosition {
                if let oldIndex,
                   oldPositionPresence.indices.contains(oldIndex),
                   oldPositionPresence[oldIndex] {
                    externalOverridesRetainedPosition =
                        oldPositionValues[oldIndex]
                        != externalPosition
                } else {
                    externalOverridesRetainedPosition = true
                }
            } else {
                externalOverridesRetainedPosition = false
            }

            if let externalPosition {
                positionValues.append(externalPosition)
                positionPresence.append(true)
            } else if preservesRetainedState,
                      let oldIndex,
                      oldPositionPresence.indices.contains(oldIndex),
                      oldPositionPresence[oldIndex] {
                positionValues.append(oldPositionValues[oldIndex])
                positionPresence.append(true)
            } else {
                positionValues.append(.zero)
                positionPresence.append(false)
            }

            if let suppliedVelocity = initialVelocities[key] {
                velocityValues.append(suppliedVelocity)
            } else if preservesRetainedState,
                      !externalOverridesRetainedPosition,
                      let oldIndex,
                      oldVelocityValues.indices.contains(oldIndex) {
                velocityValues.append(oldVelocityValues[oldIndex])
            } else {
                velocityValues.append(.zero)
            }
        }

        pendingPositions.removeAll(keepingCapacity: true)
        pendingVelocities.removeAll(keepingCapacity: true)
        prepareStep(preparedInput: preparedInput)
        hasSynchronizedState = true
    }

    mutating func removeAllSemanticContent(
        keepingCapacity: Bool = true
    ) {
        orderedNodes.removeAll(keepingCapacity: keepingCapacity)
        orderedNodeKeys.removeAll(keepingCapacity: keepingCapacity)
        nodeIndexByKey.removeAll(keepingCapacity: keepingCapacity)
        positionValues.removeAll(keepingCapacity: keepingCapacity)
        positionPresence.removeAll(keepingCapacity: keepingCapacity)
        velocityValues.removeAll(keepingCapacity: keepingCapacity)
        simulatedNodeIndices.removeAll(keepingCapacity: keepingCapacity)
        fixedNodeMask.removeAll(keepingCapacity: keepingCapacity)
        pendingPositions.removeAll(keepingCapacity: keepingCapacity)
        pendingVelocities.removeAll(keepingCapacity: keepingCapacity)
        indexedGridNodes.removeAll(keepingCapacity: keepingCapacity)
        indexedGridCells.removeAll(keepingCapacity: keepingCapacity)
        distantVelocityByCellIndex.removeAll(
            keepingCapacity: keepingCapacity
        )
        hasSynchronizedState = false
    }

    mutating func releaseTransientCapacity() {
        indexedGridNodes.removeAll(keepingCapacity: false)
        indexedGridCells.removeAll(keepingCapacity: false)
        distantVelocityByCellIndex.removeAll(keepingCapacity: false)
    }

    mutating func prepareStep(
        preparedInput: GraphPhysicsPreparedStepInput
    ) {
        if orderedNodeKeys != preparedInput.orderedNodeKeys {
            let initialPositions = pendingPositions
            let initialVelocities = pendingVelocities
            synchronize(
                preparedInput: preparedInput,
                positions: initialPositions,
                initialVelocities: initialVelocities,
                preservesRetainedState: true
            )
            return
        }

        orderedNodes.removeAll(keepingCapacity: true)
        orderedNodes.append(contentsOf: preparedInput.nodes)
        simulatedNodeIndices.removeAll(keepingCapacity: true)
        simulatedNodeIndices.append(
            contentsOf: preparedInput.simulatedNodeIndices
        )
        fixedNodeMask.removeAll(keepingCapacity: true)
        fixedNodeMask.append(contentsOf: preparedInput.fixedNodeMask)
    }

    mutating func applyExternalPositions(
        _ externalPositions: [NodeKey: CGPoint],
        zeroesChangedVelocities: Bool
    ) -> Bool {
        guard hasSynchronizedState else { return false }

        var didChange = false
        for (key, position) in externalPositions {
            guard let index = nodeIndexByKey[key] else { continue }
            if positionPresence[index] == false
                || positionValues[index] != position {
                positionValues[index] = position
                positionPresence[index] = true
                if zeroesChangedVelocities {
                    velocityValues[index] = .zero
                }
                didChange = true
            }
        }
        return didChange
    }

    mutating func prepareSpatialGrid(
        configuration: GraphPhysicsSpatialGridConfiguration
    ) {
        indexedGridNodes.removeAll(keepingCapacity: true)
        indexedGridCells.removeAll(keepingCapacity: true)
        distantVelocityByCellIndex.removeAll(keepingCapacity: true)

        indexedGridNodes.reserveCapacity(simulatedNodeIndices.count)
        for nodeIndex in simulatedNodeIndices {
            guard positionPresence[nodeIndex] else { continue }
            let position = positionValues[nodeIndex]
            guard position.x.isFinite, position.y.isFinite else {
                continue
            }
            indexedGridNodes.append(
                GraphPhysicsIndexedGridNode(
                    nodeIndex: nodeIndex,
                    key: orderedNodeKeys[nodeIndex],
                    position: position,
                    coordinate: GraphPhysicsGridCoordinate(
                        position: position,
                        cellSize: configuration.cellSize
                    )
                )
            )
        }

        indexedGridNodes.sort {
            if $0.coordinate != $1.coordinate {
                return $0.coordinate < $1.coordinate
            }
            return $0.key.identifier < $1.key.identifier
        }

        indexedGridCells.reserveCapacity(indexedGridNodes.count)
        var rangeStart = 0
        while rangeStart < indexedGridNodes.count {
            let coordinate = indexedGridNodes[rangeStart].coordinate
            var rangeEnd = rangeStart
            var x: CGFloat = 0
            var y: CGFloat = 0

            while rangeEnd < indexedGridNodes.count,
                  indexedGridNodes[rangeEnd].coordinate == coordinate {
                x += indexedGridNodes[rangeEnd].position.x
                y += indexedGridNodes[rangeEnd].position.y
                rangeEnd += 1
            }

            let count = rangeEnd - rangeStart
            let divisor = CGFloat(count)
            indexedGridCells.append(
                GraphPhysicsIndexedGridCell(
                    coordinate: coordinate,
                    nodeRange: rangeStart..<rangeEnd,
                    aggregate: GraphPhysicsGridCellAggregate(
                        coordinate: coordinate,
                        positionedNodeCount: count,
                        centroid: CGPoint(
                            x: x / divisor,
                            y: y / divisor
                        )
                    )
                )
            )
            rangeStart = rangeEnd
        }

        distantVelocityByCellIndex = Array(
            repeating: .zero,
            count: indexedGridCells.count
        )
    }

    mutating func stopNonRelevantNodes() {
        guard simulatedNodeIndices.count != orderedNodeKeys.count else {
            return
        }
        var simulatedMask = Array(
            repeating: false,
            count: orderedNodeKeys.count
        )
        for index in simulatedNodeIndices {
            simulatedMask[index] = true
        }
        for index in simulatedMask.indices where simulatedMask[index] == false {
            velocityValues[index] = .zero
        }
    }

    mutating func addVelocity(
        at index: Int,
        dx: CGFloat,
        dy: CGFloat
    ) {
        guard fixedNodeMask[index] == false else { return }
        velocityValues[index].dx += dx
        velocityValues[index].dy += dy
    }

    mutating func accumulateDistantVelocity(
        _ velocity: CGVector,
        forCellAt cellIndex: Int
    ) {
        distantVelocityByCellIndex[cellIndex].dx += velocity.dx
        distantVelocityByCellIndex[cellIndex].dy += velocity.dy
    }

    mutating func setVelocity(
        _ velocity: CGVector,
        at index: Int
    ) {
        velocityValues[index] = velocity
    }

    mutating func setPosition(
        _ position: CGPoint,
        at index: Int
    ) {
        positionValues[index] = position
        positionPresence[index] = true
    }

    func position(at index: Int) -> CGPoint? {
        positionPresence[index] ? positionValues[index] : nil
    }

    func velocity(at index: Int) -> CGVector {
        velocityValues[index]
    }

    func isFixed(at index: Int) -> Bool {
        fixedNodeMask[index]
    }

    var simulationIndices: [Int] {
        simulatedNodeIndices
    }

    var gridCellCount: Int {
        indexedGridCells.count
    }

    func gridCoordinate(at cellIndex: Int)
        -> GraphPhysicsGridCoordinate {
        indexedGridCells[cellIndex].coordinate
    }

    func gridAggregate(at cellIndex: Int)
        -> GraphPhysicsGridCellAggregate {
        indexedGridCells[cellIndex].aggregate
    }

    func gridNodeCount(at cellIndex: Int) -> Int {
        indexedGridCells[cellIndex].nodeRange.count
    }

    func gridNodeIndex(
        at cellIndex: Int,
        offset: Int
    ) -> Int {
        let range = indexedGridCells[cellIndex].nodeRange
        return indexedGridNodes[range.lowerBound + offset].nodeIndex
    }

    func distantVelocity(at cellIndex: Int) -> CGVector {
        distantVelocityByCellIndex[cellIndex]
    }

    func maximumPositionDelta(
        from snapshot: GraphPhysicsPositionSnapshot
    ) -> CGFloat {
        guard snapshot.orderedNodeKeys == orderedNodeKeys,
              snapshot.positions.count == positionValues.count,
              snapshot.positionPresence.count == positionPresence.count else {
            return .greatestFiniteMagnitude
        }

        var maximumDelta: CGFloat = 0
        for index in positionValues.indices {
            guard snapshot.positionPresence[index]
                    == positionPresence[index] else {
                return .greatestFiniteMagnitude
            }
            guard positionPresence[index] else { continue }
            let dx = positionValues[index].x
                - snapshot.positions[index].x
            let dy = positionValues[index].y
                - snapshot.positions[index].y
            maximumDelta = max(
                maximumDelta,
                sqrt(dx * dx + dy * dy)
            )
        }
        return maximumDelta
    }

    func makePositionSnapshot(
        graphID: UUID?,
        commandRevision: UInt64,
        snapshotRevision: UInt64
    ) -> GraphPhysicsPositionSnapshot {
        GraphPhysicsPositionSnapshot(
            graphID: graphID,
            identity: GraphPhysicsRuntimeIdentity(
                graphID: graphID,
                orderedNodeKeys: orderedNodeKeys
            ),
            commandRevision: commandRevision,
            snapshotRevision: snapshotRevision,
            orderedNodeKeys: orderedNodeKeys,
            positions: positionValues,
            positionPresence: positionPresence
        )
    }

    var capacitySnapshot: GraphPhysicsWorkspaceCapacitySnapshot {
        GraphPhysicsWorkspaceCapacitySnapshot(
            nodeCapacity: orderedNodeKeys.capacity,
            positionCapacity: positionValues.capacity,
            velocityCapacity: velocityValues.capacity,
            simulatedNodeCapacity: simulatedNodeIndices.capacity,
            positionedGridNodeCapacity: indexedGridNodes.capacity,
            activeGridCoordinateCapacity: indexedGridCells.capacity,
            gridAggregateCapacity: indexedGridCells.capacity
        )
    }
}

nonisolated struct GraphPhysicsWorkspaceCapacitySnapshot:
    Equatable,
    Sendable
{
    let nodeCapacity: Int
    let positionCapacity: Int
    let velocityCapacity: Int
    let simulatedNodeCapacity: Int
    let positionedGridNodeCapacity: Int
    let activeGridCoordinateCapacity: Int
    let gridAggregateCapacity: Int
}

/// Immutable engine input. The actor caches its indexed prepared projection
/// whenever topology or interaction constraints change.
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
/// internal until the pure API or a diagnostic explicitly requests them.
nonisolated struct GraphPhysicsWorkspaceStepResult:
    Equatable,
    Sendable
{
    let maxSimSpeed: CGFloat
    let metrics: GraphPhysicsStepMetrics
}
