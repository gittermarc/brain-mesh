//
//  GraphPhysicsRuntime.swift
//  BrainMesh
//

import CoreGraphics
import Foundation
import os

@MainActor
final class GraphPhysicsRuntime {
    typealias ExternalStateProvider =
        @MainActor () -> GraphPhysicsExternalState
    typealias CommitHandler =
        @MainActor (GraphPhysicsExternalState) -> Void

    private let adaptiveConfiguration:
        GraphPhysicsAdaptiveConfiguration
    private let automaticallySchedules: Bool

    private var workspace = GraphPhysicsWorkspace()
    private var currentInput: GraphPhysicsRuntimeInput?
    private var lastPublishedState: GraphPhysicsExternalState?
    private var cadencePolicy = GraphPhysicsCadencePolicy()
    private var stabilityPolicy = GraphPhysicsStabilityPolicy()

    private var externalStateProvider: ExternalStateProvider?
    private var commitHandler: CommitHandler?
    private var simulationAllowed = false
    private var isRunning = false
    private var isSleeping = false

    private var ticksSinceLastCommit = 0
    private var maximumCumulativeUnpublishedPositionDelta:
        CGFloat = 0
    private var workspaceTicksSinceFullReset = 0

    private var timer: Timer?
    private var lifecycleGeneration: UInt64 = 0
    private var schedulingSequence: UInt64 = 0
    private var scheduledToken: GraphPhysicsSchedulingToken?

    private var rollingTickCount = 0
    private var rollingTickNanos: UInt64 = 0
    private var rollingMaximumTickNanos: UInt64 = 0
    private var rollingPositionCommitCount = 0
    private var rollingSkippedCommitCount = 0

    private(set) var metrics = GraphPhysicsRuntimeMetrics()

    init(
        adaptiveConfiguration:
            GraphPhysicsAdaptiveConfiguration = .production,
        automaticallySchedules: Bool = true
    ) {
        self.adaptiveConfiguration = adaptiveConfiguration
        self.automaticallySchedules = automaticallySchedules
    }

    deinit {
        timer?.invalidate()
    }

    func update(
        input: GraphPhysicsRuntimeInput,
        externalState: GraphPhysicsExternalState,
        simulationAllowed: Bool,
        reason: GraphPhysicsRuntimeWakeReason,
        externalStateProvider:
            @escaping ExternalStateProvider,
        commit: @escaping CommitHandler
    ) {
        self.externalStateProvider = externalStateProvider
        commitHandler = commit

        let previousInput = currentInput
        let identityChanged =
            previousInput?.identity != input.identity
        let graphChanged =
            previousInput?.graphID != nil
            && previousInput?.graphID != input.graphID

        var didExternalResynchronize = false

        if identityChanged {
            invalidateScheduledTick()

            if !graphChanged,
               workspace.hasSynchronizedState,
               let lastPublishedState,
               externalState == lastPublishedState,
               maximumCumulativeUnpublishedPositionDelta > 0 {
                publish(
                    forcedReason: .beforeDiscard
                )
            }

            let refreshedExternalState =
                externalStateProvider()
            workspace.fullReset(
                positions: refreshedExternalState.positions,
                velocities: refreshedExternalState.velocities
            )
            metrics.workspaceFullResetCount += 1
            workspaceTicksSinceFullReset = 0
            lastPublishedState = refreshedExternalState
            ticksSinceLastCommit = 0
            maximumCumulativeUnpublishedPositionDelta = 0
            cadencePolicy.resetToActive()
            stabilityPolicy.reset()
            isSleeping = false
        } else if workspace.hasSynchronizedState {
            didExternalResynchronize =
                resynchronizeIfExternalStateChanged(
                externalState
            )
        }

        currentInput = input
        self.simulationAllowed = simulationAllowed

        if identityChanged, previousInput != nil {
            publish(
                forcedReason: graphChanged
                    ? .graphChange
                    : .externalInputChange
            )
        } else if didExternalResynchronize {
            publish(forcedReason: .externalInputChange)
        }

        guard simulationAllowed else {
            stop()
            return
        }

        guard input.nodes.count >= 2 else {
            invalidateScheduledTick()
            isRunning = false
            isSleeping = false
            return
        }

        if reason == .externalState,
           !identityChanged,
           !didExternalResynchronize,
           lastPublishedState == externalState {
            return
        }

        if reason == .draggingEnded,
           workspace.hasSynchronizedState {
            publish(forcedReason: .dragEnd)
        }

        wake(reason: graphChanged ? .graphChanged : reason)
    }

