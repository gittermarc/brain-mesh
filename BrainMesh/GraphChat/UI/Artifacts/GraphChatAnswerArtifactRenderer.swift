//
//  GraphChatAnswerArtifactRenderer.swift
//  BrainMesh
//
//  Single type-dispatch boundary for all graph-native answer artifacts.
//

import SwiftUI

struct GraphChatAnswerArtifactRenderer: View {
    let resolved: GraphChatResolvedAnswerArtifact
    let availableEvidence: [GraphEvidenceID: GraphEvidence]
    let language: GraphChatResponseLanguage
    let allowsEvidenceActions: Bool
    let canOpenTarget: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    let onOpenTarget: (GraphChatAnswerArtifactNavigationTarget) -> Void
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceDrawer: (GraphChatEvidenceDrawerPresentation) -> Void

    @ViewBuilder
    var body: some View {
        let artifact = resolved.artifact
        let descriptor = GraphChatAnswerArtifactRenderDescriptor.make(for: artifact)
        if descriptor.isEmpty {
            GraphChatAnswerArtifactCard(
                title: artifact.title,
                systemImage: systemImage(for: descriptor.component),
                language: language,
                onShowEvidence: showEvidenceAction
            ) {
                GraphChatAnswerArtifactEmptyView(language: language)
                if let metadata = artifact.payload.resultMetadata {
                    GraphChatAnswerArtifactMetadataView(
                        metadata: metadata,
                        visibleCount: nil,
                        availableCount: nil,
                        language: language
                    )
                }
                artifactEvidenceRow
            }
        } else {
            switch artifact.payload {
            case .nodeProfile(let payload):
                GraphChatNodeProfileArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence:
                        availableEvidence,
                    language: language,
                    allowsEvidenceActions:
                        allowsEvidenceActions,
                    canOpenTarget:
                        canOpenTarget,
                    onOpenTarget:
                        onOpenTarget,
                    onOpenEvidence:
                        onOpenEvidence,
                    onShowEvidenceInGraph:
                        onShowEvidenceInGraph,
                    onShowEvidenceDrawer:
                        onShowEvidenceDrawer
                )
            case .relationship(let payload):
                GraphChatRelationshipArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence:
                        availableEvidence,
                    language: language,
                    allowsEvidenceActions:
                        allowsEvidenceActions,
                    canOpenTarget:
                        canOpenTarget,
                    onOpenTarget:
                        onOpenTarget,
                    onOpenEvidence:
                        onOpenEvidence,
                    onShowEvidenceInGraph:
                        onShowEvidenceInGraph,
                    onShowEvidenceDrawer:
                        onShowEvidenceDrawer
                )
            case .metric(let payload):
                GraphChatMetricArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsEvidenceActions: allowsEvidenceActions,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph,
                    onShowEvidenceDrawer: onShowEvidenceDrawer
                )
            case .resultList(let payload):
                GraphChatResultListArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsEvidenceActions: allowsEvidenceActions,
                    canOpenTarget: canOpenTarget,
                    onOpenTarget: onOpenTarget,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph,
                    onShowEvidenceDrawer: onShowEvidenceDrawer
                )
            case .table(let payload):
                GraphChatTableArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsEvidenceActions: allowsEvidenceActions,
                    canOpenTarget: canOpenTarget,
                    onOpenTarget: onOpenTarget,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph,
                    onShowEvidenceDrawer: onShowEvidenceDrawer
                )
            case .ranking(let payload):
                GraphChatRankingArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsEvidenceActions: allowsEvidenceActions,
                    canOpenTarget: canOpenTarget,
                    onOpenTarget: onOpenTarget,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph,
                    onShowEvidenceDrawer: onShowEvidenceDrawer
                )
            case .grouping(let payload):
                GraphChatGroupingArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsEvidenceActions: allowsEvidenceActions,
                    canOpenTarget: canOpenTarget,
                    onOpenTarget: onOpenTarget,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph,
                    onShowEvidenceDrawer: onShowEvidenceDrawer
                )
            case .comparison(let payload):
                GraphChatComparisonArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsEvidenceActions: allowsEvidenceActions,
                    canOpenTarget: canOpenTarget,
                    onOpenTarget: onOpenTarget,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph,
                    onShowEvidenceDrawer: onShowEvidenceDrawer
                )
            case .healthFinding(let payload):
                GraphChatHealthFindingArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsEvidenceActions: allowsEvidenceActions,
                    canOpenTarget: canOpenTarget,
                    onOpenTarget: onOpenTarget,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph,
                    onShowEvidenceDrawer: onShowEvidenceDrawer
                )
            case .timeline(let payload):
                GraphChatTimelineArtifactView(
                    artifact: artifact,
                    resolved: resolved,
                    payload: payload,
                    availableEvidence: availableEvidence,
                    language: language,
                    allowsEvidenceActions: allowsEvidenceActions,
                    canOpenTarget: canOpenTarget,
                    onOpenTarget: onOpenTarget,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph,
                    onShowEvidenceDrawer: onShowEvidenceDrawer
                )
            }
        }
    }

    private var showEvidenceAction: (() -> Void)? {
        {
            onShowEvidenceDrawer(
                GraphChatEvidenceDrawerPresentation(
                    resolved: resolved,
                    availableEvidence: Array(availableEvidence.values),
                    language: language
                )
            )
        }
    }

    private var artifactEvidenceRow: some View {
        GraphChatAnswerEvidenceChipRow(
            evidenceIDs: resolved.artifact.allEvidenceIDs,
            artifact: resolved.artifact,
            availableEvidence: availableEvidence,
            language: language,
            allowsActions: allowsEvidenceActions,
            onOpenEvidence: onOpenEvidence,
            onShowEvidenceInGraph: onShowEvidenceInGraph
        )
    }

    private func systemImage(
        for component: GraphChatAnswerArtifactRenderComponent
    ) -> String {
        switch component {
        case .nodeProfile:
            return "person.text.rectangle"
        case .relationship:
            return "point.3.connected.trianglepath.dotted"
        case .metric:
            return "number"
        case .resultList:
            return "list.bullet"
        case .table:
            return "tablecells"
        case .ranking:
            return "list.number"
        case .grouping:
            return "square.grid.2x2"
        case .comparison:
            return "rectangle.split.3x1"
        case .healthFinding:
            return "checkmark.shield"
        case .timeline:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }
}
