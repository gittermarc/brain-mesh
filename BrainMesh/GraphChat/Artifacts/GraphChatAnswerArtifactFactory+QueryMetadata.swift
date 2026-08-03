//
//  GraphChatAnswerArtifactFactory+QueryMetadata.swift
//  BrainMesh
//
//  Deterministic query summaries, result metadata, and truncation mapping.
//

import Foundation

nonisolated extension GraphChatAnswerArtifactFactory {
    static func querySummary(
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage
    ) -> GraphChatAnswerArtifactQuerySummary {
        let strings = Strings(language)
        let entityLabel = entityName(plan.entityID, schemaContext: schemaContext)
            ?? plan.entityID.uuidString
        let fields = fieldInfoByID(schemaContext)
        let filterSummaries = plan.filters.map { filter in
            let field = fields[filter.fieldID] ?? FieldInfo(
                id: filter.fieldID,
                name: filter.fieldID.uuidString,
                type: filter.fieldType,
                unit: nil,
                choiceOptions: []
            )
            let values = artifactValues(filter.value, field: field)
            return GraphChatAnswerArtifactQueryFilterSummary(
                field: field.summary,
                operation: filter.operation,
                operationLabel: strings.operation(filter.operation),
                values: values,
                valueDescription: values.isEmpty
                    ? nil
                    : values.map { readableLabel($0, strings: strings) }.joined(separator: ", ")
            )
        }
        let projectionFields = projectedFieldIDs(plan).compactMap { fieldID in
            fields[fieldID]?.summary
        }
        let sorting = plan.sorting.map { sort in
            switch sort.key {
            case .nodeName:
                return GraphChatAnswerArtifactQuerySortSummary(
                    key: "nodeName",
                    label: strings.name,
                    direction: sort.direction.artifactDirection,
                    directionLabel: strings.sortDirection(sort.direction)
                )
            case .field(let fieldID):
                return GraphChatAnswerArtifactQuerySortSummary(
                    key: fieldID.uuidString,
                    label: fields[fieldID]?.name ?? fieldID.uuidString,
                    direction: sort.direction.artifactDirection,
                    directionLabel: strings.sortDirection(sort.direction)
                )
            }
        }
        let aggregation: GraphChatAnswerArtifactQueryAggregationSummary?
        let grouping: GraphChatAnswerArtifactQueryFieldSummary?
        switch plan.aggregation {
        case .count:
            aggregation = .count(label: strings.count)
            grouping = nil
        case .minimum(let fieldID):
            let field = fields[fieldID]?.summary
                ?? GraphChatAnswerArtifactQueryFieldSummary(fieldID: fieldID, label: fieldID.uuidString)
            aggregation = .minimum(field: field, label: strings.minimum)
            grouping = nil
        case .maximum(let fieldID):
            let field = fields[fieldID]?.summary
                ?? GraphChatAnswerArtifactQueryFieldSummary(fieldID: fieldID, label: fieldID.uuidString)
            aggregation = .maximum(field: field, label: strings.maximum)
            grouping = nil
        case .groupCount(let fieldID):
            let field = fields[fieldID]?.summary
                ?? GraphChatAnswerArtifactQueryFieldSummary(fieldID: fieldID, label: fieldID.uuidString)
            aggregation = .groupCount(field: field, label: strings.groupCount)
            grouping = field
        case nil:
            aggregation = nil
            grouping = nil
        }
        let includesNodeIdentity = plan.projection.contains { projection in
            if case .nodeIdentity = projection {
                return true
            }
            return false
        }
        let displayText = querySummaryText(
            entityLabel: entityLabel,
            filters: filterSummaries,
            grouping: grouping,
            sorting: sorting,
            projection: projectionFields,
            includesNodeIdentity: includesNodeIdentity,
            limit: plan.limit,
            aggregation: aggregation,
            strings: strings
        )
        return GraphChatAnswerArtifactQuerySummary(
            language: language,
            entityID: plan.entityID,
            entityLabel: entityLabel,
            filters: filterSummaries,
            grouping: grouping,
            sorting: sorting,
            projection: projectionFields,
            includesNodeIdentity: includesNodeIdentity,
            limit: plan.limit,
            aggregation: aggregation,
            displayText: displayText
        )
    }

    static func resultMetadata(
        sourceWindow: GraphChatResultWindow,
        includedCount: Int,
        sourceReason: GraphChatAnswerArtifactTruncationReason,
        fallbackLimit: Int? = nil,
        forceUILimit: Bool = false,
        omittedColumnCount: Int? = nil
    ) -> GraphChatAnswerArtifactResultMetadata {
        let normalizedIncludedCount = max(0, includedCount)
        var reasons: [GraphChatAnswerArtifactTruncationReason] = []
        if sourceWindow.limitReached {
            if sourceWindow.limitSources.isEmpty {
                reasons.append(sourceReason)
            } else {
                reasons.append(
                    contentsOf: sourceWindow.limitSources.map {
                        truncationReason(for: $0, fallback: sourceReason)
                    }
                )
            }
        } else if sourceWindow.limit == nil,
                  let fallbackLimit,
                  fallbackLimit > 0,
                  sourceWindow.returnedCount > fallbackLimit {
            reasons.append(sourceReason)
        }
        if normalizedIncludedCount < sourceWindow.returnedCount || forceUILimit {
            reasons.append(.uiLimit)
        }
        let omittedCount: Int?
        if let totalCount = sourceWindow.totalCount {
            omittedCount = max(0, totalCount - normalizedIncludedCount)
        } else if reasons == [.uiLimit] {
            omittedCount = max(0, sourceWindow.returnedCount - normalizedIncludedCount)
        } else {
            omittedCount = nil
        }
        return GraphChatAnswerArtifactResultMetadata(
            resultCount: sourceWindow.totalCount,
            returnedCount: normalizedIncludedCount,
            truncation: GraphChatAnswerArtifactTruncation(
                reasons: reasons,
                omittedCount: omittedCount,
                omittedColumnCount: omittedColumnCount
            )
        )
    }

    static func truncationReason(
        for source: GraphChatResultLimitSource?,
        fallback: GraphChatAnswerArtifactTruncationReason
    ) -> GraphChatAnswerArtifactTruncationReason {
        switch source {
        case .tool:
            return .toolLimit
        case .query:
            return .queryLimit
        case .source:
            return .sourceLimited
        case .appPolicy:
            return .appPolicy
        case nil:
            return fallback
        }
    }

    static func querySummaryText(
        entityLabel: String,
        filters: [GraphChatAnswerArtifactQueryFilterSummary],
        grouping: GraphChatAnswerArtifactQueryFieldSummary?,
        sorting: [GraphChatAnswerArtifactQuerySortSummary],
        projection: [GraphChatAnswerArtifactQueryFieldSummary],
        includesNodeIdentity: Bool,
        limit: Int,
        aggregation: GraphChatAnswerArtifactQueryAggregationSummary?,
        strings: Strings
    ) -> String {
        var clauses = ["\(strings.entity): \(entityLabel)"]
        if filters.isEmpty == false {
            let filterText = filters.map { filter in
                var value = "\(filter.field.label) \(filter.operationLabel)"
                if let description = filter.valueDescription, description.isEmpty == false {
                    value += " \(description)"
                }
                return value
            }.joined(separator: ", ")
            clauses.append("\(strings.filters): \(filterText)")
        }
        if let grouping {
            clauses.append("\(strings.grouping): \(grouping.label)")
        }
        if sorting.isEmpty == false {
            let value = sorting.map { "\($0.label) \($0.directionLabel)" }.joined(separator: ", ")
            clauses.append("\(strings.sorting): \(value)")
        }
        var projectionLabels = projection.map(\.label)
        if includesNodeIdentity {
            projectionLabels.insert(strings.name, at: 0)
        }
        if projectionLabels.isEmpty == false {
            clauses.append("\(strings.projection): \(projectionLabels.joined(separator: ", "))")
        }
        clauses.append("\(strings.limit): \(limit)")
        if let aggregation {
            clauses.append("\(strings.aggregation): \(aggregationLabel(aggregation))")
        }
        return clauses.joined(separator: "; ")
    }

    static func aggregationLabel(
        _ aggregation: GraphChatAnswerArtifactQueryAggregationSummary
    ) -> String {
        switch aggregation {
        case .count(let label):
            return label
        case .minimum(let field, let label),
             .maximum(let field, let label),
             .groupCount(let field, let label):
            return "\(label): \(field.label)"
        }
    }

    static func projectedFieldIDs(
        _ plan: ValidatedGraphQueryPlan
    ) -> [UUID] {
        var seen = Set<UUID>()
        return plan.projection.compactMap { projection in
            guard case .field(let fieldID) = projection,
                  seen.insert(fieldID).inserted else {
                return nil
            }
            return fieldID
        }
    }

}
