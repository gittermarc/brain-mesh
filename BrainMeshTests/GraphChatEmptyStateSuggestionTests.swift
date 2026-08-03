import Foundation
import Testing
@testable import BrainMesh

struct GraphChatEmptyStateSuggestionTests {
    private let graphID = UUID(
        uuidString: "10000000-0000-0000-0000-000000000001"
    )!
    private let projectEntityID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000001"
    )!
    private let personEntityID = UUID(
        uuidString: "20000000-0000-0000-0000-000000000002"
    )!
    private let statusFieldID = UUID(
        uuidString: "30000000-0000-0000-0000-000000000001"
    )!
    private let dueDateFieldID = UUID(
        uuidString: "30000000-0000-0000-0000-000000000002"
    )!
    private let budgetFieldID = UUID(
        uuidString: "30000000-0000-0000-0000-000000000003"
    )!
    private let firstNodeID = UUID(
        uuidString: "40000000-0000-0000-0000-000000000001"
    )!
    private let secondNodeID = UUID(
        uuidString: "40000000-0000-0000-0000-000000000002"
    )!

    @Test
    func graphScopeOffersOnlySupportedGraphQuestionsAndIsDeterministic() {
        let context = makeSuggestionContext(
            scope: .entireGraph(
                GraphScope(graphID: graphID)
            ),
            launchContext: .graph(name: "Portfolio")
        )

        let first = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)
        let second = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(first == second)
        #expect(
            first.count
                <= GraphChatEmptyStateSuggestionBuilder
                    .maximumSuggestions
        )
        #expect(first.map(\.capabilityID) == [
            .entityEntries,
            .nodeProfile,
            .directRelationships,
        ])
        #expect(Set(first.map(\.prompt)).count == first.count)
        #expect(
            first.allSatisfy {
                $0.validation.capabilityID
                    == $0.capabilityID
            }
        )
    }

    @Test
    func entityScopeUsesConcreteEntityWithoutUnprovenFieldQuestions() {
        let scope = GraphChatScope.entity(
            projectEntityID,
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .entity(
                GraphChatEntityContextReference(
                    id: projectEntityID,
                    name: "Untrusted name"
                )
            )
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(suggestions.isEmpty == false)
        #expect(
            suggestions.allSatisfy {
                $0.prompt.contains("Status") == false
                    && $0.prompt.contains("Zieldatum")
                        == false
                    && $0.prompt.contains("Budget")
                        == false
            }
        )
        #expect(
            suggestions.contains {
                $0.capabilityID == .entityEntries
                    && $0.prompt.contains("Projekte")
            }
        )
        #expect(
            suggestions.contains {
                $0.prompt.contains("Untrusted name")
            } == false
        )
    }

    @Test
    func detailFieldScopeDoesNotPromiseProviderDependentFieldOperations() {
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

        // Field filtering, sorting, and grouping currently require the free
        // semantic interpreter, so no guaranteed starter is displayed.
        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
                .isEmpty
        )
    }

    @Test
    func nodeScopeNeverOffersGraphStatistics() {
        let node = firstNode
        let scope = GraphChatScope.node(
            node,
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .node(
                nodeReference(node, label: "Untrusted label")
            )
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(suggestions.map(\.capabilityID) == [
            .nodeProfile,
            .directRelationships,
        ])
        #expect(
            suggestions.allSatisfy {
                $0.prompt.contains("Apollo")
            }
        )
        #expect(
            suggestions.contains {
                $0.kind == .statistics
            } == false
        )
    }

    @Test
    func selectionScopeUsesActualSelectionAndDoesNotPromiseComparison() throws {
        let first = nodeReference(firstNode, label: "Apollo")
        let second = nodeReference(secondNode, label: "Hermes")
        let scope = try GraphChatScope.selection(
            [first.node, second.node],
            in: GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .selection([first, second])
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(suggestions.map(\.capabilityID) == [
            .nodeProfile,
            .directRelationships,
        ])
        #expect(
            suggestions.contains {
                $0.prompt.contains("Apollo")
                    && $0.prompt.contains("Hermes")
            }
        )
        #expect(
            suggestions.contains {
                BMSearch.fold($0.prompt)
                    .contains("vergleich")
                    || BMSearch.fold($0.prompt)
                        .contains("compare")
            } == false
        )
    }

    @Test
    func healthFindingScopeDoesNotPromiseProviderInterpretation() throws {
        let node = nodeReference(firstNode, label: "Apollo")
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
            launchContext: .healthFinding(finding)
        )

        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
                .isEmpty
        )
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

        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
                .isEmpty
        )
    }

    @Test
    func largeSelectionDoesNotOfferBudgetExceedingDirectInspectionStarters() throws {
        let count =
            GraphChatToolBudgetPolicy.default.maximumCalls + 1
        let references = (0..<count).map { index in
            GraphChatNodeContextReference(
                node: NodeRefKey(
                    kind: .attribute,
                    id: UUID()
                ),
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

        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
                .isEmpty
        )
    }

    @Test
    func englishSuggestionsExposeCompleteVoiceOverText() {
        let scope = GraphChatScope.entireGraph(
            GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio"),
            language: .english
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(suggestions.isEmpty == false)
        #expect(
            suggestions.allSatisfy {
                $0.accessibilityLabel.isEmpty == false
            }
        )
        #expect(
            suggestions.allSatisfy {
                $0.accessibilityHint.contains("verified")
            }
        )
    }

    @Test
    func unavailableToolsAndModelSuppressUnsupportedSuggestions() {
        let scope = GraphChatScope.entireGraph(
            GraphScope(graphID: graphID)
        )
        let queryOnly = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio"),
            availableTools: [.queryDetailValues]
        )
        let unavailableModel = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio"),
            modelAvailability:
                .unavailable(reason: .modelNotReady)
        )

        let querySuggestions =
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: queryOnly)
        #expect(querySuggestions.map(\.capabilityID) == [
            .entityEntries,
        ])
        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: unavailableModel)
                .isEmpty
        )
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
        let first = nodeReference(firstNode, label: "Apollo")
        let second = nodeReference(secondNode, label: "Hermes")
        let finding = GraphChatHealthFindingContext(
            id: "missing-status",
            title: "Fehlender Status",
            message: "Einträge besitzen keinen Status.",
            count: 2,
            affectedNodes: [first, second]
        )
        let fixtures: [(
            GraphChatSuggestionContext,
            [String]
        )] = [
            (
                makeSuggestionContext(
                    scope: .entireGraph(graphScope),
                    launchContext:
                        .graph(name: "Portfolio")
                ),
                [
                    "graph-entity-entries-20000000-0000-0000-0000-000000000001",
                    "node-profile-40000000-0000-0000-0000-000000000001",
                    "node-relationships-40000000-0000-0000-0000-000000000001",
                ]
            ),
            (
                makeSuggestionContext(
                    scope: .entity(
                        projectEntityID,
                        in: graphScope
                    ),
                    launchContext: .entity(
                        entityReference
                    )
                ),
                [
                    "entity-entries-20000000-0000-0000-0000-000000000001",
                    "node-profile-40000000-0000-0000-0000-000000000001",
                    "node-relationships-40000000-0000-0000-0000-000000000001",
                ]
            ),
            (
                makeSuggestionContext(
                    scope: .detailField(
                        statusFieldID,
                        entityID: projectEntityID,
                        in: graphScope
                    ),
                    launchContext:
                        .detailField(fieldReference)
                ),
                []
            ),
            (
                makeSuggestionContext(
                    scope: .node(
                        first.node,
                        in: graphScope
                    ),
                    launchContext: .node(first)
                ),
                [
                    "node-profile-40000000-0000-0000-0000-000000000001",
                    "node-relationships-40000000-0000-0000-0000-000000000001",
                ]
            ),
            (
                makeSuggestionContext(
                    scope: try .selection(
                        [first.node, second.node],
                        in: graphScope
                    ),
                    launchContext:
                        .selection([first, second])
                ),
                [
                    "selection-node-profile-40000000-0000-0000-0000-000000000001",
                    "selection-direct-relationships",
                ]
            ),
            (
                makeSuggestionContext(
                    scope: try .healthFinding(
                        id: finding.id,
                        affectedNodes: [
                            first.node,
                            second.node,
                        ],
                        in: graphScope
                    ),
                    launchContext:
                        .healthFinding(finding)
                ),
                []
            ),
        ]

        for (context, expectedIDs) in fixtures {
            let actualIDs =
                GraphChatEmptyStateSuggestionBuilder
                    .suggestions(for: context)
                    .map(\.id)
            #expect(actualIDs == expectedIDs)
        }
    }

    @Test
    func germanAndEnglishGraphCopyRemainsExact() {
        let scope = GraphChatScope.entireGraph(
            GraphScope(graphID: graphID)
        )
        let german = GraphChatEmptyStateSuggestionBuilder
            .suggestions(
                for: makeSuggestionContext(
                    scope: scope,
                    launchContext:
                        .graph(name: "Portfolio"),
                    language: .german
                )
            )
        let english = GraphChatEmptyStateSuggestionBuilder
            .suggestions(
                for: makeSuggestionContext(
                    scope: scope,
                    launchContext:
                        .graph(name: "Portfolio"),
                    language: .english
                )
            )

        #expect(german.map(copySignature) == [
            "graph-entity-entries-20000000-0000-0000-0000-000000000001|Einträge auflisten|Zeige mir alle „Projekte“.|Übernimmt diese geprüfte Frage in das Eingabefeld.",
            "node-profile-40000000-0000-0000-0000-000000000001|Profil anzeigen|Zeige mir Details zu „Apollo“.|Übernimmt diese geprüfte Frage in das Eingabefeld.",
            "node-relationships-40000000-0000-0000-0000-000000000001|Direkte Verbindungen|Zeige alle direkten Verbindungen von „Apollo“.|Übernimmt diese geprüfte Frage in das Eingabefeld.",
        ])
        #expect(english.map(copySignature) == [
            "graph-entity-entries-20000000-0000-0000-0000-000000000001|List entries|Show me all “Projekte”.|Places this verified question in the composer.",
            "node-profile-40000000-0000-0000-0000-000000000001|Show profile|Show me details about “Apollo”.|Places this verified question in the composer.",
            "node-relationships-40000000-0000-0000-0000-000000000001|Direct connections|Show all direct links for “Apollo”.|Places this verified question in the composer.",
        ])
    }

    @Test
    func rankingUsesPriorityThenDeterministicTieBreakers() {
        let candidates = [
            makeCandidate(
                id: "late",
                priority: 30,
                kind: .detail
            ),
            makeCandidate(
                id: "zeta",
                priority: 10,
                kind: .detail
            ),
            makeCandidate(
                id: "alpha",
                priority: 10,
                kind: .detail
            ),
            makeCandidate(
                id: "middle",
                priority: 20,
                kind: .detail
            ),
        ]

        let selected = GraphChatEmptyStateSuggestionBuilder
            .selectedCandidates(candidates)

        #expect(selected.map(\.id) == [
            "alpha",
            "zeta",
            "middle",
        ])
    }

    @Test
    func rankingRemovesSemanticAndFoldedPromptDuplicates() {
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
            ),
        ]

        let selected = GraphChatEmptyStateSuggestionBuilder
            .selectedCandidates(candidates)

        #expect(selected.map(\.id) == [
            "semantic-first",
            "prompt-first",
        ])
    }

    @Test
    func rankingPrefersKindDiversityAndCapsTheResultAtVisibleLimit() {
        let candidates = [
            makeCandidate(
                id: "detail-first",
                priority: 10,
                kind: .detail
            ),
            makeCandidate(
                id: "detail-second",
                priority: 20,
                kind: .detail
            ),
            makeCandidate(
                id: "statistics",
                priority: 30,
                kind: .statistics
            ),
            makeCandidate(
                id: "list",
                priority: 40,
                kind: .list
            ),
            makeCandidate(
                id: "structure",
                priority: 50,
                kind: .structure
            ),
            makeCandidate(
                id: "detail-third",
                priority: 60,
                kind: .detail
            ),
        ]

        let selected = GraphChatEmptyStateSuggestionBuilder
            .selectedCandidates(candidates)

        #expect(selected.map(\.id) == [
            "detail-first",
            "statistics",
            "list",
        ])
        #expect(
            selected.count
                == GraphChatEmptyStateSuggestionBuilder
                    .maximumSuggestions
        )
    }

    @Test
    func rankingSuppressesOnlyCandidatesWhoseToolsAreUnavailable() {
        let context = makeSuggestionContext(
            scope: .entireGraph(
                GraphScope(graphID: graphID)
            ),
            launchContext: .graph(name: "Portfolio"),
            availableTools: [.queryDetailValues]
        )
        let candidates = [
            makeCandidate(
                id: "query",
                priority: 10,
                kind: .list,
                capabilityID: .entityEntries
            ),
            makeCandidate(
                id: "node",
                priority: 20,
                kind: .detail,
                capabilityID: .nodeProfile
            ),
            makeCandidate(
                id: "links",
                priority: 30,
                kind: .structure,
                capabilityID: .directRelationships
            ),
        ]

        let eligible = GraphChatEmptyStateSuggestionBuilder
            .toolEligibleCandidates(
                candidates,
                context: context
            )

        #expect(eligible.map(\.id) == ["query"])
    }

    @Test
    func mismatchedEntityFieldNodeAndSelectionReferencesProduceNoStarters() throws {
        let graphScope = GraphScope(graphID: graphID)
        let foreignEntityID = UUID(
            uuidString:
                "20000000-0000-0000-0000-000000000099"
        )!
        let foreignNode = GraphChatNodeContextReference(
            node: secondNode,
            label: "Fremd"
        )
        let entityContext = makeSuggestionContext(
            scope: .entity(
                foreignEntityID,
                in: graphScope
            ),
            launchContext: .entity(
                GraphChatEntityContextReference(
                    id: foreignEntityID,
                    name: "Gelöscht"
                )
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
                    entity:
                        GraphChatEntityContextReference(
                            id: foreignEntityID,
                            name: "Fremd"
                        )
                )
            )
        )
        let nodeContext = makeSuggestionContext(
            scope: .node(firstNode, in: graphScope),
            launchContext: .node(foreignNode)
        )
        let selectionContext = makeSuggestionContext(
            scope: try .selection(
                [firstNode],
                in: graphScope
            ),
            launchContext: .selection([foreignNode])
        )

        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: entityContext)
                .isEmpty
        )
        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: fieldContext)
                .isEmpty
        )
        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: nodeContext)
                .isEmpty
        )
        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: selectionContext)
                .isEmpty
        )
    }

    @Test
    func healthFindingAboveDirectInspectionBudgetProducesNoSelectionStarter() throws {
        let graphScope = GraphScope(graphID: graphID)
        let references = (0...GraphChatToolBudgetPolicy
            .default.maximumCalls).map { index in
            GraphChatNodeContextReference(
                node: NodeRefKey(
                    kind: .attribute,
                    id: UUID()
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

        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
                .isEmpty
        )
    }

    @Test
    func compatibilityEntryRemainsDeterministic() {
        let scope = GraphChatScope.entireGraph(
            GraphScope(graphID: graphID)
        )
        let context = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio")
        )

        let first = GraphChatEmptyStateSuggestionBuilder
            .suggestions(
                for: context.schema.snapshot,
                scope: scope
            )
        let second = GraphChatEmptyStateSuggestionBuilder
            .suggestions(
                for: context.schema.snapshot,
                scope: scope
            )

        #expect(first == second)
        #expect(first.isEmpty)
    }

    @Test
    func everyVisibleQuestionRevalidatesThroughProductionCode() {
        let context = makeSuggestionContext(
            scope: .entireGraph(
                GraphScope(graphID: graphID)
            ),
            launchContext: .graph(name: "Portfolio")
        )
        let validator =
            GraphChatCapabilityQuestionValidator()

        for suggestion in
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
        {
            let capability =
                GraphChatCapabilityCatalog.capability(
                    withID: suggestion.capabilityID
                )
            #expect(capability != nil)
            let validation = capability.flatMap {
                validator.validate(
                    question: suggestion.prompt,
                    capability: $0,
                    schemaContext: context.schema,
                    chatScope: context.scope,
                    language: context.language
                )
            }
            #expect(validation == suggestion.validation)
        }
    }

    @Test
    func ambiguousNamesAreSkippedWithoutSelectingAnInternalIdentity() {
        let context = makeSuggestionContext(
            scope: .entireGraph(
                GraphScope(graphID: graphID)
            ),
            launchContext: .graph(name: "Portfolio"),
            duplicateNodeName: true
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(
            suggestions.contains {
                $0.prompt.contains("Apollo")
            } == false
        )
        #expect(
            suggestions.allSatisfy {
                containsTechnicalIdentifier($0.prompt)
                    == false
            }
        )
    }

    @Test
    func ambiguousEntityNamesNeverProduceAnEntityStarter() {
        let context = makeSuggestionContext(
            scope: .entireGraph(
                GraphScope(graphID: graphID)
            ),
            launchContext: .graph(name: "Portfolio"),
            duplicateEntityName: true
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(
            suggestions.contains {
                $0.capabilityID == .entityEntries
            } == false
        )
    }

    @Test
    func uuidLikeDisplayNamesAreNeverRendered() {
        let scope = GraphChatScope.entireGraph(
            GraphScope(graphID: graphID)
        )
        let base = makeSuggestionContext(
            scope: scope,
            launchContext: .graph(name: "Portfolio")
        )
        let unsafeName = firstNodeID.uuidString
        var nodes = base.schema.foundationalAliases
            .nodesByKey
        nodes[firstNode] = GraphSchemaNodeResolution(
            node: firstNode,
            ownerEntityID: projectEntityID,
            displayName: unsafeName
        )
        let aliases = GraphSchemaAliasMap(
            graphScope: scope.graphScope,
            entitiesByAlias: base.schema
                .foundationalAliases.entitiesByAlias,
            fieldsByAlias: base.schema
                .foundationalAliases.fieldsByAlias,
            nodeEntityIDs: base.schema
                .foundationalAliases.nodeEntityIDs,
            nodesByKey: nodes
        )
        let context = GraphChatSuggestionContext(
            schema: GraphSchemaContext(
                graphScope: scope.graphScope,
                snapshot: base.schema.snapshot,
                aliases: aliases
            ),
            scope: scope,
            launchContext: .graph(name: "Portfolio"),
            language: .german
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(
            suggestions.contains {
                $0.prompt.contains(unsafeName)
            } == false
        )
        #expect(
            suggestions.allSatisfy {
                containsTechnicalIdentifier($0.prompt)
                    == false
            }
        )
    }

    @Test
    func fullFoundationalCatalogIsUsedBeyondPromptSnapshot() {
        let context = makeFoundationalOnlyEntityContext()

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(
            suggestions.contains {
                $0.capabilityID == .entityEntries
                    && $0.prompt.contains("Ärger & Öl")
            }
        )
    }

    @Test
    func unsupportedSuperlativesAndAggregationsAreNeverSuggested() {
        let context = makeSuggestionContext(
            scope: .entireGraph(
                GraphScope(graphID: graphID)
            ),
            launchContext: .graph(name: "Portfolio")
        )
        let folded = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)
            .map { BMSearch.fold($0.prompt) }
            .joined(separator: " ")

        for forbidden in [
            "minimum",
            "maximum",
            "meisten",
            "wenigsten",
            "ranking",
            "verteilung",
            "distribution",
            "durchschnitt",
            "average",
            "compare",
            "vergleich",
        ] {
            #expect(folded.contains(forbidden) == false)
        }
    }

    @Test
    func emptyGraphProducesSafeEmptyGuidance() {
        let graphScope = GraphScope(graphID: graphID)
        let emptyAliases = GraphSchemaAliasMap(
            graphScope: graphScope,
            entitiesByAlias: [:],
            fieldsByAlias: [:],
            nodeEntityIDs: [:]
        )
        let context = GraphChatSuggestionContext(
            schema: GraphSchemaContext(
                graphScope: graphScope,
                snapshot: GraphSchemaSnapshot(
                    graphName: "Leer",
                    entities: [],
                    truncation: emptyTruncation
                ),
                aliases: emptyAliases
            ),
            scope: .entireGraph(graphScope),
            launchContext: .graph(name: "Leer"),
            language: .german
        )

        #expect(
            GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
                .isEmpty
        )
    }

    @Test
    func singleEntityGraphProducesOneValidatedCollectionStarter() {
        let graphScope = GraphScope(graphID: graphID)
        let alias = GraphEntityAlias("E-single")
        let entity = GraphSchemaEntityResolution(
            alias: alias,
            entityID: projectEntityID,
            name: "Sammlungen"
        )
        let aliases = GraphSchemaAliasMap(
            graphScope: graphScope,
            entitiesByAlias: [alias: entity],
            fieldsByAlias: [:],
            nodeEntityIDs: [:]
        )
        let context = GraphChatSuggestionContext(
            schema: GraphSchemaContext(
                graphScope: graphScope,
                snapshot: GraphSchemaSnapshot(
                    graphName: "Klein",
                    entities: [
                        GraphSchemaEntity(
                            alias: alias,
                            name: entity.name,
                            attributeCount: 0,
                            fields: [],
                            fieldsWereTruncated: false
                        ),
                    ],
                    truncation:
                        GraphSchemaTruncation(
                            sourceEntityCount: 1,
                            includedEntityCount: 1,
                            sourceFieldCount: 0,
                            includedFieldCount: 0,
                            sourceChoiceOptionCount: 0,
                            includedChoiceOptionCount: 0,
                            sourceExampleValueCount: 0,
                            includedExampleValueCount: 0,
                            stringsWereTruncated: false
                        )
                ),
                aliases: aliases
            ),
            scope: .entireGraph(graphScope),
            launchContext: .graph(name: "Klein"),
            language: .german
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(suggestions.count == 1)
        #expect(suggestions[0].capabilityID == .entityEntries)
        #expect(suggestions[0].prompt.contains("Sammlungen"))
        #expect(
            suggestions[0].validation.readPlanFamily
                == .entityCollection
        )
    }

    private var firstNode: NodeRefKey {
        NodeRefKey(
            kind: .attribute,
            id: firstNodeID
        )
    }

    private var secondNode: NodeRefKey {
        NodeRefKey(
            kind: .attribute,
            id: secondNodeID
        )
    }

    private var emptyTruncation: GraphSchemaTruncation {
        GraphSchemaTruncation(
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
    }

    private func nodeReference(
        _ node: NodeRefKey,
        label: String
    ) -> GraphChatNodeContextReference {
        GraphChatNodeContextReference(
            node: node,
            label: label,
            entityID: projectEntityID,
            entityName: "Projekte"
        )
    }

    private func makeCandidate(
        id: String,
        semanticKey: String? = nil,
        priority: Int,
        kind: GraphChatSuggestionKind = .detail,
        capabilityID: GraphChatCapabilityID = .nodeProfile,
        prompt: String? = nil
    ) -> GraphChatEmptyStateSuggestionBuilder.Candidate {
        GraphChatEmptyStateSuggestionBuilder.Candidate(
            id: id,
            semanticKey: semanticKey ?? id,
            priority: priority,
            kind: kind,
            capabilityID: capabilityID,
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
            suggestion.accessibilityHint,
        ].joined(separator: "|")
    }

    private func containsTechnicalIdentifier(
        _ value: String
    ) -> Bool {
        GraphChatSemanticSafety
            .containsTechnicalIdentifier(value)
            || value.contains("E-")
            || value.contains("F-")
    }

    private func makeSuggestionContext(
        scope: GraphChatScope,
        launchContext: GraphChatLaunchContext,
        availableTools: Set<GraphChatToolKind> =
            Set(GraphChatToolKind.allCases),
        modelAvailability:
            GraphChatAvailabilityPresentationState =
                .available,
        language: GraphChatResponseLanguage = .german,
        duplicateNodeName: Bool = false,
        duplicateEntityName: Bool = false
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
                    attributeCount: 2,
                    fields: [
                        GraphSchemaField(
                            alias: statusAlias,
                            name: "Status",
                            type: .singleChoice,
                            unit: nil,
                            choiceOptions: [
                                "Offen",
                                "Fertig",
                            ],
                            isPinned: true,
                            sortIndex: 0,
                            exampleValues: [
                                .choice("Offen"),
                            ],
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
                            exampleValues: [
                                .decimal(1_000),
                            ],
                            optionsWereTruncated: false,
                            examplesWereTruncated: false
                        ),
                    ],
                    fieldsWereTruncated: false
                ),
                GraphSchemaEntity(
                    alias: personAlias,
                    name: duplicateEntityName
                        ? "Projekte"
                        : "Personen",
                    attributeCount: 0,
                    fields: [],
                    fieldsWereTruncated: false
                ),
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
        let project = GraphSchemaEntityResolution(
            alias: projectAlias,
            entityID: projectEntityID,
            name: "Projekte"
        )
        let person = GraphSchemaEntityResolution(
            alias: personAlias,
            entityID: personEntityID,
            name: duplicateEntityName
                ? "Projekte"
                : "Personen"
        )
        let projectNode = NodeRefKey(
            kind: .entity,
            id: projectEntityID
        )
        let personNode = NodeRefKey(
            kind: .entity,
            id: personEntityID
        )
        let nodeEntityIDs: [NodeRefKey: UUID] = [
            projectNode: projectEntityID,
            personNode: personEntityID,
            firstNode: projectEntityID,
            secondNode: projectEntityID,
        ]
        let nodesByKey: [
            NodeRefKey: GraphSchemaNodeResolution
        ] = [
            projectNode: GraphSchemaNodeResolution(
                node: projectNode,
                ownerEntityID: projectEntityID,
                displayName: "Projekte"
            ),
            personNode: GraphSchemaNodeResolution(
                node: personNode,
                ownerEntityID: personEntityID,
                displayName: duplicateEntityName
                    ? "Projekte"
                    : "Personen"
            ),
            firstNode: GraphSchemaNodeResolution(
                node: firstNode,
                ownerEntityID: projectEntityID,
                displayName: "Apollo"
            ),
            secondNode: GraphSchemaNodeResolution(
                node: secondNode,
                ownerEntityID: projectEntityID,
                displayName:
                    duplicateNodeName ? "Apollo" : "Hermes"
            ),
        ]
        let aliases = GraphSchemaAliasMap(
            graphScope: scope.graphScope,
            entitiesByAlias: [
                projectAlias: project,
                personAlias: person,
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
                    choiceOptions: [
                        "Offen",
                        "Fertig",
                    ]
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
                ),
            ],
            nodeEntityIDs: nodeEntityIDs,
            nodesByKey: nodesByKey
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

    private func makeFoundationalOnlyEntityContext()
        -> GraphChatSuggestionContext {
        let graphScope = GraphScope(graphID: graphID)
        let visibleAlias = GraphEntityAlias("E-visible")
        let hiddenAlias = GraphEntityAlias("E-hidden")
        let hiddenEntityID = UUID(
            uuidString:
                "20000000-0000-0000-0000-000000000003"
        )!
        let snapshot = GraphSchemaSnapshot(
            graphName: "Sprachzeichen",
            entities: [
                GraphSchemaEntity(
                    alias: visibleAlias,
                    name: "Ziele",
                    attributeCount: 0,
                    fields: [],
                    fieldsWereTruncated: false
                ),
            ],
            truncation: GraphSchemaTruncation(
                sourceEntityCount: 2,
                includedEntityCount: 1,
                sourceFieldCount: 0,
                includedFieldCount: 0,
                sourceChoiceOptionCount: 0,
                includedChoiceOptionCount: 0,
                sourceExampleValueCount: 0,
                includedExampleValueCount: 0,
                stringsWereTruncated: false
            )
        )
        let visible = GraphSchemaEntityResolution(
            alias: visibleAlias,
            entityID: projectEntityID,
            name: "Ziele"
        )
        let hidden = GraphSchemaEntityResolution(
            alias: hiddenAlias,
            entityID: hiddenEntityID,
            name: "Ärger & Öl"
        )
        let promptAliases = GraphSchemaAliasMap(
            graphScope: graphScope,
            entitiesByAlias: [visibleAlias: visible],
            fieldsByAlias: [:],
            nodeEntityIDs: [:]
        )
        let foundationalAliases = GraphSchemaAliasMap(
            graphScope: graphScope,
            entitiesByAlias: [
                visibleAlias: visible,
                hiddenAlias: hidden,
            ],
            fieldsByAlias: [:],
            nodeEntityIDs: [:]
        )
        return GraphChatSuggestionContext(
            schema: GraphSchemaContext(
                graphScope: graphScope,
                snapshot: snapshot,
                aliases: promptAliases,
                foundationalAliases:
                    foundationalAliases
            ),
            scope: .entireGraph(graphScope),
            launchContext:
                .graph(name: "Sprachzeichen"),
            availableTools: [.queryDetailValues],
            language: .german
        )
    }
}
