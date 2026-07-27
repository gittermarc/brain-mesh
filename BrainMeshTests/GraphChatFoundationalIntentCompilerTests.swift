import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat foundational intent compiler")
struct GraphChatFoundationalIntentCompilerTests {
    @Test
    func recognizesSingleFieldGermanAndEnglishBirthdayQuestions() throws {
        let cases: [(String, GraphChatResponseLanguage)] = [
            ("Wann hat Person X Geburtstag?", GraphChatResponseLanguage.german),
            ("Was ist das Geburtsdatum von Person X?", .german),
            ("What is Person X’s birthday?", .english),
            ("What is the birth date of Person X?", .english),
        ]
        let fixture = Fixture()

        for (question, language) in cases {
            let intent = try #require(
                compiled(
                    question,
                    language: language,
                    fixture: fixture
                )
            )

            #expect(intent.kind == .singleNodeFieldValue)
            #expect(intent.entity.id == fixture.peopleEntityID)
            #expect(intent.node?.node == fixture.personNode)
            #expect(intent.field?.id == fixture.birthdayFieldID)
            #expect(intent.resultLimit == 1)
            #expect(intent.expectedCardinality == .zeroOrOne)
        }
    }

    @Test
    func genericTextAndChoiceFieldsAreSchemaOriented() throws {
        let fixture = Fixture()

        let textIntent = try #require(
            compiled(
                "Was ist die Beschreibung von Projekt Atlas?",
                language: .german,
                fixture: fixture
            )
        )
        let choiceIntent = try #require(
            compiled(
                "Welchen Status hat Projekt Atlas?",
                language: .german,
                fixture: fixture
            )
        )
        let englishChoiceIntent = try #require(
            compiled(
                "What is the status of Project Atlas?",
                language: .english,
                fixture: fixture
            )
        )

        #expect(textIntent.field?.id == fixture.descriptionFieldID)
        #expect(textIntent.field?.type == .multiLineText)
        #expect(choiceIntent.field?.id == fixture.statusFieldID)
        #expect(choiceIntent.field?.type == .singleChoice)
        #expect(englishChoiceIntent.field?.id == fixture.statusFieldID)
        #expect(
            choiceIntent.entity.alias
                == fixture.schema.aliases.entity(
                    id: fixture.projectsEntityID
                )?.alias
        )
    }

    @Test
    func recognizesCompleteEntityCollections() throws {
        let cases: [
            (
                question: String,
                language: GraphChatResponseLanguage,
                fixture: Fixture
            )
        ] = [
            (
                "Welche Reisen habe ich gemacht?",
                .german,
                Fixture()
            ),
            ("Zeige mir alle Reisen.", .german, Fixture()),
            (
                "Which trips have I taken?",
                .english,
                Fixture(tripsEntityName: "Trips")
            ),
            (
                "Show me all trips.",
                .english,
                Fixture(tripsEntityName: "Trips")
            ),
        ]

        for value in cases {
            let intent = try #require(
                compiled(
                    value.question,
                    language: value.language,
                    fixture: value.fixture
                )
            )

            #expect(intent.kind == .entityAttributeCollection)
            #expect(intent.entity.id == value.fixture.tripsEntityID)
            #expect(
                intent.resultLimit
                    == GraphQueryPlanLimits.maximumResultLimit
            )
            #expect(intent.expectedCardinality == .zeroOrMore)
            #expect(intent.field == nil)
            #expect(intent.node == nil)
        }
    }

    @Test
    func duplicateNodeNamesProduceAClarification() throws {
        let fixture = Fixture(duplicatePerson: true)
        let compilation = compile(
            "Wann hat Person X Geburtstag?",
            language: .german,
            fixture: fixture
        )

        guard case .clarification(let clarification) = compilation else {
            Issue.record("Expected a typed clarification")
            return
        }
        #expect(clarification.options.count == 2)
        #expect(
            clarification.options.allSatisfy {
                $0.selection.entityID == fixture.peopleEntityID
                    && $0.selection.fieldID
                        == fixture.birthdayFieldID
            }
        )
        #expect(
            clarification.options.allSatisfy {
                $0.title.contains("Person X")
            }
        )
    }

    @Test
    func duplicateMatchingFieldsProduceAClarification() {
        let fixture = Fixture(duplicateBirthdayField: true)
        let compilation = compile(
            "Was ist das Geburtsdatum von Person X?",
            language: .german,
            fixture: fixture
        )

        guard case .clarification(let clarification) = compilation else {
            Issue.record("Expected a typed clarification")
            return
        }
        #expect(clarification.options.count == 2)
        #expect(
            Set(
                clarification.options.compactMap {
                    $0.selection.fieldID
                }
            ).count == 2
        )
    }

    @Test
    func duplicateEntityDisplayNamesProduceAClarification() {
        let fixture = Fixture(duplicateTripsEntity: true)
        let compilation = compile(
            "Zeige mir alle Reisen.",
            language: .german,
            fixture: fixture
        )

        guard case .clarification(let clarification) = compilation else {
            Issue.record("Expected a typed entity clarification")
            return
        }
        #expect(clarification.options.count == 2)
        #expect(
            Set(
                clarification.options.map {
                    $0.selection.entityID
                }
            ).count == 2
        )
    }

    @Test
    func clarificationSelectionIsRevalidatedAndBoundToTheTurn() throws {
        let fixture = Fixture(duplicatePerson: true)
        let initial = compile(
            "Wann hat Person X Geburtstag?",
            language: .german,
            fixture: fixture
        )
        guard case .clarification(let clarification) = initial else {
            Issue.record("Expected a typed clarification")
            return
        }
        let selected = try #require(clarification.options.first)
        let requestID = UUID()
        let sourceTurnID = UUID()
        let clarificationID = UUID()
        let compilation = fixture.compiler.compile(
            fixture.input(
                requestID: requestID,
                question: "Wann hat Person X Geburtstag?",
                language: .german,
                selection: selected.selection,
                sourceTurnID: sourceTurnID,
                clarificationID: clarificationID
            )
        )
        guard case .compiled(let intent) = compilation else {
            Issue.record("Expected the selected intent to compile")
            return
        }

        #expect(intent.node?.node == selected.selection.node)
        #expect(intent.origin == .clarificationSelection)
        #expect(intent.confidence == .revalidatedClarification)
        #expect(intent.binding.requestID == requestID)
        #expect(intent.binding.sourceTurnID == sourceTurnID)
        #expect(intent.binding.clarificationID == clarificationID)
    }

    @Test
    func staleClarificationSelectionIsRejected() {
        let fixture = Fixture()
        let selection = GraphChatFoundationalIntentSelection(
            entityID: fixture.peopleEntityID,
            node: NodeRefKey(kind: .attribute, id: UUID()),
            fieldID: fixture.birthdayFieldID
        )
        let compilation = fixture.compiler.compile(
            fixture.input(
                question: "Wann hat Person X Geburtstag?",
                language: .german,
                selection: selection
            )
        )

        #expect(compilation == .rejected(.staleClarification))
    }

    @Test
    func nodeAndSelectionScopesAreNeverBroadened() throws {
        let fixture = Fixture()
        let nodeScope = GraphChatScope.node(
            fixture.personNode,
            in: fixture.graphScope
        )
        let intent = try #require(
            compiled(
                "Wann hat Person X Geburtstag?",
                language: .german,
                fixture: fixture,
                chatScope: nodeScope
            )
        )
        #expect(intent.queryScope == nodeScope)

        let foreignNodeScope = GraphChatScope.node(
            fixture.projectNode,
            in: fixture.graphScope
        )
        #expect(
            compile(
                "Wann hat Person X Geburtstag?",
                language: .german,
                fixture: fixture,
                chatScope: foreignNodeScope
            ) == .rejected(.unauthorizedSelection)
        )
    }

    @Test
    func collectionKeepsEntityAndSelectionScope() throws {
        let fixture = Fixture()
        let entityScope = GraphChatScope.entity(
            fixture.tripsEntityID,
            in: fixture.graphScope
        )
        let entityIntent = try #require(
            compiled(
                "Zeige mir alle Reisen.",
                language: .german,
                fixture: fixture,
                chatScope: entityScope
            )
        )
        #expect(entityIntent.queryScope == entityScope)

        let selectionScope = try GraphChatScope.selection(
            [fixture.tripNode],
            in: fixture.graphScope
        )
        let selectionIntent = try #require(
            compiled(
                "Welche Reisen habe ich gemacht?",
                language: .german,
                fixture: fixture,
                chatScope: selectionScope
            )
        )
        #expect(selectionIntent.queryScope == selectionScope)

        let foreignEntityScope = GraphChatScope.entity(
            fixture.peopleEntityID,
            in: fixture.graphScope
        )
        #expect(
            compile(
                "Zeige mir alle Reisen.",
                language: .german,
                fixture: fixture,
                chatScope: foreignEntityScope
            ) == .rejected(.unauthorizedSelection)
        )
    }

    @Test
    func unrecognizedAnalyticalQuestionFallsBack() {
        let fixture = Fixture()
        let compilation = compile(
            "Welche Projekte haben das höchste Budget im Durchschnitt?",
            language: .german,
            fixture: fixture
        )

        #expect(compilation == .notRecognized)
    }

    private func compiled(
        _ question: String,
        language: GraphChatResponseLanguage,
        fixture: Fixture,
        chatScope: GraphChatScope? = nil
    ) -> GraphChatFoundationalIntent? {
        let compilation = compile(
            question,
            language: language,
            fixture: fixture,
            chatScope: chatScope
        )
        guard case .compiled(let intent) = compilation else {
            return nil
        }
        return intent
    }

    private func compile(
        _ question: String,
        language: GraphChatResponseLanguage,
        fixture: Fixture,
        chatScope: GraphChatScope? = nil
    ) -> GraphChatFoundationalIntentCompilation {
        fixture.compiler.compile(
            fixture.input(
                question: question,
                language: language,
                chatScope: chatScope
            )
        )
    }
}

