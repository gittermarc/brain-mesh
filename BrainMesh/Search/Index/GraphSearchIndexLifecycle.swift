//
//  GraphSearchIndexLifecycle.swift
//  BrainMesh
//
//  Persistent graph-scoped readiness, revision and generation values.
//

import Foundation

nonisolated enum GraphSearchIndexLifecycleState: String, Codable, Sendable {
    case ready
    case invalidated
    case rebuilding
}

/// Constant-size persisted state used to decide whether the active index can be
/// searched without materializing graph sources.
nonisolated struct GraphSearchIndexReadinessToken: Equatable, Sendable {
    let graphID: UUID
    let sourceRevision: UUID
    let indexedSourceRevision: UUID
    let indexRevision: UUID
    let indexFormatVersion: Int
    let sourceManifestFormatVersion: Int
    let sourceManifestHash: String
    let activeGeneration: UUID
    let stagingGeneration: UUID?
    let lifecycleState: GraphSearchIndexLifecycleState
    let invalidationReason: GraphSearchIndexReconciliationReason?
    let documentCount: Int

    var isReady: Bool {
        sourceRevision == indexedSourceRevision
            && indexFormatVersion == GraphSearchIndexSchema.currentVersion
            && sourceManifestFormatVersion
                == GraphSearchSourceManifestSchema.currentVersion
            && sourceManifestHash.isEmpty == false
            && stagingGeneration == nil
            && lifecycleState == .ready
            && invalidationReason == nil
            && documentCount >= 0
    }
}

nonisolated struct GraphSearchStoredIndexLifecycle: Equatable, Sendable {
    let graphID: UUID
    let indexedSourceRevision: UUID?
    let indexRevision: UUID?
    let indexFormatVersion: Int
    let sourceManifestFormatVersion: Int
    let sourceManifestHash: String?
    let activeGeneration: UUID?
    let stagingGeneration: UUID?
    let lifecycleState: GraphSearchIndexLifecycleState
    let invalidationReason: GraphSearchIndexReconciliationReason?
    let documentCount: Int?

    var hasUsableActiveGeneration: Bool {
        activeGeneration != nil && documentCount != nil
    }
}

nonisolated struct GraphSearchIndexStagingGeneration: Equatable, Sendable {
    let graphID: UUID
    let generationID: UUID
    let sourceRevision: UUID
    let expectedActiveGeneration: UUID?
    let expectedIndexRevision: UUID?
}
