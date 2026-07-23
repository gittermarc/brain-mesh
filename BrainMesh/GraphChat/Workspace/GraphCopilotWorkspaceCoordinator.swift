//
//  GraphCopilotWorkspaceCoordinator.swift
//  BrainMesh
//
//  Graph-scoped, transient command bridge between the existing Canvas selection and Graph Chat.
//  The Canvas remains the only owner of GraphCanvasSelectionState.
//

import Combine
import Foundation

nonisolated enum GraphCopilotWorkspacePresentationPolicy {
    static let minimumInspectorWidth: Double = 320
    static let defaultInspectorWidth: Double = 440
    static let maximumInspectorWidth: Double = 620

    static func supportsInspector(isRegularHorizontalSizeClass: Bool) -> Bool {
        isRegularHorizontalSizeClass
    }

    static func chatPresentationStyle(
        isRegularHorizontalSizeClass: Bool
    ) -> GraphChatPresentationStyle {
        supportsInspector(isRegularHorizontalSizeClass: isRegularHorizontalSizeClass)
            ? .sheet
            : .rootTab
    }

    static func normalizedInspectorWidth(_ width: Double) -> Double {
        guard width.isFinite else {
            return defaultInspectorWidth
        }
        return min(max(width, minimumInspectorWidth), maximumInspectorWidth)
    }
}

nonisolated struct GraphCopilotCanvasContext: Equatable, Sendable {
    let graphScope: GraphScope
    let graphName: String
    let primaryNode: GraphChatNodeContextReference?
    let selectedNodes: [GraphChatNodeContextReference]
    let totalSelectedNodeCount: Int

    init(
        graphScope: GraphScope,
        graphName: String,
        primaryNode: GraphChatNodeContextReference?,
        selectedNodes: [GraphChatNodeContextReference]
    ) {
        self.graphScope = graphScope
        self.graphName = String(graphName.prefix(240))

        var allSeen = Set<NodeRefKey>()
        var totalSelectedNodeCount = 0
        if let primaryNode, allSeen.insert(primaryNode.node).inserted {
            totalSelectedNodeCount += 1
        }
        for node in selectedNodes where allSeen.insert(node.node).inserted {
            totalSelectedNodeCount += 1
        }
        self.totalSelectedNodeCount = totalSelectedNodeCount

        var bounded: [GraphChatNodeContextReference] = []
        bounded.reserveCapacity(
            min(totalSelectedNodeCount, GraphChatWorkspaceBudget.maximumContextNodes)
        )
        var seen = Set<NodeRefKey>()
        if let primaryNode, seen.insert(primaryNode.node).inserted {
            bounded.append(primaryNode)
        }
        for node in selectedNodes where bounded.count < GraphChatWorkspaceBudget.maximumContextNodes {
            if seen.insert(node.node).inserted {
                bounded.append(node)
            }
        }
        self.selectedNodes = bounded
        self.primaryNode = primaryNode.flatMap { primary in
            bounded.first { $0.node == primary.node }
        }
    }

    var selectedNodeCount: Int {
        totalSelectedNodeCount
    }

    var selectionIsTruncated: Bool {
        totalSelectedNodeCount > selectedNodes.count
    }

    var selectionLaunch: GraphChatContextLaunch? {
        GraphChatContextEntryPoint.selection(
            graphID: graphScope.graphID,
            nodes: selectedNodes
        )
    }
}

nonisolated struct GraphCopilotResultRow: Identifiable, Equatable, Sendable {
    let node: NodeRefKey
    let title: String
    let subtitle: String?

    var id: NodeRefKey {
        node
    }
}

nonisolated struct GraphCopilotResultSetPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let graphScope: GraphScope
    let title: String
    let filterSummary: String?
    let rows: [GraphCopilotResultRow]
    let wasTruncated: Bool

    init(
        id: UUID = UUID(),
        graphScope: GraphScope,
        title: String,
        filterSummary: String? = nil,
        rows: [GraphCopilotResultRow],
        wasTruncated: Bool = false
    ) {
        self.id = id
        self.graphScope = graphScope
        self.title = String(title.prefix(240))
        self.filterSummary = filterSummary.map { String($0.prefix(1_000)) }
        self.rows = Array(rows.prefix(GraphChatWorkspaceBudget.maximumResultRows))
        self.wasTruncated =
            wasTruncated
            || rows.count > GraphChatWorkspaceBudget.maximumResultRows
    }
}

nonisolated enum GraphCopilotCanvasCommandAction: Equatable, Sendable {
    case focus(NodeRefKey)
    case highlight([NodeRefKey])
    case clearHighlight
    case addToSelection([NodeRefKey])
    case replaceSelection([NodeRefKey])
}

nonisolated struct GraphCopilotCanvasCommand: Identifiable, Equatable, Sendable {
    let id: UUID
    let graphScope: GraphScope
    let action: GraphCopilotCanvasCommandAction

    init(
        id: UUID = UUID(),
        graphScope: GraphScope,
        action: GraphCopilotCanvasCommandAction
    ) {
        self.id = id
        self.graphScope = graphScope
        self.action = action
    }
}

