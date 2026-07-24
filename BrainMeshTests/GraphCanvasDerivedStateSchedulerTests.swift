import Foundation
import CoreGraphics
import Testing

@testable import BrainMesh

@Suite("Graph Canvas derived-state scheduler")
@MainActor
struct GraphCanvasDerivedStateSchedulerTests {
    @Test
    func singleInputExecutesBuilderAndCommitsOnce() async {
        let graphID = uuid(1)
        let input = makeInput(lensDepth: 1)
        var committedDepths: [Int] = []
        let scheduler = GraphCanvasDerivedStateScheduler()

        scheduler.schedule(
            input: input,
            graphID: graphID,
            reason: .initial,
            commit: { committedDepths.append($0.lens.depth) }
        )
        await scheduler.waitForCurrentWork()

        #expect(committedDepths == [1])
        #expect(scheduler.metrics.schedulingRequestCount == 1)
        #expect(scheduler.metrics.builderExecutionCount == 1)
        #expect(scheduler.metrics.commitCount == 1)
    }

    @Test
    func multipleInputsInOneWindowExecuteBuilderOnce() async {
        let graphID = uuid(2)
        let scheduler = GraphCanvasDerivedStateScheduler()
        var committedDepths: [Int] = []

        for depth in 1...3 {
            scheduler.schedule(
                input: makeInput(lensDepth: depth),
                graphID: graphID,
                reason: .selectionOrLens,
                commit: { committedDepths.append($0.lens.depth) }
            )
        }
        await scheduler.waitForCurrentWork()

        #expect(committedDepths == [3])
        #expect(scheduler.metrics.schedulingRequestCount == 3)
        #expect(scheduler.metrics.builderExecutionCount == 1)
        #expect(scheduler.metrics.coalescedRequestCount == 2)
    }

    @Test
    func lastInputOfBurstWins() async {
        let graphID = uuid(3)
        let first = makeInput(lensDepth: 1)
        let last = makeInput(lensDepth: 4)
        var builtInputs: [GraphCanvasDerivedStateInputSnapshot] = []
        let scheduler = GraphCanvasDerivedStateScheduler(
            buildOperation: { input in
                builtInputs.append(input)
                return input.buildDerivedState()
            }
        )

        scheduler.schedule(
            input: first,
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { _ in }
        )
        scheduler.schedule(
            input: last,
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { _ in }
        )
        await scheduler.waitForCurrentWork()

        #expect(builtInputs == [last])
    }

    @Test
    func identicalInputDoesNotExecuteAgain() async {
        let graphID = uuid(4)
        let input = makeInput(lensDepth: 2)
        let scheduler = GraphCanvasDerivedStateScheduler()

        scheduler.schedule(
            input: input,
            graphID: graphID,
            reason: .initial,
            commit: { _ in }
        )
        await scheduler.waitForCurrentWork()

        scheduler.schedule(
            input: input,
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { _ in }
        )
        await scheduler.waitForCurrentWork()

        #expect(scheduler.metrics.schedulingRequestCount == 2)
        #expect(scheduler.metrics.builderExecutionCount == 1)
        #expect(scheduler.metrics.identicalInputDropCount == 1)
    }

    @Test
    func newerInputDiscardsOlderPendingCommit() async {
        let graphID = uuid(5)
        let first = makeInput(lensDepth: 1)
        let second = makeInput(lensDepth: 2)
        let gate = GraphCanvasDerivedStateBuildGate()
        var committedDepths: [Int] = []
        let scheduler = GraphCanvasDerivedStateScheduler(
            buildOperation: { input in
                if input == first {
                    await gate.wait()
                }
                return input.buildDerivedState()
            }
        )

        scheduler.schedule(
            input: first,
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { committedDepths.append($0.lens.depth) }
        )
        let firstBuildStarted = await waitUntil {
            scheduler.metrics.builderExecutionCount == 1
        }
        #expect(firstBuildStarted)

        scheduler.schedule(
            input: second,
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { committedDepths.append($0.lens.depth) }
        )
        await scheduler.waitForCurrentWork()
        gate.resume()
        let staleResultWasDiscarded = await waitUntil {
            scheduler.metrics.staleResultDropCount == 1
        }

        #expect(staleResultWasDiscarded)
        #expect(committedDepths == [2])
        #expect(scheduler.metrics.builderExecutionCount == 2)
        #expect(scheduler.metrics.commitCount == 1)
    }

