//
//  GraphCanvasScreen+Layout.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {

    func seedLayout(preservePinned: Bool) {
        let oldPos = positions

        positions.removeAll(keepingCapacity: true)
        velocities.removeAll(keepingCapacity: true)
        guard !nodes.isEmpty else { return }

        if preservePinned {
            for k in pinned {
                if let p = oldPos[k] {
                    positions[k] = p
                    velocities[k] = .zero
                }
            }
        }

        let entityNodes = nodes.filter { $0.key.kind == .entity }
        let attrNodes = nodes.filter { $0.key.kind == .attribute }

        let radius: CGFloat = 220
        for (i, n) in entityNodes.enumerated() {
            if pinned.contains(n.key), positions[n.key] != nil { continue }
            let angle = (CGFloat(i) / CGFloat(max(1, entityNodes.count))) * (.pi * 2)
            let p = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            positions[n.key] = p
            velocities[n.key] = .zero
        }

        let containment = edges.filter { $0.type == .containment }
        var owner: [NodeKey: [NodeKey]] = [:]
        for e in containment {
            if e.a.kind == .entity && e.b.kind == .attribute {
                owner[e.a, default: []].append(e.b)
            } else if e.b.kind == .entity && e.a.kind == .attribute {
                owner[e.b, default: []].append(e.a)
            }
        }

        for a in attrNodes {
            if pinned.contains(a.key), positions[a.key] != nil { continue }
            positions[a.key] = positions[a.key] ?? CGPoint(x: 0, y: 0)
            velocities[a.key] = .zero
        }

        let satRadius: CGFloat = 70
        for (ek, attrs) in owner {
            guard let ep = positions[ek] else { continue }
            for (i, ak) in attrs.enumerated() {
                if pinned.contains(ak), positions[ak] != nil { continue }
                let angle = (CGFloat(i) / CGFloat(max(1, attrs.count))) * (.pi * 2)
                let p = CGPoint(x: ep.x + cos(angle) * satRadius, y: ep.y + sin(angle) * satRadius)
                positions[ak] = p
                velocities[ak] = .zero
            }
        }
    }

}
