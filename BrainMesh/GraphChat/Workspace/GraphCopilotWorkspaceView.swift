//
//  GraphCopilotWorkspaceView.swift
//  BrainMesh
//
//  Adaptive iPad inspector that reuses the productive Graph Chat host.
//

import SwiftUI

struct GraphCopilotWorkspaceView: View {
    @EnvironmentObject private var launchCoordinator: GraphChatLaunchCoordinator
    @EnvironmentObject private var sessionStore: GraphChatSessionStore
    @EnvironmentObject private var workspaceCoordinator: GraphCopilotWorkspaceCoordinator

    let graphID: UUID
    let graphName: String
    @Binding var preferredWidth: Double
    let onClose: () -> Void

    private var language: GraphChatResponseLanguage {
        GraphChatResponseLanguageSelector.systemFallback()
    }

    private var currentRequest: GraphChatLaunchRequest {
        launchCoordinator.requestForActiveGraph(graphID)
    }

    private var canvasContext: GraphCopilotCanvasContext? {
        guard workspaceCoordinator.canvasContext?.graphScope.graphID == graphID else {
            return nil
        }
        return workspaceCoordinator.canvasContext
    }

    private var selectionLaunch: GraphChatContextLaunch? {
        canvasContext?.selectionLaunch
    }

    private var selectionMatchesCurrentScope: Bool {
        selectionLaunch?.scope == currentRequest.scope
    }