@MainActor
final class GraphCopilotWorkspaceCoordinator: ObservableObject {
    @Published private(set) var canvasContext: GraphCopilotCanvasContext?
    @Published private(set) var pendingCanvasCommand: GraphCopilotCanvasCommand?
    @Published private(set) var highlightedNodes: [NodeRefKey] = []
    @Published var presentedResultSet: GraphCopilotResultSetPresentation?

    private var activeGraphID: UUID?
    private var highlightedGraphScope: GraphScope?

    func publishCanvasContext(_ context: GraphCopilotCanvasContext) {
        guard accepts(context.graphScope) else {
            return
        }
        if activeGraphID == nil {
            activeGraphID = context.graphScope.graphID
        }
        guard canvasContext != context else {
            return
        }
        canvasContext = context
    }

    func setCanvasVisible(
        _ isVisible: Bool,
        graphScope: GraphScope?
    ) {
        guard isVisible == false else {
            return
        }
        guard graphScope == nil || canvasContext?.graphScope == graphScope else {
            return
        }
        canvasContext = nil
    }

    func requestFocus(
        _ node: NodeRefKey,
        in graphScope: GraphScope
    ) {
        enqueue(.focus(node), in: graphScope)
    }

    func requestHighlight(
        _ nodes: [NodeRefKey],
        in graphScope: GraphScope
    ) {
        guard accepts(graphScope) else {
            return
        }
        let bounded = Self.normalizedNodes(nodes)
        guard bounded.isEmpty == false else {
            requestClearHighlight(in: graphScope)
            return
        }
        highlightedGraphScope = graphScope
        highlightedNodes = bounded
        enqueue(.highlight(bounded), in: graphScope)
    }

    func requestClearHighlight(in graphScope: GraphScope) {
        guard accepts(graphScope) else {
            return
        }
        highlightedGraphScope = graphScope
        highlightedNodes = []
        enqueue(.clearHighlight, in: graphScope)
    }

    func requestAddToSelection(
        _ nodes: [NodeRefKey],
        in graphScope: GraphScope
    ) {
        let bounded = Self.normalizedNodes(nodes)
        guard bounded.isEmpty == false else {
            return
        }
        enqueue(.addToSelection(bounded), in: graphScope)
    }

    func requestReplaceSelection(
        _ nodes: [NodeRefKey],
        in graphScope: GraphScope
    ) {
        let bounded = Self.normalizedNodes(nodes)
        guard bounded.isEmpty == false else {
            return
        }
        enqueue(.replaceSelection(bounded), in: graphScope)
    }

    func consumeCanvasCommand(id: UUID) -> GraphCopilotCanvasCommand? {
        guard pendingCanvasCommand?.id == id else {
            return nil
        }
        let command = pendingCanvasCommand
        pendingCanvasCommand = nil
        return command
    }

    func highlightedNodes(in graphScope: GraphScope) -> [NodeRefKey] {
        guard accepts(graphScope), highlightedGraphScope == graphScope else {
            return []
        }
        return highlightedNodes
    }

    func presentResultSet(_ presentation: GraphCopilotResultSetPresentation) {
        guard accepts(presentation.graphScope),
            presentation.graphScope == canvasContext?.graphScope
                || canvasContext == nil
        else {
            return
        }
        if activeGraphID == nil {
            activeGraphID = presentation.graphScope.graphID
        }
        presentedResultSet = presentation
    }

    func dismissResultSet() {
        presentedResultSet = nil
    }

    func handleActiveGraphChange(to graphID: UUID?) {
        guard activeGraphID != graphID else {
            return
        }
        activeGraphID = graphID
        clearTransientState()
    }

    func handleSensitiveStateInvalidation(graphID: UUID? = nil) {
        if let graphID {
            let currentGraphID =
                activeGraphID
                ?? canvasContext?.graphScope.graphID
                ?? pendingCanvasCommand?.graphScope.graphID
                ?? highlightedGraphScope?.graphID
                ?? presentedResultSet?.graphScope.graphID
            guard currentGraphID == graphID else {
                return
            }
        }
        clearTransientState()
    }

    func clearChatDerivedState() {
        presentedResultSet = nil
        highlightedNodes = []
        if let graphScope = highlightedGraphScope ?? canvasContext?.graphScope {
            enqueue(.clearHighlight, in: graphScope)
        } else {
            pendingCanvasCommand = nil
        }
        highlightedGraphScope = nil
    }

    func clearTransientState() {
        canvasContext = nil
        pendingCanvasCommand = nil
        highlightedNodes = []
        highlightedGraphScope = nil
        presentedResultSet = nil
    }

    private func enqueue(
        _ action: GraphCopilotCanvasCommandAction,
        in graphScope: GraphScope
    ) {
        guard accepts(graphScope) else {
            return
        }
        if activeGraphID == nil {
            activeGraphID = graphScope.graphID
        }
        pendingCanvasCommand = GraphCopilotCanvasCommand(
            graphScope: graphScope,
            action: action
        )
    }

    private func accepts(_ graphScope: GraphScope) -> Bool {
        activeGraphID == nil || activeGraphID == graphScope.graphID
    }

    private nonisolated static func normalizedNodes(
        _ nodes: [NodeRefKey]
    ) -> [NodeRefKey] {
        var seen = Set<NodeRefKey>()
        return Array(
            nodes
                .filter { seen.insert($0).inserted }
                .prefix(GraphChatWorkspaceBudget.maximumActionNodes)
        )
    }
}
