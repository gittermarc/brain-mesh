//
//  GraphChatFinalAnswerView.swift
//  BrainMesh
//
//  Final-answer composition that keeps text stable and augments it with registry-backed artifacts.
//

import SwiftUI

struct GraphChatFinalAnswerView: View {
    let answer: GraphChatAnswer
    let language: GraphChatResponseLanguage
    let allowsEvidenceActions: Bool
    let resolvePresentation: (GraphChatAnswer) async -> GraphChatAnswerPresentationResolution
    let canOpenArtifactTarget: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    let onOpenArtifactTarget: (GraphChatAnswerArtifactNavigationTarget) -> Void
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void
    let onUseFollowUp: (GraphChatFollowUpSuggestion) -> Void
    let onInterpretationEvent: (
        GraphChatIntentInterpretationLifecycleEvent
    ) -> Void

    @State private var resolution: GraphChatAnswerPresentationResolution?
    @State private var selectedEvidenceDrawer: GraphChatEvidenceDrawerPresentation?
    @State private var isResolving = false

    init(
        answer: GraphChatAnswer,
        language: GraphChatResponseLanguage,
        allowsEvidenceActions: Bool,
        resolvePresentation:
            @escaping (
                GraphChatAnswer
            ) async -> GraphChatAnswerPresentationResolution,
        canOpenArtifactTarget:
            @escaping (
                GraphChatAnswerArtifactNavigationTarget
            ) -> Bool,
        onOpenArtifactTarget:
            @escaping (
                GraphChatAnswerArtifactNavigationTarget
            ) -> Void,
        onOpenEvidence:
            @escaping (
                GraphChatEvidencePresentation
            ) -> Void,
        onShowEvidenceInGraph:
            @escaping (
                GraphChatEvidencePresentation
            ) -> Void,
        onUseFollowUp:
            @escaping (
                GraphChatFollowUpSuggestion
            ) -> Void,
        onInterpretationEvent:
            @escaping (
                GraphChatIntentInterpretationLifecycleEvent
            ) -> Void = { _ in }
    ) {
        self.answer = answer
        self.language = language
        self.allowsEvidenceActions =
            allowsEvidenceActions
        self.resolvePresentation =
            resolvePresentation
        self.canOpenArtifactTarget =
            canOpenArtifactTarget
        self.onOpenArtifactTarget =
            onOpenArtifactTarget
        self.onOpenEvidence = onOpenEvidence
        self.onShowEvidenceInGraph =
            onShowEvidenceInGraph
        self.onUseFollowUp = onUseFollowUp
        self.onInterpretationEvent =
            onInterpretationEvent
    }

    private var taskKey: GraphChatFinalAnswerResolutionKey {
        GraphChatFinalAnswerResolutionKey(
            artifactIDs: allRequestedArtifactIDs,
            evidenceIDs: answer.evidenceIDs
        )
    }

    private var allRequestedArtifactIDs: [GraphChatAnswerArtifactID] {
        GraphChatAnswerArtifactViewSupport.uniqueArtifactIDs(
            answer.artifactIDs + answer.sections.flatMap(\.artifactIDs)
        )
    }

    private var unsectionedArtifactIDs: [GraphChatAnswerArtifactID] {
        let sectionIDs = Set(answer.sections.flatMap(\.artifactIDs))
        return answer.artifactIDs.filter { sectionIDs.contains($0) == false }
    }

    private var availableEvidence: [GraphEvidenceID: GraphEvidence] {
        resolution?.evidenceByID ?? [:]
    }

    private var presentationSafeInterpretation:
        GraphChatIntentInterpretation?
    {
        guard let interpretation =
                answer.interpretation
        else {
            return nil
        }
        let context =
            answer.presentationContext
            ?? GraphChatPresentationContext(
                registry: .empty,
                language: language
            )
        return GraphChatPresentationFirewall()
            .presentationSafeInterpretation(
                interpretation,
                context: context
            )
    }

