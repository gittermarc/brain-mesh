//
//  GraphCanvasTypes.swift
//  BrainMesh
//
//  Extracted from GraphCanvasScreen.swift (P0.1)
//

import Foundation
import CoreGraphics

// MARK: - Work Mode

nonisolated enum WorkMode: String, CaseIterable, Identifiable, Sendable {
    case explore
    case organize
    case present

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: return "Erkunden"
        case .organize: return "Aufräumen"
        case .present: return "Präsentieren"
        }
    }

    var icon: String {
        switch self {
        case .explore: return "hand.draw"
        case .organize: return "arrow.up.and.down.and.arrow.left.and.right"
        case .present: return "rectangle.on.rectangle.angled"
        }
    }

    var inspectorDescription: String {
        switch self {
        case .explore:
            return "Pan, Zoom und Auswahl. Layout und Pins bleiben unverändert."
        case .organize:
            return "Layout bearbeiten, Nodes ziehen und Pins setzen."
        case .present:
            return "Ruhiger Canvas für Übersicht und Screenshots. Keine Layout-Bearbeitung."
        }
    }

    static func canonical(rawValue: String) -> WorkMode {
        if rawValue == "edit" {
            return .organize
        }
        return WorkMode(rawValue: rawValue) ?? .explore
    }
}

struct GraphCanvasModePolicy: Equatable, Sendable {
    let mode: WorkMode

    var allowsNodeDragging: Bool {
        mode == .organize
    }

    var allowsDoubleTapPinning: Bool {
        mode == .organize
    }

    var allowsLayoutEditing: Bool {
        allowsNodeDragging || allowsDoubleTapPinning
    }

    var usesQuietChrome: Bool {
        mode == .present
    }

