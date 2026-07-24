//
//  GraphChatContextualSuggestionCandidates+Graph.swift
//  BrainMesh
//
//  Deterministic graph, entity, and detail-field starter candidates.
//

import Foundation

nonisolated extension GraphChatEmptyStateSuggestionBuilder {
    static func graphCandidates(
        _ context: GraphChatSuggestionContext
    ) -> [Candidate] {
        var result: [Candidate] = []
        let text = Texts(context.language)

        if tool(.graphStats, isAvailableIn: context),
           case .graph = context.scope.target {
            result.append(
                Candidate(
                    id: "graph-overview",
                    semanticKey: "graph-overview",
                    priority: 10,
                    kind: .detail,
                    requiredTools: [.graphStats],
                    title: text.graphOverviewTitle,
                    prompt: text.graphOverviewPrompt(context.schema.snapshot.graphName)
                )
            )
            result.append(
                Candidate(
                    id: "graph-links",
                    semanticKey: "graph-links",
                    priority: 30,
                    kind: .structure,
                    requiredTools: [.graphStats],
                    title: text.strongestLinksTitle,
                    prompt: text.strongestLinksPrompt
                )
            )
        }

        if let entity = context.schema.snapshot.entities
            .filter({ $0.attributeCount > 0 })
            .sorted(by: entitySort)
            .first,
           tool(.queryDetailValues, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "graph-entity-list-\(entity.alias.rawValue)",
                    semanticKey: "entity-list-\(entity.alias.rawValue)",
                    priority: 20,
                    kind: .list,
                    requiredTools: [.queryDetailValues],
                    title: text.entityListTitle,
                    prompt: text.graphEntityListPrompt(entity.name)
                )
            )
        }

        if let pair = preferredChoiceField(in: context.schema.snapshot),
           tool(.queryDetailValues, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "graph-choice-\(pair.field.alias.rawValue)",
                    semanticKey: "choice-distribution-\(pair.field.alias.rawValue)",
                    priority: 15,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.distributionTitle,
                    prompt: text.distributionPrompt(
                        entity: pair.entity.name,
                        field: pair.field.name
                    )
                )
            )
        } else if let pair = firstField(
            in: context.schema.snapshot,
            matching: { $0.type == .date }
        ), tool(.queryDetailValues, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "graph-date-\(pair.field.alias.rawValue)",
                    semanticKey: "date-overdue-\(pair.field.alias.rawValue)",
                    priority: 15,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.overdueTitle,
                    prompt: text.overduePrompt(
                        entity: pair.entity.name,
                        field: pair.field.name
                    )
                )
            )
        }

        if let pair = firstField(
            in: context.schema.snapshot,
            matching: { _ in true }
        ), tool(.queryDetailValues, isAvailableIn: context) {
            result.append(
                Candidate(
                    id: "graph-missing-\(pair.field.alias.rawValue)",
                    semanticKey: "missing-\(pair.field.alias.rawValue)",
                    priority: 40,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.missingValuesTitle,
                    prompt: text.missingValuesPrompt(
                        entity: pair.entity.name,
                        field: pair.field.name
                    )
                )
            )
        }

        return result
    }

    static func entityCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatEntityContextReference
    ) -> [Candidate] {
        guard let entity = entity(
            id: reference.id,
            in: context.schema
        ), scopeAllows(entityID: reference.id, context: context),
        tool(.queryDetailValues, isAvailableIn: context) else {
            return []
        }

        let text = Texts(context.language)
        var result: [Candidate] = [
            Candidate(
                id: "entity-list-\(entity.alias.rawValue)",
                semanticKey: "entity-list-\(entity.alias.rawValue)",
                priority: 10,
                kind: .list,
                requiredTools: [.queryDetailValues],
                title: text.entityListTitle,
                prompt: text.entityListPrompt(entity.name)
            )
        ]

        if let field = preferredChoiceField(in: entity) {
            result.append(
                Candidate(
                    id: "entity-choice-\(field.alias.rawValue)",
                    semanticKey: "choice-distribution-\(field.alias.rawValue)",
                    priority: 20,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.distributionTitle,
                    prompt: text.distributionPrompt(entity: entity.name, field: field.name)
                )
            )
        }

        if let dateField = entity.fields.first(where: { $0.type == .date }) {
            result.append(
                Candidate(
                    id: "entity-newest-\(dateField.alias.rawValue)",
                    semanticKey: "newest-\(dateField.alias.rawValue)",
                    priority: 30,
                    kind: .list,
                    requiredTools: [.queryDetailValues],
                    title: text.newestTitle,
                    prompt: text.newestPrompt(entity: entity.name, field: dateField.name)
                )
            )
        }

        if let field = entity.fields.first {
            result.append(
                Candidate(
                    id: "entity-missing-\(field.alias.rawValue)",
                    semanticKey: "missing-\(field.alias.rawValue)",
                    priority: 40,
                    kind: .detail,
                    requiredTools: [.queryDetailValues],
                    title: text.missingValuesTitle,
                    prompt: text.missingValuesPrompt(entity: entity.name, field: field.name)
                )
            )
        }

        if let field = entity.fields.first(where: supportsMinimumMaximum) {
            result.append(
                Candidate(
                    id: "entity-range-\(field.alias.rawValue)",
                    semanticKey: "range-\(field.alias.rawValue)",
                    priority: 35,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.rangeTitle,
                    prompt: text.rangePrompt(entity: entity.name, field: field.name)
                )
            )
        }

        return result
    }

    static func fieldCandidates(
        _ context: GraphChatSuggestionContext,
        reference: GraphChatFieldContextReference
    ) -> [Candidate] {
        guard let pair = field(id: reference.id, in: context.schema),
              pair.entityID == reference.entity.id,
              scopeAllows(entityID: reference.entity.id, context: context),
              tool(.queryDetailValues, isAvailableIn: context) else {
            return []
        }

        let entity = pair.entity
        let field = pair.field
        let text = Texts(context.language)
        var result: [Candidate] = []

        if supportsDistribution(field) {
            result.append(
                Candidate(
                    id: "field-distribution-\(field.alias.rawValue)",
                    semanticKey: "field-frequency-\(field.alias.rawValue)",
                    priority: 10,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.distributionTitle,
                    prompt: text.distributionPrompt(entity: entity.name, field: field.name)
                )
            )
        } else if supportsCommonValues(field) {
            result.append(
                Candidate(
                    id: "field-common-\(field.alias.rawValue)",
                    semanticKey: "field-frequency-\(field.alias.rawValue)",
                    priority: 10,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.commonValuesTitle,
                    prompt: text.commonValuesPrompt(entity: entity.name, field: field.name)
                )
            )
        }

        result.append(
            Candidate(
                id: "field-missing-\(field.alias.rawValue)",
                semanticKey: "missing-\(field.alias.rawValue)",
                priority: 15,
                kind: .detail,
                requiredTools: [.queryDetailValues],
                title: text.missingValuesTitle,
                prompt: text.missingValuesPrompt(entity: entity.name, field: field.name)
            )
        )
        result.append(
            Candidate(
                id: "field-nodes-\(field.alias.rawValue)",
                semanticKey: "field-nodes-\(field.alias.rawValue)",
                priority: 30,
                kind: .list,
                requiredTools: [.queryDetailValues],
                title: text.affectedNodesTitle,
                prompt: text.fieldNodesPrompt(entity: entity.name, field: field.name)
            )
        )

        if supportsMinimumMaximum(field) {
            result.append(
                Candidate(
                    id: "field-range-\(field.alias.rawValue)",
                    semanticKey: "range-\(field.alias.rawValue)",
                    priority: 25,
                    kind: .statistics,
                    requiredTools: [.queryDetailValues],
                    title: text.rangeTitle,
                    prompt: text.rangePrompt(entity: entity.name, field: field.name)
                )
            )
        }

        return result
    }
}
