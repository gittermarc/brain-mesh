//
//  GraphChatQueryEngine.swift
//  BrainMesh
//
//  Deterministic, read-only execution of validated graph query plans.
//

import Foundation

actor GraphChatQueryEngine {
    static let shared = GraphChatQueryEngine(
        repository: GraphReadRepository.shared,
        evidenceValidator: GraphEvidenceSourceValidator.shared
    )

    private let repository: any GraphChatQueryReading
    private let evidenceValidator: any GraphEvidenceValidating
    private let limits: GraphChatQueryEngineLimits

    init(
        repository: any GraphChatQueryReading,
        evidenceValidator: any GraphEvidenceValidating,
        limits: GraphChatQueryEngineLimits = .default
    ) {
        self.repository = repository
        self.evidenceValidator = evidenceValidator
        self.limits = limits
    }

    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult {
        try Task.checkCancellation()
        guard plan.limit <= limits.maximumResultCount else {
            throw GraphChatQueryEngineError.resultLimitExceeded(
                maximum: limits.maximumResultCount
            )
        }

        let fieldIDs = Self.requiredFieldIDs(for: plan)
        guard let source = try await repository.graphChatQuerySource(
            entityID: plan.entityID,
            fieldIDs: fieldIDs,
            in: plan.graphScope
        ) else {
            throw GraphChatQueryEngineError.sourceUnavailable
        }
        try Task.checkCancellation()

        guard source.graphScope == plan.graphScope else {
            throw GraphChatQueryEngineError.graphScopeMismatch
        }
        guard source.entity.id == plan.entityID,
              source.entity.scope == plan.graphScope else {
            throw GraphChatQueryEngineError.entityMismatch
        }

        let fieldMap = Dictionary(uniqueKeysWithValues: source.fields.map { ($0.id, $0) })
        guard fieldIDs.isSubset(of: Set(fieldMap.keys)),
              Self.sourceFieldsMatchValidatedPlan(plan, fieldMap: fieldMap) else {
            throw GraphChatQueryEngineError.sourceUnavailable
        }
        let valuesByAttribute = Self.valuesByAttribute(
            source.values,
            validAttributeIDs: Set(source.attributes.map(\.id))
        )
        let scopedAttributes = Self.attributes(
            source.attributes,
            allowedBy: plan.scope,
            selectedEntityID: plan.entityID
        )
        var preparedRows: [GraphChatPreparedQueryRow] = []
        preparedRows.reserveCapacity(scopedAttributes.count)

        for (index, attribute) in scopedAttributes.enumerated() {
            if index.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let row = GraphChatPreparedQueryRow(
                attribute: attribute,
                valuesByFieldID: valuesByAttribute[attribute.id] ?? [:]
            )
            if Self.matchesAllFilters(row, filters: plan.filters) {
                preparedRows.append(row)
            }
        }
        try Task.checkCancellation()

        let appliedFilters = Self.appliedFilters(
            plan.filters,
            fieldMap: fieldMap
        )

        if let aggregation = plan.aggregation {
            return try await executeAggregation(
                aggregation,
                plan: plan,
                rows: preparedRows,
                fieldMap: fieldMap,
                appliedFilters: appliedFilters,
                entity: source.entity,
                sourceAttributes: source.attributes
            )
        }

        let sortedRows = Self.sortedRows(preparedRows, using: plan.sorting)
        let limitedRows = Array(sortedRows.prefix(plan.limit))
        guard limitedRows.isEmpty == false else {
            return GraphChatQueryResult(
                state: .noResults,
                rows: [],
                aggregation: nil,
                appliedFilters: appliedFilters,
                evidence: []
            )
        }

        let rowBuild = try Self.makeResultRows(
            limitedRows,
            plan: plan,
            fieldMap: fieldMap,
            maximumEvidenceCount: limits.maximumEvidenceCount
        )
        let validatedEvidence = try await evidenceValidator.validatedEvidence(
            rowBuild.evidence,
            in: try Self.chatScope(for: plan)
        )
        try Task.checkCancellation()
        let validEvidenceIDs = Set(validatedEvidence.map(\.id))
        let validatedRows = rowBuild.rows.compactMap { row -> GraphChatQueryResultRow? in
            let cells = row.cells.filter { validEvidenceIDs.contains($0.evidenceID) }
            let evidenceIDs = row.evidenceIDs.filter { validEvidenceIDs.contains($0) }
            guard evidenceIDs.isEmpty == false else {
                return nil
            }
            return GraphChatQueryResultRow(
                node: row.node,
                label: row.label,
                cells: cells,
                evidenceIDs: evidenceIDs
            )
        }

        return GraphChatQueryResult(
            state: validatedRows.isEmpty ? .noEvidence : .success,
            rows: validatedRows,
            aggregation: nil,
            appliedFilters: appliedFilters,
            evidence: validatedEvidence
        )
    }

    private func executeAggregation(
        _ aggregation: GraphValidatedAggregation,
        plan: ValidatedGraphQueryPlan,
        rows: [GraphChatPreparedQueryRow],
        fieldMap: [UUID: GraphDetailFieldDefinitionDTO],
        appliedFilters: [GraphChatAppliedFilter],
        entity: GraphEntityDTO,
        sourceAttributes: [GraphAttributeDTO]
    ) async throws -> GraphChatQueryResult {
        let build = try Self.makeAggregation(
            aggregation,
            rows: rows,
            entity: entity,
            fieldMap: fieldMap,
            scope: plan.scope,
            sourceAttributes: sourceAttributes,
            limit: plan.limit,
            maximumEvidenceCount: limits.maximumEvidenceCount
        )
        let validatedEvidence = try await evidenceValidator.validatedEvidence(
            build.evidence,
            in: try Self.chatScope(for: plan)
        )
        try Task.checkCancellation()
        let validEvidenceIDs = Set(validatedEvidence.map(\.id))
        let aggregateEvidenceID = build.evidence.first?.id
        let aggregateEvidenceIsValid = aggregateEvidenceID.map {
            validEvidenceIDs.contains($0)
        } == true
        let validResultEvidenceIDs = build.result.evidenceIDs.filter {
            validEvidenceIDs.contains($0)
        }
        let supportingEvidenceIDs = validResultEvidenceIDs.filter {
            $0 != aggregateEvidenceID
        }
        let groups = build.result.groups.compactMap { group -> GraphChatGroupCount? in
            let evidenceIDs = group.evidenceIDs.filter { validEvidenceIDs.contains($0) }
            guard evidenceIDs.isEmpty == false else {
                return nil
            }
            return GraphChatGroupCount(
                value: group.value,
                count: group.count,
                evidenceIDs: evidenceIDs
            )
        }
        let adjustedCount = build.result.count
        let hasRequiredValueEvidence: Bool
        switch build.result.kind {
        case .minimum, .maximum:
            hasRequiredValueEvidence = build.result.value == nil
                || supportingEvidenceIDs.isEmpty == false
        case .count:
            hasRequiredValueEvidence = true
        case .groupCount:
            hasRequiredValueEvidence = build.result.groups.isEmpty || groups.isEmpty == false
        }
        let aggregationResult = GraphChatAggregationResult(
            kind: build.result.kind,
            fieldID: build.result.fieldID,
            fieldName: build.result.fieldName,
            count: adjustedCount,
            groups: groups,
            value: hasRequiredValueEvidence ? build.result.value : nil,
            evidenceIDs: validResultEvidenceIDs
        )
        let finalState: GraphChatResultState
        if aggregateEvidenceIsValid == false || hasRequiredValueEvidence == false {
            finalState = .noEvidence
        } else {
            finalState = build.state
        }

        return GraphChatQueryResult(
            state: finalState,
            rows: [],
            aggregation: aggregationResult,
            appliedFilters: appliedFilters,
            evidence: validatedEvidence
        )
    }

    nonisolated private static func sourceFieldsMatchValidatedPlan(
        _ plan: ValidatedGraphQueryPlan,
        fieldMap: [UUID: GraphDetailFieldDefinitionDTO]
    ) -> Bool {
        for filter in plan.filters {
            guard let field = fieldMap[filter.fieldID],
                  field.type == filter.fieldType else {
                return false
            }
            if filter.fieldType == .singleChoice,
               validatedChoiceValuesRemainAvailable(filter.value, field: field) == false {
                return false
            }
        }
        guard let aggregation = plan.aggregation else {
            return true
        }
        switch aggregation {
        case .count:
            return true
        case .groupCount(let fieldID):
            return fieldMap[fieldID] != nil
        case .minimum(let fieldID), .maximum(let fieldID):
            guard let type = fieldMap[fieldID]?.type else {
                return false
            }
            return type == .numberInt || type == .numberDouble || type == .date
        }
    }


    nonisolated private static func validatedChoiceValuesRemainAvailable(
        _ value: GraphValidatedFilterValue,
        field: GraphDetailFieldDefinitionDTO
    ) -> Bool {
        let available = Set(field.options.map(GraphQueryChoiceNormalizer.normalize))
        switch value {
        case .none:
            return true
        case .choice(let choice):
            return available.contains(
                GraphQueryChoiceNormalizer.normalize(choice.canonicalValue)
            )
        case .choices(let choices):
            return choices.allSatisfy { choice in
                available.contains(
                    GraphQueryChoiceNormalizer.normalize(choice.canonicalValue)
                )
            }
        default:
            return false
        }
    }

    nonisolated private static func requiredFieldIDs(
        for plan: ValidatedGraphQueryPlan
    ) -> Set<UUID> {
        var result = Set(plan.filters.map(\.fieldID))
        for sort in plan.sorting {
            if case .field(let fieldID) = sort.key {
                result.insert(fieldID)
            }
        }
        for projection in plan.projection {
            if case .field(let fieldID) = projection {
                result.insert(fieldID)
            }
        }
        if let aggregation = plan.aggregation {
            switch aggregation {
            case .count:
                break
            case .groupCount(let fieldID), .minimum(let fieldID), .maximum(let fieldID):
                result.insert(fieldID)
            }
        }
        return result
    }

    nonisolated private static func valuesByAttribute(
        _ values: [GraphDetailValueDTO],
        validAttributeIDs: Set<UUID>
    ) -> [UUID: [UUID: GraphDetailValueDTO]] {
        var result: [UUID: [UUID: GraphDetailValueDTO]] = [:]
        for value in values where validAttributeIDs.contains(value.attributeID) {
            if let existing = result[value.attributeID]?[value.fieldID],
               existing.id.uuidString <= value.id.uuidString {
                continue
            }
            result[value.attributeID, default: [:]][value.fieldID] = value
        }
        return result
    }

    nonisolated private static func attributes(
        _ attributes: [GraphAttributeDTO],
        allowedBy scope: GraphResolvedQueryScope,
        selectedEntityID: UUID
    ) -> [GraphAttributeDTO] {
        switch scope {
        case .graph, .entity:
            return attributes
        case .node(let node):
            switch node.kind {
            case .entity:
                return node.id == selectedEntityID ? attributes : []
            case .attribute:
                return attributes.filter { $0.id == node.id }
            }
        case .selection(let nodes):
            if nodes.contains(NodeRefKey(kind: .entity, id: selectedEntityID)) {
                return attributes
            }
            let attributeIDs = Set(
                nodes.compactMap { $0.kind == .attribute ? $0.id : nil }
            )
            return attributes.filter { attributeIDs.contains($0.id) }
        }
    }

    nonisolated private static func chatScope(
        for plan: ValidatedGraphQueryPlan
    ) throws -> GraphChatScope {
        switch plan.scope {
        case .graph:
            return .entireGraph(plan.graphScope)
        case .entity(let entityID):
            return .entity(entityID, in: plan.graphScope)
        case .node(let node):
            return .node(node, in: plan.graphScope)
        case .selection(let nodes):
            return try .selection(nodes, in: plan.graphScope)
        }
    }
}
