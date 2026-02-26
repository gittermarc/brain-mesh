//
//  GraphCanvasView+DrawLabels.swift
//  BrainMesh
//
//  P0.3: Split GraphCanvasView+Rendering.swift -> DrawLabels
//

import SwiftUI

extension GraphCanvasView {
    func drawLabel(
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
}
