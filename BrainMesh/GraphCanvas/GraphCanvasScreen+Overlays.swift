//
//  GraphCanvasScreen+Overlays.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - Overlays

    @ViewBuilder
    var loadingChipOverlay: some View {
        if isLoading {
            HStack(spacing: 8) {
                ProgressView()
                Text("Lade…")
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    var sideStatusOverlay: some View {
        GeometryReader { geo in
            let x = geo.safeAreaInsets.leading + 16
            sideStatusBar
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .position(x: x, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    func miniMapOverlay(drawEdges: [GraphEdge]) -> some View {
        GeometryReader { geo in
            MiniMapView(
                nodes: nodes,
                edges: drawEdges,
                positions: positions,
                selection: selection,
                focus: focusKey,
                scale: scale,
                pan: pan,
                canvasSize: geo.size
            )
            .frame(width: 180, height: 125)
            .opacity(miniMapEmphasized ? 1.0 : 0.55)
            .scaleEffect(miniMapEmphasized ? 1.02 : 1.0)
            .padding(.trailing, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Side status bar

    var sideStatusBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                let scope = (focusEntity == nil) ? "Global" : "Fokus"
                Text(verbatim: "\(activeGraphName) · \(scope)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(verbatim: focusEntity?.name ?? "Alle Entitäten")
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Divider().frame(height: 20)

            Text(verbatim: "N \(nodes.count) · L \(edges.count) · 📌 \(pinned.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    var focusKey: NodeKey? {
        guard let f = focusEntity else { return nil }
        return NodeKey(kind: .entity, uuid: f.id)
    }

    func pulseMiniMap() {
        miniMapPulseTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) { miniMapEmphasized = true }
        miniMapPulseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: 0.25)) { miniMapEmphasized = false }
        }
    }

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

                // ✅ Degree cap “more”
                if hiddenLinks > 0 {
                    Button {
                        showAllLinksForSelection = true
                    } label: {
                        Label("Mehr (\(hiddenLinks))", systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("Weitere Links dieser Node anzeigen")
                } else if showAllLinksForSelection {
                    Button {
                        showAllLinksForSelection = false
                    } label: {
                        Label("Weniger", systemImage: "chevron.up.circle")
                    }
                    .buttonStyle(.bordered)
                }

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

            // ✅ Option A: Details Peek (read-only)
            if node.key.kind == .attribute, !detailsPeekChips.isEmpty {
                detailsPeekBar(chips: detailsPeekChips)
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(radius: 6, y: 2)
        .frame(maxWidth: 640)
    }

    func detailsPeekBar(chips: [GraphDetailsPeekChip]) -> some View {
        let visible = 3

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chips.prefix(visible))) { chip in
                    detailsPeekChip(chip)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func detailsPeekChip(_ chip: GraphDetailsPeekChip) -> some View {
        (Text(verbatim: chip.fieldName).foregroundStyle(.secondary)
         + Text(verbatim: ": ").foregroundStyle(.secondary)
         + Text(verbatim: chip.valueText).foregroundStyle(chip.isPlaceholder ? .secondary : .primary))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(.secondary.opacity(0.18))
            )
    }

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
