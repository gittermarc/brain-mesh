import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph mention resolver")
struct GraphMentionResolverTests {
    private let resolver =
        GraphMentionResolver()

    @Test
    func resolvesGermanAndEnglishSingularPluralForms() throws {
        let medicine =
            GraphChatGroundingFixture.medicine()
        let library =
            GraphChatGroundingFixture.library()
        let operations =
            GraphChatGroundingFixture.itOperations()

        let patient = try resolveEntity(
            "Patienten",
            language: .german,
            fixture: medicine
        )
        let author = try resolveEntity(
            "Autoren",
            language: .german,
            fixture: library
        )
        let book = try resolveEntity(
            "Bücher",
            language: .german,
            fixture: library
        )
        let incident = try resolveEntity(
            "Incident Records",
            language: .english,
            fixture: operations
        )

        #expect(
            patient.entityID
                == medicine.entityID(
                    named: "Patient"
                )
        )
        #expect(
            author.entityID
                == library.entityID(named: "Autor")
        )
        #expect(
            book.entityID
                == library.entityID(named: "Buch")
        )
        #expect(
            incident.entityID
                == operations.entityID(
                    named: "Incident Record"
                )
        )
    }

    @Test
    func resolvesPunctuationUnicodeUmlautsAndSharpS() throws {
        let operations =
            GraphChatGroundingFixture.itOperations()
        let medicine =
            GraphChatGroundingFixture.medicine()
        let unicode =
            GraphChatGroundingFixture(
                graphName: "Unicode",
                entities: [
                    GraphChatGroundingEntityDefinition(
                        name: "Café",
                        nodeNames: ["München Süd"],
                        fieldNames: ["Straße"]
                    ),
                ]
            )

        let punctuated = try resolveEntity(
            "incident-record!",
            language: .english,
            fixture: operations
        )
        let decomposed = try resolveEntity(
            "Cafe\u{301}",
            language: .german,
            fixture: unicode
        )
        let umlaut = try resolveNode(
            "Muenchen Sued",
            language: .german,
            fixture: unicode
        )
        let sharpS = try resolveField(
            "Strasse",
            ownerEntityID:
                medicine.entityID(
                    named: "Patient"
                ),
            language: .german,
            fixture: medicine
        )

        #expect(
            punctuated.entityID
                == operations.entityID(
                    named: "Incident Record"
                )
        )
        #expect(
            decomposed.entityID
                == unicode.entityID(named: "Café")
        )
        #expect(
            umlaut.node
                == unicode.node(
                    named: "München Süd"
                ).node
        )
        #expect(
            sharpS.fieldID
                == medicine.field(
                    named: "Straße",
                    index: 0
                ).fieldID
        )
    }

    @Test
    func conservativeTypoRequiresStrengthAndDistanceGap() throws {
        let operations =
            GraphChatGroundingFixture.itOperations()
        let resolved = try resolveEntity(
            "Incident Recor",
            language: .english,
            fixture: operations
        )
        #expect(
            resolved.entityID
                == operations.entityID(
                    named: "Incident Record"
                )
        )

        let weak = entityResult(
            "Patio",
            language: .german,
            fixture:
                GraphChatGroundingFixture.medicine()
        )
        guard case .failure(.notFound) = weak else {
            Issue.record(
                "Weak similarity must not bind silently"
            )
            return
        }

        let ambiguousFixture =
            GraphChatGroundingFixture(
                graphName: "Typo ambiguity",
                entities: [
                    GraphChatGroundingEntityDefinition(
                        name: "Cluster",
                        nodeNames: [],
                        fieldNames: []
                    ),
                    GraphChatGroundingEntityDefinition(
                        name: "Clutter",
                        nodeNames: [],
                        fieldNames: []
                    ),
                ]
            )
        let ambiguous = entityResult(
            "Cluter",
            language: .english,
            fixture: ambiguousFixture
        )
        guard case .failure(
            .ambiguous(let alternatives)
        ) = ambiguous else {
            Issue.record(
                "Close fuzzy candidates must clarify"
            )
            return
        }
        #expect(alternatives.count == 2)
    }

    @Test
    func sameNamesAreNarrowedOnlyByOwnerAndScope() throws {
        let fixture =
            GraphChatGroundingFixture(
                graphName: "Owner ambiguity",
                entities: [
                    GraphChatGroundingEntityDefinition(
                        name: "Alpha",
                        nodeNames: ["Shared Entry"],
                        fieldNames: ["Shared Field"]
                    ),
                    GraphChatGroundingEntityDefinition(
                        name: "Beta",
                        nodeNames: ["Shared Entry"],
                        fieldNames: ["Shared Field"]
                    ),
                ]
            )
        let allNodes = nodeResult(
            "Shared Entry",
            language: .english,
            fixture: fixture
        )
        let allFields = fieldResult(
            "Shared Field",
            ownerEntityID: nil,
            language: .english,
            fixture: fixture
        )
        guard case .failure(.ambiguous) =
                allNodes,
              case .failure(.ambiguous) =
                allFields else {
            Issue.record(
                "Unowned duplicate names must clarify"
            )
            return
        }

        let alphaID =
            fixture.entityID(named: "Alpha")
        let alphaNode = try resolveNode(
            "Shared Entry",
            ownerEntityID: alphaID,
            language: .english,
            fixture: fixture
        )
        let alphaField = try resolveField(
            "Shared Field",
            ownerEntityID: alphaID,
            language: .english,
            fixture: fixture
        )
        #expect(alphaNode.ownerEntityID == alphaID)
        #expect(alphaField.entityID == alphaID)
    }

    @Test
    func usesCompleteCatalogBeyondPromptLimits() throws {
        let fixture =
            GraphChatGroundingFixture
                .beyondInterpreterCatalogLimits()
        #expect(
            fixture.context.aliases
                .entity(id:
                    fixture.entityID(
                        named: "Remote Workload"
                    )
                ) == nil
        )

        let entity = try resolveEntity(
            "Remote Workloads",
            language: .english,
            fixture: fixture
        )
        let node = try resolveNode(
            "Remote Edge 25",
            language: .english,
            fixture: fixture
        )
        let field = try resolveField(
            "Escalation Matrix",
            ownerEntityID: entity.entityID,
            language: .english,
            fixture: fixture
        )
        let lateField = try resolveField(
            "Late Field 13",
            ownerEntityID:
                fixture.entityID(
                    named: "Catalog Entry 1"
                ),
            language: .english,
            fixture: fixture
        )

        #expect(
            entity.entityID
                == fixture.entityID(
                    named: "Remote Workload"
                )
        )
        #expect(
            node.node
                == fixture.node(
                    named: "Remote Edge 25"
                ).node
        )
        #expect(
            field.fieldID
                == fixture.field(
                    named: "Escalation Matrix"
                ).fieldID
        )
        #expect(
            fixture.context.aliases.field(
                for: lateField.alias
            ) == nil
        )
        #expect(
            lateField.fieldID
                == fixture.field(
                    named: "Late Field 13"
                ).fieldID
        )
    }

    @Test
    func enforcesEntityNodeAndSelectionScopes() throws {
        let fixture =
            GraphChatGroundingFixture.medicine()
        let patientID =
            fixture.entityID(named: "Patient")
        let patientNode =
            fixture.node(named: "Patient A")
        let treatmentNode =
            fixture.node(named: "Therapie Alpha")

        let entityScoped = try resolveNode(
            "Patient A",
            language: .german,
            fixture: fixture,
            chatScope:
                .entity(
                    patientID,
                    in: fixture.graphScope
                )
        )
        #expect(entityScoped.node == patientNode.node)

        let forbiddenEntity = entityResult(
            "Behandlung",
            language: .german,
            fixture: fixture,
            chatScope:
                .node(
                    patientNode.node,
                    in: fixture.graphScope
                )
        )
        guard case .failure(.scopeViolation) =
                forbiddenEntity else {
            Issue.record(
                "Node scope must not expand to another entity"
            )
            return
        }

        let selected = try resolveNode(
            "Therapie Alpha",
            language: .german,
            fixture: fixture,
            chatScope:
                try .selection(
                    [treatmentNode.node],
                    in: fixture.graphScope
                )
        )
        #expect(selected.node == treatmentNode.node)

        let conversationBound =
            resolver.resolve(
                GraphMentionResolverInput(
                    mention: "Therapie Alpha",
                    kind: .node,
                    language: .german,
                    graphScope:
                        fixture.graphScope,
                    catalog:
                        GraphMentionCatalog(
                            schemaContext:
                                fixture.context
                        ),
                    constraints:
                        GraphMentionResolutionConstraints(
                            chatScope:
                                .entireGraph(
                                    fixture
                                        .graphScope
                                ),
                            conversationEntityID:
                                patientID,
                            conversationNodes:
                                Set([
                                    patientNode.node,
                                ])
                        )
                )
            )
        guard case .failure(
            .ownerEntityMismatch
        ) = conversationBound else {
            Issue.record(
                "Conversation grounding must only narrow the active graph"
            )
            return
        }
    }

    @Test
    func rejectsForeignCatalogWithCollidingIDsAndNames() {
        let active =
            GraphChatGroundingFixture.medicine()
        let foreign =
            GraphChatGroundingFixture.medicine(
                graphID: UUID()
            )
        let foreignCandidates =
            GraphMentionCatalog(
                schemaContext: foreign.context
            ).candidates
        let collidingForeignCatalog =
            GraphMentionCatalog(
                graphScope: active.graphScope,
                candidates:
                    zip(
                        foreignCandidates,
                        GraphMentionCatalog(
                            schemaContext:
                                active.context
                        ).candidates
                    ).map {
                        foreignCandidate,
                        activeCandidate in
                        GraphMentionCandidate(
                            graphScope:
                                foreignCandidate
                                    .graphScope,
                            identity:
                                activeCandidate
                                    .identity,
                            aliases:
                                foreignCandidate
                                    .aliases
                        )
                    }
        )
        let result = resolver.resolve(
            GraphMentionResolverInput(
                mention: "Patient",
                kind: .entity,
                language: .german,
                graphScope: active.graphScope,
                catalog:
                    collidingForeignCatalog,
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope:
                            .entireGraph(
                                active.graphScope
                            )
                    )
            )
        )
        guard case .failure(
            .graphScopeMismatch
        ) = result else {
            Issue.record(
                "A foreign catalog must be rejected before matching"
            )
            return
        }
    }

    @Test
    func appOwnedLocalizedFieldSynonymsRemainDataDriven() throws {
        let fixture =
            GraphChatGroundingFixture.medicine()
        let field = try resolveField(
            "Birthday",
            ownerEntityID:
                fixture.entityID(
                    named: "Patient"
                ),
            language: .english,
            fixture: fixture
        )
        #expect(
            field.fieldID
                == fixture.field(
                    named: "Geburtsdatum"
                ).fieldID
        )
    }

    private func resolveEntity(
        _ term: String,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope? = nil
    ) throws -> GraphSchemaEntityResolution {
        let resolution = try entityResult(
            term,
            language: language,
            fixture: fixture,
            chatScope: chatScope
        ).get()
        guard case .entity(let entity) =
                resolution.candidate.identity else {
            throw GraphMentionResolutionFailure
                .notFound
        }
        return entity
    }

    private func resolveNode(
        _ term: String,
        ownerEntityID: UUID? = nil,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope? = nil
    ) throws -> GraphSchemaNodeResolution {
        let resolution = try nodeResult(
            term,
            ownerEntityID: ownerEntityID,
            language: language,
            fixture: fixture,
            chatScope: chatScope
        ).get()
        guard case .node(let node) =
                resolution.candidate.identity else {
            throw GraphMentionResolutionFailure
                .notFound
        }
        return node
    }

    private func resolveField(
        _ term: String,
        ownerEntityID: UUID?,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope? = nil
    ) throws -> GraphSchemaFieldResolution {
        let resolution = try fieldResult(
            term,
            ownerEntityID:
                ownerEntityID,
            language: language,
            fixture: fixture,
            chatScope: chatScope
        ).get()
        guard case .field(let field) =
                resolution.candidate.identity else {
            throw GraphMentionResolutionFailure
                .notFound
        }
        return field
    }

    private func entityResult(
        _ term: String,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope? = nil
    ) -> Result<
        GraphMentionResolution,
        GraphMentionResolutionFailure
    > {
        result(
            term,
            kind: .entity,
            ownerEntityID: nil,
            language: language,
            fixture: fixture,
            chatScope: chatScope
        )
    }

    private func nodeResult(
        _ term: String,
        ownerEntityID: UUID? = nil,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope? = nil
    ) -> Result<
        GraphMentionResolution,
        GraphMentionResolutionFailure
    > {
        result(
            term,
            kind: .node,
            ownerEntityID:
                ownerEntityID,
            language: language,
            fixture: fixture,
            chatScope: chatScope
        )
    }

    private func fieldResult(
        _ term: String,
        ownerEntityID: UUID?,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope? = nil
    ) -> Result<
        GraphMentionResolution,
        GraphMentionResolutionFailure
    > {
        result(
            term,
            kind: .field,
            ownerEntityID:
                ownerEntityID,
            language: language,
            fixture: fixture,
            chatScope: chatScope
        )
    }

    private func result(
        _ term: String,
        kind: GraphMentionKind,
        ownerEntityID: UUID?,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope?
    ) -> Result<
        GraphMentionResolution,
        GraphMentionResolutionFailure
    > {
        resolver.resolve(
            GraphMentionResolverInput(
                mention: term,
                kind: kind,
                language: language,
                graphScope: fixture.graphScope,
                catalog: GraphMentionCatalog(
                    schemaContext:
                        fixture.context
                ),
                constraints:
                    GraphMentionResolutionConstraints(
                        chatScope:
                            chatScope
                            ?? .entireGraph(
                                fixture.graphScope
                            ),
                        ownerEntityID:
                            ownerEntityID
                    )
            )
        )
    }
}