    func stop() {
        let wasRunning = isRunning || scheduledToken != nil

        if wasRunning,
           workspace.hasSynchronizedState {
            if let externalStateProvider {
                _ = resynchronizeIfExternalStateChanged(
                    externalStateProvider()
                )
            }
            publish(forcedReason: .stop)
        }

        invalidateScheduledTick()
        isRunning = false
        isSleeping = false
        stabilityPolicy.reset()
    }

    func wake(reason: GraphPhysicsRuntimeWakeReason) {
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
        isRunning = true
        metrics.wakeCount += 1

        invalidateScheduledTick()
        scheduleNextTick()
    }

    func fireScheduledCallbackForTesting(
        _ token: GraphPhysicsSchedulingToken
    ) {
        handleScheduledTick(token: token)
    }

    func runNextScheduledTickForTesting() {
        guard let scheduledToken else { return }
        handleScheduledTick(token: scheduledToken)
    }

    var scheduledTokenForTesting:
        GraphPhysicsSchedulingToken? {
        scheduledToken
    }

    var state: GraphPhysicsRuntimeState {
        GraphPhysicsRuntimeState(
            identity: currentInput?.identity,
            cadencePhase: cadencePolicy.phase,
            isRunning: isRunning,
            isSleeping: isSleeping,
            hasScheduledTick: scheduledToken != nil,
            ticksSinceLastCommit: ticksSinceLastCommit,
            maximumCumulativeUnpublishedPositionDelta:
                maximumCumulativeUnpublishedPositionDelta,
            stableQuietSamples:
                stabilityPolicy.stableQuietSamples
        )
    }

    var internalPositions: [NodeKey: CGPoint] {
        workspace.positions
    }

    var internalVelocities: [NodeKey: CGVector] {
        workspace.velocities
    }

    var workspaceCapacitySnapshot:
        GraphPhysicsWorkspaceCapacitySnapshot {
        workspace.capacitySnapshot
    }

    private func handleScheduledTick(
        token: GraphPhysicsSchedulingToken
    ) {
        guard token == scheduledToken,
              token.lifecycleGeneration
                == lifecycleGeneration else {
            return
        }

        timer?.invalidate()
        timer = nil
        scheduledToken = nil

        guard isRunning,
              simulationAllowed,
              let input = currentInput else {
            return
        }

        if let externalStateProvider {
            let externalState = externalStateProvider()
            if resynchronizeIfExternalStateChanged(
                externalState
            ) {
                publish(forcedReason: .externalInputChange)
                cadencePolicy.resetToActive()
                stabilityPolicy.reset()
            }
        }

        guard simulationAllowed else {
            stop()
            return
        }

        let phaseForTick = cadencePolicy.phase
        let tickDuration = BMDuration()

        if workspaceTicksSinceFullReset > 0 {
            metrics.workspaceReuseCount += 1
        }
        workspaceTicksSinceFullReset += 1

        let result = GraphPhysicsEngine.step(
            input: input.workspaceStepInput,
            workspace: &workspace
        )
        let tickNanos = tickDuration.nanosecondsElapsed
        metrics.engineTickCount += 1
        metrics.lastStepMetrics = result.metrics
        recordCadenceTick(phaseForTick)

        _ = cadencePolicy.observe(
            maxSimSpeed: result.maxSimSpeed,
            isDragging: input.isDragging,
            configuration: adaptiveConfiguration
        )

        ticksSinceLastCommit += 1
        let currentPositionDelta =
            maximumPositionDeltaFromPublishedState()
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
            publish(forcedReason: nil)
        } else {
            metrics.skippedCommitCount += 1
            rollingSkippedCommitCount += 1
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

        if shouldSleep {
            publish(forcedReason: .sleep)
            metrics.sleepCount += 1
            metrics.lastSleepEngineTick =
                metrics.engineTickCount
            isSleeping = true
            isRunning = false
            invalidateScheduledTick()
            return
        }

        if isRunning {
            scheduleNextTick()
        }
    }

