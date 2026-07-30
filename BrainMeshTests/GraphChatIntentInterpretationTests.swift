//
//  GraphChatIntentInterpretationTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat intent interpretation")
struct GraphChatIntentInterpretationTests {
    @Test
    func everyTypedIntentFamilyProducesAProfessionalGermanInterpretation()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let interpretations = try fixture
            .allGermanInterpretations()

        #expect(
            Set(interpretations.map(\.intentKind))
                == Set(
                    GraphChatTypedIntentKind
                        .allCases
                )
        )
        #expect(
            interpretations.allSatisfy {
                $0.isInternallyConsistent
            }
        )
        #expect(
            interpretations.allSatisfy {
                $0.presentation.label
                    == "Verstanden als"
            }
        )

        let byKind = Dictionary(
            uniqueKeysWithValues:
                interpretations.map {
                    ($0.intentKind, $0)
                }
        )
        #expect(
            byKind[.findNodes]?
                .presentation.title
                == "Projekte finden"
        )
        #expect(
            byKind[.entityCollection]?
                .presentation.title
                == "Projekte mit Status: Offen, sortiert nach Fälligkeitsdatum absteigend"
        )
        #expect(
            byKind[.countOrGroup]?
                .presentation.title
                == "Projekte, gruppiert nach Status"
        )
        #expect(
            byKind[.nodeDetails]?
                .presentation.title
                == "Fälligkeitsdatum von Atlas (Projekte)"
        )
        #expect(
            byKind[.narrowResultSet]?
                .presentation.title
                == "Projekte aus den vorherigen Ergebnissen mit Fälligkeitsdatum: überfällig"
        )
        #expect(
            byKind[.compareNodes]?
                .presentation.title
                == "Vergleich von Atlas und Apollo nach Status und Budget (Projekte)"
        )
        #expect(
            byKind[.inspectGraphState]?
                .presentation.title
                == "Gesundheitszustand des gesamten Graphen"
        )
        #expect(
            byKind[.relationships]?
                .presentation.title
                == "Direkte Verbindungen von Atlas zu Apollo"
        )
    }

    @Test
    func filteredListSortCountAndGroupUseValidatedPlanSemantics()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let filtered =
            try fixture.filteredCollection(
                language: .german
            )
        let count =
            try fixture.countInterpretation(
                language: .german
            )
        let group =
            try fixture.groupInterpretation(
                language: .german
            )

        #expect(filtered.filters.count == 1)
        #expect(
            filtered.filters.first?
                .operation == .equals
        )
        #expect(filtered.sorting.count == 1)
        #expect(
            filtered.sorting.first?
                .direction == .descending
        )
        #expect(
            filtered.presentation.title
                .contains("Status: Offen")
        )
        #expect(
            filtered.presentation.title
                .contains(
                    "Fälligkeitsdatum absteigend"
                )
        )
        #expect(count.aggregation == .count)
        #expect(
            count.presentation.title
                == "Anzahl der Projekte mit Status: Offen"
        )
        guard let aggregation =
                group.aggregation,
              case .groupCount(let field) =
                aggregation
        else {
            Issue.record(
                "Expected the validated group-count field."
            )
            return
        }
        #expect(field.displayName == "Status")
        #expect(
            group.grouping?.field
                .displayName == "Status"
        )
        #expect(
            group.presentation.title
                == "Projekte, gruppiert nach Status"
        )
    }

    @Test
    func englishRenderingIsLocalAndContainsNoTechnicalQuerySummary()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let filtered =
            try fixture.filteredCollection(
                language: .english
            )
        let group =
            try fixture.groupInterpretation(
                language: .english
            )
        let graphState =
            try fixture.graphStateInterpretation(
                language: .english
            )

        #expect(
            filtered.presentation.label
                == "Understood as"
        )
        #expect(
            filtered.presentation.title
                == "Projects with Status: Open, sorted by Due date descending"
        )
        #expect(
            group.presentation.title
                == "Projects, grouped by Status"
        )
        #expect(
            graphState.presentation.title
                == "Health of the entire graph"
        )
        let visible = [
            filtered.presentation.title,
            group.presentation.title,
            graphState.presentation.title,
        ].joined(separator: "\n")
        #expect(visible.contains("Entity:") == false)
        #expect(
            visible.contains("Projection:")
                == false
        )
        #expect(visible.contains("Limit:") == false)
        #expect(
            visible.contains(
                GraphChatToolKind
                    .queryDetailValues
                    .rawValue
            ) == false
        )
    }

    @Test
    func singleFactBindsEntityNodeFieldScopeAndTurn()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let interpretation =
            try fixture.singleFactInterpretation(
                language: .german
            )

        #expect(
            interpretation.entities.first?
                .displayName == "Projekte"
        )
        #expect(
            interpretation.nodes.first?
                .displayName == "Atlas"
        )
        #expect(
            interpretation.fields.first?
                .displayName
                == "Fälligkeitsdatum"
        )
        #expect(
            interpretation.scopeBinding
                .graphScope
                == fixture.graphScope
        )
        #expect(
            interpretation.scopeBinding
                .chatScope
                == fixture.chatScope
        )
        #expect(
            interpretation.turnBinding
                .requestID
                == fixture.requestID
        )
        #expect(
            interpretation.turnBinding
                .conversationID
                == fixture.conversationID
        )
        #expect(
            interpretation.resolutionOrigin
                == .schemaDisplayName
        )
        #expect(
            interpretation.editableComponents
                == [.nodes, .fields]
        )
    }

    @Test
    func refinementAndComparisonUseOnlyRevalidatedReferences()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let refinement =
            try fixture.refinementInterpretation(
                language: .german
            )
        let comparison =
            try fixture.comparisonInterpretation(
                language: .german
            )

        #expect(
            refinement.resultExtent.kind
                == .refinedCollection
        )
        #expect(
            refinement.turnBinding.sourceTurnID
                == fixture.sourceTurnID
        )
        #expect(
            refinement.editableComponents
                .contains(.sourceResultSet)
        )
        #expect(
            refinement.presentation.title
                .contains(
                    "vorherigen Ergebnissen"
                )
        )
        #expect(
            comparison.nodes.map(\.displayName)
                == ["Atlas", "Apollo"]
        )
        #expect(
            comparison.resultExtent.subjectCount
                == 2
        )
        #expect(
            comparison.presentation.title
                .contains("Atlas und Apollo")
        )
    }

    @Test
    func presentationFirewallDropsOnlyAnUnsafeInterpretation()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let unsafe =
            try fixture.filteredCollection(
                language: .german,
                entityDisplayName: "E99"
            )
        let unsafeFilterValue =
            try fixture.filteredCollection(
                language: .german,
                filterDisplayValue:
                    fixture.statusFieldID
                        .uuidString
            )
        let context =
            GraphChatPresentationContext(
                registry: .empty,
                language: .german
            )

        for interpretation in [
            unsafe,
            unsafeFilterValue,
        ] {
            let answer = GraphChatAnswer(
                directAnswer:
                    "Die validierte Antwort bleibt erhalten.",
                hasInsufficientEvidence: false,
                presentationContext: context,
                interpretation:
                    interpretation
            )

            let result =
                GraphChatPresentationFirewall()
                    .present(
                        answer,
                        context: context
                    )
            guard case .safe(let safeAnswer) =
                    result
            else {
                Issue.record(
                    "An unsafe interpretation must not discard a safe answer."
                )
                return
            }
            #expect(
                safeAnswer.directAnswer
                    == answer.directAnswer
            )
            #expect(
                safeAnswer.interpretation
                    == nil
            )
        }
    }

    @Test
    func visibleInterpretationsNeverContainUUIDsOrInternalAliases()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let interpretations = try fixture
            .allGermanInterpretations()
        let visible = interpretations
            .map(\.presentation.title)
            .joined(separator: "\n")
        let accessibility = interpretations
            .map {
                $0.presentation
                    .accessibilityLabel
            }
            .joined(separator: "\n")
        let forbidden = [
            "E1",
            "E99",
            "F1",
            "F2",
            "F3",
            "N1",
            "CURRENT",
            fixture.graphScope.graphID
                .uuidString,
            fixture.entityID.uuidString,
            fixture.statusFieldID.uuidString,
            fixture.atlasNode.node.id
                .uuidString,
        ]

        #expect(
            forbidden.allSatisfy {
                visible.contains($0) == false
            }
        )
        #expect(
            forbidden.allSatisfy {
                accessibility.contains($0)
                    == false
            }
        )
        #expect(
            interpretations.allSatisfy {
                $0.presentation
                    .accessibilityLabel
                    .hasPrefix(
                        "Verstanden als: "
                    )
            }
        )
    }

    @Test
    func modelAnswerAndQuerySummaryCannotChangeInterpretation()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let interpretation =
            try fixture.filteredCollection(
                language: .german
            )
        let technicalSummary =
            GraphChatAnswerArtifactQuerySummary(
                language: .german,
                entityID: fixture.entityID,
                entityLabel:
                    fixture.entityID.uuidString,
                filters: [],
                grouping: nil,
                sorting: [],
                projection: [],
                includesNodeIdentity: true,
                limit: 50,
                aggregation: nil,
                displayText:
                    "Entity: E99; Limit: 50"
            )
        let answer = GraphChatAnswer(
            directAnswer:
                "Modelltext mit einer anderen Interpretation.",
            sections: [
                GraphChatAnswerSection(
                    text: "Zusatz",
                    querySummary:
                        technicalSummary
                ),
            ],
            hasInsufficientEvidence: false,
            presentationContext:
                GraphChatPresentationContext(
                    registry: .empty,
                    language: .german
                ),
            interpretation: interpretation
        )

        #expect(
            answer.interpretation?
                .presentation.title
                == interpretation
                    .presentation.title
        )
        #expect(
            answer.interpretation?
                .presentation.title
                .contains("Modelltext")
                == false
        )
        #expect(
            answer.interpretation?
                .presentation.title
                .contains("Entity:")
                == false
        )
        #expect(
            answer.interpretation?
                .presentation.title
                .contains(
                    fixture.entityID
                        .uuidString
                ) == false
        )
        let presented =
            GraphChatPresentationFirewall()
                .present(
                    answer,
                    context:
                        GraphChatPresentationContext(
                            registry: .empty,
                            language: .german
                        )
                )
        guard case .safe(let safeAnswer) =
                presented
        else {
            Issue.record(
                "Technical QuerySummary text must not replace a safe app interpretation."
            )
            return
        }
        #expect(
            safeAnswer.interpretation?
                .presentation.title
                == interpretation
                    .presentation.title
        )
    }

    @Test
    func legacyAnswersDoNotInventAnInterpretation() {
        let answer = GraphChatAnswer(
            directAnswer:
                "Legacy provider answer",
            hasInsufficientEvidence: false
        )
        var state =
            GraphChatAssistantMessageState(
                question: "Legacy question"
            )
        state.apply(.completed(answer))

        #expect(answer.interpretation == nil)
        #expect(
            state.answer?.interpretation == nil
        )
    }

    @Test
    func messageNormalizationArtifactRetentionAndTranscriptHistoryKeepInterpretation()
        async throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let interpretation =
            try fixture.filteredCollection(
                language: .german
            )
        let retained =
            GraphChatAnswerArtifactID()
        let removed =
            GraphChatAnswerArtifactID()
        let answer = GraphChatAnswer(
            directAnswer: String(
                repeating: "A",
                count:
                    GraphChatAssistantMessageState
                        .maximumTextLength
                    + 100
            ),
            artifactIDs: [
                retained,
                removed,
            ],
            hasInsufficientEvidence: false,
            presentationContext:
                GraphChatPresentationContext(
                    registry: .empty,
                    language: .german
                ),
            interpretation: interpretation
        )
        var state =
            GraphChatAssistantMessageState(
                question: "Frage"
            )
        state.apply(.completed(answer))

        #expect(
            state.answer?.interpretation
                == interpretation
        )
        let retainedAnswer =
            try #require(state.answer)
                .retainingArtifactIDs(
                    [retained]
                )
        #expect(
            retainedAnswer.interpretation
                == interpretation
        )

        let checkpoint =
            GraphChatConversationCheckpoint.initial(
                graphScope:
                    fixture.graphScope,
                chatScope:
                    fixture.chatScope
            )
        let transcript =
            GraphChatTranscriptMessage(
                state:
                    .assistant(state),
                conversationCheckpointBeforeTurn:
                    checkpoint,
                conversationCheckpointAfterTurn:
                    checkpoint
            )
        let store =
            InMemoryGraphChatHistoryStore()
        await store.save(
            [transcript],
            for: fixture.chatScope
        )
        let restoredMessages =
            await store.messages(
                for: fixture.chatScope
            )
        let restored =
            try #require(
                restoredMessages.first
            )
        guard case .assistant(let restoredState) =
                restored.state
        else {
            Issue.record(
                "Expected the assistant transcript state."
            )
            return
        }
        #expect(
            restoredState.answer?
                .interpretation
                == interpretation
        )
        #expect(
            restored.conversationCheckpointBeforeTurn
                == checkpoint
        )
        #expect(
            restored.conversationCheckpointAfterTurn
                == checkpoint
        )
    }

    @Test
    func copyKeepsTheFinalizedAnswerAndOmitsInterpretationByDefault()
        throws
    {
        let fixture =
            GraphChatIntentInterpretationTestFixture()
        let interpretation =
            try fixture.filteredCollection(
                language: .german
            )
        let authoritativeText =
            "Autoritativer Fachwert: 42."
        let answer = GraphChatAnswer(
            directAnswer: authoritativeText,
            hasInsufficientEvidence: false,
            presentationContext:
                GraphChatPresentationContext(
                    registry: .empty,
                    language: .german
                ),
            interpretation: interpretation
        )
        var state =
            GraphChatAssistantMessageState(
                question: "Wie hoch ist der Wert?"
            )
        state.apply(.completed(answer))
        let payload = try #require(
            GraphChatCopyContentBuilder.payload(
                for: state,
                sourcePolicy: .none
            )
        )

        #expect(payload.text == authoritativeText)
        #expect(
            payload.text.contains(
                interpretation.presentation.label
            ) == false
        )
        #expect(
            payload.text.contains(
                interpretation.presentation.title
            ) == false
        )
    }

    @Test
    func observabilityCarriesOnlyTheLifecycleEvent() {
        let metric =
            GraphChatIntentInterpretationMetric(
                event: .displayed
            )
        let serialized = String(
            reflecting:
                GraphChatObservabilityEvent
                    .intentInterpretation(
                        metric
                    )
        )

        #expect(
            metric
                == GraphChatIntentInterpretationMetric(
                    event: .displayed
                )
        )
        #expect(
            serialized.contains("Atlas")
                == false
        )
        #expect(
            serialized.contains(
                "Verstanden als"
            ) == false
        )
    }
}

