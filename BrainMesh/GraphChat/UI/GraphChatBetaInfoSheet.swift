//
//  GraphChatBetaInfoSheet.swift
//  BrainMesh
//
//  Scrollable, reusable Graph Chat beta guidance for iPhone and iPad.
//

import SwiftUI

struct GraphChatBetaInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    let presentation: GraphChatBetaInfoPresentation
    let onSelectQuestion: (GraphChatBetaQuestionSelection) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(presentation.sectionOrder, id: \.self) {
                        section in
                        sectionView(section)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(presentation.copy.sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(presentation.copy.closeTitle) {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint(presentation.copy.closeHint)
                    .accessibilityIdentifier("graph-chat-beta-close")
                }
            }
        }
        .presentationDetents(presentationDetents)
        .presentationDragIndicator(
            GraphChatBetaSheetPresentationContract.showsDragIndicator
                ? .visible
                : .hidden
        )
        .accessibilityIdentifier("graph-chat-beta-info-sheet")
    }

    @ViewBuilder
    private func sectionView(
        _ section: GraphChatBetaInfoSectionID
    ) -> some View {
        switch section {
        case .overview:
            overview
        case .currentCapabilities:
            currentCapabilities
        case .betterQuestions:
            betterQuestions
        case .limitations:
            limitations
        case .developmentDirections:
            developmentDirections
        case .graphExamples:
            graphExamples
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(presentation.copy.sheetTitle)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                GraphChatBetaBadge(copy: presentation.copy)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                presentation.copy.navigationAccessibilityLabel
            )

            Text(presentation.copy.sheetIntroduction)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.copy.trustTitle)
                        .font(.headline)
                    Text(presentation.copy.trustMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                .thinMaterial,
                in: RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("graph-chat-beta-trust")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("graph-chat-beta-section-overview")
    }

    private var currentCapabilities: some View {
        betaSection(
            title: presentation.copy.capabilitiesTitle,
            systemImage: "checkmark.shield"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(presentation.copy.capabilities) { capability in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(capability.title)
                            .font(.headline)
                        Text(capability.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(capability.genericExample)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier(
            "graph-chat-beta-section-capabilities"
        )
    }

    private var betterQuestions: some View {
        betaSection(
            title: presentation.copy.betterQuestionsTitle,
            systemImage: "text.bubble"
        ) {
            bulletList(presentation.copy.betterQuestionItems)
        }
        .accessibilityIdentifier("graph-chat-beta-section-tips")
    }

    private var limitations: some View {
        betaSection(
            title: presentation.copy.limitationsTitle,
            systemImage: "scope"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                bulletList(presentation.copy.limitationItems)
                Text(presentation.copy.limitationOutcome)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
            }
        }
        .accessibilityIdentifier("graph-chat-beta-section-limits")
    }

    private var developmentDirections: some View {
        betaSection(
            title: presentation.copy.developmentTitle,
            systemImage: "wrench.and.screwdriver"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(presentation.copy.developmentIntroduction)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                bulletList(presentation.copy.developmentItems)
            }
        }
        .accessibilityIdentifier("graph-chat-beta-section-development")
    }

    private var graphExamples: some View {
        betaSection(
            title: presentation.copy.examplesTitle,
            systemImage: "bubble.left.and.text.bubble.right"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if presentation.tappableQuestions.isEmpty == false {
                    Text(presentation.copy.examplesIntroduction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(
                        Array(presentation.tappableQuestions.enumerated()),
                        id: \.element.id
                    ) { index, suggestion in
                        Button {
                            selectQuestion(suggestion)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: suggestion.kind.systemImage)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)
                                Text(suggestion.prompt)
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .contentShape(Rectangle())
                            .background(
                                .thinMaterial,
                                in: RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(suggestion.accessibilityLabel)
                        .accessibilityHint(
                            presentation.copy.exampleSelectionHint
                        )
                        .accessibilityIdentifier(
                            "graph-chat-beta-example-\(index)"
                        )
                    }
                } else {
                    Text(presentation.copy.fallbackExamplesIntroduction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(
                        Array(presentation.fallbackExamples.enumerated()),
                        id: \.offset
                    ) { _, example in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(example)
                                .font(.subheadline.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            .quaternary,
                            in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            )
                        )
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .accessibilityIdentifier("graph-chat-beta-section-examples")
    }

    private func betaSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func bulletList(
        _ items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func selectQuestion(
        _ suggestion: GraphChatEmptyStateSuggestion
    ) {
        let selection = GraphChatBetaQuestionSelection(
            suggestion: suggestion
        )
        onSelectQuestion(selection)
        if selection.dismissesInfoSheet {
            dismiss()
        }
    }

    private var presentationDetents: Set<PresentationDetent> {
        Set(
            GraphChatBetaSheetPresentationContract.detents.map {
                detent in
                switch detent {
                case .medium:
                    return PresentationDetent.medium
                case .large:
                    return PresentationDetent.large
                }
            }
        )
    }
}