    @discardableResult
    private func resynchronizeIfExternalStateChanged(
        _ externalState: GraphPhysicsExternalState
    ) -> Bool {
        guard workspace.hasSynchronizedState else {
            workspace.fullReset(
                positions: externalState.positions,
                velocities: externalState.velocities
            )
            metrics.workspaceFullResetCount += 1
            workspaceTicksSinceFullReset = 0
            lastPublishedState = externalState
            return true
        }

        guard externalState != lastPublishedState else {
            return false
        }

        workspace.fullReset(
            positions: externalState.positions,
            velocities: externalState.velocities
        )
        metrics.workspaceFullResetCount += 1
        metrics.externalResynchronizationCount += 1
        workspaceTicksSinceFullReset = 0
        lastPublishedState = externalState
        ticksSinceLastCommit = 0
        maximumCumulativeUnpublishedPositionDelta = 0
        cadencePolicy.resetToActive()
        stabilityPolicy.reset()
        isSleeping = false
        return true
    }

    private func publish(
        forcedReason: GraphPhysicsForcedCommitReason?
    ) {
        guard workspace.hasSynchronizedState,
              let commitHandler else {
            return
        }

        var publishedPositions: [NodeKey: CGPoint] = [:]
        publishedPositions.reserveCapacity(
            workspace.positions.count
        )
        for (key, position) in workspace.positions {
            publishedPositions[key] = position
        }

        var publishedVelocities: [NodeKey: CGVector] = [:]
        publishedVelocities.reserveCapacity(
            workspace.velocities.count
        )
        for (key, velocity) in workspace.velocities {
            publishedVelocities[key] = velocity
        }

        let publishedState = GraphPhysicsExternalState(
            positions: publishedPositions,
            velocities: publishedVelocities
        )
        lastPublishedState = publishedState
        ticksSinceLastCommit = 0
        maximumCumulativeUnpublishedPositionDelta = 0
        metrics.positionCommitCount += 1
        metrics.velocityCommitCount += 1
        rollingPositionCommitCount += 1
        if forcedReason != nil {
            metrics.forcedCommitCount += 1
        }
        commitHandler(publishedState)
    }

    private func maximumPositionDeltaFromPublishedState()
        -> CGFloat {
        guard let lastPublishedState else {
            return .greatestFiniteMagnitude
        }
        guard workspace.positions.count
            == lastPublishedState.positions.count else {
            return .greatestFiniteMagnitude
        }

        var maximumDelta: CGFloat = 0
        for (key, position) in workspace.positions {
            guard let publishedPosition =
                    lastPublishedState.positions[key] else {
                return .greatestFiniteMagnitude
            }
            let dx = position.x - publishedPosition.x
            let dy = position.y - publishedPosition.y
            let delta = sqrt(dx * dx + dy * dy)
            if delta > maximumDelta {
                maximumDelta = delta
            }
        }
        return maximumDelta
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
            Double(rollingMaximumTickNanos)
            / 1_000_000.0
        let cadence = cadencePolicy.phase.rawValue
        let averageTicksPerCommit =
            metrics.averageTicksPerUICommit

        BMLog.physics.debug(
            "physics_runtime avgMs=\(averageMilliseconds, format: .fixed(precision: 2)) maxMs=\(maximumMilliseconds, format: .fixed(precision: 2)) cadence=\(cadence, privacy: .public) ticks=\(self.rollingTickCount, privacy: .public) commits=\(self.rollingPositionCommitCount, privacy: .public) skipped=\(self.rollingSkippedCommitCount, privacy: .public) avgTicksPerCommit=\(averageTicksPerCommit, format: .fixed(precision: 2)) strategy=\(stepMetrics.interactionStrategy.rawValue, privacy: .public) simNodes=\(stepMetrics.simulatedNodeCount, privacy: .public) exactPairs=\(stepMetrics.exactCheckedNodePairCount, privacy: .public) gridCells=\(stepMetrics.occupiedGridCellCount, privacy: .public) distantCellPairs=\(stepMetrics.approximatedDistantCellPairCount, privacy: .public) workspaceResets=\(self.metrics.workspaceFullResetCount, privacy: .public) workspaceReuse=\(self.metrics.workspaceReuseCount, privacy: .public)"
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
            scheduledToken == nil ? 0 : 1
        )

        guard automaticallySchedules else { return }

        timer = Timer.scheduledTimer(
            withTimeInterval: cadencePolicy.phase.interval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScheduledTick(token: token)
            }
        }
    }

    private func invalidateScheduledTick() {
        timer?.invalidate()
        timer = nil
        scheduledToken = nil
        lifecycleGeneration &+= 1
    }
}
