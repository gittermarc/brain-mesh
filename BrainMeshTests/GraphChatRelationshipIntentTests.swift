import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat relationship intent")
struct GraphChatRelationshipIntentTests {
    @Test
    func typedDomainVersionAndPlanContractAreClosed()
        throws
    {
        let fixture = RelationshipIntentFixture()
        let plan = try fixture.plan()
        let intent = try fixture.intent(plan: plan)

        #expect(
            GraphChatTypedIntentDomainVersion.current
                == .v2
        )
        #expect(intent.version == .v2)
        #expect(intent.kind == .relationships)
        #expect(plan.graphScope == intent.scope.graphScope)
        #expect(plan.chatScope == intent.scope.chatScope)
        #expect(plan.queryScope == intent.scope.queryScope)
        #expect(plan.binding == intent.binding)
        #expect(plan.limits == intent.limits)
        #expect(
            plan.expectedCardinality
                == .zeroOrMore
        )

        #expect(
            throws:
                GraphChatTypedIntentValidationError
                    .unsupportedDomainVersion
        ) {
            try GraphChatTypedIntent(
                version: .v1,
                scope: intent.scope,
                responseLanguage:
                    intent.responseLanguage,
                binding: intent.binding,
                resolution:
                    intent.resolution,
                expectedCardinality:
                    .zeroOrMore,
                factExpectation: .none,
                limits: intent.limits,
                payload: .relationships(plan)
            )
        }

        let differentBinding =
            GraphChatTypedIntentBinding(
                requestID:
                    fixture.uuid(91),
                conversationID:
                    plan.binding
                        .conversationID,
                turnID:
                    fixture.uuid(91),
                sourceTurnID: nil,
                clarificationID: nil
            )
        #expect(
            throws:
                GraphChatTypedIntentValidationError
                    .invalidRelationshipPlan
        ) {
            try GraphChatTypedIntent(
                version: .v2,
                scope: intent.scope,
                responseLanguage:
                    intent.responseLanguage,
                binding: differentBinding,
                resolution:
                    intent.resolution,
                expectedCardinality:
                    .zeroOrMore,
                factExpectation: .none,
                limits: intent.limits,
                payload: .relationships(plan)
            )
        }
    }

    @Test
    func semanticDraftRejectsTechnicalManipulation()
        throws
    {
        let validator =
            GraphChatSemanticDraftValidator()
        let request =
            GraphChatIntentInterpreterRequest(
                normalizedQuestion:
                    "Womit ist Patient A verbunden?",
                responseLanguage: .german,
                schemaEntities: [],
                conversationDescriptions: [],
                scopeDescription: "Dieser Graph"
            )
        let valid =
            GraphChatUntrustedSemanticIntentDraft(
                family: .relationships,
                nodeTerms: ["Patient A"],
                relationshipDirection: .both,
                responseLanguage: .german
            )
        #expect(
            try validator.validate(
                valid,
                for: request
            ) == valid
        )

        for injected in [
            "0FBA0000-0000-0000-0000-000000000001",
            "N_42",
            "getNeighbors",
            "queryPlan",
        ] {
            #expect(
                throws:
                    GraphChatSemanticDraftValidationError
                        .technicalIdentifier
            ) {
                try validator.validate(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .relationships,
                        nodeTerms: [injected],
                        relationshipDirection:
                            .both,
                        responseLanguage:
                            .german
                    ),
                    for: request
                )
            }
        }

        #expect(
            throws:
                GraphChatSemanticDraftValidationError
                    .invalidCombination
        ) {
            try validator.validate(
                GraphChatUntrustedSemanticIntentDraft(
                    family: .relationships,
                    nodeTerms: [
                        "Patient A",
                        "Medikament 3",
                    ],
                    relationshipRequest:
                        .linkNotesBetweenNodes,
                    relationshipDirection:
                        .incoming,
                    relationshipNotePredicate:
                        .contains,
                    relationshipNoteTerm:
                        "täglich",
                    responseLanguage:
                        .german
                ),
                for: request
            )
        }
    }

    @Test
    func genericGermanAndEnglishFastPathsPreserveMeaning()
        throws
    {
        let compiler =
            GraphChatRelationshipFastPathCompiler()
        let german = try #require(
            compiler.compile(
                question:
                    "Welche Services zeigen auf Datenbank Nord?",
                language: .german
            )
        )
        #expect(german.family == .relationships)
        #expect(
            german.relationshipDirection
                == .incoming
        )
        #expect(
            german
                .relationshipCounterpartEntityTerm
                == "Services"
        )
        #expect(
            german.nodeTerms
                == ["Datenbank Nord"]
        )

        let germanContinuation = try #require(
            compiler.compile(
                question:
                    "Und nur die eingehenden?",
                language: .german
            )
        )
        #expect(
            germanContinuation
                .conversationReference
                == .currentSelection
        )
        #expect(
            germanContinuation
                .relationshipDirection
                == .incoming
        )

        let english = try #require(
            compiler.compile(
                question:
                    "What does the connection between Book North and Author Ada say?",
                language: .english
            )
        )
        #expect(
            english.relationshipRequest
                == .linkNotesBetweenNodes
        )
        #expect(
            english.nodeTerms
                == [
                    "Book North",
                    "Author Ada",
                ]
        )
        #expect(
            english.relationshipDirection
                == .both
        )

        let outgoing = try #require(
            compiler.compile(
                question:
                    "Show outgoing connections from Service Alpha.",
                language: .english
            )
        )
        #expect(
            outgoing.relationshipDirection
                == .outgoing
        )
        #expect(
            outgoing.nodeTerms
                == ["Service Alpha"]
        )
    }

    @Test
    func executorHandlesDirectionSelfLinksAndParallelLinks()
        async throws
    {
        let fixture = RelationshipIntentFixture()
        let executor =
            fixture.executor(
                neighborhood:
                    fixture.neighborhood()
            )

        let both = try await fixture.output(
            executor: executor,
            plan:
                fixture.plan(
                    direction: .both
                )
        )
        let incoming = try await fixture.output(
            executor: executor,
            plan:
                fixture.plan(
                    direction: .incoming
                )
        )
        let outgoing = try await fixture.output(
            executor: executor,
            plan:
                fixture.plan(
                    direction: .outgoing
                )
        )

        #expect(both.connections.count == 4)
        #expect(
            incoming.connections.map(\.direction)
                == [
                    .selfLink,
                    .incoming,
                ]
        )
        #expect(
            outgoing.connections.map(\.direction)
                == [
                    .outgoing,
                    .outgoing,
                    .selfLink,
                ]
        )
        #expect(
            both.connections.filter {
                $0.counterpart.nodeKey
                    == fixture.medicationNode.node
            }.count == 2
        )
        #expect(
            both.connections.filter {
                $0.direction == .selfLink
            }.count == 1
        )
        #expect(
            Set(both.connections.map(\.id))
                .count
                == both.connections.count
        )
    }

    @Test
    func equalCounterpartNamesUseStableIdentityOrdering()
        async throws
    {
        let fixture = RelationshipIntentFixture()
        let output =
            try await fixture.output(
                executor:
                    fixture.executor(
                        neighborhood:
                            fixture
                                .sameNameNeighborhood()
                    ),
                plan: fixture.plan()
            )

        #expect(
            output.connections.map {
                $0.counterpart.nodeKey.id
            } == [
                fixture.uuid(13),
                fixture.uuid(14),
            ]
        )
        #expect(
            output.connections.map {
                $0.counterpart.label
            } == [
                "Gleicher Name",
                "Gleicher Name",
            ]
        )
    }

    @Test
    func executorAppliesCounterpartAndNoteFiltersBeforeLimit()
        async throws
    {
        let fixture = RelationshipIntentFixture()
        let executor =
            fixture.executor(
                neighborhood:
                    fixture.neighborhood()
            )
        let medicationOnly =
            try await fixture.output(
                executor: executor,
                plan:
                    fixture.plan(
                        counterpartEntity:
                            fixture
                                .medicationEntity
                    )
            )
        #expect(
            medicationOnly.connections.count
                == 2
        )
        #expect(
            medicationOnly.connections
                .allSatisfy {
                    $0.counterpart
                        .ownerEntityID
                        == fixture
                            .medicationEntity.id
                }
        )

        let nodeOnly =
            try await fixture.output(
                executor: executor,
                plan:
                    fixture.plan(
                        counterpartEntity:
                            fixture
                                .medicationEntity,
                        counterpartNode:
                            fixture
                                .medicationNode
                    )
            )
        #expect(nodeOnly.connections.count == 2)

        let present =
            try await fixture.output(
                executor: executor,
                plan:
                    fixture.plan(
                        notePredicate:
                            .present
                    )
            )
        #expect(present.connections.count == 2)

        let missing =
            try await fixture.output(
                executor: executor,
                plan:
                    fixture.plan(
                        notePredicate:
                            .missing
                    )
            )
        #expect(missing.connections.count == 2)

        let matching =
            try await fixture.output(
                executor: executor,
                plan:
                    fixture.plan(
                        notePredicate:
                            .contains(
                                "TÄGLICH"
                            )
                    )
            )
        #expect(
            matching.connections
                .map(\.note)
                == ["3× täglich"]
        )

        let filteredBeforeLimit =
            try await fixture.output(
                executor: executor,
                plan:
                    fixture.plan(
                        direction: .incoming,
                        counterpartEntity:
                            fixture.serviceEntity,
                        resultLimit: 1
                    )
            )
        #expect(
            filteredBeforeLimit.connections
                .map {
                    $0.counterpart.nodeKey
                }
                == [fixture.serviceNode.node]
        )
        #expect(
            filteredBeforeLimit
                .resultWindow.totalCount == 1
        )
        #expect(
            filteredBeforeLimit
                .resultWindow.limitReached
                == false
        )

        let visiblyTruncated =
            try await fixture.output(
                executor: executor,
                plan:
                    fixture.plan(
                        resultLimit: 1
                    )
            )
        #expect(
            visiblyTruncated
                .resultWindow.totalCount == 4
        )
        #expect(
            visiblyTruncated
                .resultWindow.returnedCount == 1
        )
        #expect(
            visiblyTruncated
                .resultWindow.limitReached
        )
        #expect(
            visiblyTruncated
                .resultWindow.limitSources
                == [.tool]
        )
    }

    @Test
    func linkNoteReadsOnlyCurrentAuthoritativeValue()
        async throws
    {
        let fixture = RelationshipIntentFixture()
        let plan = try fixture.plan(
            request:
                .linkNotesBetweenNodes,
            counterpartEntity:
                fixture.medicationEntity,
            counterpartNode:
                fixture.medicationNode
        )

        let original =
            try await fixture.output(
                executor:
                    fixture.executor(
                        neighborhood:
                            fixture.neighborhood(
                                medicationNote:
                                    "3× täglich"
                            )
                    ),
                plan: plan
            )
        #expect(
            original.connections.map(\.note)
                == [
                    nil,
                    "3× täglich",
                ]
        )

        let emptied =
            try await fixture.output(
                executor:
                    fixture.executor(
                        neighborhood:
                            fixture.neighborhood(
                                medicationNote: ""
                            )
                    ),
                plan: plan
            )
        #expect(
            emptied.connections.map(\.note)
                == [
                    nil,
                    "",
                ]
        )

        let changed =
            try await fixture.output(
                executor:
                    fixture.executor(
                        neighborhood:
                            fixture.neighborhood(
                                medicationNote:
                                    "2× täglich"
                            )
                    ),
                plan: plan
            )
        #expect(
            changed.connections.map(\.note)
                == [
                    nil,
                    "2× täglich",
                ]
        )
        #expect(
            changed.connections
                .contains {
                    $0.note == "3× täglich"
                } == false
        )

        let deleted =
            try await fixture.output(
                executor:
                    fixture.executor(
                        neighborhood:
                            fixture.neighborhood(
                                medicationNote:
                                    nil
                            )
                    ),
                plan: plan
            )
        #expect(
            deleted.connections
                .allSatisfy {
                    $0.note == nil
                }
        )
    }

    @Test
    func artifactOrderingWindowAndPresentationStayInParity()
        async throws
    {
        let fixture = RelationshipIntentFixture()
        let plan = try fixture.plan()
        let output =
            try await fixture.output(
                executor:
                    fixture.executor(
                        neighborhood:
                            fixture.neighborhood()
                    ),
                plan: plan
            )
        let draft = try #require(
            GraphChatAnswerArtifactFactory
                .relationships(
                    output: output,
                    plan: plan
                )
        )
        guard case .relationship(let payload) =
                draft.payload else {
            Issue.record(
                "Expected a relationship artifact."
            )
            return
        }
        let medicationRows =
            payload.connections.filter {
                $0.counterpartNode
                    == fixture.medicationNode.node
            }
        #expect(
            medicationRows.map(
                \.parallelOrdinal
            ) == [1, 2]
        )
        #expect(
            medicationRows.map(
                \.parallelCount
            ) == [2, 2]
        )
        #expect(
            payload.resultWindow
                == output.resultWindow
        )
        #expect(
            payload.resultMetadata
                .returnedCount
                == payload.connections.count
        )
        let presentation =
            GraphChatRelationshipPresentation(
                payload: payload
            )
        #expect(
            presentation.rows.count
                == payload.connections.count
        )

        let artifact =
            GraphChatAnswerArtifact(
                id: GraphChatAnswerArtifactID(),
                sessionID:
                    GraphChatAnswerArtifactSessionID(),
                graphScope:
                    draft.graphScope,
                title: draft.title,
                payload: draft.payload,
                evidence: draft.evidence,
                navigationTargets:
                    draft.navigationTargets,
                querySummary:
                    draft.querySummary
            )
        #expect(
            GraphChatDeterministicAnswerFallbackRenderer()
                .render(
                    source:
                        GraphChatDeterministicAnswerFallbackSource(
                            kind: .neighbors,
                            completionStatus:
                                .succeeded,
                            evidence: [],
                            artifacts: [artifact]
                        ),
                    language: .german
                )
                == presentation.plainText
        )
        #expect(
            GraphChatAnswerArtifactRenderDescriptor
                .make(for: artifact)
                .component
                == .relationship
        )
        #expect(
            presentation.plainText
                .contains(
                    fixture.medicationNode
                        .node.id.uuidString
                ) == false
        )
        #expect(
            presentation.plainText
                .contains("N_") == false
        )
    }

    @Test
    func interpretationAndCorrectionExposeOnlyRelationshipSemantics()
        throws
    {
        let fixture = RelationshipIntentFixture()
        let plan = try fixture.plan(
            direction: .incoming,
            counterpartEntity:
                fixture.medicationEntity,
            notePredicate: .present
        )
        let intent = try fixture.intent(
            plan: plan
        )
        let interpretation = try #require(
            GraphChatIntentInterpretationBuilder(
                timeZone:
                    TimeZone(
                        identifier:
                            "Europe/Berlin"
                    )!
            )
            .executionInterpretation(
                intent: intent,
                witness:
                    .relationship(plan)
            )
        )
        let capabilities =
            GraphChatInterpretationCorrectionCapabilities
                .derive(from: interpretation)

        #expect(
            interpretation.relationship?
                .direction == .incoming
        )
        #expect(
            interpretation.relationship?
                .counterpartEntity?
                .id
                == fixture.medicationEntity.id
        )
        #expect(
            interpretation.relationship?
                .notePredicate == .present
        )
        #expect(
            capabilities.components
                == [
                    .relationshipDirection,
                    .relationshipCounterpartEntity,
                    .relationshipCounterpartNode,
                    .relationshipNotePredicate,
                ]
        )
        #expect(
            capabilities.components
                .contains(.entity) == false
        )
        #expect(
            capabilities.components
                .contains(.fields) == false
        )
    }

    @Test
    func executorRejectsCrossGraphAndChatScope()
        async throws
    {
        let fixture = RelationshipIntentFixture()
        let plan = try fixture.plan()
        let executor =
            fixture.executor(
                neighborhood:
                    fixture.neighborhood()
            )
        let foreignGraph =
            GraphScope(
                graphID:
                    fixture.uuid(99)
            )
        let budget =
            fixture.budget(
                for: plan
            )

        await #expect(
            throws: GraphChatToolError.self
        ) {
            try await executor.execute(
                plan,
                context:
                    GraphChatToolContext(
                        scope:
                            .node(
                                plan.centerNode
                                    .node,
                                in: foreignGraph
                            ),
                        budget: budget
                    )
            )
        }
    }
}

