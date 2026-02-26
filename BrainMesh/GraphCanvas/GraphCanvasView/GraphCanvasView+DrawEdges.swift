//
//  GraphCanvasView+DrawEdges.swift
//  BrainMesh
//
//  P0.3: Split GraphCanvasView+Rendering.swift -> DrawEdges
//

import SwiftUI

extension GraphCanvasView {
    func drawEdges(
        in context: GraphicsContext,
        frame: FrameCache,
        alphas: ZoomAlphas,
        theme: GraphTheme,
        colorScheme: ColorScheme
    ) {
        for e in drawEdges {
            if lens.hideNonRelevant && (lens.isHidden(e.a) || lens.isHidden(e.b)) { continue }

            guard let a = frame.screenPoints[e.a], let b = frame.screenPoints[e.b] else { continue }

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
            if let sel = selection,
               let notes = frame.outgoingNotesByTarget,
               alphas.showNotes,
               e.type == .link {

                if sel == e.a, let note = notes[e.b] {
                    drawEdgeNotePrepared(note, source: e.a, target: e.b, from: a, to: b, alpha: alphas.noteAlpha, in: context)
                } else if sel == e.b, let note = notes[e.a] {
                    drawEdgeNotePrepared(note, source: e.b, target: e.a, from: b, to: a, alpha: alphas.noteAlpha, in: context)
                }
            }
        }
    }
}
