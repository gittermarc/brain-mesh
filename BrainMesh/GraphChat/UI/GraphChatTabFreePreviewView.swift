//
//  GraphChatTabFreePreviewView.swift
//  BrainMesh
//
//  Memory-only Free preview presentation without session-store or SwiftData dependencies.
//

import Foundation
import SwiftUI


nonisolated struct GraphChatTabFreePreviewLoader: Sendable {
    private let schemaProvider: any GraphSchemaSnapshotProviding

    init(
        schemaProvider: any GraphSchemaSnapshotProviding = GraphSchemaService.shared
    ) {
        self.schemaProvider = schemaProvider
    }

    func schemaContext(
        for graphID: UUID
    ) async throws -> GraphSchemaContext {
        try await schemaProvider.makeSnapshot(
            in: GraphScope(graphID: graphID),
            exampleFieldIDs: []
        )
    }

    static func suggestions(
        schemaContext: GraphSchemaContext,
        request: GraphChatLaunchRequest?,
        modelAvailability: GraphChatAvailabilityPresentationState,
        language: GraphChatResponseLanguage
    ) -> [GraphChatEmptyStateSuggestion] {
        let previewRequest = request ?? GraphChatLaunchRequest(
            scope: .entireGraph(schemaContext.graphScope),
            context: .graph(name: schemaContext.snapshot.graphName)
        )
        return GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: GraphChatSuggestionContext(
                schema: schemaContext,
                scope: previewRequest.scope,
                launchContext: previewRequest.context,
                availableTools: Set(GraphChatToolKind.allCases),
                modelAvailability: modelAvailability,
                language: language
            )
        )
    }
}

struct GraphChatTabFreePreviewView: View {
    @Binding var draft: String

    let presentation: GraphChatTabFreePreviewPresentation
    let onSelectSuggestion: (GraphChatEmptyStateSuggestion) -> Void
    let onOpenPaywall: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GraphChatTabStatusCard(
                    icon: "sparkles.rectangle.stack",
                    title: "Chat with your Graph",
                    message: "Stelle natürliche Fragen an deinen aktiven Graphen und erhalte nachvollziehbare Antworten mit direkten Quellen."
                )

                if presentation.showsDraft {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deine Frage")
                            .font(.headline)
                        TextField(
                            "Was möchtest du in deinem Graphen finden?",
                            text: $draft,
                            axis: .vertical
                        )
                        .lineLimit(2...6)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("graph-chat-free-draft")
                        Text("Der Draft bleibt nur im Speicher. Nach dem Kauf entscheidest du selbst, ob du ihn sendest.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if presentation.suggestions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beispielfragen für diesen Graphen")
                            .font(.headline)
                        ForEach(presentation.suggestions) { suggestion in
                            Button {
                                onSelectSuggestion(suggestion)
                            } label: {
                                Label(suggestion.prompt, systemImage: "text.bubble")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        .thinMaterial,
                                        in: RoundedRectangle(cornerRadius: 14)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let errorMessage = presentation.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button(action: onOpenPaywall) {
                    Label("Mit BrainMesh Pro freischalten", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("graph-chat-open-paywall")

                Text("On-Device-Verarbeitung ist verfügbar, wenn das Gerät Apple Intelligence und das Systemmodell unterstützt. Die Vorschau liest keine Attachment-Inhalte.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }
}
