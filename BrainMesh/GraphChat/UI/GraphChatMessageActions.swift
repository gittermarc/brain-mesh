//
//  GraphChatMessageActions.swift
//  BrainMesh
//
//  Central value-only action, copy, branching, and privacy-neutral feedback models.
//

import Foundation

nonisolated enum GraphChatMessageAction: Hashable, Sendable {
    case copy
    case editAndResend
    case regenerate
    case startNewChat
    case feedback(GraphChatFeedbackCategory)
    case removeFeedback

    var title: String {
        switch self {
        case .copy:
            return "Antwort kopieren"
        case .editAndResend:
            return "Bearbeiten und erneut senden"
        case .regenerate:
            return "Antwort neu generieren"
        case .startNewChat:
            return "Neuer Chat"
        case .feedback(let category):
            return category.title
        case .removeFeedback:
            return "Feedback entfernen"
        }
    }

    var systemImage: String {
        switch self {
        case .copy:
            return "doc.on.doc"
        case .editAndResend:
            return "pencil"
        case .regenerate:
            return "arrow.clockwise"
        case .startNewChat:
            return "plus.message"
        case .feedback(let category):
            return category.systemImage
        case .removeFeedback:
            return "xmark.circle"
        }
    }
}

nonisolated enum GraphChatMessageActionAccessibility {
    static let userMessageMenuLabel = "Aktionen für deine Frage"
    static let userMessageMenuHint = "Öffnet die Aktion zum Bearbeiten und erneuten Senden."
    static let assistantMessageMenuLabel = "Aktionen für diese Antwort"
    static let assistantMessageMenuHint = "Öffnet verfügbare Aktionen für diese Antwort."
    static let newChatLabel = "Neuer Chat"
    static let newChatHint = "Löscht den aktuellen Chat und behält den aktiven Graphen sowie Scope bei."
}

nonisolated struct GraphChatMessageActionAvailability: Hashable, Sendable {
    let canCopy: Bool
    let canEditAndResend: Bool
    let canRegenerate: Bool
    let canGiveFeedback: Bool

    static let unavailable = GraphChatMessageActionAvailability(
        canCopy: false,
        canEditAndResend: false,
        canRegenerate: false,
        canGiveFeedback: false
    )

    var hasAnyAction: Bool {
        canCopy || canEditAndResend || canRegenerate || canGiveFeedback
    }
}

nonisolated enum GraphChatMessageActionPolicy {
    static func availability(
        for messageID: UUID,
        in messages: [GraphChatTranscriptMessage],
        isGenerating: Bool
    ) -> GraphChatMessageActionAvailability {
        guard let message = messages.first(where: { $0.id == messageID }) else {
            return .unavailable
        }

        switch message.state {
        case .userQuestion(let question):
            return GraphChatMessageActionAvailability(
                canCopy: false,
                canEditAndResend: question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                canRegenerate: false,
                canGiveFeedback: false
            )

        case .assistant(let state):
            let isLatestAssistant = messages.last(where: { message in
                if case .assistant = message.state {
                    return true
                }
                return false
            })?.id == messageID
            let terminalAnswer = state.isTerminal && state.answer != nil
            return GraphChatMessageActionAvailability(
                canCopy: GraphChatCopyContentBuilder.payload(for: state) != nil,
                canEditAndResend: false,
                canRegenerate: terminalAnswer && isLatestAssistant && isGenerating == false,
                canGiveFeedback: terminalAnswer && feedbackAnswerState(for: state) != nil
            )
        }
    }

    static func feedbackAnswerState(
        for state: GraphChatAssistantMessageState
    ) -> GraphChatFeedbackAnswerState? {
        guard state.isTerminal else {
            return nil
        }

        switch state.phase {
        case .final:
            return .answer
        case .clarification:
            return .clarification
        case .noResults:
            return .noResults
        case .unsupported:
            return .unsupported
        case .running, .partial, .availabilityError, .technicalError, .cancelled:
            return nil
        }
    }
}

nonisolated enum GraphChatCopySourcePolicy: Hashable, Sendable {
    case none
    case compactValidatedCount
}

nonisolated struct GraphChatCopyPayload: Hashable, Sendable {
    let text: String
    let includesCompactSourceMetadata: Bool
}

