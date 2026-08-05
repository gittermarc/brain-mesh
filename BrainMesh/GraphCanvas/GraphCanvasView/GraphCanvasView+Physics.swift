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

/// Protects user-owned coordinates while an actor snapshot is crossing the
/// Main-Actor boundary. This closes the small interval before SwiftUI delivers
/// the corresponding `onChange` command revision back to the runtime.
nonisolated enum GraphCanvasPhysicsPositionMergePolicy {
    static func merge(
        actorPositions: [NodeKey: CGPoint],
        currentPositions: [NodeKey: CGPoint],
        protectedNodeKeys: Set<NodeKey>
    ) -> [NodeKey: CGPoint] {
        guard !protectedNodeKeys.isEmpty else {
            return actorPositions
        }

        var merged = actorPositions
        for key in protectedNodeKeys {
            if let currentPosition = currentPositions[key] {
                merged[key] = currentPosition
            }
        }
        return merged
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
        let pinnedBinding = $pinned
        let draggingKeyBinding = $draggingKey

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
            externalPositions: positionsBinding.wrappedValue,
            simulationAllowed: simulationAllowed,
            reason: reason,
            commit: { actorPositions in
                var protectedNodeKeys = pinnedBinding.wrappedValue
                if let draggingKey = draggingKeyBinding.wrappedValue {
                    protectedNodeKeys.insert(draggingKey)
                }
                positionsBinding.wrappedValue =
                    GraphCanvasPhysicsPositionMergePolicy.merge(
                        actorPositions: actorPositions,
                        currentPositions:
                            positionsBinding.wrappedValue,
                        protectedNodeKeys: protectedNodeKeys
                    )
            }
        )
    }
}
