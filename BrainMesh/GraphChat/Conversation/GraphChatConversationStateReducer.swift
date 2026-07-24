//
//  GraphChatConversationStateReducer.swift
//  BrainMesh
//
//  Central trust boundary and dispatch entry point for graph-chat conversation state.
//

import Foundation

nonisolated struct GraphChatConversationStateReducer: Sendable {
    let policy: GraphChatConversationStatePolicy

    init(policy: GraphChatConversationStatePolicy = .default) {
        self.policy = policy
    }

    func reduce(
        _ state: GraphChatConversationState,
        event: GraphChatConversationTrustedEvent
    ) throws -> GraphChatConversationStateReduction {
        guard event.graphScope == state.graphScope else {
            throw GraphChatConversationStateError.graphScopeMismatch
        }
        guard event.chatScope == state.chatScope else {
            throw GraphChatConversationStateError.chatScopeMismatch
        }

        var candidate = state
        switch event.payload {
        case .schemaResolved(let schemaContext, let resultState, let evidence):
            try validate(schemaContext: schemaContext, evidence: evidence, state: state)
            applySchema(
                schemaContext,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .searchResolved(let output, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applySearch(
                output,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .queryResolved(let plan, let result, let schemaContext):
            guard plan.graphScope == state.graphScope else {
                throw GraphChatConversationStateError.graphScopeMismatch
            }
            guard
                GraphChatScopeAuthorization.allows(
                    plan: plan,
                    within: state.chatScope
                )
            else {
                throw GraphChatConversationStateError.chatScopeMismatch
            }
            try validate(schemaContext: schemaContext, evidence: result.evidence, state: state)
            applyQuery(
                plan: plan,
                result: result,
                schemaContext: schemaContext,
                eventID: event.id,
                to: &candidate
            )
        case .nodeResolved(let output, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applyNode(
                output,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .neighborsResolved(let output, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applyNeighbors(
                output,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .statsResolved(let output, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applyStats(
                output,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .validatedEvidence(let tool, let resultState, let evidence):
            try validate(evidence: evidence, state: state)
            applyValidatedEvidence(
                tool: tool,
                resultState: resultState,
                evidence: evidence,
                eventID: event.id,
                to: &candidate
            )
        case .comparisonResolved(let references, let technicalDescription):
            applyComparison(
                references: references,
                technicalDescription: technicalDescription,
                to: &candidate
            )
        case .clarificationRequested(let clarification):
            guard clarification.graphScope == state.graphScope else {
                throw GraphChatConversationStateError.graphScopeMismatch
            }
            guard clarification.chatScope == state.chatScope else {
                throw GraphChatConversationStateError.chatScopeMismatch
            }
            candidate.pendingClarification = sanitizedClarification(clarification)
        case .clarificationResolved:
            candidate.pendingClarification = nil
        case .turnCompleted(let completion):
            applyTurnCompletion(completion, to: &candidate)
        }

        let result = enforceBudgets(candidate)
        return GraphChatConversationStateReduction(
            state: result.state,
            evictedItemCount: result.evictedItemCount
        )
    }

    func transition(
        _ state: GraphChatConversationState,
        to newScope: GraphChatScope,
        reason: GraphChatConversationResetReason = .scopeChanged
    ) -> GraphChatConversationStateReduction {
        guard state.graphScope == newScope.graphScope else {
            return GraphChatConversationStateReduction(
                state: .initial(
                    graphScope: newScope.graphScope,
                    chatScope: newScope,
                    resetReason: .graphChanged
                ),
                evictedItemCount: state.turnContexts.count
                    + state.nodeReferences.count
                    + state.entityReferences.count
                    + state.fieldReferences.count
                    + state.resultContexts.count
                    + state.groupReferences.count
            )
        }
        guard state.chatScope != newScope else {
            return GraphChatConversationStateReduction(
                state: state,
                evictedItemCount: 0
            )
        }

        var transitioned = GraphChatConversationState(
            conversationID: state.conversationID,
            graphScope: state.graphScope,
            chatScope: newScope,
            turnContexts: [],
            nodeReferences: state.nodeReferences.filter { allows($0, in: newScope) },
            entityReferences: state.entityReferences,
            fieldReferences: state.fieldReferences,
            resultContexts: [],
            groupReferences: [],
            lastValidatedQueryPlan: nil,
            lastComparison: nil,
            referenceTargets: .empty,
            pendingClarification: nil,
            lastResetReason: reason,
            budgetEvictionCount: state.budgetEvictionCount
        )

        let allowedEntityIDs = Set(
            transitioned.nodeReferences.compactMap(\.ownerEntityID)
                + entityIDsExplicitlyAllowed(by: newScope)
        )
        switch newScope.target {
        case .graph:
            transitioned.nodeReferences = []
        case .entity(let entityID):
            transitioned.entityReferences = transitioned.entityReferences.filter {
                $0.entityID == entityID
            }
            transitioned.fieldReferences = transitioned.fieldReferences.filter {
                $0.entityID == entityID
            }
        case .node, .selection:
            transitioned.entityReferences = transitioned.entityReferences.filter {
                allowedEntityIDs.contains($0.entityID)
            }
            transitioned.fieldReferences = transitioned.fieldReferences.filter {
                allowedEntityIDs.contains($0.entityID)
            }
        }

        switch newScope.context {
        case .detailField(let entityID, let fieldID):
            transitioned.nodeReferences = []
            transitioned.entityReferences = transitioned.entityReferences.filter {
                $0.entityID == entityID
            }
            transitioned.fieldReferences = transitioned.fieldReferences.filter {
                $0.entityID == entityID && $0.fieldID == fieldID
            }

        case .healthFinding(_, let affectedNodes) where affectedNodes.isEmpty:
            transitioned.nodeReferences = []
            transitioned.entityReferences = []
            transitioned.fieldReferences = []

        case .graph, .entity, .node, .selection, .healthFinding:
            break
        }

        let priorCount =
            state.turnContexts.count
            + state.nodeReferences.count
            + state.entityReferences.count
            + state.fieldReferences.count
            + state.resultContexts.count
            + state.groupReferences.count
        let retainedCount =
            transitioned.nodeReferences.count
            + transitioned.entityReferences.count
            + transitioned.fieldReferences.count
        let evicted = max(0, priorCount - retainedCount)
        transitioned.budgetEvictionCount += evicted
        return GraphChatConversationStateReduction(
            state: transitioned,
            evictedItemCount: evicted
        )
    }
}
