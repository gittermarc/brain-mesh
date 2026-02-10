//
//  MiniMapView.swift
//  BrainMesh
//
//  Extracted from GraphCanvasScreen.swift (P0.1)
//

import SwiftUI

struct MiniMapView: View {
    @EnvironmentObject private var appearance: AppearanceStore

    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let positions: [NodeKey: CGPoint]

    let selection: NodeKey?
    let focus: NodeKey?

    let scale: CGFloat
    let pan: CGSize
    let canvasSize: CGSize

    private var theme: GraphTheme {
        GraphTheme(settings: appearance.settings.graph)
    }

    var body: some View {
        let theme = self.theme

        Canvas { context, size in
            guard let bounds = worldBounds() else {
                let frame = CGRect(origin: .zero, size: size)
                context.stroke(
                    Path(roundedRect: frame, cornerRadius: 12),
                    with: .color(theme.linkColor.opacity(0.22)),
                    lineWidth: 1
                )
                return
            }

            let worldRect = bounds.insetBy(dx: -60, dy: -60)

            func map(_ p: CGPoint) -> CGPoint {
                let nx = (p.x - worldRect.minX) / max(1, worldRect.width)
                let ny = (p.y - worldRect.minY) / max(1, worldRect.height)
                return CGPoint(x: nx * size.width, y: ny * size.height)
            }

            for e in edges {
                guard let p1 = positions[e.a], let p2 = positions[e.b] else { continue }
                let a = map(p1)
                let b = map(p2)

                var path = Path()
                path.move(to: a)
                path.addLine(to: b)

                switch e.type {
                case .containment:
                    context.stroke(path, with: .color(theme.containmentColor.opacity(0.26)), lineWidth: 1)
                case .link:
                    context.stroke(path, with: .color(theme.linkColor.opacity(0.34)), lineWidth: 1)
                }
            }

            for n in nodes {
                guard let p = positions[n.key] else { continue }
                let s = map(p)

                let isFocus = (focus == n.key)
                let isSel = (selection == n.key)

                let r: CGFloat = (n.key.kind == .entity) ? 3.2 : 2.6
                let dot = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
                let dotColor = (n.key.kind == .entity) ? theme.entityColor : theme.attributeColor
                context.fill(Path(ellipseIn: dot), with: .color(dotColor.opacity(0.55)))

                if isFocus || isSel {
                    let rr: CGFloat = isSel ? 7.0 : 5.8
                    let ring = CGRect(x: s.x - rr, y: s.y - rr, width: rr * 2, height: rr * 2)
                    context.stroke(
                        Path(ellipseIn: ring),
                        with: .color(theme.highlightColor.opacity(isSel ? 0.95 : 0.70)),
                        lineWidth: isSel ? 2 : 1
                    )
                }
            }

            let v = viewportWorldRect()
            let tl = map(CGPoint(x: v.minX, y: v.minY))
            let br = map(CGPoint(x: v.maxX, y: v.maxY))

            let vRect = CGRect(
                x: min(tl.x, br.x),
                y: min(tl.y, br.y),
                width: abs(br.x - tl.x),
                height: abs(br.y - tl.y)
            )

            context.stroke(
                Path(roundedRect: vRect, cornerRadius: 8),
                with: .color(theme.highlightColor.opacity(0.70)),
                lineWidth: 2
            )

            let frame = CGRect(origin: .zero, size: size)
            context.stroke(
                Path(roundedRect: frame, cornerRadius: 12),
                with: .color(theme.linkColor.opacity(0.22)),
                lineWidth: 1
            )
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6, y: 2)
    }

    private func worldBounds() -> CGRect? {
        var minX: CGFloat = .greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude

        var any = false
        for n in nodes {
            guard let p = positions[n.key] else { continue }
            any = true
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        guard any else { return nil }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    private func viewportWorldRect() -> CGRect {
        let centerX = canvasSize.width / 2 + pan.width
        let centerY = canvasSize.height / 2 + pan.height

        let tl = CGPoint(x: (0 - centerX) / scale, y: (0 - centerY) / scale)
        let br = CGPoint(x: (canvasSize.width - centerX) / scale, y: (canvasSize.height - centerY) / scale)

        return CGRect(
            x: min(tl.x, br.x),
            y: min(tl.y, br.y),
            width: abs(br.x - tl.x),
            height: abs(br.y - tl.y)
        )
    }
}
