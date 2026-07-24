//
//  GraphChatAnswerArtifactFactory+SchemaSearch.swift
//  BrainMesh
//
//  Deterministic schema overview and search result artifacts.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func schemaOverview(
        output: DescribeGraphSchemaOutput,
        schemaContext: GraphSchemaContext,
        evidenceIDs: [GraphEvidenceID],
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.snapshot.entities.isEmpty == false,
              evidenceIDs.isEmpty == false else {
            return nil
        }
        let strings = Strings(language)
        let entityColumnID = stableItemID("schema-entity")
        let attributeCountColumnID = stableItemID("schema-attribute-count")
        let fieldsColumnID = stableItemID("schema-fields")
        let columns = [
            GraphChatAnswerArtifactTableColumn(
                id: entityColumnID,
                key: "entity",
                title: strings.entity,
                role: .primary,
                unit: nil,
                valuePresentation: strings.presentation()
            ),
            GraphChatAnswerArtifactTableColumn(
                id: attributeCountColumnID,
                key: "attributeCount",
                title: strings.entries,
                role: .measure,
                unit: nil,
                valuePresentation: strings.presentation()
            ),
            GraphChatAnswerArtifactTableColumn(
                id: fieldsColumnID,
                key: "fields",
                title: strings.fields,
                role: .secondary,
                unit: nil,
                valuePresentation: strings.presentation()
            )
        ]
        let includedEntities = Array(output.snapshot.entities.prefix(budget.maximumRows))
        let graphEvidence = GraphChatAnswerArtifactEvidenceBinding(evidenceIDs: evidenceIDs)
        let rows = includedEntities.map { entity in
            let resolution = schemaContext.aliases.entity(for: entity.alias)
            let node = resolution.map {
                NodeRefKey(kind: .entity, id: $0.entityID)
            }
            let navigationTarget = node.map {
                GraphChatAnswerArtifactNavigationTarget.openNode(
                    graphScope: schemaContext.graphScope,
                    node: $0
                )
            }
            let fieldDescription = entity.fields.map { field in
                var value = "\(field.name) [\(localizedFieldType(field.type, language: language))]"
                if let unit = field.unit, unit.isEmpty == false {
                    value += " (\(unit))"
                }
                return value
            }.joined(separator: ", ")
            return GraphChatAnswerArtifactTableRow(
                id: resolution.map {
                    GraphChatAnswerArtifactItemID(rawValue: $0.entityID)
                } ?? stableItemID("schema:\(entity.alias.rawValue)"),
                cells: [
                    GraphChatAnswerArtifactTableCell(
                        columnID: entityColumnID,
                        value: .text(entity.name),
                        evidence: graphEvidence
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: attributeCountColumnID,
                        value: .integer(entity.attributeCount),
                        evidence: graphEvidence
                    ),
                    GraphChatAnswerArtifactTableCell(
                        columnID: fieldsColumnID,
                        value: fieldDescription.isEmpty ? .missing : .text(fieldDescription),
                        evidence: graphEvidence
                    )
                ],
                navigationTarget: navigationTarget,
                evidence: graphEvidence
            )
        }
        let sourceWindow = GraphChatResultWindow(
            totalCount: output.snapshot.truncation.sourceEntityCount,
            returnedCount: output.snapshot.entities.count,
            limit: nil,
            limitReached: output.snapshot.truncation.sourceEntityCount
                > output.snapshot.truncation.includedEntityCount,
            limitSource: .source
        )
        let title = strings.schemaOverview(output.snapshot.graphName)
        let payload = GraphChatAnswerArtifactTablePayload(
            title: title,
            columns: columns,
            rows: rows,
            sorting: [],
            resultMetadata: resultMetadata(
                sourceWindow: sourceWindow,
                includedCount: rows.count,
                sourceReason: .sourceLimited
            ),
            evidence: graphEvidence
        )
        return GraphChatAnswerArtifactDraft(
            graphScope: schemaContext.graphScope,
            title: title,
            payload: .table(payload),
            evidence: graphEvidence,
            navigationTargets: rows.compactMap(\.navigationTarget)
        )
    }

    static func searchResults(
        output: SearchGraphOutput,
        graphScope: GraphScope,
        requestedLimit: Int,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        guard output.hits.isEmpty == false else {
            return nil
        }
        let strings = Strings(language)
        let includedHits = Array(output.hits.prefix(budget.maximumRows))
        let rows = includedHits.map { hit in
            GraphChatAnswerArtifactListRow(
                id: GraphChatAnswerArtifactItemID(rawValue: hit.evidenceID.rawValue),
                primaryText: hit.title,
                secondaryText: hit.subtitle.isEmpty ? nil : hit.subtitle,
                navigationTargets: navigationTargets(
                    for: hit.sourceReference,
                    graphScope: graphScope
                ),
                evidence: GraphChatAnswerArtifactEvidenceBinding(
                    evidenceIDs: [hit.evidenceID]
                )
            )
        }
        let evidence = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: output.hits.map(\.evidenceID)
        )
        let title = strings.searchResults(output.query)
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