    @Test
    func cancellationPreventsLateCommit() async {
        let graphID = uuid(6)
        let input = makeInput(lensDepth: 1)
        let gate = GraphCanvasDerivedStateBuildGate()
        var commitCount = 0
        let scheduler = GraphCanvasDerivedStateScheduler(
            buildOperation: { input in
                await gate.wait()
                return input.buildDerivedState()
            }
        )

        scheduler.schedule(
            input: input,
            graphID: graphID,
            reason: .initial,
            commit: { _ in commitCount += 1 }
        )
        let buildStarted = await waitUntil {
            scheduler.metrics.builderExecutionCount == 1
        }
        #expect(buildStarted)

        scheduler.cancel()
        gate.resume()
        _ = await waitUntil {
            scheduler.metrics.staleResultDropCount == 1
        }

        #expect(commitCount == 0)
        #expect(scheduler.metrics.cancellationCount == 1)
        #expect(scheduler.metrics.commitCount == 0)
    }

    @Test
    func graphChangeDiscardsPreviousGraphResult() async {
        let firstGraphID = uuid(7)
        let secondGraphID = uuid(8)
        let first = makeInput(lensDepth: 1)
        let second = makeInput(lensDepth: 2)
        let gate = GraphCanvasDerivedStateBuildGate()
        var committedDepths: [Int] = []
        let scheduler = GraphCanvasDerivedStateScheduler(
            buildOperation: { input in
                if input == first {
                    await gate.wait()
                }
                return input.buildDerivedState()
            }
        )

        scheduler.schedule(
            input: first,
            graphID: firstGraphID,
            reason: .graphLoad,
            commit: { committedDepths.append($0.lens.depth) }
        )
        let firstBuildStarted = await waitUntil {
            scheduler.metrics.builderExecutionCount == 1
        }
        #expect(firstBuildStarted)

        scheduler.schedule(
            input: second,
            graphID: secondGraphID,
            reason: .graphLoad,
            commit: { committedDepths.append($0.lens.depth) }
        )
        await scheduler.waitForCurrentWork()
        gate.resume()
        _ = await waitUntil {
            scheduler.metrics.staleResultDropCount == 1
        }

        #expect(committedDepths == [2])
        #expect(scheduler.metrics.commitCount == 1)
    }

    @Test
    func initialLoadProducesOneFinalBuild() async {
        let graphID = uuid(9)
        let selection = key(10)
        let peer = key(11)
        let edge = GraphEdge(a: selection, b: peer, type: .link)
        let scheduler = GraphCanvasDerivedStateScheduler()
        var committedEdges: [[GraphEdge]] = []

        let empty = makeInput(selection: selection)
        let withEdges = makeInput(
            selection: selection,
            edges: [edge]
        )
        let final = makeInput(
            selection: selection,
            edges: [edge],
            labels: [selection: "Selection", peer: "Peer"]
        )

        scheduler.schedule(
            input: empty,
            graphID: graphID,
            reason: .graphLoad,
            commit: { committedEdges.append($0.drawEdges) }
        )
        scheduler.schedule(
            input: withEdges,
            graphID: graphID,
            reason: .graphLoad,
            commit: { committedEdges.append($0.drawEdges) }
        )
        scheduler.schedule(
            input: final,
            graphID: graphID,
            reason: .graphLoad,
            commit: { committedEdges.append($0.drawEdges) }
        )
        await scheduler.waitForCurrentWork()

        #expect(committedEdges == [[edge]])
        #expect(scheduler.metrics.builderExecutionCount == 1)
    }

