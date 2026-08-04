//
//  GraphChatTranscriptView.swift
//  BrainMesh
//
//  Transcript-only observation boundary and bottom-aware auto-scroll behavior.
//

import SwiftUI

struct GraphChatTranscriptView: View {
    private static let bottomTolerance: CGFloat = 32

    @ObservedObject var viewModel: GraphChatViewModel
    @ObservedObject var controller: GraphChatTranscriptController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let betaCopy: GraphChatBetaCopy
    let onOpenBetaInfo: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if controller.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(controller.messages) { message in
                            messageView(message)
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
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let visibleBottom = geometry.contentOffset.y
                    + geometry.containerSize.height
                return visibleBottom
                    >= geometry.contentSize.height - Self.bottomTolerance
            } action: { _, isAtBottom in
                controller.updateViewport(
                    isAtBottom: isAtBottom,
                    userInitiated: false
                )
            }
            .onScrollPhaseChange { _, newPhase in
                switch newPhase {
                case .tracking, .interacting, .decelerating:
                    controller.updateUserScrollInteraction(isActive: true)
                case .idle:
                    controller.updateUserScrollInteraction(isActive: false)
                case .animating:
                    controller.updateUserScrollInteraction(isActive: false)
                @unknown default:
                    break
                }
            }
            .onChange(of: controller.scrollRequest) { _, request in
                guard let request else {
                    return
                }
                scrollToBottom(
                    proxy: proxy,
                    request: request
                )
            }
        }
    }

    private var emptyState: some View {
        GraphChatEmptyState(
            graphName: viewModel.graphName,
            scopePresentation: viewModel.scopePresentation,
            language: viewModel.interfaceLanguage,
            suggestions: viewModel.suggestions,
            schemaErrorMessage: viewModel.schemaErrorMessage,
            isLoadingSuggestions:
                viewModel.isLoadingSuggestions
                || (
                    viewModel.schemaContext == nil
                    && viewModel.schemaErrorMessage == nil
                ),
            betaCopy: betaCopy,
            onSelectSuggestion: viewModel.useSuggestion,
            onOpenBetaInfo: onOpenBetaInfo
        )
    }

    private func messageView(
        _ message: GraphChatTranscriptMessage
    ) -> some View {
        GraphChatMessageView(
            message: message,
            actionAvailability: viewModel.messageActionAvailability(
                for: message.id
            ),
            selectedFeedback: viewModel.feedbackCategory(
                for: message.id
            ),
            language: viewModel.interfaceLanguage,
            onAction: { action in
                viewModel.performMessageAction(
                    action,
                    messageID: message.id
                )
            },
            onRetry: viewModel.retry,
            onOpenEvidence: viewModel.openEntry,
            onShowEvidenceInGraph: viewModel.showInGraph,
            onUseFollowUp: viewModel.useFollowUp,
            onResolveAnswerPresentation: viewModel.resolveAnswerPresentation,
            canOpenArtifactTarget: viewModel.canOpenArtifactTarget,
            onOpenArtifactTarget: viewModel.openArtifactTarget,
            onInterpretationEvent: viewModel.recordInterpretationEvent,
            onEditInterpretation: viewModel.openInterpretationCorrection
        )
    }

    private func scrollToBottom(
        proxy: ScrollViewProxy,
        request: GraphChatTranscriptScrollRequest
    ) {
        guard GraphChatTranscriptScrollPolicy.shouldRequestScroll(
            for: request.trigger,
            isAtBottom: controller.isAtBottom
        ) else {
            return
        }
        let scroll = {
            proxy.scrollTo("graph-chat-bottom", anchor: .bottom)
        }
        switch GraphChatTranscriptScrollPolicy.animation(
            for: request.trigger,
            reduceMotion: reduceMotion
        ) {
        case .none:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scroll()
            }
        case .subtle:
            withAnimation(.easeOut(duration: 0.12)) {
                scroll()
            }
        }
    }
}
