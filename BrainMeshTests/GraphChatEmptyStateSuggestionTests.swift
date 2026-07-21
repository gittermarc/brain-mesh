import Foundation
import Testing
@testable import BrainMesh

struct GraphChatEmptyStateSuggestionTests {
    @Test
    func schemaSpecificSuggestionsAreDeterministicAndBounded() {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let snapshot = makeSnapshot()

        let first = GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: snapshot,
            scope: .entireGraph(graphScope)
        )
        let second = GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: snapshot,
            scope: .entireGraph(graphScope)
        )

        #expect(first == second)
        #expect(first.count == GraphChatEmptyStateSuggestionBuilder.maximumSuggestions)
        #expect(first.map(\.id) == [
            "date-F1",
            "status-F2",
            "choice-F3",
            "structure-E1"
        ])
        #expect(first.allSatisfy { $0.prompt.contains("Projekte") })
    }

    @Test
    func statusSuggestionUsesAvailableChoiceValue() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: makeSnapshot(),
            scope: .entireGraph(graphScope)
        )
        let status = try #require(suggestions.first(where: { $0.id == "status-F2" }))

        #expect(status.prompt.contains("Offen"))
        #expect(status.prompt.contains("Status"))
    }

    @Test
    func emptySchemaFallsBackToGraphNamedQuestion() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let snapshot = GraphSchemaSnapshot(
            graphName: "Reiseplanung",
            entities: [],
            truncation: GraphSchemaTruncation(
                sourceEntityCount: 0,
                includedEntityCount: 0,
                sourceFieldCount: 0,
                includedFieldCount: 0,
                sourceChoiceOptionCount: 0,
                includedChoiceOptionCount: 0,
                sourceExampleValueCount: 0,
                includedExampleValueCount: 0,
                stringsWereTruncated: false
            )
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: snapshot,
            scope: .entireGraph(graphScope)
        )
        let suggestion = try #require(suggestions.first)

        #expect(suggestion.id == "graph-overview")
        #expect(suggestion.prompt.contains("Reiseplanung"))
    }

    private func makeSnapshot() -> GraphSchemaSnapshot {
        GraphSchemaSnapshot(
            graphName: "Portfolio",
            entities: [
                GraphSchemaEntity(
                    alias: GraphEntityAlias("E1"),
                    name: "Projekte",
                    attributeCount: 20,
                    fields: [
                        GraphSchemaField(
                            alias: GraphFieldAlias("F1"),
                            name: "Zieldatum",
                            type: .date,
                            unit: nil,
                            choiceOptions: [],
                            isPinned: false,
                            sortIndex: 0,
                            exampleValues: [],
                            optionsWereTruncated: false,
                            examplesWereTruncated: false
                        ),
                        GraphSchemaField(
                            alias: GraphFieldAlias("F2"),
                            name: "Status",
                            type: .singleChoice,
                            unit: nil,
                            choiceOptions: ["Offen", "In Arbeit", "Fertig"],
                            isPinned: true,
                            sortIndex: 1,
                            exampleValues: [.choice("Offen")],
                            optionsWereTruncated: false,
                            examplesWereTruncated: false
                        ),
                        GraphSchemaField(
                            alias: GraphFieldAlias("F3"),
                            name: "Priorität",
                            type: .singleChoice,
                            unit: nil,
                            choiceOptions: ["Hoch", "Mittel", "Niedrig"],
                            isPinned: false,
                            sortIndex: 2,
                            exampleValues: [.choice("Hoch")],
                            optionsWereTruncated: false,
                            examplesWereTruncated: false
                        )
                    ],
                    fieldsWereTruncated: false
                )
            ],
            truncation: GraphSchemaTruncation(
                sourceEntityCount: 1,
                includedEntityCount: 1,
                sourceFieldCount: 3,
                includedFieldCount: 3,
                sourceChoiceOptionCount: 6,
                includedChoiceOptionCount: 6,
                sourceExampleValueCount: 2,
                includedExampleValueCount: 2,
                stringsWereTruncated: false
            )
        )
    }
}
