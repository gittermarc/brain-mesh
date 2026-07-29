//
//  GraphChatInterpretationCorrectionEditorPresentation.swift
//  BrainMesh
//
//  Presentation-only constraints for the schema-driven interpretation editor.
//

import Foundation

/// UI-only explanatory and minimum-selection details. Domain validation
/// remains authoritative for every correction.
nonisolated struct GraphChatInterpretationCorrectionEditorPresentation:
    Hashable,
    Sendable
{
    let entitySelectionIsOptional: Bool
    let minimumFieldCount: Int
    let sourceResultDescription: String?

    init(
        entitySelectionIsOptional: Bool = false,
        minimumFieldCount: Int = 0,
        sourceResultDescription: String? = nil
    ) {
        precondition(minimumFieldCount >= 0)
        self.entitySelectionIsOptional =
            entitySelectionIsOptional
        self.minimumFieldCount = minimumFieldCount
        self.sourceResultDescription =
            sourceResultDescription
    }
}