private struct RelationshipIntentFixture {
    let graphScope =
        GraphScope(
            graphID:
                UUID(
                    uuidString:
                        "7A000000-0000-0000-0000-000000000001"
                )!
        )

    var patientEntity:
        GraphChatTypedEntityIdentity
    {
        typedEntity(
            id: uuid(2),
            alias: "E1",
            name: "Patienten"
        )
    }

    var medicationEntity:
        GraphChatTypedEntityIdentity
    {
        typedEntity(
            id: uuid(3),
            alias: "E2",
            name: "Medikamente"
        )
    }

    var serviceEntity:
        GraphChatTypedEntityIdentity
    {
        typedEntity(
            id: uuid(4),
            alias: "E3",
            name: "Services"
        )
    }

    var centerNode: GraphChatTypedNodeIdentity {
        typedNode(
            id: uuid(10),
            name: "Patient A",
            owner: patientEntity.id
        )
    }

    var medicationNode:
        GraphChatTypedNodeIdentity
    {
        typedNode(
            id: uuid(11),
            name: "Medikament 3",
            owner:
                medicationEntity.id
        )
    }

    var serviceNode: GraphChatTypedNodeIdentity {
        typedNode(
            id: uuid(12),
            name: "Service Alpha",
            owner: serviceEntity.id
        )
    }

