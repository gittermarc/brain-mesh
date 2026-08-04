//
//  GraphChatContextualSuggestions.swift
//  BrainMesh
//
//  Scope-aware starter questions proven by the production compiler path.
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
    let capabilityID: GraphChatCapabilityID
    let title: String
    let prompt: String
    let kind: GraphChatSuggestionKind
    let accessibilityLabel: String
    let accessibilityHint: String
    let validation: GraphChatCapabilityQuestionValidation

    init(
        id: String,
        capabilityID: GraphChatCapabilityID,
        title: String,
        prompt: String,
        kind: GraphChatSuggestionKind = .detail,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        validation: GraphChatCapabilityQuestionValidation
    ) {
        self.id = id
        self.capabilityID = capabilityID
        self.title = title
        self.prompt = prompt
        self.kind = kind
        self.accessibilityLabel = accessibilityLabel ?? "\(title): \(prompt)"
        self.accessibilityHint = accessibilityHint ?? "Übernimmt diese Frage in das Eingabefeld."
        self.validation = validation
    }
}

nonisolated struct GraphChatSuggestionContext: Sendable {
    let schema: GraphSchemaContext
    let scope: GraphChatScope
    let launchContext: GraphChatLaunchContext
    let availableTools: Set<GraphChatToolKind>
    let modelAvailability: GraphChatAvailabilityPresentationState
    let language: GraphChatResponseLanguage
    let localeIdentifier: String

    init(
        schema: GraphSchemaContext,
        scope: GraphChatScope,
        launchContext: GraphChatLaunchContext,
        availableTools: Set<GraphChatToolKind> = Set(GraphChatToolKind.allCases),
        modelAvailability: GraphChatAvailabilityPresentationState = .available,
        language: GraphChatResponseLanguage = GraphChatResponseLanguageSelector.systemFallback(),
        localeIdentifier: String = Locale.current.identifier
    ) {
        self.schema = schema
        self.scope = scope
        self.launchContext = launchContext
        self.availableTools = availableTools
        self.modelAvailability = modelAvailability
        self.language = language
        self.localeIdentifier = localeIdentifier
    }
}

nonisolated enum GraphChatEmptyStateSuggestionBuilder {
    static let maximumSuggestions = 3
    static let maximumCandidateAttemptsPerCapability =
        GraphChatIntentLimitPolicy
            .default.maximumClarificationOptionCount

    static func suggestions(
        for context: GraphChatSuggestionContext
    ) -> [GraphChatEmptyStateSuggestion] {
        guard context.modelAvailability.isAvailable else {
            return []
        }

        let mentionCatalog = GraphMentionCatalog(
            schemaContext: context.schema
        )
        return (try? validatedSuggestions(
            for: context,
            mentionCatalog: mentionCatalog,
            validator: GraphChatCapabilityQuestionValidator()
        )) ?? []
    }

    static func validatedSuggestions(
        for context: GraphChatSuggestionContext,
        mentionCatalog: GraphMentionCatalog,
        validator: GraphChatCapabilityQuestionValidator
    ) throws -> [GraphChatEmptyStateSuggestion] {
        guard context.modelAvailability.isAvailable else {
            return []
        }
        try Task.checkCancellation()

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

        return try ranked(
            candidates,
            context: context,
            mentionCatalog: mentionCatalog,
            validator: validator
        )
    }

    /// A prompt-only snapshot cannot prove current UUID-backed bindings.
    /// Callers without the complete app-side catalog therefore receive no
    /// tappable question instead of an unverified compatibility suggestion.
    static func suggestions(
        for snapshot: GraphSchemaSnapshot,
        scope: GraphChatScope
    ) -> [GraphChatEmptyStateSuggestion] {
        _ = snapshot
        _ = scope
        return []
    }
}