    var body: some View {
        VStack(spacing: 0) {
            contextHeader
            Divider()
            GraphChatTabView()
        }
        .frame(minWidth: 320)
        .onAppear {
            preferredWidth =
                GraphCopilotWorkspacePresentationPolicy
                .normalizedInspectorWidth(preferredWidth)
        }
        .accessibilityIdentifier("graph-copilot-workspace")
    }

    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(localized("Copilot-Workspace", "Copilot workspace"), systemImage: "sidebar.right")
                    .font(.headline)
                Spacer(minLength: 8)
                widthMenu
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(localized("Copilot schließen", "Close copilot"))
            }

            Label(graphName, systemImage: "square.stack.3d.up")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .accessibilityLabel(
                    localized("Aktueller Graph: \(graphName)", "Current graph: \(graphName)"))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(localized("Chat-Scope", "Chat scope"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                GraphChatScopeChip(
                    presentation: GraphChatScopePresentation.model(
                        for: currentRequest.context,
                        scope: currentRequest.scope,
                        language: language
                    )
                )
            }

            canvasSelectionSummary
            healthFindingSummary
            scopeActions
        }
        .padding(12)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var canvasSelectionSummary: some View {
        if let canvasContext {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                    Text(
                        localized(
                            canvasContext.selectionIsTruncated
                                ? "Canvas-Auswahl: \(canvasContext.selectedNodeCount) (Kontext auf \(canvasContext.selectedNodes.count) begrenzt)"
                                : "Canvas-Auswahl: \(canvasContext.selectedNodeCount)",
                            canvasContext.selectionIsTruncated
                                ? "Canvas selection: \(canvasContext.selectedNodeCount) (context limited to \(canvasContext.selectedNodes.count))"
                                : "Canvas selection: \(canvasContext.selectedNodeCount)"
                        )
                    )
                    .font(.caption.weight(.semibold))
                }

                if let primary = canvasContext.primaryNode {
                    Text(
                        localized(
                            "Aktueller Node: \(primary.label)",
                            "Current node: \(primary.label)"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                } else {
                    Text(localized("Keine Canvas-Auswahl", "No canvas selection"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text(
                localized(
                    "Canvas-Kontext wird verfügbar, sobald der Graph sichtbar ist.",
                    "Canvas context becomes available when the graph is visible.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var healthFindingSummary: some View {
        if case .healthFinding(let finding) = currentRequest.context {
            Label(
                "\(finding.title) · \(finding.count)",
                systemImage: "stethoscope"
            )
            .font(.caption.weight(.semibold))
            .accessibilityLabel(
                localized(
                    "Aktiver Health-Befund: \(finding.title), \(finding.count) betroffene Nodes",
                    "Active health finding: \(finding.title), \(finding.count) affected nodes"
                )
            )
        }
    }

    private var scopeActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                adoptSelectionButton
                wholeGraphButton
            }
            VStack(alignment: .leading, spacing: 8) {
                adoptSelectionButton
                wholeGraphButton
            }
        }
    }

    private var adoptSelectionButton: some View {
        Button {
            guard let selectionLaunch else {
                return
            }
            launchCoordinator.launch(
                selectionLaunch,
                presentationStyle: .sheet
            )
        } label: {
            Label(
                localized("Auswahl als Chat-Kontext", "Use selection as chat context"),
                systemImage: "checkmark.circle.badge.questionmark"
            )
            .frame(minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(
            selectionLaunch == nil
                || selectionMatchesCurrentScope
                || sessionStore.isGenerationRunning
        )
        .accessibilityHint(
            sessionStore.isGenerationRunning
                ? localized(
                    "Während der laufenden Antwort bleibt der ursprüngliche Scope unverändert.",
                    "The original scope remains unchanged while the answer is streaming."
                )
                : localized(
                    "Wechselt bewusst auf einen graph-sicheren Snapshot der aktuellen Canvas-Auswahl.",
                    "Explicitly switches to a graph-safe snapshot of the current canvas selection."
                )
        )
    }

    private var wholeGraphButton: some View {
        Button {
            launchCoordinator.launch(
                GraphChatContextEntryPoint.wholeGraph(
                    graphID: graphID,
                    graphName: graphName
                ),
                presentationStyle: .sheet
            )
        } label: {
            Label(localized("Gesamter Graph", "Entire graph"), systemImage: "square.stack.3d.up")
                .frame(minHeight: 34)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(
            currentRequest.scope == .entireGraph(GraphScope(graphID: graphID))
                || sessionStore.isGenerationRunning
        )
    }

    private var widthMenu: some View {
        Menu {
            Button(localized("Kompakt", "Compact")) { preferredWidth = 360 }
            Button(localized("Standard", "Standard")) { preferredWidth = 440 }
            Button(localized("Breit", "Wide")) { preferredWidth = 560 }
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(localized("Copilot-Breite", "Copilot width"))
    }

    private func localized(_ german: String, _ english: String) -> String {
        language == .german ? german : english
    }
}

struct GraphCopilotResultSetSheet: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: GraphCopilotResultSetPresentation
    let onFocus: (NodeRefKey) -> Void
    let onAddAll: ([NodeRefKey]) -> Void
    let onReplaceAll: ([NodeRefKey]) -> Void

    private var language: GraphChatResponseLanguage {
        GraphChatResponseLanguageSelector.systemFallback()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let filterSummary = presentation.filterSummary {
                        Label(filterSummary, systemImage: "line.3.horizontal.decrease.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }

                    ForEach(presentation.rows) { row in
                        Button {
                            onFocus(row.node)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName: row.node.kind == .entity ? "square.3.layers.3d" : "circle.hexagongrid"
                                )
                                .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.title)
                                        .font(.body.weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                    if let subtitle = row.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "scope")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 12)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            localized(
                                "Fokussiert diesen Node im Canvas.",
                                "Focuses this node in the Canvas."
                            )
                        )
                    }

                    if presentation.wasTruncated {
                        Label(
                            localized(
                                "Die Liste ist auf die sicher geladene Ergebnismenge begrenzt.",
                                "The list is limited to the safely loaded result set."
                            ),
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        onAddAll(presentation.rows.map(\.node))
                        dismiss()
                    } label: {
                        Label(
                            localized("Zur Auswahl", "Add to selection"),
                            systemImage: "plus.circle"
                        )
                    }
                    Spacer()
                    Button {
                        onReplaceAll(presentation.rows.map(\.node))
                        dismiss()
                    } label: {
                        Label(
                            localized("Auswahl ersetzen", "Replace selection"),
                            systemImage: "checkmark.circle"
                        )
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("Fertig", "Done")) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .accessibilityIdentifier("graph-copilot-result-set")
    }

    private func localized(_ german: String, _ english: String) -> String {
        language == .german ? german : english
    }
}
