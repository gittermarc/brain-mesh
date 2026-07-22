//
//  GraphChatEmptyState.swift
//  BrainMesh
//
//  Scope-aware schema-derived empty state suggestions.
//

import SwiftUI

struct GraphChatEmptyState: View {
    let graphName: String
    let scopePresentation: GraphChatScopePresentationModel
    let language: GraphChatResponseLanguage
    let suggestions: [GraphChatEmptyStateSuggestion]
    let schemaErrorMessage: String?
    let isLoadingSuggestions: Bool
    let onSelectSuggestion: (GraphChatEmptyStateSuggestion) -> Void

    private var localizer: GraphChatUILocalizer {
        GraphChatUILocalizer(language: language)
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("\(localizer.emptyStateTitlePrefix) „\(graphName)“")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                GraphChatScopeChip(presentation: scopePresentation)

                Text(localizer.emptyStateDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let schemaErrorMessage {
                Label(schemaErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(localizer.schemaUnavailableLabel)
                    .accessibilityHint(schemaErrorMessage)
            } else if suggestions.isEmpty, isLoadingSuggestions {
                ProgressView(localizer.suggestionLoading)
                    .font(.callout)
            } else if suggestions.isEmpty {
                Label(localizer.noSupportedSuggestions, systemImage: "checkmark.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(localizer.noSupportedSuggestions)
            } else {
                VStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            onSelectSuggestion(suggestion)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: suggestion.kind.systemImage)
                                    .font(.body.weight(.semibold))
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.title)
                                        .font(.headline)
                                    Text(suggestion.prompt)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(12)
                            .contentShape(Rectangle())
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(suggestion.accessibilityLabel)
                        .accessibilityHint(suggestion.accessibilityHint)
                    }
                }
            }
        }
        .frame(maxWidth: 660)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .accessibilityElement(children: .contain)
    }
}

struct GraphChatScopeChip: View {
    let presentation: GraphChatScopePresentationModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                content
            }
            VStack(alignment: .center, spacing: 3) {
                content
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        Image(systemName: presentation.systemImage)
            .accessibilityHidden(true)
        Text(presentation.title)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        if let detail = presentation.detail {
            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