    var chatScope: GraphChatScope {
        .node(
            centerNode.node,
            in: graphScope
        )
    }

    func plan(
        request:
            GraphChatRelationshipRequestKind =
                .connections,
        direction:
            GraphChatRelationshipDirection =
                .both,
        counterpartEntity:
            GraphChatTypedEntityIdentity? = nil,
        counterpartNode:
            GraphChatTypedNodeIdentity? = nil,
        notePredicate:
            GraphChatRelationshipNotePredicate? =
                nil,
        resultLimit: Int = 20
    ) throws -> GraphChatRelationshipPlan {
        let requestID = uuid(70)
        let binding =
            GraphChatTypedIntentBinding(
                requestID: requestID,
                conversationID: uuid(71),
                turnID: requestID,
                sourceTurnID: nil,
                clarificationID: nil
            )
        return try GraphChatRelationshipPlan(
            graphScope: graphScope,
            chatScope: chatScope,
            queryScope:
                .node(
                    centerNode.node,
                    in: graphScope
                ),
            binding: binding,
            request: request,
            centerEntity: patientEntity,
            centerNode: centerNode,
            direction:
                request
                    == .linkNotesBetweenNodes
                ? .both
                : direction,
            counterpartEntity:
                counterpartEntity,
            counterpartNode:
                counterpartNode,
            notePredicate:
                notePredicate,
            limits:
                GraphChatTypedIntentLimits(
                    resultLimit: resultLimit,
                    maximumResultLimit: 30,
                    maximumEvidenceCount: 31,
                    maximumArtifactCount: 1
                ),
            responseLanguage: .german
        )
    }

