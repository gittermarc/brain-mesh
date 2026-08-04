//
//  GraphChatSuggestionsInstrumentation.swift
//  BrainMesh
//
//  Deterministic, opt-in counters for the production suggestions pipeline.
//

import Foundation

nonisolated enum GraphChatSuggestionsInstrumentationEvent:
    Hashable,
    Sendable
{
    case snapshotBuild
    case mentionCatalogBuild
    case capabilityValidation(GraphChatCapabilityID)
    case intentCompiler(GraphChatCapabilityCompilerFamily)
    case readPlanValidation(GraphChatCapabilityID)
}

nonisolated struct GraphChatSuggestionsInstrumentation:
    Sendable
{
    private let eventHandler:
        @Sendable (GraphChatSuggestionsInstrumentationEvent) -> Void

    init(
        eventHandler: @escaping @Sendable (
            GraphChatSuggestionsInstrumentationEvent
        ) -> Void = { _ in }
    ) {
        self.eventHandler = eventHandler
    }

    func record(
        _ event: GraphChatSuggestionsInstrumentationEvent
    ) {
        eventHandler(event)
    }

    static let disabled = GraphChatSuggestionsInstrumentation()
}
