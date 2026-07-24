//
//  GraphPhysicsSpatialGrid.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Stable integer coordinate for one spatial-grid cell.
///
/// `floor` is required here: integer truncation would incorrectly place
/// negative values between `-cellSize` and zero into cell zero.
nonisolated struct GraphPhysicsGridCoordinate:
    Comparable,
    Hashable,
    Sendable
{
    let x: Int
    let y: Int

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    init(position: CGPoint, cellSize: CGFloat) {
        self.x = Self.component(position.x, cellSize: cellSize)
        self.y = Self.component(position.y, cellSize: cellSize)
    }

    static func < (
        lhs: GraphPhysicsGridCoordinate,
        rhs: GraphPhysicsGridCoordinate
    ) -> Bool {
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }
        return lhs.y < rhs.y
    }

    func isImmediatelyNeighboring(
        _ other: GraphPhysicsGridCoordinate
    ) -> Bool {
        let xDistance = abs(Double(x) - Double(other.x))
        let yDistance = abs(Double(y) - Double(other.y))
        return xDistance <= 1 && yDistance <= 1
    }

    private static func component(
        _ value: CGFloat,
        cellSize: CGFloat
    ) -> Int {
        guard value.isFinite, cellSize.isFinite, cellSize > 0 else {
            return 0
        }

        let floored = floor(value / cellSize)
        let safeMinimum = CGFloat(Int.min / 4)
        let safeMaximum = CGFloat(Int.max / 4)
        return Int(min(max(floored, safeMinimum), safeMaximum))
    }
}

/// Stable positioned-node entry stored in a grid cell.
nonisolated struct GraphPhysicsGridNode: Equatable, Sendable {
    let key: NodeKey
    let position: CGPoint
}

/// Technical aggregate for deterministic distant-cell repulsion.
nonisolated struct GraphPhysicsGridCellAggregate: Equatable, Sendable {
    let coordinate: GraphPhysicsGridCoordinate
    let positionedNodeCount: Int
    let centroid: CGPoint
}

/// Symmetric per-node velocity contribution for one distant cell pair.
nonisolated struct GraphPhysicsDistantCellRepulsion:
    Equatable,
    Sendable
{
    let firstCellVelocityPerMovableNode: CGVector
    let secondCellVelocityPerMovableNode: CGVector

    static func calculate(
        first: GraphPhysicsGridCellAggregate,
        second: GraphPhysicsGridCellAggregate,
        configuration: GraphPhysicsConfiguration
    ) -> GraphPhysicsDistantCellRepulsion {
        guard first.positionedNodeCount > 0,
              second.positionedNodeCount > 0 else {
            return GraphPhysicsDistantCellRepulsion(
                firstCellVelocityPerMovableNode: .zero,
                secondCellVelocityPerMovableNode: .zero
            )
        }

        let dx = first.centroid.x - second.centroid.x
        let dy = first.centroid.y - second.centroid.y
        let distanceSquared = max(
            dx * dx + dy * dy,
            configuration.minimumPairDistanceSquared
        )
        let repulsionForce = configuration.repulsion / distanceSquared
        let baseX =
            dx * repulsionForce * configuration.repulsionScale
        let baseY =
            dy * repulsionForce * configuration.repulsionScale

        guard baseX.isFinite, baseY.isFinite else {
            return GraphPhysicsDistantCellRepulsion(
                firstCellVelocityPerMovableNode: .zero,
                secondCellVelocityPerMovableNode: .zero
            )
        }

        return GraphPhysicsDistantCellRepulsion(
            firstCellVelocityPerMovableNode: CGVector(
                dx: baseX * CGFloat(second.positionedNodeCount),
                dy: baseY * CGFloat(second.positionedNodeCount)
            ),
            secondCellVelocityPerMovableNode: CGVector(
                dx: -baseX * CGFloat(first.positionedNodeCount),
                dy: -baseY * CGFloat(first.positionedNodeCount)
            )
        )
    }
}