    @Test
    func selectionAndShowAllLinksInSameTurnProduceOneBuild() async {
        let graphID = uuid(12)
        let selection = key(13)
        let firstPeer = key(14)
        let secondPeer = key(15)
        let edges = [
            GraphEdge(a: selection, b: firstPeer, type: .link),
            GraphEdge(a: selection, b: secondPeer, type: .link)
        ]
        let labels = [
            selection: "Selection",
            firstPeer: "A",
            secondPeer: "B"
        ]
        let scheduler = GraphCanvasDerivedStateScheduler()
        var committedEdgeCounts: [Int] = []

        scheduler.schedule(
            input: makeInput(
                selection: selection,
                edges: edges,
                showAllLinksForSelection: false,
                degreeCap: 1,
                labels: labels
            ),
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { committedEdgeCounts.append($0.drawEdges.count) }
        )
        scheduler.schedule(
            input: makeInput(
                selection: selection,
                edges: edges,
                showAllLinksForSelection: true,
                degreeCap: 1,
                labels: labels
            ),
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { committedEdgeCounts.append($0.drawEdges.count) }
        )
        await scheduler.waitForCurrentWork()

        #expect(committedEdgeCounts == [2])
        #expect(scheduler.metrics.builderExecutionCount == 1)
    }

    @Test
    func detailsFocusAndPreparedStateInSameTurnProduceOneBuild() async {
        let graphID = uuid(16)
        let fixture = detailsFixture()
        let scheduler = GraphCanvasDerivedStateScheduler()
        var matchCounts: [Int] = []

        scheduler.schedule(
            input: makeInput(detailsFocusState: fixture.focus),
            graphID: graphID,
            reason: .detailsFocus,
            commit: { matchCounts.append($0.detailsFocusSummary.matchCount) }
        )
        scheduler.schedule(
            input: makeInput(
                detailsFocusState: fixture.focus,
                detailsFocusPreparedState: fixture.prepared
            ),
            graphID: graphID,
            reason: .detailsExpansion,
            commit: { matchCounts.append($0.detailsFocusSummary.matchCount) }
        )
        await scheduler.waitForCurrentWork()

        #expect(matchCounts == [1])
        #expect(scheduler.metrics.builderExecutionCount == 1)
    }

    @Test
    func edgesLabelsAndFocusFromLoadCommitAreCoalesced() async {
        let graphID = uuid(17)
        let selection = key(18)
        let peer = key(19)
        let edge = GraphEdge(a: selection, b: peer, type: .link)
        let fixture = detailsFixture()
        let scheduler = GraphCanvasDerivedStateScheduler()

        scheduler.schedule(
            input: makeInput(selection: selection, edges: [edge]),
            graphID: graphID,
            reason: .graphLoad,
            commit: { _ in }
        )
        scheduler.schedule(
            input: makeInput(
                selection: selection,
                edges: [edge],
                labels: [selection: "Selection", peer: "Peer"]
            ),
            graphID: graphID,
            reason: .graphLoad,
            commit: { _ in }
        )
        scheduler.schedule(
            input: makeInput(
                selection: selection,
                edges: [edge],
                detailsFocusState: fixture.focus,
                detailsFocusPreparedState: fixture.prepared,
                labels: [selection: "Selection", peer: "Peer"]
            ),
            graphID: graphID,
            reason: .graphLoad,
            commit: { _ in }
        )
        await scheduler.waitForCurrentWork()

        #expect(scheduler.metrics.schedulingRequestCount == 3)
        #expect(scheduler.metrics.builderExecutionCount == 1)
        #expect(scheduler.metrics.coalescedRequestCount == 2)
    }

