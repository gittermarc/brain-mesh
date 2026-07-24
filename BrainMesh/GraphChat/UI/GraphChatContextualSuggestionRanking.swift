//
//  GraphChatContextualSuggestionRanking.swift
//  BrainMesh
//
//  Shared tool gating, scope validation, deterministic ranking, and schema lookups.
//

import Foundation

nonisolated extension GraphChatEmptyStateSuggestionBuilder {
    static func ranked(
        _ candidates: [Candidate],
        context: GraphChatSuggestionContext
    ) -> [GraphChatEmptyStateSuggestion] {
        let sorted = candidates
            .filter { candidate in
                candidate.requiredTools.isSubset(of: context.availableTools)
            }
            .sorted {
                if $0.priority != $1.priority {
                    return $0.priority < $1.priority
                }
                if $0.kind.rawValue != $1.kind.rawValue {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                return $0.id < $1.id
            }

        var seenSemanticKeys = Set<String>()
        var seenPrompts = Set<String>()
        var unique: [Candidate] = []
        for candidate in sorted {
            let promptKey = BMSearch.fold(candidate.prompt)
            guard seenSemanticKeys.insert(candidate.semanticKey).inserted,
                  seenPrompts.insert(promptKey).inserted else {
                continue
            }
            unique.append(candidate)
        }

        var selected: [Candidate] = []
        var selectedKinds = Set<GraphChatSuggestionKind>()
        for candidate in unique where selected.count < maximumSuggestions {
            guard selectedKinds.insert(candidate.kind).inserted else {
                continue
            }
            selected.append(candidate)
        }
        for candidate in unique where selected.count < maximumSuggestions {
            guard selected.contains(where: { $0.id == candidate.id }) == false else {
                continue
            }
            selected.append(candidate)
        }

        let text = Texts(context.language)
        return selected.map {
            GraphChatEmptyStateSuggestion(
                id: $0.id,
                title: $0.title,
                prompt: $0.prompt,
                kind: $0.kind,
                accessibilityLabel: "\($0.title): \($0.prompt)",
                accessibilityHint: text.suggestionAccessibilityHint
            )
        }
    }

    static func tool(
        _ tool: GraphChatToolKind,
        isAvailableIn context: GraphChatSuggestionContext
    ) -> Bool {
        context.availableTools.contains(tool)
    }

    static func scopeAllows(
        entityID: UUID,
        context: GraphChatSuggestionContext
    ) -> Bool {
        switch context.scope.target {
        case .graph:
            return true
        case .entity(let scopedEntityID):
            return scopedEntityID == entityID
        case .node(let node):
            return context.schema.aliases.owningEntityID(for: node) == entityID
                || (node.kind == .entity && node.id == entityID)
        case .selection(let nodes):
            return nodes.allSatisfy {
                context.schema.aliases.owningEntityID(for: $0) == entityID
                    || ($0.kind == .entity && $0.id == entityID)
            }
        }
    }

    static func entity(
        id: UUID,
        in schema: GraphSchemaContext
    ) -> GraphSchemaEntity? {
        guard let resolution = schema.aliases.entitiesByAlias.values.first(
            where: { $0.entityID == id }
        ) else {
            return nil
        }
        return schema.snapshot.entities.first { $0.alias == resolution.alias }
    }

    static func field(
        id: UUID,
        in schema: GraphSchemaContext
    ) -> (entity: GraphSchemaEntity, field: GraphSchemaField, entityID: UUID)? {
        guard let resolution = schema.aliases.fieldsByAlias.values.first(
            where: { $0.fieldID == id }
        ), let entity = schema.snapshot.entities.first(
            where: { $0.alias == resolution.entityAlias }
        ), let field = entity.fields.first(
            where: { $0.alias == resolution.alias }
        ) else {
            return nil
        }
        return (entity, field, resolution.entityID)
    }

    static func firstField(
        in snapshot: GraphSchemaSnapshot,
        matching predicate: (GraphSchemaField) -> Bool
    ) -> (entity: GraphSchemaEntity, field: GraphSchemaField)? {
        for entity in snapshot.entities.sorted(by: entitySort) {
            if let field = entity.fields.first(where: predicate) {
                return (entity, field)
            }
        }
        return nil
    }

    static func preferredChoiceField(
        in snapshot: GraphSchemaSnapshot
    ) -> (entity: GraphSchemaEntity, field: GraphSchemaField)? {
        let entities = snapshot.entities.sorted(by: entitySort)
        for entity in entities {
            if let field = preferredChoiceField(in: entity) {
                return (entity, field)
            }
        }
        return nil
    }

    static func preferredChoiceField(
        in entity: GraphSchemaEntity
    ) -> GraphSchemaField? {
        let choiceFields = entity.fields.filter { $0.type == .singleChoice }
        return choiceFields.first {
            BMSearch.fold($0.name).contains("status")
        } ?? choiceFields.first
    }

    static func supportsDistribution(_ field: GraphSchemaField) -> Bool {
        switch field.type {
        case .singleChoice, .toggle:
            return true
        case .singleLineText, .multiLineText, .numberInt, .numberDouble, .date:
            return false
        }
    }

    static func supportsCommonValues(_ field: GraphSchemaField) -> Bool {
        field.type == .singleLineText
    }

    static func supportsMinimumMaximum(_ field: GraphSchemaField) -> Bool {
        switch field.type {
        case .numberInt, .numberDouble, .date:
            return true
        case .singleLineText, .multiLineText, .toggle, .singleChoice:
            return false
        }
    }

    static func commonEntityID(
        _ references: [GraphChatNodeContextReference]
    ) -> UUID? {
        let ids = Set(references.compactMap(\GraphChatNodeContextReference.entityID))
        guard ids.count == 1,
              references.allSatisfy({ $0.entityID != nil }) else {
            return nil
        }
        return ids.first
    }

    static func entitySort(
        _ lhs: GraphSchemaEntity,
        _ rhs: GraphSchemaEntity
    ) -> Bool {
        if lhs.attributeCount != rhs.attributeCount {
            return lhs.attributeCount > rhs.attributeCount
        }
        let lhsName = BMSearch.fold(lhs.name)
        let rhsName = BMSearch.fold(rhs.name)
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.alias.rawValue < rhs.alias.rawValue
    }

    struct Candidate: Sendable {
        let id: String
        let semanticKey: String
        let priority: Int
        let kind: GraphChatSuggestionKind
        let requiredTools: Set<GraphChatToolKind>
        let title: String
        let prompt: String
    }
}
