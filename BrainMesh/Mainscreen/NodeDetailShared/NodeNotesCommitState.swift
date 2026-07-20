//
//  NodeNotesCommitState.swift
//  BrainMesh
//
//  Value-only draft state for explicit notes commits.
//

import Foundation

/// Keeps editor keystrokes separate from persistence and exposes one final commit candidate.
nonisolated struct NodeNotesCommitState: Equatable, Sendable {
    private(set) var committedNotes: String
    private(set) var draftNotes: String

    init(initialNotes: String) {
        committedNotes = initialNotes
        draftNotes = initialNotes
    }

    var hasPendingChanges: Bool {
        draftNotes != committedNotes
    }

    var commitCandidate: String? {
        hasPendingChanges ? draftNotes : nil
    }

    mutating func updateDraft(_ value: String) {
        draftNotes = value
    }

    mutating func markCommitted(_ value: String) {
        committedNotes = value
    }
}
