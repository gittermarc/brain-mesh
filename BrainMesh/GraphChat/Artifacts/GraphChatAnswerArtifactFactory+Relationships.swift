//
//  GraphChatAnswerArtifactFactory+Relationships.swift
//  BrainMesh
//
//  Deterministic projection of locally executed relationships.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func relationships(
        output: GraphChatRelationshipOutput,
        plan: GraphChatRelationshipPlan,
        budget:
            GraphChatAnswerArtifactFactoryBudget =
                .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.center.nodeKey
                == plan.centerNode.node,
              output.evidenceIDs.contains(
                output.centerEvidenceID
              ) else {
            return nil
        }
        let centerEvidenceID =
            output.centerEvidenceID
        let included = Array(
            output.connections.prefix(
                budget.maximumRows
            )
        )
        let groupCounts = Dictionary(
            grouping: included,
            by: parallelKey
        ).mapValues(\.count)
        var nextOrdinal = [String: Int]()
        let connections = included.map {
            connection
            -> GraphChatAnswerArtifactRelationshipConnection
            in
            let key = parallelKey(connection)
            let ordinal =
                (nextOrdinal[key] ?? 0) + 1
            nextOrdinal[key] = ordinal
            let target =
                GraphChatAnswerArtifactNavigationTarget
                    .openNode(
                        graphScope:
                            plan.graphScope,
                        node:
                            connection
                                .counterpart
                                .nodeKey
                    )
            return GraphChatAnswerArtifactRelationshipConnection(
                id:
                    GraphChatAnswerArtifactItemID(
                        rawValue:
                            connection.id
                    ),
                linkID: connection.id,
                direction:
                    connection.direction,
                sourceLabel:
                    connection.sourceLabel,
                targetLabel:
                    connection.targetLabel,
                counterpartNode:
                    connection
                        .counterpart.nodeKey,
                counterpartLabel:
                    connection
                        .counterpart.visibleName,
                counterpartOwnerEntityID:
                    ownerEntityID(
                        connection.counterpart
                    ),
                note: connection.note,
                parallelOrdinal: ordinal,
                parallelCount:
                    groupCounts[key] ?? 1,
                navigationTargets: [
                    target,
                    .focusNodeInGraph(
                        graphScope:
                            plan.graphScope,
                        node:
                            connection
                                .counterpart
                                .nodeKey
                    ),
                ],
                evidence:
                    GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: [
                            connection
                                .evidenceID,
                        ]
                    )
            )
        }
        let identityEvidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [
                    centerEvidenceID,
                ]
            )
        let evidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs:
                    identityEvidence
                        .evidenceIDs
                    + connections.flatMap {
                        $0.evidence.evidenceIDs
                    }
            )
        let artifactWasLimited =
            included.count < output.connections.count
        let resultWindow =
            GraphChatResultWindow(
                totalCount:
                    output.resultWindow
                        .totalCount,
                returnedCount:
                    connections.count,
                limit:
                    artifactWasLimited
                    ? min(
                        output.resultWindow.limit
                            ?? budget.maximumRows,
                        budget.maximumRows
                    )
                    : output.resultWindow
                        .limit,
                limitReached:
                    output.resultWindow
                        .limitReached
                    || artifactWasLimited,
                limitSources:
                    output.resultWindow
                        .limitSources
                    + (
                        artifactWasLimited
                        ? [.source]
                        : []
                    )
            )
        let title =
            plan.responseLanguage == .german
            ? "Direkte Verbindungen von \(output.center.visibleName)"
            : "Direct connections of \(output.center.visibleName)"
        let centerTarget =
            GraphChatAnswerArtifactNavigationTarget
                .openNode(
                    graphScope: plan.graphScope,
                    node:
                        output.center.nodeKey
                )
        let payload =
            GraphChatAnswerArtifactRelationshipPayload(
                language:
                    plan.responseLanguage,
                request: plan.request,
                direction: plan.direction,
                centerNode:
                    output.center.nodeKey,
                centerLabel:
                    output.center.visibleName,
                centerEntityID:
                    plan.centerEntity.id,
                centerEntityLabel:
                    plan.centerEntity
                        .displayName,
                counterpartEntityID:
                    plan.counterpartEntity?.id,
                counterpartEntityLabel:
                    plan.counterpartEntity?
                        .displayName,
                counterpartNode:
                    plan.counterpartNode?.node,
                counterpartNodeLabel:
                    plan.counterpartNode?
                        .displayName,
                notePredicate:
                    plan.notePredicate,
                connections: connections,
                resultWindow:
                    resultWindow,
                resultMetadata:
                    resultMetadata(
                        sourceWindow:
                            output.resultWindow,
                        includedCount:
                            connections.count,
                        sourceReason:
                            .toolLimit,
                        fallbackLimit:
                            plan.limits
                                .resultLimit
                    ),
                centerNavigationTarget:
                    centerTarget,
                identityEvidence:
                    identityEvidence,
                evidence: evidence
            )
        return GraphChatAnswerArtifactDraft(
            graphScope: plan.graphScope,
            title: title,
            payload:
                .relationship(payload),
            evidence: evidence,
            navigationTargets: [
                centerTarget,
                .focusNodeInGraph(
                    graphScope:
                        plan.graphScope,
                    node:
                        output.center
                            .nodeKey
                ),
            ]
        )
    }

    private static func parallelKey(
        _ connection:
            GraphChatRelationshipConnection
    ) -> String {
        [
            String(
                connection
                    .counterpart.kind
                    .rawValue
            ),
            connection.counterpart
                .nodeKey.id.uuidString,
            connection.direction.rawValue,
        ].joined(separator: ":")
    }

    private static func ownerEntityID(
        _ node: GraphNodeSummaryDTO
    ) -> UUID? {
        switch node.kind {
        case .entity:
            return node.nodeKey.id
        case .attribute:
            return node.ownerEntityID
        }
    }
}
