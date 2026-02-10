//
//  GraphCanvasView+Rendering.swift
//  BrainMesh
//
//  P0.1: Split GraphCanvasView.swift -> Rendering
//

import SwiftUI
import UIKit

extension GraphCanvasView {
    struct ZoomAlphas {
        let entityLabelAlpha: CGFloat
        let attributeLabelAlpha: CGFloat
        let noteAlpha: CGFloat
        let showNotes: Bool
        let thumbAlpha: CGFloat
        let spotlightLabelsOnly: Bool
    }

    func zoomAlphas() -> ZoomAlphas {
        let entityLabelAlpha = fade(scale, from: 0.55, to: 0.88)
        let attributeLabelAlpha = fade(scale, from: 1.20, to: 1.42)
        let noteAlpha = fade(scale, from: 1.32, to: 1.52)
        let thumbAlpha = fade(scale, from: 1.26, to: 1.42)

        let spotlightLabelsOnly = (selection != nil)
        let showNotes = (noteAlpha > 0.02) && (selection != nil)

        return ZoomAlphas(
            entityLabelAlpha: entityLabelAlpha,
            attributeLabelAlpha: attributeLabelAlpha,
            noteAlpha: noteAlpha,
            showNotes: showNotes,
            thumbAlpha: thumbAlpha,
            spotlightLabelsOnly: spotlightLabelsOnly
        )
    }

    func renderCanvas(in context: GraphicsContext, size: CGSize, alphas: ZoomAlphas, theme: GraphTheme, colorScheme: ColorScheme) {
        let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)

        // edges (DRAW)
        for e in drawEdges {
            if lens.hideNonRelevant && (lens.isHidden(e.a) || lens.isHidden(e.b)) { continue }

            guard let p1 = positions[e.a], let p2 = positions[e.b] else { continue }
            let a = toScreen(p1, center: center)
            let b = toScreen(p2, center: center)

            let edgeAlpha = lens.edgeOpacity(a: e.a, b: e.b)

            var path = Path()
            path.move(to: a)
            path.addLine(to: b)

            let zoomEdgeFactor = max(0.65, min(1.0, scale / 1.0))
            let baseLink = 0.40 * edgeAlpha * zoomEdgeFactor
            let baseContain = 0.22 * edgeAlpha * zoomEdgeFactor

            switch e.type {
            case .containment:
                context.stroke(path, with: .color(theme.containmentColor.opacity(baseContain)), lineWidth: 1)
            case .link:
                context.stroke(path, with: .color(theme.linkColor.opacity(baseLink)), lineWidth: 1)
            }

            // ✅ Notizen: nur im Nah-Zoom + nur für Kanten der selektierten Node (ausgehend)
            if alphas.showNotes, let sel = selection, e.type == .link {
                if sel == e.a {
                    drawOutgoingNoteIfAny(source: e.a, target: e.b, from: a, to: b, alpha: alphas.noteAlpha, in: context)
                } else if sel == e.b {
                    drawOutgoingNoteIfAny(source: e.b, target: e.a, from: b, to: a, alpha: alphas.noteAlpha, in: context)
                }
            }
        }