/// One occupied grid cell with nodes ordered by stable technical identifier.
nonisolated struct GraphPhysicsGridCell: Equatable, Sendable {
    let coordinate: GraphPhysicsGridCoordinate
    let nodes: [GraphPhysicsGridNode]
    let aggregate: GraphPhysicsGridCellAggregate

    init(
        coordinate: GraphPhysicsGridCoordinate,
        nodes: [GraphPhysicsGridNode]
    ) {
        let stableNodes = nodes.sorted {
            $0.key.identifier < $1.key.identifier
        }
        self.coordinate = coordinate
        self.nodes = stableNodes

        guard !stableNodes.isEmpty else {
            self.aggregate = GraphPhysicsGridCellAggregate(
                coordinate: coordinate,
                positionedNodeCount: 0,
                centroid: .zero
            )
            return
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        for node in stableNodes {
            x += node.position.x
            y += node.position.y
        }
        let count = CGFloat(stableNodes.count)
        self.aggregate = GraphPhysicsGridCellAggregate(
            coordinate: coordinate,
            positionedNodeCount: stableNodes.count,
            centroid: CGPoint(x: x / count, y: y / count)
        )
    }
}

/// Named, deterministic cell-size derivation for graph physics.
///
/// The production cell is at least the maximum possible collision distance
/// (`entityRadius + entityRadius + collisionPadding`) and also covers the
/// smaller spring rest distance. With the current canvas constants this is
/// `max(50, min(130, 76)) == 76` world points.
nonisolated struct GraphPhysicsSpatialGridConfiguration:
    Equatable,
    Sendable
{
    let cellSize: CGFloat
    let maximumCollisionDistance: CGFloat
    let localInteractionReferenceDistance: CGFloat

    init(physicsConfiguration: GraphPhysicsConfiguration) {
        let maximumRadius = max(
            physicsConfiguration.entityRadius,
            physicsConfiguration.attributeRadius
        )
        let maximumCollisionDistance =
            maximumRadius * 2 + physicsConfiguration.collisionPadding
        let localInteractionReferenceDistance = min(
            physicsConfiguration.linkRestDistance,
            physicsConfiguration.containmentRestDistance
        )

        self.maximumCollisionDistance = maximumCollisionDistance
        self.localInteractionReferenceDistance =
            localInteractionReferenceDistance
        self.cellSize = max(
            maximumCollisionDistance,
            localInteractionReferenceDistance
        )
    }

    init(
        cellSize: CGFloat,
        maximumCollisionDistance: CGFloat
    ) {
        let safeCollisionDistance =
            maximumCollisionDistance.isFinite
                ? max(1, maximumCollisionDistance)
                : 1
        let safeCellSize =
            cellSize.isFinite ? max(1, cellSize) : safeCollisionDistance

        self.maximumCollisionDistance = safeCollisionDistance
        self.localInteractionReferenceDistance = safeCellSize
        self.cellSize = max(safeCellSize, safeCollisionDistance)
    }
}

/// Immutable deterministic grid rebuilt from current positions for one tick.
///
/// Nodes without a finite current position are not inserted. The engine still
/// integrates those nodes with its pre-existing missing-position semantics.
nonisolated struct GraphPhysicsSpatialGrid: Equatable, Sendable {
    let configuration: GraphPhysicsSpatialGridConfiguration
    let cells: [GraphPhysicsGridCell]

    init(
        nodes: [GraphNode],
        positions: [NodeKey: CGPoint],
        configuration: GraphPhysicsSpatialGridConfiguration
    ) {
        self.configuration = configuration

        let positionedNodes = nodes.compactMap { node
            -> GraphPhysicsGridNode? in
            guard let position = positions[node.key],
                  position.x.isFinite,
                  position.y.isFinite else {
                return nil
            }
            return GraphPhysicsGridNode(
                key: node.key,
                position: position
            )
        }.sorted {
            $0.key.identifier < $1.key.identifier
        }

        var nodesByCoordinate:
            [GraphPhysicsGridCoordinate: [GraphPhysicsGridNode]] = [:]
        nodesByCoordinate.reserveCapacity(positionedNodes.count)

        for node in positionedNodes {
            let coordinate = GraphPhysicsGridCoordinate(
                position: node.position,
                cellSize: configuration.cellSize
            )
            nodesByCoordinate[coordinate, default: []].append(node)
        }

        self.cells = nodesByCoordinate.keys.sorted().map { coordinate in
            GraphPhysicsGridCell(
                coordinate: coordinate,
                nodes: nodesByCoordinate[coordinate, default: []]
            )
        }
    }

    func cell(
        at coordinate: GraphPhysicsGridCoordinate
    ) -> GraphPhysicsGridCell? {
        cells.first { $0.coordinate == coordinate }
    }
}
