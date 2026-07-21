//
//  GraphChatEmptyState.swift
//  BrainMesh
//
//  Schema-derived empty state suggestions.
//

import SwiftUI

struct GraphChatEmptyState: View {
    let graphName: String
    let suggestions: [GraphChatEmptyStateSuggestion]
    let schemaErrorMessage: String?
    let onSelectSuggestion: (GraphChatEmptyStateSuggestion) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Mit „\(graphName)“ chatten")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Frage nach Daten, Statuswerten, Zeiträumen oder direkten Verbindungen im aktuellen Scope.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let schemaErrorMessage {
                Label(schemaErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Schema konnte nicht geladen werden")
                    .accessibilityHint(schemaErrorMessage)
            } else if suggestions.isEmpty {
                ProgressView("Graphbezogene Vorschläge werden erstellt")
                    .font(.callout)
            } else {
                VStack(spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            onSelectSuggestion(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.title)
                                        .font(.headline)
                                    Text(suggestion.prompt)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .padding(12)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(suggestion.title)
                        .accessibilityHint("Übernimmt den Vorschlag in das Eingabefeld: \(suggestion.prompt)")
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
