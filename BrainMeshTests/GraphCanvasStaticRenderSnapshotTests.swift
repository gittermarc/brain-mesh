import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph Canvas static render snapshot")
@MainActor
struct GraphCanvasStaticRenderSnapshotTests {
    @Test
    func identicalInputsProduceEqualSnapshots() {
        let entity = key(1, kind: .entity)
        let attribute = key(2, kind: .attribute)
        let notes = [
            DirectedEdgeKey.make(
                source: entity,
                target: attribute,
                type: .link
            ): "  Owns this attribute  "
        ]
        let input = GraphCanvasStaticRenderInput(
            nodeKeys: [attribute, entity],
            directedEdgeNotes: notes
        )

        let first = GraphCanvasStaticRenderSnapshotBuilder.build(input: input)
        let second = GraphCanvasStaticRenderSnapshotBuilder.build(input: input)

        #expect(first == second)
    }

    @Test
    func labelOffsetsAreDeterministicAndMatchThePreviousAlgorithm() {
        let nodeKeys = [
            key(10, kind: .entity),
            key(11, kind: .attribute),
            key(12, kind: .entity),
            key(13, kind: .attribute)
        ]
        let input = GraphCanvasStaticRenderInput(
            nodeKeys: nodeKeys,
            directedEdgeNotes: [:]
        )
        let snapshot = GraphCanvasStaticRenderSnapshotBuilder.build(input: input)

        for nodeKey in nodeKeys {
            let expected = legacyLabelOffset(for: nodeKey)
            #expect(snapshot.labelOffsetsByNodeKey[nodeKey] == expected)
            #expect(
                GraphCanvasStaticRenderSnapshotBuilder.labelOffset(for: nodeKey)
                    == expected
            )
        }
    }

    @Test
    func nodeInputOrderDoesNotChangeKeysOffsetsOrIdentifierMapping() {
        let alpha = key(20, kind: .entity)
        let beta = key(21, kind: .attribute)
        let gamma = key(22, kind: .entity)

        let first = GraphCanvasStaticRenderSnapshotBuilder.build(
            input: GraphCanvasStaticRenderInput(
                nodeKeys: [alpha, beta, gamma],
                directedEdgeNotes: [:]
            )
        )
        let second = GraphCanvasStaticRenderSnapshotBuilder.build(
            input: GraphCanvasStaticRenderInput(
                nodeKeys: [gamma, alpha, beta, alpha],
                directedEdgeNotes: [:]
            )
        )

        #expect(first == second)
        #expect(first.orderedNodeKeys.map(\.identifier) == [
            alpha.identifier,
            beta.identifier,
            gamma.identifier
        ].sorted())
    }

    @Test
    func everyIdentifierMapsToItsCorrectNodeKey() {
        let nodeKeys = [
            key(30, kind: .attribute),
            key(31, kind: .entity),
            key(32, kind: .attribute)
        ]
        let snapshot = GraphCanvasStaticRenderSnapshotBuilder.build(
            input: GraphCanvasStaticRenderInput(
                nodeKeys: nodeKeys,
                directedEdgeNotes: [:]
            )
        )

        #expect(snapshot.nodeKeyByIdentifier.count == nodeKeys.count)
        for nodeKey in nodeKeys {
            #expect(
                snapshot.nodeKeyByIdentifier[nodeKey.identifier] == nodeKey
            )
        }
    }

    @Test
    func addAndRemoveEachCauseExactlyOneNewSnapshot() {
        let alpha = key(40, kind: .entity)
        let beta = key(41, kind: .attribute)
        let cache = GraphCanvasStaticRenderSnapshotCache()

        let initial = cache.request(
            input: GraphCanvasStaticRenderInput(
                nodeKeys: [alpha],
                directedEdgeNotes: [:]
            )
        )
        let added = cache.request(
            input: GraphCanvasStaticRenderInput(
                nodeKeys: [alpha, beta],
                directedEdgeNotes: [:]
            )
        )
        let removed = cache.request(
            input: GraphCanvasStaticRenderInput(
                nodeKeys: [beta],
                directedEdgeNotes: [:]
            )
        )

        #expect(initial.didRebuild)
        #expect(added.didRebuild)
        #expect(removed.didRebuild)
        #expect(cache.metrics.requestCount == 3)
        #expect(cache.metrics.rebuildCount == 3)
        #expect(cache.metrics.identicalInputSkipCount == 0)
    }

    @Test
    func unchangedStaticInputDoesNotRebuild() {
        let input = GraphCanvasStaticRenderInput(
            nodeKeys: [key(50, kind: .entity)],
            directedEdgeNotes: [:]
        )
        let cache = GraphCanvasStaticRenderSnapshotCache()

        let first = cache.request(input: input)
        let second = cache.request(input: input)

        #expect(first.didRebuild)
        #expect(second.didRebuild == false)
        #expect(first.snapshot == second.snapshot)
        #expect(cache.metrics.requestCount == 2)
        #expect(cache.metrics.rebuildCount == 1)
        #expect(cache.metrics.identicalInputSkipCount == 1)
    }

    @Test
    func positionsVelocitiesCameraSelectionAndLensDoNotAffectRebuildIdentity() {
        let alpha = key(60, kind: .entity)
        let beta = key(61, kind: .attribute)
        let input = GraphCanvasStaticRenderInput(
            nodeKeys: [alpha, beta],
            directedEdgeNotes: [:]
        )
        let cache = GraphCanvasStaticRenderSnapshotCache()

        _ = cache.request(input: input)

        var positions: [NodeKey: CGPoint] = [
            alpha: CGPoint(x: 10, y: 20),
            beta: CGPoint(x: 30, y: 40)
        ]
        var velocities: [NodeKey: CGVector] = [
            alpha: CGVector(dx: 1, dy: 2),
            beta: CGVector(dx: 3, dy: 4)
        ]
        var pan = CGSize(width: 12, height: -8)
        var zoom: CGFloat = 1.4
        var selection: NodeKey? = alpha
        var lensEnabled = true

        positions[alpha] = CGPoint(x: 200, y: 300)
        velocities[beta] = CGVector(dx: -5, dy: 9)
        pan = CGSize(width: -40, height: 24)
        zoom = 2.2
        selection = beta
        lensEnabled = false

        _ = positions
        _ = velocities
        _ = pan
        _ = zoom
        _ = selection
        _ = lensEnabled

        for _ in 0..<6 {
            let resolution = cache.request(input: input)
            #expect(resolution.didRebuild == false)
        }

        #expect(cache.metrics.rebuildCount == 1)
        #expect(cache.metrics.identicalInputSkipCount == 6)
    }

    @Test
    func onlyRelevantDirectedNoteChangesCauseARebuild() {
        let source = key(70, kind: .entity)
        let target = key(71, kind: .attribute)
        let unknown = key(72, kind: .attribute)
        let directedKey = DirectedEdgeKey.make(
            source: source,
            target: target,
            type: .link
        )
        let unknownKey = DirectedEdgeKey.make(
            source: source,
            target: unknown,
            type: .link
        )
        let cache = GraphCanvasStaticRenderSnapshotCache()

        let initialInput = GraphCanvasStaticRenderInput(
            nodeKeys: [source, target],
            directedEdgeNotes: [directedKey: "First"]
        )
        _ = cache.request(input: initialInput)

        let whitespaceOnlyChange = GraphCanvasStaticRenderInput(
            nodeKeys: [source, target],
            directedEdgeNotes: [directedKey: "  First  "]
        )
        let whitespaceResolution = cache.request(input: whitespaceOnlyChange)

        let irrelevantMissingEndpointChange = GraphCanvasStaticRenderInput(
            nodeKeys: [source, target],
            directedEdgeNotes: [
                directedKey: "First",
                unknownKey: "Not renderable"
            ]
        )
        let irrelevantResolution = cache.request(
            input: irrelevantMissingEndpointChange
        )

        let relevantChange = GraphCanvasStaticRenderInput(
            nodeKeys: [source, target],
            directedEdgeNotes: [directedKey: "Second"]
        )
        let relevantResolution = cache.request(input: relevantChange)

        #expect(whitespaceResolution.didRebuild == false)
        #expect(irrelevantResolution.didRebuild == false)
        #expect(relevantResolution.didRebuild)
        #expect(cache.metrics.rebuildCount == 2)
        #expect(
            relevantResolution.snapshot.preparedOutgoingNote(
                source: source,
                target: target
            )?.text == "Second"
        )
    }

    @Test
    func repeatedDynamicFramesKeepOneSnapshotAndOneNodeAddBuildsOneMore() {
        let alpha = key(80, kind: .entity)
        let beta = key(81, kind: .attribute)
        let baseInput = GraphCanvasStaticRenderInput(
            nodeKeys: [alpha],
            directedEdgeNotes: [:]
        )
        let cache = GraphCanvasStaticRenderSnapshotCache()

        _ = cache.request(input: baseInput)

        var positions: [NodeKey: CGPoint] = [alpha: .zero]
        for tick in 1...100 {
            positions[alpha] = CGPoint(
                x: CGFloat(tick),
                y: -CGFloat(tick)
            )
            let resolution = cache.request(input: baseInput)
            #expect(resolution.didRebuild == false)
        }

        let added = cache.request(
            input: GraphCanvasStaticRenderInput(
                nodeKeys: [alpha, beta],
                directedEdgeNotes: [:]
            )
        )

        #expect(positions[alpha] == CGPoint(x: 100, y: -100))
        #expect(added.didRebuild)
        #expect(cache.metrics.requestCount == 102)
        #expect(cache.metrics.rebuildCount == 2)
        #expect(cache.metrics.identicalInputSkipCount == 100)
        #expect(added.snapshot.labelOffsetsByNodeKey.count == 2)
        #expect(added.snapshot.nodeKeyByIdentifier.count == 2)
    }

    private func key(_ value: Int, kind: NodeKind) -> NodeKey {
        NodeKey(kind: kind, uuid: uuid(value))
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "71000000-0000-0000-0000-%012d",
                value
            )
        )!
    }

    private func legacyLabelOffset(for nodeKey: NodeKey) -> CGPoint {
        let xChoices: [CGFloat] = [-14, 0, 14]
        let entityYChoices: [CGFloat] = [0, 6, 12]
        let attributeYChoices: [CGFloat] = [0, -6, -12]
        let yChoices = nodeKey.kind == .entity
            ? entityYChoices
            : attributeYChoices

        var seed = 0
        for scalar in nodeKey.identifier.unicodeScalars {
            seed = (seed &* 31) &+ Int(scalar.value)
        }

        return CGPoint(
            x: xChoices[abs(seed) % xChoices.count],
            y: yChoices[abs(seed / 7) % yChoices.count]
        )
    }
}
