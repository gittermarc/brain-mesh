//
//  GraphCanvasView+DrawNotes.swift
//  BrainMesh
//
//  P0.3: Split GraphCanvasView+Rendering.swift -> DrawNotes
//

import SwiftUI

extension GraphCanvasView {
    func drawEdgeNotePrepared(
        _ prepared: GraphCanvasPreparedOutgoingNote,
        source: NodeKey,
        target: NodeKey,
        from a: CGPoint,
        to b: CGPoint,
        alpha: CGFloat,
        in context: GraphicsContext
    ) {
        let textStr = prepared.text
        guard !textStr.isEmpty else { return }

        let midBase = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)

        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(1.0, sqrt(dx*dx + dy*dy))
        let nx = -dy / len
        let ny = dx / len

        let side = prepared.side
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