        // nodes
        for n in nodes {
            if lens.hideNonRelevant && lens.isHidden(n.key) { continue }
            guard let p = positions[n.key] else { continue }

            let s = toScreen(p, center: center)

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
                        let off = labelOffset(for: n.key, kind: .entity)
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
                        let off = labelOffset(for: n.key, kind: .attribute)
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

    @ViewBuilder
    func selectionThumbnailOverlay(size: CGSize, thumbAlpha: CGFloat) -> some View {
        if thumbAlpha > 0.05,
           let sel = selection,
           let wp = positions[sel],
           let img = cachedThumb {

            let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
            let sp = toScreen(wp, center: center)

            let rawX = sp.x + 54
            let rawY = sp.y - 54

            let x = min(max(44, rawX), size.width - 44)
            let y = min(max(44, rawY), size.height - 44)

            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.45), lineWidth: 1))
                .shadow(radius: 8, y: 3)
                .opacity(0.25 + 0.75 * thumbAlpha)
                .position(x: x, y: y)
                .onTapGesture { onTapSelectedThumbnail() }
        }
    }

    // MARK: - Thumbnail cache

    func refreshThumbnailCache() {
        let path = selectedImagePath
        guard path != cachedThumbPath else { return }
        cachedThumbPath = path
        cachedThumb = nil

        guard let path, !path.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let full = ImageStore.loadUIImage(path: path) else { return }
            let thumb = full.preparingThumbnail(of: CGSize(width: 160, height: 160)) ?? full
            DispatchQueue.main.async {
                if cachedThumbPath == path {
                    cachedThumb = thumb
                }
            }
        }
    }

    // MARK: - Semantic Zoom helpers

    private func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }

    private func fade(_ value: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
        guard b > a else { return value >= b ? 1 : 0 }
        return clamp01((value - a) / (b - a))
    }

    // MARK: - Stable jitter helpers

    private func stableSeed(_ s: String) -> Int {
        var h: Int = 0
        for u in s.unicodeScalars {
            h = (h &* 31) &+ Int(u.value)
        }
        return h
    }

    private enum LabelKind { case entity, attribute }

    private func labelOffset(for key: NodeKey, kind: LabelKind) -> CGPoint {
        let h = stableSeed(key.identifier)
        let xChoices: [CGFloat] = [-14, 0, 14]
        let yChoicesEntity: [CGFloat] = [0, 6, 12]
        let yChoicesAttr: [CGFloat] = [0, -6, -12]

        let xi = abs(h) % xChoices.count
        let yi = abs(h / 7) % 3

        let x = xChoices[xi]
        let y = (kind == .entity) ? yChoicesEntity[yi] : yChoicesAttr[yi]
        return CGPoint(x: x, y: y)
    }

    // MARK: - Label drawing (Halo)

    private func drawLabel(
        _ textStr: String,
        at p: CGPoint,
        alpha: CGFloat,
        isSelected: Bool,
        wantHalo: Bool,
        in context: GraphicsContext,
        font: Font,
        maxWidth: CGFloat,
        theme: GraphTheme,
        colorScheme: ColorScheme
    ) {
        let _ = maxWidth // kept for call-site stability; Canvas text does not hard-wrap by width

        let base = Text(textStr)
            .font(font)

        if theme.labelHaloEnabled && (wantHalo || isSelected) {
            let haloBase: Color = (colorScheme == .dark) ? .black : .white
            let halo = base.foregroundColor(haloBase.opacity(min(1.0, 0.88 * alpha)))
            let offsets: [CGPoint] = [
                CGPoint(x: -1, y: -1), CGPoint(x: -1, y: 0), CGPoint(x: -1, y: 1),
                CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1),
                CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)
            ]
            for o in offsets {
                context.draw(halo, at: CGPoint(x: p.x + o.x, y: p.y + o.y), anchor: .center)
            }
        }

        let main = base.foregroundColor(.primary.opacity(alpha))
        context.draw(main, at: p, anchor: .center)
    }

    // MARK: - Notes

    private func drawOutgoingNoteIfAny(
        source: NodeKey,
        target: NodeKey,
        from a: CGPoint,
        to b: CGPoint,
        alpha: CGFloat,
        in context: GraphicsContext
    ) {
        let k = DirectedEdgeKey.make(source: source, target: target, type: .link)
        guard let note = directedEdgeNotes[k], !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        drawEdgeNote(note, source: source, target: target, from: a, to: b, alpha: alpha, in: context)
    }

    private func drawEdgeNote(
        _ raw: String,
        source: NodeKey,
        target: NodeKey,
        from a: CGPoint,
        to b: CGPoint,
        alpha: CGFloat,
        in context: GraphicsContext
    ) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let maxChars = 46
        let textStr = trimmed.count > maxChars ? (String(trimmed.prefix(maxChars)) + "…") : trimmed

        let midBase = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)

        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(1.0, sqrt(dx*dx + dy*dy))
        let nx = -dy / len
        let ny = dx / len

        let side = (stableSeed(source.identifier + "->" + target.identifier) % 2 == 0) ? CGFloat(1) : CGFloat(-1)
        var offset: CGFloat = 14
        if len < 120 { offset = 20 }

        let mid = CGPoint(x: midBase.x + nx * offset * side,
                          y: midBase.y + ny * offset * side - 8)

        let text = Text(textStr)
            .font(.caption2)
            .foregroundStyle(.primary.opacity(alpha))

        let resolved = context.resolve(text)
        let maxSize = CGSize(width: 160, height: 60)
        let measured = resolved.measure(in: maxSize)

        let pad: CGFloat = 6
        let bg = CGRect(
            x: mid.x - measured.width/2 - pad,
            y: mid.y - measured.height/2 - pad,
            width: measured.width + pad*2,
            height: measured.height + pad*2
        )

        let bgPath = Path(roundedRect: bg, cornerRadius: 8)
        context.fill(bgPath, with: .color(.primary.opacity(0.12 * alpha)))
        context.stroke(bgPath, with: .color(.primary.opacity(0.28 * alpha)), lineWidth: 1)
        context.draw(resolved, at: mid, anchor: .center)
    }
}
