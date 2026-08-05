//
//  GraphPhysicsSimulationActor.swift
//  BrainMesh
//

import CoreGraphics
import Foundation
import os

/// Owns all mutable simulation state and scheduling away from MainActor.
///
/// The actor delegates the mathematical step to `GraphPhysicsEngine`. Its
/// responsibilities are stable-index ownership, lifecycle, adaptive cadence,
/// publication coalescing, and cancellation.
actor GraphPhysicsSimulationActor {
    typealias SnapshotSink =
        @MainActor @Sendable (GraphPhysicsPositionSnapshot) -> Bool

    private let adaptiveConfiguration:
        GraphPhysicsAdaptiveConfiguration
    private let automaticallySchedules: Bool
    private let clock: any GraphPhysicsRuntimeClock
    private let snapshotSink: SnapshotSink

    private var workspace = GraphPhysicsWorkspace()
    private var currentInput: GraphPhysicsRuntimeInput?
    private var currentIdentity: GraphPhysicsRuntimeIdentity?
    private var preparedInput: GraphPhysicsPreparedStepInput?
    private var lastPublishedSnapshot:
        GraphPhysicsPositionSnapshot?
    private var cadencePolicy = GraphPhysicsCadencePolicy()
    private var stabilityPolicy = GraphPhysicsStabilityPolicy()

    private var simulationAllowed = false
    private var isRunning = false
    private var isSleeping = false
    private var ticksSinceLastCommit = 0
    private var maximumCumulativeUnpublishedPositionDelta:
        CGFloat = 0
    private var workspaceTicksSinceFullReset = 0

    private var lifecycleGeneration: UInt64 = 0
    private var schedulingSequence: UInt64 = 0
    private var scheduledToken: GraphPhysicsSchedulingToken?
    private var scheduledTickTask: Task<Void, Never>?
    private var commandRevision: UInt64 = 0
    private var snapshotRevision: UInt64 = 0

    private var rollingTickCount = 0
    private var rollingTickNanos: UInt64 = 0
    private var rollingMaximumTickNanos: UInt64 = 0
    private var rollingPositionCommitCount = 0
    private var rollingSkippedCommitCount = 0

    private var metrics = GraphPhysicsRuntimeMetrics()

    init(
        adaptiveConfiguration:
            GraphPhysicsAdaptiveConfiguration = .production,
        automaticallySchedules: Bool = true,
        clock: any GraphPhysicsRuntimeClock =
            ContinuousGraphPhysicsRuntimeClock(),
        snapshotSink: @escaping SnapshotSink
    ) {
        self.adaptiveConfiguration = adaptiveConfiguration
        self.automaticallySchedules = automaticallySchedules
        self.clock = clock
        self.snapshotSink = snapshotSink
    }

    deinit {
        scheduledTickTask?.cancel()
    }

    func update(_ command: GraphPhysicsSimulationCommand) async {
        let previousInput = currentInput
        let previousAllowed = simulationAllowed
        let identityChanged = currentIdentity.map {
            $0 != command.identity
        } ?? true
        let graphChanged = previousInput.map {
            $0.graphID != command.input.graphID
        } ?? false

        commandRevision = command.commandRevision
        simulationAllowed = command.simulationAllowed

        let nextWorkspaceStepInput = command.input.workspaceStepInput
        let preparedInputChanged: Bool
        if let previousInput, preparedInput != nil {
            preparedInputChanged =
                previousInput.workspaceStepInput
                    != nextWorkspaceStepInput
        } else {
            preparedInputChanged = true
        }
        let nextPreparedInput: GraphPhysicsPreparedStepInput
        if preparedInputChanged {
            nextPreparedInput = GraphPhysicsPreparedStepInput(
                input: nextWorkspaceStepInput
            )
        } else if let preparedInput {
            nextPreparedInput = preparedInput
        } else {
            preconditionFailure(
                "Prepared physics input invariant violated."
            )
        }

        if identityChanged {
            invalidateScheduledTick()
            let synchronizationPositions =
                positionsForIdentitySynchronization(
                    command.externalPositions,
                    graphChanged: graphChanged
                )
            workspace.synchronize(
                preparedInput: nextPreparedInput,
                positions: synchronizationPositions,
                initialVelocities: command.initialVelocities,
                preservesRetainedState: previousInput != nil
                    && !graphChanged
            )
            preparedInput = nextPreparedInput
            workspaceTicksSinceFullReset = 0
            metrics.workspaceFullResetCount += 1
            resetAdaptiveState()

            if graphChanged {
                metrics.graphSwitchCount += 1
                BMGraphPhysicsInstrumentation.graphChanged()
                lastPublishedSnapshot = workspace.makePositionSnapshot(
                    graphID: command.input.graphID,
                    commandRevision: commandRevision,
                    snapshotRevision: snapshotRevision
                )
            } else if previousInput == nil {
                lastPublishedSnapshot = workspace.makePositionSnapshot(
                    graphID: command.input.graphID,
                    commandRevision: commandRevision,
                    snapshotRevision: snapshotRevision
                )
            }
        } else {
            if preparedInputChanged {
                workspace.prepareStep(
                    preparedInput: nextPreparedInput
                )
                preparedInput = nextPreparedInput
            }

            if synchronizeExternalPositionsIfNeeded(
                command.externalPositions
            ) {
                metrics.externalResynchronizationCount += 1
                resetAdaptiveState()
            }
        }

        currentInput = command.input
        currentIdentity = command.identity

        if identityChanged, previousInput != nil, !graphChanged {
            // Topology changed inside the same graph. Publish the reconciled
            // contiguous state once so additions/removals cannot make the UI
            // rewind retained nodes to an older coalesced snapshot.
            await publish(forcedReason: .externalInputChange)
        }

        guard simulationAllowed else {
            await pause(publishesPendingSnapshot: true)
            return
        }

        guard command.input.nodes.count >= 2 else {
            invalidateScheduledTick()
            isRunning = false
            isSleeping = false
            return
        }

        if previousInput != nil, !previousAllowed {
            metrics.resumeCount += 1
            BMGraphPhysicsInstrumentation.resume()
        }

        if command.reason == .draggingEnded {
            await publish(forcedReason: .dragEnd)
        }

        wake(reason: graphChanged ? .graphChanged : command.reason)
    }

    func stop() async {
        simulationAllowed = false
        await pause(publishesPendingSnapshot: true)
    }

    func handleMemoryPressure() async {
        metrics.memoryPressureCount += 1
        BMGraphPhysicsInstrumentation.memoryPressure()
        let shouldResume = simulationAllowed
        let input = currentInput
        await pause(publishesPendingSnapshot: true)
        workspace.releaseTransientCapacity()

        if shouldResume, let input, input.nodes.count >= 2 {
            simulationAllowed = true
            metrics.resumeCount += 1
            BMGraphPhysicsInstrumentation.resume()
            wake(reason: .memoryPressure)
        }
    }

    func runNextScheduledTickForTesting() async {
        guard let scheduledToken else { return }
        await handleScheduledTick(token: scheduledToken)
    }

    func fireScheduledCallbackForTesting(
        _ token: GraphPhysicsSchedulingToken
    ) async {
        await handleScheduledTick(token: token)
    }

    func schedulingTokenForTesting()
        -> GraphPhysicsSchedulingToken? {
        scheduledToken
    }

    func debugSnapshot() -> GraphPhysicsSimulationDebugSnapshot {
        GraphPhysicsSimulationDebugSnapshot(
            positions: workspace.positions,
            velocities: workspace.velocities,
            indexByNodeKey: workspace.nodeIndexByKey,
            state: runtimeState,
            metrics: metrics,
            workspaceCapacity: workspace.capacitySnapshot
        )
    }

    func recordDroppedSnapshot() {
        metrics.droppedSnapshotCount += 1
        BMGraphPhysicsInstrumentation.droppedFrame()
    }

    private var runtimeState: GraphPhysicsRuntimeState {
        GraphPhysicsRuntimeState(
            identity: currentIdentity,
            cadencePhase: cadencePolicy.phase,
            isRunning: isRunning,
            isSleeping: isSleeping,
            hasScheduledTick: scheduledToken != nil,
            ticksSinceLastCommit: ticksSinceLastCommit,
            maximumCumulativeUnpublishedPositionDelta:
                maximumCumulativeUnpublishedPositionDelta,
            stableQuietSamples: stabilityPolicy.stableQuietSamples,
            commandRevision: commandRevision
        )
    }

    private func wake(reason: GraphPhysicsRuntimeWakeReason) {
        guard simulationAllowed,
              let currentInput,
              currentInput.nodes.count >= 2 else {
            return
        }

        cadencePolicy.resetToActive()
        stabilityPolicy.reset()
        ticksSinceLastCommit = 0
        maximumCumulativeUnpublishedPositionDelta = 0
        isSleeping = false
        metrics.wakeCount += 1

        // High-frequency drag updates synchronize the user-controlled node
        // without continually postponing the already-owned physics tick.
        if reason == .externalState,
           isRunning,
           scheduledToken != nil {
            return
        }

        isRunning = true
        invalidateScheduledTick()
        scheduleNextTick()
    }

    private func pause(
        publishesPendingSnapshot: Bool
    ) async {
        let wasActive = isRunning || scheduledToken != nil
        invalidateScheduledTick()
        isRunning = false
        isSleeping = false
        stabilityPolicy.reset()

        if wasActive {
            metrics.pauseCount += 1
            BMGraphPhysicsInstrumentation.pause()
            if publishesPendingSnapshot {
                await publish(forcedReason: .stop)
            }
        }
    }

    private func handleScheduledTick(
        token: GraphPhysicsSchedulingToken
    ) async {
        guard token == scheduledToken,
              token.lifecycleGeneration == lifecycleGeneration else {
            return
        }

        scheduledTickTask?.cancel()
        scheduledTickTask = nil
        scheduledToken = nil

        guard isRunning,
              simulationAllowed,
              let input = currentInput,
              let preparedInput else {
            return
        }

        let tickGeneration = lifecycleGeneration
        let tickCommandRevision = commandRevision
        let phaseForTick = cadencePolicy.phase
        let duration = BMDuration()

        if workspaceTicksSinceFullReset > 0 {
            metrics.workspaceReuseCount += 1
        }
        workspaceTicksSinceFullReset += 1

        let result = BMGraphPhysicsInstrumentation.measureStep {
            GraphPhysicsEngine.stepPreparedWorkspace(
                preparedInput: preparedInput,
                workspace: &workspace
            )
        }
        let tickNanos = duration.nanosecondsElapsed
        metrics.engineTickCount += 1
        metrics.lastStepMetrics = result.metrics
        metrics.totalTheoreticalExactPairCount +=
            result.metrics.theoreticalExactPairCount
        metrics.totalExactCheckedNodePairCount +=
            result.metrics.exactCheckedNodePairCount
        metrics.totalSpringCount += result.metrics.springCount
        recordCadenceTick(phaseForTick)

        _ = cadencePolicy.observe(
            maxSimSpeed: result.maxSimSpeed,
            isDragging: input.isDragging,
            configuration: adaptiveConfiguration
        )

        ticksSinceLastCommit += 1
        let currentPositionDelta = workspace.maximumPositionDelta(
            from: lastPublishedSnapshot
                ?? workspace.makePositionSnapshot(
                    graphID: input.graphID,
                    commandRevision: commandRevision,
                    snapshotRevision: snapshotRevision
                )
        )
        maximumCumulativeUnpublishedPositionDelta = max(
            maximumCumulativeUnpublishedPositionDelta,
            currentPositionDelta
        )

        let shouldCommit = GraphPhysicsCommitPolicy.shouldCommit(
            GraphPhysicsCommitPolicyInput(
                cadencePhase: phaseForTick,
                maximumCumulativePositionDelta:
                    maximumCumulativeUnpublishedPositionDelta,
                maxSimSpeed: result.maxSimSpeed,
                ticksSinceLastCommit: ticksSinceLastCommit,
                forcedReason: nil,
                isDragging: input.isDragging
            ),
            configuration: adaptiveConfiguration
        )

        if shouldCommit {
            await publish(forcedReason: nil)
        } else {
            metrics.skippedCommitCount += 1
            metrics.coalescedSnapshotCount += 1
            rollingSkippedCommitCount += 1
            BMGraphPhysicsInstrumentation.coalescedFrame()
        }

        recordRollingTick(
            nanoseconds: tickNanos,
            stepMetrics: result.metrics
        )

        let shouldSleep = stabilityPolicy.observe(
            cadencePhase: phaseForTick,
            maxSimSpeed: result.maxSimSpeed,
            maximumUnpublishedPositionDelta:
                maximumCumulativeUnpublishedPositionDelta,
            isDragging: input.isDragging,
            simulationAllowed: simulationAllowed,
            externalInputChangePending: false,
            configuration: adaptiveConfiguration
        )

        guard tickGeneration == lifecycleGeneration,
              tickCommandRevision == commandRevision,
              simulationAllowed else {
            return
        }

        if shouldSleep {
            await publish(forcedReason: .sleep)
            metrics.sleepCount += 1
            metrics.lastSleepEngineTick = metrics.engineTickCount
            isSleeping = true
            isRunning = false
            invalidateScheduledTick()
            return
        }

        if isRunning {
            scheduleNextTick()
        }
    }

    private func synchronizeExternalPositionsIfNeeded(
        _ positions: [NodeKey: CGPoint]
    ) -> Bool {
        // A UI position change can be coalesced with a later selection,
        // pinning, drag-end, visibility, or configuration command. Compare
        // every latest command against the published baseline so that the
        // user coordinate is never lost while unpublished actor motion is
        // still retained.
        guard let baseline = lastPublishedSnapshot,
              baseline.orderedNodeKeys == workspace.orderedNodeKeys else {
            let changed = workspace.applyExternalPositions(
                positions,
                zeroesChangedVelocities: true
            )
            if changed, let input = currentInput {
                lastPublishedSnapshot = workspace.makePositionSnapshot(
                    graphID: input.graphID,
                    commandRevision: commandRevision,
                    snapshotRevision: snapshotRevision
                )
            }
            return changed
        }

        var changedPositions: [NodeKey: CGPoint] = [:]
        changedPositions.reserveCapacity(positions.count)
        for (key, position) in positions {
            guard let index = workspace.nodeIndexByKey[key],
                  baseline.positions.indices.contains(index),
                  baseline.positionPresence.indices.contains(index),
                  baseline.positionPresence[index],
                  baseline.positions[index] == position else {
                changedPositions[key] = position
                continue
            }
        }
        guard !changedPositions.isEmpty,
              workspace.applyExternalPositions(
                changedPositions,
                zeroesChangedVelocities: true
              ) else {
            return false
        }

        var publishedPositions = baseline.positions
        var publishedPresence = baseline.positionPresence
        for (key, position) in changedPositions {
            guard let index = workspace.nodeIndexByKey[key],
                  publishedPositions.indices.contains(index),
                  publishedPresence.indices.contains(index) else {
                continue
            }
            publishedPositions[index] = position
            publishedPresence[index] = true
        }
        lastPublishedSnapshot = GraphPhysicsPositionSnapshot(
            graphID: baseline.graphID,
            identity: baseline.identity,
            commandRevision: commandRevision,
            snapshotRevision: baseline.snapshotRevision,
            orderedNodeKeys: baseline.orderedNodeKeys,
            positions: publishedPositions,
            positionPresence: publishedPresence
        )
        return true
    }

    /// Keeps unpublished actor positions for retained node IDs. Only a new node
    /// or a UI position that differs from the last published baseline crosses
    /// back into contiguous simulation storage.
    private func positionsForIdentitySynchronization(
        _ externalPositions: [NodeKey: CGPoint],
        graphChanged: Bool
    ) -> [NodeKey: CGPoint] {
        guard !graphChanged,
              let baseline = lastPublishedSnapshot else {
            return externalPositions
        }

        var overrides: [NodeKey: CGPoint] = [:]
        overrides.reserveCapacity(externalPositions.count)
        for (key, position) in externalPositions {
            guard let oldIndex = workspace.nodeIndexByKey[key],
                  baseline.orderedNodeKeys.indices.contains(oldIndex),
                  baseline.orderedNodeKeys[oldIndex] == key,
                  baseline.positions.indices.contains(oldIndex),
                  baseline.positionPresence.indices.contains(oldIndex),
                  baseline.positionPresence[oldIndex],
                  baseline.positions[oldIndex] == position else {
                overrides[key] = position
                continue
            }
        }
        return overrides
    }

    private func publish(
        forcedReason: GraphPhysicsForcedCommitReason?
    ) async {
        guard workspace.hasSynchronizedState,
              let input = currentInput else {
            return
        }

        snapshotRevision &+= 1
        let snapshot = workspace.makePositionSnapshot(
            graphID: input.graphID,
            commandRevision: commandRevision,
            snapshotRevision: snapshotRevision
        )

        if let previous = lastPublishedSnapshot,
           previous.orderedNodeKeys == snapshot.orderedNodeKeys,
           previous.positions == snapshot.positions,
           previous.positionPresence == snapshot.positionPresence {
            metrics.skippedCommitCount += 1
            metrics.coalescedSnapshotCount += 1
            BMGraphPhysicsInstrumentation.coalescedFrame()
            return
        }

        guard await snapshotSink(snapshot) else {
            recordDroppedSnapshot()
            return
        }

        lastPublishedSnapshot = snapshot
        ticksSinceLastCommit = 0
        maximumCumulativeUnpublishedPositionDelta = 0
        metrics.positionCommitCount += 1
        rollingPositionCommitCount += 1
        if forcedReason != nil {
            metrics.forcedCommitCount += 1
        }
        BMGraphPhysicsInstrumentation.snapshotPublished()
    }

    private func resetAdaptiveState() {
        cadencePolicy.resetToActive()
        stabilityPolicy.reset()
        ticksSinceLastCommit = 0
        maximumCumulativeUnpublishedPositionDelta = 0
        isSleeping = false
    }

    private func recordCadenceTick(
        _ phase: GraphPhysicsCadencePhase
    ) {
        switch phase {
        case .active:
            metrics.activeTickCount += 1
        case .settling:
            metrics.settlingTickCount += 1
        case .quiet:
            metrics.quietTickCount += 1
        }
    }

    private func recordRollingTick(
        nanoseconds: UInt64,
        stepMetrics: GraphPhysicsStepMetrics
    ) {
        rollingTickCount += 1
        rollingTickNanos &+= nanoseconds
        rollingMaximumTickNanos = max(
            rollingMaximumTickNanos,
            nanoseconds
        )

        guard rollingTickCount >= 60 else { return }
        let averageMilliseconds =
            Double(rollingTickNanos)
            / Double(rollingTickCount)
            / 1_000_000.0
        let maximumMilliseconds =
            Double(rollingMaximumTickNanos) / 1_000_000.0

        BMLog.physics.debug(
            "physics_actor avgMs=\(averageMilliseconds, format: .fixed(precision: 2)) maxMs=\(maximumMilliseconds, format: .fixed(precision: 2)) cadence=\(self.cadencePolicy.phase.rawValue, privacy: .public) ticks=\(self.rollingTickCount, privacy: .public) publishes=\(self.rollingPositionCommitCount, privacy: .public) coalesced=\(self.rollingSkippedCommitCount, privacy: .public) strategy=\(stepMetrics.interactionStrategy.rawValue, privacy: .public) simNodes=\(stepMetrics.simulatedNodeCount, privacy: .public) exactPairs=\(stepMetrics.exactCheckedNodePairCount, privacy: .public) gridCells=\(stepMetrics.occupiedGridCellCount, privacy: .public)"
        )

        rollingTickCount = 0
        rollingTickNanos = 0
        rollingMaximumTickNanos = 0
        rollingPositionCommitCount = 0
        rollingSkippedCommitCount = 0
    }

    private func scheduleNextTick() {
        guard isRunning,
              simulationAllowed,
              scheduledToken == nil else {
            return
        }

        schedulingSequence &+= 1
        let token = GraphPhysicsSchedulingToken(
            lifecycleGeneration: lifecycleGeneration,
            sequence: schedulingSequence
        )
        scheduledToken = token
        metrics.maximumSimultaneouslyScheduledTickCount = max(
            metrics.maximumSimultaneouslyScheduledTickCount,
            1
        )

        guard automaticallySchedules else { return }
        let interval = cadencePolicy.phase.interval
        let clock = self.clock
        scheduledTickTask = Task { [weak self] in
            do {
                try await clock.sleep(for: interval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.handleScheduledTick(token: token)
        }
    }

    private func invalidateScheduledTick() {
        scheduledTickTask?.cancel()
        scheduledTickTask = nil
        scheduledToken = nil
        lifecycleGeneration &+= 1
    }
}
