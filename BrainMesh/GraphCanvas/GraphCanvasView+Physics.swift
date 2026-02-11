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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            stepSimulation()
        }
    }

    func stopSimulation() {
        timer?.invalidate()
        timer = nil
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

        // repulsion + collisions
        for i in 0..<simNodes.count {
            let a = simNodes[i].key
            guard let pa = pos[a], !isFixed(a) else { continue }

            for j in 0..<simNodes.count where j != i {
                let b = simNodes[j].key
                guard let pb = pos[b] else { continue }

                let dx = pa.x - pb.x
                let dy = pa.y - pb.y
                let dist2 = max(dx*dx + dy*dy, 40)
                let dist = sqrt(dist2)

                let f = repulsion / dist2
                addVelocity(a, dx: dx * f * 0.00002, dy: dy * f * 0.00002, vel: &vel)

                let minDist = approxRadius(for: a) + approxRadius(for: b) + collisionPadding
                if dist < minDist {
                    let overlap = (minDist - dist)
                    let nx = (dist > 0.01) ? (dx / dist) : 1
                    let ny = (dist > 0.01) ? (dy / dist) : 0
                    addVelocity(a, dx: nx * overlap * collisionStrength, dy: ny * overlap * collisionStrength, vel: &vel)
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

            var p = pos[id, default: .zero]
            p.x += v.dx
            p.y += v.dy

            pos[id] = p
            vel[id] = v
        }

        positions = pos
        velocities = vel

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
