//
//  GraphChatPreviewSupport.swift
//  BrainMesh
//
//  Static value-only preview dependencies for the internal chat screen.
//

#if DEBUG
import Foundation
import SwiftUI

private actor GraphChatPreviewOrchestrator: GraphChatOrchestrating {
    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream {
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .entity,
                sourceID: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
            ),
            summary: "Projekt Atlas",
            fieldValues: [
                GraphEvidenceFieldValue(
                    fieldID: nil,
                    fieldName: "Status",
                    value: .choice("In Arbeit"),
                    unit: nil
                )
            ],
            navigationTitle: "Projekt Atlas",
            identitySuffix: "preview"
        )
        let answer = GraphChatAnswer(
            directAnswer: "Projekt Atlas befindet sich im Status „In Arbeit“.",
            evidence: [evidence],
            appliedFilters: [
                GraphChatAppliedFilter(
                    fieldName: "Status",
                    operationDescription: "entspricht",
                    valueDescription: "In Arbeit"
                )
            ],
            followUpSuggestions: [
                GraphChatFollowUpSuggestion(
                    title: "Offene Aufgaben anzeigen",
                    prompt: "Welche offenen Aufgaben gehören zu Projekt Atlas?"
                )
            ],
            hasInsufficientEvidence: false
        )
        return AsyncStream { continuation in
            continuation.yield(.started(requestID: UUID()))
            continuation.yield(.partialAnswer("Projekt Atlas befindet sich"))
            continuation.yield(.completed(answer))
            continuation.finish()
        }
    }

    func cancelCurrentGeneration() async {}
    func discardSession() async {}
}

private actor GraphChatPreviewSchemaProvider: GraphSchemaSnapshotProviding {
    let context: GraphSchemaContext

    init(context: GraphSchemaContext) {
        self.context = context
    }

    func makeSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) async throws -> GraphSchemaContext {
        context
    }
}

private nonisolated struct GraphChatPreviewAvailabilityProvider: GraphChatAvailabilityProviding {
    func availability() async -> GraphChatModelAvailability {
        .available
    }
}

private nonisolated struct GraphChatPreviewIndexProvider: GraphChatIndexStatusProviding {
    func presentationState(
        for scope: GraphScope
    ) async -> GraphChatIndexPresentationState {
        .ready(documentCount: 128)
    }
}

private actor GraphChatPreviewHistoryStore: GraphChatHistoryStoring {
    private var values: [GraphChatTranscriptMessage]

    init(values: [GraphChatTranscriptMessage]) {
        self.values = values
    }

    func messages(for scope: GraphChatScope) async -> [GraphChatTranscriptMessage] {
        values
    }

    func save(
        _ messages: [GraphChatTranscriptMessage],
        for scope: GraphChatScope
    ) async {
        values = messages
    }

    func removeMessages(for scope: GraphChatScope) async {
        values = []
    }
}

@MainActor
private enum GraphChatPreviewFactory {
    static func makeViewModel() -> GraphChatViewModel {
        let graphID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
        let graphScope = GraphScope(graphID: graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let context = makeSchemaContext(graphScope: graphScope)

        return GraphChatViewModel(
            graphScope: graphScope,
            chatScope: chatScope,
            graphName: "Produktportfolio",
            orchestrator: GraphChatPreviewOrchestrator(),
            schemaProvider: GraphChatPreviewSchemaProvider(context: context),
            availabilityProvider: GraphChatPreviewAvailabilityProvider(),
            indexStatusProvider: GraphChatPreviewIndexProvider(),
            historyStore: GraphChatPreviewHistoryStore(values: []),
            navigationActions: .disabled
        )
    }

    private static func makeSchemaContext(
        graphScope: GraphScope
    ) -> GraphSchemaContext {
        let entityID = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
        let statusID = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
        let dateID = UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!
        let entityAlias = GraphEntityAlias("E1")
        let statusAlias = GraphFieldAlias("F1")
        let dateAlias = GraphFieldAlias("F2")
        let fields = [
            GraphSchemaField(
                alias: statusAlias,
                name: "Status",
                type: .singleChoice,
                unit: nil,
                choiceOptions: ["Offen", "In Arbeit", "Fertig"],
                isPinned: true,
                sortIndex: 0,
                exampleValues: [.choice("In Arbeit")],
                optionsWereTruncated: false,
                examplesWereTruncated: false
            ),
            GraphSchemaField(
                alias: dateAlias,
                name: "Zieldatum",
                type: .date,
                unit: nil,
                choiceOptions: [],
                isPinned: false,
                sortIndex: 1,
                exampleValues: [],
                optionsWereTruncated: false,
                examplesWereTruncated: false
            )
        ]
        let snapshot = GraphSchemaSnapshot(
            graphName: "Produktportfolio",
            entities: [
                GraphSchemaEntity(
                    alias: entityAlias,
                    name: "Projekte",
                    attributeCount: 24,
                    fields: fields,
                    fieldsWereTruncated: false
                )
            ],
            truncation: GraphSchemaTruncation(
                sourceEntityCount: 1,
                includedEntityCount: 1,
                sourceFieldCount: 2,
                includedFieldCount: 2,
                sourceChoiceOptionCount: 3,
                includedChoiceOptionCount: 3,
                sourceExampleValueCount: 1,
                includedExampleValueCount: 1,
                stringsWereTruncated: false
            )
        )
        let aliases = GraphSchemaAliasMap(
            graphScope: graphScope,
            entitiesByAlias: [
                entityAlias: GraphSchemaEntityResolution(
                    alias: entityAlias,
                    entityID: entityID,
                    name: "Projekte"
                )
            ],
            fieldsByAlias: [
                statusAlias: GraphSchemaFieldResolution(
                    alias: statusAlias,
                    entityAlias: entityAlias,
                    entityID: entityID,
                    fieldID: statusID,
                    name: "Status",
                    type: .singleChoice,
                    unit: nil,
                    choiceOptions: ["Offen", "In Arbeit", "Fertig"]
                ),
                dateAlias: GraphSchemaFieldResolution(
                    alias: dateAlias,
                    entityAlias: entityAlias,
                    entityID: entityID,
                    fieldID: dateID,
                    name: "Zieldatum",
                    type: .date,
                    unit: nil,
                    choiceOptions: []
                )
            ],
            nodeEntityIDs: [
                NodeRefKey(kind: .entity, id: entityID): entityID
            ]
        )
        return GraphSchemaContext(
            graphScope: graphScope,
            snapshot: snapshot,
            aliases: aliases
        )
    }
}

#Preview("Graph Chat") {
    NavigationStack {
        GraphChatView(viewModel: GraphChatPreviewFactory.makeViewModel())
    }
}
#endif
