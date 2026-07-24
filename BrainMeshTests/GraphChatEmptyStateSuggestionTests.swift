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
    private let firstNodeID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    private let secondNodeID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!

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

    @Test
    func allLaunchContextsKeepStableIDsAndOrdering() throws {
        let graphScope = GraphScope(graphID: graphID)
        let entityReference = GraphChatEntityContextReference(
            id: projectEntityID,
            name: "Projekte"
        )
        let fieldReference = GraphChatFieldContextReference(
            id: statusFieldID,
            name: "Status",
            type: .singleChoice,
            entity: entityReference
        )
        let firstNode = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: firstNodeID),
            label: "Apollo",
            entityID: projectEntityID,
            entityName: "Projekte"
        )
        let secondNode = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: secondNodeID),
            label: "Hermes",
            entityID: projectEntityID,
            entityName: "Projekte"
        )
        let finding = GraphChatHealthFindingContext(
            id: "missing-status",
            title: "Fehlender Status",
            message: "Einträge besitzen keinen Status.",
            count: 2,
            affectedNodes: [firstNode, secondNode]
        )
        let nodeEntityIDs = [
            firstNode.node: projectEntityID,
            secondNode.node: projectEntityID
        ]
        let fixtures: [(GraphChatSuggestionContext, [String])] = [
            (
                makeSuggestionContext(
                    scope: .entireGraph(graphScope),
                    launchContext: .graph(name: "Portfolio")
                ),
                [
                    "graph-overview",
                    "graph-choice-F-status",
                    "graph-entity-list-E-projects",
                    "graph-links"
                ]
            ),
            (
                makeSuggestionContext(
                    scope: .entity(projectEntityID, in: graphScope),
                    launchContext: .entity(entityReference)
                ),
                [
                    "entity-list-E-projects",
                    "entity-choice-F-status",
                    "entity-missing-F-status",
                    "entity-newest-F-due"
                ]
            ),
            (
                makeSuggestionContext(
                    scope: .detailField(
                        statusFieldID,
                        entityID: projectEntityID,
                        in: graphScope
                    ),
                    launchContext: .detailField(fieldReference)
                ),
                [
                    "field-distribution-F-status",
                    "field-missing-F-status",
                    "field-nodes-F-status"
                ]
            ),
            (
                makeSuggestionContext(
                    scope: .node(firstNode.node, in: graphScope),
                    launchContext: .node(firstNode),
                    nodeEntityIDs: nodeEntityIDs
                ),
                [
                    "node-describe-40000000-0000-0000-0000-000000000001",
                    "node-neighbors-40000000-0000-0000-0000-000000000001",
                    "node-directions-40000000-0000-0000-0000-000000000001",
                    "node-details-40000000-0000-0000-0000-000000000001"
                ]
            ),
            (
                makeSuggestionContext(
                    scope: try .selection(
                        [firstNode.node, secondNode.node],
                        in: graphScope
                    ),
                    launchContext: .selection([firstNode, secondNode]),
                    nodeEntityIDs: nodeEntityIDs
                ),
                [
                    "selection-summary",
                    "selection-choice-F-status",
                    "selection-compare",
                    "selection-connections"
                ]
            ),
            (
                makeSuggestionContext(
                    scope: try .healthFinding(
                        id: finding.id,
                        affectedNodes: [firstNode.node, secondNode.node],
                        in: graphScope
                    ),
                    launchContext: .healthFinding(finding),
                    nodeEntityIDs: nodeEntityIDs
                ),
                [
                    "health-explain-missing-status",
                    "health-list-missing-status",
                    "health-group-missing-status",
                    "health-details-missing-status"
                ]
            )
        ]

        for (context, expectedIDs) in fixtures {
            let actualIDs = GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
                .map(\.id)
            #expect(actualIDs == expectedIDs)
        }
    }

    @Test
    func germanAndEnglishGraphCopyRemainsExact() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let german = GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: makeSuggestionContext(
                scope: scope,
                launchContext: .graph(name: "Portfolio"),
                language: .german
            )
        )
        let english = GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: makeSuggestionContext(
                scope: scope,
                launchContext: .graph(name: "Portfolio"),
                language: .english
            )
        )

        #expect(german.map(copySignature) == [
            "graph-overview|Graph überblicken|Gib mir einen Überblick über „Portfolio“ mit Anzahl der Entities, Attribute und direkten Verbindungen.|Übernimmt diese ausführbare Frage in das Eingabefeld.",
            "graph-choice-F-status|Werte verteilen|Wie verteilen sich die Werte von „Status“ bei „Projekte“?|Übernimmt diese ausführbare Frage in das Eingabefeld.",
            "graph-entity-list-E-projects|Einträge auflisten|Liste die ersten Einträge der Entity „Projekte“ mit ihren verfügbaren Details auf.|Übernimmt diese ausführbare Frage in das Eingabefeld.",
            "graph-links|Stärkste Verknüpfungen|Welche Nodes haben im gesamten Graphen die meisten direkten Verbindungen?|Übernimmt diese ausführbare Frage in das Eingabefeld."
        ])
        #expect(english.map(copySignature) == [
            "graph-overview|Review graph|Give me an overview of “Portfolio” with counts of entities, attributes, and direct links.|Places this supported question in the composer.",
            "graph-choice-F-status|Show distribution|How are the values of “Status” distributed across “Projekte”?|Places this supported question in the composer.",
            "graph-entity-list-E-projects|List entries|List the first entries of the “Projekte” entity with their available details.|Places this supported question in the composer.",
            "graph-links|Strongest links|Which nodes have the most direct links in the entire graph?|Places this supported question in the composer."
        ])
    }

    @Test
    func rankingUsesPriorityThenDeterministicTieBreakers() {
        let context = makeSuggestionContext(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            launchContext: .graph(name: "Portfolio")
        )
        let candidates = [
            makeCandidate(id: "late", priority: 30, kind: .detail),
            makeCandidate(id: "zeta", priority: 10, kind: .detail),
            makeCandidate(id: "alpha", priority: 10, kind: .detail),
            makeCandidate(id: "middle", priority: 20, kind: .detail)
        ]

        let suggestions = GraphChatEmptyStateSuggestionBuilder.ranked(
            candidates,
            context: context
        )

        #expect(suggestions.map(\.id) == ["alpha", "zeta", "middle", "late"])
    }

    @Test
    func rankingRemovesSemanticAndFoldedPromptDuplicates() {
        let context = makeSuggestionContext(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            launchContext: .graph(name: "Portfolio")
        )
        let candidates = [
            makeCandidate(
                id: "semantic-first",
                semanticKey: "same-meaning",
                priority: 10,
                prompt: "Erster Prompt"
            ),
            makeCandidate(
                id: "semantic-second",
                semanticKey: "same-meaning",
                priority: 20,
                prompt: "Anderer Prompt"
            ),
            makeCandidate(
                id: "prompt-first",
                semanticKey: "prompt-one",
                priority: 30,
                prompt: "Überblick"
            ),
            makeCandidate(
                id: "prompt-second",
                semanticKey: "prompt-two",
                priority: 40,
                prompt: "uberblick"
            )
        ]

        let suggestions = GraphChatEmptyStateSuggestionBuilder.ranked(
            candidates,
            context: context
        )

        #expect(suggestions.map(\.id) == ["semantic-first", "prompt-first"])
    }

    @Test
    func rankingPrefersKindDiversityAndCapsTheResultAtFour() {
        let context = makeSuggestionContext(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            launchContext: .graph(name: "Portfolio")
        )
        let candidates = [
            makeCandidate(id: "detail-first", priority: 10, kind: .detail),
            makeCandidate(id: "detail-second", priority: 20, kind: .detail),
            makeCandidate(id: "statistics", priority: 30, kind: .statistics),
            makeCandidate(id: "list", priority: 40, kind: .list),
            makeCandidate(id: "structure", priority: 50, kind: .structure),
            makeCandidate(id: "detail-third", priority: 60, kind: .detail)
        ]

        let suggestions = GraphChatEmptyStateSuggestionBuilder.ranked(
            candidates,
            context: context
        )

        #expect(suggestions.map(\.id) == [
            "detail-first",
            "statistics",
            "list",
            "structure"
        ])
        #expect(suggestions.count == GraphChatEmptyStateSuggestionBuilder.maximumSuggestions)
    }

    @Test
    func rankingSuppressesOnlyCandidatesWhoseToolsAreUnavailable() {
        let context = makeSuggestionContext(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            launchContext: .graph(name: "Portfolio"),
            availableTools: [.queryDetailValues]
        )
        let candidates = [
            makeCandidate(
                id: "query",
                priority: 10,
                kind: .list,
                requiredTools: [.queryDetailValues]
            ),
            makeCandidate(
                id: "stats",
                priority: 20,
                kind: .statistics,
                requiredTools: [.graphStats]
            ),
            makeCandidate(
                id: "both",
                priority: 30,
                kind: .detail,
                requiredTools: [.queryDetailValues, .graphStats]
            )
        ]

        let suggestions = GraphChatEmptyStateSuggestionBuilder.ranked(
            candidates,
            context: context
        )

        #expect(suggestions.map(\.id) == ["query"])
    }

    @Test
    func mismatchedEntityFieldNodeAndSelectionReferencesProduceNoStarters() throws {
        let graphScope = GraphScope(graphID: graphID)
        let foreignEntityID = UUID(uuidString: "20000000-0000-0000-0000-000000000099")!
        let foreignNode = GraphChatNodeContextReference(
            node: NodeRefKey(kind: .attribute, id: secondNodeID),
            label: "Fremd"
        )
        let scopedNode = NodeRefKey(kind: .attribute, id: firstNodeID)
        let entityContext = makeSuggestionContext(
            scope: .entity(foreignEntityID, in: graphScope),
            launchContext: .entity(
                GraphChatEntityContextReference(id: foreignEntityID, name: "Gelöscht")
            )
        )
        let fieldContext = makeSuggestionContext(
            scope: .detailField(
                statusFieldID,
                entityID: projectEntityID,
                in: graphScope
            ),
            launchContext: .detailField(
                GraphChatFieldContextReference(
                    id: statusFieldID,
                    name: "Status",
                    type: .singleChoice,
                    entity: GraphChatEntityContextReference(
                        id: foreignEntityID,
                        name: "Fremd"
                    )
                )
            )
        )
        let nodeContext = makeSuggestionContext(
            scope: .node(scopedNode, in: graphScope),
            launchContext: .node(foreignNode)
        )
        let selectionContext = makeSuggestionContext(
            scope: try .selection([scopedNode], in: graphScope),
            launchContext: .selection([foreignNode])
        )

        #expect(GraphChatEmptyStateSuggestionBuilder.suggestions(for: entityContext).isEmpty)
        #expect(GraphChatEmptyStateSuggestionBuilder.suggestions(for: fieldContext).isEmpty)
        #expect(GraphChatEmptyStateSuggestionBuilder.suggestions(for: nodeContext).isEmpty)
        #expect(GraphChatEmptyStateSuggestionBuilder.suggestions(for: selectionContext).isEmpty)
    }

    @Test
    func healthFindingAboveDirectInspectionBudgetProducesNoSelectionStarter() throws {
        let graphScope = GraphScope(graphID: graphID)
        let references = (0...GraphChatToolBudgetPolicy.default.maximumCalls).map { index in
            GraphChatNodeContextReference(
                node: NodeRefKey(
                    kind: .attribute,
                    id: UUID(uuidString: String(format: "40000000-0000-0000-0000-%012d", index + 10))!
                ),
                label: "Node \(index)"
            )
        }
        let finding = GraphChatHealthFindingContext(
            id: "large-finding",
            title: "Großer Befund",
            message: "Viele betroffene Nodes.",
            count: references.count,
            affectedNodes: references
        )
        let context = makeSuggestionContext(
            scope: try .healthFinding(
                id: finding.id,
                affectedNodes: references.map(\.node),
                in: graphScope
            ),
            launchContext: .healthFinding(finding),
            availableTools: [.getNode]
        )

        #expect(GraphChatEmptyStateSuggestionBuilder.suggestions(for: context).isEmpty)
    }

    @Test
    func compatibilityEntryRemainsDeterministic() {
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio")
        )

        let first = GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: context.schema.snapshot,
            scope: scope
        )
        let second = GraphChatEmptyStateSuggestionBuilder.suggestions(
            for: context.schema.snapshot,
            scope: scope
        )

        #expect(first == second)
        #expect(first.map(\.id) == [
            "graph-overview",
            "graph-choice-F-status",
            "graph-entity-list-E-projects",
            "graph-links"
        ])
    }

    private func makeCandidate(
        id: String,
        semanticKey: String? = nil,
        priority: Int,
        kind: GraphChatSuggestionKind = .detail,
        requiredTools: Set<GraphChatToolKind> = [],
        title: String = "Titel",
        prompt: String? = nil
    ) -> GraphChatEmptyStateSuggestionBuilder.Candidate {
        GraphChatEmptyStateSuggestionBuilder.Candidate(
            id: id,
            semanticKey: semanticKey ?? id,
            priority: priority,
            kind: kind,
            requiredTools: requiredTools,
            title: title,
            prompt: prompt ?? "Prompt \(id)"
        )
    }

    private func copySignature(
        _ suggestion: GraphChatEmptyStateSuggestion
    ) -> String {
        [
            suggestion.id,
            suggestion.title,
            suggestion.prompt,
            suggestion.accessibilityHint
        ].joined(separator: "|")
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
