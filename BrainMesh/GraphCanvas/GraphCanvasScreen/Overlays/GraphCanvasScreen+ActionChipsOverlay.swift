//
//  GraphCanvasScreen+ActionChipsOverlay.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Selection action rail

    func actionChip(for node: GraphNode) -> some View {
        let hiddenLinks = GraphCanvasDisplayEdgesPlanner.hiddenLinkCount(
            selection: selection,
            allEdges: edges,
            showAllLinksForSelection: false,
            degreeCap: degreeCap
        )

        let model = GraphCanvasActionRailModel(
            nodeKind: node.key.kind,
            isPinned: pinned.contains(node.key),
            hiddenLinkCount: hiddenLinks,
            showsAllLinks: showAllLinksForSelection,
            selectionCount: canvasSelection.chatNodeCount,
            isPrimaryRetained: canvasSelection.isPrimaryRetained,
            language: GraphChatResponseLanguageSelector.systemFallback()
        )

        return GraphCanvasActionRail(
            title: nodeLabel(for: node),
            model: model,
            onAction: { action in
                performActionRailAction(action, for: node)
            },
            supplementaryContent: {
                actionRailSupplementaryContent(for: node)
            }
        )
    }

    @ViewBuilder
    func actionRailSupplementaryContent(for node: GraphNode) -> some View {
        if node.key.kind == .attribute, !detailsPeekChips.isEmpty {
            detailsPeekBar(chips: detailsPeekChips)
        }

        if node.key.kind == .entity {
            entityFieldsPeekPanel(summaryChips: detailsPeekChips, fields: entityFieldsPeekItems)

            if let activeFocus = detailsFocusSummaryCache.activeFocus,
                activeFocus.entityID == node.key.uuid
            {
                graphDetailsFocusSummaryChip(summary: detailsFocusSummaryCache)
            }
        }
    }

    func performActionRailAction(_ action: GraphCanvasActionRailActionKind, for node: GraphNode) {
        switch action {
        case .openDetails:
            openDetails(for: node.key)
        case .askGraph:
            openGraphChat(for: node.key)
        case .addToSelection, .removeFromSelection:
            canvasSelection.togglePrimaryRetention()
        case .chatWithSelection:
            openGraphChatForSelection()
        case .center:
            cameraCommand = CameraCommand(kind: .center(node.key))
        case .expandNeighbors:
            Task { await expand(from: node.key) }
        case .setFocus:
            setFocus(to: node)
        case .pin:
            pinned.insert(node.key)
        case .unpin:
            pinned.remove(node.key)
        case .showMoreLinks:
            showAllLinksForSelection = true
        case .showFewerLinks:
            showAllLinksForSelection = false
        case .closeSelection:
            selection = nil
        }
    }

    func setFocus(to node: GraphNode) {
        guard node.key.kind == .entity else { return }
        guard let entity = fetchEntity(id: node.key.uuid) else { return }

        setFocusEntity(
            entity,
            recordInHistory: true,
            selectFocus: true,
            resetHops: true,
            resetLayout: true,
            centerAfterLoad: true,
            scheduleReload: true
        )
    }

    @ViewBuilder
    func graphDetailsFocusSummaryChip(summary: GraphDetailsMatchSummary) -> some View {
        if let activeFocus = summary.activeFocus {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.tint)
                    Text("Details-Fokus aktiv")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(activeFocus.mode.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(
                    verbatim: GraphDetailsFocusFormatting.ruleText(
                        focusState: activeFocus, field: summary.field)
                )
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

                Text(verbatim: "Treffer \(summary.matchCount) von \(summary.inspectedAttributeCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.tint.opacity(0.24))
            )
        }
    }

    // MARK: - Helpers

    func nodeLabel(for node: GraphNode) -> String {
        labelCache[node.key] ?? node.label
    }

    func openGraphChat(for key: NodeKey) {
        guard let activeGraphID else {
            return
        }
        let reference = graphChatReference(for: key)
        let launch = GraphChatContextEntryPoint.graphNode(
            graphID: activeGraphID,
            node: key,
            label: reference.label,
            entityID: reference.entityID,
            entityName: reference.entityName
        )
        graphChatLaunch(
            launch,
            presentationStyle: graphChatPresentationStyle
        )
        if supportsCopilotInspector {
            isCopilotInspectorPresented = true
        } else {
            tabRouter.openChat()
        }
    }

    func openGraphChatForSelection() {
        guard let activeGraphID else {
            return
        }
        let references = canvasSelection.chatNodes.map(graphChatReference)
        guard
            let launch = GraphChatContextEntryPoint.selection(
                graphID: activeGraphID,
                nodes: references
            )
        else {
            return
        }
        graphChatLaunch(
            launch,
            presentationStyle: graphChatPresentationStyle
        )
        if supportsCopilotInspector {
            isCopilotInspectorPresented = true
        } else {
            tabRouter.openChat()
        }
    }

    func graphChatReference(for key: NodeKey) -> GraphChatNodeContextReference {
        switch key.kind {
        case .entity:
            let entity = fetchEntity(id: key.uuid)
            return GraphChatNodeContextReference(
                node: NodeRefKey(kind: key.kind, id: key.uuid),
                label: entity?.name ?? labelCache[key] ?? "Entity",
                entityID: entity?.id,
                entityName: entity?.name
            )
        case .attribute:
            let attribute = fetchAttribute(id: key.uuid)
            return GraphChatNodeContextReference(
                node: NodeRefKey(kind: key.kind, id: key.uuid),
                label: attribute?.name ?? labelCache[key] ?? "Attribut",
                entityID: attribute?.owner?.id,
                entityName: attribute?.owner?.name
            )
        }
    }

    func openDetails(for key: NodeKey) {
        switch key.kind {
        case .entity:
            if let entity = fetchEntity(id: key.uuid) {
                selectedEntity = entity
            }
        case .attribute:
            if let attribute = fetchAttribute(id: key.uuid) {
                selectedAttribute = attribute
            }
        }
    }
}
