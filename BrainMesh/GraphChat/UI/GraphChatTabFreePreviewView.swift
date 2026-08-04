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
}

struct GraphChatTabFreePreviewView: View {
    @State private var draftController:
        GraphChatComposerController

    let initialDraft: String
    let presentation: GraphChatTabFreePreviewPresentation
    let betaCopy: GraphChatBetaCopy
    let focusRequestID: UUID?
    let onOpenBetaInfo: () -> Void
    let onOpenPaywall: () -> Void

    init(
        initialDraft: String,
        draftScope: GraphChatScope?,
        presentation: GraphChatTabFreePreviewPresentation,
        betaCopy: GraphChatBetaCopy,
        focusRequestID: UUID? = nil,
        onCheckpointDraft: @escaping (String, GraphChatScope) -> Void,
        onOpenBetaInfo: @escaping () -> Void,
        onOpenPaywall: @escaping () -> Void
    ) {
        let bounded = Self.bounded(initialDraft)
        self.initialDraft = bounded
        self.presentation = presentation
        self.betaCopy = betaCopy
        self.focusRequestID = focusRequestID
        self.onOpenBetaInfo = onOpenBetaInfo
        self.onOpenPaywall = onOpenPaywall
        _draftController = State(
            initialValue: GraphChatComposerController(
                initialText: bounded,
                checkpointHandler: { value in
                    guard let draftScope else {
                        return
                    }
                    onCheckpointDraft(value, draftScope)
                }
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GraphChatTabStatusCard(
                    icon: "sparkles.rectangle.stack",
                    title: "Chat with your Graph",
                    message: "Stelle natürliche Fragen an deinen aktiven Graphen und erhalte nachvollziehbare Antworten mit direkten Quellen."
                )

                if presentation.showsDraft {
                    GraphChatTabFreePreviewDraftEditor(
                        controller: draftController,
                        focusRequestID: focusRequestID
                    )
                }

                GraphChatBetaCompactNoticeCard(
                    copy: betaCopy,
                    surface: .freePreview,
                    onOpenInfo: onOpenBetaInfo
                )

                if presentation.suggestions.isEmpty == false {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beispielfragen für diesen Graphen")
                            .font(.headline)
                        ForEach(presentation.suggestions) { suggestion in
                            Button {
                                draftController.replaceText(
                                    suggestion.prompt,
                                    checkpoint: false
                                )
                                checkpointDraft()
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

                Button {
                    checkpointDraft()
                    onOpenPaywall()
                } label: {
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
        .onChange(of: initialDraft) { _, value in
            let bounded = Self.bounded(value)
            guard draftController.text != bounded else {
                return
            }
            draftController.replaceText(
                bounded,
                checkpoint: false
            )
        }
        .onDisappear {
            checkpointDraft()
        }
    }

    private func checkpointDraft() {
        draftController.checkpointLatest()
    }

    private nonisolated static func bounded(
        _ value: String
    ) -> String {
        String(
            value.prefix(
                GraphChatIntentLimitPolicy
                    .default.maximumQuestionLength
            )
        )
    }
}

private struct GraphChatTabFreePreviewDraftEditor: View {
    @Bindable var controller: GraphChatComposerController
    @FocusState private var isDraftFocused: Bool

    let focusRequestID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deine Frage")
                .font(.headline)
            TextField(
                "Was möchtest du in deinem Graphen finden?",
                text: Binding(
                    get: { controller.text },
                    set: controller.updateFromUser
                ),
                axis: .vertical
            )
            .focused($isDraftFocused)
            .lineLimit(2...6)
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("graph-chat-free-draft")
            Text("Der Draft bleibt nur im Speicher. Nach dem Kauf entscheidest du selbst, ob du ihn sendest.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: focusRequestID) { _, requestID in
            guard requestID != nil else {
                return
            }
            isDraftFocused = true
        }
    }
}