    @Test
    func positionAndVelocityChangesDoNotProduceAnotherBuild() async {
        let graphID = uuid(20)
        let input = makeInput(lensDepth: 2)
        let scheduler = GraphCanvasDerivedStateScheduler()
        var positions: [NodeKey: CGPoint] = [:]
        var velocities: [NodeKey: CGVector] = [:]

        scheduler.schedule(
            input: input,
            graphID: graphID,
            reason: .initial,
            commit: { _ in }
        )
        await scheduler.waitForCurrentWork()

        let node = key(21)
        positions[node] = CGPoint(x: 100, y: 200)
        velocities[node] = CGVector(dx: 3, dy: 4)
        scheduler.schedule(
            input: input,
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { _ in }
        )
        await scheduler.waitForCurrentWork()

        #expect(positions[node] == CGPoint(x: 100, y: 200))
        #expect(velocities[node] == CGVector(dx: 3, dy: 4))
        #expect(scheduler.metrics.builderExecutionCount == 1)
        #expect(scheduler.metrics.identicalInputDropCount == 1)
    }

    @Test
    func panAndZoomChangesDoNotProduceAnotherBuild() async {
        let graphID = uuid(22)
        let input = makeInput(lensDepth: 2)
        let scheduler = GraphCanvasDerivedStateScheduler()
        var pan = CGSize.zero
        var scale: CGFloat = 1

        scheduler.schedule(
            input: input,
            graphID: graphID,
            reason: .initial,
            commit: { _ in }
        )
        await scheduler.waitForCurrentWork()

        pan = CGSize(width: 30, height: -10)
        scale = 1.8
        scheduler.schedule(
            input: input,
            graphID: graphID,
            reason: .selectionOrLens,
            commit: { _ in }
        )
        await scheduler.waitForCurrentWork()

        #expect(pan == CGSize(width: 30, height: -10))
        #expect(scale == 1.8)
        #expect(scheduler.metrics.builderExecutionCount == 1)
        #expect(scheduler.metrics.identicalInputDropCount == 1)
    }

    @Test
    func metricsSeparateSchedulingRequestsFromActualBuilds() async {
        let graphID = uuid(23)
        let scheduler = GraphCanvasDerivedStateScheduler()

        for depth in 1...4 {
            scheduler.schedule(
                input: makeInput(lensDepth: depth),
                graphID: graphID,
                reason: .selectionOrLens,
                commit: { _ in }
            )
        }
        await scheduler.waitForCurrentWork()

        #expect(scheduler.metrics.schedulingRequestCount == 4)
        #expect(scheduler.metrics.builderExecutionCount == 1)
        #expect(scheduler.metrics.coalescedRequestCount == 3)
        #expect(scheduler.metrics.requestCountByReason[.selectionOrLens] == 4)
        #expect(scheduler.metrics.buildCountByReason[.selectionOrLens] == 1)
        #expect(scheduler.metrics.lastBuildDurationMilliseconds >= 0)
    }

    @Test
    func graphTransitionSuppressesIntermediateInputAndBuildsFinalInput() async {
        let graphID = uuid(24)
        let staleInput = makeInput(lensDepth: 1)
        let finalInput = makeInput(lensDepth: 2)
        let scheduler = GraphCanvasDerivedStateScheduler()
        var committedDepths: [Int] = []

        scheduler.beginGraphTransition(to: graphID)
        scheduler.schedule(
            input: staleInput,
            graphID: graphID,
            reason: .detailsFocus,
            commit: { committedDepths.append($0.lens.depth) }
        )
        scheduler.resumeAfterGraphTransition(
            input: finalInput,
            graphID: graphID,
            commit: { committedDepths.append($0.lens.depth) }
        )
        await scheduler.waitForCurrentWork()

        #expect(committedDepths == [2])
        #expect(scheduler.metrics.schedulingRequestCount == 2)
        #expect(scheduler.metrics.builderExecutionCount == 1)
        #expect(scheduler.metrics.coalescedRequestCount == 1)
    }

