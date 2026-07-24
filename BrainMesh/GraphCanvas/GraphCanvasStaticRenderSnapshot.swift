//
//  GraphCanvasStaticRenderSnapshot.swift
//  BrainMesh
//

import CoreGraphics
import Foundation
import os

/// The smallest static node input required by the Canvas renderer.
///
/// Labels, positions, velocities, camera values, selection, Lens, and Focus are
/// deliberately excluded. Label placement depends only on the stable NodeKey.
nonisolated struct GraphCanvasStaticRenderInput: Equatable, Sendable {
    let orderedNodeKeys: [NodeKey]
    let directedNotes: [GraphCanvasStaticDirectedNoteInput]

    init(
        nodeKeys: [NodeKey],
        directedEdgeNotes: [DirectedEdgeKey: String]
    ) {
        let orderedNodeKeys = Array(Set(nodeKeys)).sorted {
            $0.identifier < $1.identifier
        }
        let knownIdentifiers = Set(orderedNodeKeys.map(\.identifier))

        self.orderedNodeKeys = orderedNodeKeys
        self.directedNotes = directedEdgeNotes.compactMap { edgeKey, rawNote in
            guard edgeKey.type == GraphEdgeType.link.rawValue,
                  knownIdentifiers.contains(edgeKey.sourceID),
                  knownIdentifiers.contains(edgeKey.targetID) else {
                return nil
            }

            let trimmed = rawNote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let maxCharacters = GraphCanvasStaticRenderSnapshotBuilder.maximumNoteCharacterCount
            let text: String
            if trimmed.count > maxCharacters {
                text = String(trimmed.prefix(maxCharacters)) + "…"
            } else {
                text = trimmed
            }

            return GraphCanvasStaticDirectedNoteInput(
                edgeKey: edgeKey,
                text: text
            )
        }
        .sorted(by: GraphCanvasStaticDirectedNoteInput.sort)
    }

    init(
        nodes: [GraphNode],
        directedEdgeNotes: [DirectedEdgeKey: String]
    ) {
        self.init(
            nodeKeys: nodes.map(\.key),
            directedEdgeNotes: directedEdgeNotes
        )
    }
}

nonisolated struct GraphCanvasStaticDirectedNoteInput: Equatable, Sendable {
    let edgeKey: DirectedEdgeKey
    let text: String

    static func sort(
        _ lhs: GraphCanvasStaticDirectedNoteInput,
        _ rhs: GraphCanvasStaticDirectedNoteInput
    ) -> Bool {
        if lhs.edgeKey.sourceID != rhs.edgeKey.sourceID {
            return lhs.edgeKey.sourceID < rhs.edgeKey.sourceID
        }
        if lhs.edgeKey.targetID != rhs.edgeKey.targetID {
            return lhs.edgeKey.targetID < rhs.edgeKey.targetID
        }
        if lhs.edgeKey.type != rhs.edgeKey.type {
            return lhs.edgeKey.type < rhs.edgeKey.type
        }
        return lhs.text < rhs.text
    }
}

nonisolated struct GraphCanvasPreparedOutgoingNote: Equatable, Sendable {
    let text: String
    let side: CGFloat
}

/// Immutable, value-only lookup data shared by every dynamic Canvas frame until
/// the actual static input changes.
nonisolated struct GraphCanvasStaticRenderSnapshot: Equatable, Sendable {
    let orderedNodeKeys: [NodeKey]
    let knownNodeKeys: Set<NodeKey>
    let labelOffsetsByNodeKey: [NodeKey: CGPoint]
    let nodeKeyByIdentifier: [String: NodeKey]
    let preparedOutgoingNotesBySource: [
        NodeKey: [NodeKey: GraphCanvasPreparedOutgoingNote]
    ]

    static let empty = GraphCanvasStaticRenderSnapshot(
        orderedNodeKeys: [],
        knownNodeKeys: [],
        labelOffsetsByNodeKey: [:],
        nodeKeyByIdentifier: [:],
        preparedOutgoingNotesBySource: [:]
    )

    func preparedOutgoingNote(
        source: NodeKey,
        target: NodeKey
    ) -> GraphCanvasPreparedOutgoingNote? {
        preparedOutgoingNotesBySource[source]?[target]
    }
}

