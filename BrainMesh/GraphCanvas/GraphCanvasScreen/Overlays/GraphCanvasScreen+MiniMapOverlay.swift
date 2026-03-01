//
//  GraphCanvasScreen+MiniMapOverlay.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    // MARK: - MiniMap + Side status overlays

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
                positions: miniMapPositionsSnapshot,
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
}