    private func makeInput(
        selection: NodeKey? = nil,
        edges: [GraphEdge] = [],
        showAllLinksForSelection: Bool = false,
        degreeCap: Int = 12,
        lensEnabled: Bool = true,
        lensHideNonRelevant: Bool = false,
        lensDepth: Int = 2,
        detailsFocusState: GraphDetailsFocusState? = nil,
        detailsFocusPreparedState: GraphDetailsPreparedState = .empty,
        labels: [NodeKey: String] = [:]
    ) -> GraphCanvasDerivedStateInputSnapshot {
        GraphCanvasDerivedStateInputSnapshot(
            selection: selection,
            edges: edges,
            showAllLinksForSelection: showAllLinksForSelection,
            degreeCap: degreeCap,
            lensEnabled: lensEnabled,
            lensHideNonRelevant: lensHideNonRelevant,
            lensDepth: lensDepth,
            detailsFocusState: detailsFocusState,
            detailsFocusPreparedState: detailsFocusPreparedState,
            labelLookup: labels
        )
    }

    private func detailsFixture() -> (
        focus: GraphDetailsFocusState,
        prepared: GraphDetailsPreparedState
    ) {
        let entityID = uuid(100)
        let fieldID = uuid(101)
        let attributeKey = NodeKey(kind: .attribute, uuid: uuid(102))
        let focus = GraphDetailsFocusState(
            entityID: entityID,
            entityName: "Entity",
            rule: GraphDetailsMatchRule(
                fieldID: fieldID,
                fieldName: "Status",
                fieldType: .singleChoice,
                comparison: .equals(.choice("Active"))
            ),
            mode: .highlight
        )
        let prepared = GraphDetailsPreparedState(
            attributes: [
                GraphDetailsPreparedAttribute(
                    nodeKey: attributeKey,
                    attributeID: attributeKey.uuid,
                    entityID: entityID,
                    valuesByFieldID: [
                        fieldID: GraphDetailsPreparedValue(
                            stringValue: "Active",
                            intValue: nil,
                            doubleValue: nil,
                            dateValue: nil,
                            boolValue: nil
                        )
                    ]
                )
            ],
            fieldsByEntityID: [
                entityID: [
                    GraphDetailsPreparedField(
                        id: fieldID,
                        entityID: entityID,
                        name: "Status",
                        type: .singleChoice,
                        sortIndex: 0,
                        isPinned: true,
                        unit: nil,
                        options: ["Active"]
                    )
                ]
            ]
        )
        return (focus, prepared)
    }

    private func key(_ suffix: Int) -> NodeKey {
        NodeKey(kind: .entity, uuid: uuid(suffix))
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "D0000000-0000-0000-0000-%012d", suffix))!
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

@Suite("Graph Canvas derived-state input parity")
@MainActor
struct GraphCanvasDerivedStateInputParityTests {
    @Test
    func snapshotMatchesExistingBuilderExactly() {
        let selection = key(1)
        let alpha = key(2)
        let beta = key(3)
        let edges = [
            GraphEdge(a: selection, b: beta, type: .link),
            GraphEdge(a: selection, b: alpha, type: .link)
        ]
        let labels = [selection: "Selection", alpha: "Alpha", beta: "Beta"]
        let input = makeInput(
            selection: selection,
            edges: edges,
            degreeCap: 1,
            lensEnabled: false,
            lensHideNonRelevant: false,
            lensDepth: 2,
            labels: labels
        )

        #expect(input.buildDerivedState() == directBuild(input))
    }

    @Test
    func selectionResultsRemainIdentical() {
        let selection = key(4)
        let peer = key(5)
        let edge = GraphEdge(a: selection, b: peer, type: .link)
        let input = makeInput(
            selection: selection,
            edges: [edge],
            labels: [selection: "Selection", peer: "Peer"]
        )

        let snapshotResult = input.buildDerivedState()
        let directResult = directBuild(input)

        #expect(snapshotResult.drawEdges == directResult.drawEdges)
        #expect(snapshotResult.physicsRelevant == directResult.physicsRelevant)
    }

