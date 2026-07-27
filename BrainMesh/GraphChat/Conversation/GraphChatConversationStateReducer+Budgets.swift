//
//  GraphChatConversationStateReducer+Budgets.swift
//  BrainMesh
//
//  Conversation-state budgets, deterministic eviction, and bounded sanitizing.
//

import Foundation

nonisolated extension GraphChatConversationStateReducer {
    func enforceBudgets(
        _ input: GraphChatConversationState
    ) -> GraphChatConversationStateReduction {
        var state = input
        var evicted = 0

        evicted += trimRecent(&state.turnContexts, limit: policy.maximumTurnContexts)
        evicted += trimRecent(&state.nodeReferences, limit: policy.maximumNodeReferences)
        evicted += trimRecent(&state.entityReferences, limit: policy.maximumEntityReferences)
        evicted += trimRecent(&state.fieldReferences, limit: policy.maximumFieldReferences)
        evicted += trimRecent(&state.resultContexts, limit: policy.maximumResultContexts)

        let resultContentReduction = trimResultContextContents(state.resultContexts)
        state.resultContexts = resultContentReduction.contexts
        evicted += resultContentReduction.evictedItemCount

        let retainedGroupIDs = Set(
            state.resultContexts.flatMap(\.groupReferences).map(\.id)
        )
        state.groupReferences = state.groupReferences.filter {
            retainedGroupIDs.contains($0.id)
        }

        let retainedResultIDs = Set(state.resultContexts.map(\.id))
        state.turnContexts = state.turnContexts.map { turn in
            GraphChatConversationTurnContext(
                id: turn.id,
                completedAt: turn.completedAt,
                toolKinds: turn.toolKinds,
                resultContextIDs: turn.resultContextIDs.filter(retainedResultIDs.contains),
                evidenceIDs: boundedEvidenceIDs(turn.evidenceIDs),
                technicalDescription: boundedTechnicalDescription(turn.technicalDescription)
            )
        }

        state.nodeReferences = state.nodeReferences.map { reference in
            GraphChatConversationNodeReference(
                node: reference.node,
                label: boundedLabel(reference.label),
                ownerEntityID: reference.ownerEntityID,
                evidenceIDs: boundedEvidenceIDs(reference.evidenceIDs)
            )
        }
        state.entityReferences = state.entityReferences.map { reference in
            GraphChatConversationEntityReference(
                entityID: reference.entityID,
                name: boundedLabel(reference.name),
                alias: reference.alias
            )
        }
        state.fieldReferences = state.fieldReferences.map { reference in
            GraphChatConversationFieldReference(
                fieldID: reference.fieldID,
                entityID: reference.entityID,
                name: boundedLabel(reference.name),
                type: reference.type,
                unit: reference.unit.map(boundedLabel),
                alias: reference.alias
            )
        }
        state.groupReferences = state.groupReferences.map(sanitizedGroup)

        state.referenceTargets = sanitizedTargets(state.referenceTargets, state: state)
        if let clarification = state.pendingClarification {
            let known = knownReferenceKeys(in: state)
            let options = clarification.options.filter { option in
                if clarification.decision == .foundationalIntent {
                    return option.foundationalSelection != nil
                }
                switch option.proposal {
                case .alias:
                    return true
                case .validatedScope(let resolvedScope):
                    guard
                        resolvedScope.graphScope == state.graphScope,
                        resolvedScope.chatScope == state.chatScope,
                        resolvedScope.conversationID == state.conversationID
                    else {
                        return false
                    }
                    if let sourceResultID =
                        resolvedScope.revision.sourceResultID
                    {
                        guard
                            let result = state.resultContexts.first(where: {
                                $0.id == sourceResultID
                            }),
                            result.references.count
                                == resolvedScope.revision
                                    .sourceReferenceCount
                        else {
                            return false
                        }
                    }
                    return resolvedScope.nodes.allSatisfy { node in
                        known.contains(
                            GraphChatConversationReference.node(node).stableKey
                        )
                    }
                case .latestResults, .latestResultsSubset, .ordinal, .lastEntity, .lastField, .lastGroup,
                    .lastNode, .lastCompared:
                    return known.isEmpty == false
                }
            }
            state.pendingClarification =
                options.isEmpty
                ? nil
                : sanitizedClarification(
                    GraphChatPendingClarification(
                        id: clarification.id,
                        decision: clarification.decision,
                        options: options,
                        sourceTurnID: clarification.sourceTurnID,
                        graphScope: clarification.graphScope,
                        chatScope: clarification.chatScope,
                        continuationOperation: clarification.continuationOperation,
                        continuationQuestion: clarification.continuationQuestion,
                        createdAt: clarification.createdAt,
                        expiresAt: clarification.expiresAt
                    )
                )
        }
        if let comparison = state.lastComparison {
            let known = knownReferenceKeys(in: state)
            let references = comparison.references.filter {
                known.contains($0.stableKey)
            }
            state.lastComparison =
                references.isEmpty
                ? nil
                : GraphChatConversationComparisonContext(
                    references: Array(references.prefix(policy.maximumComparisonReferences)),
                    technicalDescription: boundedTechnicalDescription(
                        comparison.technicalDescription
                    )
                )
        }
        state.budgetEvictionCount += evicted
        return GraphChatConversationStateReduction(
            state: state,
            evictedItemCount: evicted
        )
    }

    func trimResultContextContents(
        _ contexts: [GraphChatConversationResultContext]
    ) -> (contexts: [GraphChatConversationResultContext], evictedItemCount: Int) {
        var remainingResultReferences = policy.maximumResultReferences
        var remainingGroupReferences = policy.maximumGroupReferences
        var reversed: [GraphChatConversationResultContext] = []
        var evicted = 0

        for context in contexts.reversed() {
            let retainedReferences = Array(
                context.references.prefix(remainingResultReferences)
            )
            let retainedGroups = Array(
                context.groupReferences.prefix(remainingGroupReferences)
            ).map(sanitizedGroup)
            evicted += max(0, context.references.count - retainedReferences.count)
            evicted += max(0, context.groupReferences.count - retainedGroups.count)
            remainingResultReferences = max(
                0,
                remainingResultReferences - retainedReferences.count
            )
            remainingGroupReferences = max(
                0,
                remainingGroupReferences - retainedGroups.count
            )
            reversed.append(
                GraphChatConversationResultContext(
                    id: context.id,
                    kind: context.kind,
                    state: context.state,
                    entityID: context.entityID,
                    references: retainedReferences,
                    groupReferences: retainedGroups,
                    evidenceIDs: boundedEvidenceIDs(context.evidenceIDs),
                    appliedFilters: context.appliedFilters,
                    technicalDescription: boundedTechnicalDescription(
                        context.technicalDescription
                    )
                )
            )
        }
        return (Array(reversed.reversed()), evicted)
    }

    func sanitizedGroup(
        _ group: GraphChatConversationGroupReference
    ) -> GraphChatConversationGroupReference {
        GraphChatConversationGroupReference(
            id: group.id,
            fieldID: group.fieldID,
            fieldName: group.fieldName.map(boundedLabel),
            valueDescription: boundedLabel(group.valueDescription),
            count: group.count,
            evidenceIDs: boundedEvidenceIDs(group.evidenceIDs),
            memberNodes: Array(
                group.memberNodes.prefix(policy.maximumResultReferences)
            )
        )
    }

    func trimRecent<T>(
        _ values: inout [T],
        limit: Int
    ) -> Int {
        guard values.count > limit else {
            return 0
        }
        let evicted = values.count - limit
        values = Array(values.suffix(limit))
        return evicted
    }
    func sanitizedClarification(
        _ clarification: GraphChatPendingClarification
    ) -> GraphChatPendingClarification {
        let options = Array(clarification.options.prefix(8)).map { option in
            GraphChatPendingClarificationOption(
                id: bounded(option.id, limit: 64),
                title: boundedLabel(option.title),
                proposal: option.proposal,
                foundationalSelection: option.foundationalSelection
            )
        }
        return GraphChatPendingClarification(
            id: clarification.id,
            decision: clarification.decision,
            options: options,
            sourceTurnID: clarification.sourceTurnID,
            graphScope: clarification.graphScope,
            chatScope: clarification.chatScope,
            continuationOperation: clarification.continuationOperation,
            continuationQuestion: bounded(clarification.continuationQuestion, limit: 500),
            createdAt: clarification.createdAt,
            expiresAt: clarification.expiresAt
        )
    }

    func boundedEvidenceIDs(
        _ values: [GraphEvidenceID]
    ) -> [GraphEvidenceID] {
        var seen = Set<GraphEvidenceID>()
        return Array(
            values.filter { seen.insert($0).inserted }
                .prefix(policy.maximumEvidenceIDsPerReference)
        )
    }

    func boundedTechnicalDescription(_ value: String) -> String {
        bounded(value, limit: policy.maximumTechnicalDescriptionLength)
    }

    func boundedLabel(_ value: String) -> String {
        bounded(value, limit: policy.maximumLabelLength)
    }

    func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit))
    }
}