/// Pure deterministic builder for the Canvas static render snapshot.
nonisolated enum GraphCanvasStaticRenderSnapshotBuilder {
    static let maximumNoteCharacterCount = 46

    private static let labelXChoices: [CGFloat] = [-14, 0, 14]
    private static let entityLabelYChoices: [CGFloat] = [0, 6, 12]
    private static let attributeLabelYChoices: [CGFloat] = [0, -6, -12]

    static func build(
        input: GraphCanvasStaticRenderInput
    ) -> GraphCanvasStaticRenderSnapshot {
        var knownNodeKeys = Set<NodeKey>()
        knownNodeKeys.reserveCapacity(input.orderedNodeKeys.count)

        var labelOffsetsByNodeKey: [NodeKey: CGPoint] = [:]
        labelOffsetsByNodeKey.reserveCapacity(input.orderedNodeKeys.count)

        var nodeKeyByIdentifier: [String: NodeKey] = [:]
        nodeKeyByIdentifier.reserveCapacity(input.orderedNodeKeys.count)

        for nodeKey in input.orderedNodeKeys {
            knownNodeKeys.insert(nodeKey)
            labelOffsetsByNodeKey[nodeKey] = labelOffset(for: nodeKey)
            nodeKeyByIdentifier[nodeKey.identifier] = nodeKey
        }

        var preparedOutgoingNotesBySource: [
            NodeKey: [NodeKey: GraphCanvasPreparedOutgoingNote]
        ] = [:]
        preparedOutgoingNotesBySource.reserveCapacity(
            min(input.directedNotes.count, input.orderedNodeKeys.count)
        )

        for note in input.directedNotes {
            guard let source = nodeKeyByIdentifier[note.edgeKey.sourceID],
                  let target = nodeKeyByIdentifier[note.edgeKey.targetID] else {
                continue
            }

            let edgeSeed = stableSeed(
                note.edgeKey.sourceID + "->" + note.edgeKey.targetID
            )
            let side: CGFloat = edgeSeed % 2 == 0 ? 1 : -1
            preparedOutgoingNotesBySource[source, default: [:]][target] =
                GraphCanvasPreparedOutgoingNote(
                    text: note.text,
                    side: side
                )
        }

        return GraphCanvasStaticRenderSnapshot(
            orderedNodeKeys: input.orderedNodeKeys,
            knownNodeKeys: knownNodeKeys,
            labelOffsetsByNodeKey: labelOffsetsByNodeKey,
            nodeKeyByIdentifier: nodeKeyByIdentifier,
            preparedOutgoingNotesBySource: preparedOutgoingNotesBySource
        )
    }

    static func labelOffset(for nodeKey: NodeKey) -> CGPoint {
        let seed = stableSeed(nodeKey.identifier)
        let yChoices = nodeKey.kind == .entity
            ? entityLabelYChoices
            : attributeLabelYChoices

        let xIndex = abs(seed) % labelXChoices.count
        let yIndex = abs(seed / 7) % yChoices.count

        return CGPoint(
            x: labelXChoices[xIndex],
            y: yChoices[yIndex]
        )
    }

    static func stableSeed(_ string: String) -> Int {
        var hash = 0
        for scalar in string.unicodeScalars {
            hash = (hash &* 31) &+ Int(scalar.value)
        }
        return hash
    }
}

nonisolated struct GraphCanvasStaticRenderSnapshotMetrics:
    Equatable,
    Sendable
{
    fileprivate(set) var requestCount = 0
    fileprivate(set) var rebuildCount = 0
    fileprivate(set) var identicalInputSkipCount = 0
    fileprivate(set) var totalRebuildDurationMilliseconds = 0.0
    fileprivate(set) var lastRebuildDurationMilliseconds = 0.0
    fileprivate(set) var lastNodeCount = 0
}

nonisolated struct GraphCanvasStaticRenderSnapshotResolution:
    Equatable,
    Sendable
{
    let snapshot: GraphCanvasStaticRenderSnapshot
    let didRebuild: Bool
}

/// Narrow stateful boundary that owns rebuild identity and technical metrics.
///
/// Requests happen only at Canvas static-data mutation boundaries. Dynamic
/// frames consume the current immutable snapshot without touching this cache.
@MainActor
final class GraphCanvasStaticRenderSnapshotCache {
    private var lastInput: GraphCanvasStaticRenderInput?
    private var currentSnapshot: GraphCanvasStaticRenderSnapshot = .empty

    private(set) var metrics = GraphCanvasStaticRenderSnapshotMetrics()

    func request(
        input: GraphCanvasStaticRenderInput
    ) -> GraphCanvasStaticRenderSnapshotResolution {
        metrics.requestCount += 1

        guard lastInput != input else {
            metrics.identicalInputSkipCount += 1

            #if DEBUG
            BMLog.canvasStaticRender.debug(
                "canvas_static_render_snapshot requests=\(self.metrics.requestCount, privacy: .public) rebuilds=\(self.metrics.rebuildCount, privacy: .public) skipped=\(self.metrics.identicalInputSkipCount, privacy: .public) duration_ms=0 nodes=\(self.metrics.lastNodeCount, privacy: .public)"
            )
            #endif

            return GraphCanvasStaticRenderSnapshotResolution(
                snapshot: currentSnapshot,
                didRebuild: false
            )
        }

        let duration = BMDuration()
        let snapshot = GraphCanvasStaticRenderSnapshotBuilder.build(input: input)
        let durationMilliseconds = duration.millisecondsElapsed

        lastInput = input
        currentSnapshot = snapshot
        metrics.rebuildCount += 1
        metrics.lastRebuildDurationMilliseconds = durationMilliseconds
        metrics.totalRebuildDurationMilliseconds += durationMilliseconds
        metrics.lastNodeCount = input.orderedNodeKeys.count

        #if DEBUG
        BMLog.canvasStaticRender.debug(
            "canvas_static_render_snapshot requests=\(self.metrics.requestCount, privacy: .public) rebuilds=\(self.metrics.rebuildCount, privacy: .public) skipped=\(self.metrics.identicalInputSkipCount, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public) nodes=\(self.metrics.lastNodeCount, privacy: .public)"
        )
        #endif

        return GraphCanvasStaticRenderSnapshotResolution(
            snapshot: snapshot,
            didRebuild: true
        )
    }
}
