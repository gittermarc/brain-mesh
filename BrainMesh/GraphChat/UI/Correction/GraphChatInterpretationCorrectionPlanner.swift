//
//  GraphChatInterpretationCorrectionPlanner.swift
//  BrainMesh
//
//  Transcript binding and Edit-and-Resend-compatible suffix policy for an
//  interpretation correction.
//

import Foundation

nonisolated struct GraphChatInterpretationCorrectionBranchPlan:
    Hashable,
    Sendable
{
    let binding:
        GraphChatInterpretationCorrectionBinding
    let retainedMessages:
        [GraphChatTranscriptMessage]
    let originalUserMessage:
        GraphChatTranscriptMessage
    let removedMessageIDs: [UUID]
}

nonisolated enum GraphChatInterpretationCorrectionPlanner {
    static func plan(
        messages: [GraphChatTranscriptMessage],
        assistantMessageID: UUID,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> GraphChatInterpretationCorrectionBranchPlan? {
        guard
            graphScope == chatScope.graphScope,
            let assistantIndex =
                messages.firstIndex(
                    where: {
                        $0.id
                            == assistantMessageID
                    }
                ),
            assistantIndex
                > messages.startIndex,
            case .assistant(let assistantState) =
                messages[assistantIndex]
                    .state,
            assistantState.isTerminal,
            let answer = assistantState.answer,
            let interpretation =
                answer.interpretation,
            interpretation.isCorrectionEditable,
            let origin =
                interpretation
                    .correctionOrigin
        else {
            return nil
        }

        let userIndex =
            messages.index(
                before: assistantIndex
            )
        guard
            case .userQuestion(let question) =
                messages[userIndex]
                    .state,
            question.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false,
            question.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) == origin.requestQuestion,
            let checkpointBefore =
                checkpointBeforeTurn(
                    assistant:
                        messages[assistantIndex],
                    user:
                        messages[userIndex],
                    userIndex: userIndex,
                    messages: messages,
                    graphScope:
                        graphScope,
                    chatScope:
                        chatScope
                ),
            let currentCheckpoint =
                currentCommittedCheckpoint(
                    messages: messages,
                    graphScope:
                        graphScope,
                    chatScope:
                        chatScope
                ),
            let currentState =
                currentCheckpoint.state,
            currentState.turnContexts
                .contains(
                    where: {
                        $0.id
                            == interpretation
                                .turnBinding
                                .turnID
                    }
                )
        else {
            return nil
        }

        let userMessage =
            GraphChatMessage(
                id: messages[userIndex].id,
                role: .user,
                text: question,
                createdAt:
                    messages[userIndex]
                        .createdAt,
                evidenceIDs: []
            )
        let assistantMessage =
            GraphChatMessage(
                id:
                    messages[assistantIndex]
                        .id,
                role: .assistant,
                text: answer.directAnswer,
                createdAt:
                    messages[assistantIndex]
                        .createdAt,
                evidenceIDs:
                    answer.evidenceIDs
            )
        let originalRequest =
            GraphChatRequest(
                id:
                    interpretation
                        .turnBinding
                        .requestID,
                scope: chatScope,
                messages: [userMessage],
                createdAt:
                    messages[userIndex]
                        .createdAt
            )
        let removedMessages =
            Array(
                messages[assistantIndex...]
            )
        let artifactIDs =
            uniqueArtifactIDs(
                removedMessages
                    .flatMap {
                        message
                        -> [GraphChatAnswerArtifactID] in
                        guard
                            case .assistant(
                                let state
                            ) = message.state,
                            let answer =
                                state.answer
                        else {
                            return []
                        }
                        return answer.artifactIDs
                            + answer.sections
                                .flatMap(
                                    \.artifactIDs
                                )
                    }
            )
        let binding:
            GraphChatInterpretationCorrectionBinding
        do {
            binding =
                try GraphChatInterpretationCorrectionBinding(
                    originalUserMessage:
                        userMessage,
                    originalAssistantMessage:
                        assistantMessage,
                    originalRequest:
                        originalRequest,
                    originalTurnID:
                        interpretation
                            .turnBinding
                            .turnID,
                    conversationID:
                        interpretation
                            .turnBinding
                            .conversationID,
                    graphScope:
                        graphScope,
                    chatScope:
                        chatScope,
                    intentDomainVersion:
                        origin.adaptation
                            .intent.version,
                    originalInterpretation:
                        interpretation,
                    artifactSessionID:
                        origin.artifactSessionID,
                    checkpointBeforeOriginalTurn:
                        checkpointBefore,
                    expectedCurrentCheckpoint:
                        currentCheckpoint,
                    artifactIDsToReplace:
                        artifactIDs
                )
        } catch {
            return nil
        }

        return GraphChatInterpretationCorrectionBranchPlan(
            binding: binding,
            retainedMessages:
                Array(
                    messages.prefix(
                        through:
                            userIndex
                    )
                ),
            originalUserMessage:
                messages[userIndex],
            removedMessageIDs:
                removedMessages.map(\.id)
        )
    }

    private static func checkpointBeforeTurn(
        assistant:
            GraphChatTranscriptMessage,
        user:
            GraphChatTranscriptMessage,
        userIndex: Int,
        messages:
            [GraphChatTranscriptMessage],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> GraphChatConversationCheckpoint? {
        if let checkpoint =
                assistant
                    .conversationCheckpointBeforeTurn
                ?? user
                    .conversationCheckpointBeforeTurn
        {
            return checkpoint.belongsTo(
                graphScope: graphScope,
                chatScope: chatScope
            )
                ? checkpoint
                : nil
        }
        if userIndex == messages.startIndex {
            return .initial(
                graphScope: graphScope,
                chatScope: chatScope
            )
        }
        let previous =
            messages.index(before: userIndex)
        guard let checkpoint =
                messages[previous]
                    .conversationCheckpointAfterTurn,
              checkpoint.belongsTo(
                  graphScope: graphScope,
                  chatScope: chatScope
              )
        else {
            return nil
        }
        return checkpoint
    }

    private static func currentCommittedCheckpoint(
        messages:
            [GraphChatTranscriptMessage],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> GraphChatConversationCheckpoint? {
        messages.reversed()
            .compactMap(
                \.conversationCheckpointAfterTurn
            )
            .first {
                $0.state != nil
                    && $0.belongsTo(
                        graphScope:
                            graphScope,
                        chatScope:
                            chatScope
                    )
            }
    }

    private static func uniqueArtifactIDs(
        _ values:
            [GraphChatAnswerArtifactID]
    ) -> [GraphChatAnswerArtifactID] {
        var seen =
            Set<GraphChatAnswerArtifactID>()
        return values.filter {
            seen.insert($0).inserted
        }
    }
}