struct GraphChatIntentInterpretationTestFixture {
    let graphScope = GraphScope(
        graphID: UUID(
            uuidString:
                "A5100000-0000-0000-0000-000000000001"
        )!
    )
    let requestID = UUID(
        uuidString:
            "A5100000-0000-0000-0000-000000000002"
    )!
    let conversationID = UUID(
        uuidString:
            "A5100000-0000-0000-0000-000000000003"
    )!
    let sourceTurnID = UUID(
        uuidString:
            "A5100000-0000-0000-0000-000000000004"
    )!
    let sourceResultContextID = UUID(
        uuidString:
            "A5100000-0000-0000-0000-000000000005"
    )!
    let entityID = UUID(
        uuidString:
            "A5100000-0000-0000-0000-000000000101"
    )!
    let statusFieldID = UUID(
        uuidString:
            "A5100000-0000-0000-0000-000000000201"
    )!
    let dueDateFieldID = UUID(
        uuidString:
            "A5100000-0000-0000-0000-000000000202"
    )!
    let budgetFieldID = UUID(
        uuidString:
            "A5100000-0000-0000-0000-000000000203"
    )!

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    var atlasNode:
        GraphChatTypedNodeIdentity
    {
        GraphChatTypedNodeIdentity(
            node: NodeRefKey(
                kind: .attribute,
                id: UUID(
                    uuidString:
                        "A5100000-0000-0000-0000-000000000301"
                )!
            ),
            displayName: "Atlas",
            ownerEntityID: entityID
        )
    }

