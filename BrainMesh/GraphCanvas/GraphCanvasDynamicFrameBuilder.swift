//
//  GraphCanvasDynamicFrameBuilder.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Dynamic render values that legitimately change with positions, camera, Lens,
/// Focus, or visibility. Static label and identifier lookups are intentionally
/// absent and remain owned by `GraphCanvasStaticRenderSnapshot`.
nonisolated struct GraphCanvasDynamicFrameCache: Equatable, Sendable {
    let screenPoints: [NodeKey: CGPoint]
    let defensiveEndpointFallbackCount: Int
    let skippedEdgeEndpointCount: Int
}

nonisolated struct GraphCanvasResolvedEdgeEndpoints: Equatable, Sendable {
    let a: NodeKey
    let b: NodeKey
    let usedDefensiveFallback: Bool
}

@MainActor
enum GraphCanvasDynamicFrameBuilder {
    static func build(
        nodes: [GraphNode],
        drawEdges: [GraphEdge],
        positions: [NodeKey: CGPoint],
        center: CGPoint,
        scale: CGFloat,
        lens: LensContext,
        detailsFocusRenderPlan: GraphDetailsRenderPlan,
        staticSnapshot: GraphCanvasStaticRenderSnapshot
    ) -> GraphCanvasDynamicFrameCache {
        var screenPoints: [NodeKey: CGPoint] = [:]
        screenPoints.reserveCapacity(nodes.count + (drawEdges.count * 2))

        for node in nodes {
            let key = node.key
            if lens.hideNonRelevant && lens.isHidden(key) { continue }
            if detailsFocusRenderPlan.isHidden(key) { continue }

            if let position = positions[key] {
                screenPoints[key] = screenPoint(
                    worldPoint: position,
                    center: center,
                    scale: scale
                )
            }
        }

        var defensiveEndpointFallbackCount = 0
        var skippedEdgeEndpointCount = 0

        for edge in drawEdges {
            if lens.hideNonRelevant &&
                (lens.isHidden(edge.a) || lens.isHidden(edge.b)) {
                continue
            }
            if !detailsFocusRenderPlan.shouldRender(edge: edge) {
                continue
            }

            guard let endpoints = resolveEdgeEndpoints(
                edge,
                availableValues: positions,
                staticSnapshot: staticSnapshot
            ) else {
                skippedEdgeEndpointCount += 1
                continue
            }

            if endpoints.usedDefensiveFallback {
                defensiveEndpointFallbackCount += 1
            }

            if screenPoints[endpoints.a] == nil,
               let position = positions[endpoints.a] {
                screenPoints[endpoints.a] = screenPoint(
                    worldPoint: position,
                    center: center,
                    scale: scale
                )
            }
            if screenPoints[endpoints.b] == nil,
               let position = positions[endpoints.b] {
                screenPoints[endpoints.b] = screenPoint(
                    worldPoint: position,
                    center: center,
                    scale: scale
                )
            }
        }

        return GraphCanvasDynamicFrameCache(
            screenPoints: screenPoints,
            defensiveEndpointFallbackCount: defensiveEndpointFallbackCount,
            skippedEdgeEndpointCount: skippedEdgeEndpointCount
        )
    }

    static func screenPoint(
        worldPoint: CGPoint,
        center: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: center.x + worldPoint.x * scale,
            y: center.y + worldPoint.y * scale
        )
    }

    /// Resolves through the prepared identifier map in the regular path.
    /// A missing static entry falls back only to the concrete edge key if that
    /// key already has a current dynamic value. It never reconstructs the full
    /// identifier dictionary and never mutates the static snapshot.
    static func resolveEdgeEndpoints<Value>(
        _ edge: GraphEdge,
        availableValues: [NodeKey: Value],
        staticSnapshot: GraphCanvasStaticRenderSnapshot
    ) -> GraphCanvasResolvedEdgeEndpoints? {
        let resolvedA: NodeKey
        let usedFallbackA: Bool
        if let mapped = staticSnapshot.nodeKeyByIdentifier[edge.a.identifier] {
            resolvedA = mapped
            usedFallbackA = false
        } else if availableValues[edge.a] != nil {
            resolvedA = edge.a
            usedFallbackA = true
        } else {
            return nil
        }

        let resolvedB: NodeKey
        let usedFallbackB: Bool
        if let mapped = staticSnapshot.nodeKeyByIdentifier[edge.b.identifier] {
            resolvedB = mapped
            usedFallbackB = false
        } else if availableValues[edge.b] != nil {
            resolvedB = edge.b
            usedFallbackB = true
        } else {
            return nil
        }

        return GraphCanvasResolvedEdgeEndpoints(
            a: resolvedA,
            b: resolvedB,
            usedDefensiveFallback: usedFallbackA || usedFallbackB
        )
    }
}

@MainActor
enum GraphCanvasHitTesting {
    static func hitTest(
        nodes: [GraphNode],
        positions: [NodeKey: CGPoint],
        worldTap: CGPoint,
        lens: LensContext
    ) -> NodeKey? {
        var best: (NodeKey, CGFloat)?

        for node in nodes {
            if lens.hideNonRelevant && lens.isHidden(node.key) { continue }
            guard let position = positions[node.key] else { continue }

            let dx = position.x - worldTap.x
            let dy = position.y - worldTap.y
            let distance = sqrt(dx * dx + dy * dy)
            let hitRadius: CGFloat = node.key.kind == .entity ? 22 : 18

            if distance <= hitRadius,
               best == nil || distance < best!.1 {
                best = (node.key, distance)
            }
        }

        return best?.0
    }
}
