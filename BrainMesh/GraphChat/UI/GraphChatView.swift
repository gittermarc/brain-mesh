//
//  GraphChatView.swift
//  BrainMesh
//
//  Shared graph chat screen hosted by the productive root and contextual routing layer.
//

import SwiftUI

struct GraphChatView: View {
    @StateObject private var viewModel: GraphChatViewModel

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
                onSend: viewModel.send,
                onCancel: viewModel.cancelGeneration
            )
        }
        .navigationTitle("Graph Chat")
        .navigationBarTitleDisplayMode(.inline)
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
                    Label(viewModel.scopeTitle, systemImage: "scope")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
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

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if viewModel.messages.isEmpty {
                        GraphChatEmptyState(
                            graphName: viewModel.graphName,
                            suggestions: viewModel.suggestions,
                            schemaErrorMessage: viewModel.schemaErrorMessage,
                            onSelectSuggestion: viewModel.useSuggestion
                        )
                    } else {
                        ForEach(viewModel.messages) { message in
                            GraphChatMessageView(
                                message: message,
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
}