    @Test
    func lensDepthAndHideNonRelevantRemainIdentical() {
        let selection = key(6)
        let neighbor = key(7)
        let secondHop = key(8)
        let input = makeInput(
            selection: selection,
            edges: [
                GraphEdge(a: selection, b: neighbor, type: .link),
                GraphEdge(a: neighbor, b: secondHop, type: .link)
            ],
            showAllLinksForSelection: true,
            lensEnabled: true,
            lensHideNonRelevant: true,
            lensDepth: 2,
            labels: [
                selection: "Selection",
                neighbor: "Neighbor",
                secondHop: "Second"
            ]
        )

        #expect(input.buildDerivedState().lens == directBuild(input).lens)
    }

    @Test
    func detailsFocusAndExpansionRemainIdentical() {
        let fixture = detailsFixture()
        let input = makeInput(
            detailsFocusState: fixture.focus,
            detailsFocusPreparedState: fixture.prepared
        )

        let snapshotResult = input.buildDerivedState()
        let directResult = directBuild(input)

        #expect(snapshotResult.detailsFocusSummary == directResult.detailsFocusSummary)
        #expect(snapshotResult.detailsFocusRenderPlan == directResult.detailsFocusRenderPlan)
    }

    @Test
    func edgeSelectionAndDegreeCapRemainIdentical() {
        let selection = key(9)
        let peers = [key(10), key(11), key(12)]
        let edges = peers.map { GraphEdge(a: selection, b: $0, type: .link) }
        let labels = [
            selection: "Selection",
            peers[0]: "Zulu",
            peers[1]: "Alpha",
            peers[2]: "Beta"
        ]
        let input = makeInput(
            selection: selection,
            edges: edges,
            degreeCap: 2,
            labels: labels
        )

        #expect(input.buildDerivedState().drawEdges == directBuild(input).drawEdges)
    }