    static func policy(for mode: WorkMode) -> GraphCanvasModePolicy {
        GraphCanvasModePolicy(mode: mode)
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


// MARK: - Derived State Planning

struct GraphCanvasLensConfiguration: Equatable {
    let autoSpotlight: Bool
    let enabled: Bool
    let hideNonRelevant: Bool
    let depth: Int

    static func resolve(
        selection: NodeKey?,
        lensEnabled: Bool,
        lensHideNonRelevant: Bool,
        lensDepth: Int,
        detailsFocusSuppressesSelectionSpotlight: Bool
    ) -> GraphCanvasLensConfiguration {
        if selection != nil, !lensEnabled, !detailsFocusSuppressesSelectionSpotlight {
            return GraphCanvasLensConfiguration(
                autoSpotlight: true,
                enabled: true,
                hideNonRelevant: true,
                depth: 1
            )
        }

        return GraphCanvasLensConfiguration(
            autoSpotlight: false,
            enabled: lensEnabled,
            hideNonRelevant: lensHideNonRelevant,
            depth: lensDepth
        )
    }
}

struct GraphDetailsRenderPlan: Equatable {
    let activeFocus: GraphDetailsFocusState?
    let candidateAttributeNodeKeys: Set<NodeKey>
    let matchedAttributeNodeKeys: Set<NodeKey>
    let hiddenAttributeNodeKeys: Set<NodeKey>
    let dimmedAttributeNodeKeys: Set<NodeKey>
    let suppressesSelectionSpotlight: Bool

    static let empty = GraphDetailsRenderPlan(
        activeFocus: nil,
        candidateAttributeNodeKeys: [],
        matchedAttributeNodeKeys: [],
        hiddenAttributeNodeKeys: [],
        dimmedAttributeNodeKeys: [],
        suppressesSelectionSpotlight: false
    )

    var hasActiveFocus: Bool {
        activeFocus != nil
    }

    func isHidden(_ key: NodeKey) -> Bool {
        hiddenAttributeNodeKeys.contains(key)
    }

    func isMatchedAttribute(_ key: NodeKey) -> Bool {
        matchedAttributeNodeKeys.contains(key)
    }

    func isCandidateAttribute(_ key: NodeKey) -> Bool {
        candidateAttributeNodeKeys.contains(key)
    }

    func nodeOpacityMultiplier(for key: NodeKey) -> CGFloat {
        if hiddenAttributeNodeKeys.contains(key) {
            return 0.0
        }
        if dimmedAttributeNodeKeys.contains(key) {
            return 0.26
        }
        return 1.0
    }

    func edgeOpacityMultiplier(a: NodeKey, b: NodeKey) -> CGFloat {
        if isHidden(a) || isHidden(b) {
            return 0.0
        }
        if dimmedAttributeNodeKeys.contains(a) || dimmedAttributeNodeKeys.contains(b) {
            return 0.22
        }
        return 1.0
    }

    func shouldRender(edge: GraphEdge) -> Bool {
        !isHidden(edge.a) && !isHidden(edge.b)
    }
}

enum GraphDetailsRenderPlanner {
    static func build(summary: GraphDetailsMatchSummary) -> GraphDetailsRenderPlan {
        guard let focus = summary.activeFocus else {
            return .empty
        }

        let candidateKeys = summary.candidateAttributeNodeKeys
        let matchedKeys = summary.matchedAttributeNodeKeys

        switch focus.mode {
        case .highlight:
            return GraphDetailsRenderPlan(
                activeFocus: focus,
                candidateAttributeNodeKeys: candidateKeys,
                matchedAttributeNodeKeys: matchedKeys,
                hiddenAttributeNodeKeys: [],
                dimmedAttributeNodeKeys: candidateKeys.subtracting(matchedKeys),
                suppressesSelectionSpotlight: true
            )
        case .onlyMatches:
            return GraphDetailsRenderPlan(
                activeFocus: focus,
                candidateAttributeNodeKeys: candidateKeys,
                matchedAttributeNodeKeys: matchedKeys,
                hiddenAttributeNodeKeys: candidateKeys.subtracting(matchedKeys),
                dimmedAttributeNodeKeys: [],
                suppressesSelectionSpotlight: true
            )
        }
    }
}

enum GraphCanvasSelectionSpotlightPolicy {
    static func limitsLabels(
        selection: NodeKey?,
        detailsFocusRenderPlan: GraphDetailsRenderPlan
    ) -> Bool {
        selection != nil && !detailsFocusRenderPlan.suppressesSelectionSpotlight
    }
}

struct GraphCanvasDisplayEdgesPlanner {
    static func displayEdges(
        selection: NodeKey?,
        allEdges: [GraphEdge],
        showAllLinksForSelection: Bool,
        degreeCap: Int,
        labelForKey: (NodeKey) -> String
    ) -> [GraphEdge] {
        guard let selection else { return [] }

        let incident = allEdges.filter { $0.a == selection || $0.b == selection }
        let containment = incident.filter { $0.type == .containment }
        var links = incident.filter { $0.type == .link }

        links.sort {
            let lhs = otherEnd(of: $0, from: selection)
            let rhs = otherEnd(of: $1, from: selection)
            return labelForKey(lhs) < labelForKey(rhs)
        }

        if !showAllLinksForSelection {
            links = Array(links.prefix(degreeCap))
        }

        return (containment + links).unique()
    }

    static func hiddenLinkCount(
        selection: NodeKey?,
        allEdges: [GraphEdge],
        showAllLinksForSelection: Bool,
        degreeCap: Int
    ) -> Int {
        guard let selection else { return 0 }
        if showAllLinksForSelection { return 0 }

        let incidentLinkCount = allEdges.filter {
            $0.type == .link && ($0.a == selection || $0.b == selection)
        }.count
        return max(0, incidentLinkCount - degreeCap)
    }

    private static func otherEnd(of edge: GraphEdge, from selection: NodeKey) -> NodeKey {
        edge.a == selection ? edge.b : edge.a
    }
}

struct GraphCanvasDerivedStateSnapshot: Equatable {
    let drawEdges: [GraphEdge]
    let lens: LensContext
    let physicsRelevant: Set<NodeKey>?
    let detailsFocusSummary: GraphDetailsMatchSummary
    let detailsFocusRenderPlan: GraphDetailsRenderPlan
}

struct GraphCanvasDerivedStateBuilder {
    static func build(
        selection: NodeKey?,
        edges: [GraphEdge],
        showAllLinksForSelection: Bool,
        degreeCap: Int,
        lensEnabled: Bool,
        lensHideNonRelevant: Bool,
        lensDepth: Int,
        detailsFocusState: GraphDetailsFocusState? = nil,
        detailsFocusPreparedState: GraphDetailsPreparedState = .empty,
        labelForKey: (NodeKey) -> String
    ) -> GraphCanvasDerivedStateSnapshot {
        let baseDrawEdges = GraphCanvasDisplayEdgesPlanner.displayEdges(
            selection: selection,
            allEdges: edges,
            showAllLinksForSelection: showAllLinksForSelection,
            degreeCap: degreeCap,
            labelForKey: labelForKey
        )

        let detailsFocusSummary = GraphDetailsMatcher.summary(
            focusState: detailsFocusState,
            preparedState: detailsFocusPreparedState
        )
        let detailsFocusRenderPlan = GraphDetailsRenderPlanner.build(summary: detailsFocusSummary)
        let drawEdges = baseDrawEdges.filter { detailsFocusRenderPlan.shouldRender(edge: $0) }

        let lensConfiguration = GraphCanvasLensConfiguration.resolve(
            selection: selection,
            lensEnabled: lensEnabled,
            lensHideNonRelevant: lensHideNonRelevant,
            lensDepth: lensDepth,
            detailsFocusSuppressesSelectionSpotlight: detailsFocusRenderPlan.suppressesSelectionSpotlight
        )

        let lens = LensContext.build(
            enabled: lensConfiguration.enabled,
            hideNonRelevant: lensConfiguration.hideNonRelevant,
            depth: lensConfiguration.depth,
            selection: selection,
            edges: drawEdges
        )

        let physicsRelevant = lensConfiguration.autoSpotlight ? lens.relevant : nil

        return GraphCanvasDerivedStateSnapshot(
            drawEdges: drawEdges,
            lens: lens,
            physicsRelevant: physicsRelevant,
            detailsFocusSummary: detailsFocusSummary,
            detailsFocusRenderPlan: detailsFocusRenderPlan
        )
    }
}

struct GraphCanvasDerivedStateCacheMutation: Equatable {
    let drawEdgesChanged: Bool
    let lensChanged: Bool
    let physicsRelevantChanged: Bool
    let detailsFocusSummaryChanged: Bool
    let detailsFocusRenderPlanChanged: Bool

    var hasChanges: Bool {
        drawEdgesChanged || lensChanged || physicsRelevantChanged || detailsFocusSummaryChanged || detailsFocusRenderPlanChanged
    }

    static func diff(
        cachedDrawEdges: [GraphEdge],
        cachedLens: LensContext,
        cachedPhysicsRelevant: Set<NodeKey>?,
        cachedDetailsFocusSummary: GraphDetailsMatchSummary,
        cachedDetailsFocusRenderPlan: GraphDetailsRenderPlan,
        derived: GraphCanvasDerivedStateSnapshot
    ) -> GraphCanvasDerivedStateCacheMutation {
        GraphCanvasDerivedStateCacheMutation(
            drawEdgesChanged: cachedDrawEdges != derived.drawEdges,
            lensChanged: cachedLens != derived.lens,
            physicsRelevantChanged: cachedPhysicsRelevant != derived.physicsRelevant,
            detailsFocusSummaryChanged: cachedDetailsFocusSummary != derived.detailsFocusSummary,
            detailsFocusRenderPlanChanged: cachedDetailsFocusRenderPlan != derived.detailsFocusRenderPlan
        )
    }
}

// MARK: - Graph Types

nonisolated struct NodeKey: Hashable, Sendable {
    let kind: NodeKind
    let uuid: UUID
    var identifier: String { "\(kind.rawValue)-\(uuid.uuidString)" }
}

nonisolated struct GraphNode: Identifiable, Hashable, Sendable {
    let key: NodeKey
    let label: String
    var id: String { key.identifier }
}

nonisolated enum GraphEdgeType: Int, Hashable, Sendable {
    case link = 0
    case containment = 1
}

nonisolated struct GraphEdge: Hashable, Sendable {
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

nonisolated extension Array where Element == GraphEdge {
    /// Removes duplicate edges without changing their established render order.
    func unique() -> [GraphEdge] {
        var seen = Set<GraphEdge>()
        seen.reserveCapacity(count)
        return filter { seen.insert($0).inserted }
    }
}

/// Directed notes key: source -> target
nonisolated struct DirectedEdgeKey: Hashable, Sendable {
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
