import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph Canvas dynamic frame builder")
@MainActor
struct GraphCanvasDynamicFrameBuilderTests {
    @Test
    func screenPointsMatchThePreviousFrameTransformation() {
        let alpha = node(1, kind: .entity)
        let beta = node(2, kind: .attribute)
        let positions: [NodeKey: CGPoint] = [
            alpha.key: CGPoint(x: -24, y: 18),
            beta.key: CGPoint(x: 60, y: -32)
        ]
        let center = CGPoint(x: 240, y: 180)
        let scale: CGFloat = 1.75
        let snapshot = staticSnapshot(nodes: [alpha, beta])

        let frame = GraphCanvasDynamicFrameBuilder.build(
            nodes: [alpha, beta],
            drawEdges: [],
            positions: positions,
            center: center,
            scale: scale,
            lens: inactiveLens(),
            detailsFocusRenderPlan: .empty,
            staticSnapshot: snapshot
        )

        #expect(
            frame.screenPoints[alpha.key]
                == legacyScreenPoint(
                    positions[alpha.key]!,
                    center: center,
                    scale: scale
                )
        )
        #expect(
            frame.screenPoints[beta.key]
                == legacyScreenPoint(
                    positions[beta.key]!,
                    center: center,
                    scale: scale
                )
        )
    }

    @Test
    func zoomAndPanEquivalentCenterChangesMatchPreviousTransformation() {
        let alpha = node(10, kind: .entity)
        let position = CGPoint(x: 35, y: -20)
        let viewportCenter = CGPoint(x: 200, y: 150)
        let pan = CGSize(width: 44, height: -18)
        let transformedCenter = CGPoint(
            x: viewportCenter.x + pan.width,
            y: viewportCenter.y + pan.height
        )
        let scale: CGFloat = 2.25
        let snapshot = staticSnapshot(nodes: [alpha])

        let frame = GraphCanvasDynamicFrameBuilder.build(
            nodes: [alpha],
            drawEdges: [],
            positions: [alpha.key: position],
            center: transformedCenter,
            scale: scale,
            lens: inactiveLens(),
            detailsFocusRenderPlan: .empty,
            staticSnapshot: snapshot
        )

        let expected = CGPoint(
            x: viewportCenter.x + pan.width + position.x * scale,
            y: viewportCenter.y + pan.height + position.y * scale
        )
        #expect(frame.screenPoints[alpha.key] == expected)
    }

    @Test
    func regularEdgeEndpointsResolveExactlyThroughPreparedIdentifiers() {
        let alpha = node(20, kind: .entity)
        let beta = node(21, kind: .attribute)
        let edge = GraphEdge(a: alpha.key, b: beta.key, type: .link)
        let positions: [NodeKey: CGPoint] = [
            alpha.key: CGPoint(x: 10, y: 20),
            beta.key: CGPoint(x: 30, y: 40)
        ]
        let snapshot = staticSnapshot(nodes: [alpha, beta])

        let endpoints = GraphCanvasDynamicFrameBuilder.resolveEdgeEndpoints(
            edge,
            availableValues: positions,
            staticSnapshot: snapshot
        )

        #expect(endpoints?.a == edge.a)
        #expect(endpoints?.b == edge.b)
        #expect(endpoints?.usedDefensiveFallback == false)
    }

    @Test
    func directedNotesRemainOnTheSameOutgoingEdge() {
        let source = node(30, kind: .entity)
        let target = node(31, kind: .attribute)
        let reverseKey = DirectedEdgeKey.make(
            source: target.key,
            target: source.key,
            type: .link
        )
        let outgoingKey = DirectedEdgeKey.make(
            source: source.key,
            target: target.key,
            type: .link
        )
        let input = GraphCanvasStaticRenderInput(
            nodes: [target, source],
            directedEdgeNotes: [
                outgoingKey: "  Forward note  ",
                reverseKey: "Reverse note"
            ]
        )
        let snapshot = GraphCanvasStaticRenderSnapshotBuilder.build(input: input)

        let forward = snapshot.preparedOutgoingNote(
            source: source.key,
            target: target.key
        )
        let reverse = snapshot.preparedOutgoingNote(
            source: target.key,
            target: source.key
        )

        #expect(forward?.text == "Forward note")
        #expect(reverse?.text == "Reverse note")
        #expect(forward?.side == legacyNoteSide(source.key, target.key))
        #expect(reverse?.side == legacyNoteSide(target.key, source.key))
    }

    @Test
    func lensAndFocusVisibilityKeepTheSameDynamicScreenPointSet() {
        let selection = node(40, kind: .entity)
        let neighbor = node(41, kind: .attribute)
        let hidden = node(42, kind: .attribute)
        let visibleEdge = GraphEdge(
            a: selection.key,
            b: neighbor.key,
            type: .link
        )
        let hiddenEdge = GraphEdge(
            a: selection.key,
            b: hidden.key,
            type: .link
        )
        let lens = LensContext.build(
            enabled: true,
            hideNonRelevant: true,
            depth: 1,
            selection: selection.key,
            edges: [visibleEdge]
        )
        let focusPlan = GraphDetailsRenderPlan(
            activeFocus: nil,
            candidateAttributeNodeKeys: [neighbor.key, hidden.key],
            matchedAttributeNodeKeys: [neighbor.key],
            hiddenAttributeNodeKeys: [hidden.key],
            dimmedAttributeNodeKeys: [],
            suppressesSelectionSpotlight: false
        )
        let positions: [NodeKey: CGPoint] = [
            selection.key: .zero,
            neighbor.key: CGPoint(x: 40, y: 0),
            hidden.key: CGPoint(x: 80, y: 0)
        ]
        let snapshot = staticSnapshot(
            nodes: [selection, neighbor, hidden]
        )

        let frame = GraphCanvasDynamicFrameBuilder.build(
            nodes: [selection, neighbor, hidden],
            drawEdges: [visibleEdge, hiddenEdge],
            positions: positions,
            center: CGPoint(x: 100, y: 100),
            scale: 1,
            lens: lens,
            detailsFocusRenderPlan: focusPlan,
            staticSnapshot: snapshot
        )

        #expect(frame.screenPoints[selection.key] != nil)
        #expect(frame.screenPoints[neighbor.key] != nil)
        #expect(frame.screenPoints[hidden.key] == nil)
        #expect(lens.nodeOpacity(selection.key) == 1)
        #expect(lens.nodeOpacity(neighbor.key) == 0.92)
        #expect(
            focusPlan.nodeOpacityMultiplier(for: neighbor.key) == 1
        )
        #expect(focusPlan.nodeOpacityMultiplier(for: hidden.key) == 0)
    }

    @Test
    func hitTestingUsesTheSameWorldPositionsAndRadii() {
        let entity = node(50, kind: .entity)
        let attribute = node(51, kind: .attribute)
        let nodes = [entity, attribute]
        let positions: [NodeKey: CGPoint] = [
            entity.key: CGPoint(x: 0, y: 0),
            attribute.key: CGPoint(x: 50, y: 0)
        ]

        let entityHit = GraphCanvasHitTesting.hitTest(
            nodes: nodes,
            positions: positions,
            worldTap: CGPoint(x: 21, y: 0),
            lens: inactiveLens()
        )
        let attributeHit = GraphCanvasHitTesting.hitTest(
            nodes: nodes,
            positions: positions,
            worldTap: CGPoint(x: 67, y: 0),
            lens: inactiveLens()
        )
        let miss = GraphCanvasHitTesting.hitTest(
            nodes: nodes,
            positions: positions,
            worldTap: CGPoint(x: 100, y: 100),
            lens: inactiveLens()
        )

        #expect(entityHit == entity.key)
        #expect(attributeHit == attribute.key)
        #expect(miss == nil)
    }

    @Test
    func missingStaticNodeUsesSmallEndpointFallbackWithoutMutation() {
        let alpha = node(60, kind: .entity)
        let beta = node(61, kind: .attribute)
        let edge = GraphEdge(a: alpha.key, b: beta.key, type: .link)
        let staleSnapshot = staticSnapshot(nodes: [alpha])
        let snapshotBeforeFrame = staleSnapshot
        let positions: [NodeKey: CGPoint] = [
            alpha.key: .zero,
            beta.key: CGPoint(x: 60, y: 0)
        ]

        let frame = GraphCanvasDynamicFrameBuilder.build(
            nodes: [alpha, beta],
            drawEdges: [edge],
            positions: positions,
            center: CGPoint(x: 100, y: 100),
            scale: 1,
            lens: inactiveLens(),
            detailsFocusRenderPlan: .empty,
            staticSnapshot: staleSnapshot
        )

        #expect(frame.screenPoints[alpha.key] != nil)
        #expect(frame.screenPoints[beta.key] != nil)
        #expect(frame.defensiveEndpointFallbackCount == 1)
        #expect(frame.skippedEdgeEndpointCount == 0)
        #expect(staleSnapshot == snapshotBeforeFrame)
        #expect(
            staleSnapshot.nodeKeyByIdentifier[beta.key.identifier] == nil
        )
    }

    @Test
    func unknownEndpointIsSkippedWithoutCrash() {
        let alpha = node(70, kind: .entity)
        let unknown = node(71, kind: .attribute)
        let edge = GraphEdge(a: alpha.key, b: unknown.key, type: .link)
        let snapshot = staticSnapshot(nodes: [alpha])

        let frame = GraphCanvasDynamicFrameBuilder.build(
            nodes: [alpha],
            drawEdges: [edge],
            positions: [alpha.key: .zero],
            center: CGPoint(x: 100, y: 100),
            scale: 1,
            lens: inactiveLens(),
            detailsFocusRenderPlan: .empty,
            staticSnapshot: snapshot
        )

        #expect(frame.screenPoints[alpha.key] != nil)
        #expect(frame.screenPoints[unknown.key] == nil)
        #expect(frame.defensiveEndpointFallbackCount == 0)
        #expect(frame.skippedEdgeEndpointCount == 1)
    }

    @Test
    func rebuiltSnapshotEliminatesTheEndpointFallback() {
        let alpha = node(80, kind: .entity)
        let beta = node(81, kind: .attribute)
        let edge = GraphEdge(a: alpha.key, b: beta.key, type: .link)
        let positions: [NodeKey: CGPoint] = [
            alpha.key: .zero,
            beta.key: CGPoint(x: 60, y: 0)
        ]

        let staleFrame = GraphCanvasDynamicFrameBuilder.build(
            nodes: [alpha, beta],
            drawEdges: [edge],
            positions: positions,
            center: .zero,
            scale: 1,
            lens: inactiveLens(),
            detailsFocusRenderPlan: .empty,
            staticSnapshot: staticSnapshot(nodes: [alpha])
        )
        let rebuiltFrame = GraphCanvasDynamicFrameBuilder.build(
            nodes: [alpha, beta],
            drawEdges: [edge],
            positions: positions,
            center: .zero,
            scale: 1,
            lens: inactiveLens(),
            detailsFocusRenderPlan: .empty,
            staticSnapshot: staticSnapshot(nodes: [alpha, beta])
        )

        #expect(staleFrame.defensiveEndpointFallbackCount == 1)
        #expect(rebuiltFrame.defensiveEndpointFallbackCount == 0)
        #expect(staleFrame.screenPoints == rebuiltFrame.screenPoints)
    }

    @Test
    func oneHundredTwentyPositionFramesDoNotRequestAnotherStaticSnapshot() {
        let alpha = node(90, kind: .entity)
        let beta = node(91, kind: .attribute)
        let edge = GraphEdge(a: alpha.key, b: beta.key, type: .link)
        let cache = GraphCanvasStaticRenderSnapshotCache()
        let initialInput = GraphCanvasStaticRenderInput(
            nodes: [alpha, beta],
            directedEdgeNotes: [:]
        )
        let initialResolution = cache.request(input: initialInput)
        var positions: [NodeKey: CGPoint] = [
            alpha.key: .zero,
            beta.key: CGPoint(x: 60, y: 0)
        ]

        for tick in 1...120 {
            positions[beta.key] = CGPoint(
                x: 60 + CGFloat(tick),
                y: CGFloat(tick) * 0.5
            )
            let frame = GraphCanvasDynamicFrameBuilder.build(
                nodes: [alpha, beta],
                drawEdges: [edge],
                positions: positions,
                center: CGPoint(x: 100, y: 100),
                scale: 1,
                lens: inactiveLens(),
                detailsFocusRenderPlan: .empty,
                staticSnapshot: initialResolution.snapshot
            )

            #expect(frame.defensiveEndpointFallbackCount == 0)
            #expect(frame.skippedEdgeEndpointCount == 0)
            #expect(
                initialResolution.snapshot.labelOffsetsByNodeKey[beta.key]
                    != nil
            )
        }

        #expect(cache.metrics.requestCount == 1)
        #expect(cache.metrics.rebuildCount == 1)
        #expect(cache.metrics.identicalInputSkipCount == 0)

        let gamma = node(92, kind: .attribute)
        let addedResolution = cache.request(
            input: GraphCanvasStaticRenderInput(
                nodes: [alpha, beta, gamma],
                directedEdgeNotes: [:]
            )
        )

        #expect(addedResolution.didRebuild)
        #expect(cache.metrics.requestCount == 2)
        #expect(cache.metrics.rebuildCount == 2)
    }

    private func node(_ value: Int, kind: NodeKind) -> GraphNode {
        let key = NodeKey(kind: kind, uuid: uuid(value))
        return GraphNode(key: key, label: "Node \(value)")
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "72000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    private func staticSnapshot(
        nodes: [GraphNode]
    ) -> GraphCanvasStaticRenderSnapshot {
        GraphCanvasStaticRenderSnapshotBuilder.build(
            input: GraphCanvasStaticRenderInput(
                nodes: nodes,
                directedEdgeNotes: [:]
            )
        )
    }

    private func inactiveLens() -> LensContext {
        LensContext.build(
            enabled: false,
            hideNonRelevant: false,
            depth: 2,
            selection: nil,
            edges: []
        )
    }

    private func legacyScreenPoint(
        _ worldPoint: CGPoint,
        center: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: center.x + worldPoint.x * scale,
            y: center.y + worldPoint.y * scale
        )
    }

    private func legacyNoteSide(
        _ source: NodeKey,
        _ target: NodeKey
    ) -> CGFloat {
        var seed = 0
        for scalar in (source.identifier + "->" + target.identifier).unicodeScalars {
            seed = (seed &* 31) &+ Int(scalar.value)
        }
        return seed % 2 == 0 ? 1 : -1
    }
}
