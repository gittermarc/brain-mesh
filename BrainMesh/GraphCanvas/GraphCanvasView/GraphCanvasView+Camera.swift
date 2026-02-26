//
//  GraphCanvasView+Camera.swift
//  BrainMesh
//
//  P0.1: Split GraphCanvasView.swift -> Camera / Coordinate transforms
//

import SwiftUI

extension GraphCanvasView {
    func applyCameraCommand(_ cmd: CameraCommand, in size: CGSize) {
        switch cmd.kind {
        case .reset:
            withAnimation(.snappy) {
                scale = 1.0
                pan = .zero
                panStart = .zero
                scaleStart = 1.0
            }

        case .center(let key):
            guard let p = positions[key] else { return }
            withAnimation(.snappy) {
                pan = CGSize(width: -p.x * scale, height: -p.y * scale)
                panStart = pan
            }

        case .fitAll:
            let keys = nodes.map(\.key)
            guard !keys.isEmpty else { return }
            var minX: CGFloat = .greatestFiniteMagnitude
            var minY: CGFloat = .greatestFiniteMagnitude
            var maxX: CGFloat = -.greatestFiniteMagnitude
            var maxY: CGFloat = -.greatestFiniteMagnitude

            for k in keys {
                guard let p = positions[k] else { continue }
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }

            if minX == .greatestFiniteMagnitude { return }

            let worldW = max(1, maxX - minX)
            let worldH = max(1, maxY - minY)

            let padding: CGFloat = 90
            let availW = max(1, size.width - padding)
            let availH = max(1, size.height - padding)

            let targetScale = min(availW / worldW, availH / worldH)
            let clamped = max(0.4, min(3.0, targetScale))

            let mid = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)

            withAnimation(.snappy) {
                scale = clamped
                scaleStart = clamped
                pan = CGSize(width: -mid.x * clamped, height: -mid.y * clamped)
                panStart = pan
            }
        }
    }

    func toWorld(_ screen: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(x: (screen.x - center.x) / scale, y: (screen.y - center.y) / scale)
    }

    func toScreen(_ world: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(x: center.x + world.x * scale, y: center.y + world.y * scale)
    }
}
