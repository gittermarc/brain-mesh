//
//  GraphChatInterpretationCorrectionEditorSession.swift
//  BrainMesh
//
//  Main-actor presentation state for one bound correction sheet.
//

import Foundation

nonisolated struct GraphChatInterpretationCorrectionEditorSession:
    Hashable,
    Sendable,
    Identifiable
{
    let id: UUID
    let assistantMessageID: UUID
    let branchPlan:
        GraphChatInterpretationCorrectionBranchPlan
    let snapshot:
        GraphChatInterpretationCorrectionSchemaSnapshot
    let capabilities:
        GraphChatInterpretationCorrectionCapabilities
    let presentation:
        GraphChatInterpretationCorrectionEditorPresentation
    var selection:
        GraphChatInterpretationCorrectionSelection
    var validationState:
        GraphChatInterpretationCorrectionValidationState
    var isApplying: Bool

    init(
        id: UUID = UUID(),
        assistantMessageID: UUID,
        branchPlan:
            GraphChatInterpretationCorrectionBranchPlan,
        snapshot:
            GraphChatInterpretationCorrectionSchemaSnapshot,
        capabilities:
            GraphChatInterpretationCorrectionCapabilities,
        presentation:
            GraphChatInterpretationCorrectionEditorPresentation,
        selection:
            GraphChatInterpretationCorrectionSelection,
        validationState:
            GraphChatInterpretationCorrectionValidationState,
        isApplying: Bool = false
    ) {
        self.id = id
        self.assistantMessageID = assistantMessageID
        self.branchPlan = branchPlan
        self.snapshot = snapshot
        self.capabilities = capabilities
        self.presentation = presentation
        self.selection = selection
        self.validationState = validationState
        self.isApplying = isApplying
    }
}
