//
//  GraphChatAnswerArtifactFactory+NodeNeighbors.swift
//  BrainMesh
//
//  Deterministic node detail and neighbor artifacts.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func nodeDetails(
        output: GetNodeOutput,
        graphScope: GraphScope,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard
            let baseEvidenceID =
                output.evidenceIDs.first
        else {
            return nil
        }
        let nodeTarget =
            GraphChatAnswerArtifactNavigationTarget
                .openNode(
                    graphScope: graphScope,
                    node: output.node
                )
        let details = Array(
            output.detailValues.prefix(
                budget.maximumRows
            )
        ).map { detail in
            GraphChatAnswerArtifactNodeProfileDetailValue(
                id:
                    GraphChatAnswerArtifactItemID(
                        rawValue:
                            detail.valueID
                    ),
                fieldID: detail.fieldID,
                fieldName:
                    detail.fieldName,
                fieldType:
                    detail.fieldType,
                value:
                    artifactValue(
                        detail.value,
                        field: FieldInfo(
                            id: detail.fieldID,
                            name:
                                detail.fieldName,
                            type:
                                detail.fieldType,
                            unit: detail.unit,
                            choiceOptions: []
                        )
                    ),
                unit: detail.unit,
                evidence:
                    GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: [
                            detail.evidenceID,
                        ]
                    )
            )
        }
        let incoming = Array(
            output.links.filter {
                $0.direction == .incoming
            }.prefix(budget.maximumRows)
        ).map {
            profileConnection(
                $0,
                center: output.node,
                graphScope: graphScope
            )
        }
        let outgoing = Array(
            output.links.filter {
                $0.direction == .outgoing
            }.prefix(budget.maximumRows)
        ).map {
            profileConnection(
                $0,
                center: output.node,
                graphScope: graphScope
            )
        }
        let attachments = Array(
            output.attachments.prefix(
                budget.maximumRows
            )
        ).map {
            GraphChatAnswerArtifactNodeProfileAttachment(
                id:
                    GraphChatAnswerArtifactItemID(
                        rawValue: $0.id
                    ),
                contentKind:
                    $0.contentKind,
                title: $0.title,
                originalFilename:
                    $0.originalFilename,
                contentTypeIdentifier:
                    $0.contentTypeIdentifier,
                fileExtension:
                    $0.fileExtension,
                byteCount: $0.byteCount,
                evidence:
                    GraphChatAnswerArtifactEvidenceBinding(
                        evidenceIDs: [
                            $0.evidenceID,
                        ]
                    )
            )
        }
        let notes:
            GraphChatAnswerArtifactNodeProfileNotes?
        if
            let evidenceID =
                output.notesEvidenceID,
            output.notes
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty == false
        {
            notes =
                GraphChatAnswerArtifactNodeProfileNotes(
                    text: output.notes,
                    evidence:
                        GraphChatAnswerArtifactEvidenceBinding(
                            evidenceIDs: [
                                evidenceID,
                            ]
                        )
                )
        } else {
            notes = nil
        }
        let identityEvidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [
                    baseEvidenceID,
                ]
            )
        let evidence =
            GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs:
                    identityEvidence.evidenceIDs
                    + (notes?.evidence
                        .evidenceIDs ?? [])
                    + details.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + incoming.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + outgoing.flatMap {
                        $0.evidence.evidenceIDs
                    }
                    + attachments.flatMap {
                        $0.evidence.evidenceIDs
                    }
            )
        let owner =
            output.owner.flatMap {
                owner ->
                    GraphChatAnswerArtifactNodeProfileOwner?
                in
                guard
                    let label = owner.label?
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        ),
                    label.isEmpty == false
                else {
                    return nil
                }
                return GraphChatAnswerArtifactNodeProfileOwner(
                    label: label,
                    navigationTarget:
                        .openNode(
                            graphScope:
                                graphScope,
                            node: NodeRefKey(
                                kind: .entity,
                                id:
                                    owner
                                    .entityID
                            )
                        )
                )
            }
        let payload =
            GraphChatAnswerArtifactNodeProfilePayload(
                node: output.node,
                visibleName:
                    output.visibleName,
                displayName:
                    output.label,
                owner: owner,
                notes: notes,
                detailValues: details,
                incomingConnections:
                    incoming,
                outgoingConnections:
                    outgoing,
                attachments:
                    attachments,
                detailValueMetadata:
                    resultMetadata(
                        sourceWindow:
                            output
                                .detailValueWindow,
                        includedCount:
                            details.count,
                        sourceReason:
                            .toolLimit
                    ),
                incomingConnectionMetadata:
                    resultMetadata(
                        sourceWindow:
                            output
                                .incomingLinkWindow,
                        includedCount:
                            incoming.count,
                        sourceReason:
                            .toolLimit
                    ),
                outgoingConnectionMetadata:
                    resultMetadata(
                        sourceWindow:
                            output
                                .outgoingLinkWindow,
                        includedCount:
                            outgoing.count,
                        sourceReason:
                            .toolLimit
                    ),
                attachmentMetadata:
                    resultMetadata(
                        sourceWindow:
                            output
                                .attachmentWindow,
                        includedCount:
                            attachments.count,
                        sourceReason:
                            .toolLimit
                    ),
                nodeNavigationTarget:
                    nodeTarget,
                identityEvidence:
                    identityEvidence,
                evidence: evidence
            )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: output.label,
            payload:
                .nodeProfile(payload),
            evidence: evidence,
            navigationTargets: [
                nodeTarget,
                .focusNodeInGraph(graphScope: graphScope, node: output.node)
            ]
        )
    }

    private static func profileConnection(
        _ connection:
            GraphChatNodeLinkMetadata,
        center: NodeRefKey,
        graphScope: GraphScope
    ) ->
        GraphChatAnswerArtifactNodeProfileConnection
    {
        let counterpart =
            connection.direction == .incoming
            ? connection.source
            : connection.target
        let counterpartLabel =
            connection.direction == .incoming
            ? connection.sourceLabel
            : connection.targetLabel
        return GraphChatAnswerArtifactNodeProfileConnection(
            id:
                GraphChatAnswerArtifactItemID(
                    rawValue: connection.id
                ),
            direction:
                connection.direction,
            sourceLabel:
                connection.sourceLabel,
            targetLabel:
                connection.targetLabel,
            counterpartLabel:
                counterpartLabel,
            counterpartNavigationTarget:
                counterpart == center
                ? nil
                : .openNode(
                    graphScope:
                        graphScope,
                    node: counterpart
                ),
            note: connection.note,
            evidence:
                GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: [
                        connection.evidenceID,
                    ]
                )
        )
    }

    static func neighbors(
        output: GetNeighborsOutput,
        graphScope: GraphScope,
        requestedLimit: Int,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.connections.isEmpty == false,
              let centerEvidenceID = output.evidenceIDs.first else {
            return nil
        }
        let strings = Strings(language)
        let includedConnections = Array(output.connections.prefix(budget.maximumRows))
        let rows = includedConnections.map { connection in
            let direction = connection.direction == .incoming
                ? strings.incoming
                : strings.outgoing
            return GraphChatAnswerArtifactListRow(
                id: GraphChatAnswerArtifactItemID(rawValue: connection.id),
                primaryText: connection.neighborLabel,
                secondaryText: connection.note.map { "\(direction): \($0)" } ?? direction,
                navigationTargets: [
                    .openNode(graphScope: graphScope, node: connection.neighbor),
                    .focusNodeInGraph(graphScope: graphScope, node: connection.neighbor)
                ],
                evidence: GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: [connection.evidenceID]
                )
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [centerEvidenceID] + output.connections.map(\.evidenceID)
        )
        let title = strings.neighbors(output.center.label)
        let payload = GraphChatAnswerArtifactResultListPayload(
            title: title,
            rows: rows,
            resultMetadata: resultMetadata(
                sourceWindow: output.resultWindow,
                includedCount: rows.count,
                sourceReason: .toolLimit,
                fallbackLimit: requestedLimit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: title,
            payload: .resultList(payload),
            evidence: evidence,
            navigationTargets: rows.flatMap(\.navigationTargets)
        )
    }

}
