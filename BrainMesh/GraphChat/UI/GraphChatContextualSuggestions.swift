//
//  GraphChatContextualSuggestions.swift
//  BrainMesh
//
//  Scope-aware, deterministic starter questions backed by productive tools.
//

import Foundation

nonisolated enum GraphChatSuggestionKind: String, CaseIterable, Hashable, Sendable {
    case list
    case detail
    case statistics
    case structure

    var systemImage: String {
        switch self {
        case .list:
            return "list.bullet"
        case .detail:
            return "doc.text.magnifyingglass"
        case .statistics:
            return "chart.bar.xaxis"
        case .structure:
            return "point.3.connected.trianglepath.dotted"
        }
    }
}

nonisolated struct GraphChatEmptyStateSuggestion: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let prompt: String
    let kind: GraphChatSuggestionKind
    let accessibilityLabel: String
    let accessibilityHint: String

    init(
        id: String,
        title: String,
        prompt: String,
        kind: GraphChatSuggestionKind = .detail,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.kind = kind
        self.accessibilityLabel = accessibilityLabel ?? "\(title): \(prompt)"
        self.accessibilityHint = accessibilityHint ?? "Übernimmt diese Frage in das Eingabefeld."
    }
}

nonisolated struct GraphChatSuggestionContext: Sendable {
    let schema: GraphSchemaContext
    let scope: GraphChatScope
    let launchContext: GraphChatLaunchContext
    let availableTools: Set<GraphChatToolKind>
    let modelAvailability: GraphChatAvailabilityPresentationState
    let language: GraphChatResponseLanguage

    init(
        schema: GraphSchemaContext,
        scope: GraphChatScope,
        launchContext: GraphChatLaunchContext,
        availableTools: Set<GraphChatToolKind> = Set(GraphChatToolKind.allCases),
        modelAvailability: GraphChatAvailabilityPresentationState = .available,
        language: GraphChatResponseLanguage = GraphChatResponseLanguageSelector.systemFallback()
    ) {
        self.schema = schema
        self.scope = scope
        self.launchContext = launchContext
        self.availableTools = availableTools
        self.modelAvailability = modelAvailability
        self.language = language
    }
}

nonisolated enum GraphChatEmptyStateSuggestionBuilder {
    static let maximumSuggestions = 4
    static let maximumDirectNodeInspections = GraphChatToolBudgetPolicy.default.maximumCalls

    static func suggestions(
        for context: GraphChatSuggestionContext
    ) -> [GraphChatEmptyStateSuggestion] {
        guard context.modelAvailability.isAvailable else {
            return []
        }

        let candidates: [Candidate]
        switch context.launchContext {
        case .graph:
            candidates = graphCandidates(context)
        case .entity(let entityReference):
            candidates = entityCandidates(context, reference: entityReference)
        case .detailField(let fieldReference):
            candidates = fieldCandidates(context, reference: fieldReference)
        case .node(let nodeReference):
            candidates = nodeCandidates(context, reference: nodeReference)
        case .selection(let nodeReferences):
            candidates = selectionCandidates(context, references: nodeReferences)
        case .healthFinding(let finding):
            candidates = healthCandidates(context, finding: finding)
        }

        return ranked(candidates, context: context)
    }

    /// Compatibility entry used by previews and older callers that only own a snapshot.
    /// Contextual production callers should pass a full `GraphChatSuggestionContext`.
    static func suggestions(
        for snapshot: GraphSchemaSnapshot,
        scope: GraphChatScope
    ) -> [GraphChatEmptyStateSuggestion] {
        let aliases = GraphSchemaAliasMap(
            graphScope: scope.graphScope,
            entitiesByAlias: [:],
            fieldsByAlias: [:],
            nodeEntityIDs: [:]
        )
        return suggestions(
            for: GraphChatSuggestionContext(
                schema: GraphSchemaContext(
                    graphScope: scope.graphScope,
                    snapshot: snapshot,
                    aliases: aliases
                ),
                scope: scope,
                launchContext: .inferred(from: scope)
            )
        )
    }
}
