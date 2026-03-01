//
//  GraphCanvasScreen+ActionChipsOverlay.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Action chip

    func actionChip(for node: GraphNode) -> some View {
        let isPinned = pinned.contains(node.key)
        let hiddenLinks = hiddenLinkCountForSelection()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.key.kind == .entity ? "Entität" : "Attribut")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(verbatim: nodeLabel(for: node))
                        .font(.subheadline)
                        .lineLimit(1)
                }

                Spacer()

                // ✅ Degree cap “more/less” (never grows vertically on narrow iPhone widths)
                degreeCapToggleButton(hiddenLinks: hiddenLinks)

                // ✅ Expand
                Button {
                    Task { await expand(from: node.key) }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.bordered)
                .help("Nachbarn aufklappen")

                Button {
                    cameraCommand = CameraCommand(kind: .center(node.key))
                } label: {
                    Image(systemName: "dot.scope")
                }
                .buttonStyle(.bordered)

                if node.key.kind == .entity {
                    Button {
                        if let e = fetchEntity(id: node.key.uuid) {
                            focusEntity = e
                            scheduleLoadGraph(resetLayout: true)
                            cameraCommand = CameraCommand(kind: .center(node.key))
                        }
                    } label: {
                        Image(systemName: "scope")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    openDetails(for: node.key)
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.bordered)

                Button {
                    if isPinned { pinned.remove(node.key) }
                    else { pinned.insert(node.key) }
                    velocities[node.key] = .zero
                } label: {
                    Image(systemName: isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.bordered)

                Button {
                    selection = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
            }

            // ✅ Option A: Details Peek
            if node.key.kind == .attribute, !detailsPeekChips.isEmpty {
                detailsPeekBar(chips: detailsPeekChips)
            }

            // ✅ Entity selection summary + list of defined detail fields
            if node.key.kind == .entity {
                entityFieldsPeekPanel(summaryChips: detailsPeekChips, fields: entityFieldsPeekItems)
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6, y: 2)
        .frame(maxWidth: 640)
    }

    @ViewBuilder
    func degreeCapToggleButton(hiddenLinks: Int) -> some View {
        if hiddenLinks > 0 {
            // On iPhone portrait, the full “Mehr (12)” label can wrap and make the action chip very tall.
            // `ViewThatFits` automatically falls back to compact variants that keep the height stable.
            ViewThatFits(in: .horizontal) {
                Button {
                    showAllLinksForSelection = true
                } label: {
                    Label("Mehr (\(hiddenLinks))", systemImage: "ellipsis.circle")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(.bordered)

                Button {
                    showAllLinksForSelection = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "ellipsis.circle")
                        Text(verbatim: "\(hiddenLinks)")
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                }
                .buttonStyle(.bordered)

                Button {
                    showAllLinksForSelection = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
            }
            .accessibilityLabel("Mehr (\(hiddenLinks))")
            .help("Weitere Links dieser Node anzeigen")
        } else if showAllLinksForSelection {
            ViewThatFits(in: .horizontal) {
                Button {
                    showAllLinksForSelection = false
                } label: {
                    Label("Weniger", systemImage: "chevron.up.circle")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .buttonStyle(.bordered)

                Button {
                    showAllLinksForSelection = false
                } label: {
                    Image(systemName: "chevron.up.circle")
                }
                .buttonStyle(.bordered)
            }
            .accessibilityLabel("Weniger")
            .help("Nur die wichtigsten Links anzeigen")
        }
    }

    // MARK: - Helpers

    func nodeLabel(for node: GraphNode) -> String {
        labelCache[node.key] ?? node.label
    }

    func openDetails(for key: NodeKey) {
        switch key.kind {
        case .entity:
            if let e = fetchEntity(id: key.uuid) { selectedEntity = e }
        case .attribute:
            if let a = fetchAttribute(id: key.uuid) { selectedAttribute = a }
        }
    }
}
