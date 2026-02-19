//
//  GraphAppearancePreview.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct GraphAppearancePreview: View {
    let theme: GraphTheme

    var body: some View {
        ZStack {
            background
            Canvas { context, size in
                let w = size.width
                let h = size.height

                let a = CGPoint(x: w * 0.28, y: h * 0.55) // entity
                let b = CGPoint(x: w * 0.70, y: h * 0.35) // entity
                let c = CGPoint(x: w * 0.72, y: h * 0.72) // attribute
                let d = CGPoint(x: w * 0.38, y: h * 0.28) // attribute

                // Edges
                drawLine(from: a, to: b, in: &context, color: theme.linkColor.opacity(0.85), width: 2)
                drawLine(from: b, to: c, in: &context, color: theme.containmentColor.opacity(0.9), width: 2, dashed: true)
                drawLine(from: a, to: d, in: &context, color: theme.linkColor.opacity(0.65), width: 2)

                // Nodes
                drawEntity(at: a, in: &context, fill: theme.entityColor)
                drawEntity(at: b, in: &context, fill: theme.entityColor.opacity(0.92))
                drawAttribute(at: c, in: &context, fill: theme.attributeColor)
                drawAttribute(at: d, in: &context, fill: theme.attributeColor.opacity(0.92))

                // Highlight ring
                let ringRect = CGRect(x: a.x - 18, y: a.y - 18, width: 36, height: 36)
                let ring = Path(ellipseIn: ringRect)
                context.stroke(ring, with: .color(theme.highlightColor), lineWidth: 3)

                // Labels
                drawLabel("Entität", at: CGPoint(x: a.x, y: a.y + 26), in: &context)
                drawLabel("Entität", at: CGPoint(x: b.x, y: b.y + 26), in: &context)
                drawLabel("Attribut", at: CGPoint(x: c.x, y: c.y + 24), in: &context)
                drawLabel("Attribut", at: CGPoint(x: d.x, y: d.y + 24), in: &context)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        switch theme.backgroundStyle {
        case .system:
            Color(.systemBackground)

        case .solid:
            theme.backgroundPrimary

        case .gradient:
            LinearGradient(colors: [theme.backgroundPrimary, theme.backgroundSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)

        case .grid:
            theme.backgroundPrimary
                .overlay(GridOverlay(lineColor: gridLineColor))
        }
    }

    private var gridLineColor: Color {
        // A subtle line color derived from the secondary color.
        theme.backgroundSecondary.opacity(0.35)
    }

    private func drawLine(from: CGPoint, to: CGPoint, in context: inout GraphicsContext, color: Color, width: CGFloat, dashed: Bool = false) {
        var p = Path()
        p.move(to: from)
        p.addLine(to: to)

        var style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        if dashed {
            style.dash = [6, 5]
        }

        context.stroke(p, with: .color(color), style: style)
    }

    private func drawEntity(at point: CGPoint, in context: inout GraphicsContext, fill: Color) {
        let rect = CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)
        let shape = Path(ellipseIn: rect)
        context.fill(shape, with: .color(fill))
        context.stroke(shape, with: .color(fill.opacity(0.25)), lineWidth: 2)
    }

    private func drawAttribute(at point: CGPoint, in context: inout GraphicsContext, fill: Color) {
        let rect = CGRect(x: point.x - 16, y: point.y - 10, width: 32, height: 20)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous).path(in: rect)
        context.fill(shape, with: .color(fill))
        context.stroke(shape, with: .color(fill.opacity(0.25)), lineWidth: 2)
    }

    private func drawLabel(_ text: String, at point: CGPoint, in context: inout GraphicsContext) {
        let base = Text(text)
            .font(.caption.weight(.semibold))

        if theme.labelHaloEnabled {
            // Canvas can only draw `Text` (not arbitrary Views). We fake a halo by drawing
            // the same text multiple times with small offsets in a darker color.
            let halo = base.foregroundColor(.black.opacity(0.8))
            let offsets: [CGPoint] = [
                CGPoint(x: -1, y: -1), CGPoint(x: -1, y: 0), CGPoint(x: -1, y: 1),
                CGPoint(x: 0, y: -1),                    CGPoint(x: 0, y: 1),
                CGPoint(x: 1, y: -1),  CGPoint(x: 1, y: 0),  CGPoint(x: 1, y: 1)
            ]
            for o in offsets {
                context.draw(halo, at: CGPoint(x: point.x + o.x, y: point.y + o.y), anchor: .center)
            }
        }

        let main = base.foregroundColor(.primary)
        context.draw(main, at: point, anchor: .center)
    }
}

private struct GridOverlay: View {
    let lineColor: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { context, _ in
                let step: CGFloat = 18
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

                context.stroke(path, with: .color(lineColor), lineWidth: 1)
            }
        }
    }
}