    private var interpretationTaskKey:
        GraphChatInterpretationPresentationTaskKey?
    {
        guard let interpretation =
                answer.interpretation
        else {
            return nil
        }
        return GraphChatInterpretationPresentationTaskKey(
            turnID:
                interpretation.turnBinding.turnID,
            isPresented:
                presentationSafeInterpretation
                    != nil
        )
    }

    var body: some View {
        let strings = GraphChatAnswerArtifactStrings(language: language)
        Group {
            if let interpretation =
                    presentationSafeInterpretation {
                interpretationView(interpretation)
            }

            Text(answer.directAnswer)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(strings.answer)
                .accessibilityValue(answer.directAnswer)

            clarificationOptions

            ForEach(answer.sections) { section in
                sectionView(section)
            }

            artifactEntries(for: unsectionedArtifactIDs)

            appliedFilters

            if isResolving,
               allRequestedArtifactIDs.isEmpty == false || answer.evidence.isEmpty == false {
                Label(strings.sourcesBeingChecked, systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
            }

            answerSources
            followUpSuggestions
        }
        .task(id: taskKey) {
            isResolving = true
            resolution = nil
            selectedEvidenceDrawer = nil
            let resolvedPresentation = await resolvePresentation(answer)
            guard Task.isCancelled == false else {
                return
            }
            resolution = resolvedPresentation
            isResolving = false
        }
        .task(id: interpretationTaskKey) {
            guard let key =
                    interpretationTaskKey
            else {
                return
            }
            onInterpretationEvent(
                key.isPresented
                    ? .displayed
                    : .discardedPresentationViolation
            )
        }
        .sheet(item: $selectedEvidenceDrawer) { presentation in
            GraphChatEvidenceDrawerView(
                presentation: presentation,
                allowsEvidenceActions: allowsEvidenceActions,
                onOpenEvidence: onOpenEvidence,
                onShowEvidenceInGraph: onShowEvidenceInGraph
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func interpretationView(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> some View {
        let presentation =
            interpretation.presentation
        return HStack(
            alignment: .top,
            spacing: 9
        ) {
            Image(
                systemName: "slider.horizontal.3"
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 2
            ) {
                Text(presentation.label)
                    .font(
                        .caption2
                            .weight(.semibold)
                    )
                    .foregroundStyle(.tertiary)
                Text(presentation.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            .thinMaterial,
            in: RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .stroke(.quaternary, lineWidth: 1)
        }
        .fixedSize(
            horizontal: false,
            vertical: true
        )
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            presentation.accessibilityLabel
        )
        .accessibilityIdentifier(
            "graph-chat-intent-interpretation"
        )
    }

    @ViewBuilder
    private var clarificationOptions: some View {
        if case .clarification(let clarification) = answer.state,
           clarification.options.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(clarification.options) { option in
                    Button {
                        onUseFollowUp(
                            GraphChatFollowUpSuggestion(
                                title: option.title,
                                prompt: option.id
                            )
                        )
                    } label: {
                        HStack {
                            Text(option.title)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "checkmark.circle")
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(
                        language == .german
                            ? "Wählt diese Option für die offene Rückfrage aus."
                            : "Selects this option for the open clarification."
                    )
                }
            }
        }
    }

    private func sectionView(
        _ section: GraphChatAnswerSection
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title = section.title, title.isEmpty == false {
                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if section.text.isEmpty == false {
                Text(section.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GraphChatAnswerEvidenceChipRow(
                evidenceIDs: section.evidenceIDs,
                artifact: nil,
                availableEvidence: availableEvidence,
                language: language,
                allowsActions: allowsEvidenceActions,
                onOpenEvidence: onOpenEvidence,
                onShowEvidenceInGraph: onShowEvidenceInGraph
            )

            artifactEntries(for: section.artifactIDs)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func artifactEntries(
        for artifactIDs: [GraphChatAnswerArtifactID]
    ) -> some View {
        if let resolution, artifactIDs.isEmpty == false {
            let plan = GraphChatAnswerArtifactRenderPlan(
                artifactIDs: artifactIDs,
                resolution: resolution
            )
            ForEach(plan.entries) { entry in
                switch entry {
                case .artifact(let resolved):
                    GraphChatAnswerArtifactRenderer(
                        resolved: resolved,
                        availableEvidence: resolution.evidenceByID,
                        language: resolved.artifact.querySummary?.language ?? language,
                        allowsEvidenceActions: allowsEvidenceActions,
                        canOpenTarget: canOpenArtifactTarget,
                        onOpenTarget: onOpenArtifactTarget,
                        onOpenEvidence: onOpenEvidence,
                        onShowEvidenceInGraph: onShowEvidenceInGraph,
                        onShowEvidenceDrawer: { presentation in
                            selectedEvidenceDrawer = presentation
                        }
                    )
                case .fallback:
                    GraphChatAnswerArtifactFallbackView(language: language)
                }
            }
        }
    }

    @ViewBuilder
    private var appliedFilters: some View {
        if answer.appliedFilters.isEmpty == false {
            let strings = GraphChatAnswerArtifactStrings(language: language)
            VStack(alignment: .leading, spacing: 8) {
                Label(strings.appliedFilters, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))

                ForEach(answer.appliedFilters) { filter in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            filterContent(filter)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            filterContent(filter)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func filterContent(
        _ filter: GraphChatAppliedFilter
    ) -> some View {
        Text(filter.fieldName)
            .font(.caption.weight(.semibold))
        Text(filter.operationDescription)
            .font(.caption)
            .foregroundStyle(.secondary)
        if let value = filter.valueDescription, value.isEmpty == false {
            Text(value)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }

    @ViewBuilder
    private var answerSources: some View {
        if let resolution,
           resolution.evidence.isEmpty == false {
            let strings = GraphChatAnswerArtifactStrings(language: language)
            VStack(alignment: .leading, spacing: 8) {
                Label(strings.sources, systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel(strings.validatedSources)

                GraphChatAnswerEvidenceChipRow(
                    evidenceIDs: resolution.evidence.map(\.id),
                    artifact: nil,
                    availableEvidence: resolution.evidenceByID,
                    language: language,
                    allowsActions: allowsEvidenceActions,
                    onOpenEvidence: onOpenEvidence,
                    onShowEvidenceInGraph: onShowEvidenceInGraph
                )
            }
        }
    }

    @ViewBuilder
    private var followUpSuggestions: some View {
        if answer.followUpSuggestions.isEmpty == false {
            let strings = GraphChatAnswerArtifactStrings(language: language)
            VStack(alignment: .leading, spacing: 8) {
                Text(strings.followUp)
                    .font(.subheadline.weight(.semibold))

                ForEach(answer.followUpSuggestions) { suggestion in
                    Button {
                        onUseFollowUp(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion.title)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.left")
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(
                        language == .german
                            ? "Übernimmt die Folgefrage in das Eingabefeld."
                            : "Copies the follow-up question into the composer."
                    )
                }
            }
        }
    }
}

private nonisolated struct GraphChatFinalAnswerResolutionKey: Hashable {
    let artifactIDs: [GraphChatAnswerArtifactID]
    let evidenceIDs: [GraphEvidenceID]
}

private nonisolated struct GraphChatInterpretationPresentationTaskKey:
    Hashable
{
    let turnID: UUID
    let isPresented: Bool
}

nonisolated extension GraphChatAnswerArtifactViewSupport {
    static func uniqueArtifactIDs(
        _ ids: [GraphChatAnswerArtifactID]
    ) -> [GraphChatAnswerArtifactID] {
        var seen = Set<GraphChatAnswerArtifactID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