nonisolated enum GraphChatCopyContentBuilder {
    static let maximumCopyLength = 16_000

    static func payload(
        for state: GraphChatAssistantMessageState,
        sourcePolicy: GraphChatCopySourcePolicy = .compactValidatedCount
    ) -> GraphChatCopyPayload? {
        guard state.isTerminal,
              let answer = state.answer else {
            return nil
        }

        let internalIdentifierTokens = internalIdentifierTokens(in: answer)
        var blocks: [String] = []
        appendDistinct(
            redacted(answer.directAnswer, tokens: internalIdentifierTokens),
            to: &blocks
        )

        for section in answer.sections {
            let text = normalized(
                redacted(section.text, tokens: internalIdentifierTokens)
            )
            guard text.isEmpty == false else {
                continue
            }
            if let title = section.title.map({ value in
                normalized(redacted(value, tokens: internalIdentifierTokens))
            }), title.isEmpty == false {
                appendDistinct("\(title)\n\(text)", to: &blocks)
            } else {
                appendDistinct(text, to: &blocks)
            }
        }

        if case .clarification(let clarification) = answer.state,
           clarification.options.isEmpty == false {
            let optionLines = clarification.options.compactMap { option -> String? in
                let title = normalized(
                    redacted(option.title, tokens: internalIdentifierTokens)
                )
                return title.isEmpty ? nil : "• \(title)"
            }
            if optionLines.isEmpty == false {
                appendDistinct(
                    "Optionen\n\(optionLines.joined(separator: "\n"))",
                    to: &blocks
                )
            }
        }

        if answer.appliedFilters.isEmpty == false {
            let filterLines = answer.appliedFilters.compactMap { filter -> String? in
                let fieldName = normalized(
                    redacted(filter.fieldName, tokens: internalIdentifierTokens)
                )
                let operation = normalized(
                    redacted(filter.operationDescription, tokens: internalIdentifierTokens)
                )
                let value = filter.valueDescription.map { rawValue in
                    normalized(redacted(rawValue, tokens: internalIdentifierTokens))
                }
                guard fieldName.isEmpty == false,
                      operation.isEmpty == false else {
                    return nil
                }
                if let value, value.isEmpty == false {
                    return "• \(fieldName): \(operation) \(value)"
                }
                return "• \(fieldName): \(operation)"
            }
            if filterLines.isEmpty == false {
                appendDistinct(
                    "Angewendete Filter\n\(filterLines.joined(separator: "\n"))",
                    to: &blocks
                )
            }
        }

        var includesSourceMetadata = false
        if sourcePolicy == .compactValidatedCount,
           answer.evidence.isEmpty == false {
            includesSourceMetadata = true
            let count = Set(answer.evidence.map(\.sourceReference)).count
            let sourceLine = count == 1
                ? "Quellenhinweis: 1 validierte Graphquelle"
                : "Quellenhinweis: \(count) validierte Graphquellen"
            appendDistinct(sourceLine, to: &blocks)
        }

        let combined = normalized(blocks.joined(separator: "\n\n"))
        guard combined.isEmpty == false else {
            return nil
        }
        return GraphChatCopyPayload(
            text: String(combined.prefix(maximumCopyLength)),
            includesCompactSourceMetadata: includesSourceMetadata
        )
    }

    private static func internalIdentifierTokens(
        in answer: GraphChatAnswer
    ) -> Set<String> {
        var tokens = Set(answer.sections.flatMap { section in
            section.evidenceIDs.map { $0.rawValue.uuidString }
        })
        for evidence in answer.evidence {
            tokens.insert(evidence.id.rawValue.uuidString)
            tokens.insert(evidence.sourceReference.graphID.uuidString)
            tokens.insert(evidence.sourceReference.sourceID.uuidString)
            if let nodeID = evidence.sourceReference.node?.id {
                tokens.insert(nodeID.uuidString)
            }
            if let ownerID = evidence.sourceReference.owner?.id {
                tokens.insert(ownerID.uuidString)
            }
            if let fieldID = evidence.sourceReference.fieldID {
                tokens.insert(fieldID.uuidString)
            }
            if let linkID = evidence.sourceReference.linkID {
                tokens.insert(linkID.uuidString)
            }
            if let attachmentID = evidence.sourceReference.attachmentID {
                tokens.insert(attachmentID.uuidString)
            }
            for fieldValue in evidence.fieldValues {
                if let fieldID = fieldValue.fieldID {
                    tokens.insert(fieldID.uuidString)
                }
            }
        }
        return tokens
    }

    private static func redacted(
        _ value: String,
        tokens: Set<String>
    ) -> String {
        tokens.reduce(value) { partialResult, token in
            partialResult.replacingOccurrences(
                of: token,
                with: "Graphquelle",
                options: .caseInsensitive
            )
        }
    }

    private static func appendDistinct(
        _ value: String,
        to blocks: inout [String]
    ) {
        let normalizedValue = normalized(value)
        guard normalizedValue.isEmpty == false,
              blocks.contains(normalizedValue) == false else {
            return
        }
        blocks.append(normalizedValue)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum GraphChatFeedbackCategory: String, CaseIterable, Hashable, Sendable {
    case helpful
    case incomplete
    case wrongSource
    case misunderstoodQuestion

    var title: String {
        switch self {
        case .helpful:
            return "Hilfreich"
        case .incomplete:
            return "Unvollständig"
        case .wrongSource:
            return "Falsche Quelle"
        case .misunderstoodQuestion:
            return "Frage missverstanden"
        }
    }

    var systemImage: String {
        switch self {
        case .helpful:
            return "hand.thumbsup"
        case .incomplete:
            return "text.badge.minus"
        case .wrongSource:
            return "link.badge.plus"
        case .misunderstoodQuestion:
            return "questionmark.bubble"
        }
    }
}

nonisolated enum GraphChatFeedbackAnswerState: String, CaseIterable, Hashable, Sendable {
    case answer
    case clarification
    case noResults
    case unsupported
}

nonisolated enum GraphChatFeedbackScopeType: String, CaseIterable, Hashable, Sendable {
    case graph
    case entity
    case node
    case selection

    init(scope: GraphChatScope) {
        switch scope.target {
        case .graph:
            self = .graph
        case .entity:
            self = .entity
        case .node:
            self = .node
        case .selection:
            self = .selection
        }
    }
}

nonisolated struct GraphChatFeedbackRecord: Hashable, Sendable, Identifiable {
    let localMessageID: UUID
    let category: GraphChatFeedbackCategory
    let answerState: GraphChatFeedbackAnswerState
    let scopeType: GraphChatFeedbackScopeType
    let toolCategories: [GraphChatToolKind]
    let createdAt: Date

    var id: UUID {
        localMessageID
    }

    init(
        localMessageID: UUID,
        category: GraphChatFeedbackCategory,
        answerState: GraphChatFeedbackAnswerState,
        scopeType: GraphChatFeedbackScopeType,
        toolCategories: [GraphChatToolKind],
        createdAt: Date = Date()
    ) {
        self.localMessageID = localMessageID
        self.category = category
        self.answerState = answerState
        self.scopeType = scopeType
        self.toolCategories = Array(Set(toolCategories)).sorted {
            $0.rawValue < $1.rawValue
        }
        self.createdAt = createdAt
    }
}

nonisolated struct GraphChatEditResendPlan: Hashable, Sendable {
    let originalMessageID: UUID
    let originalQuestion: String
    let replacementQuestion: String
    let restoreCheckpoint: GraphChatConversationCheckpoint
    let retainedMessages: [GraphChatTranscriptMessage]
    let removedMessageIDs: [UUID]
}

nonisolated struct GraphChatRegenerationPlan: Hashable, Sendable {
    let assistantMessageID: UUID
    let userMessageID: UUID
    let question: String
    let assistantCreatedAt: Date
    let restoreCheckpoint: GraphChatConversationCheckpoint
    let retainedMessages: [GraphChatTranscriptMessage]
    let removedMessageIDs: [UUID]
}

nonisolated enum GraphChatMessageActionPlanner {
    private enum CheckpointResolution {
        case resolved(GraphChatConversationCheckpoint)
        case missing
        case incompatible
    }

    static func editResendPlan(
        messages: [GraphChatTranscriptMessage],
        userMessageID: UUID,
        replacementQuestion: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> GraphChatEditResendPlan? {
        let normalizedQuestion = normalized(replacementQuestion)
        guard normalizedQuestion.isEmpty == false,
              let index = messages.firstIndex(where: { $0.id == userMessageID }),
              case .userQuestion(let originalQuestion) = messages[index].state,
              case .resolved(let checkpoint) = resolveCheckpoint(
                for: messages[index],
                index: index,
                messages: messages,
                graphScope: graphScope,
                chatScope: chatScope
              ) else {
            return nil
        }

        return GraphChatEditResendPlan(
            originalMessageID: userMessageID,
            originalQuestion: originalQuestion,
            replacementQuestion: String(normalizedQuestion.prefix(4_000)),
            restoreCheckpoint: checkpoint,
            retainedMessages: Array(messages.prefix(index)),
            removedMessageIDs: messages[index...].map(\.id)
        )
    }

    static func regenerationPlan(
        messages: [GraphChatTranscriptMessage],
        assistantMessageID: UUID,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> GraphChatRegenerationPlan? {
        guard let assistantIndex = messages.firstIndex(where: { $0.id == assistantMessageID }),
              assistantIndex == messages.indices.last,
              assistantIndex > messages.startIndex,
              case .assistant = messages[assistantIndex].state else {
            return nil
        }

        let userIndex = messages.index(before: assistantIndex)
        guard case .userQuestion(let question) = messages[userIndex].state,
              let checkpoint = regenerationCheckpoint(
                assistantMessage: messages[assistantIndex],
                assistantIndex: assistantIndex,
                userMessage: messages[userIndex],
                userIndex: userIndex,
                messages: messages,
                graphScope: graphScope,
                chatScope: chatScope
              ) else {
            return nil
        }

        return GraphChatRegenerationPlan(
            assistantMessageID: assistantMessageID,
            userMessageID: messages[userIndex].id,
            question: question,
            assistantCreatedAt: messages[assistantIndex].createdAt,
            restoreCheckpoint: checkpoint,
            retainedMessages: Array(messages.prefix(through: userIndex)),
            removedMessageIDs: [assistantMessageID]
        )
    }

    private static func regenerationCheckpoint(
        assistantMessage: GraphChatTranscriptMessage,
        assistantIndex: Int,
        userMessage: GraphChatTranscriptMessage,
        userIndex: Int,
        messages: [GraphChatTranscriptMessage],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> GraphChatConversationCheckpoint? {
        switch resolveCheckpoint(
            for: assistantMessage,
            index: assistantIndex,
            messages: messages,
            graphScope: graphScope,
            chatScope: chatScope
        ) {
        case .resolved(let checkpoint):
            return checkpoint
        case .incompatible:
            return nil
        case .missing:
            break
        }

        guard case .resolved(let checkpoint) = resolveCheckpoint(
            for: userMessage,
            index: userIndex,
            messages: messages,
            graphScope: graphScope,
            chatScope: chatScope
        ) else {
            return nil
        }
        return checkpoint
    }

    private static func resolveCheckpoint(
        for message: GraphChatTranscriptMessage,
        index: Int,
        messages: [GraphChatTranscriptMessage],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> CheckpointResolution {
        if let checkpoint = message.conversationCheckpointBeforeTurn {
            guard checkpoint.belongsTo(graphScope: graphScope, chatScope: chatScope) else {
                return .incompatible
            }
            return .resolved(checkpoint)
        }

        if index == messages.startIndex {
            return .resolved(.initial(graphScope: graphScope, chatScope: chatScope))
        }

        let previousIndex = messages.index(before: index)
        guard let checkpoint = messages[previousIndex].conversationCheckpointAfterTurn else {
            return .missing
        }
        guard checkpoint.belongsTo(graphScope: graphScope, chatScope: chatScope) else {
            return .incompatible
        }
        return .resolved(checkpoint)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct GraphChatEditingState: Hashable, Sendable {
    let userMessageID: UUID
    let originalQuestion: String
}

nonisolated struct GraphChatActionNotice: Hashable, Sendable, Identifiable {
    let id: UUID
    let message: String
    let systemImage: String

    init(
        id: UUID = UUID(),
        message: String,
        systemImage: String
    ) {
        self.id = id
        self.message = message
        self.systemImage = systemImage
    }
}
