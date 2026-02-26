//
//  GraphCanvasView+Rendering.swift
//  BrainMesh
//
//  P0.1: Split GraphCanvasView.swift -> Rendering
//  P0.3: Rendering perf: per-frame screen cache + label offset cache + outgoing note prefilter
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

    struct PreparedOutgoingNote {
        let text: String
        let side: CGFloat
    }

    struct FrameCache {
        let screenPoints: [NodeKey: CGPoint]
        let labelOffsets: [NodeKey: CGPoint]
        let outgoingNotesByTarget: [NodeKey: PreparedOutgoingNote]?
    }

    enum LabelConstants {
        static let xChoices: [CGFloat] = [-14, 0, 14]
        static let yChoicesEntity: [CGFloat] = [0, 6, 12]
        static let yChoicesAttr: [CGFloat] = [0, -6, -12]
    }

    enum LabelKind { case entity, attribute }

    enum RenderingSupport {
        static func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }

        static func fade(_ value: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
            guard b > a else { return value >= b ? 1 : 0 }
            return clamp01((value - a) / (b - a))
        }

        static func stableSeed(_ s: String) -> Int {
            var h: Int = 0
            for u in s.unicodeScalars {
                h = (h &* 31) &+ Int(u.value)
            }
            return h
        }

        static func labelOffset(seed: Int, kind: LabelKind) -> CGPoint {
            let xChoices = LabelConstants.xChoices
            let yChoices = (kind == .entity) ? LabelConstants.yChoicesEntity : LabelConstants.yChoicesAttr

            let xi = abs(seed) % xChoices.count
            let yi = abs(seed / 7) % yChoices.count

            return CGPoint(x: xChoices[xi], y: yChoices[yi])
        }
    }

    func zoomAlphas() -> ZoomAlphas {
        let entityLabelAlpha = RenderingSupport.fade(scale, from: 0.55, to: 0.88)
        let attributeLabelAlpha = RenderingSupport.fade(scale, from: 1.20, to: 1.42)
        let noteAlpha = RenderingSupport.fade(scale, from: 1.32, to: 1.52)
        let thumbAlpha = RenderingSupport.fade(scale, from: 1.26, to: 1.42)

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
        let frame = buildFrameCache(center: center, alphas: alphas)
        drawEdges(in: context, frame: frame, alphas: alphas, theme: theme, colorScheme: colorScheme)
        drawNodes(in: context, frame: frame, alphas: alphas, theme: theme, colorScheme: colorScheme)
    }

    private func buildFrameCache(center: CGPoint, alphas: ZoomAlphas) -> FrameCache {
        var screenPoints: [NodeKey: CGPoint] = [:]
        screenPoints.reserveCapacity(nodes.count + (drawEdges.count * 2))

        var labelOffsets: [NodeKey: CGPoint] = [:]
        labelOffsets.reserveCapacity(nodes.count)

        // NodeKey reconstruction for directed edge notes (keys store string identifiers)
        var keyByIdentifier: [String: NodeKey] = [:]
        keyByIdentifier.reserveCapacity(positions.count)

        for (k, _) in positions {
            keyByIdentifier[k.identifier] = k
        }

        // Cache for nodes (also precomputes label offsets)
        for n in nodes {
            let key = n.key
            if lens.hideNonRelevant && lens.isHidden(key) { continue }

            if let p = positions[key] {
                screenPoints[key] = toScreen(p, center: center)
            }

            // label offset is deterministic -> compute once per frame (no allocations per node)
            let seed = RenderingSupport.stableSeed(key.identifier)
            switch key.kind {
            case .entity:
                labelOffsets[key] = RenderingSupport.labelOffset(seed: seed, kind: .entity)
            case .attribute:
                labelOffsets[key] = RenderingSupport.labelOffset(seed: seed, kind: .attribute)
            }
        }

        // Ensure endpoints exist for edges (defensive, in case edges reference nodes not in `nodes`)
        for e in drawEdges {
            if lens.hideNonRelevant && (lens.isHidden(e.a) || lens.isHidden(e.b)) { continue }

            if screenPoints[e.a] == nil, let p = positions[e.a] {
                screenPoints[e.a] = toScreen(p, center: center)
            }
            if screenPoints[e.b] == nil, let p = positions[e.b] {
                screenPoints[e.b] = toScreen(p, center: center)
            }

            if labelOffsets[e.a] == nil {
                let seed = RenderingSupport.stableSeed(e.a.identifier)
                labelOffsets[e.a] = RenderingSupport.labelOffset(seed: seed, kind: e.a.kind == .entity ? .entity : .attribute)
            }
            if labelOffsets[e.b] == nil {
                let seed = RenderingSupport.stableSeed(e.b.identifier)
                labelOffsets[e.b] = RenderingSupport.labelOffset(seed: seed, kind: e.b.kind == .entity ? .entity : .attribute)
            }
        }

        var outgoingNotesByTarget: [NodeKey: PreparedOutgoingNote]? = nil
        if alphas.showNotes, let sel = selection {
            outgoingNotesByTarget = prepareOutgoingNotes(for: sel, keyByIdentifier: keyByIdentifier)
        }

        return FrameCache(
            screenPoints: screenPoints,
            labelOffsets: labelOffsets,
            outgoingNotesByTarget: outgoingNotesByTarget
        )
    }

    private func prepareOutgoingNotes(for selection: NodeKey, keyByIdentifier: [String: NodeKey]) -> [NodeKey: PreparedOutgoingNote]? {
        let maxChars = 46

        var map: [NodeKey: PreparedOutgoingNote] = [:]
        map.reserveCapacity(8)

        for (k, raw) in directedEdgeNotes {
            guard k.type == GraphEdgeType.link.rawValue else { continue }
            guard k.sourceID == selection.identifier else { continue }
            guard let targetKey = keyByIdentifier[k.targetID] else { continue }

            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let textStr: String
            if trimmed.count > maxChars {
                textStr = String(trimmed.prefix(maxChars)) + "…"
            } else {
                textStr = trimmed
            }

            let edgeSeed = RenderingSupport.stableSeed(k.sourceID + "->" + k.targetID)
            let side: CGFloat = (edgeSeed % 2 == 0) ? 1 : -1

            map[targetKey] = PreparedOutgoingNote(text: textStr, side: side)
        }

        return map.isEmpty ? nil : map
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

}
