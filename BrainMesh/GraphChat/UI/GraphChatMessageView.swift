//
//  GraphChatMessageView.swift
//  BrainMesh
//
//  User and assistant transcript rendering for every stream state.
//

import SwiftUI

struct GraphChatMessageView: View {
    let message: GraphChatTranscriptMessage
    let onRetry: (UUID) -> Void
    let onOpenEvidence: (GraphChatEvidencePresentation) -> Void
    let onShowEvidenceInGraph: (GraphChatEvidencePresentation) -> Void
    let onUseFollowUp: (GraphChatFollowUpSuggestion) -> Void

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
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(phaseTitle(state.phase))
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
        Text(answer.directAnswer)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Antwort")
            .accessibilityValue(answer.directAnswer)

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
                    .accessibilityHint("Wählt diese Option für die offene Rückfrage aus.")
                }
            }
        }

        ForEach(answer.sections) { section in
            VStack(alignment: .leading, spacing: 6) {
                if let title = section.title, title.isEmpty == false {
                    Text(title)
                        .font(.headline)
                }
                Text(section.text)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }

        if answer.appliedFilters.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Label("Angewendete Filter", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline.weight(.semibold))

                ForEach(answer.appliedFilters) { filter in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                }
            }
        }

        if allowsEvidenceActions, answer.evidence.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                Label("Quellen", systemImage: "checkmark.seal")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel("Validierte Quellen")

                ForEach(answer.evidence.map(GraphChatEvidencePresentation.init)) { evidence in
                    GraphChatEvidenceCard(
                        evidence: evidence,
                        onOpenEntry: {
                            onOpenEvidence(evidence)
                        },
                        onShowInGraph: {
                            onShowEvidenceInGraph(evidence)
                        }
                    )
                }
            }
        }

        if answer.followUpSuggestions.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weiterfragen")
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
                    .accessibilityHint("Übernimmt die Folgefrage in das Eingabefeld.")
                }
            }
        }
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
