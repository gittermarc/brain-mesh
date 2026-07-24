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
        guard output.detailValues.isEmpty == false,
              let baseEvidenceID = output.evidenceIDs.first else {
            return nil
        }
        let strings = Strings(language)
        let fieldColumnID = stableItemID("node-detail-field")
        let valueColumnID = stableItemID("node-detail-value")
        let unitColumnID = stableItemID("node-detail-unit")
        let columns = [
            GraphChatAnswerArtifactTableColumn(
                id: fieldColumnID,
                key: "field",
                title: strings.field,
                role: .primary,
                unit: nil,
                valuePresentation: strings.presentation()
            ),
            GraphChatAnswerArtifactTableColumn(
                id: valueColumnID,
                key: "value",
                title: strings.value,
                role: .measure,
                unit: nil,
                valuePresentation: strings.presentation()
            ),
            GraphChatAnswerArtifactTableColumn(
                id: unitColumnID,
                key: "unit",
                title: strings.unit,
                role: .secondary,
                unit: nil,
                valuePresentation: strings.presentation()
            )
        ]
        let nodeTarget = GraphChatAnswerArtifactNavigationTarget.openNode(
            graphScope: graphScope,
            node: output.node
        )
        let includedValues = Array(output.detailValues.prefix(budget.maximumRows))
        let rows = includedValues.map { detail in
            let binding = GraphChatAnswerArtifactEvidenceBinding(
                evidenceIDs: [detail.evidenceID]
            )
            return GraphChatAnswerArtifactTableRow(
                id: GraphChatAnswerArtifactItemID(rawValue: detail.valueID),
                cells: [
                    GraphChatAnswerArtifactTableCell(
                        columnID: fieldColumnID,
                        value: .text(detail.fieldName),
                        evidence: binding
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: valueColumnID,
                        value: artifactValue(
                            detail.value,
                            field: FieldInfo(
                                id: detail.fieldID,
                                name: detail.fieldName,
                                type: detail.fieldType,
                                unit: detail.unit,
                                choiceOptions: []
                            )
                        ),
                        evidence: binding
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: unitColumnID,
                        value: detail.unit.map(GraphChatAnswerArtifactValue.text) ?? .missing,
                        evidence: binding
                    )
                ],
                navigationTarget: nodeTarget,
                evidence: binding
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [baseEvidenceID] + output.detailValues.map(\.evidenceID)
        )
        let payload = GraphChatAnswerArtifactTablePayload(
            title: output.label,
            columns: columns,
            rows: rows,
            sorting: [],
            resultMetadata: resultMetadata(
                sourceWindow: output.detailValueWindow,
                includedCount: rows.count,
                sourceReason: .toolLimit
            ),
            evidence: evidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: output.label,
            payload: .table(payload),
            evidence: evidence,
            navigationTargets: [
                nodeTarget,
                .focusNodeInGraph(graphScope: graphScope, node: output.node)
            ]
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