    @Test
    func labelLookupKeepsStableSortIdentical() {
        let selection = key(13)
        let alpha = key(14)
        let zulu = key(15)
        let input = makeInput(
            selection: selection,
            edges: [
                GraphEdge(a: selection, b: zulu, type: .link),
                GraphEdge(a: selection, b: alpha, type: .link)
            ],
            degreeCap: 1,
            labels: [
                selection: "Selection",
                alpha: "Alpha",
                zulu: "Zulu"
            ]
        )

        #expect(input.buildDerivedState().drawEdges == directBuild(input).drawEdges)
        #expect(input.buildDerivedState().drawEdges.first?.a == alpha ||
                input.buildDerivedState().drawEdges.first?.b == alpha)
    }

    @Test
    func unchangedDerivedOutputProducesNoCommitMutation() {
        let input = makeInput(lensDepth: 2)
        let derived = input.buildDerivedState()

        let mutation = GraphCanvasDerivedStateCacheMutation.diff(
            cachedDrawEdges: derived.drawEdges,
            cachedLens: derived.lens,
            cachedPhysicsRelevant: derived.physicsRelevant,
            cachedDetailsFocusSummary: derived.detailsFocusSummary,
            cachedDetailsFocusRenderPlan: derived.detailsFocusRenderPlan,
            derived: derived
        )

        #expect(mutation.hasChanges == false)
        #expect(mutation.drawEdgesChanged == false)
        #expect(mutation.lensChanged == false)
        #expect(mutation.physicsRelevantChanged == false)
        #expect(mutation.detailsFocusSummaryChanged == false)
        #expect(mutation.detailsFocusRenderPlanChanged == false)
    }

    @Test
    func nodeListIsReducedToValueOnlyLabelLookup() {
        let first = GraphNode(key: key(16), label: "First")
        let second = GraphNode(key: key(17), label: "Second")
        let cachedLabels = [first.key: "Cached First"]

        let lookup = GraphCanvasDerivedStateInputSnapshot.makeLabelLookup(
            nodes: [first, second],
            labelCache: cachedLabels
        )

        #expect(lookup[first.key] == "Cached First")
        #expect(lookup[second.key] == "Second")
    }

    private func directBuild(
        _ input: GraphCanvasDerivedStateInputSnapshot
    ) -> GraphCanvasDerivedStateSnapshot {
        GraphCanvasDerivedStateBuilder.build(
            selection: input.selection,
            edges: input.edges,
            showAllLinksForSelection: input.showAllLinksForSelection,
            degreeCap: input.degreeCap,
            lensEnabled: input.lensEnabled,
            lensHideNonRelevant: input.lensHideNonRelevant,
            lensDepth: input.lensDepth,
            detailsFocusState: input.detailsFocusState,
            detailsFocusPreparedState: input.detailsFocusPreparedState,
            labelForKey: { input.labelLookup[$0, default: ""] }
        )
    }

    private func makeInput(
        selection: NodeKey? = nil,
        edges: [GraphEdge] = [],
        showAllLinksForSelection: Bool = false,
        degreeCap: Int = 12,
        lensEnabled: Bool = true,
        lensHideNonRelevant: Bool = false,
        lensDepth: Int = 2,
        detailsFocusState: GraphDetailsFocusState? = nil,
        detailsFocusPreparedState: GraphDetailsPreparedState = .empty,
        labels: [NodeKey: String] = [:]
    ) -> GraphCanvasDerivedStateInputSnapshot {
        GraphCanvasDerivedStateInputSnapshot(
            selection: selection,
            edges: edges,
            showAllLinksForSelection: showAllLinksForSelection,
            degreeCap: degreeCap,
            lensEnabled: lensEnabled,
            lensHideNonRelevant: lensHideNonRelevant,
            lensDepth: lensDepth,
            detailsFocusState: detailsFocusState,
            detailsFocusPreparedState: detailsFocusPreparedState,
            labelLookup: labels
        )
    }

    private func detailsFixture() -> (
        focus: GraphDetailsFocusState,
        prepared: GraphDetailsPreparedState
    ) {
        let entityID = uuid(200)
        let fieldID = uuid(201)
        let matchingKey = NodeKey(kind: .attribute, uuid: uuid(202))
        let nonMatchingKey = NodeKey(kind: .attribute, uuid: uuid(203))
        let focus = GraphDetailsFocusState(
            entityID: entityID,
            entityName: "Entity",
            rule: GraphDetailsMatchRule(
                fieldID: fieldID,
                fieldName: "Priority",
                fieldType: .numberInt,
                comparison: .greaterThanOrEqual(.int(3))
            ),
            mode: .onlyMatches
        )
        let prepared = GraphDetailsPreparedState(
            attributes: [
                preparedAttribute(
                    key: matchingKey,
                    entityID: entityID,
                    fieldID: fieldID,
                    value: 5
                ),
                preparedAttribute(
                    key: nonMatchingKey,
                    entityID: entityID,
                    fieldID: fieldID,
                    value: 1
                )
            ],
            fieldsByEntityID: [
                entityID: [
                    GraphDetailsPreparedField(
                        id: fieldID,
                        entityID: entityID,
                        name: "Priority",
                        type: .numberInt,
                        sortIndex: 0,
                        isPinned: true,
                        unit: nil,
                        options: []
                    )
                ]
            ]
        )
        return (focus, prepared)
    }

    private func preparedAttribute(
        key: NodeKey,
        entityID: UUID,
        fieldID: UUID,
        value: Int
    ) -> GraphDetailsPreparedAttribute {
        GraphDetailsPreparedAttribute(
            nodeKey: key,
            attributeID: key.uuid,
            entityID: entityID,
            valuesByFieldID: [
                fieldID: GraphDetailsPreparedValue(
                    stringValue: nil,
                    intValue: value,
                    doubleValue: nil,
                    dateValue: nil,
                    boolValue: nil
                )
            ]
        )
    }

    private func key(_ suffix: Int) -> NodeKey {
        NodeKey(kind: .entity, uuid: uuid(suffix))
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "E0000000-0000-0000-0000-%012d", suffix))!
    }
}

@MainActor
private final class GraphCanvasDerivedStateBuildGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
