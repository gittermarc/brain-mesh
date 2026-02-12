//
//  GraphCanvasView+Physics.swift
//  BrainMesh
//
//  P0.1: Split GraphCanvasView.swift -> Simulation / Physics
//

import SwiftUI
import os

extension GraphCanvasView {
    func startSimulation() {
        stopSimulation()
        // Reset idle state when (re)starting.
        physicsIdleTicks = 0
        physicsIsSleeping = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            stepSimulation()
        }
    }

    func stopSimulation() {
        timer?.invalidate()
        timer = nil
    }

    func wakeSimulationIfNeeded() {
        // If we were sleeping (timer stopped), restart. If we're running, just clear idle state.
        physicsIdleTicks = 0
        physicsIsSleeping = false
        guard timer == nil else { return }
        startSimulation()
    }

    private func isFixed(_ key: NodeKey) -> Bool {
        pinned.contains(key) || (workMode == .edit && draggingKey == key)
    }

    private func addVelocity(_ key: NodeKey, dx: CGFloat, dy: CGFloat, vel: inout [NodeKey: CGVector]) {
        guard !isFixed(key) else { return }
        vel[key, default: .zero].dx += dx
        vel[key, default: .zero].dy += dy
    }

    private func approxRadius(for key: NodeKey) -> CGFloat {
        switch key.kind {
        case .entity: return 22
        case .attribute: return 18
        }
    }

    func stepSimulation() {
        guard nodes.count >= 2 else { return }

        let tickTimer = BMDuration()

        let repulsion: CGFloat = 8800
        let springLink: CGFloat = 0.018
        let springContain: CGFloat = 0.040
        let restLink: CGFloat = 130
        let restContain: CGFloat = 76
        let damping: CGFloat = 0.85
        let maxSpeed: CGFloat = 18

        let collisionStrength: CGFloat = max(0, self.collisionStrength)
        let collisionPadding: CGFloat = 6

        var pos = positions
        var vel = velocities

        // ✅ Spotlight Physik: nur relevante Nodes bewegen; Rest “stilllegen”
        let relevant = physicsRelevant
        let simNodes = (relevant == nil) ? nodes : nodes.filter { relevant!.contains($0.key) }

        if let relevant {
            for n in nodes where !relevant.contains(n.key) {
                vel[n.key] = .zero
            }
        }

        // repulsion + collisions (pair loop: i < j)
        // Old: each pair computed twice (i→j and j→i). New: compute once and apply forces symmetrically.
        for i in 0..<simNodes.count {
            let a = simNodes[i].key
            guard let pa = pos[a] else { continue }

            if (i + 1) >= simNodes.count { continue }
            for j in (i + 1)..<simNodes.count {
                let b = simNodes[j].key
                guard let pb = pos[b] else { continue }

                let dx = pa.x - pb.x
                let dy = pa.y - pb.y
                let dist2 = max(dx*dx + dy*dy, 40)
                let dist = sqrt(dist2)

                // Repulsion: equal and opposite forces
                let f = repulsion / dist2
                let rx = dx * f * 0.00002
                let ry = dy * f * 0.00002
                addVelocity(a, dx: rx, dy: ry, vel: &vel)
                addVelocity(b, dx: -rx, dy: -ry, vel: &vel)

                // Collision: push apart when overlapping (also symmetric)
                let minDist = approxRadius(for: a) + approxRadius(for: b) + collisionPadding
                if dist < minDist {
                    let overlap = (minDist - dist)
                    let nx = (dist > 0.01) ? (dx / dist) : 1
                    let ny = (dist > 0.01) ? (dy / dist) : 0
                    let cx = nx * overlap * collisionStrength
                    let cy = ny * overlap * collisionStrength
                    addVelocity(a, dx: cx, dy: cy, vel: &vel)
                    addVelocity(b, dx: -cx, dy: -cy, vel: &vel)
                }
            }
        }

        // springs (Physik nutzt volle Kantenliste, aber Spotlight begrenzt auf relevante Nodes)
        for e in physicsEdges {
            if let relevant {
                if !relevant.contains(e.a) || !relevant.contains(e.b) { continue }
            }
            guard let p1 = pos[e.a], let p2 = pos[e.b] else { continue }

            let dx = p2.x - p1.x
            let dy = p2.y - p1.y
            let dist = max(sqrt(dx*dx + dy*dy), 1)

            let spring = (e.type == .containment) ? springContain : springLink
            let rest = (e.type == .containment) ? restContain : restLink

            let diff = dist - rest
            let fx = (dx / dist) * diff * spring
            let fy = (dy / dist) * diff * spring

            addVelocity(e.a, dx: fx, dy: fy, vel: &vel)
            addVelocity(e.b, dx: -fx, dy: -fy, vel: &vel)
        }

        // integrate
        var maxSimSpeed: CGFloat = 0
        for n in simNodes {
            let id = n.key

            if isFixed(id) {
                vel[id] = .zero
                continue
            }

            var v = vel[id, default: .zero]
            v.dx *= damping
            v.dy *= damping

            let speed = sqrt(v.dx*v.dx + v.dy*v.dy)
            if speed > maxSpeed {
                v.dx = (v.dx / speed) * maxSpeed
                v.dy = (v.dy / speed) * maxSpeed
            }

            let clampedSpeed = sqrt(v.dx*v.dx + v.dy*v.dy)
            if clampedSpeed > maxSimSpeed { maxSimSpeed = clampedSpeed }

            var p = pos[id, default: .zero]
            p.x += v.dx
            p.y += v.dy

            pos[id] = p
            vel[id] = v
        }

        positions = pos
        velocities = vel

        // MARK: - Idle / Sleep (P0.1 optional)
        // Pause the 30 FPS timer once the layout has settled.
        // We intentionally keep thresholds conservative to avoid stopping too early.
        if draggingKey == nil {
            let idleSpeedThreshold: CGFloat = 0.03
            let idleTicksNeeded: Int = 90  // ~3 seconds at 30 FPS

            if maxSimSpeed < idleSpeedThreshold {
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
            let simCount = simNodes.count
            let relCount = relevant?.count ?? 0

            BMLog.physics.debug(
                "physics avgMs=\(avgMs, format: .fixed(precision: 2)) maxMs=\(maxMs, format: .fixed(precision: 2)) nodes=\(nodes.count, privacy: .public) simNodes=\(simCount, privacy: .public) relevant=\(relCount, privacy: .public) edges=\(physicsEdges.count, privacy: .public)"
            )

            physicsTickCounter = 0
            physicsTickAccumNanos = 0
            physicsTickMaxNanos = 0
        }
    }
}