    func intent(
        plan: GraphChatRelationshipPlan
    ) throws -> GraphChatTypedIntent {
        try GraphChatTypedIntent(
            version: .v2,
            scope:
                GraphChatTypedIntentScope(
                    graphScope:
                        plan.graphScope,
                    chatScope:
                        plan.chatScope,
                    queryScope:
                        plan.queryScope
                ),
            responseLanguage:
                plan.responseLanguage,
            binding: plan.binding,
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
            limits: plan.limits,
            payload: .relationships(plan)
        )
    }

    func neighborhood(
        medicationNote: String? =
            "3× täglich"
    ) -> GraphDirectNeighborhoodDTO {
        let center = summary(centerNode)
        let medication =
            summary(medicationNode)
        let service = summary(serviceNode)
        let firstParallel =
            link(
                id: uuid(30),
                createdAt: 1,
                source:
                    centerNode.node,
                sourceLabel:
                    centerNode.displayName,
                target:
                    medicationNode.node,
                targetLabel:
                    medicationNode.displayName,
                note: nil
            )
        let medicationLink =
            link(
                id: uuid(31),
                createdAt: 2,
                source:
                    centerNode.node,
                sourceLabel:
                    centerNode.displayName,
                target:
                    medicationNode.node,
                targetLabel:
                    medicationNode.displayName,
                note:
                    medicationNote
            )
        let serviceLink =
            link(
                id: uuid(32),
                createdAt: 3,
                source:
                    serviceNode.node,
                sourceLabel:
                    serviceNode.displayName,
                target:
                    centerNode.node,
                targetLabel:
                    centerNode.displayName,
                note: "liest"
            )
        let selfLink =
            link(
                id: uuid(33),
                createdAt: 0,
                source:
                    centerNode.node,
                sourceLabel:
                    centerNode.displayName,
                target:
                    centerNode.node,
                targetLabel:
                    centerNode.displayName,
                note: ""
            )
        return GraphDirectNeighborhoodDTO(
            scope: graphScope,
            center: center,
            outgoingLinks: [
                medicationLink,
                selfLink,
                firstParallel,
            ],
            incomingLinks: [
                serviceLink,
                selfLink,
            ],
            neighbors: [
                service,
                medication,
            ]
        )
    }

