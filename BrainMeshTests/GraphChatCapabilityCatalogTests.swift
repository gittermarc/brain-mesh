import Foundation
import Testing
@testable import BrainMesh

struct GraphChatCapabilityCatalogTests {
    @Test
    func catalogHasStableUniqueIDsAndDeterministicOrder() {
        let first = GraphChatCapabilityCatalog.stable
        let second = GraphChatCapabilityCatalog.stable

        #expect(first == second)
        #expect(first.map(\.id) == [
            .entityEntries,
            .nodeProfile,
            .directRelationships,
            .frequencyRelationshipChain,
        ])
        #expect(Set(first.map(\.id)).count == first.count)
        #expect(
            Set(first.map(\.starterRule)).count
                == first.count
        )
        #expect(
            Set(first.map { $0.id.rawValue }).count
                == first.count
        )
    }

    @Test
    func catalogPresentationIsCompleteInGermanAndEnglish() {
        for capability in GraphChatCapabilityCatalog.stable {
            for presentation in [
                capability.german,
                capability.english,
            ] {
                #expect(
                    presentation.title
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty == false
                )
                #expect(
                    presentation.summary
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty == false
                )
                #expect(
                    presentation.genericExample
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty == false
                )
            }
        }
    }

    @Test
    func userFacingCatalogCopyContainsNoImplementationNames() {
        let forbidden = [
            "typed intent",
            "intent kind",
            "compiler",
            "fast path",
            "read plan",
            "query plan",
            "tool kind",
            "getnode",
            "getneighbors",
            "querydetailvalues",
            "uuid",
            "e1",
            "n2",
        ]

        for capability in GraphChatCapabilityCatalog.stable {
            let copy = [
                capability.german.title,
                capability.german.summary,
                capability.german.genericExample,
                capability.english.title,
                capability.english.summary,
                capability.english.genericExample,
            ].joined(separator: " ").lowercased()
            for term in forbidden {
                #expect(copy.contains(term) == false)
            }
            #expect(
                GraphChatSemanticSafety
                    .containsTechnicalIdentifier(copy)
                    == false
            )
        }
    }

    @Test
    func everyCatalogCapabilityHasAValidatedProductionPath() throws {
        let fixture = makeFixture(
            graphSuffix: 10,
            primaryEntityName: "Aufgaben",
            secondaryEntityName: "Teams",
            primaryNodeName: "Sprint #1",
            secondaryNodeName: "Team Nord",
            includesFields: true
        )
        let validator =
            GraphChatCapabilityQuestionValidator()
        let questions: [GraphChatCapabilityID: String] = [
            .entityEntries:
                "Zeige mir alle „Aufgaben“.",
            .nodeProfile:
                "Zeige mir Details zu „Sprint #1“.",
            .directRelationships:
                "Zeige alle direkten Verbindungen von „Sprint #1“.",
            .frequencyRelationshipChain:
                "Welche Aufgaben sind mit Teams dreimal verbunden?",
        ]

        for capability in GraphChatCapabilityCatalog.stable {
            let question = try #require(
                questions[capability.id]
            )
            let validation = try #require(
                validator.validate(
                    question: question,
                    capability: capability,
                    schemaContext: fixture.schema,
                    chatScope: fixture.scope,
                    language: .german
                )
            )
            #expect(validation.capabilityID == capability.id)
            #expect(
                validation.compilerFamily
                    == capability.productionPath
                        .compilerFamily
            )
            #expect(
                validation.typedIntentKind
                    == capability.productionPath
                        .typedIntentKind
            )
            #expect(
                validation.readPlanFamily
                    == capability.productionPath
                        .readPlanFamily
            )
            #expect(validation.readPlanVersion == .current)
            #expect(
                validation.queryPlanVersion
                    == GraphQueryPlan.currentVersion
            )
        }
    }

    @Test
    func relationshipChainIsHelpOnlyUntilGraphEvidenceCanGenerateAQuestion() throws {
        let capability = try #require(
            GraphChatCapabilityCatalog.capability(
                withID: .frequencyRelationshipChain
            )
        )

        #expect(capability.placements == [.generalHelp])
        #expect(
            capability.prerequisites.contains(
                .explicitFrequencyInLinkNote
            )
        )
        #expect(
            capability.placements.contains(
                .starterQuestion
            ) == false
        )
    }

    @Test
    func catalogDoesNotClaimProviderDependentIntentFamilies() {
        let stableKinds = Set(
            GraphChatCapabilityCatalog.stable.map {
                $0.productionPath.typedIntentKind
            }
        )

        #expect(stableKinds.contains(.countOrGroup) == false)
        #expect(stableKinds.contains(.narrowResultSet) == false)
        #expect(stableKinds.contains(.compareNodes) == false)
        #expect(stableKinds.contains(.inspectGraphState) == false)
        #expect(stableKinds.contains(.findNodes) == false)

        let text = GraphChatCapabilityCatalog.stable
            .flatMap { capability in
                [
                    capability.german.title,
                    capability.german.summary,
                    capability.german.genericExample,
                    capability.english.title,
                    capability.english.summary,
                    capability.english.genericExample,
                ]
            }
            .map { BMSearch.fold($0) }
            .joined(separator: " ")
        for unsupported in [
            "minimum",
            "maximum",
            "ranking",
            "durchschnitt",
            "average",
        ] {
            #expect(text.contains(unsupported) == false)
        }
    }

    @Test
    func catalogValuesAreHashableAndSendable() {
        let values = GraphChatCapabilityCatalog.stable
        requireSendable(values)
        requireHashable(values[0])
        requireSendable(values[0].german)
        requireHashable(values[0].productionPath)
        #expect(Set(values).count == values.count)
    }

    @Test
    func twoUnrelatedGraphFixturesGenerateOnlyBoundQuestions() {
        let planning = makeFixture(
            graphSuffix: 20,
            primaryEntityName: "Aufgaben",
            secondaryEntityName: "Teams",
            primaryNodeName: "Sprint #1",
            secondaryNodeName: "Team Nord",
            includesFields: true
        )
        let publishing = makeFixture(
            graphSuffix: 30,
            primaryEntityName: "Bücher & Essays",
            secondaryEntityName: "Autor:innen",
            primaryNodeName: "Öl, Wasser – Band 2",
            secondaryNodeName: "M. Öztürk",
            includesFields: false
        )

        for fixture in [planning, publishing] {
            let context = GraphChatSuggestionContext(
                schema: fixture.schema,
                scope: fixture.scope,
                launchContext:
                    .graph(name: fixture.graphName),
                language: .german
            )
            let first = GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)
            let second = GraphChatEmptyStateSuggestionBuilder
                .suggestions(for: context)

            #expect(first == second)
            #expect(first.isEmpty == false)
            #expect(
                first.allSatisfy { suggestion in
                    fixture.visibleNames.contains {
                        suggestion.prompt.contains($0)
                    }
                }
            )
            #expect(
                first.allSatisfy { suggestion in
                    GraphChatSemanticSafety
                        .containsTechnicalIdentifier(
                            suggestion.prompt
                        ) == false
                }
            )
        }
    }

    @Test
    func fieldsDoNotEnableUnprovenFilterSortOrGroupingStarters() {
        let withFields = makeFixture(
            graphSuffix: 40,
            primaryEntityName: "Messreihen",
            secondaryEntityName: "Labore",
            primaryNodeName: "Reihe A",
            secondaryNodeName: "Labor West",
            includesFields: true
        )
        let withoutFields = makeFixture(
            graphSuffix: 50,
            primaryEntityName: "Routen",
            secondaryEntityName: "Stationen",
            primaryNodeName: "Nord-Süd",
            secondaryNodeName: "Tor 7",
            includesFields: false
        )

        for fixture in [withFields, withoutFields] {
            let context = GraphChatSuggestionContext(
                schema: fixture.schema,
                scope: fixture.scope,
                launchContext:
                    .graph(name: fixture.graphName),
                language: .german
            )
            let suggestions =
                GraphChatEmptyStateSuggestionBuilder
                    .suggestions(for: context)
            #expect(
                suggestions.allSatisfy {
                    $0.capabilityID == .entityEntries
                        || $0.capabilityID == .nodeProfile
                        || $0.capabilityID
                            == .directRelationships
                }
            )
        }
    }

    @Test
    func singularPluralNamesAreEitherUniquelyBoundOrSafelySkipped() {
        let fixture = makeFixture(
            graphSuffix: 60,
            primaryEntityName: "Buch",
            secondaryEntityName: "Bücher",
            primaryNodeName: "Band Eins",
            secondaryNodeName: "Band Zwei",
            includesFields: false
        )
        let context = GraphChatSuggestionContext(
            schema: fixture.schema,
            scope: fixture.scope,
            launchContext:
                .graph(name: fixture.graphName),
            language: .german
        )

        let suggestions = GraphChatEmptyStateSuggestionBuilder
            .suggestions(for: context)

        #expect(
            suggestions
                == GraphChatEmptyStateSuggestionBuilder
                    .suggestions(for: context)
        )
        #expect(Set(suggestions.map(\.prompt)).count == suggestions.count)
        #expect(
            suggestions.allSatisfy {
                $0.validation.capabilityID
                    == $0.capabilityID
            }
        )
    }

    private func requireSendable<T: Sendable>(
        _ value: T
    ) {
        _ = value
    }

    private func requireHashable<T: Hashable>(
        _ value: T
    ) {
        _ = value
    }

    private func makeFixture(
        graphSuffix: Int,
        primaryEntityName: String,
        secondaryEntityName: String,
        primaryNodeName: String,
        secondaryNodeName: String,
        includesFields: Bool
    ) -> CapabilityFixture {
        let graphID = uuid(prefix: 1, suffix: graphSuffix)
        let graphScope = GraphScope(graphID: graphID)
        let primaryID = uuid(
            prefix: 2,
            suffix: graphSuffix
        )
        let secondaryID = uuid(
            prefix: 3,
            suffix: graphSuffix
        )
        let primaryNode = NodeRefKey(
            kind: .attribute,
            id: uuid(prefix: 4, suffix: graphSuffix)
        )
        let secondaryNode = NodeRefKey(
            kind: .attribute,
            id: uuid(prefix: 5, suffix: graphSuffix)
        )
        let primaryEntityNode = NodeRefKey(
            kind: .entity,
            id: primaryID
        )
        let secondaryEntityNode = NodeRefKey(
            kind: .entity,
            id: secondaryID
        )
        let primaryAlias = GraphEntityAlias("E-primary")
        let secondaryAlias = GraphEntityAlias("E-secondary")
        let statusAlias = GraphFieldAlias("F-status")
        let dateAlias = GraphFieldAlias("F-date")
        let noteAlias = GraphFieldAlias("F-note")
        let fieldSpecifications: [(
            alias: GraphFieldAlias,
            id: UUID,
            name: String,
            type: DetailFieldType,
            options: [String]
        )] = includesFields ? [
            (
                statusAlias,
                uuid(prefix: 6, suffix: graphSuffix),
                "Phase",
                .singleChoice,
                ["Neu", "Aktiv"]
            ),
            (
                dateAlias,
                uuid(prefix: 7, suffix: graphSuffix),
                "Termin",
                .date,
                []
            ),
            (
                noteAlias,
                uuid(prefix: 8, suffix: graphSuffix),
                "Notiz",
                .multiLineText,
                []
            ),
        ] : []
        let primaryEntity = GraphSchemaEntityResolution(
            alias: primaryAlias,
            entityID: primaryID,
            name: primaryEntityName
        )
        let secondaryEntity = GraphSchemaEntityResolution(
            alias: secondaryAlias,
            entityID: secondaryID,
            name: secondaryEntityName
        )
        let fields = fieldSpecifications.enumerated().map {
            index, value in
            GraphSchemaField(
                alias: value.alias,
                name: value.name,
                type: value.type,
                unit: nil,
                choiceOptions: value.options,
                isPinned: index == 0,
                sortIndex: index,
                exampleValues: [],
                optionsWereTruncated: false,
                examplesWereTruncated: false
            )
        }
        let snapshot = GraphSchemaSnapshot(
            graphName:
                "Graph \(graphSuffix)",
            entities: [
                GraphSchemaEntity(
                    alias: primaryAlias,
                    name: primaryEntityName,
                    attributeCount: 1,
                    fields: fields,
                    fieldsWereTruncated: false
                ),
                GraphSchemaEntity(
                    alias: secondaryAlias,
                    name: secondaryEntityName,
                    attributeCount: 1,
                    fields: [],
                    fieldsWereTruncated: false
                ),
            ],
            truncation: GraphSchemaTruncation(
                sourceEntityCount: 2,
                includedEntityCount: 2,
                sourceFieldCount: fields.count,
                includedFieldCount: fields.count,
                sourceChoiceOptionCount:
                    includesFields ? 2 : 0,
                includedChoiceOptionCount:
                    includesFields ? 2 : 0,
                sourceExampleValueCount: 0,
                includedExampleValueCount: 0,
                stringsWereTruncated: false
            )
        )
        let entities: [
            GraphEntityAlias: GraphSchemaEntityResolution
        ] = [
            primaryAlias: primaryEntity,
            secondaryAlias: secondaryEntity,
        ]
        var fieldResolutions: [
            GraphFieldAlias: GraphSchemaFieldResolution
        ] = [:]
        for (index, field) in fieldSpecifications.enumerated() {
            fieldResolutions[field.alias] =
                GraphSchemaFieldResolution(
                    alias: field.alias,
                    entityAlias: primaryAlias,
                    entityID: primaryID,
                    fieldID: field.id,
                    name: field.name,
                    type: field.type,
                    unit: nil,
                    choiceOptions: field.options,
                    isPinned: index == 0,
                    sortIndex: index
                )
        }
        let nodeEntityIDs: [NodeRefKey: UUID] = [
            primaryEntityNode: primaryID,
            secondaryEntityNode: secondaryID,
            primaryNode: primaryID,
            secondaryNode: secondaryID,
        ]
        let nodesByKey: [
            NodeRefKey: GraphSchemaNodeResolution
        ] = [
            primaryEntityNode: GraphSchemaNodeResolution(
                node: primaryEntityNode,
                ownerEntityID: primaryID,
                displayName: primaryEntityName
            ),
            secondaryEntityNode: GraphSchemaNodeResolution(
                node: secondaryEntityNode,
                ownerEntityID: secondaryID,
                displayName: secondaryEntityName
            ),
            primaryNode: GraphSchemaNodeResolution(
                node: primaryNode,
                ownerEntityID: primaryID,
                displayName: primaryNodeName
            ),
            secondaryNode: GraphSchemaNodeResolution(
                node: secondaryNode,
                ownerEntityID: secondaryID,
                displayName: secondaryNodeName
            ),
        ]
        let aliases = GraphSchemaAliasMap(
            graphScope: graphScope,
            entitiesByAlias: entities,
            fieldsByAlias: fieldResolutions,
            nodeEntityIDs: nodeEntityIDs,
            nodesByKey: nodesByKey
        )
        return CapabilityFixture(
            graphName: snapshot.graphName,
            visibleNames: [
                primaryEntityName,
                secondaryEntityName,
                primaryNodeName,
                secondaryNodeName,
            ],
            schema: GraphSchemaContext(
                graphScope: graphScope,
                snapshot: snapshot,
                aliases: aliases
            ),
            scope: .entireGraph(graphScope)
        )
    }

    private func uuid(
        prefix: Int,
        suffix: Int
    ) -> UUID {
        UUID(
            uuidString: String(
                format:
                    "%08d-0000-0000-0000-%012d",
                prefix,
                suffix
            )
        )!
    }

    private struct CapabilityFixture {
        let graphName: String
        let visibleNames: Set<String>
        let schema: GraphSchemaContext
        let scope: GraphChatScope
    }
}
