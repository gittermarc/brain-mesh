//
//  GraphChatNodeProfileArtifactView.swift
//  BrainMesh
//
//  Complete, localized presentation of a revalidated node profile.
//

import SwiftUI

struct GraphChatNodeProfileArtifactView: View {
    let artifact: GraphChatAnswerArtifact
    let resolved: GraphChatResolvedAnswerArtifact
    let payload:
        GraphChatAnswerArtifactNodeProfilePayload
    let availableEvidence:
        [GraphEvidenceID: GraphEvidence]
    let language:
        GraphChatResponseLanguage
    let allowsEvidenceActions: Bool
    let canOpenTarget:
        (
            GraphChatAnswerArtifactNavigationTarget
        ) -> Bool
    let onOpenTarget:
        (
            GraphChatAnswerArtifactNavigationTarget
        ) -> Void
    let onOpenEvidence:
        (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph:
        (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceDrawer:
        (
            GraphChatEvidenceDrawerPresentation
        ) -> Void

    private var presentation:
        GraphChatNodeProfilePresentation
    {
        GraphChatNodeProfilePresentation(
            payload: payload,
            language: language
        )
    }

    var body: some View {
        let presentation = presentation
        GraphChatAnswerArtifactCard(
            title: presentation.title,
            systemImage:
                "person.text.rectangle",
            language: language,
            onShowEvidence: showEvidence
        ) {
            identity(
                presentation
            )

            ForEach(
                presentation.sections
            ) { section in
                Divider()
                profileSection(section)
            }

            GraphChatAnswerEvidenceChipRow(
                evidenceIDs:
                    presentation
                    .identityEvidenceIDs,
                artifact: artifact,
                availableEvidence:
                    availableEvidence,
                language: language,
                allowsActions:
                    allowsEvidenceActions,
                onOpenEvidence:
                    onOpenEvidence,
                onShowEvidenceInGraph:
                    onShowEvidenceInGraph
            )
        }
    }

    @ViewBuilder
    private func identity(
        _ presentation:
            GraphChatNodeProfilePresentation
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: 10
        ) {
            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                if let nameLine =
                    presentation.nameLine
                {
                    Text(nameLine)
                        .font(.callout)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
                if let ownerLine =
                    presentation.ownerLine
                {
                    Text(ownerLine)
                        .font(.callout)
                        .foregroundStyle(
                            .secondary
                        )
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )

            if let target =
                presentation
                .nodeNavigationTarget
            {
                GraphChatAnswerArtifactNavigationButton(
                    target: target,
                    language: language,
                    canOpen:
                        canOpenTarget,
                    onOpen:
                        onOpenTarget
                )
            }
        }
    }

    private func profileSection(
        _ section:
            GraphChatNodeProfilePresentationSection
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 9
        ) {
            Text(section.title)
                .font(
                    .subheadline
                    .weight(.semibold)
                )

            ForEach(section.rows) { row in
                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    HStack(
                        alignment: .top,
                        spacing: 8
                    ) {
                        Text(row.text)
                            .font(.callout)
                            .fixedSize(
                                horizontal:
                                    false,
                                vertical: true
                            )
                            .frame(
                                maxWidth:
                                    .infinity,
                                alignment:
                                    .leading
                            )
                        if let target =
                            row.navigationTarget
                        {
                            GraphChatAnswerArtifactNavigationButton(
                                target:
                                    target,
                                language:
                                    language,
                                canOpen:
                                    canOpenTarget,
                                onOpen:
                                    onOpenTarget
                            )
                        }
                    }

                    GraphChatAnswerEvidenceChipRow(
                        evidenceIDs:
                            row.evidenceIDs,
                        artifact:
                            artifact,
                        availableEvidence:
                            availableEvidence,
                        language:
                            language,
                        allowsActions:
                            allowsEvidenceActions,
                        onOpenEvidence:
                            onOpenEvidence,
                        onShowEvidenceInGraph:
                            onShowEvidenceInGraph
                    )
                }
            }

            if let limitation =
                section.limitationText
            {
                Label(
                    limitation,
                    systemImage: "scissors"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
        .accessibilityElement(
            children: .contain
        )
    }

    private func showEvidence() {
        onShowEvidenceDrawer(
            GraphChatEvidenceDrawerPresentation(
                resolved: resolved,
                availableEvidence:
                    Array(
                        availableEvidence
                            .values
                    ),
                language: language
            )
        )
    }
}
