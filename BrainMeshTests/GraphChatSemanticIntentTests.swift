import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat semantic intent contracts")
struct GraphChatSemanticIntentTests {
    @Test
    func interpreterRequestIsValueOnlyAndHasNoToolRunner() {
        let request = GraphChatIntentInterpreterRequest(
            normalizedQuestion:
                "Find Project Atlas.",
            responseLanguage: .english,
            schemaEntities: [
                GraphChatSemanticSchemaEntity(
                    displayName: "Projects",
                    fieldDisplayNames:
                        ["Status"]
                )
            ],
            conversationDescriptions:
                ["Atlas"],
            scopeDescription:
                "Entire graph Portfolio"
        )
        let labels = Set(
            Mirror(reflecting: request)
                .children
                .compactMap(\.label)
        )

        #expect(
            labels == [
                "normalizedQuestion",
                "responseLanguage",
                "schemaEntities",
                "conversationDescriptions",
                "scopeDescription",
            ]
        )
        #expect(
            labels.contains("toolRunner")
                == false
        )
        #expect(
            labels.contains("graphScope")
                == false
        )

        let draft =
            GraphChatUntrustedSemanticIntentDraft(
                family: .findNodes,
                entityTerm: "Projects",
                searchTerm: "Atlas",
                responseLanguage: .english
            )
        let draftLabels = Set(
            Mirror(reflecting: draft)
                .children
                .compactMap(\.label)
        )
        #expect(
            draftLabels.contains("entityID")
                == false
        )
        #expect(
            draftLabels.contains("tool")
                == false
        )
        #expect(
            draftLabels.contains("limit")
                == false
        )
    }

    @Test
    func validatorRejectsTechnicalIdentifiers()
        throws
    {
        let request = interpreterRequest()
        let validator =
            GraphChatSemanticDraftValidator()
        let forbiddenValues = [
            "E1",
            "F27",
            "N4",
            "E-7",
            "CURRENT",
            "CR_123",
            "CF_ABC123",
            "LAST_COMPARISON",
            "searchGraph",
            "GraphQueryPlan",
            "artifact ID",
            UUID().uuidString,
        ]

        for value in forbiddenValues {
            #expect(
                throws:
                    GraphChatSemanticDraftValidationError
                        .technicalIdentifier
            ) {
                try validator.validate(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .findNodes,
                        searchTerm: value,
                        responseLanguage:
                            .english
                    ),
                    for: request
                )
            }
        }
    }

    @Test
    func interpreterContextIsAppBoundedAndUserVisible()
        throws
    {
        let context =
            GraphChatTestSupport
                .makeSchemaContext()
        let plan = providerPlan(
            schemaContext: context,
            question:
                "Find Project Atlas.",
            language: .english
        )
        let request =
            try GraphChatIntentInterpreterRequestBuilder(
                limits:
                    GraphChatIntentInterpreterContextLimits(
                        maximumEntities: 1,
                        maximumFieldsPerEntity: 1,
                        maximumConversationDescriptions:
                            1,
                        maximumDescriptionLength: 40
                    )
            ).makeRequest(
                providerPlan: plan,
                schemaContext: context
            )
        let visibleValues =
            request.schemaEntities.flatMap {
                [$0.displayName]
                    + $0.fieldDisplayNames
            } + [request.scopeDescription]

        #expect(request.schemaEntities.count == 1)
        #expect(
            request.schemaEntities[0]
                .fieldDisplayNames.count == 1
        )
        #expect(
            visibleValues.allSatisfy {
                $0.contains(
                    context.graphScope
                        .graphID.uuidString
                ) == false
            }
        )
        #expect(
            visibleValues.allSatisfy {
                GraphChatSemanticSafety
                    .containsTechnicalIdentifier(
                        $0
                    ) == false
            }
        )
    }

    @Test
    func validatorRejectsUnsupportedCombinations()
        throws
    {
        let request = interpreterRequest()
        let validator =
            GraphChatSemanticDraftValidator()

        #expect(
            throws:
                GraphChatSemanticDraftValidationError
                    .invalidCombination
        ) {
            try validator.validate(
                GraphChatUntrustedSemanticIntentDraft(
                    family: .entityList,
                    entityTerm: "Projects",
                    searchTerm: "Atlas",
                    responseLanguage: .english
                ),
                for: request
            )
        }
        #expect(
            throws:
                GraphChatSemanticDraftValidationError
                    .invalidRequestedCount
        ) {
            try validator.validate(
                GraphChatUntrustedSemanticIntentDraft(
                    family: .findNodes,
                    searchTerm: "Atlas",
                    resultAmount:
                        .first(10_001),
                    responseLanguage: .english
                ),
                for: request
            )
        }
    }

    @Test
    func entityIdentityComesFromFullAppSchema()
        throws
    {
        let context =
            contextWithBoundedPromptSchema()
        let plan = providerPlan(
            schemaContext: context,
            question:
                "Could you show the people entries?",
            language: .english
        )
        let result =
            try GraphChatSemanticIntentResolver()
                .resolve(
                    draft:
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .entityList,
                            entityTerm:
                                "Personen",
                            responseLanguage:
                                .english
                        ),
                    selectedEntityID: nil,
                    currentResolvedScope:
                        nil,
                    providerPlan: plan,
                    schemaContext: context,
                    requestID: UUID(),
                    sourceTurnID: nil,
                    clarificationID: nil
                )
        guard
            case .compiled(let adaptation) =
                result
        else {
            Issue.record(
                "Expected a compiled entity list."
            )
            return
        }

        #expect(
            context.snapshot.entities
                .contains {
                    $0.name == "Personen"
                } == false
        )
        #expect(
            adaptation.intent.payload
                .entities.first?.id
                == GraphChatTestSupport
                    .personEntityID
        )
        #expect(
            adaptation.intent.payload
                .entities.first?.alias
                == GraphEntityAlias("E2")
        )
    }

    @Test
    func equalEntityNamesRequireClarification()
        throws
    {
        let context =
            contextWithDuplicateEntityNames()
        let plan = providerPlan(
            schemaContext: context,
            question:
                "Please list the projects.",
            language: .english
        )
        let result =
            try GraphChatSemanticIntentResolver()
                .resolve(
                    draft:
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .entityList,
                            entityTerm:
                                "Projekte",
                            responseLanguage:
                                .english
                        ),
                    selectedEntityID: nil,
                    currentResolvedScope:
                        nil,
                    providerPlan: plan,
                    schemaContext: context,
                    requestID: UUID(),
                    sourceTurnID: nil,
                    clarificationID: nil
                )

        guard
            case .clarification(
                let clarification
            ) = result
        else {
            Issue.record(
                "Expected an entity clarification."
            )
            return
        }
        #expect(
            clarification.candidates.count == 2
        )
        #expect(
            clarification.candidates
                .allSatisfy {
                    $0.displayName == "Projekte"
                }
        )
    }

    @Test
    func semanticResolutionNeverBroadensEntityScope()
        throws
    {
        let context =
            GraphChatTestSupport
                .makeSchemaContext()
        let projectScope = GraphChatScope.entity(
            GraphChatTestSupport
                .projectEntityID,
            in: context.graphScope
        )
        let plan = providerPlan(
            schemaContext: context,
            chatScope: projectScope,
            question:
                "List people.",
            language: .english
        )

        #expect(
            throws:
                GraphChatSemanticIntentResolutionError
                    .scopeViolation
        ) {
            try GraphChatSemanticIntentResolver()
                .resolve(
                    draft:
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .entityList,
                            entityTerm:
                                "Personen",
                            responseLanguage:
                                .english
                        ),
                    selectedEntityID: nil,
                    currentResolvedScope:
                        nil,
                    providerPlan: plan,
                    schemaContext: context,
                    requestID: UUID(),
                    sourceTurnID: nil,
                    clarificationID: nil
                )
        }
    }

    @Test
    func searchAuthorizationPreservesNodeAndSelectionScopes()
        throws
    {
        let context =
            GraphChatTestSupport
                .makeSchemaContext()
        let projectNode = NodeRefKey(
            kind: .attribute,
            id:
                GraphChatTestSupport
                    .projectAttributeID
        )
        let personNode = NodeRefKey(
            kind: .attribute,
            id:
                GraphChatTestSupport
                    .personAttributeID
        )
        let nodeScope = GraphChatScope.node(
            projectNode,
            in: context.graphScope
        )
        let selectionScope =
            try GraphChatScope.selection(
                [projectNode, personNode],
                in: context.graphScope
            )

        #expect(
            GraphChatScopeAuthorization.allows(
                scope: nodeScope,
                within: nodeScope,
                aliases: context.aliases
            )
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                scope:
                    .entireGraph(
                        context.graphScope
                    ),
                within: nodeScope,
                aliases: context.aliases
            ) == false
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                scope: nodeScope,
                within: selectionScope,
                aliases: context.aliases
            )
        )
        #expect(
            GraphChatScopeAuthorization.allows(
                scope:
                    .node(
                        NodeRefKey(
                            kind: .attribute,
                            id: UUID()
                        ),
                        in:
                            context.graphScope
                    ),
                within: selectionScope,
                aliases: context.aliases
            ) == false
        )
    }

    @Test
    func appPolicyOwnsFindAndListLimits()
        throws
    {
        let context =
            GraphChatTestSupport
                .makeSchemaContext()
        let plan = providerPlan(
            schemaContext: context,
            question: "Natural language",
            language: .english
        )
        let resolver =
            GraphChatSemanticIntentResolver()
        let standardList = try compiled(
            resolver.resolve(
                draft:
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .entityList,
                        entityTerm: "Projekte",
                        resultAmount: .standard,
                        responseLanguage:
                            .english
                    ),
                selectedEntityID: nil,
                currentResolvedScope: nil,
                providerPlan: plan,
                schemaContext: context,
                requestID: UUID(),
                sourceTurnID: nil,
                clarificationID: nil
            )
        )
        let allList = try compiled(
            resolver.resolve(
                draft:
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .entityList,
                        entityTerm: "Projekte",
                        resultAmount: .all,
                        responseLanguage:
                            .english
                    ),
                selectedEntityID: nil,
                currentResolvedScope: nil,
                providerPlan: plan,
                schemaContext: context,
                requestID: UUID(),
                sourceTurnID: nil,
                clarificationID: nil
            )
        )
        let firstFind = try compiled(
            resolver.resolve(
                draft:
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .findNodes,
                        searchTerm: "migration",
                        resultAmount:
                            .first(500),
                        responseLanguage:
                            .english
                    ),
                selectedEntityID: nil,
                currentResolvedScope: nil,
                providerPlan: plan,
                schemaContext: context,
                requestID: UUID(),
                sourceTurnID: nil,
                clarificationID: nil
            )
        )

        #expect(
            standardList.intent.limits
                .resultLimit
                == GraphQueryPlanLimits
                    .defaultResultLimit
        )
        #expect(
            allList.intent.limits.resultLimit
                == GraphQueryPlanLimits
                    .maximumResultLimit
        )
        #expect(
            firstFind.intent.limits.resultLimit
                == SearchGraphTool
                    .maximumResultCount
        )
        guard
            case .queryDetailValues(
                let standardAction
            ) = standardList.action,
            case .queryDetailValues(
                let allAction
            ) = allList.action,
            case .searchGraph(
                let findAction
            ) = firstFind.action
        else {
            Issue.record(
                "Expected app-compiled actions."
            )
            return
        }
        #expect(
            standardAction.plan.limit
                == GraphQueryPlanLimits
                    .defaultResultLimit
        )
        #expect(
            allAction.plan.limit
                == GraphQueryPlanLimits
                    .maximumResultLimit
        )
        #expect(
            findAction.limit
                == SearchGraphTool
                    .maximumResultCount
        )
    }

    @Test
    func localSearchFiltersGraphEntityAndKind() {
        let context =
            GraphChatTestSupport
                .makeSchemaContext()
        let projectID =
            GraphChatTestSupport
                .projectEntityID
        let projectNode =
            GraphChatTestSupport
                .projectAttributeID
        let personNode =
            GraphChatTestSupport
                .personAttributeID
        let projectEvidence = evidence(
            graphID:
                GraphChatTestSupport.graphID,
            sourceID: projectNode,
            ownerID: projectID,
            title: "Atlas"
        )
        let personEvidence = evidence(
            graphID:
                GraphChatTestSupport.graphID,
            sourceID: personNode,
            ownerID:
                GraphChatTestSupport
                    .personEntityID,
            title: "Atlas Person"
        )
        let foreignEvidence = evidence(
            graphID:
                GraphChatTestSupport
                    .otherGraphID,
            sourceID: UUID(),
            ownerID: UUID(),
            title: "Atlas Foreign"
        )
        let output = SearchGraphOutput(
            query: "atlas",
            hits: [
                hit(
                    evidence: projectEvidence,
                    kind: .attribute,
                    title: "Atlas"
                ),
                hit(
                    evidence: personEvidence,
                    kind: .attribute,
                    title: "Atlas Person"
                ),
                hit(
                    evidence: foreignEvidence,
                    kind: .attribute,
                    title: "Atlas Foreign"
                ),
                GraphChatSearchHit(
                    sourceReference:
                        GraphSourceReference(
                            graphID:
                                GraphChatTestSupport
                                    .graphID,
                            sourceKind: .entity,
                            sourceID: projectID,
                            node:
                                GraphSourceNodeReference(
                                    kind: .entity,
                                    id: projectID
                                )
                        ),
                    kind: .entity,
                    title: "Projekte",
                    subtitle: "Entity",
                    matchReason: "Name",
                    evidenceID:
                        GraphEvidence(
                            sourceReference:
                                GraphSourceReference(
                                    graphID:
                                        GraphChatTestSupport
                                            .graphID,
                                    sourceKind:
                                        .entity,
                                    sourceID:
                                        projectID,
                                    node:
                                        GraphSourceNodeReference(
                                            kind:
                                                .entity,
                                            id:
                                                projectID
                                        )
                                ),
                            summary:
                                "Projekte"
                        ).id
                ),
            ],
            resultWindow:
                GraphChatResultWindow(
                    totalCount: 4,
                    returnedCount: 4
                )
        )
        let raw =
            GraphChatToolResult<SearchGraphOutput>(
                state: .success,
                payload: output,
                evidence: [
                    projectEvidence,
                    personEvidence,
                    foreignEvidence,
                ]
            )
        let action = GraphChatLocalSearchAction(
            query: "atlas",
            limit: 20,
            scope: .entity(
                projectID,
                in: context.graphScope
            ),
            target: .entityNodes,
            entityID: projectID
        )
        let result =
            GraphChatLocalIntentSearchExecutionSupport()
                .normalizedResult(
                    raw,
                    action: action,
                    schemaContext:
                        context
                )

        #expect(
            result.output.hits.map(\.title)
                == ["Atlas"]
        )
        #expect(
            result.evidence
                .map(\.sourceReference.sourceID)
                == [projectNode]
        )
        #expect(
            result.output.hits
                .allSatisfy {
                    $0.subtitle.isEmpty
                        && $0.matchReason.isEmpty
                }
        )
        #expect(
            result.evidence
                .allSatisfy {
                    $0.fieldValues.isEmpty
                        && $0.summary
                            == $0.navigationTitle
                }
        )
        #expect(
            result.output.resultWindow
                .limitReached
        )
        #expect(
            result.output.resultWindow
                .limitSources
                .contains(.source)
        )
        #expect(
            result.output.resultWindow
                .totalCount == nil
        )
    }

    @Test
    func searchArtifactNeverRendersMatchSnippetOrDetailValue() {
        let source =
            GraphSourceReference(
                graphID:
                    GraphChatTestSupport.graphID,
                sourceKind: .attribute,
                sourceID:
                    GraphChatTestSupport
                        .projectAttributeID,
                node:
                    GraphSourceNodeReference(
                        kind: .attribute,
                        id:
                            GraphChatTestSupport
                                .projectAttributeID
                    ),
                owner:
                    GraphSourceNodeReference(
                        kind: .entity,
                        id:
                            GraphChatTestSupport
                                .projectEntityID
                    )
            )
        let evidence = GraphEvidence(
            sourceReference: source,
            summary:
                "Atlas — Attribute",
            fieldValues: [
                GraphEvidenceFieldValue(
                    fieldID: UUID(),
                    fieldName: "Budget",
                    value: .integer(999_999),
                    unit: "EUR"
                )
            ],
            identitySuffix: "search"
        )
        let output = SearchGraphOutput(
            query: "atlas",
            hits: [
                GraphChatSearchHit(
                    sourceReference: source,
                    kind: .attribute,
                    title: "Atlas",
                    subtitle:
                        "SECRET 999999 EUR",
                    matchReason:
                        "SECRET 999999 EUR",
                    evidenceID: evidence.id
                )
            ]
        )
        let normalized =
            GraphChatLocalIntentSearchExecutionSupport()
                .normalizedResult(
                    GraphChatToolResult(
                        state: .success,
                        payload: output,
                        evidence: [evidence]
                    ),
                    action:
                        GraphChatLocalSearchAction(
                            query: "atlas",
                            limit: 20,
                            scope:
                                .entireGraph(
                                    GraphChatTestSupport
                                        .makeSchemaContext()
                                        .graphScope
                                ),
                            target: .anyEntry,
                            entityID: nil
                        ),
                    schemaContext:
                        GraphChatTestSupport
                            .makeSchemaContext()
                )
        let draft =
            GraphChatAnswerArtifactFactory
                .searchResults(
                    output:
                        normalized.output,
                    graphScope:
                        GraphChatTestSupport
                            .makeSchemaContext()
                            .graphScope,
                    requestedLimit: 20,
                    language: .german
                )
        guard
            case .resultList(let payload) =
                draft?.payload
        else {
            Issue.record(
                "Expected search artifact."
            )
            return
        }
        let visible = payload.rows
            .flatMap {
                [$0.primaryText]
                    + [$0.secondaryText]
                        .compactMap { $0 }
            }
            .joined(separator: "\n")

        #expect(visible.contains("Atlas"))
        #expect(visible.contains("SECRET") == false)
        #expect(visible.contains("999999") == false)
        #expect(visible.contains("EUR") == false)
        #expect(
            normalized.evidence
                .allSatisfy {
                    $0.fieldValues.isEmpty
                }
        )
    }

    private func interpreterRequest()
        -> GraphChatIntentInterpreterRequest
    {
        GraphChatIntentInterpreterRequest(
            normalizedQuestion:
                "Find Project Atlas.",
            responseLanguage: .english,
            schemaEntities: [],
            conversationDescriptions: [],
            scopeDescription:
                "Entire graph"
        )
    }

    private func providerPlan(
        schemaContext: GraphSchemaContext,
        chatScope: GraphChatScope? = nil,
        question: String,
        language: GraphChatResponseLanguage
    ) -> GraphChatProviderTurnPlan {
        let scope =
            chatScope
            ?? .entireGraph(
                schemaContext.graphScope
            )
        let state =
            GraphChatConversationState.initial(
                graphScope:
                    schemaContext.graphScope,
                chatScope: scope
            )
        return GraphChatProviderTurnPlan(
            scopeKey:
                GraphChatOrchestrationScopeKey(
                    graphScope:
                        schemaContext
                            .graphScope,
                    chatScope: scope
                ),
            normalizedQuestion: question,
            providerQuestion: question,
            responseLanguage: language,
            requestBaseState: state,
            expectedCommittedState: state,
            conversationContext:
                GraphChatConversationContextBuilder()
                    .makeSnapshot(
                        from: state.snapshot
                    ),
            currentReference: nil,
            currentResolvedScope: nil,
            continuationOperation: nil,
            foundationalContinuation: nil
        )
    }

    private func compiled(
        _ resolution:
            GraphChatSemanticIntentResolution
    ) throws -> GraphChatTypedIntentAdaptation {
        guard
            case .compiled(let adaptation) =
                resolution
        else {
            throw SemanticIntentTestError
                .expectedCompiled
        }
        return adaptation
    }

    private func contextWithBoundedPromptSchema()
        -> GraphSchemaContext
    {
        let base =
            GraphChatTestSupport
                .makeSchemaContext()
        let projectAlias =
            GraphEntityAlias("E1")
        let promptAliases =
            GraphSchemaAliasMap(
                graphScope: base.graphScope,
                entitiesByAlias: [
                    projectAlias:
                        base.aliases
                            .entitiesByAlias[
                                projectAlias
                            ]!,
                ],
                fieldsByAlias:
                    base.aliases
                        .fieldsByAlias
                        .filter {
                            $0.value.entityAlias
                                == projectAlias
                        },
                nodeEntityIDs:
                    base.aliases
                        .nodeEntityIDs
                        .filter {
                            $0.value
                                == GraphChatTestSupport
                                    .projectEntityID
                        }
            )
        return GraphSchemaContext(
            graphScope: base.graphScope,
            snapshot:
                GraphSchemaSnapshot(
                    graphName:
                        base.snapshot.graphName,
                    entities:
                        Array(
                            base.snapshot
                                .entities
                                .prefix(1)
                        ),
                    truncation:
                        base.snapshot.truncation
                ),
            aliases: promptAliases,
            foundationalAliases:
                base.aliases
        )
    }

    private func contextWithDuplicateEntityNames()
        -> GraphSchemaContext
    {
        let base =
            GraphChatTestSupport
                .makeSchemaContext()
        let duplicateID = UUID()
        var entities =
            base.aliases.entitiesByAlias
        entities[GraphEntityAlias("E3")] =
            GraphSchemaEntityResolution(
                alias: GraphEntityAlias("E3"),
                entityID: duplicateID,
                name: "Projekte"
            )
        var nodeEntityIDs =
            base.aliases.nodeEntityIDs
        nodeEntityIDs[
            NodeRefKey(
                kind: .entity,
                id: duplicateID
            )
        ] = duplicateID
        let aliases = GraphSchemaAliasMap(
            graphScope: base.graphScope,
            entitiesByAlias: entities,
            fieldsByAlias:
                base.aliases.fieldsByAlias,
            nodeEntityIDs: nodeEntityIDs
        )
        return GraphSchemaContext(
            graphScope: base.graphScope,
            snapshot: base.snapshot,
            aliases: aliases
        )
    }

    private func evidence(
        graphID: UUID,
        sourceID: UUID,
        ownerID: UUID,
        title: String
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference:
                GraphSourceReference(
                    graphID: graphID,
                    sourceKind: .attribute,
                    sourceID: sourceID,
                    node:
                        GraphSourceNodeReference(
                            kind: .attribute,
                            id: sourceID
                        ),
                    owner:
                        GraphSourceNodeReference(
                            kind: .entity,
                            id: ownerID
                        )
                ),
            summary: title,
            navigationTitle: title
        )
    }

    private func hit(
        evidence: GraphEvidence,
        kind: BrainMeshSearchResultKind,
        title: String
    ) -> GraphChatSearchHit {
        GraphChatSearchHit(
            sourceReference:
                evidence.sourceReference,
            kind: kind,
            title: title,
            subtitle: "Attribut",
            matchReason: "Name",
            evidenceID: evidence.id
        )
    }
}

private enum SemanticIntentTestError: Error {
    case expectedCompiled
}