    var apolloNode:
        GraphChatTypedNodeIdentity
    {
        GraphChatTypedNodeIdentity(
            node: NodeRefKey(
                kind: .attribute,
                id: UUID(
                    uuidString:
                        "A5100000-0000-0000-0000-000000000302"
                )!
            ),
            displayName: "Apollo",
            ownerEntityID: entityID
        )
    }

    func allGermanInterpretations()
        throws
        -> [GraphChatIntentInterpretation]
    {
        [
            try findInterpretation(
                language: .german
            ),
            try filteredCollection(
                language: .german
            ),
            try groupInterpretation(
                language: .german
            ),
            try singleFactInterpretation(
                language: .german
            ),
            try refinementInterpretation(
                language: .german
            ),
            try comparisonInterpretation(
                language: .german
            ),
            try graphStateInterpretation(
                language: .german
            ),
            try relationshipInterpretation(
                language: .german
            ),
        ]
    }

    func findInterpretation(
        language: GraphChatResponseLanguage
    ) throws -> GraphChatIntentInterpretation {
        let entity = entity(language)
        let intent = try makeIntent(
            language: language,
            queryScope: chatScope,
            expectedCardinality: .zeroOrMore,
            payload: .findNodes(
                GraphChatTypedFindNodesIntent(
                    entity: entity,
                    fields: [],
                    nodeScope: []
                )
            ),
            resultLimit: 20
        )
        return try #require(
            builder.searchInterpretation(
                intent: intent,
                action:
                    GraphChatLocalSearchAction(
                        query:
                            "This model-derived search term is not presented",
                        limit: 20,
                        scope: chatScope,
                        target: .entityNodes,
                        entityID: entityID
                    )
            )
        )
    }

    func filteredCollection(
        language: GraphChatResponseLanguage,
        entityDisplayName: String? = nil,
        filterDisplayValue: String? = nil
    ) throws -> GraphChatIntentInterpretation {
        let entity = entity(
            language,
            displayName: entityDisplayName
        )
        let status = statusField(language)
        let dueDate = dueDateField(language)
        let intent = try makeIntent(
            language: language,
            queryScope: chatScope,
            expectedCardinality: .zeroOrMore,
            payload: .entityCollection(
                GraphChatTypedEntityCollectionIntent(
                    entity: entity,
                    projectedFields: [],
                    referencedFields: [
                        status,
                        dueDate,
                    ]
                )
            ),
            resultLimit: 50
        )
        let plan = ValidatedGraphQueryPlan(
            version:
                GraphQueryPlan.currentVersion,
            graphScope: graphScope,
            entityID: entityID,
            scope: .graph,
            filters: [
                GraphValidatedQueryFilter(
                    fieldID: status.id,
                    fieldType: status.type,
                    operation: .equals,
                    value: .choice(
                        GraphResolvedChoiceValue(
                            originalValue:
                                language == .german
                                ? "offen"
                                : "open",
                            canonicalValue:
                                filterDisplayValue
                                ?? (
                                    language == .german
                                    ? "Offen"
                                    : "Open"
                                )
                        )
                    ),
                    valueDescription:
                        "Entity: E99; Limit: 50"
                ),
            ],
            sorting: [
                GraphValidatedQuerySort(
                    key: .field(dueDate.id),
                    direction: .descending
                ),
            ],
            projection: [.nodeIdentity],
            aggregation: nil,
            limit: 50
        )
        return try #require(
            builder.queryInterpretation(
                intent: intent,
                plan: plan
            )
        )
    }

    func countInterpretation(
        language: GraphChatResponseLanguage
    ) throws -> GraphChatIntentInterpretation {
        let entity = entity(language)
        let status = statusField(language)
        let intent = try makeIntent(
            language: language,
            queryScope: chatScope,
            expectedCardinality: .exactlyOne,
            payload: .countOrGroup(
                GraphChatTypedCountOrGroupIntent(
                    entity: entity,
                    operation: .count,
                    referencedFields: [status]
                )
            ),
            resultLimit: 1
        )
        let plan = ValidatedGraphQueryPlan(
            version:
                GraphQueryPlan.currentVersion,
            graphScope: graphScope,
            entityID: entityID,
            scope: .graph,
            filters: [
                GraphValidatedQueryFilter(
                    fieldID: status.id,
                    fieldType: status.type,
                    operation: .equals,
                    value: .choice(
                        GraphResolvedChoiceValue(
                            originalValue:
                                language == .german
                                ? "offen"
                                : "open",
                            canonicalValue:
                                language == .german
                                ? "Offen"
                                : "Open"
                        )
                    )
                ),
            ],
            sorting: [],
            projection: [.nodeIdentity],
            aggregation: .count,
            limit: 1
        )
        return try #require(
            builder.queryInterpretation(
                intent: intent,
                plan: plan
            )
        )
    }

    func groupInterpretation(
        language: GraphChatResponseLanguage
    ) throws -> GraphChatIntentInterpretation {
        let entity = entity(language)
        let status = statusField(language)
        let intent = try makeIntent(
            language: language,
            queryScope: chatScope,
            expectedCardinality: .zeroOrMore,
            payload: .countOrGroup(
                GraphChatTypedCountOrGroupIntent(
                    entity: entity,
                    operation: .group(
                        field: status
                    )
                )
            ),
            resultLimit: 50
        )
        let plan = ValidatedGraphQueryPlan(
            version:
                GraphQueryPlan.currentVersion,
            graphScope: graphScope,
            entityID: entityID,
            scope: .graph,
            filters: [],
            sorting: [],
            projection: [.nodeIdentity],
            aggregation:
                .groupCount(status.id),
            limit: 50
        )
        return try #require(
            builder.queryInterpretation(
                intent: intent,
                plan: plan
            )
        )
    }

    func singleFactInterpretation(
        language: GraphChatResponseLanguage
    ) throws -> GraphChatIntentInterpretation {
        let entity = entity(language)
        let dueDate = dueDateField(language)
        let scope = GraphChatScope.node(
            atlasNode.node,
            in: graphScope
        )
        let intent = try makeIntent(
            language: language,
            queryScope: scope,
            expectedCardinality: .zeroOrOne,
            factExpectation:
                .authoritativeSingleField,
            payload: .nodeDetails(
                GraphChatTypedNodeDetailsIntent(
                    entity: entity,
                    node: atlasNode,
                    fields: [dueDate]
                )
            ),
            resultLimit: 1
        )
        let plan = ValidatedGraphQueryPlan(
            version:
                GraphQueryPlan.currentVersion,
            graphScope: graphScope,
            entityID: entityID,
            scope: .node(atlasNode.node),
            filters: [],
            sorting: [],
            projection: [
                .nodeIdentity,
                .field(dueDate.id),
            ],
            aggregation: nil,
            limit: 1
        )
        return try #require(
            builder.queryInterpretation(
                intent: intent,
                plan: plan
            )
        )
    }

    func refinementInterpretation(
        language: GraphChatResponseLanguage
    ) throws -> GraphChatIntentInterpretation {
        let entity = entity(language)
        let dueDate = dueDateField(language)
        let nodes = [
            atlasNode,
            apolloNode,
        ]
        let scope = try GraphChatScope.selection(
            nodes.map(\.node),
            in: graphScope
        )
        let intent = try makeIntent(
            language: language,
            queryScope: scope,
            expectedCardinality: .zeroOrMore,
            payload: .narrowResultSet(
                GraphChatTypedNarrowResultSetIntent(
                    sourceResultContextID:
                        sourceResultContextID,
                    entity: entity,
                    nodes: nodes,
                    fields: [dueDate],
                    projectedFields: []
                )
            ),
            resultLimit: 2,
            sourceTurnID: sourceTurnID
        )
        let interval =
            GraphQueryDateInterval(
                lowerBound: Date(
                    timeIntervalSince1970: 0
                ),
                upperBoundExclusive: Date(
                    timeIntervalSince1970:
                        1_800_000_000
                )
            )
        let plan = ValidatedGraphQueryPlan(
            version:
                GraphQueryPlan.currentVersion,
            graphScope: graphScope,
            entityID: entityID,
            scope:
                .selection(
                    nodes.map(\.node)
                ),
            filters: [
                GraphValidatedQueryFilter(
                    fieldID: dueDate.id,
                    fieldType: dueDate.type,
                    operation: .isOverdue,
                    value: .dateInterval(
                        interval
                    )
                ),
            ],
            sorting: [
                GraphValidatedQuerySort(
                    key: .nodeName,
                    direction: .ascending
                ),
            ],
            projection: [.nodeIdentity],
            aggregation: nil,
            limit: 2
        )
        return try #require(
            builder.queryInterpretation(
                intent: intent,
                plan: plan
            )
        )
    }

    func comparisonInterpretation(
        language: GraphChatResponseLanguage
    ) throws -> GraphChatIntentInterpretation {
        let entity = entity(language)
        let status = statusField(language)
        let budget = budgetField(language)
        let nodes = [
            atlasNode,
            apolloNode,
        ]
        let scope = try GraphChatScope.selection(
            nodes.map(\.node),
            in: graphScope
        )
        let intent = try makeIntent(
            language: language,
            queryScope: scope,
            expectedCardinality: .twoOrMore,
            payload: .compareNodes(
                GraphChatTypedCompareNodesIntent(
                    entities: [entity],
                    nodes: nodes,
                    fields: [
                        status,
                        budget,
                    ]
                )
            ),
            resultLimit: 2
        )
        let comparison = try GraphChatComparisonPlan(
            graphScope: graphScope,
            chatScope: chatScope,
            binding: intent.binding,
            nodes: nodes,
            kind: .sameEntityAttributes,
            features: [
                .field(status),
                .field(budget),
            ],
            selectionQuery: GraphQueryPlan(
                entityAlias: entity.alias,
                scope: scope,
                sorting: [
                    GraphQuerySort(
                        key: .nodeName,
                        direction: .ascending
                    ),
                ],
                projection: [
                    .nodeIdentity,
                    .field(status.alias),
                    .field(budget.alias),
                ],
                limit: 2
            ),
            relatedLimit: 0,
            responseLanguage: language
        )
        return try #require(
            builder.comparisonInterpretation(
                intent: intent,
                plan: comparison
            )
        )
    }

    func graphStateInterpretation(
        language: GraphChatResponseLanguage
    ) throws -> GraphChatIntentInterpretation {
        let intent = try makeIntent(
            language: language,
            queryScope: chatScope,
            expectedCardinality: .exactlyOne,
            payload: .inspectGraphState(
                GraphChatTypedInspectGraphStateIntent(
                    aspect: .health
                )
            ),
            resultLimit:
                GraphChatAdvancedIntentPolicy
                    .default
                    .graphHubLimit
        )
        return try #require(
            builder.graphStateInterpretation(
                intent: intent,
                action:
                    GraphChatLocalGraphStateAction(
                        aspect: .health,
                        hubLimit:
                            GraphChatAdvancedIntentPolicy
                                .default
                                .graphHubLimit
                    )
            )
        )
    }

    func relationshipInterpretation(
        language: GraphChatResponseLanguage
    ) throws -> GraphChatIntentInterpretation {
        let binding =
            GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID:
                    conversationID,
                turnID: requestID,
                sourceTurnID: nil,
                clarificationID: nil
            )
        let limits =
            GraphChatTypedIntentLimits(
                resultLimit:
                    GraphChatIntentLimitPolicy
                        .default
                        .nodeDetailRelatedItemCount,
                maximumResultLimit:
                    GraphChatIntentLimitPolicy
                        .default
                        .maximumNeighborCount,
                maximumEvidenceCount:
                    GraphChatIntentLimitPolicy
                        .default
                        .maximumNeighborCount + 1,
                maximumArtifactCount: 1
            )
        let queryScope =
            GraphChatScope.node(
                atlasNode.node,
                in: graphScope
            )
        let plan =
            try GraphChatRelationshipPlan(
                graphScope: graphScope,
                chatScope: chatScope,
                queryScope: queryScope,
                binding: binding,
                request: .connections,
                centerEntity:
                    entity(language),
                centerNode: atlasNode,
                direction: .both,
                counterpartEntity:
                    entity(language),
                counterpartNode:
                    apolloNode,
                limits: limits,
                responseLanguage: language
            )
        let intent =
            try GraphChatTypedIntent(
                version: .v2,
                scope:
                    GraphChatTypedIntentScope(
                        graphScope:
                            graphScope,
                        chatScope:
                            chatScope,
                        queryScope:
                            queryScope
                    ),
                responseLanguage:
                    language,
                binding: binding,
                resolution:
                    GraphChatTypedIntentResolution(
                        source:
                            .appSemanticResolution,
                        origin:
                            .schemaDisplayName,
                        quality: .exact
                    ),
                expectedCardinality:
                    .zeroOrMore,
                factExpectation: .none,
                limits: limits,
                payload:
                    .relationships(plan)
            )
        return try #require(
            builder.executionInterpretation(
                intent: intent,
                witness:
                    .relationship(plan)
            )
        )
    }

    private var builder:
        GraphChatIntentInterpretationBuilder
    {
        GraphChatIntentInterpretationBuilder(
            timeZone: TimeZone(
                secondsFromGMT: 0
            )!
        )
    }

    private func makeIntent(
        language: GraphChatResponseLanguage,
        queryScope: GraphChatScope,
        expectedCardinality:
            GraphChatTypedIntentExpectedCardinality,
        factExpectation:
            GraphChatTypedIntentFactExpectation = .none,
        payload: GraphChatTypedIntentPayload,
        resultLimit: Int,
        sourceTurnID: UUID? = nil
    ) throws -> GraphChatTypedIntent {
        try GraphChatTypedIntent(
            version: .v1,
            scope: GraphChatTypedIntentScope(
                graphScope: graphScope,
                chatScope: chatScope,
                queryScope: queryScope
            ),
            responseLanguage: language,
            binding: GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID:
                    conversationID,
                turnID: requestID,
                sourceTurnID: sourceTurnID,
                clarificationID: nil
            ),
            resolution:
                GraphChatTypedIntentResolution(
                    source:
                        sourceTurnID == nil
                        ? .appSemanticResolution
                        : .conversationContinuation,
                    origin:
                        sourceTurnID == nil
                        ? .schemaDisplayName
                        : .conversationReference,
                    quality:
                        sourceTurnID == nil
                        ? .exact
                        : .revalidatedConversationReference
                ),
            expectedCardinality:
                expectedCardinality,
            factExpectation:
                factExpectation,
            limits: GraphChatTypedIntentLimits(
                resultLimit: resultLimit,
                maximumResultLimit:
                    GraphQueryPlanLimits
                        .maximumResultLimit,
                maximumEvidenceCount:
                    GraphQueryPlanLimits
                        .maximumResultLimit,
                maximumArtifactCount:
                    GraphChatAdvancedIntentPolicy
                        .default
                        .maximumArtifactCount
            ),
            payload: payload
        )
    }

    private func entity(
        _ language: GraphChatResponseLanguage,
        displayName: String? = nil
    ) -> GraphChatTypedEntityIdentity {
        GraphChatTypedEntityIdentity(
            id: entityID,
            alias: GraphEntityAlias("E1"),
            displayName:
                displayName
                ?? (
                    language == .german
                    ? "Projekte"
                    : "Projects"
                )
        )
    }

    private func statusField(
        _ language: GraphChatResponseLanguage
    ) -> GraphChatTypedFieldIdentity {
        GraphChatTypedFieldIdentity(
            id: statusFieldID,
            alias: GraphFieldAlias("F1"),
            displayName: "Status",
            ownerEntityID: entityID,
            type: .singleChoice,
            unit: nil
        )
    }

    private func dueDateField(
        _ language: GraphChatResponseLanguage
    ) -> GraphChatTypedFieldIdentity {
        GraphChatTypedFieldIdentity(
            id: dueDateFieldID,
            alias: GraphFieldAlias("F2"),
            displayName:
                language == .german
                ? "Fälligkeitsdatum"
                : "Due date",
            ownerEntityID: entityID,
            type: .date,
            unit: nil
        )
    }

    private func budgetField(
        _ language: GraphChatResponseLanguage
    ) -> GraphChatTypedFieldIdentity {
        GraphChatTypedFieldIdentity(
            id: budgetFieldID,
            alias: GraphFieldAlias("F3"),
            displayName:
                language == .german
                ? "Budget"
                : "Budget",
            ownerEntityID: entityID,
            type: .numberDouble,
            unit: "EUR"
        )
    }
}
