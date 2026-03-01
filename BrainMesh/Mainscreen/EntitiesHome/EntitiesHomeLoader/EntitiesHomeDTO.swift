//
//  EntitiesHomeDTO.swift
//  BrainMesh
//
//  Value-only DTOs used by EntitiesHomeLoader.
//

import Foundation

/// Value-only row snapshot for EntitiesHome.
///
/// Important: Do NOT pass SwiftData `@Model` instances across concurrency boundaries.
/// The UI navigates by `id` and resolves the model from its main `ModelContext`.
struct EntitiesHomeRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let iconSymbolName: String?

    let attributeCount: Int
    let linkCount: Int?

    let notesPreview: String?

    /// True when the row was included *only* because a note matched the search term.
    /// Used for subtle UX feedback ("Notiztreffer" pill).
    let isNotesOnlyHit: Bool

    let imagePath: String?
    let hasImageData: Bool
}

/// Snapshot DTO returned to the UI.
/// This is intentionally a value-only container so the UI can commit state in one go.
struct EntitiesHomeSnapshot: @unchecked Sendable {
    let rows: [EntitiesHomeRow]
}
