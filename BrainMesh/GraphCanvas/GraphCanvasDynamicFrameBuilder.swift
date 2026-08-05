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
    static let empty = GraphCanvasDynamicFrameCache(
        screenPoints: [:],
        preparedNodes: [],
        preparedEdges: [],
        defensiveEndpointFallbackCount: 0,
        skippedEdgeEndpointCount: 0
    )

    let screenPoints: [NodeKey: CGPoint]
    let preparedNodes: [GraphCanvasPreparedDynamicNode]
    let preparedEdges: [GraphCanvasPreparedDynamicEdge]
    let defensiveEndpointFallbackCount: Int
    let skippedEdgeEndpointCount: Int
}

nonisolated struct GraphCanvasPreparedDynamicNode:
    Equatable,
    Sendable
{
    let node: GraphNode
    let screenPoint: CGPoint
    let labelOffset: CGPoint
    let opacity: CGFloat
    let isRelevantInSpotlight: Bool
    let isMatchedDetailsAttribute: Bool
}

nonisolated struct GraphCanvasPreparedDynamicEdge:
    Equatable,
    Sendable
{
    let edge: GraphEdge
    let firstPoint: CGPoint
    let secondPoint: CGPoint
    let opacity: CGFloat
}

/// Main-Actor render preparation input. SwiftUI compares this value at the
/// view boundary; the Canvas draw closure consumes only the finished cache.
@MainActor
struct GraphCanvasDynamicFrameInput: Equatable {
    let nodes: [GraphNode]
    let drawEdges: [GraphEdge]
    let positions: [NodeKey: CGPoint]
    let center: CGPoint
    let scale: CGFloat
    let lens: LensContext
    let detailsFocusRenderPlan: GraphDetailsRenderPlan
    let staticSnapshot: GraphCanvasStaticRenderSnapshot
}

nonisolated struct GraphCanvasResolvedEdgeEndpoints: Equatable, Sendable {
    let a: NodeKey
    let b: NodeKey
    let usedDefensiveFallback: Bool
}

@MainActor
enum GraphCanvasDynamicFrameBuilder {
    static func build(
        input: GraphCanvasDynamicFrameInput
    ) -> GraphCanvasDynamicFrameCache {
        build(
            nodes: input.nodes,
            drawEdges: input.drawEdges,
            positions: input.positions,
            center: input.center,
            scale: input.scale,
            lens: input.lens,
            detailsFocusRenderPlan:
                input.detailsFocusRenderPlan,
            staticSnapshot: input.staticSnapshot
        )
    }

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
        var preparedNodes: [GraphCanvasPreparedDynamicNode] = []
        preparedNodes.reserveCapacity(nodes.count)

        for node in nodes {
            let key = node.key
            if lens.hideNonRelevant && lens.isHidden(key) { continue }
            if detailsFocusRenderPlan.isHidden(key) { continue }

            if let position = positions[key] {
                let point = screenPoint(
                    worldPoint: position,
                    center: center,
                    scale: scale
                )
                screenPoints[key] = point
                preparedNodes.append(
                    GraphCanvasPreparedDynamicNode(
                        node: node,
                        screenPoint: point,
                        labelOffset:
                            staticSnapshot
                                .labelOffsetsByNodeKey[key]
                            ?? GraphCanvasStaticRenderSnapshotBuilder
                                .labelOffset(for: key),
                        opacity: lens.nodeOpacity(key)
                            * detailsFocusRenderPlan
                                .nodeOpacityMultiplier(for: key),
                        isRelevantInSpotlight:
                            lens.distance[key] != nil,
                        isMatchedDetailsAttribute:
                            detailsFocusRenderPlan
                                .isMatchedAttribute(key)
                    )
                )
            }
        }

        var preparedEdges: [GraphCanvasPreparedDynamicEdge] = []
        preparedEdges.reserveCapacity(drawEdges.count)
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

            guard let firstPoint = screenPoints[endpoints.a],
                  let secondPoint = screenPoints[endpoints.b] else {
                skippedEdgeEndpointCount += 1
                continue
            }
            let opacity =
                lens.edgeOpacity(a: edge.a, b: edge.b) *
                detailsFocusRenderPlan.edgeOpacityMultiplier(
                    a: edge.a,
                    b: edge.b
                )
            guard opacity > 0.001 else { continue }
            preparedEdges.append(
                GraphCanvasPreparedDynamicEdge(
                    edge: edge,
                    firstPoint: firstPoint,
                    secondPoint: secondPoint,
                    opacity: opacity
                )
            )
        }

        return GraphCanvasDynamicFrameCache(
            screenPoints: screenPoints,
            preparedNodes: preparedNodes,
            preparedEdges: preparedEdges,
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