private extension GraphChatFoundationalIntentCompilerTests {
    struct Fixture {
        let compiler = GraphChatFoundationalIntentCompiler()
        let graphScope = GraphScope(
            graphID: UUID(
                uuidString:
                    "91000000-0000-0000-0000-000000000001"
            )!
        )
        let peopleEntityID = UUID(
            uuidString:
                "91000000-0000-0000-0000-000000000101"
        )!
        let projectsEntityID = UUID(
            uuidString:
                "91000000-0000-0000-0000-000000000102"
        )!
        let tripsEntityID = UUID(
            uuidString:
                "91000000-0000-0000-0000-000000000103"
        )!
        let personNode = NodeRefKey(
            kind: .attribute,
            id: UUID(
                uuidString:
                    "91000000-0000-0000-0000-000000000201"
            )!
        )
        let projectNode = NodeRefKey(
            kind: .attribute,
            id: UUID(
                uuidString:
                    "91000000-0000-0000-0000-000000000202"
            )!
        )
        let tripNode = NodeRefKey(
            kind: .attribute,
            id: UUID(
                uuidString:
                    "91000000-0000-0000-0000-000000000203"
            )!
        )
        let birthdayFieldID = UUID(
            uuidString:
                "91000000-0000-0000-0000-000000000301"
        )!
        let descriptionFieldID = UUID(
            uuidString:
                "91000000-0000-0000-0000-000000000302"
        )!
        let statusFieldID = UUID(
            uuidString:
                "91000000-0000-0000-0000-000000000303"
        )!
        let schema: GraphSchemaContext

