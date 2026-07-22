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

    init(viewModel: @autoclosure @escaping () -> GraphChatViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GraphChatComposer(
                text: Binding(
                    get: { viewModel.composerState.text },
                    set: viewModel.setComposerText
                ),
                isGenerating: viewModel.isGenerating,
                canSend: viewModel.canSend,
                editingState: viewModel.editingState,
                isPerformingSessionMutation: viewModel.isPerformingSessionMutation,
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
        .navigationTitle("Graph Chat")
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
        .task {
            await viewModel.load()
        }
        .onDisappear {
            viewModel.viewDidDisappear()
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
            .disabled(viewModel.canStartNewChat == false)
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button {
                isConfirmingNewChat = true
            } label: {
                Image(systemName: GraphChatMessageAction.startNewChat.systemImage)
                    .frame(width: 36, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.canStartNewChat == false)
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .accessibilityLabel(GraphChatMessageActionAccessibility.newChatLabel)
        .accessibilityHint(GraphChatMessageActionAccessibility.newChatHint)
        .accessibilityIdentifier("graph-chat-new-chat")
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if viewModel.messages.isEmpty {
                        GraphChatEmptyState(
                            graphName: viewModel.graphName,
                            scopePresentation: viewModel.scopePresentation,
                            language: viewModel.interfaceLanguage,
                            suggestions: viewModel.suggestions,
                            schemaErrorMessage: viewModel.schemaErrorMessage,
                            isLoadingSuggestions: viewModel.schemaContext == nil
                                && viewModel.schemaErrorMessage == nil,
                            onSelectSuggestion: viewModel.useSuggestion
                        )
                    } else {
                        ForEach(viewModel.messages) { message in
                            GraphChatMessageView(
                                message: message,
                                actionAvailability: viewModel.messageActionAvailability(
                                    for: message.id
                                ),
                                selectedFeedback: viewModel.feedbackCategory(
                                    for: message.id
                                ),
                                onAction: { action in
                                    viewModel.performMessageAction(
                                        action,
                                        messageID: message.id
                                    )
                                },
                                onRetry: viewModel.retry,
                                onOpenEvidence: viewModel.openEntry,
                                onShowEvidenceInGraph: viewModel.showInGraph,
                                onUseFollowUp: viewModel.useFollowUp
                            )
                            .id(message.id)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("graph-chat-bottom")
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: 760)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: viewModel.scrollAnchorToken) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("graph-chat-bottom", anchor: .bottom)
                }
            }
        }
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
}
