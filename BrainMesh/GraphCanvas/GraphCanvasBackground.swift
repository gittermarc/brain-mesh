//
//  GraphCanvasBackground.swift
//  BrainMesh
//
//  P2: GraphCanvas rendering uses GraphTheme tokens
//

import SwiftUI

struct GraphCanvasBackground: View {
    let theme: GraphTheme

    var body: some View {
        switch theme.backgroundStyle {
        case .system:
            Color(.systemBackground)

        case .solid:
            theme.backgroundPrimary

        case .gradient:
            LinearGradient(
                colors: [theme.backgroundPrimary, theme.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

        case .grid:
            theme.backgroundPrimary
                .overlay(GraphGridOverlay(lineColor: theme.backgroundSecondary.opacity(0.35)))
        }
    }
}

private struct GraphGridOverlay: View {
    let lineColor: Color

    @State private var cachedSize: CGSize = .zero
    @State private var cachedPath: Path = Path()

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, _ in
                context.stroke(cachedPath, with: .color(lineColor), lineWidth: 1)
            }
            .onAppear { rebuildPath(for: size) }
            .onChange(of: size) { _, newSize in
                rebuildPath(for: newSize)
            }
        }
    }

    private func rebuildPath(for size: CGSize) {
        guard size != cachedSize else { return }
        cachedSize = size
        cachedPath = GraphGridOverlay.makePath(size: size, step: 18)
    }

    private static func makePath(size: CGSize, step: CGFloat) -> Path {
        let w = size.width
        let h = size.height

        var path = Path()

        var x: CGFloat = 0
        while x <= w {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: h))
            x += step
        }

        var y: CGFloat = 0
        while y <= h {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: w, y: y))
            y += step
        }
        return path
    }
}