    func sameNameNeighborhood()
        -> GraphDirectNeighborhoodDTO
    {
        let first =
            typedNode(
                id: uuid(13),
                name: "Gleicher Name",
                owner: serviceEntity.id
            )
        let second =
            typedNode(
                id: uuid(14),
                name: "Gleicher Name",
                owner: serviceEntity.id
            )
        return GraphDirectNeighborhoodDTO(
            scope: graphScope,
            center: summary(centerNode),
            outgoingLinks: [
                link(
                    id: uuid(41),
                    createdAt: 2,
                    source:
                        centerNode.node,
                    sourceLabel:
                        centerNode.displayName,
                    target: second.node,
                    targetLabel:
                        second.displayName,
                    note: nil
                ),
                link(
                    id: uuid(40),
                    createdAt: 1,
                    source:
                        centerNode.node,
                    sourceLabel:
                        centerNode.displayName,
                    target: first.node,
                    targetLabel:
                        first.displayName,
                    note: nil
                ),
            ],
            incomingLinks: [],
            neighbors: [
                summary(second),
                summary(first),
            ]
        )
    }

    func executor(
        neighborhood:
            GraphDirectNeighborhoodDTO
    ) -> GraphChatRelationshipExecutor {
        GraphChatRelationshipExecutor(
            repository:
                RelationshipNeighborhoodReader(
                    neighborhood:
                        neighborhood
                ),
            evidenceValidator:
                RelationshipEvidenceValidator(),
            logger:
                NoOpGraphChatToolLogger()
        )
    }

