//
//  GraphUnlockSnapshot.swift
//  BrainMesh
//
//  Created by Marc Fechner on 26.02.26.
//

import Foundation

/// Value-only snapshot used by the lock UI.
///
/// This keeps the unlock flow independent from SwiftData models and avoids
/// fetches from within the UI.
struct GraphUnlockSnapshot: Sendable {
    let graphID: UUID
    let password: GraphLockPasswordSnapshot?
}

/// Value-only password data needed for verification.
///
/// NOTE: This is kept in-memory only for the duration of the unlock sheet.
struct GraphLockPasswordSnapshot: Sendable {
    let saltB64: String
    let hashB64: String
    let iterations: Int
}
