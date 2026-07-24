//
//  GraphCanvasView+Rendering.swift
//  BrainMesh
//
//  P0.1: Split GraphCanvasView.swift -> Rendering
//  P0.3: Rendering perf: per-frame screen cache
//  PR 11: Static label, identifier, and note preparation moved out of the frame path
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

    enum RenderingSupport {
        static func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }

        static func fade(_ value: CGFloat, from a: CGFloat, to b: CGFloat) -> CGFloat {
            guard b > a else { return value >= b ? 1 : 0 }
            return clamp01((value - a) / (b - a))
        }
    }

    func zoomAlphas() -> ZoomAlphas {
        let entityLabelAlpha = RenderingSupport.fade(scale, from: 0.55, to: 0.88)
        let attributeLabelAlpha = RenderingSupport.fade(scale, from: 1.20, to: 1.42)
        let noteAlpha = RenderingSupport.fade(scale, from: 1.32, to: 1.52)
        let thumbAlpha = RenderingSupport.fade(scale, from: 1.26, to: 1.42)

        let spotlightLabelsOnly = GraphCanvasSelectionSpotlightPolicy.limitsLabels(
            selection: selection,
            detailsFocusRenderPlan: detailsFocusRenderPlan
        )
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
        let frame = GraphCanvasDynamicFrameBuilder.build(
            nodes: nodes,
            drawEdges: drawEdges,
            positions: positions,
            center: center,
            scale: scale,
            lens: lens,
            detailsFocusRenderPlan: detailsFocusRenderPlan,
            staticSnapshot: staticRenderSnapshot
        )
        drawEdges(
            in: context,
            frame: frame,
            staticSnapshot: staticRenderSnapshot,
            alphas: alphas,
            theme: theme,
            colorScheme: colorScheme
        )
        drawNodes(
            in: context,
            frame: frame,
            staticSnapshot: staticRenderSnapshot,
            alphas: alphas,
            theme: theme,
            colorScheme: colorScheme
        )
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
