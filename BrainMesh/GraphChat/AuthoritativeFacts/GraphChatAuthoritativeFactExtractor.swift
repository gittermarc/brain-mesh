//
//  GraphChatAuthoritativeFactExtractor.swift
//  BrainMesh
//
//  Strict extraction from the revalidated primary result and its typed artifact.
//

import Foundation

nonisolated struct GraphChatAuthoritativeFactExtractor: Sendable {
    func resolve(
        expectation: GraphChatAuthoritativeFactExpectation,
        primaryResult: GraphChatToolExecutionLedgerEntry?,
        source: GraphChatDeterministicAnswerFallbackSource?
    ) -> GraphChatAuthoritativeFactResolution {
        guard expectation.hasIntegrityConflict == false else {
            return .rejected(.integrityConflict)
        }
        guard expectation.hasAmbiguousCardinality == false else {
            return .rejected(.ambiguousCardinality)
        }
        guard let primaryResult,
              let source,
              bindingsMatch(
                expectation: expectation,
                primaryResult: primaryResult
              ) else {
            return .rejected(.revalidationRejected)
        }
        guard primaryResult.kind != .search else {
            return .rejected(.searchOnlyResult)
        }
        guard primaryResult.kind == .query,
              primaryResult.completionStatus == .succeeded,
              source.completionStatus == .succeeded else {
            return .rejected(.missingValue)
        }
        guard source.artifacts.count == 1,
              let artifact = source.artifacts.first else {
            return source.artifacts.isEmpty
                ? .rejected(.revalidationRejected)
                : .rejected(.ambiguousCardinality)
        }
        return fact(
            expectation: expectation,
            primaryResult: primaryResult,
            artifact: artifact,
            evidence: source.evidence
        )
    }

    private func bindingsMatch(
        expectation: GraphChatAuthoritativeFactExpectation,
        primaryResult: GraphChatToolExecutionLedgerEntry
    ) -> Bool {
        let binding = primaryResult.binding
        return expectation.graphScope == binding.request.graphScope
            && expectation.chatScope == binding.request.chatScope
            && expectation.requestID == binding.request.requestID
            && expectation.turnID == binding.request.requestID
    }

    private func fact(
        expectation: GraphChatAuthoritativeFactExpectation,
        primaryResult: GraphChatToolExecutionLedgerEntry,
        artifact: GraphChatAnswerArtifact,
        evidence: [GraphEvidence]
    ) -> GraphChatAuthoritativeFactResolution {
        guard artifact.graphScope == expectation.graphScope,
              artifact.sessionID
                == primaryResult.binding.request.artifactSessionID,
              let query = artifact.querySummary,
              query.entityID == expectation.entityID,
              normalized(query.entityLabel)
                == normalized(expectation.entityDisplayName),
              query.filters.isEmpty,
              query.grouping == nil,
              query.sorting.allSatisfy({ $0.key == "nodeName" }),
              query.includesNodeIdentity,
              query.limit == 1,
              query.aggregation == nil else {
            return .rejected(.revalidationRejected)
        }
        guard query.projection.count == 1,
              query.projection[0].fieldID == expectation.fieldID,
              normalized(query.projection[0].label)
                == normalized(expectation.fieldDisplayName) else {
            return .rejected(.ambiguousCardinality)
        }
        guard case .table(let table) = artifact.payload else {
            return .rejected(.revalidationRejected)
        }
        guard table.rows.count == 1,
              table.resultMetadata.returnedCount == 1,
              table.resultMetadata.totalCount == 1,
              table.resultMetadata.truncation.isTruncated == false,
              let row = table.rows.first else {
            return .rejected(.ambiguousCardinality)
        }
        guard row.id.rawValue == expectation.node.id,
              navigationTarget(
                row.navigationTarget,
                matches: expectation.node,
                graphScope: expectation.graphScope
              ) else {
            return .rejected(.revalidationRejected)
        }

        let primaryColumns = table.columns.filter { $0.role == .primary }
        let fieldColumns = table.columns.filter {
            $0.id.rawValue == expectation.fieldID
        }
        guard primaryColumns.count == 1,
              fieldColumns.count == 1,
              let primaryColumn = primaryColumns.first,
              let fieldColumn = fieldColumns.first,
              normalized(fieldColumn.title)
                == normalized(expectation.fieldDisplayName),
              normalizedOptional(fieldColumn.unit)
                == normalizedOptional(expectation.unit) else {
            return .rejected(.ambiguousCardinality)
        }

        let primaryCells = row.cells.filter {
            $0.columnID == primaryColumn.id
        }
        let valueCells = row.cells.filter {
            $0.columnID == fieldColumn.id
        }
        guard primaryCells.count == 1,
              valueCells.count == 1,
              case .text(let artifactNodeName) = primaryCells[0].value,
              artifactNodeNameMatches(
                artifactNodeName,
                expectation: expectation
              ),
              let valueCell = valueCells.first,
              valueCell.value != .missing else {
            return .rejected(.missingValue)
        }
        guard valueMatchesFieldType(
            valueCell.value,
            fieldType: expectation.fieldType
        ) else {
            return .rejected(.revalidationRejected)
        }
        guard let cellEvidence = valueCell.evidence,
              cellEvidence.evidenceIDs.isEmpty == false else {
            return .rejected(.revalidationRejected)
        }

        let matchingEvidence = evidence.filter {
            evidenceMatches(
                $0,
                matches: expectation,
                artifactValue: valueCell.value,
                allowedIDs: Set(cellEvidence.evidenceIDs)
            )
        }
        guard matchingEvidence.count == 1,
              let authoritativeEvidence = matchingEvidence.first else {
            return matchingEvidence.isEmpty
                ? .rejected(.revalidationRejected)
                : .rejected(.ambiguousCardinality)
        }
        let evidenceIDs = GraphEvidenceCollection(
            [authoritativeEvidence]
        ).ids
        guard evidenceIDs.isEmpty == false else {
            return .rejected(.revalidationRejected)
        }

        return .fact(
            GraphChatAuthoritativeFact(
                binding: GraphChatAuthoritativeFactBinding(
                    graphScope: expectation.graphScope,
                    chatScope: expectation.chatScope,
                    requestID: expectation.requestID,
                    sessionID:
                        primaryResult.binding.request.artifactSessionID,
                    transactionID: primaryResult.binding.transactionID,
                    turnID: expectation.turnID
                ),
                node: expectation.node,
                nodeDisplayName: cleaned(
                    expectation.nodeDisplayName
                ),
                entityID: expectation.entityID,
                entityDisplayName: cleaned(query.entityLabel),
                fieldID: expectation.fieldID,
                fieldDisplayName: cleaned(fieldColumn.title),
                fieldType: expectation.fieldType,
                value: valueCell.value,
                unit: cleanedOptional(fieldColumn.unit),
                evidenceIDs: evidenceIDs,
                artifactIDs: [artifact.id],
                cardinality: .exactlyOne,
                dateTimeZoneIdentifier:
                    expectation.dateTimeZoneIdentifier
            )
        )
    }

    private func artifactNodeNameMatches(
        _ artifactNodeName: String,
        expectation: GraphChatAuthoritativeFactExpectation
    ) -> Bool {
        let normalizedArtifactName = normalized(artifactNodeName)
        if normalizedArtifactName
            == normalized(expectation.nodeDisplayName) {
            return true
        }
        return normalizedArtifactName
            == normalized(
                "\(expectation.entityDisplayName) · \(expectation.nodeDisplayName)"
            )
    }

    private func navigationTarget(
        _ target: GraphChatAnswerArtifactNavigationTarget?,
        matches node: NodeRefKey,
        graphScope: GraphScope
    ) -> Bool {
        guard let target,
              target.graphScope == graphScope else {
            return false
        }
        switch target {
        case .openNode(_, let candidate),
            .focusNodeInGraph(_, let candidate):
            return candidate == node
        case .openEntityList(_, _, _),
            .showResultNodes(_, _, _),
            .openResultFilter(_, _, _, _),
            .highlightNodesInCanvas(_, _),
            .clearCanvasHighlight(_),
            .addNodesToCanvasSelection(_, _),
            .replaceCanvasSelection(_, _),
            .compareNodes(_, _):
            return false
        }
    }

    private func evidenceMatches(
        _ evidence: GraphEvidence,
        matches expectation: GraphChatAuthoritativeFactExpectation,
        artifactValue: GraphChatAnswerArtifactValue,
        allowedIDs: Set<GraphEvidenceID>
    ) -> Bool {
        let reference = evidence.sourceReference
        guard allowedIDs.contains(evidence.id),
              reference.graphID == expectation.graphScope.graphID,
              reference.sourceKind == .detailValue,
              reference.node?.nodeKey == expectation.node,
              reference.owner?.nodeKey
                == NodeRefKey(
                    kind: .entity,
                    id: expectation.entityID
                ),
              reference.fieldID == expectation.fieldID else {
            return false
        }
        let fieldValues = evidence.fieldValues.filter {
            $0.fieldID == expectation.fieldID
                && normalized($0.fieldName)
                    == normalized(expectation.fieldDisplayName)
                && normalizedOptional($0.unit)
                    == normalizedOptional(expectation.unit)
        }
        guard fieldValues.count == 1,
              let fieldValue = fieldValues.first else {
            return false
        }
        return valuesMatch(
            artifactValue,
            evidenceValue: fieldValue.value
        )
    }

    private func valueMatchesFieldType(
        _ value: GraphChatAnswerArtifactValue,
        fieldType: DetailFieldType
    ) -> Bool {
        switch (fieldType, value) {
        case (.singleLineText, .text(_)),
            (.multiLineText, .text(_)),
            (.numberInt, .integer(_)),
            (.numberDouble, .decimal(_)),
            (.date, .date(_)),
            (.toggle, .boolean(_)),
            (.singleChoice, .choice(_)):
            return true
        default:
            return false
        }
    }

    private func valuesMatch(
        _ artifactValue: GraphChatAnswerArtifactValue,
        evidenceValue: GraphEvidenceValue
    ) -> Bool {
        switch (artifactValue, evidenceValue) {
        case (.text(let left), .text(let right)):
            return left == right
        case (.integer(let left), .integer(let right)):
            return left == right
        case (.decimal(let left), .decimal(let right)):
            return left == decimal(right)
        case (.date(let left), .date(let right)):
            return left == right
        case (.boolean(let left), .boolean(let right)):
            return left == right
        case (.choice(let left), .choice(let right)):
            return left.value == right
        default:
            return false
        }
    }

    private func decimal(_ value: Double) -> Decimal {
        Decimal(
            string: String(value),
            locale: Locale(identifier: "en_US_POSIX")
        ) ?? Decimal(value)
    }

    private func normalized(_ value: String) -> String {
        cleaned(value).precomposedStringWithCanonicalMapping
    }

    private func normalizedOptional(_ value: String?) -> String? {
        value.map(normalized).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanedOptional(_ value: String?) -> String? {
        value.map(cleaned).flatMap { $0.isEmpty ? nil : $0 }
    }
}
