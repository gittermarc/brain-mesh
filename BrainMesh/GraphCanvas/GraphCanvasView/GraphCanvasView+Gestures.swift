//
//  GraphCanvasView+Gestures.swift
//  BrainMesh
//
//  P0.1: Split GraphCanvasView.swift -> Gestures + HitTesting
//

import SwiftUI

extension GraphCanvasView {
    func singleTapSelectGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                let worldTap = toWorld(value.location, center: center)
                let hit = hitTest(worldTap: worldTap)
                onTapNode(hit)
            }
    }

    func doubleTapPinGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard GraphCanvasModePolicy.policy(for: workMode).allowsDoubleTapPinning else { return }

                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
                let worldTap = toWorld(value.location, center: center)
                guard let key = hitTest(worldTap: worldTap) else { return }

                if pinned.contains(key) {
                    pinned.remove(key)
                } else {
                    pinned.insert(key)
                    velocities[key] = .zero
                }
            }
    }

    func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)

                let modePolicy = GraphCanvasModePolicy.policy(for: workMode)
                if !modePolicy.allowsNodeDragging {
                    if draggingKey != nil { draggingKey = nil }
                    pan = CGSize(width: panStart.width + value.translation.width,
                                 height: panStart.height + value.translation.height)
                    return
                }

                if draggingKey == nil {
                    let worldStart = toWorld(value.startLocation, center: center)
                    if let key = hitTest(worldTap: worldStart) {
                        draggingKey = key
                        selection = key
                        dragStartWorld = positions[key] ?? worldStart
                        velocities[key] = .zero
                    } else {
                        dragStartPan = panStart
                    }
                }

                if let key = draggingKey {
                    let dx = value.translation.width / scale
                    let dy = value.translation.height / scale
                    positions[key] = CGPoint(x: dragStartWorld.x + dx, y: dragStartWorld.y + dy)
                    velocities[key] = .zero
                } else {
                    pan = CGSize(width: dragStartPan.width + value.translation.width,
                                 height: dragStartPan.height + value.translation.height)
                }
            }
            .onEnded { _ in
                let modePolicy = GraphCanvasModePolicy.policy(for: workMode)
                if !modePolicy.allowsNodeDragging {
                    panStart = pan
                    draggingKey = nil
                    return
                }

                if let key = draggingKey {
                    pinned.insert(key)
                    velocities[key] = .zero
                } else {
                    panStart = pan
                }
                draggingKey = nil
            }
    }

    func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { val in
                scale = max(0.4, min(3.0, scaleStart * val))
            }
            .onEnded { _ in
                scaleStart = scale
            }
    }

    private func hitTest(worldTap: CGPoint) -> NodeKey? {
        GraphCanvasHitTesting.hitTest(
            nodes: nodes,
            positions: positions,
            worldTap: worldTap,
            lens: lens
        )
    }
}
