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
        timeZone: TimeZone,
        requestQuestion: String
    ) async -> GraphChatIntentInterpretation? {
        guard
            adaptation.readPlan.version
                == .current,
            artifactContext.readPlanVersion
                == adaptation.readPlan.version,
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
            .entityCollection,
            .getNeighbors
        ):
            guard
                let latestResult,
                latestResult.kind == .query,
                let continuationPlan =
                    state.lastValidatedQueryPlan,
                validatedReadPlan.plan
                    .resultContract
                    == .composableNodeCollection
            else {
                return nil
            }
            let resultNodes = latestResult.references
                .compactMap { reference
                    -> NodeRefKey? in
                    guard case .node(let node) =
                            reference.reference else {
                        return nil
                    }
                    return node
                }
            guard
                resultNodes.count
                    == latestResult.references.count,
                case .selection(let continuationNodes) =
                    continuationPlan.scope,
                continuationNodes == resultNodes
            else {
                return nil
            }
            witness = .composableRead(
                validatedReadPlan,
                continuationPlan: continuationPlan
            )

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

        case (.relationships, .getNeighbors):
            guard
                latestResult?.kind
                    == .relationship,
                case .relationships(
                    let relationshipPlan
                ) = intent.payload,
                let relationship =
                    state.lastRelationship,
                relationship.plan
                    == relationshipPlan,
                relationship.resultContextID
                    == latestResult?.id
            else {
                return nil
            }
            witness =
                .relationship(
                    relationshipPlan
                )

        default:
            return nil
        }

        return GraphChatIntentInterpretationBuilder(
            timeZone: timeZone
        ).executionInterpretation(
            intent: intent,
            witness: witness,
            correctionOrigin:
                GraphChatInterpretationCorrectionOrigin(
                    adaptation: adaptation,
                    artifactSessionID:
                        artifactContext
                            .sessionID,
                    requestQuestion:
                        requestQuestion
                )
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
