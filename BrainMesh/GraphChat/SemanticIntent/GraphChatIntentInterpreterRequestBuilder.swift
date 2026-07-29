//
//  GraphChatIntentInterpreterRequestBuilder.swift
//  BrainMesh
//
//  Builds the bounded, user-visible context accepted by the interpreter.
//

import Foundation

nonisolated struct GraphChatIntentInterpreterContextLimits:
    Hashable,
    Sendable
{
    let maximumEntities: Int
    let maximumFieldsPerEntity: Int
    let maximumConversationDescriptions: Int
    let maximumDescriptionLength: Int
    let maximumReferencesPerResult: Int
    let maximumSelectionDescriptions: Int

    static let `default`: GraphChatIntentInterpreterContextLimits = {
        make(
            GraphChatIntentLimitPolicy
                .default.standardInterpreterContext
        )
    }()

    static let compactRetry:
        GraphChatIntentInterpreterContextLimits =
            make(
                GraphChatIntentLimitPolicy
                    .default.compactInterpreterContext
            )

    init(
        maximumEntities: Int,
        maximumFieldsPerEntity: Int,
        maximumConversationDescriptions: Int,
        maximumDescriptionLength: Int,
        maximumReferencesPerResult: Int =
            GraphChatIntentLimitPolicy
                .default.standardInterpreterContext
                .maximumReferencesPerResult,
        maximumSelectionDescriptions: Int =
            GraphChatIntentLimitPolicy
                .default.standardInterpreterContext
                .maximumSelectionDescriptions
    ) {
        precondition(maximumEntities > 0)
        precondition(maximumFieldsPerEntity > 0)
        precondition(maximumConversationDescriptions >= 0)
        precondition(maximumDescriptionLength > 0)
        precondition(maximumReferencesPerResult > 0)
        precondition(maximumSelectionDescriptions > 0)

        self.maximumEntities = maximumEntities
        self.maximumFieldsPerEntity =
            maximumFieldsPerEntity
        self.maximumConversationDescriptions =
            maximumConversationDescriptions
        self.maximumDescriptionLength =
            maximumDescriptionLength
        self.maximumReferencesPerResult =
            maximumReferencesPerResult
        self.maximumSelectionDescriptions =
            maximumSelectionDescriptions
    }

    private static func make(
        _ budget:
            GraphChatIntentInterpreterContextBudget
    ) -> GraphChatIntentInterpreterContextLimits {
        GraphChatIntentInterpreterContextLimits(
            maximumEntities: budget.maximumEntities,
            maximumFieldsPerEntity:
                budget.maximumFieldsPerEntity,
            maximumConversationDescriptions:
                budget.maximumConversationDescriptions,
            maximumDescriptionLength:
                budget.maximumDescriptionLength,
            maximumReferencesPerResult:
                budget.maximumReferencesPerResult,
            maximumSelectionDescriptions:
                budget.maximumSelectionDescriptions
        )
    }
}

nonisolated struct GraphChatIntentInterpreterRequestBuilder:
    Hashable,
    Sendable
{
    private let limits:
        GraphChatIntentInterpreterContextLimits

    init(
        limits:
            GraphChatIntentInterpreterContextLimits = .default
    ) {
        self.limits = limits
    }

    func makeRequest(
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) throws -> GraphChatIntentInterpreterRequest {
        guard
            providerPlan.scopeKey.graphScope
                == schemaContext.graphScope,
            schemaContext.foundationalAliases.graphScope
                == schemaContext.graphScope
        else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message:
                    "Der begrenzte Interpreter-Kontext gehört nicht zum aktiven Graphen."
            )
        }

        let entities = Array(
            schemaContext.snapshot.entities
                .prefix(limits.maximumEntities)
        ).map { entity in
            GraphChatSemanticSchemaEntity(
                displayName: boundedVisible(entity.name),
                fieldDisplayNames: Array(
                    entity.fields
                        .prefix(limits.maximumFieldsPerEntity)
                ).map { boundedVisible($0.name) }
            )
        }
        return GraphChatIntentInterpreterRequest(
            normalizedQuestion:
                providerPlan.providerQuestion,
            responseLanguage:
                providerPlan.responseLanguage,
            schemaEntities: entities,
            conversationDescriptions:
                conversationDescriptions(
                    from: providerPlan
                        .requestBaseState
                ),
            scopeDescription: scopeDescription(
                providerPlan.scopeKey.chatScope,
                schemaContext: schemaContext,
                language:
                    providerPlan.responseLanguage
            )
        )
    }

    private func conversationDescriptions(
        from state: GraphChatConversationState
    ) -> [String] {
        let descriptions = state.resultContexts
            .reversed()
            .flatMap { result in
                result.references.prefix(
                    limits.maximumReferencesPerResult
                ).map {
                    $0.label
                }
            }
            .filter { isSafeVisible($0) }
            .map { boundedVisible($0) }
        var seen = Set<String>()
        return Array(
            descriptions
                .filter { seen.insert(BMSearch.fold($0)).inserted }
                .prefix(
                    limits.maximumConversationDescriptions
                )
        )
    }

    private func scopeDescription(
        _ scope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage
    ) -> String {
        let aliases = schemaContext.foundationalAliases
        switch scope.target {
        case .graph:
            return language == .german
                ? "Gesamter Graph \(boundedVisible(schemaContext.snapshot.graphName))"
                : "Entire graph \(boundedVisible(schemaContext.snapshot.graphName))"

        case .entity(let entityID):
            let name: String
            if let value =
                aliases.entity(id: entityID)?.name,
               isSafeVisible(value)
            {
                name = boundedVisible(value)
            } else {
                name = genericEntity(language)
            }
            return language == .german
                ? "Entity \(name)"
                : "Entity \(name)"

        case .node(let node):
            let name: String
            if let value =
                aliases.nodesByKey[node]?.displayName,
               isSafeVisible(value)
            {
                name = boundedVisible(value)
            } else {
                name = genericNode(language)
            }
            return language == .german
                ? "Node \(name)"
                : "Node \(name)"

        case .selection(let nodes):
            let names = nodes.compactMap {
                aliases.nodesByKey[$0]?.displayName
            }
            .filter { isSafeVisible($0) }
            .prefix(
                limits.maximumSelectionDescriptions
            )
            .map { boundedVisible($0) }
            .joined(separator: ", ")
            let visible = names.isEmpty
                ? genericSelection(language)
                : names
            return language == .german
                ? "Auswahl: \(visible)"
                : "Selection: \(visible)"
        }
    }

    private func genericEntity(
        _ language: GraphChatResponseLanguage
    ) -> String {
        language == .german ? "aktuelle Entity" : "current entity"
    }

    private func genericNode(
        _ language: GraphChatResponseLanguage
    ) -> String {
        language == .german ? "aktueller Node" : "current node"
    }

    private func genericSelection(
        _ language: GraphChatResponseLanguage
    ) -> String {
        language == .german
            ? "aktuelle Auswahl"
            : "current selection"
    }

    private func isSafeVisible(_ value: String) -> Bool {
        GraphChatSemanticSafety.containsTechnicalIdentifier(
            value
        ) == false
    }

    private func boundedVisible(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if isSafeVisible(trimmed) == false {
            return ""
        }
        return String(
            trimmed.prefix(limits.maximumDescriptionLength)
        )
    }
}