    func output(
        executor: GraphChatRelationshipExecutor,
        plan: GraphChatRelationshipPlan
    ) async throws -> GraphChatRelationshipOutput {
        let result = try await executor.execute(
            plan,
            context:
                GraphChatToolContext(
                    scope: plan.queryScope,
                    budget:
                        budget(for: plan)
                )
        )
        return try #require(result.payload)
    }

    func budget(
        for plan: GraphChatRelationshipPlan
    ) -> GraphChatToolBudget {
        GraphChatToolBudget(
            policy:
                GraphChatToolBudgetPolicy(
                    maximumCalls: 1,
                    maximumResultCountPerTool:
                        plan.limits
                            .maximumResultLimit
                        + 1,
                    maximumEvidenceCount:
                        plan.limits
                            .maximumEvidenceCount
                )
        )
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString:
                String(
                    format:
                        "7A000000-0000-0000-0000-%012d",
                    suffix
                )
        )!
    }

    private func typedEntity(
        id: UUID,
        alias: String,
        name: String
    ) -> GraphChatTypedEntityIdentity {
        GraphChatTypedEntityIdentity(
            id: id,
            alias:
                GraphEntityAlias(alias),
            displayName: name
        )
    }

    private func typedNode(
        id: UUID,
        name: String,
        owner: UUID
    ) -> GraphChatTypedNodeIdentity {
        GraphChatTypedNodeIdentity(
            node:
                NodeRefKey(
                    kind: .attribute,
                    id: id
                ),
            displayName: name,
            ownerEntityID: owner
        )
    }

    private func summary(
        _ node:
            GraphChatTypedNodeIdentity
    ) -> GraphNodeSummaryDTO {
        GraphNodeSummaryDTO(
            scope: graphScope,
            nodeKey: node.node,
            label: node.displayName,
            notes: "",
            iconSymbolName: nil,
            ownerEntityID:
                node.ownerEntityID,
            ownerLabel: nil
        )
    }

    private func link(
        id: UUID,
        createdAt: TimeInterval,
        source: NodeRefKey,
        sourceLabel: String,
        target: NodeRefKey,
        targetLabel: String,
        note: String?
    ) -> GraphLinkDTO {
        GraphLinkDTO(
            id: id,
            scope: graphScope,
            createdAt:
                Date(
                    timeIntervalSince1970:
                        createdAt
                ),
            sourceKindRaw:
                source.kind.rawValue,
            sourceID: source.id,
            sourceLabel: sourceLabel,
            targetKindRaw:
                target.kind.rawValue,
            targetID: target.id,
            targetLabel: targetLabel,
            note: note
        )
    }
}

private actor RelationshipNeighborhoodReader:
    GraphChatNeighborhoodReading
{
    let neighborhood:
        GraphDirectNeighborhoodDTO

    init(
        neighborhood:
            GraphDirectNeighborhoodDTO
    ) {
        self.neighborhood = neighborhood
    }

    func directNeighborhood(
        of nodeKey: NodeRefKey,
        in scope: GraphScope
    ) async throws
        -> GraphDirectNeighborhoodDTO?
    {
        guard
            neighborhood.scope == scope,
            neighborhood.center.nodeKey
                == nodeKey
        else {
            return nil
        }
        return neighborhood
    }
}

private nonisolated struct
    RelationshipEvidenceValidator:
    GraphEvidenceValidating
{
    func validatedEvidence(
        _ evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> [GraphEvidence] {
        evidence.filter {
            $0.sourceReference.graphID
                == scope.graphScope.graphID
        }
    }
}
