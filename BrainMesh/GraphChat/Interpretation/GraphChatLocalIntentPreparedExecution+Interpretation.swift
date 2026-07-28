//
//  GraphChatLocalIntentPreparedExecution+Interpretation.swift
//  BrainMesh
//
//  Reconstructs a presentation interpretation only from trusted execution
//  state retained after the local kernel has revalidated and run an intent.
//

import Foundation

nonisolated extension GraphChatLocalIntentPreparedExecution {
    func resolvedIntentInterpretation(
        timeZone: TimeZone
    ) async -> GraphChatIntentInterpretation? {
        guard
            primaryResult.isEligibleAsPrimary,
            primaryResult.completionStatus
                != .unverified,
            primaryResult.belongsTo(
                requestID:
                    intent.binding.requestID,
                graphScope:
                    intent.scope.graphScope,
                chatScope:
                    intent.scope.chatScope,
                artifactSessionID:
                    artifactContext.sessionID,
                transactionID:
                    artifactContext.transactionID
            )
        else {
            return nil
        }

        let state =
            await conversationTransaction
                .snapshot()
        let baseState =
            await conversationTransaction
                .baseSnapshot()
        guard
            state.conversationID
                == intent.binding.conversationID,
            state.graphScope
                == intent.scope.graphScope,
            state.chatScope
                == intent.scope.chatScope,
            baseState.conversationID
                == state.conversationID,
            baseState.graphScope
                == state.graphScope,
            baseState.chatScope
                == state.chatScope
        else {
            return nil
        }
        let latestResult =
            state.resultContexts.last.flatMap {
                candidate in
                baseState.resultContexts.contains(
                    where: {
                        $0.id == candidate.id
                    }
                )
                ? nil
                : candidate
            }

        let witness:
            GraphChatIntentInterpretationExecutionWitness
        switch (
            intent.kind,
            primaryResult.tool
        ) {
        case (.findNodes, .searchGraph):
            guard latestResult?.kind == .search else {
                return nil
            }
            witness = .search

        case (
            .entityCollection,
            .queryDetailValues
        ),
            (
                .countOrGroup,
                .queryDetailValues
            ),
            (
                .narrowResultSet,
                .queryDetailValues
            ):
            guard
                latestResult?.kind == .query,
                let plan =
                    state.lastValidatedQueryPlan
            else {
                return nil
            }
            witness = .query(plan)

        case (
            .nodeDetails,
            .queryDetailValues
        ):
            guard
                latestResult?.kind == .query,
                let plan =
                    state.lastValidatedQueryPlan
            else {
                return nil
            }
            witness = .query(plan)

        case (.nodeDetails, .getNode):
            guard
                case .nodeDetails(let details) =
                    intent.payload
            else {
                return nil
            }
            if primaryResult.completionStatus
                != .noResults {
                guard
                    latestResult?.kind == .node,
                    latestResult?.references
                        .contains(where: {
                            $0.reference
                                == .node(
                                    details.node.node
                                )
                        }) == true
                else {
                    return nil
                }
            }
            witness = .node(details.node)

        case (
            .compareNodes,
            .queryDetailValues
        ):
            guard
                latestResult?.kind == .comparison,
                let plan =
                    state.lastValidatedQueryPlan,
                let nodes = comparisonNodes(
                    in: state
                ),
                nodes == intent.payload.nodes
                    .map(\.node)
            else {
                return nil
            }
            witness = .query(plan)

        case (.compareNodes, .getNode):
            let nodes =
                intent.payload.nodes.map(\.node)
            guard
                latestResult?.kind == .comparison,
                let revalidatedNodes =
                    comparisonNodes(
                    in: state
                ),
                revalidatedNodes == nodes
            else {
                return nil
            }
            witness = .comparison(nodes)

        case (
            .inspectGraphState,
            .graphStats
        ):
            guard
                latestResult?.kind == .stats,
                case .inspectGraphState(
                    let graphState
                ) = intent.payload
            else {
                return nil
            }
            witness =
                .graphState(
                    graphState.aspect
                )

        default:
            return nil
        }

        return GraphChatIntentInterpretationBuilder(
            timeZone: timeZone
        ).executionInterpretation(
            intent: intent,
            witness: witness
        )
    }

    private func comparisonNodes(
        in state: GraphChatConversationState
    ) -> [NodeRefKey]? {
        guard let comparison =
                state.lastComparison
        else {
            return nil
        }
        let nodes = comparison.references
            .compactMap { reference in
                if case .node(let node) =
                    reference {
                    return node
                }
                return nil
            }
        guard nodes.count
                == comparison.references.count
        else {
            return nil
        }
        return nodes
    }
}
