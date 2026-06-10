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
            showsAllLinks: showAllLinksForSelection
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
               activeFocus.entityID == node.key.uuid {
                graphDetailsFocusSummaryChip(summary: detailsFocusSummaryCache)
            }
        }
    }

    func performActionRailAction(_ action: GraphCanvasActionRailActionKind, for node: GraphNode) {
        switch action {
        case .openDetails:
            openDetails(for: node.key)
        case .center:
            cameraCommand = CameraCommand(kind: .center(node.key))
        case .expandNeighbors:
            Task { await expand(from: node.key) }
        case .setFocus:
            setFocus(to: node)
        case .pin:
            pinned.insert(node.key)
            velocities[node.key] = .zero
        case .unpin:
            pinned.remove(node.key)
            velocities[node.key] = .zero
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

        focusEntity = entity
        scheduleLoadGraph(resetLayout: true)
        cameraCommand = CameraCommand(kind: .center(node.key))
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

                Text(verbatim: GraphDetailsFocusFormatting.ruleText(focusState: activeFocus, field: summary.field))
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
