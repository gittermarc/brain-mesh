//
//  GraphCanvasDerivedStateScheduler.swift
//  BrainMesh
//

import Foundation
import os

enum GraphCanvasDerivedStateTriggerReason:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case initial
    case graphLoad
    case selectionOrLens
    case detailsFocus
    case detailsExpansion

    static func classify(
        previous: GraphCanvasDerivedStateInputSnapshot,
        current: GraphCanvasDerivedStateInputSnapshot
    ) -> GraphCanvasDerivedStateTriggerReason {
        if previous.edges != current.edges ||
            previous.labelLookup != current.labelLookup {
            return .graphLoad
        }

        if previous.detailsFocusState != current.detailsFocusState {
            return .detailsFocus
        }

        if previous.detailsFocusPreparedState != current.detailsFocusPreparedState {
            return .detailsExpansion
        }

        return .selectionOrLens
    }
}

struct GraphCanvasDerivedStateSchedulerMetrics: Equatable, Sendable {
    fileprivate(set) var schedulingRequestCount = 0
    fileprivate(set) var builderExecutionCount = 0
    fileprivate(set) var coalescedRequestCount = 0
    fileprivate(set) var identicalInputDropCount = 0
    fileprivate(set) var staleResultDropCount = 0
    fileprivate(set) var cancellationCount = 0
    fileprivate(set) var commitCount = 0
    fileprivate(set) var totalBuildDurationMilliseconds = 0.0
    fileprivate(set) var lastBuildDurationMilliseconds = 0.0
    fileprivate(set) var requestCountByReason: [GraphCanvasDerivedStateTriggerReason: Int] = [:]
    fileprivate(set) var buildCountByReason: [GraphCanvasDerivedStateTriggerReason: Int] = [:]
}

/// Main-actor coordinator for the Canvas derived-state calculation.
///
/// Its scope is intentionally narrow: it coalesces value-only inputs, executes
/// the existing builder, rejects stale results, and hands a finished value to
/// the caller's existing diff-based commit path.
@MainActor
final class GraphCanvasDerivedStateScheduler {
    typealias BuildOperation = @MainActor (
        GraphCanvasDerivedStateInputSnapshot
    ) async -> GraphCanvasDerivedStateSnapshot

    typealias CommitOperation = @MainActor (
        GraphCanvasDerivedStateSnapshot
    ) -> Void

    private enum WorkPhase {
        case coalescing
        case building
    }

    private let coalescingYieldCount: Int
    private let buildOperation: BuildOperation

    private var scheduledTask: Task<Void, Never>?
    private var workPhase: WorkPhase?
    private var generation: UInt64 = 0
    private var hasGraphIdentity = false
    private var graphID: UUID?
    private var latestInput: GraphCanvasDerivedStateInputSnapshot?
    private var isGraphTransitionSuspended = false

    private(set) var metrics = GraphCanvasDerivedStateSchedulerMetrics()

    init(
        coalescingYieldCount: Int = 2,
        buildOperation: @escaping BuildOperation = { input in
            input.buildDerivedState()
        }
    ) {
        self.coalescingYieldCount = max(1, coalescingYieldCount)
        self.buildOperation = buildOperation
    }

