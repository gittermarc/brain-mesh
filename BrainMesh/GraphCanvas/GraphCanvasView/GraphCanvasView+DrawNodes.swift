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
        frame: GraphCanvasDynamicFrameCache,
        alphas: ZoomAlphas,
        theme: GraphTheme,
        colorScheme: ColorScheme
    ) {
        for preparedNode in frame.preparedNodes {
            let n = preparedNode.node
            let s = preparedNode.screenPoint

            let isPinned = pinned.contains(n.key)
            let isSelected = (selection == n.key)
            let isCopilotHighlighted = copilotHighlightedNodes.contains(n.key)
            let nodeAlpha = preparedNode.opacity
            let isMatchedDetailsAttribute =
                preparedNode.isMatchedDetailsAttribute

            switch n.key.kind {
            case .entity:
                let r: CGFloat = 16
                let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)

                let circle = Path(ellipseIn: rect)
                context.fill(
                    circle, with: .color(theme.entityColor.opacity((isPinned ? 0.20 : 0.14) * nodeAlpha)))
                context.stroke(
                    circle,
                    with: .color(theme.entityColor.opacity((isPinned ? 0.72 : 0.55) * nodeAlpha)),
                    lineWidth: isPinned ? 2 : 1
                )

                if isCopilotHighlighted {
                    let highlightRadius: CGFloat = r + (isSelected ? 8 : 5)
                    let highlightRect = CGRect(
                        x: s.x - highlightRadius,
                        y: s.y - highlightRadius,
                        width: highlightRadius * 2,
                        height: highlightRadius * 2
                    )
                    context.stroke(
                        Path(ellipseIn: highlightRect),
                        with: .color(theme.highlightColor.opacity(0.58 * nodeAlpha)),
                        lineWidth: 4
                    )
                }

                if isSelected {
                    let rr: CGFloat = r + 3
                    let ringRect = CGRect(x: s.x - rr, y: s.y - rr, width: rr * 2, height: rr * 2)
                    let ring = Path(ellipseIn: ringRect)
                    context.stroke(
                        ring, with: .color(theme.highlightColor.opacity(0.95 * nodeAlpha)), lineWidth: 3)
                }

                if let iconName = iconSymbolCache[n.key], !iconName.isEmpty {
                    let iconText = Text(Image(systemName: iconName))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.entityColor.opacity(0.95 * nodeAlpha))
                    context.draw(iconText, at: s, anchor: .center)
                }

                // Labels: Default besser sichtbar; Spotlight nur relevant
                let isRelevantInSpotlight =
                    preparedNode.isRelevantInSpotlight
                let allowLabel = (!alphas.spotlightLabelsOnly) || isRelevantInSpotlight

                if allowLabel {
                    let baseMin: CGFloat = (selection == nil) ? 0.34 : 0.10
                    let labelA =
                        max(
                            max(alphas.entityLabelAlpha, baseMin),
                            (isSelected || isCopilotHighlighted) ? 1.0 : 0.0
                        ) * nodeAlpha
                    if labelA > 0.04 {
                        let off = preparedNode.labelOffset
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
                    context.draw(
                        Text("📌").font(.caption2),
                        at: CGPoint(x: s.x + 18, y: s.y - 18),
                        anchor: .center)
                }

            case .attribute:
                let w: CGFloat = 28
                let h: CGFloat = 22
                let rect = CGRect(x: s.x - w / 2, y: s.y - h / 2, width: w, height: h)
                let rr = Path(roundedRect: rect, cornerRadius: 6)

                let fillOpacity =
                    (isPinned ? 0.18 : 0.12) * nodeAlpha * (isMatchedDetailsAttribute ? 1.45 : 1.0)
                let strokeOpacity =
                    (isPinned ? 0.70 : 0.50) * nodeAlpha * (isMatchedDetailsAttribute ? 1.20 : 1.0)
                let strokeWidth: CGFloat =
                    isMatchedDetailsAttribute ? max(isPinned ? 2 : 1, 2.4) : (isPinned ? 2 : 1)

                context.fill(rr, with: .color(theme.attributeColor.opacity(fillOpacity)))
                context.stroke(
                    rr,
                    with: .color(theme.attributeColor.opacity(strokeOpacity)),
                    lineWidth: strokeWidth
                )

                if isMatchedDetailsAttribute {
                    let haloRect = rect.insetBy(dx: -4, dy: -4)
                    let halo = Path(roundedRect: haloRect, cornerRadius: 10)
                    context.stroke(
                        halo,
                        with: .color(theme.highlightColor.opacity(0.92 * nodeAlpha)),
                        lineWidth: 3
                    )
                }

                if isCopilotHighlighted {
                    let highlightRect = rect.insetBy(
                        dx: isSelected || isMatchedDetailsAttribute ? -9 : -6,
                        dy: isSelected || isMatchedDetailsAttribute ? -9 : -6
                    )
                    context.stroke(
                        Path(roundedRect: highlightRect, cornerRadius: 12),
                        with: .color(theme.highlightColor.opacity(0.58 * nodeAlpha)),
                        lineWidth: 4
                    )
                }

                if isSelected {
                    let pad: CGFloat = isMatchedDetailsAttribute ? 5 : 3
                    let ringRect = rect.insetBy(dx: -pad, dy: -pad)
                    let ring = Path(roundedRect: ringRect, cornerRadius: isMatchedDetailsAttribute ? 10 : 8)
                    context.stroke(
                        ring, with: .color(theme.highlightColor.opacity(0.95 * nodeAlpha)), lineWidth: 3)
                }

                if let iconName = iconSymbolCache[n.key], !iconName.isEmpty {
                    let iconText = Text(Image(systemName: iconName))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.attributeColor.opacity(0.95 * nodeAlpha))
                    context.draw(iconText, at: s, anchor: .center)
                }

                let isRelevantInSpotlight =
                    preparedNode.isRelevantInSpotlight
                let allowLabel = (!alphas.spotlightLabelsOnly) || isRelevantInSpotlight

                if allowLabel {
                    let labelA =
                        max(
                            alphas.attributeLabelAlpha,
                            (isSelected || isCopilotHighlighted) ? 1.0 : 0.0
                        ) * nodeAlpha
                    if labelA > 0.06 {
                        let off = preparedNode.labelOffset
                        drawLabel(
                            n.label,
                            at: CGPoint(x: s.x + off.x, y: s.y + 24 + off.y),
                            alpha: labelA,
                            isSelected: isSelected,
                            wantHalo: isSelected || isMatchedDetailsAttribute || labelA < 0.90,
                            in: context,
                            font: .caption2,
                            maxWidth: 170,
                            theme: theme,
                            colorScheme: colorScheme
                        )
                    }
                }

                if isPinned && (alphas.attributeLabelAlpha > 0.25 || isSelected) && nodeAlpha > 0.20 {
                    context.draw(
                        Text("📌").font(.caption2),
                        at: CGPoint(x: s.x + 18, y: s.y - 14),
                        anchor: .center)
                }
            }
        }
    }
}
