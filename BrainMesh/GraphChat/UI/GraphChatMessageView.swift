//
//  GraphChatMessageView.swift
//  BrainMesh
//
//  User and assistant transcript rendering with centralized, context-sensitive actions.
//

import SwiftUI

struct GraphChatMessageView: View {
    let message: GraphChatTranscriptMessage
    let actionAvailability: GraphChatMessageActionAvailability
    let selectedFeedback: GraphChatFeedbackCategory?
    let onAction: (GraphChatMessageAction) -> Void
    let onRetry: (UUID) -> Void
    let language: GraphChatResponseLanguage
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void
    let onUseFollowUp: (GraphChatFollowUpSuggestion) -> Void
    let onResolveAnswerPresentation: (GraphChatAnswer) async -> GraphChatAnswerPresentationResolution
    let canOpenArtifactTarget: (GraphChatAnswerArtifactNavigationTarget) -> Bool
    let onOpenArtifactTarget: (GraphChatAnswerArtifactNavigationTarget) -> Void

    init(
        message: GraphChatTranscriptMessage,
        actionAvailability: GraphChatMessageActionAvailability,
        selectedFeedback: GraphChatFeedbackCategory?,
        language: GraphChatResponseLanguage = .german,
        onAction: @escaping (GraphChatMessageAction) -> Void,
        onRetry: @escaping (UUID) -> Void,
        onOpenEvidence: @escaping (GraphChatEvidencePresentation) -> Void,
        onShowEvidenceInGraph: @escaping (GraphChatEvidencePresentation) -> Void,
        onUseFollowUp: @escaping (GraphChatFollowUpSuggestion) -> Void,
        onResolveAnswerPresentation: @escaping (GraphChatAnswer) async -> GraphChatAnswerPresentationResolution = { answer in
            let graphScope = GraphScope(
                graphID: answer.evidence.first?.sourceReference.graphID ?? UUID()
            )
            return .unavailable(
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope),
                requestedArtifactIDs: GraphChatAnswerArtifactViewSupport.uniqueArtifactIDs(
                    answer.artifactIDs + answer.sections.flatMap(\.artifactIDs)
                ),
                evidence: answer.evidence,
                reason: .sessionUnavailable
            )
        },
        canOpenArtifactTarget: @escaping (GraphChatAnswerArtifactNavigationTarget) -> Bool = { _ in false },
        onOpenArtifactTarget: @escaping (GraphChatAnswerArtifactNavigationTarget) -> Void = { _ in }
    ) {
        self.message = message
        self.actionAvailability = actionAvailability
        self.selectedFeedback = selectedFeedback
        self.language = language
        self.onAction = onAction
        self.onRetry = onRetry
        self.onOpenEvidence = onOpenEvidence
        self.onShowEvidenceInGraph = onShowEvidenceInGraph
        self.onUseFollowUp = onUseFollowUp
        self.onResolveAnswerPresentation = onResolveAnswerPresentation
        self.canOpenArtifactTarget = canOpenArtifactTarget
        self.onOpenArtifactTarget = onOpenArtifactTarget
    }

    var body: some View {
        switch message.state {
        case .userQuestion(let question):
            userQuestion(question)
        case .assistant(let state):
            assistantMessage(state)
        }
    }

    private func userQuestion(_ question: String) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 6) {
                Text(question)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 620, alignment: .trailing)
                    .accessibilityLabel("Deine Frage")
                    .accessibilityValue(question)
                    .accessibilitySortPriority(2)

                if actionAvailability.canEditAndResend {
                    Menu {
                        Button {
                            onAction(.editAndResend)
                        } label: {
                            Label(
                                GraphChatMessageAction.editAndResend.title,
                                systemImage: GraphChatMessageAction.editAndResend.systemImage
                            )
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(GraphChatMessageActionAccessibility.userMessageMenuLabel)
                    .accessibilityHint(GraphChatMessageActionAccessibility.userMessageMenuHint)
                }
            }
        }
    }

    private func assistantMessage(
        _ state: GraphChatAssistantMessageState
    ) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 14) {
                phaseHeader(state)

                if state.toolActivities.isEmpty == false,
                   state.phase == .running || state.phase == .partial {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(state.toolActivities) { activity in
                            Label {
                                Text(activity.text)
                            } icon: {
                                if activity.state == .started {
                                    ProgressView()
                                } else {
                                    Image(systemName: "checkmark.circle")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                switch state.phase {
                case .running:
                    if state.text.isEmpty {
                        Text("Die Antwort wird vorbereitet.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        partialText(state.text)
                    }
                case .partial:
                    partialText(state.text)
                case .final, .clarification, .unsupported:
                    if let answer = state.answer {
                        finalAnswer(answer, allowsEvidenceActions: state.allowsEvidenceActions)
                    }
                case .noResults:
                    noResults(state)
                case .availabilityError:
                    availabilityError(state)
                case .technicalError:
                    technicalError(state)
                case .cancelled:
                    cancelled(state)
                }

                if let selectedFeedback {
                    Label(
                        "Feedback: \(selectedFeedback.title)",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Ausgewähltes Feedback: \(selectedFeedback.title)")
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(1)

            Spacer(minLength: 20)
        }
    }

    private func phaseHeader(
        _ state: GraphChatAssistantMessageState
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: phaseSymbol(state.phase))
                .accessibilityHidden(true)
            Text(phaseTitle(state.phase))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if actionAvailability.hasAnyAction {
                assistantActionMenu
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var assistantActionMenu: some View {
        Menu {
            if actionAvailability.canCopy {
                Button {
                    onAction(.copy)
                } label: {
                    Label(
                        GraphChatMessageAction.copy.title,
                        systemImage: GraphChatMessageAction.copy.systemImage
                    )
                }
            }

            if actionAvailability.canRegenerate {
                Button {
                    onAction(.regenerate)
                } label: {
                    Label(
                        GraphChatMessageAction.regenerate.title,
                        systemImage: GraphChatMessageAction.regenerate.systemImage
                    )
                }
            }

            if actionAvailability.canGiveFeedback {
                Section("Feedback") {
                    ForEach(GraphChatFeedbackCategory.allCases, id: \.self) { category in
                        Button {
                            onAction(.feedback(category))
                        } label: {
                            if selectedFeedback == category {
                                Label(category.title, systemImage: "checkmark")
                            } else {
                                Label(
                                    GraphChatMessageAction.feedback(category).title,
                                    systemImage: GraphChatMessageAction.feedback(category).systemImage
                                )
                            }
                        }
                    }

                    if selectedFeedback != nil {
                        Button(role: .destructive) {
                            onAction(.removeFeedback)
                        } label: {
                            Label(
                                GraphChatMessageAction.removeFeedback.title,
                                systemImage: GraphChatMessageAction.removeFeedback.systemImage
                            )
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GraphChatMessageActionAccessibility.assistantMessageMenuLabel)
        .accessibilityHint(GraphChatMessageActionAccessibility.assistantMessageMenuHint)
    }

    private func partialText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Partielle Antwort")
            .accessibilityValue(text)
    }

    @ViewBuilder
    private func finalAnswer(
        _ answer: GraphChatAnswer,
        allowsEvidenceActions: Bool
    ) -> some View {
        GraphChatFinalAnswerView(
            answer: answer,
            language: language,
            allowsEvidenceActions: allowsEvidenceActions,
            resolvePresentation: onResolveAnswerPresentation,
            canOpenArtifactTarget: canOpenArtifactTarget,
            onOpenArtifactTarget: onOpenArtifactTarget,
            onOpenEvidence: onOpenEvidence,
            onShowEvidenceInGraph: onShowEvidenceInGraph,
            onUseFollowUp: onUseFollowUp
        )
    }

    private func noResults(
        _ state: GraphChatAssistantMessageState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.text.isEmpty == false {
                Text(state.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(
                "Es wurden keine passenden dokumentierten Graphdaten gefunden. Nicht dokumentierte Informationen wurden nicht berücksichtigt.",
                systemImage: "magnifyingglass"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func availabilityError(
        _ state: GraphChatAssistantMessageState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.text.isEmpty == false {
                Text(state.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(state.error?.message ?? "Das On-Device-Modell ist nicht verfügbar.")
                .font(.body)
            if let recovery = state.error?.recoverySuggestion {
                Text(recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func technicalError(
        _ state: GraphChatAssistantMessageState
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.text.isEmpty == false {
                Text(state.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(state.error?.message ?? "Die Anfrage konnte nicht abgeschlossen werden.")
                .font(.body)
            if let recovery = state.error?.recoverySuggestion {
                Text(recovery)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button {
                onRetry(message.id)
            } label: {
                Label("Erneut versuchen", systemImage: "arrow.clockwise")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Wiederholt dieselbe Frage ohne einen neuen Verlaufseintrag.")
        }
    }

    private func cancelled(
        _ state: GraphChatAssistantMessageState
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.text.isEmpty == false {
                Text(state.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Antwort abgebrochen", systemImage: "stop.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func phaseTitle(_ phase: GraphChatAssistantPhase) -> String {
        switch phase {
        case .running:
            return "Antwort läuft"
        case .partial:
            return "Antwort wird ergänzt"
        case .final:
            return "Antwort"
        case .clarification:
            return "Rückfrage"
        case .noResults:
            return "Keine passenden Ergebnisse"
        case .unsupported:
            return "Nicht unterstützt"
        case .availabilityError:
            return "On-Device-Modell nicht verfügbar"
        case .technicalError:
            return "Technischer Fehler"
        case .cancelled:
            return "Abgebrochen"
        }
    }

    private func phaseSymbol(_ phase: GraphChatAssistantPhase) -> String {
        switch phase {
        case .running, .partial:
            return "sparkles"
        case .final:
            return "checkmark.bubble"
        case .clarification:
            return "questionmark.bubble"
        case .noResults:
            return "magnifyingglass"
        case .unsupported:
            return "nosign"
        case .availabilityError:
            return "exclamationmark.triangle"
        case .technicalError:
            return "exclamationmark.circle"
        case .cancelled:
            return "stop.circle"
        }
    }
}
