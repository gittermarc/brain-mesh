//
//  AnyModelContainer.swift
//  BrainMesh
//
//  Wrapper to pass SwiftData's `ModelContainer` across concurrency boundaries.
//  Keep usage constrained to read-only fetches / extraction in background contexts.
//

import SwiftData

/// Wrapper to pass SwiftData's `ModelContainer` across concurrency boundaries.
///
/// This is intentionally tiny: many actors/loaders store it and create their own
/// short-lived `ModelContext` instances as needed.
struct AnyModelContainer: @unchecked Sendable {
    let container: ModelContainer

    init(_ container: ModelContainer) {
        self.container = container
    }
}
