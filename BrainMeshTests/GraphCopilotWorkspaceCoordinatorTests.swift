//
//  GraphCopilotWorkspaceCoordinatorTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph Copilot workspace coordination")
@MainActor
struct GraphCopilotWorkspaceCoordinatorTests {
    @Test
    func canvasContextKeepsTheFullSelectionCountButBoundsTheAdoptableSnapshot() throws {
        let graphScope = GraphScope(graphID: uuid(1))
        let references = (0..<80).map { index in
            reference(index + 100)
        }
        let context = GraphCopilotCanvasContext(
            graphScope: graphScope,
            graphName: String(repeating: "G", count: 300),
            primaryNode: references[0],
            selectedNodes: references + [references[0]]
        )

        #expect(context.graphName.count == 240)
        #expect(context.selectedNodeCount == 80)
        #expect(context.selectedNodes.count == GraphChatWorkspaceBudget.maximumContextNodes)
        #expect(context.selectionIsTruncated)
        #expect(context.primaryNode == references[0])

        let launch = try #require(context.selectionLaunch)
        #expect(launch.scope.graphScope == graphScope)
        #expect(
            launch.scope.nodeReferences
                == Array(references.prefix(GraphChatWorkspaceBudget.maximumContextNodes)).map(\.node))
    }

    @Test
    func commandsAreBoundedDeduplicatedAndRejectedForAnotherGraph() throws {
        let coordinator = GraphCopilotWorkspaceCoordinator()
        let graphScope = GraphScope(graphID: uuid(2))
        let foreignScope = GraphScope(graphID: uuid(3))
        coordinator.handleActiveGraphChange(to: graphScope.graphID)
        let nodes = (0..<200).map { index in
            NodeRefKey(kind: .attribute, id: uuid(index + 1_000))
        }

        coordinator.requestHighlight(nodes + [nodes[0]], in: graphScope)

        #expect(coordinator.highlightedNodes.count == GraphChatWorkspaceBudget.maximumActionNodes)
        #expect(coordinator.highlightedNodes(in: graphScope) == coordinator.highlightedNodes)
        let localCommand = try #require(coordinator.pendingCanvasCommand)
        guard case .highlight(let highlighted) = localCommand.action else {
            Issue.record("Expected a highlight command")
            return
        }
        #expect(highlighted.count == GraphChatWorkspaceBudget.maximumActionNodes)

        coordinator.requestReplaceSelection([nodes[0]], in: foreignScope)
        coordinator.requestHighlight([nodes[1]], in: foreignScope)

        #expect(coordinator.pendingCanvasCommand == localCommand)
        #expect(coordinator.highlightedNodes.count == GraphChatWorkspaceBudget.maximumActionNodes)
        #expect(coordinator.highlightedNodes(in: foreignScope).isEmpty)
    }

    @Test
    func boundedSelectionAlwaysRetainsThePrimaryCanvasNode() throws {
        let graphScope = GraphScope(graphID: uuid(3_001))
        let references = (0..<80).map { index in
            reference(index + 3_100)
        }
        let primary = references.last!

        let context = GraphCopilotCanvasContext(
            graphScope: graphScope,
            graphName: "Graph",
            primaryNode: primary,
            selectedNodes: references
        )

        #expect(context.selectedNodeCount == references.count)
        #expect(context.selectedNodes.count == GraphChatWorkspaceBudget.maximumContextNodes)
        #expect(context.primaryNode == primary)
        #expect(context.selectedNodes.first == primary)
        #expect(context.selectionLaunch?.scope.nodeReferences.contains(primary.node) == true)
    }

    @Test
    func graphChangeClearsEveryGraphDerivedWorkspaceState() throws {
        let coordinator = GraphCopilotWorkspaceCoordinator()
        let graphScope = GraphScope(graphID: uuid(4))
        coordinator.handleActiveGraphChange(to: graphScope.graphID)
        let node = NodeRefKey(kind: .entity, id: uuid(5))
        coordinator.publishCanvasContext(
            GraphCopilotCanvasContext(
                graphScope: graphScope,
                graphName: "Graph A",
                primaryNode: reference(node: node, label: "Entity"),
                selectedNodes: [reference(node: node, label: "Entity")]
            )
        )
        coordinator.requestHighlight([node], in: graphScope)
        coordinator.presentResultSet(
            GraphCopilotResultSetPresentation(
                graphScope: graphScope,
                title: "Results",
                rows: [GraphCopilotResultRow(node: node, title: "Entity", subtitle: nil)]
            )
        )

        coordinator.handleActiveGraphChange(to: uuid(6))

        #expect(coordinator.canvasContext == nil)
        #expect(coordinator.pendingCanvasCommand == nil)
        #expect(coordinator.highlightedNodes.isEmpty)
        #expect(coordinator.presentedResultSet == nil)
        #expect(coordinator.highlightedNodes(in: graphScope).isEmpty)
    }

    @Test
    func chatCleanupPreservesTheVisibleCanvasContextAndRequestsHighlightRemoval() throws {
        let coordinator = GraphCopilotWorkspaceCoordinator()
        let graphScope = GraphScope(graphID: uuid(7))
        coordinator.handleActiveGraphChange(to: graphScope.graphID)
        let node = NodeRefKey(kind: .attribute, id: uuid(8))
        let context = GraphCopilotCanvasContext(
            graphScope: graphScope,
            graphName: "Graph",
            primaryNode: reference(node: node, label: "Attribute"),
            selectedNodes: [reference(node: node, label: "Attribute")]
        )
        coordinator.publishCanvasContext(context)
        coordinator.requestHighlight([node], in: graphScope)
        coordinator.presentResultSet(
            GraphCopilotResultSetPresentation(
                graphScope: graphScope,
                title: "Results",
                rows: [GraphCopilotResultRow(node: node, title: "Attribute", subtitle: nil)]
            )
        )

        coordinator.clearChatDerivedState()

        #expect(coordinator.canvasContext == context)
        #expect(coordinator.highlightedNodes.isEmpty)
        #expect(coordinator.presentedResultSet == nil)
        let command = try #require(coordinator.pendingCanvasCommand)
        #expect(command.graphScope == graphScope)
        #expect(command.action == .clearHighlight)
    }

    @Test
    func resultPresentationIsGraphSafeAndBudgeted() throws {
        let coordinator = GraphCopilotWorkspaceCoordinator()
        let graphScope = GraphScope(graphID: uuid(9))
        let foreignScope = GraphScope(graphID: uuid(10))
        coordinator.handleActiveGraphChange(to: graphScope.graphID)
        let rows = (0..<200).map { index in
            GraphCopilotResultRow(
                node: NodeRefKey(kind: .attribute, id: uuid(index + 2_000)),
                title: "Row \(index)",
                subtitle: nil
            )
        }

        let local = GraphCopilotResultSetPresentation(
            graphScope: graphScope,
            title: String(repeating: "R", count: 300),
            filterSummary: String(repeating: "F", count: 1_100),
            rows: rows
        )
        coordinator.presentResultSet(local)
        let presented = try #require(coordinator.presentedResultSet)
        #expect(presented.title.count == 240)
        #expect(presented.filterSummary?.count == 1_000)
        #expect(presented.rows.count == GraphChatWorkspaceBudget.maximumResultRows)
        #expect(presented.wasTruncated)

        coordinator.presentResultSet(
            GraphCopilotResultSetPresentation(
                graphScope: foreignScope,
                title: "Foreign",
                rows: [rows[0]]
            )
        )
        #expect(coordinator.presentedResultSet == presented)
    }

    @Test
    func pendingCanvasCommandCanBeConsumedExactlyOnce() throws {
        let coordinator = GraphCopilotWorkspaceCoordinator()
        let graphScope = GraphScope(graphID: uuid(11))
        coordinator.handleActiveGraphChange(to: graphScope.graphID)
        let node = NodeRefKey(kind: .entity, id: uuid(12))
        coordinator.requestFocus(node, in: graphScope)
        let pending = try #require(coordinator.pendingCanvasCommand)

        #expect(coordinator.consumeCanvasCommand(id: UUID()) == nil)
        #expect(coordinator.consumeCanvasCommand(id: pending.id) == pending)
        #expect(coordinator.consumeCanvasCommand(id: pending.id) == nil)
        #expect(coordinator.pendingCanvasCommand == nil)
    }

    private func reference(_ suffix: Int) -> GraphChatNodeContextReference {
        let node = NodeRefKey(kind: .attribute, id: uuid(suffix))
        return reference(node: node, label: "Node \(suffix)")
    }

    @Test
    func presentationPolicyKeepsPhoneNavigationAndBoundsThePersistedInspectorWidth() {
        #expect(
            GraphCopilotWorkspacePresentationPolicy.chatPresentationStyle(
                isRegularHorizontalSizeClass: false
            ) == .rootTab)
        #expect(
            GraphCopilotWorkspacePresentationPolicy.chatPresentationStyle(
                isRegularHorizontalSizeClass: true
            ) == .sheet)
        #expect(GraphCopilotWorkspacePresentationPolicy.normalizedInspectorWidth(100) == 320)
        #expect(GraphCopilotWorkspacePresentationPolicy.normalizedInspectorWidth(440) == 440)
        #expect(GraphCopilotWorkspacePresentationPolicy.normalizedInspectorWidth(900) == 620)
        #expect(GraphCopilotWorkspacePresentationPolicy.normalizedInspectorWidth(.infinity) == 440)
    }

    private func reference(
        node: NodeRefKey,
        label: String
    ) -> GraphChatNodeContextReference {
        GraphChatNodeContextReference(node: node, label: label)
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "C0000000-0000-0000-0000-%012d", suffix))!
    }
}
