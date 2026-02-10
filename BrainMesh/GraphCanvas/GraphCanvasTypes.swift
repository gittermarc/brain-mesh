//
//  GraphCanvasTypes.swift
//  BrainMesh
//
//  Extracted from GraphCanvasScreen.swift (P0.1)
//

import Foundation
import CoreGraphics

// MARK: - Work Mode

enum WorkMode: String, CaseIterable, Identifiable {
    case explore
    case edit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: return "Explore"
        case .edit: return "Edit"
        }
    }

    var icon: String {
        switch self {
        case .explore: return "hand.draw"
        case .edit: return "pencil.tip"
        }
    }
}

// MARK: - Lens

/// Small helper that computes a relevance neighborhood around a selection.
/// Used to dim/hide nodes/edges outside the chosen depth.
struct LensContext: Equatable {
    let enabled: Bool
    let hideNonRelevant: Bool
    let depth: Int
    let selection: NodeKey?
    let distance: [NodeKey: Int]
    let relevant: Set<NodeKey>

    static func build(
        enabled: Bool,
        hideNonRelevant: Bool,
        depth: Int,
        selection: NodeKey?,
        edges: [GraphEdge]
    ) -> LensContext {
        guard enabled, let s = selection else {
            return LensContext(
                enabled: false,
                hideNonRelevant: false,
                depth: depth,
                selection: selection,
                distance: [:],
                relevant: []
            )
        }

        var adj: [NodeKey: [NodeKey]] = [:]
        adj.reserveCapacity(edges.count * 2)
        for e in edges {
            adj[e.a, default: []].append(e.b)
            adj[e.b, default: []].append(e.a)
        }

        var dist: [NodeKey: Int] = [s: 0]
        var q: [NodeKey] = [s]
        var idx = 0

        while idx < q.count {
            let cur = q[idx]; idx += 1
            let d = dist[cur, default: 0]
            if d >= depth { continue }
            for nb in adj[cur, default: []] {
                if dist[nb] == nil {
                    dist[nb] = d + 1
                    q.append(nb)
                }
            }
        }

        let rel = Set(dist.keys)
        return LensContext(
            enabled: true,
            hideNonRelevant: hideNonRelevant,
            depth: depth,
            selection: s,
            distance: dist,
            relevant: rel
        )
    }

    func nodeOpacity(_ k: NodeKey) -> CGFloat {
        // Wenn Lens nicht aktiv ist, soll der Graph NICHT gedimmt werden.
        // Sonst wirken Nodes/Labels "ausgewaschen" und werden erst bei Selection wirklich lesbar.
        guard enabled else { return 1.0 }

        guard let d = distance[k] else {
            return hideNonRelevant ? 0.0 : 0.12
        }
        switch d {
        case 0: return 1.0
        case 1: return 0.92
        case 2: return 0.55
        default: return hideNonRelevant ? 0.0 : 0.12
        }
    }

    func edgeOpacity(a: NodeKey, b: NodeKey) -> CGFloat {
        guard enabled else { return 1.0 }
        let da = distance[a]
        let db = distance[b]
        if da == nil || db == nil { return hideNonRelevant ? 0.0 : 0.10 }
        let m = max(da!, db!)
        if m <= 1 { return 0.95 }
        if m == 2 { return 0.55 }
        return hideNonRelevant ? 0.0 : 0.10
    }

    func isHidden(_ k: NodeKey) -> Bool {
        enabled && hideNonRelevant && distance[k] == nil
    }
}

// MARK: - Graph Types

struct NodeKey: Hashable {
    let kind: NodeKind
    let uuid: UUID
    var identifier: String { "\(kind.rawValue)-\(uuid.uuidString)" }
}

struct GraphNode: Identifiable, Hashable {
    let key: NodeKey
    let label: String
    var id: String { key.identifier }
}

enum GraphEdgeType: Int, Hashable {
    case link = 0
    case containment = 1
}

struct GraphEdge: Hashable {
    let a: NodeKey
    let b: NodeKey
    let type: GraphEdgeType

    init(a: NodeKey, b: NodeKey, type: GraphEdgeType) {
        if a.identifier <= b.identifier {
            self.a = a; self.b = b
        } else {
            self.a = b; self.b = a
        }
        self.type = type
    }
}

extension Array where Element == GraphEdge {
    func unique() -> [GraphEdge] { Array(Set(self)) }
}

/// Directed notes key: source -> target
struct DirectedEdgeKey: Hashable {
    let sourceID: String
    let targetID: String
    let type: Int

    static func make(source: NodeKey, target: NodeKey, type: GraphEdgeType) -> DirectedEdgeKey {
        DirectedEdgeKey(sourceID: source.identifier, targetID: target.identifier, type: type.rawValue)
    }
}

// MARK: - Camera Commands

struct CameraCommand: Identifiable, Equatable {
    enum Kind: Equatable {
        case center(NodeKey)
        case fitAll
        case reset
    }

    let id = UUID()
    let kind: Kind
}