        init(
            duplicatePerson: Bool = false,
            duplicateBirthdayField: Bool = false,
            duplicateTripsEntity: Bool = false,
            tripsEntityName: String = "Reisen"
        ) {
            let duplicatePersonNode = NodeRefKey(
                kind: .attribute,
                id: UUID(
                    uuidString:
                        "91000000-0000-0000-0000-000000000204"
                )!
            )
            let secondBirthdayFieldID = UUID(
                uuidString:
                    "91000000-0000-0000-0000-000000000304"
            )!
            let secondTripsEntityID = UUID(
                uuidString:
                    "91000000-0000-0000-0000-000000000104"
            )!
            var entityResolutions = [
                GraphEntityAlias("E1"):
                    GraphSchemaEntityResolution(
                        alias: GraphEntityAlias("E1"),
                        entityID: peopleEntityID,
                        name: "Personen"
                    ),
                GraphEntityAlias("E2"):
                    GraphSchemaEntityResolution(
                        alias: GraphEntityAlias("E2"),
                        entityID: projectsEntityID,
                        name: "Projekte"
                    ),
                GraphEntityAlias("E3"):
                    GraphSchemaEntityResolution(
                        alias: GraphEntityAlias("E3"),
                        entityID: tripsEntityID,
                        name: tripsEntityName
                    ),
            ]
            if duplicateTripsEntity {
                entityResolutions[GraphEntityAlias("E4")] =
                    GraphSchemaEntityResolution(
                        alias: GraphEntityAlias("E4"),
                        entityID: secondTripsEntityID,
                        name: tripsEntityName
                    )
            }
            var fieldResolutions = [
                GraphFieldAlias("F1"):
                    GraphSchemaFieldResolution(
                        alias: GraphFieldAlias("F1"),
                        entityAlias: GraphEntityAlias("E1"),
                        entityID: peopleEntityID,
                        fieldID: birthdayFieldID,
                        name: "Geburtsdatum",
                        type: .date,
                        unit: nil,
                        choiceOptions: []
                    ),
                GraphFieldAlias("F2"):
                    GraphSchemaFieldResolution(
                        alias: GraphFieldAlias("F2"),
                        entityAlias: GraphEntityAlias("E2"),
                        entityID: projectsEntityID,
                        fieldID: descriptionFieldID,
                        name: "Beschreibung",
                        type: .multiLineText,
                        unit: nil,
                        choiceOptions: []
                    ),
                GraphFieldAlias("F3"):
                    GraphSchemaFieldResolution(
                        alias: GraphFieldAlias("F3"),
                        entityAlias: GraphEntityAlias("E2"),
                        entityID: projectsEntityID,
                        fieldID: statusFieldID,
                        name: "Status",
                        type: .singleChoice,
                        unit: nil,
                        choiceOptions: [
                            "Offen",
                            "In Arbeit",
                            "Fertig",
                        ]
                    ),
            ]
            if duplicateBirthdayField {
                fieldResolutions[GraphFieldAlias("F4")] =
                    GraphSchemaFieldResolution(
                        alias: GraphFieldAlias("F4"),
                        entityAlias: GraphEntityAlias("E1"),
                        entityID: peopleEntityID,
                        fieldID: secondBirthdayFieldID,
                        name: "Geburtsdatum",
                        type: .date,
                        unit: nil,
                        choiceOptions: []
                    )
            }
            var nodes = [
                personNode: GraphSchemaNodeResolution(
                    node: personNode,
                    ownerEntityID: peopleEntityID,
                    displayName: "Person X"
                ),
                projectNode: GraphSchemaNodeResolution(
                    node: projectNode,
                    ownerEntityID: projectsEntityID,
                    displayName: "Projekt Atlas"
                ),
                tripNode: GraphSchemaNodeResolution(
                    node: tripNode,
                    ownerEntityID: tripsEntityID,
                    displayName: "Berlin"
                ),
            ]
            if duplicatePerson {
                nodes[duplicatePersonNode] =
                    GraphSchemaNodeResolution(
                        node: duplicatePersonNode,
                        ownerEntityID: peopleEntityID,
                        displayName: "Person X"
                    )
            }
            let entityNodes = [
                NodeRefKey(
                    kind: .entity,
                    id: peopleEntityID
                ): peopleEntityID,
                NodeRefKey(
                    kind: .entity,
                    id: projectsEntityID
                ): projectsEntityID,
                NodeRefKey(
                    kind: .entity,
                    id: tripsEntityID
                ): tripsEntityID,
            ]
            var nodeEntityIDs = entityNodes
            if duplicateTripsEntity {
                nodeEntityIDs[
                    NodeRefKey(
                        kind: .entity,
                        id: secondTripsEntityID
                    )
                ] = secondTripsEntityID
            }
            for node in nodes.values {
                nodeEntityIDs[node.node] = node.ownerEntityID
            }
            schema = GraphSchemaContext(
                graphScope: graphScope,
                snapshot: GraphSchemaSnapshot(
                    graphName: "Foundational Test",
                    entities: [],
                    truncation: GraphSchemaTruncation(
                        sourceEntityCount: 3,
                        includedEntityCount: 0,
                        sourceFieldCount:
                            fieldResolutions.count,
                        includedFieldCount: 0,
                        sourceChoiceOptionCount: 3,
                        includedChoiceOptionCount: 0,
                        sourceExampleValueCount: 0,
                        includedExampleValueCount: 0,
                        stringsWereTruncated: false
                    )
                ),
                aliases: GraphSchemaAliasMap(
                    graphScope: graphScope,
                    entitiesByAlias: entityResolutions,
                    fieldsByAlias: fieldResolutions,
                    nodeEntityIDs: nodeEntityIDs,
                    nodesByKey: nodes
                )
            )
        }

        func input(
            requestID: UUID = UUID(),
            question: String,
            language: GraphChatResponseLanguage,
            chatScope: GraphChatScope? = nil,
            selection:
                GraphChatFoundationalIntentSelection? = nil,
            sourceTurnID: UUID? = nil,
            clarificationID: UUID? = nil
        ) -> GraphChatFoundationalIntentCompilerInput {
            let scope = chatScope ?? .entireGraph(graphScope)
            return GraphChatFoundationalIntentCompilerInput(
                requestID: requestID,
                question: question,
                graphScope: graphScope,
                chatScope: scope,
                responseLanguage: language,
                conversationState: .initial(
                    graphScope: graphScope,
                    chatScope: scope
                ),
                schemaContext: schema,
                selectedCandidate: selection,
                sourceTurnID: sourceTurnID,
                clarificationID: clarificationID
            )
        }
    }
}
