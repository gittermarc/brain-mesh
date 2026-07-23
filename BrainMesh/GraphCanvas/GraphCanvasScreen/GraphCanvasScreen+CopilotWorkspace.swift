//
//  GraphCanvasScreen+CopilotWorkspace.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {
    var supportsCopilotInspector: Bool {
        GraphCopilotWorkspacePresentationPolicy.supportsInspector(
            isRegularHorizontalSizeClass: horizontalSizeClass == .regular
        )
    }

    var graphChatPresentationStyle: GraphChatPresentationStyle {
        GraphCopilotWorkspacePresentationPolicy.chatPresentationStyle(
            isRegularHorizontalSizeClass: horizontalSizeClass == .regular
        )
    }

    var copilotInspectorBinding: Binding<Bool> {
        Binding(
            get: { supportsCopilotInspector && isCopilotInspectorPresented },
            set: { isCopilotInspectorPresented = $0 }
        )
    }

    func publishCopilotCanvasContext() {
        guard let activeGraphID else {
            graphCopilotWorkspaceCoordinator.clearTransientState()
            return
        }
        let selectedReferences = canvasSelection.chatNodes.map(graphChatReference)
        let primaryReference = canvasSelection.primary.map(graphChatReference)
        graphCopilotWorkspaceCoordinator.publishCanvasContext(
            GraphCopilotCanvasContext(
                graphScope: GraphScope(graphID: activeGraphID),
                graphName: activeGraphName,
                primaryNode: primaryReference,
                selectedNodes: selectedReferences
            )
        )
    }

    func handlePendingCopilotCommand() {
        guard let pending = graphCopilotWorkspaceCoordinator.pendingCanvasCommand,
            let command = graphCopilotWorkspaceCoordinator.consumeCanvasCommand(id: pending.id)
        else {
            return
        }
        guard command.graphScope.graphID == activeGraphID else {
            return
        }

        let availableNodes = Set(nodes.map(\.key))
        switch command.action {
        case .focus(let node):
            let key = NodeKey(kind: node.kind, uuid: node.id)
            if availableNodes.contains(key) {
                selection = key
                cameraCommand = CameraCommand(kind: .center(key))
                announceCopilotAction(
                    german: "Node im Canvas fokussiert.",
                    english: "Node focused in the Canvas."
                )
            } else {
                graphJump.requestJump(
                    to: key,
                    in: command.graphScope.graphID,
                    centerOnArrival: true
                )
                Task { @MainActor in
                    handlePendingJumpIfNeeded()
                }
            }

        case .highlight(let references):
            let highlighted =
                references
                .map { NodeKey(kind: $0.kind, uuid: $0.id) }
                .filter { availableNodes.contains($0) }
            copilotHighlightedNodes = Set(highlighted)
            announceCopilotAction(
                german: "\(highlighted.count) Nodes im Canvas hervorgehoben.",
                english: "\(highlighted.count) nodes highlighted in the Canvas."
            )

        case .clearHighlight:
            copilotHighlightedNodes.removeAll()
            announceCopilotAction(
                german: "Canvas-Hervorhebung entfernt.",
                english: "Canvas highlight removed."
            )

        case .addToSelection(let references):
            let additions =
                references
                .map { NodeKey(kind: $0.kind, uuid: $0.id) }
                .filter { availableNodes.contains($0) }
            canvasSelection.add(additions)
            announceCopilotAction(
                german: "\(additions.count) Nodes zur Canvas-Auswahl hinzugefügt.",
                english: "\(additions.count) nodes added to the Canvas selection."
            )

        case .replaceSelection(let references):
            let replacement =
                references
                .map { NodeKey(kind: $0.kind, uuid: $0.id) }
                .filter { availableNodes.contains($0) }
            if replacement.isEmpty {
                announceCopilotAction(
                    german:
                        "Keine Ergebnis-Nodes sind im aktuellen Canvas geladen. Die Auswahl bleibt unverändert.",
                    english: "No result nodes are loaded in the current Canvas. The selection is unchanged."
                )
            } else {
                canvasSelection.replace(with: replacement)
                announceCopilotAction(
                    german: "Canvas-Auswahl durch \(replacement.count) Nodes ersetzt.",
                    english: "Canvas selection replaced with \(replacement.count) nodes."
                )
            }
        }
        publishCopilotCanvasContext()
    }

    func synchronizeCopilotHighlights() {
        guard let activeGraphID else {
            copilotHighlightedNodes.removeAll()
            return
        }
        let graphScope = GraphScope(graphID: activeGraphID)
        let availableNodes = Set(nodes.map(\.key))
        copilotHighlightedNodes = Set(
            graphCopilotWorkspaceCoordinator.highlightedNodes(in: graphScope)
                .map { NodeKey(kind: $0.kind, uuid: $0.id) }
                .filter { availableNodes.contains($0) }
        )
    }
    private func announceCopilotAction(
        german: String,
        english: String
    ) {
        let language = GraphChatResponseLanguageSelector.systemFallback()
        SystemGraphChatAccessibilityAnnouncer().announce(
            language == .german ? german : english
        )
    }

}
