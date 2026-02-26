//
//  GraphCanvasView+DrawNodes.swift
//  BrainMesh
//
//  P0.3: Split GraphCanvasView+Rendering.swift -> DrawNodes
//

import SwiftUI

extension GraphCanvasView {
    func drawNodes(
        in context: GraphicsContext,
        frame: FrameCache,
        alphas: ZoomAlphas,
        theme: GraphTheme,
        colorScheme: ColorScheme
    ) {
        for n in nodes {
            if lens.hideNonRelevant && lens.isHidden(n.key) { continue }
            guard let s = frame.screenPoints[n.key] else { continue }

            let isPinned = pinned.contains(n.key)
            let isSelected = (selection == n.key)
            let nodeAlpha = lens.nodeOpacity(n.key)

            switch n.key.kind {
            case .entity:
                let r: CGFloat = 16
                let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)

                let circle = Path(ellipseIn: rect)
                context.fill(circle, with: .color(theme.entityColor.opacity((isPinned ? 0.20 : 0.14) * nodeAlpha)))
                context.stroke(
                    circle,
                    with: .color(theme.entityColor.opacity((isPinned ? 0.72 : 0.55) * nodeAlpha)),
                    lineWidth: isPinned ? 2 : 1
                )

                if isSelected {
                    let rr: CGFloat = r + 3
                    let ringRect = CGRect(x: s.x - rr, y: s.y - rr, width: rr * 2, height: rr * 2)
                    let ring = Path(ellipseIn: ringRect)
                    context.stroke(ring, with: .color(theme.highlightColor.opacity(0.95 * nodeAlpha)), lineWidth: 3)
                }

                if let iconName = iconSymbolCache[n.key], !iconName.isEmpty {
                    let iconText = Text(Image(systemName: iconName))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.entityColor.opacity(0.95 * nodeAlpha))
                    context.draw(iconText, at: s, anchor: .center)
                }

                // Labels: Default besser sichtbar; Spotlight nur relevant
                let isRelevantInSpotlight = (lens.distance[n.key] != nil)
                let allowLabel = (!alphas.spotlightLabelsOnly) || isRelevantInSpotlight

                if allowLabel {
                    let baseMin: CGFloat = (selection == nil) ? 0.34 : 0.10
                    let labelA = max(max(alphas.entityLabelAlpha, baseMin), isSelected ? 1.0 : 0.0) * nodeAlpha
                    if labelA > 0.04 {
                        let off = frame.labelOffsets[n.key] ?? .zero
                        drawLabel(
                            n.label,
                            at: CGPoint(x: s.x + off.x, y: s.y + 28 + off.y),
                            alpha: labelA,
                            isSelected: isSelected,
                            wantHalo: (selection == nil) || isSelected || labelA < 0.92,
                            in: context,
                            font: .caption.weight(.semibold),
                            maxWidth: 190,
                            theme: theme,
                            colorScheme: colorScheme
                        )
                    }
                }

                if isPinned && (alphas.entityLabelAlpha > 0.25 || isSelected) && nodeAlpha > 0.20 {
                    context.draw(Text("📌").font(.caption2),
                                 at: CGPoint(x: s.x + 18, y: s.y - 18),
                                 anchor: .center)
                }

            case .attribute:
                let w: CGFloat = 28
                let h: CGFloat = 22
                let rect = CGRect(x: s.x - w/2, y: s.y - h/2, width: w, height: h)
                let rr = Path(roundedRect: rect, cornerRadius: 6)

                context.fill(rr, with: .color(theme.attributeColor.opacity((isPinned ? 0.18 : 0.12) * nodeAlpha)))
                context.stroke(
                    rr,
                    with: .color(theme.attributeColor.opacity((isPinned ? 0.70 : 0.50) * nodeAlpha)),
                    lineWidth: isPinned ? 2 : 1
                )

                if isSelected {
                    let pad: CGFloat = 3
                    let ringRect = rect.insetBy(dx: -pad, dy: -pad)
                    let ring = Path(roundedRect: ringRect, cornerRadius: 8)
                    context.stroke(ring, with: .color(theme.highlightColor.opacity(0.95 * nodeAlpha)), lineWidth: 3)
                }

                if let iconName = iconSymbolCache[n.key], !iconName.isEmpty {
                    let iconText = Text(Image(systemName: iconName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.attributeColor.opacity(0.95 * nodeAlpha))
                    context.draw(iconText, at: s, anchor: .center)
                }

                let isRelevantInSpotlight = (lens.distance[n.key] != nil)
                let allowLabel = (!alphas.spotlightLabelsOnly) || isRelevantInSpotlight

                if allowLabel {
                    let labelA = max(alphas.attributeLabelAlpha, isSelected ? 1.0 : 0.0) * nodeAlpha
                    if labelA > 0.06 {
                        let off = frame.labelOffsets[n.key] ?? .zero
                        drawLabel(
                            n.label,
                            at: CGPoint(x: s.x + off.x, y: s.y + 24 + off.y),
                            alpha: labelA,
                            isSelected: isSelected,
                            wantHalo: isSelected || labelA < 0.90,
                            in: context,
                            font: .caption2,
                            maxWidth: 170,
                            theme: theme,
                            colorScheme: colorScheme
                        )
                    }
                }

                if isPinned && (alphas.attributeLabelAlpha > 0.25 || isSelected) && nodeAlpha > 0.20 {
                    context.draw(Text("📌").font(.caption2),
                                 at: CGPoint(x: s.x + 18, y: s.y - 14),
                                 anchor: .center)
                }
            }
        }
    }
}