    func schedule(
        input: GraphCanvasDerivedStateInputSnapshot,
        graphID: UUID?,
        reason: GraphCanvasDerivedStateTriggerReason,
        commit: @escaping CommitOperation
    ) {
        metrics.schedulingRequestCount += 1
        metrics.requestCountByReason[reason, default: 0] += 1

        activateGraphIfNeeded(graphID)

        guard !isGraphTransitionSuspended else {
            metrics.coalescedRequestCount += 1
            return
        }

        guard latestInput != input else {
            metrics.identicalInputDropCount += 1
            return
        }

        if workPhase == .coalescing {
            metrics.coalescedRequestCount += 1
        }

        scheduledTask?.cancel()
        generation &+= 1

        let scheduledGeneration = generation
        let scheduledGraphID = self.graphID
        latestInput = input
        workPhase = .coalescing

        scheduledTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for _ in 0..<self.coalescingYieldCount {
                await Task.yield()
                guard !Task.isCancelled else { return }
            }

            await self.execute(
                input: input,
                graphID: scheduledGraphID,
                generation: scheduledGeneration,
                reason: reason,
                commit: commit
            )
        }
    }

    /// Cancels work from the previous graph and suppresses intermediate state
    /// emitted while the new graph snapshot is being committed.
    func beginGraphTransition(to graphID: UUID?) {
        invalidatePendingWork(resetLatestInput: true)
        self.graphID = graphID
        hasGraphIdentity = true
        isGraphTransitionSuspended = true
    }

    /// Re-enables scheduling with the final, fully committed graph-load input.
    func resumeAfterGraphTransition(
        input: GraphCanvasDerivedStateInputSnapshot,
        graphID: UUID?,
        reason: GraphCanvasDerivedStateTriggerReason = .graphLoad,
        commit: @escaping CommitOperation
    ) {
        guard isGraphTransitionSuspended else {
            return
        }

        if !hasGraphIdentity || self.graphID != graphID {
            invalidatePendingWork(resetLatestInput: true)
            self.graphID = graphID
            hasGraphIdentity = true
        }
        isGraphTransitionSuspended = false
        schedule(
            input: input,
            graphID: graphID,
            reason: reason,
            commit: commit
        )
    }

    /// Used when the Canvas leaves the hierarchy. A later appearance must rebuild
    /// even if its first visible input equals the previously committed input.
    func cancel() {
        invalidatePendingWork(resetLatestInput: true)
        isGraphTransitionSuspended = false
    }

    /// Test seam for awaiting the newest scheduled operation. Superseded,
    /// deliberately blocked operations are guarded by generation and graph scope.
    func waitForCurrentWork() async {
        while let task = scheduledTask {
            await task.value
            await Task.yield()
        }
    }

    private func activateGraphIfNeeded(_ newGraphID: UUID?) {
        guard !hasGraphIdentity || graphID != newGraphID else { return }
        invalidatePendingWork(resetLatestInput: true)
        graphID = newGraphID
        hasGraphIdentity = true
        isGraphTransitionSuspended = false
    }

    private func invalidatePendingWork(resetLatestInput: Bool) {
        if scheduledTask != nil {
            metrics.cancellationCount += 1
        }
        scheduledTask?.cancel()
        scheduledTask = nil
        workPhase = nil
        generation &+= 1
        if resetLatestInput {
            latestInput = nil
        }
    }

    private func execute(
        input: GraphCanvasDerivedStateInputSnapshot,
        graphID scheduledGraphID: UUID?,
        generation scheduledGeneration: UInt64,
        reason: GraphCanvasDerivedStateTriggerReason,
        commit: @escaping CommitOperation
    ) async {
        guard scheduledGeneration == generation,
              scheduledGraphID == graphID,
              !Task.isCancelled else {
            return
        }

        workPhase = .building
        metrics.builderExecutionCount += 1
        metrics.buildCountByReason[reason, default: 0] += 1

        let duration = BMDuration()
        let derivedState = await buildOperation(input)
        let durationMilliseconds = duration.millisecondsElapsed

        metrics.lastBuildDurationMilliseconds = durationMilliseconds
        metrics.totalBuildDurationMilliseconds += durationMilliseconds

        guard scheduledGeneration == generation,
              scheduledGraphID == graphID,
              latestInput == input,
              !Task.isCancelled else {
            metrics.staleResultDropCount += 1
            return
        }

        commit(derivedState)
        metrics.commitCount += 1

        #if DEBUG
        let requestCount = metrics.schedulingRequestCount
        let buildCount = metrics.builderExecutionCount
        let coalescedCount = metrics.coalescedRequestCount
        BMLog.canvasDerivedState.debug(
            "canvas_derived_state reason=\(reason.rawValue, privacy: .public) requests=\(requestCount, privacy: .public) builds=\(buildCount, privacy: .public) coalesced=\(coalescedCount, privacy: .public) duration_ms=\(durationMilliseconds, privacy: .public)"
        )
        #endif

        if scheduledGeneration == generation {
            scheduledTask = nil
            workPhase = nil
        }
    }
}
