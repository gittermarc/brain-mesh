//
//  GraphCanvasView+Physics.swift
//  BrainMesh
//
//  P0.1: Split GraphCanvasView.swift -> Simulation / Physics
//

import SwiftUI
import os

enum GraphCanvasPhysicsFixedNodeResolver {
    static func resolve(
        pinned: Set<NodeKey>,
        draggingKey: NodeKey?,
        workMode: WorkMode
    ) -> Set<NodeKey> {
        var fixedNodeKeys = pinned
        let modePolicy = GraphCanvasModePolicy.policy(for: workMode)
        if modePolicy.allowsNodeDragging, let draggingKey {
            fixedNodeKeys.insert(draggingKey)
        }
        return fixedNodeKeys
    }
}

extension GraphCanvasView {
    func updateSimulationState() {
        // Centralized gate: canvas must be visible + app active.
        if simulationAllowed {
            // If we were sleeping we want to start again, otherwise keep running.
            wakeSimulationIfNeeded()
        } else {
            stopSimulation()
        }
    }

    func startSimulation() {
        guard simulationAllowed else {
            stopSimulation()
            return
        }
        stopSimulation()
        // Reset idle state when (re)starting.
        physicsIdleTicks = 0
        physicsIsSleeping = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            // If visibility / scene state changed since starting, stop immediately.
            guard simulationAllowed else {
                stopSimulation()
                return
            }
            stepSimulation()
        }
    }

    func stopSimulation() {
        timer?.invalidate()
        timer = nil
    }

    func wakeSimulationIfNeeded() {
        guard simulationAllowed else {
            stopSimulation()
            return
        }
        // If we were sleeping (timer stopped), restart. If we're running, just clear idle state.
        physicsIdleTicks = 0
        physicsIsSleeping = false
        guard timer == nil else { return }
        startSimulation()
    }

    func stepSimulation() {
        guard simulationAllowed else {
            stopSimulation()
            return
        }
        guard nodes.count >= 2 else { return }

        let tickTimer = BMDuration()
        let relevant = physicsRelevant
        let fixedNodeKeys = GraphCanvasPhysicsFixedNodeResolver.resolve(
            pinned: pinned,
            draggingKey: draggingKey,
            workMode: workMode
        )

        let input = GraphPhysicsStepInput(
            nodes: nodes,
            edges: physicsEdges,
            positions: positions,
            velocities: velocities,
            fixedNodeKeys: fixedNodeKeys,
            physicsRelevant: relevant,
            configuration: GraphPhysicsConfiguration(
                collisionStrength: collisionStrength
            )
        )
        let result = GraphPhysicsEngine.step(input: input)

        positions = result.positions
        velocities = result.velocities

        // MARK: - Idle / Sleep (P0.1 optional)
        // Pause the 30 FPS timer once the layout has settled.
        // We intentionally keep thresholds conservative to avoid stopping too early.
        if draggingKey == nil {
            let idleSpeedThreshold: CGFloat = 0.03
            let idleTicksNeeded: Int = 90  // ~3 seconds at 30 FPS

            if result.maxSimSpeed < idleSpeedThreshold {
                physicsIdleTicks += 1
                if physicsIdleTicks >= idleTicksNeeded {
                    physicsIdleTicks = 0
                    physicsIsSleeping = true
                    DispatchQueue.main.async {
                        // If something woke us up between scheduling and execution, don't stop.
                        if physicsIsSleeping {
                            stopSimulation()
                        }
                    }
                }
            } else {
                physicsIdleTicks = 0
                physicsIsSleeping = false
            }
        } else {
            physicsIdleTicks = 0
            physicsIsSleeping = false
        }

        // MARK: - Observability (P0.2)
        // Log a rolling window to avoid log spam and keep overhead minimal.
        let tickNs = tickTimer.nanosecondsElapsed
        physicsTickCounter += 1
        physicsTickAccumNanos &+= tickNs
        if tickNs > physicsTickMaxNanos { physicsTickMaxNanos = tickNs }

        if physicsTickCounter >= 60 {
            let avgMs = Double(physicsTickAccumNanos) / Double(physicsTickCounter) / 1_000_000.0
            let maxMs = Double(physicsTickMaxNanos) / 1_000_000.0
            let simCount = result.metrics.simulatedNodeCount
            let relCount = relevant?.count ?? 0
            let strategy = result.metrics.interactionStrategy.rawValue
            let theoreticalPairs =
                result.metrics.theoreticalExactPairCount
            let exactPairs = result.metrics.exactCheckedNodePairCount
            let gridCells = result.metrics.occupiedGridCellCount
            let neighboringCellPairs =
                result.metrics.neighboringCellPairCount
            let distantCellPairs =
                result.metrics.approximatedDistantCellPairCount
            let springCount = result.metrics.springCount

            BMLog.physics.debug(
                "physics avgMs=\(avgMs, format: .fixed(precision: 2)) maxMs=\(maxMs, format: .fixed(precision: 2)) strategy=\(strategy, privacy: .public) nodes=\(nodes.count, privacy: .public) simNodes=\(simCount, privacy: .public) relevant=\(relCount, privacy: .public) edges=\(physicsEdges.count, privacy: .public) theoreticalPairs=\(theoreticalPairs, privacy: .public) exactPairs=\(exactPairs, privacy: .public) gridCells=\(gridCells, privacy: .public) neighboringCellPairs=\(neighboringCellPairs, privacy: .public) distantCellPairs=\(distantCellPairs, privacy: .public) springs=\(springCount, privacy: .public)"
            )

            physicsTickCounter = 0
            physicsTickAccumNanos = 0
            physicsTickMaxNanos = 0
        }
    }
}
