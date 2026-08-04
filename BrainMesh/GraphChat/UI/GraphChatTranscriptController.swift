//
//  GraphChatTranscriptController.swift
//  BrainMesh
//
//  Narrow Observation and scroll-policy owner for the chat transcript.
//

import Combine
import Foundation

nonisolated enum GraphChatTranscriptScrollTrigger:
    String,
    Hashable,
    Sendable
{
    case turnStarted
    case partial
    case terminal
    case conversationMutation
}

nonisolated enum GraphChatTranscriptScrollAnimation:
    Hashable,
    Sendable
{
    case none
    case subtle
}

nonisolated struct GraphChatTranscriptScrollRequest:
    Hashable,
    Sendable,
    Identifiable
{
    let id: UInt64
    let trigger: GraphChatTranscriptScrollTrigger
}

nonisolated enum GraphChatTranscriptScrollPolicy {
    static func shouldRequestScroll(
        for trigger: GraphChatTranscriptScrollTrigger,
        isAtBottom: Bool
    ) -> Bool {
        switch trigger {
        case .partial, .terminal:
            return isAtBottom
        case .turnStarted, .conversationMutation:
            return true
        }
    }

    static func animation(
        for trigger: GraphChatTranscriptScrollTrigger,
        reduceMotion: Bool
    ) -> GraphChatTranscriptScrollAnimation {
        guard reduceMotion == false else {
            return .none
        }
        switch trigger {
        case .terminal, .turnStarted, .conversationMutation:
            return .subtle
        case .partial:
            return .none
        }
    }
}

@MainActor
final class GraphChatTranscriptController: ObservableObject {
    private struct ObservedState {
        var messages: [GraphChatTranscriptMessage] = []
        var scrollRequest: GraphChatTranscriptScrollRequest?
    }

    @Published private var observedState = ObservedState()

    private(set) var isAtBottom = true
    private var viewportIsAtBottom = true
    private var isUserNavigating = false
    private var nextScrollRequestID: UInt64 = 0

    var messages: [GraphChatTranscriptMessage] {
        observedState.messages
    }

    var scrollRequest: GraphChatTranscriptScrollRequest? {
        observedState.scrollRequest
    }

    func updateViewport(
        isAtBottom: Bool,
        userInitiated: Bool = true
    ) {
        viewportIsAtBottom = isAtBottom
        if isAtBottom, isUserNavigating == false {
            self.isAtBottom = true
        } else if userInitiated || isUserNavigating {
            self.isAtBottom = false
        }
    }

    func userDidNavigateTranscript() {
        viewportIsAtBottom = false
        isAtBottom = false
    }

    func updateUserScrollInteraction(isActive: Bool) {
        isUserNavigating = isActive
        if isActive {
            isAtBottom = false
        } else if viewportIsAtBottom {
            isAtBottom = true
        }
    }

    func replaceMessages(
        _ messages: [GraphChatTranscriptMessage],
        scroll trigger: GraphChatTranscriptScrollTrigger? = nil
    ) {
        var updatedState = observedState
        updatedState.messages = messages
        if let trigger,
           let request = makeScrollRequest(for: trigger) {
            updatedState.scrollRequest = request
        }
        observedState = updatedState
    }

    func appendTurn(
        userMessage: GraphChatTranscriptMessage,
        assistantMessage: GraphChatTranscriptMessage
    ) {
        var updatedMessages = messages
        updatedMessages.append(userMessage)
        updatedMessages.append(assistantMessage)
        var updatedState = observedState
        updatedState.messages = updatedMessages
        if let request = makeScrollRequest(for: .turnStarted) {
            updatedState.scrollRequest = request
        }
        observedState = updatedState
    }

    @discardableResult
    func apply(
        _ publication: GraphChatStreamingUIPublication,
        toAssistantMessageID messageID: UUID
    ) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              case .assistant(var state) = messages[index].state else {
            return false
        }

        for event in publication.events {
            state.apply(event)
        }
        var updatedMessages = messages
        updatedMessages[index].state = .assistant(state)
        var updatedObservedState = observedState
        updatedObservedState.messages = updatedMessages

        switch publication.reason {
        case .terminal:
            if let request = makeScrollRequest(
                for: .terminal
            ) {
                updatedObservedState.scrollRequest = request
            }
        case .partial:
            if let request = makeScrollRequest(
                for: .partial
            ) {
                updatedObservedState.scrollRequest = request
            }
        case .progress:
            break
        }
        observedState = updatedObservedState
        return true
    }

    @discardableResult
    func mutateAssistant(
        messageID: UUID,
        preferLastMatch: Bool = false,
        _ mutation: (inout GraphChatAssistantMessageState) -> Void
    ) -> Bool {
        let index: Int?
        if preferLastMatch {
            index = messages.lastIndex(where: { $0.id == messageID })
        } else {
            index = messages.firstIndex(where: { $0.id == messageID })
        }
        guard let index,
              case .assistant(var state) = messages[index].state else {
            return false
        }
        mutation(&state)
        var updatedMessages = messages
        updatedMessages[index].state = .assistant(state)
        var updatedObservedState = observedState
        updatedObservedState.messages = updatedMessages
        observedState = updatedObservedState
        return true
    }

    @discardableResult
    func setCheckpointAfterTurn(
        _ checkpoint: GraphChatConversationCheckpoint,
        messageID: UUID
    ) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            return false
        }
        var updatedMessages = messages
        updatedMessages[index].conversationCheckpointAfterTurn = checkpoint
        var updatedObservedState = observedState
        updatedObservedState.messages = updatedMessages
        observedState = updatedObservedState
        return true
    }

    func requestConversationMutationScroll() {
        guard let request = makeScrollRequest(
            for: .conversationMutation
        ) else {
            return
        }
        var updatedState = observedState
        updatedState.scrollRequest = request
        observedState = updatedState
    }

    private func makeScrollRequest(
        for trigger: GraphChatTranscriptScrollTrigger
    ) -> GraphChatTranscriptScrollRequest? {
        guard GraphChatTranscriptScrollPolicy.shouldRequestScroll(
            for: trigger,
            isAtBottom: isAtBottom
        ) else {
            return nil
        }
        nextScrollRequestID &+= 1
        return GraphChatTranscriptScrollRequest(
            id: nextScrollRequestID,
            trigger: trigger
        )
    }
}
