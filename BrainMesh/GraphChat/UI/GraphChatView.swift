//
//  GraphChatView.swift
//  BrainMesh
//
//  Shared graph chat screen hosted by the productive root and contextual routing layer.
//

import SwiftUI

struct GraphChatView: View {
    @StateObject private var viewModel: GraphChatViewModel
    @State private var isConfirmingNewChat = false
    @State private var presentationID = UUID()
    private let betaCopy: GraphChatBetaCopy
    private let onOpenBetaInfo: () -> Void

    init(
        viewModel: @autoclosure @escaping () -> GraphChatViewModel,
        betaCopy: GraphChatBetaCopy = GraphChatBetaCopy(
            language: GraphChatResponseLanguageSelector.systemFallback()
        ),
        onOpenBetaInfo: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.betaCopy = betaCopy
        self.onOpenBetaInfo = onOpenBetaInfo
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GraphChatComposer(
                controller: viewModel.composerController,
                isGenerating: viewModel.isGenerating,
                isSubmissionAllowed: viewModel.canSubmitComposer,
                editingState: viewModel.editingState,
                isPerformingSessionMutation: viewModel.isPerformingSessionMutation,
                focusRequestID: viewModel.composerFocusRequestID,
                onSend: viewModel.send,
                onCancel: viewModel.cancelGeneration,
                onCancelEditing: viewModel.cancelEditing
            )
        }
        .overlay(alignment: .top) {
            if let notice = viewModel.actionNotice {
                actionNotice(notice)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.actionNotice?.id)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Neuen Chat beginnen?",
            isPresented: $isConfirmingNewChat,
            titleVisibility: .visible
        ) {
            Button(GraphChatMessageAction.startNewChat.title, role: .destructive) {
                viewModel.performChatAction(.startNewChat)
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(
                "Der aktuelle Verlauf, Conversation State und das sessionlokale Feedback werden gelöscht. Graph und Scope bleiben erhalten."
            )
        }
        .sheet(
            item:
                Binding(
                    get: {
                        viewModel
                            .correctionEditorSession
                    },
                    set: { value in
                        if value == nil {
                            viewModel
                                .cancelInterpretationCorrection()
                        }
                    }
                )
        ) { presentedSession in
            correctionEditor(
                presentedSession
            )
        }
        .task {
            await viewModel.load()
        }
        .onAppear {
            viewModel.presentationDidAppear(presentationID)
        }
        .onDisappear {
            viewModel.presentationDidDisappear(presentationID)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.graphName)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    GraphChatScopeChip(
                        presentation: viewModel.scopePresentation
                    )
                }
                Spacer(minLength: 12)
                newChatButton
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    GraphChatAvailabilityView(state: viewModel.availabilityState)
                    GraphChatIndexStateView(state: viewModel.indexState)
                }
                VStack(alignment: .leading, spacing: 8) {
                    GraphChatAvailabilityView(state: viewModel.availabilityState)
                    GraphChatIndexStateView(state: viewModel.indexState)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
    }

    private var newChatButton: some View {
        ViewThatFits(in: .horizontal) {
            Button {
                isConfirmingNewChat = true
            } label: {
                Label(GraphChatMessageAction.startNewChat.title, systemImage: GraphChatMessageAction.startNewChat.systemImage)
            }
            .buttonStyle(.bordered)
            .disabled(
                viewModel.canStartNewChatFromPublishedState
                    == false
            )
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button {
                isConfirmingNewChat = true
            } label: {
                Image(systemName: GraphChatMessageAction.startNewChat.systemImage)
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(
                viewModel.canStartNewChatFromPublishedState
                    == false
            )
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .accessibilityLabel(GraphChatMessageActionAccessibility.newChatLabel)
        .accessibilityHint(GraphChatMessageActionAccessibility.newChatHint)
        .accessibilityIdentifier("graph-chat-new-chat")
    }

    private var transcript: some View {
        GraphChatTranscriptView(
            viewModel: viewModel,
            controller: viewModel.transcriptController,
            betaCopy: betaCopy,
            onOpenBetaInfo: onOpenBetaInfo
        )
    }

    private func actionNotice(
        _ notice: GraphChatActionNotice
    ) -> some View {
        Label(notice.message, systemImage: notice.systemImage)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.quaternary, lineWidth: 1)
            }
            .shadow(radius: 8, y: 3)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func correctionEditor(
        _ presentedSession:
            GraphChatInterpretationCorrectionEditorSession
    ) -> some View {
        let session =
            viewModel
                .correctionEditorSession
            ?? presentedSession
        GraphChatInterpretationCorrectionEditorView(
            snapshot:
                session.snapshot,
            capabilities:
                session.capabilities,
            presentation:
                session.presentation,
            selection:
                Binding(
                    get: {
                        viewModel
                            .correctionEditorSession?
                            .selection
                        ?? session.selection
                    },
                    set: {
                        viewModel
                            .updateInterpretationCorrectionSelection(
                                $0
                            )
                    }
                ),
            validationState:
                session.validationState,
            isApplying:
                session.isApplying,
            onCancel:
                viewModel
                    .cancelInterpretationCorrection,
            onApply:
                viewModel
                    .applyInterpretationCorrection
        )
    }
}
