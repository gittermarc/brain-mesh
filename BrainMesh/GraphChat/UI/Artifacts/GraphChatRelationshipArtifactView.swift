//
//  GraphChatRelationshipArtifactView.swift
//  BrainMesh
//
//  Typed relationship artifact rendered from the shared presentation.
//

import SwiftUI

struct GraphChatRelationshipArtifactView: View {
    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload:
        GraphChatAnswerArtifactRelationshipPayload
    let availableEvidence:
        [GraphEvidenceID: GraphEvidence]
    let language: GraphChatResponseLanguage
    let allowsEvidenceActions: Bool
    let canOpenTarget:
        (GraphChatAnswerArtifactNavigationTarget)
            -> Bool
    let onOpenTarget:
        (GraphChatAnswerArtifactNavigationTarget)
            -> Void
    let onOpenEvidence:
        (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph:
        (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceDrawer:
        (GraphChatEvidenceDrawerPresentation)
            -> Void

    var body: some View {
        let presentation =
            GraphChatRelationshipPresentation(
                payload: payload
            )
        GraphChatResultListArtifactView(
            artifact: artifact,
            resolved: resolved,
            payload:
                GraphChatAnswerArtifactResultListPayload(
                    title:
                        presentation.title,
                    rows: presentation.rows,
                    resultMetadata:
                        payload.resultMetadata,
                    evidence:
                        payload.evidence
                ),
            availableEvidence:
                availableEvidence,
            language: language,
            allowsEvidenceActions:
                allowsEvidenceActions,
            canOpenTarget: canOpenTarget,
            onOpenTarget: onOpenTarget,
            onOpenEvidence: onOpenEvidence,
            onShowEvidenceInGraph:
                onShowEvidenceInGraph,
            onShowEvidenceDrawer:
                onShowEvidenceDrawer
        )
    }
}
