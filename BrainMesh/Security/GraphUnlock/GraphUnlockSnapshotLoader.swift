//
//  GraphUnlockSnapshotLoader.swift
//  BrainMesh
//
//  Created by Marc Fechner on 26.02.26.
//

import Foundation

/// Builds the value-only snapshot for unlock flows.
enum GraphUnlockSnapshotLoader {

    static func makeSnapshot(for graph: MetaGraph) -> GraphUnlockSnapshot {
        let password: GraphLockPasswordSnapshot?

        if graph.isPasswordConfigured,
           let salt = graph.passwordSaltB64,
           let hash = graph.passwordHashB64 {
            password = GraphLockPasswordSnapshot(
                saltB64: salt,
                hashB64: hash,
                iterations: graph.passwordIterations
            )
        } else {
            password = nil
        }

        return GraphUnlockSnapshot(
            graphID: graph.id,
            password: password
        )
    }
}
