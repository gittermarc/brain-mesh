//
//  GraphCanvasView+Physics.swift
//  BrainMesh
//
//  GraphCanvasView remains the SwiftUI integration adapter. Force
//  calculation, adaptive cadence, commit decisions, sleep, and workspace
//  ownership live behind GraphPhysicsRuntime.
//

import SwiftUI

enum GraphCanvasPhysicsFixedNodeResolver {
    static func resolve(
        pinned: Set<NodeKey>,
        draggingKey: NodeKey?,
        workMode: WorkMode
    ) -> Set<NodeKey> {
        var fixedNodeKeys = pinned
        let modePolicy = GraphCanvasModePolicy.policy(
            for: workMode
        )
        if modePolicy.allowsNodeDragging, let draggingKey {
            fixedNodeKeys.insert(draggingKey)
        }
        return fixedNodeKeys
    }
}

extension GraphCanvasView {
    func updateSimulationState() {
        configurePhysicsRuntime(
            reason: .simulationAllowed
        )
    }

    func startSimulation() {
        configurePhysicsRuntime(reason: .initial)
    }

    func stopSimulation() {
        physicsRuntime.stop()
    }

    func wakeSimulationIfNeeded(
        reason: GraphPhysicsRuntimeWakeReason = .selection
    ) {
        configurePhysicsRuntime(reason: reason)
    }

    func externalPhysicsStateDidChange() {
        configurePhysicsRuntime(reason: .externalState)
    }

    private func configurePhysicsRuntime(
        reason: GraphPhysicsRuntimeWakeReason
    ) {
        let positionsBinding = $positions
        let velocitiesBinding = $velocities
        let externalStateProvider:
            @MainActor () -> GraphPhysicsExternalState = {
                GraphPhysicsExternalState(
                    positions: positionsBinding.wrappedValue,
                    velocities: velocitiesBinding.wrappedValue
                )
            }

        let fixedNodeKeys =
            GraphCanvasPhysicsFixedNodeResolver.resolve(
                pinned: pinned,
                draggingKey: draggingKey,
                workMode: workMode
            )
        let input = GraphPhysicsRuntimeInput(
            graphID: graphID,
            nodes: nodes,
            edges: physicsEdges,
            fixedNodeKeys: fixedNodeKeys,
            physicsRelevant: physicsRelevant,
            configuration: GraphPhysicsConfiguration(
                collisionStrength: collisionStrength
            ),
            workMode: workMode,
            selection: selection,
            isDragging: draggingKey != nil
        )

        physicsRuntime.update(
            input: input,
            externalState: externalStateProvider(),
            simulationAllowed: simulationAllowed,
            reason: reason,
            externalStateProvider: externalStateProvider,
            commit: { state in
                // One runtime decision publishes both dictionaries in the
                // same Main-Actor transaction. Velocities never publish on
                // their own.
                positionsBinding.wrappedValue = state.positions
                velocitiesBinding.wrappedValue = state.velocities
            }
        )
    }
}
