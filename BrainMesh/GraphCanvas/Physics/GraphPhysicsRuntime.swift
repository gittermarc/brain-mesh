//
//  GraphPhysicsRuntime.swift
//  BrainMesh
//

import CoreGraphics
import Foundation

/// Thin Main-Actor bridge between SwiftUI and the simulation actor.
///
/// This type owns no physics, velocities, forces, grid state, cadence timer,
/// or stability calculation. It coalesces UI commands and accepts immutable
/// position snapshots only when their graph and command revision are current.
@MainActor
final class GraphPhysicsRuntime {
    typealias CommitHandler =
        @MainActor ([NodeKey: CGPoint]) -> Void

    private let adaptiveConfiguration:
        GraphPhysicsAdaptiveConfiguration
    private let automaticallySchedules: Bool
    private let clock: any GraphPhysicsRuntimeClock

    private var simulationActorStorage:
        GraphPhysicsSimulationActor?
    private var commandDrainTask: Task<Void, Never>?
    private var pendingCommand: GraphPhysicsSimulationCommand?
    private var memoryPressurePending = false

    private var currentInput: GraphPhysicsRuntimeInput?
    private var currentIdentity: GraphPhysicsRuntimeIdentity?
    private var currentExternalPositions: [NodeKey: CGPoint] = [:]
    private var currentSimulationAllowed = false
    private var commitHandler: CommitHandler?
    private var commandRevision: UInt64 = 0
    private var lastCommittedPositions: [NodeKey: CGPoint]?

    init(
        adaptiveConfiguration:
            GraphPhysicsAdaptiveConfiguration = .production,
        automaticallySchedules: Bool = true,
        clock: any GraphPhysicsRuntimeClock =
            ContinuousGraphPhysicsRuntimeClock()
    ) {
        self.adaptiveConfiguration = adaptiveConfiguration
        self.automaticallySchedules = automaticallySchedules
        self.clock = clock
    }

    deinit {
        commandDrainTask?.cancel()
    }

    func update(
        input: GraphPhysicsRuntimeInput,
        externalPositions: [NodeKey: CGPoint],
        simulationAllowed: Bool,
        reason: GraphPhysicsRuntimeWakeReason,
        initialVelocities: [NodeKey: CGVector] = [:],
        commit: @escaping CommitHandler
    ) {
        commitHandler = commit

        // A SwiftUI write caused by our own accepted snapshot is not a new
        // simulation command. Suppressing it prevents a publication loop and
        // avoids resetting unpublished actor state.
        if reason == .externalState,
           externalPositions == lastCommittedPositions,
           input == currentInput,
           simulationAllowed == currentSimulationAllowed {
            return
        }

        let identity = resolvedIdentity(for: input)
        currentInput = input
        currentIdentity = identity
        currentExternalPositions = externalPositions
        currentSimulationAllowed = simulationAllowed
        commandRevision &+= 1

        pendingCommand = GraphPhysicsSimulationCommand(
            input: input,
            identity: identity,
            externalPositions: externalPositions,
            initialVelocities: initialVelocities,
            simulationAllowed: simulationAllowed,
            reason: reason,
            commandRevision: commandRevision
        )
        beginCommandDrainIfNeeded()
    }

    func stop() {
        guard let currentInput else { return }
        update(
            input: currentInput,
            externalPositions: currentExternalPositions,
            simulationAllowed: false,
            reason: .simulationAllowed,
            commit: commitHandler ?? { _ in }
        )
    }

    func handleMemoryPressure() {
        memoryPressurePending = true
        beginCommandDrainIfNeeded()
    }

    func flushForTesting() async {
        while let commandDrainTask {
            await commandDrainTask.value
        }
    }

    func runNextScheduledTickForTesting() async {
        await flushForTesting()
        await simulationActor.runNextScheduledTickForTesting()
    }

    func fireScheduledCallbackForTesting(
        _ token: GraphPhysicsSchedulingToken
    ) async {
        await flushForTesting()
        await simulationActor.fireScheduledCallbackForTesting(token)
    }

    func scheduledTokenForTesting()
        async -> GraphPhysicsSchedulingToken? {
        await flushForTesting()
        return await simulationActor.schedulingTokenForTesting()
    }

    func debugSnapshotForTesting()
        async -> GraphPhysicsSimulationDebugSnapshot {
        await flushForTesting()
        return await simulationActor.debugSnapshot()
    }

    func acceptSnapshotForTesting(
        _ snapshot: GraphPhysicsPositionSnapshot
    ) async {
        if !accept(snapshot) {
            await simulationActor.recordDroppedSnapshot()
        }
    }

    private var simulationActor: GraphPhysicsSimulationActor {
        if let simulationActorStorage {
            return simulationActorStorage
        }

        let actor = GraphPhysicsSimulationActor(
            adaptiveConfiguration: adaptiveConfiguration,
            automaticallySchedules: automaticallySchedules,
            clock: clock,
            snapshotSink: { [weak self] snapshot in
                self?.accept(snapshot) ?? false
            }
        )
        simulationActorStorage = actor
        return actor
    }

    private func beginCommandDrainIfNeeded() {
        guard commandDrainTask == nil else { return }
        _ = simulationActor
        commandDrainTask = Task { @MainActor [weak self] in
            await self?.drainPendingCommands()
        }
    }

    private func drainPendingCommands() async {
        while !Task.isCancelled {
            if let command = pendingCommand {
                pendingCommand = nil
                await simulationActor.update(command)
                continue
            }

            if memoryPressurePending {
                memoryPressurePending = false
                await simulationActor.handleMemoryPressure()
                continue
            }

            break
        }

        commandDrainTask = nil
        if pendingCommand != nil
            || memoryPressurePending {
            beginCommandDrainIfNeeded()
        }
    }

    private func accept(
        _ snapshot: GraphPhysicsPositionSnapshot
    ) -> Bool {
        guard let currentInput,
              let currentIdentity,
              snapshot.identity == currentIdentity,
              snapshot.graphID == currentInput.graphID,
              snapshot.commandRevision == commandRevision else {
            return false
        }

        let positions = snapshot.positionsByNodeKey
        guard positions != lastCommittedPositions else {
            return true
        }
        lastCommittedPositions = positions
        currentExternalPositions = positions
        commitHandler?(positions)
        return true
    }

    private func resolvedIdentity(
        for input: GraphPhysicsRuntimeInput
    ) -> GraphPhysicsRuntimeIdentity {
        guard let currentIdentity,
              currentIdentity.graphID == input.graphID,
              currentIdentity.orderedNodeKeys.count
                == input.nodes.count else {
            return input.identity
        }

        for (index, node) in input.nodes.enumerated()
        where currentIdentity.orderedNodeKeys[index] != node.key {
            return input.identity
        }
        return currentIdentity
    }
}
