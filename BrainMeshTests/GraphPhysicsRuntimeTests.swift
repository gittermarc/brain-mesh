import CoreGraphics
import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph physics simulation actor")
@MainActor
struct GraphPhysicsRuntimeTests {
    @Test
    func simulationOwnerHasActorIsolation() {
        requireActor(GraphPhysicsSimulationActor.self)
    }

    @Test
    func firstSynchronizationBuildsStableContiguousState() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 8,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)

        let initial = await runtime.debugSnapshotForTesting()
        #expect(initial.positions == fixture.step.positions)
        #expect(initial.velocities == fixture.step.velocities)
        #expect(initial.indexByNodeKey.count == 8)
        for (index, node) in fixture.step.nodes.enumerated() {
            #expect(initial.indexByNodeKey[node.key] == index)
        }

        await runtime.runNextScheduledTickForTesting()
        let advanced = await runtime.debugSnapshotForTesting()
        #expect(advanced.metrics.engineTickCount == 1)
        #expect(advanced.positions != fixture.step.positions)
        #expect(advanced.metrics.velocityCommitCount == 0)
    }

    @Test
    func consecutiveTicksReuseOneWorkspace() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 8,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)

        for _ in 0..<5 {
            await runtime.runNextScheduledTickForTesting()
        }
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.metrics.workspaceFullResetCount == 1)
        #expect(debug.metrics.workspaceReuseCount == 4)
    }

    @Test
    func externalPositionChangeResynchronizesExactlyOnce() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        await runtime.flushForTesting()
        let key = fixture.step.nodes[0].key
        let userPosition = CGPoint(x: 900, y: -700)
        harness.externalPositions[key] = userPosition

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .externalState
        )
        var debug = await runtime.debugSnapshotForTesting()
        #expect(debug.metrics.externalResynchronizationCount == 1)
        #expect(debug.positions[key] == userPosition)
        #expect(debug.velocities[key] == .zero)
        #expect(debug.state.cadencePhase == .active)
        #expect(debug.state.hasScheduledTick)

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .externalState
        )
        debug = await runtime.debugSnapshotForTesting()
        #expect(debug.metrics.externalResynchronizationCount == 1)
    }

    @Test
    func ownSnapshotFeedbackDoesNotResynchronizeWorkspace() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        await runtime.runNextScheduledTickForTesting()

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .externalState
        )
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.metrics.externalResynchronizationCount == 0)
        #expect(debug.metrics.workspaceFullResetCount == 1)
    }

    @Test
    func indexedWorkspaceMatchesPureEngineWithinTolerance() {
        let input = GraphPhysicsFixtures.deterministicInput(
            nodeCount: 120
        )
        let prepared = GraphPhysicsPreparedStepInput(
            input: GraphPhysicsWorkspaceStepInput(
                stepInput: input
            )
        )
        var workspace = GraphPhysicsWorkspace()
        workspace.fullReset(
            positions: input.positions,
            velocities: input.velocities
        )
        workspace.prepareStep(preparedInput: prepared)
        var pureInput = input

        for _ in 0..<24 {
            _ = GraphPhysicsEngine.stepPreparedWorkspace(
                preparedInput: prepared,
                workspace: &workspace
            )
            let pure = GraphPhysicsEngine.step(input: pureInput)
            assertPositions(
                workspace.positions,
                equal: pure.positions,
                tolerance: 0.000_001
            )
            assertVelocities(
                workspace.velocities,
                equal: pure.velocities,
                tolerance: 0.000_001
            )
            pureInput = GraphPhysicsStepInput(
                nodes: input.nodes,
                edges: input.edges,
                positions: pure.positions,
                velocities: pure.velocities,
                fixedNodeKeys: input.fixedNodeKeys,
                physicsRelevant: input.physicsRelevant,
                configuration: input.configuration
            )
        }
    }

    @Test
    func publishedSnapshotContainsPositionsButNoVelocitiesOrForces() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let keys = fixture.step.nodes.map(\.key)
        let snapshot = GraphPhysicsPositionSnapshot(
            graphID: fixture.runtime.graphID,
            identity: fixture.runtime.identity,
            commandRevision: 1,
            snapshotRevision: 1,
            orderedNodeKeys: keys,
            positions: keys.map {
                fixture.step.positions[$0] ?? .zero
            },
            positionPresence: Array(
                repeating: true,
                count: keys.count
            )
        )
        let labels = Set(
            Mirror(reflecting: snapshot).children.compactMap {
                $0.label
            }
        )

        #expect(labels.contains("positions"))
        #expect(!labels.contains("velocities"))
        #expect(!labels.contains("forces"))
    }

    @Test
    func currentDragPositionWinsDuringSnapshotBoundaryRace() {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let draggedKey = fixture.step.nodes[0].key
        let userPosition = CGPoint(x: 1_200, y: -900)
        var currentPositions = fixture.step.positions
        currentPositions[draggedKey] = userPosition

        let merged = GraphCanvasPhysicsPositionMergePolicy.merge(
            actorPositions: fixture.step.positions,
            currentPositions: currentPositions,
            protectedNodeKeys: [draggedKey]
        )

        #expect(merged[draggedKey] == userPosition)
        for node in fixture.step.nodes.dropFirst() {
            #expect(
                merged[node.key] == fixture.step.positions[node.key]
            )
        }
    }

    @Test
    func stableStateDoesNotPublishDuplicateSnapshots() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 12,
            speed: 0
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)

        for _ in 0..<20 {
            await runtime.runNextScheduledTickForTesting()
        }
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.metrics.engineTickCount > 0)
        #expect(debug.metrics.positionCommitCount == 0)
        #expect(debug.metrics.coalescedSnapshotCount > 0)
        #expect(harness.committedPositions.isEmpty)
    }

    @Test
    func adaptiveRuntimeCoalescesManyTicksToFewerSnapshots() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 40,
            speed: 0.01
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)

        for _ in 0..<60 {
            await runtime.runNextScheduledTickForTesting()
        }
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.metrics.engineTickCount >= 30)
        #expect(
            debug.metrics.positionCommitCount
                < debug.metrics.engineTickCount
        )
        #expect(debug.metrics.coalescedSnapshotCount > 0)
        #expect(debug.metrics.settlingTickCount > 0)
        #expect(debug.metrics.quietTickCount > 0)
        #expect(debug.metrics.velocityCommitCount == 0)
    }

    @Test
    func addAndRemovePreserveRetainedNodePositionsAndMapping() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 6,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        await runtime.runNextScheduledTickForTesting()
        let before = await runtime.debugSnapshotForTesting()

        let added = GraphPhysicsFixtures.node(
            90_001,
            kind: .entity
        )
        var positions = harness.externalPositions
        positions[added.key] = CGPoint(x: 800, y: -400)
        harness.externalPositions = positions
        let withAddedNode = GraphPhysicsRuntimeTestInputs.replacing(
            fixture.runtime,
            nodes: fixture.runtime.nodes + [added]
        )
        harness.connect(
            runtime,
            input: withAddedNode,
            reason: .nodeSet
        )
        let afterAdd = await runtime.debugSnapshotForTesting()

        for (index, node) in fixture.step.nodes.enumerated() {
            #expect(afterAdd.indexByNodeKey[node.key] == index)
            #expect(afterAdd.positions[node.key] == before.positions[node.key])
        }
        #expect(afterAdd.indexByNodeKey[added.key] == 6)
        #expect(afterAdd.positions[added.key] == positions[added.key])

        let removedKey = fixture.step.nodes[2].key
        let retainedNodes = withAddedNode.nodes.filter {
            $0.key != removedKey
        }
        harness.externalPositions.removeValue(forKey: removedKey)
        let afterRemovalInput = GraphPhysicsRuntimeTestInputs.replacing(
            withAddedNode,
            nodes: retainedNodes,
            edges: withAddedNode.edges.filter {
                $0.a != removedKey && $0.b != removedKey
            }
        )
        harness.connect(
            runtime,
            input: afterRemovalInput,
            reason: .nodeSet
        )
        let afterRemoval = await runtime.debugSnapshotForTesting()

        #expect(afterRemoval.indexByNodeKey[removedKey] == nil)
        for node in retainedNodes {
            #expect(
                afterRemoval.positions[node.key]
                    == afterAdd.positions[node.key]
            )
        }
    }

    @Test
    func nodeAdditionPreservesUnpublishedActorPositions() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 6,
            speed: 0.01
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)

        for _ in 0..<7 {
            await runtime.runNextScheduledTickForTesting()
        }
        let beforeAdd = await runtime.debugSnapshotForTesting()
        #expect(beforeAdd.metrics.skippedCommitCount > 0)
        #expect(beforeAdd.positions != harness.externalPositions)

        let added = GraphPhysicsFixtures.node(
            90_002,
            kind: .attribute
        )
        harness.externalPositions[added.key] = CGPoint(
            x: -500,
            y: 700
        )
        let updatedInput = GraphPhysicsRuntimeTestInputs.replacing(
            fixture.runtime,
            nodes: fixture.runtime.nodes + [added]
        )
        harness.connect(
            runtime,
            input: updatedInput,
            reason: .nodeSet
        )
        let afterAdd = await runtime.debugSnapshotForTesting()

        for node in fixture.step.nodes {
            #expect(
                afterAdd.positions[node.key]
                    == beforeAdd.positions[node.key]
            )
        }
        #expect(
            afterAdd.positions[added.key]
                == harness.externalPositions[added.key]
        )
    }

    @Test
    func graphSwitchRejectsOldScheduledTick() async {
        let first = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let second = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 5,
            speed: 1,
            graphID: UUID(
                uuidString:
                    "00000000-0000-0000-0000-00000000A099"
            )!
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: first.step
        )
        harness.connect(runtime, input: first.runtime)
        let staleToken = await runtime.scheduledTokenForTesting()

        harness.replaceExternalState(stepInput: second.step)
        harness.connect(
            runtime,
            input: second.runtime,
            reason: .graphChanged
        )
        let afterSwitch = await runtime.debugSnapshotForTesting()
        if let staleToken {
            await runtime.fireScheduledCallbackForTesting(staleToken)
        }
        let afterStaleTick = await runtime.debugSnapshotForTesting()

        #expect(afterSwitch.state.identity == second.runtime.identity)
        #expect(afterSwitch.metrics.graphSwitchCount == 1)
        #expect(
            afterStaleTick.metrics.engineTickCount
                == afterSwitch.metrics.engineTickCount
        )
        #expect(harness.externalPositions == second.step.positions)
    }

    @Test
    func staleSnapshotCannotOverwriteCurrentDragPosition() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        let beforeDrag = await runtime.debugSnapshotForTesting()
        let keys = fixture.step.nodes.map(\.key)
        let stale = GraphPhysicsPositionSnapshot(
            graphID: fixture.runtime.graphID,
            identity: fixture.runtime.identity,
            commandRevision: beforeDrag.state.commandRevision,
            snapshotRevision: 10,
            orderedNodeKeys: keys,
            positions: keys.map {
                beforeDrag.positions[$0] ?? .zero
            },
            positionPresence: Array(
                repeating: true,
                count: keys.count
            )
        )

        let draggedKey = keys[0]
        let userPosition = CGPoint(x: 1_200, y: -900)
        harness.externalPositions[draggedKey] = userPosition
        let draggingInput = GraphPhysicsRuntimeTestInputs.replacing(
            fixture.runtime,
            fixedNodeKeys: [draggedKey],
            isDragging: true
        )
        harness.connect(
            runtime,
            input: draggingInput,
            reason: .externalState
        )
        await runtime.acceptSnapshotForTesting(stale)
        await runtime.flushForTesting()

        #expect(harness.externalPositions[draggedKey] == userPosition)
        let debug = await runtime.debugSnapshotForTesting()
        #expect(debug.metrics.droppedSnapshotCount == 1)
    }

    @Test
    func rejectedUISnapshotDoesNotRewindUnpublishedActorState() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let actor = GraphPhysicsSimulationActor(
            automaticallySchedules: false,
            snapshotSink: { _ in false }
        )
        let initialCommand = GraphPhysicsSimulationCommand(
            input: fixture.runtime,
            identity: fixture.runtime.identity,
            externalPositions: fixture.step.positions,
            initialVelocities: fixture.step.velocities,
            simulationAllowed: true,
            reason: .initial,
            commandRevision: 1
        )
        await actor.update(initialCommand)
        await actor.runNextScheduledTickForTesting()
        let afterRejectedPublish = await actor.debugSnapshot()

        #expect(afterRejectedPublish.metrics.droppedSnapshotCount == 1)
        #expect(afterRejectedPublish.positions != fixture.step.positions)

        await actor.update(
            GraphPhysicsSimulationCommand(
                input: fixture.runtime,
                identity: fixture.runtime.identity,
                externalPositions: fixture.step.positions,
                initialVelocities: [:],
                simulationAllowed: true,
                reason: .selection,
                commandRevision: 2
            )
        )
        let afterNewCommand = await actor.debugSnapshot()

        #expect(
            afterNewCommand.positions
                == afterRejectedPublish.positions
        )
    }

    @Test
    func draggingPinningSpotlightAndEdgesApplyBeforeNextTick() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 6,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        await runtime.flushForTesting()

        let fixedKey = fixture.step.nodes[0].key
        let relevant = Set(
            fixture.step.nodes.prefix(3).map(\.key)
        )
        let updated = GraphPhysicsRuntimeInput(
            graphID: fixture.runtime.graphID,
            nodes: fixture.runtime.nodes,
            edges: [],
            fixedNodeKeys: [fixedKey],
            physicsRelevant: relevant,
            configuration: fixture.runtime.configuration,
            workMode: .organize,
            selection: fixedKey,
            isDragging: true
        )
        let fixedPosition = harness.externalPositions[fixedKey]
        harness.connect(
            runtime,
            input: updated,
            reason: .draggingStarted
        )
        await runtime.runNextScheduledTickForTesting()
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.positions[fixedKey] == fixedPosition)
        #expect(debug.velocities[fixedKey] == .zero)
        #expect(debug.metrics.lastStepMetrics?.springCount == 0)
        #expect(
            debug.metrics.lastStepMetrics?.simulatedNodeCount == 3
        )
        for node in fixture.step.nodes.dropFirst(3) {
            #expect(debug.velocities[node.key] == .zero)
        }
    }

    @Test
    func collisionStrengthChangeAppliesOnNextActorTick() async {
        let first = GraphPhysicsFixtures.node(7_000, kind: .entity)
        let second = GraphPhysicsFixtures.node(7_001, kind: .entity)
        let positions: [NodeKey: CGPoint] = [
            first.key: .zero,
            second.key: CGPoint(x: 40, y: 0)
        ]
        let zeroConfiguration = GraphPhysicsConfiguration(
            collisionStrength: 0,
            repulsion: 0,
            linkSpring: 0,
            containmentSpring: 0,
            damping: 1
        )
        let step = GraphPhysicsStepInput(
            nodes: [first, second],
            edges: [],
            positions: positions,
            velocities: [:],
            fixedNodeKeys: [],
            physicsRelevant: nil,
            configuration: zeroConfiguration
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(stepInput: step)
        var input = GraphPhysicsRuntimeInput(
            graphID: UUID(
                uuidString:
                    "00000000-0000-0000-0000-00000000A010"
            )!,
            stepInput: step
        )
        harness.connect(runtime, input: input)
        await runtime.flushForTesting()
        input = GraphPhysicsRuntimeTestInputs.replacing(
            input,
            configuration: GraphPhysicsConfiguration(
                collisionStrength: 0.09,
                repulsion: 0,
                linkSpring: 0,
                containmentSpring: 0,
                damping: 1
            )
        )
        harness.connect(
            runtime,
            input: input,
            reason: .collisionStrength
        )

        await runtime.runNextScheduledTickForTesting()
        let debug = await runtime.debugSnapshotForTesting()
        #expect(debug.velocities[first.key, default: .zero].dx < 0)
        #expect(debug.velocities[second.key, default: .zero].dx > 0)
    }

    @Test
    func staleCallbackCannotAdvanceRestartedActor() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        let staleToken = await runtime.scheduledTokenForTesting()

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .selection
        )
        let currentToken = await runtime.scheduledTokenForTesting()
        #expect(staleToken != currentToken)

        if let staleToken {
            await runtime.fireScheduledCallbackForTesting(staleToken)
        }
        var debug = await runtime.debugSnapshotForTesting()
        #expect(debug.metrics.engineTickCount == 0)

        if let currentToken {
            await runtime.fireScheduledCallbackForTesting(currentToken)
        }
        debug = await runtime.debugSnapshotForTesting()
        #expect(debug.metrics.engineTickCount == 1)
        #expect(
            debug.metrics.maximumSimultaneouslyScheduledTickCount == 1
        )
    }

    @Test
    func disablingSimulationRejectsPreviouslyScheduledTick() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        let staleToken = await runtime.scheduledTokenForTesting()
        harness.connect(
            runtime,
            input: fixture.runtime,
            simulationAllowed: false,
            reason: .simulationAllowed
        )
        if let staleToken {
            await runtime.fireScheduledCallbackForTesting(staleToken)
        }
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.metrics.engineTickCount == 0)
        #expect(!debug.state.hasScheduledTick)
        #expect(!debug.state.isRunning)
    }

    @Test
    func tabVisibilityPausesAndResumesExactlyOnce() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 10,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        var debug = await runtime.debugSnapshotForTesting()
        #expect(debug.state.hasScheduledTick)

        harness.connect(
            runtime,
            input: fixture.runtime,
            simulationAllowed: false,
            reason: .simulationAllowed
        )
        debug = await runtime.debugSnapshotForTesting()
        #expect(!debug.state.isRunning)
        #expect(!debug.state.hasScheduledTick)
        #expect(debug.metrics.pauseCount == 1)

        harness.connect(
            runtime,
            input: fixture.runtime,
            simulationAllowed: false,
            reason: .simulationAllowed
        )
        debug = await runtime.debugSnapshotForTesting()
        #expect(debug.metrics.pauseCount == 1)

        harness.connect(
            runtime,
            input: fixture.runtime,
            simulationAllowed: true,
            reason: .simulationAllowed
        )
        debug = await runtime.debugSnapshotForTesting()
        #expect(debug.state.hasScheduledTick)
        #expect(debug.metrics.resumeCount == 1)
        #expect(
            debug.metrics
                .maximumSimultaneouslyScheduledTickCount == 1
        )
    }

    @Test
    func memoryPressureLeavesOneControlledSchedule() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 120,
            speed: 1
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)
        await runtime.runNextScheduledTickForTesting()
        runtime.handleMemoryPressure()
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.metrics.memoryPressureCount == 1)
        #expect(debug.state.hasScheduledTick)
        #expect(debug.metrics.resumeCount == 1)
        #expect(
            debug.metrics
                .maximumSimultaneouslyScheduledTickCount == 1
        )
        #expect(debug.workspaceCapacity.positionedGridNodeCapacity == 0)
    }

    @Test
    func instabilityResetsQuietStabilityCounter() {
        let configuration = GraphPhysicsAdaptiveConfiguration.production
        var policy = GraphPhysicsStabilityPolicy()
        let firstSample = policy.observe(
            cadencePhase: .quiet,
            maxSimSpeed: 0.01,
            maximumUnpublishedPositionDelta: 0.01,
            isDragging: false,
            simulationAllowed: true,
            externalInputChangePending: false,
            configuration: configuration
        )
        #expect(!firstSample)
        #expect(policy.stableQuietSamples == 1)

        _ = policy.observe(
            cadencePhase: .quiet,
            maxSimSpeed: 0.04,
            maximumUnpublishedPositionDelta: 0.01,
            isDragging: false,
            simulationAllowed: true,
            externalInputChangePending: false,
            configuration: configuration
        )
        #expect(policy.stableQuietSamples == 0)
    }

    @Test
    func draggingAndUnpublishedMovementPreventSleep() {
        let configuration = GraphPhysicsAdaptiveConfiguration.production
        var draggingPolicy = GraphPhysicsStabilityPolicy()
        for _ in 0..<configuration.stableQuietSamplesRequired {
            let shouldSleep = draggingPolicy.observe(
                cadencePhase: .quiet,
                maxSimSpeed: 0,
                maximumUnpublishedPositionDelta: 0,
                isDragging: true,
                simulationAllowed: true,
                externalInputChangePending: false,
                configuration: configuration
            )
            #expect(!shouldSleep)
        }

        var movementPolicy = GraphPhysicsStabilityPolicy()
        for _ in 0..<configuration.stableQuietSamplesRequired {
            let shouldSleep = movementPolicy.observe(
                cadencePhase: .quiet,
                maxSimSpeed: 0,
                maximumUnpublishedPositionDelta:
                    configuration.visualCommitEpsilon,
                isDragging: false,
                simulationAllowed: true,
                externalInputChangePending: false,
                configuration: configuration
            )
            #expect(!shouldSleep)
        }
    }

    @Test
    func sleepNeverOccursAboveQuietEntryThreshold() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.031
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)

        for _ in 0..<80 {
            await runtime.runNextScheduledTickForTesting()
        }
        let debug = await runtime.debugSnapshotForTesting()
        #expect(!debug.state.isSleeping)
        #expect(debug.metrics.sleepCount == 0)
    }

    @Test
    func wakeAfterSleepReturnsToActiveWithOneSchedule() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(runtime, input: fixture.runtime)

        var debug = await runtime.debugSnapshotForTesting()
        while !debug.state.isSleeping {
            await runtime.runNextScheduledTickForTesting()
            debug = await runtime.debugSnapshotForTesting()
        }
        let wakeCountBefore = debug.metrics.wakeCount

        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .selection
        )
        debug = await runtime.debugSnapshotForTesting()
        #expect(debug.state.cadencePhase == .active)
        #expect(debug.state.hasScheduledTick)
        #expect(!debug.state.isSleeping)
        #expect(debug.metrics.wakeCount == wakeCountBefore + 1)
        #expect(
            debug.metrics.maximumSimultaneouslyScheduledTickCount == 1
        )
    }

    @Test
    func dragEndRestoresActiveCadenceWithoutVelocityPublication() async {
        let fixture = GraphPhysicsRuntimeTestInputs.controlled(
            nodeCount: 4,
            speed: 0.01
        )
        let draggedKey = fixture.step.nodes[0].key
        let dragging = GraphPhysicsRuntimeTestInputs.replacing(
            fixture.runtime,
            fixedNodeKeys: [draggedKey],
            workMode: .organize,
            isDragging: true
        )
        let runtime = makeRuntime()
        let harness = GraphPhysicsRuntimeTestHarness(
            stepInput: fixture.step
        )
        harness.connect(
            runtime,
            input: dragging,
            reason: .draggingStarted
        )
        await runtime.runNextScheduledTickForTesting()
        harness.externalPositions[draggedKey] = CGPoint(
            x: 750,
            y: -250
        )
        harness.connect(
            runtime,
            input: dragging,
            reason: .externalState
        )
        harness.connect(
            runtime,
            input: fixture.runtime,
            reason: .draggingEnded
        )
        let debug = await runtime.debugSnapshotForTesting()

        #expect(debug.positions[draggedKey] == CGPoint(x: 750, y: -250))
        #expect(debug.metrics.velocityCommitCount == 0)
        #expect(debug.state.cadencePhase == .active)
        #expect(debug.state.hasScheduledTick)
    }

    private func makeRuntime() -> GraphPhysicsRuntime {
        GraphPhysicsRuntime(automaticallySchedules: false)
    }

    private func requireActor<A: Actor>(_ type: A.Type) {}

    private func assertPositions(
        _ lhs: [NodeKey: CGPoint],
        equal rhs: [NodeKey: CGPoint],
        tolerance: CGFloat
    ) {
        #expect(Set(lhs.keys) == Set(rhs.keys))
        for key in lhs.keys {
            let first = lhs[key] ?? .zero
            let second = rhs[key] ?? .zero
            #expect(abs(first.x - second.x) <= tolerance)
            #expect(abs(first.y - second.y) <= tolerance)
        }
    }

    private func assertVelocities(
        _ lhs: [NodeKey: CGVector],
        equal rhs: [NodeKey: CGVector],
        tolerance: CGFloat
    ) {
        #expect(Set(lhs.keys) == Set(rhs.keys))
        for key in lhs.keys {
            let first = lhs[key] ?? .zero
            let second = rhs[key] ?? .zero
            #expect(abs(first.dx - second.dx) <= tolerance)
            #expect(abs(first.dy - second.dy) <= tolerance)
        }
    }
}
