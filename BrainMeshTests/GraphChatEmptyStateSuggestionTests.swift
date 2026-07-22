import Foundation
import Testing
@testable import BrainMesh

struct GraphChatEmptyStateSuggestionTests {
    private let graphID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let projectEntityID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let personEntityID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let statusFieldID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let dueDateFieldID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    private let budgetFieldID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    @Test
    func graphScopeOffersOnlySupportedGraphQuestionsAndIsDeterministic() {
        let context = makeSuggestionContext(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            launchContext: .graph(name: "Portfolio")
        )

        let first = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)
        let second = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)

        #expect(first == second)
        #expect(first.count <= GraphChatEmptyStateSuggestionBuilder.maximumSuggestions)
        #expect(first.contains { $0.id == "graph-overview" })
        #expect(first.contains { $0.id == "graph-links" })
        #expect(Set(first.map(\.prompt)).count == first.count)
    }

    @Test
    func entityScopeUsesConcreteEntityAndExistingFields() {
        let scope = GraphChatScope.entity(
            projectEntityID,
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .entity(
                GraphChatEntityContextReference(id: projectEntityID, name: "Projekte")
            )
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)

        #expect(suggestions.isEmpty == false)
        #expect(suggestions.allSatisfy { $0.prompt.contains("Projekte") })
        #expect(suggestions.contains { $0.prompt.contains("Status") })
        #expect(suggestions.contains { $0.prompt.contains("Zieldatum") })
    }

    @Test
    func detailFieldScopeUsesConcreteField() {
        let entity = GraphChatEntityContextReference(
            id: projectEntityID,
            name: "Projekte"
        )
        let field = GraphChatFieldContextReference(
            id: statusFieldID,
            name: "Status",
            type: .singleChoice,
            entity: entity
        )
        let scope = GraphChatScope.detailField(
            statusFieldID,
            entityID: projectEntityID,
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .detailField(field)
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)

        #expect(suggestions.isEmpty == false)
        #expect(suggestions.allSatisfy { $0.prompt.contains("Status") })
        #expect(suggestions.contains { $0.id == "field-distribution-F-status" })
        #expect(suggestions.contains { $0.id == "field-common-F-status" } == false)
    }

    @Test
    func nodeScopeNeverOffersGraphStatistics() {
        let node = NodeRefKey(kind: .attribute, id: UUID())
        let scope = GraphChatScope.node(node, in: GraphScope(graphID: graphID))
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .node(
                GraphChatNodeContextReference(
                    node: node,
                    label: "Apollo",
                    entityID: projectEntityID,
                    entityName: "Projekte"
                )
            )
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)

        #expect(suggestions.contains { $0.prompt.contains("Apollo") })
        #expect(suggestions.contains { $0.id == "graph-overview" } == false)
        #expect(suggestions.contains { $0.id == "graph-links" } == false)
    }

    @Test
    func selectionScopeUsesActualSelectionAndSupportsComparison() throws {
        let first = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: UUID()),
            label: "Apollo",
            entityID: projectEntityID,
            entityName: "Projekte"
        )
        let second = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: UUID()),
            label: "Hermes",
            entityID: projectEntityID,
            entityName: "Projekte"
        )
        let scope = try GraphChatScope.selection(
            [first.node, second.node],
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .selection([first, second]),
            nodeEntityIDs: [first.node: projectEntityID, second.node: projectEntityID]
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)

        #expect(suggestions.contains { $0.prompt.contains("2") })
        #expect(suggestions.contains { $0.id == "selection-compare" })
        #expect(suggestions.contains { $0.id == "selection-choice-F-status" })
    }

    @Test
    func healthFindingScopeUsesFindingAndAffectedNodes() throws {
        let node = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: UUID()),
            label: "Apollo",
            entityID: projectEntityID,
            entityName: "Projekte"
        )
        let finding = GraphChatHealthFindingContext(
            id: "missing-status",
            title: "Fehlender Status",
            message: "Einträge besitzen keinen Status.",
            count: 1,
            affectedNodes: [node]
        )
        let scope = try GraphChatScope.healthFinding(
            id: finding.id,
            affectedNodes: [node.node],
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .healthFinding(finding),
            nodeEntityIDs: [node.node: projectEntityID]
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)

        #expect(suggestions.contains { $0.prompt.contains("Fehlender Status") })
        #expect(suggestions.contains { $0.id == "health-list-missing-status" })
    }

    @Test
    func missingSchemaReferenceProducesNoInvalidSuggestions() {
        let unknownField = GraphChatFieldContextReference(
            id: UUID(),
            name: "Gelöscht",
            type: .singleChoice,
            entity: GraphChatEntityContextReference(
                id: projectEntityID,
                name: "Projekte"
            )
        )
        let scope = GraphChatScope.detailField(
            unknownField.id,
            entityID: projectEntityID,
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .detailField(unknownField)
        )

        #expect(GraphChatEmptyStateSuggestionBuilder.suggestions(for: context).isEmpty)
    }


    @Test
    func largeSelectionDoesNotOfferBudgetExceedingDirectInspectionStarters() throws {
        let count = GraphChatToolBudgetPolicy.default.maximumCalls + 1
        let references = (0..<count).map { index in
            GraphChatNodeContextReference(
                node: NodeRefKey(kind: .attribute, id: UUID()),
                label: "Node \(index)"
            )
        }
        let scope = try GraphChatScope.selection(
            references.map(\.node),
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .selection(references),
            availableTools: [.getNode, .getNeighbors]
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)

        #expect(suggestions.isEmpty)
    }

    @Test
    func englishSuggestionsExposeCompleteVoiceOverText() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio"),
            language: .english
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(for: context)

        #expect(suggestions.isEmpty == false)
        #expect(suggestions.allSatisfy { $0.accessibilityLabel.isEmpty == false })
        #expect(suggestions.allSatisfy { $0.accessibilityHint.contains("supported") })
    }

    @Test
    func unavailableToolsAndModelSuppressUnsupportedSuggestions() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let noStats = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio"),
            availableTools: [.queryDetailValues]
        )
        let unavailableModel = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio"),
            modelAvailability: .unavailable(reason: .modelNotReady)
        )

        let noStatsSuggestions = GraphChatEmptyStateSuggestionBuilder.suggestions(for: noStats)
        #expect(noStatsSuggestions.contains { $0.id == "graph-overview" } == false)
        #expect(noStatsSuggestions.contains { $0.id == "graph-links" } == false)
        #expect(GraphChatEmptyStateSuggestionBuilder.suggestions(for: unavailableModel).isEmpty)
    }

    private func makeSuggestionContext(
        scope: GraphChatScope,
        launchContext: GraphChatLaunchContext,
        nodeEntityIDs: [NodeRefKey: UUID] = [:],
        availableTools: Set<GraphChatToolKind> = Set(GraphChatToolKind.allCases),
        modelAvailability: GraphChatAvailabilityPresentationState = .available,
        language: GraphChatResponseLanguage = .german
    ) -> GraphChatSuggestionContext {
        let projectAlias = GraphEntityAlias("E-projects")
        let personAlias = GraphEntityAlias("E-people")
        let statusAlias = GraphFieldAlias("F-status")
        let dueDateAlias = GraphFieldAlias("F-due")
        let budgetAlias = GraphFieldAlias("F-budget")
        let snapshot = GraphSchemaSnapshot(
            graphName: "Portfolio",
            entities: [
                GraphSchemaEntity(
                    alias: projectAlias,
                    name: "Projekte",
                    attributeCount: 20,
                    fields: [
                        GraphSchemaField(
                            alias: statusAlias,
                            name: "Status",
                            type: .singleChoice,
                            unit: nil,
                            choiceOptions: ["Offen", "Fertig"],
                            isPinned: true,
                            sortIndex: 0,
                            exampleValues: [.choice("Offen")],
                            optionsWereTruncated: false,
                            examplesWereTruncated: false
                        ),
                        GraphSchemaField(
                            alias: dueDateAlias,
                            name: "Zieldatum",
                            type: .date,
                            unit: nil,
                            choiceOptions: [],
                            isPinned: false,
                            sortIndex: 1,
                            exampleValues: [],
                            optionsWereTruncated: false,
                            examplesWereTruncated: false
                        ),
                        GraphSchemaField(
                            alias: budgetAlias,
                            name: "Budget",
                            type: .numberDouble,
                            unit: "EUR",
                            choiceOptions: [],
                            isPinned: false,
                            sortIndex: 2,
                            exampleValues: [.decimal(1_000)],
                            optionsWereTruncated: false,
                            examplesWereTruncated: false
                        )
                    ],
                    fieldsWereTruncated: false
                ),
                GraphSchemaEntity(
                    alias: personAlias,
                    name: "Personen",
                    attributeCount: 5,
                    fields: [],
                    fieldsWereTruncated: false
                )
            ],
            truncation: GraphSchemaTruncation(
                sourceEntityCount: 2,
                includedEntityCount: 2,
                sourceFieldCount: 3,
                includedFieldCount: 3,
                sourceChoiceOptionCount: 2,
                includedChoiceOptionCount: 2,
                sourceExampleValueCount: 2,
                includedExampleValueCount: 2,
                stringsWereTruncated: false
            )
        )
        let aliases = GraphSchemaAliasMap(
            graphScope: scope.graphScope,
            entitiesByAlias: [
                projectAlias: GraphSchemaEntityResolution(
                    alias: projectAlias,
                    entityID: projectEntityID,
                    name: "Projekte"
                ),
                personAlias: GraphSchemaEntityResolution(
                    alias: personAlias,
                    entityID: personEntityID,
                    name: "Personen"
                )
            ],
            fieldsByAlias: [
                statusAlias: GraphSchemaFieldResolution(
                    alias: statusAlias,
                    entityAlias: projectAlias,
                    entityID: projectEntityID,
                    fieldID: statusFieldID,
                    name: "Status",
                    type: .singleChoice,
                    unit: nil,
                    choiceOptions: ["Offen", "Fertig"]
                ),
                dueDateAlias: GraphSchemaFieldResolution(
                    alias: dueDateAlias,
                    entityAlias: projectAlias,
                    entityID: projectEntityID,
                    fieldID: dueDateFieldID,
                    name: "Zieldatum",
                    type: .date,
                    unit: nil,
                    choiceOptions: []
                ),
                budgetAlias: GraphSchemaFieldResolution(
                    alias: budgetAlias,
                    entityAlias: projectAlias,
                    entityID: projectEntityID,
                    fieldID: budgetFieldID,
                    name: "Budget",
                    type: .numberDouble,
                    unit: "EUR",
                    choiceOptions: []
                )
            ],
            nodeEntityIDs: nodeEntityIDs
        )
        return GraphChatSuggestionContext(
            schema: GraphSchemaContext(
                graphScope: scope.graphScope,
                snapshot: snapshot,
                aliases: aliases
            ),
            scope: scope,
            launchContext: launchContext,
            availableTools: availableTools,
            modelAvailability: modelAvailability,
            language: language
        )
    }
}
