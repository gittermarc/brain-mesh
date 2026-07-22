import Foundation
import Testing
@testable import BrainMesh

struct GraphChatConversationStateTests {
    @Test
    func initialStateIsEmptyValueOnlyAndGraphScoped() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )

        requireSendable(state)
        #expect(state.graphScope == graphScope)
        #expect(state.chatScope == chatScope)
        #expect(state.turnContexts.isEmpty)
        #expect(state.nodeReferences.isEmpty)
        #expect(state.entityReferences.isEmpty)
        #expect(state.fieldReferences.isEmpty)
        #expect(state.resultContexts.isEmpty)
        #expect(state.groupReferences.isEmpty)
        #expect(state.lastValidatedQueryPlan == nil)
        #expect(state.referenceTargets == .empty)
        #expect(state.lastResetReason == .newConversation)
    }

    @Test
    func validatedQueryBuildsEntityFieldAndOrdinalResultReferences() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let graphScope = context.graphScope
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let reducer = GraphChatConversationStateReducer()
        let field = try #require(context.aliases.field(for: GraphFieldAlias("F3")))
        let firstNode = NodeRefKey(
            kind: .attribute,
            id: UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
        )
        let secondNode = NodeRefKey(
            kind: .attribute,
            id: UUID(uuidString: "71000000-0000-0000-0000-000000000002")!
        )
        let firstEvidence = makeNodeEvidence(
            node: firstNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "first"
        )
        let secondEvidence = makeNodeEvidence(
            node: secondNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "second"
        )
        let firstCellEvidence = makeFieldEvidence(
            node: firstNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            fieldID: field.fieldID,
            suffix: "first-cell"
        )
        let secondCellEvidence = makeFieldEvidence(
            node: secondNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            fieldID: field.fieldID,
            suffix: "second-cell"
        )
        let plan = ValidatedGraphQueryPlan(
            version: 1,
            graphScope: graphScope,
            entityID: GraphChatTestSupport.projectEntityID,
            scope: .graph,
            filters: [],
            sorting: [],
            projection: [.nodeIdentity, .field(field.fieldID)],
            aggregation: nil,
            limit: 10
        )
        let result = GraphChatQueryResult(
            state: .success,
            rows: [
                queryRow(
                    node: firstNode,
                    label: "Project One",
                    nodeEvidence: firstEvidence,
                    cellEvidence: firstCellEvidence,
                    field: field,
                    value: .integer(3)
                ),
                queryRow(
                    node: secondNode,
                    label: "Project Two",
                    nodeEvidence: secondEvidence,
                    cellEvidence: secondCellEvidence,
                    field: field,
                    value: .integer(5)
                )
            ],
            aggregation: nil,
            appliedFilters: [],
            evidence: [firstEvidence, firstCellEvidence, secondEvidence, secondCellEvidence]
        )
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )

        let reduced = try reducer.reduce(
            initial,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .queryResolved(
                    plan: plan,
                    result: result,
                    schemaContext: context
                )
            )
        ).state

        #expect(reduced.lastValidatedQueryPlan == plan)
        #expect(reduced.entityReferences.contains { $0.entityID == plan.entityID })
        #expect(reduced.fieldReferences.contains { $0.fieldID == field.fieldID })
        #expect(reduced.nodeReferences.map(\.node) == [firstNode, secondNode])
        let resultContext = try #require(reduced.resultContexts.last)
        #expect(resultContext.references.map(\.ordinal) == [1, 2])
        #expect(resultContext.references.map(\.reference) == [.node(firstNode), .node(secondNode)])
        #expect(reduced.referenceTargets.ordinal == [.node(firstNode), .node(secondNode)])
    }

    @Test
    func validatedNodeToolBuildsNodeEntityAndFieldReferences() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.node(
            NodeRefKey(kind: .attribute, id: GraphChatTestSupport.projectAttributeID),
            in: graphScope
        )
        let reducer = GraphChatConversationStateReducer()
        let center = chatScope.nodeReferences[0]
        let fieldID = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
        let centerEvidence = makeNodeEvidence(
            node: center,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "center"
        )
        let fieldEvidence = makeFieldEvidence(
            node: center,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            fieldID: fieldID,
            suffix: "field"
        )
        let output = GetNodeOutput(
            node: center,
            label: "Project Alpha",
            notes: "",
            owner: GraphChatNodeOwner(
                entityID: GraphChatTestSupport.projectEntityID,
                label: "Projects"
            ),
            detailValues: [
                GraphChatNodeDetailValue(
                    valueID: UUID(),
                    fieldID: fieldID,
                    fieldName: "Effort",
                    fieldType: .numberInt,
                    unit: "h",
                    value: .integer(8),
                    evidenceID: fieldEvidence.id
                )
            ],
            links: [],
            attachments: [],
            evidenceIDs: [centerEvidence.id, fieldEvidence.id]
        )
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )

        let reduced = try reducer.reduce(
            initial,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .nodeResolved(
                    output: output,
                    state: .success,
                    evidence: [centerEvidence, fieldEvidence]
                )
            )
        ).state

        #expect(reduced.nodeReferences.map(\.node) == [center])
        #expect(reduced.entityReferences.contains {
            $0.entityID == GraphChatTestSupport.projectEntityID
        })
        #expect(reduced.fieldReferences.contains { reference in
            reference.fieldID == fieldID
                && reference.entityID == GraphChatTestSupport.projectEntityID
        })
        #expect(reduced.referenceTargets.singular == .node(center))
    }

    @Test
    func schemaResolutionInNodeScopeRetainsOnlyOwningEntityDefinitions() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let graphScope = context.graphScope
        let scopedNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let chatScope = GraphChatScope.node(scopedNode, in: graphScope)
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .graph,
                sourceID: graphScope.graphID
            ),
            summary: "Validated schema",
            identitySuffix: "schema"
        )
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )

        let state = try GraphChatConversationStateReducer().reduce(
            initial,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .schemaResolved(
                    schemaContext: context,
                    state: .success,
                    evidence: [evidence]
                )
            )
        ).state

        #expect(state.entityReferences.map(\.entityID) == [
            GraphChatTestSupport.projectEntityID
        ])
        #expect(state.fieldReferences.isEmpty == false)
        #expect(state.fieldReferences.allSatisfy {
            $0.entityID == GraphChatTestSupport.projectEntityID
        })
        #expect(state.resultContexts.last?.references.map(\.reference) == [
            .entity(GraphChatTestSupport.projectEntityID)
        ])
    }

    @Test
    func foreignGraphEventsAndIncompatiblePlansAreRejected() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.node(
            NodeRefKey(kind: .attribute, id: GraphChatTestSupport.projectAttributeID),
            in: graphScope
        )
        let state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        let reducer = GraphChatConversationStateReducer()
        let foreignScope = GraphScope(graphID: GraphChatTestSupport.otherGraphID)

        #expect(throws: GraphChatConversationStateError.graphScopeMismatch) {
            try reducer.reduce(
                state,
                event: GraphChatConversationTrustedEvent(
                    graphScope: foreignScope,
                    chatScope: .entireGraph(foreignScope),
                    payload: .validatedEvidence(
                        tool: .searchGraph,
                        state: .success,
                        evidence: []
                    )
                )
            )
        }

        let context = GraphChatTestSupport.makeSchemaContext()
        let broadPlan = ValidatedGraphQueryPlan(
            version: 1,
            graphScope: graphScope,
            entityID: GraphChatTestSupport.projectEntityID,
            scope: .graph,
            filters: [],
            sorting: [],
            projection: [.nodeIdentity],
            aggregation: nil,
            limit: 10
        )
        #expect(throws: GraphChatConversationStateError.chatScopeMismatch) {
            try reducer.reduce(
                state,
                event: GraphChatConversationTrustedEvent(
                    graphScope: graphScope,
                    chatScope: chatScope,
                    payload: .queryResolved(
                        plan: broadPlan,
                        result: GraphChatQueryResult(
                            state: .noEvidence,
                            rows: [],
                            aggregation: nil,
                            appliedFilters: [],
                            evidence: []
                        ),
                        schemaContext: context
                    )
                )
            )
        }
    }

    @Test
    func graphForeignEvidenceIsRejectedEvenWhenEventScopeMatches() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let foreignEvidence = GraphChatProviderTestSupport.makeEvidence(
            graphID: GraphChatTestSupport.otherGraphID,
            sourceID: UUID(),
            summary: "Foreign graph"
        )
        let state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )

        #expect(throws: GraphChatConversationStateError.evidenceGraphMismatch) {
            try GraphChatConversationStateReducer().reduce(
                state,
                event: GraphChatConversationTrustedEvent(
                    graphScope: graphScope,
                    chatScope: chatScope,
                    payload: .validatedEvidence(
                        tool: .searchGraph,
                        state: .success,
                        evidence: [foreignEvidence]
                    )
                )
            )
        }
    }

    @Test
    func missingRevalidatedEvidenceDoesNotEnterResultReferences() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let graphScope = context.graphScope
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let node = NodeRefKey(kind: .attribute, id: UUID())
        let unvalidatedEvidence = makeNodeEvidence(
            node: node,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "deleted"
        )
        let plan = ValidatedGraphQueryPlan(
            version: 1,
            graphScope: graphScope,
            entityID: GraphChatTestSupport.projectEntityID,
            scope: .graph,
            filters: [],
            sorting: [],
            projection: [.nodeIdentity],
            aggregation: nil,
            limit: 10
        )
        let result = GraphChatQueryResult(
            state: .noEvidence,
            rows: [
                GraphChatQueryResultRow(
                    node: node,
                    label: "Deleted node",
                    cells: [],
                    evidenceIDs: [unvalidatedEvidence.id]
                )
            ],
            aggregation: nil,
            appliedFilters: [],
            evidence: []
        )
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )

        let reduced = try GraphChatConversationStateReducer().reduce(
            initial,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .queryResolved(
                    plan: plan,
                    result: result,
                    schemaContext: context
                )
            )
        ).state

        #expect(reduced.nodeReferences.isEmpty)
        #expect(reduced.resultContexts.last?.references.isEmpty == true)
        #expect(reduced.resultContexts.last?.evidenceIDs.isEmpty == true)
    }

    @Test
    func comparisonEventKeepsOnlyPreviouslyValidatedNodeReferences() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let reducer = GraphChatConversationStateReducer()
        let firstNode = NodeRefKey(kind: .attribute, id: UUID())
        let secondNode = NodeRefKey(kind: .attribute, id: UUID())
        let unknownNode = NodeRefKey(kind: .attribute, id: UUID())
        let evidence = [firstNode, secondNode].enumerated().map { index, node in
            makeNodeEvidence(
                node: node,
                ownerEntityID: GraphChatTestSupport.projectEntityID,
                suffix: "comparison-\(index)"
            )
        }
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state = try reducer.reduce(
            state,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .validatedEvidence(
                    tool: .searchGraph,
                    state: .success,
                    evidence: evidence
                )
            )
        ).state

        state = try reducer.reduce(
            state,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .comparisonResolved(
                    references: [
                        .node(firstNode),
                        .node(unknownNode),
                        .node(secondNode)
                    ],
                    technicalDescription: "Validated node comparison"
                )
            )
        ).state

        #expect(state.lastComparison?.references == [
            .node(firstNode),
            .node(secondNode)
        ])
        #expect(state.referenceTargets.compared == [
            .node(firstNode),
            .node(secondNode)
        ])
    }

    @Test
    func validatedAggregationBuildsOrderedGroupsAndComparisonTargets() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let graphScope = context.graphScope
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let field = try #require(context.aliases.field(for: GraphFieldAlias("F7")))
        let firstNode = NodeRefKey(kind: .attribute, id: UUID())
        let secondNode = NodeRefKey(kind: .attribute, id: UUID())
        let firstEvidence = makeNodeEvidence(
            node: firstNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "open"
        )
        let secondEvidence = makeNodeEvidence(
            node: secondNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "closed"
        )
        let plan = ValidatedGraphQueryPlan(
            version: 1,
            graphScope: graphScope,
            entityID: GraphChatTestSupport.projectEntityID,
            scope: .graph,
            filters: [],
            sorting: [],
            projection: [.nodeIdentity],
            aggregation: .groupCount(field.fieldID),
            limit: 10
        )
        let result = GraphChatQueryResult(
            state: .success,
            rows: [],
            aggregation: GraphChatAggregationResult(
                kind: .groupCount,
                fieldID: field.fieldID,
                fieldName: field.name,
                count: 2,
                groups: [
                    GraphChatGroupCount(
                        value: .choice("Open"),
                        count: 1,
                        evidenceIDs: [firstEvidence.id]
                    ),
                    GraphChatGroupCount(
                        value: .choice("Closed"),
                        count: 1,
                        evidenceIDs: [secondEvidence.id]
                    )
                ],
                value: nil,
                evidenceIDs: [firstEvidence.id, secondEvidence.id]
            ),
            appliedFilters: [],
            evidence: [firstEvidence, secondEvidence]
        )
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )

        let state = try GraphChatConversationStateReducer().reduce(
            initial,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .queryResolved(
                    plan: plan,
                    result: result,
                    schemaContext: context
                )
            )
        ).state

        #expect(state.groupReferences.map(\.valueDescription) == ["Open", "Closed"])
        #expect(state.groupReferences.map(\.memberNodes) == [[firstNode], [secondNode]])
        let comparison = try #require(state.lastComparison)
        let expectedReferences = state.groupReferences.map {
            GraphChatConversationReference.group($0.id)
        }
        #expect(comparison.references == expectedReferences)
        #expect(state.referenceTargets.compared == comparison.references)
    }

    @Test
    func groupBudgetRetainsDeterministicOrderedSubset() throws {
        let policy = GraphChatConversationStatePolicy(
            maximumTurnContexts: 2,
            maximumNodeReferences: 4,
            maximumEntityReferences: 2,
            maximumFieldReferences: 2,
            maximumResultContexts: 2,
            maximumResultReferences: 4,
            maximumGroupReferences: 2,
            maximumComparisonReferences: 2,
            maximumEvidenceIDsPerReference: 2,
            maximumTechnicalDescriptionLength: 80,
            maximumLabelLength: 40
        )
        let context = GraphChatTestSupport.makeSchemaContext()
        let graphScope = context.graphScope
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let field = try #require(context.aliases.field(for: GraphFieldAlias("F7")))
        let groupValues = ["First", "Second", "Third"]
        let evidence = groupValues.enumerated().map { index, value in
            makeNodeEvidence(
                node: NodeRefKey(kind: .attribute, id: UUID()),
                ownerEntityID: GraphChatTestSupport.projectEntityID,
                suffix: "group-\(index)-\(value)"
            )
        }
        let result = GraphChatQueryResult(
            state: .success,
            rows: [],
            aggregation: GraphChatAggregationResult(
                kind: .groupCount,
                fieldID: field.fieldID,
                fieldName: field.name,
                count: evidence.count,
                groups: zip(groupValues, evidence).map { value, item in
                    GraphChatGroupCount(
                        value: .choice(value),
                        count: 1,
                        evidenceIDs: [item.id]
                    )
                },
                value: nil,
                evidenceIDs: evidence.map(\.id)
            ),
            appliedFilters: [],
            evidence: evidence
        )
        let plan = ValidatedGraphQueryPlan(
            version: 1,
            graphScope: graphScope,
            entityID: GraphChatTestSupport.projectEntityID,
            scope: .graph,
            filters: [],
            sorting: [],
            projection: [.nodeIdentity],
            aggregation: .groupCount(field.fieldID),
            limit: 10
        )
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )

        let state = try GraphChatConversationStateReducer(policy: policy).reduce(
            initial,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .queryResolved(
                    plan: plan,
                    result: result,
                    schemaContext: context
                )
            )
        ).state

        #expect(state.groupReferences.map(\.valueDescription) == ["First", "Second"])
        #expect(state.resultContexts.last?.groupReferences.map(\.valueDescription) == [
            "First",
            "Second"
        ])
        #expect(state.lastComparison?.references == state.groupReferences.map {
            GraphChatConversationReference.group($0.id)
        })
        #expect(state.budgetEvictionCount > 0)
    }

    @Test
    func budgetsEvictOldReferencesDeterministically() throws {
        let policy = GraphChatConversationStatePolicy(
            maximumTurnContexts: 2,
            maximumNodeReferences: 2,
            maximumEntityReferences: 2,
            maximumFieldReferences: 2,
            maximumResultContexts: 2,
            maximumResultReferences: 2,
            maximumGroupReferences: 2,
            maximumComparisonReferences: 2,
            maximumEvidenceIDsPerReference: 2,
            maximumTechnicalDescriptionLength: 40,
            maximumLabelLength: 20
        )
        let reducer = GraphChatConversationStateReducer(policy: policy)
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        let nodes = (1...3).map { index in
            NodeRefKey(
                kind: .entity,
                id: UUID(
                    uuidString: String(
                        format: "72000000-0000-0000-0000-%012d",
                        index
                    )
                )!
            )
        }

        for (index, node) in nodes.enumerated() {
            let evidence = makeNodeEvidence(
                node: node,
                ownerEntityID: node.id,
                suffix: "budget-\(index)"
            )
            state = try reducer.reduce(
                state,
                event: GraphChatConversationTrustedEvent(
                    graphScope: graphScope,
                    chatScope: chatScope,
                    payload: .validatedEvidence(
                        tool: .searchGraph,
                        state: .success,
                        evidence: [evidence]
                    )
                )
            ).state
        }

        let turnIDs = (1...3).map { index in
            UUID(
                uuidString: String(
                    format: "73000000-0000-0000-0000-%012d",
                    index
                )
            )!
        }
        for turnID in turnIDs {
            state = try reducer.reduce(
                state,
                event: GraphChatConversationTrustedEvent(
                    graphScope: graphScope,
                    chatScope: chatScope,
                    payload: .turnCompleted(
                        GraphChatConversationTurnCompletion(
                            requestID: turnID,
                            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
                            toolKinds: [.searchGraph],
                            resultContextIDs: state.resultContexts.map(\.id),
                            evidenceIDs: []
                        )
                    )
                )
            ).state
        }

        #expect(state.nodeReferences.map(\.node) == Array(nodes.suffix(2)))
        #expect(state.resultContexts.count == 2)
        #expect(state.turnContexts.map(\.id) == Array(turnIDs.suffix(2)))
        #expect(state.turnContexts.allSatisfy {
            $0.technicalDescription.count <= policy.maximumTechnicalDescriptionLength
        })
        #expect(state.nodeReferences.allSatisfy {
            $0.label.count <= policy.maximumLabelLength
        })
        #expect(state.budgetEvictionCount > 0)
    }

    @Test
    func scopeAndGraphTransitionsDoNotLeakIncompatibleReferences() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let graphChatScope = GraphChatScope.entireGraph(graphScope)
        let reducer = GraphChatConversationStateReducer()
        let projectNode = NodeRefKey(kind: .attribute, id: GraphChatTestSupport.projectAttributeID)
        let personNode = NodeRefKey(kind: .attribute, id: GraphChatTestSupport.personAttributeID)
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: graphChatScope
        )

        for (node, owner, suffix) in [
            (projectNode, GraphChatTestSupport.projectEntityID, "project"),
            (personNode, GraphChatTestSupport.personEntityID, "person")
        ] {
            let evidence = makeNodeEvidence(
                node: node,
                ownerEntityID: owner,
                suffix: suffix
            )
            state = try reducer.reduce(
                state,
                event: GraphChatConversationTrustedEvent(
                    graphScope: graphScope,
                    chatScope: graphChatScope,
                    payload: .validatedEvidence(
                        tool: .searchGraph,
                        state: .success,
                        evidence: [evidence]
                    )
                )
            ).state
        }
        state.lastValidatedQueryPlan = ValidatedGraphQueryPlan(
            version: 1,
            graphScope: graphScope,
            entityID: GraphChatTestSupport.projectEntityID,
            scope: .node(projectNode),
            filters: [],
            sorting: [],
            projection: [.nodeIdentity],
            aggregation: nil,
            limit: 10
        )

        let nodeTransition = reducer.transition(
            state,
            to: .node(projectNode, in: graphScope)
        ).state
        #expect(nodeTransition.nodeReferences.map(\.node) == [projectNode])
        #expect(nodeTransition.entityReferences.allSatisfy {
            $0.entityID == GraphChatTestSupport.projectEntityID
        })
        #expect(nodeTransition.lastValidatedQueryPlan == nil)
        #expect(nodeTransition.resultContexts.isEmpty)
        #expect(nodeTransition.referenceTargets == .empty)

        let otherScope = GraphScope(graphID: GraphChatTestSupport.otherGraphID)
        let graphTransition = reducer.transition(
            nodeTransition,
            to: .entireGraph(otherScope)
        ).state
        #expect(graphTransition.graphScope == otherScope)
        #expect(graphTransition.conversationID != state.conversationID)
        #expect(graphTransition.nodeReferences.isEmpty)
        #expect(graphTransition.entityReferences.isEmpty)
        #expect(graphTransition.lastResetReason == .graphChanged)
    }

    @Test
    func detailFieldContextRemovesIncompatibleConversationReferences() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let entityScope = GraphChatScope.entity(
            GraphChatTestSupport.projectEntityID,
            in: graphScope
        )
        let retainedFieldID = UUID(uuidString: "40000000-0000-0000-0000-000000000101")!
        let discardedFieldID = UUID(uuidString: "40000000-0000-0000-0000-000000000102")!
        let node = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let reducer = GraphChatConversationStateReducer()
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: entityScope
        )

        let nodeEvidence = makeNodeEvidence(
            node: node,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "project-node"
        )
        let retainedFieldEvidence = makeFieldEvidence(
            node: node,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            fieldID: retainedFieldID,
            suffix: "retained-field"
        )
        let discardedFieldEvidence = makeFieldEvidence(
            node: node,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            fieldID: discardedFieldID,
            suffix: "discarded-field"
        )
        let output = GetNodeOutput(
            node: node,
            label: "Project Alpha",
            notes: "",
            owner: GraphChatNodeOwner(
                entityID: GraphChatTestSupport.projectEntityID,
                label: "Projects"
            ),
            detailValues: [
                GraphChatNodeDetailValue(
                    valueID: UUID(),
                    fieldID: retainedFieldID,
                    fieldName: "Status",
                    fieldType: .singleChoice,
                    unit: nil,
                    value: .choice("Active"),
                    evidenceID: retainedFieldEvidence.id
                ),
                GraphChatNodeDetailValue(
                    valueID: UUID(),
                    fieldID: discardedFieldID,
                    fieldName: "Effort",
                    fieldType: .numberInt,
                    unit: "h",
                    value: .integer(8),
                    evidenceID: discardedFieldEvidence.id
                )
            ],
            links: [],
            attachments: [],
            evidenceIDs: [
                nodeEvidence.id,
                retainedFieldEvidence.id,
                discardedFieldEvidence.id
            ]
        )
        state = try reducer.reduce(
            state,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: entityScope,
                payload: .nodeResolved(
                    output: output,
                    state: .success,
                    evidence: [
                        nodeEvidence,
                        retainedFieldEvidence,
                        discardedFieldEvidence
                    ]
                )
            )
        ).state

        #expect(Set(state.fieldReferences.map(\.fieldID)) == [retainedFieldID, discardedFieldID])

        let fieldScope = GraphChatScope.detailField(
            retainedFieldID,
            entityID: GraphChatTestSupport.projectEntityID,
            in: graphScope
        )
        let transitioned = reducer.transition(state, to: fieldScope).state

        #expect(transitioned.chatScope == fieldScope)
        #expect(transitioned.nodeReferences.isEmpty)
        #expect(transitioned.entityReferences.allSatisfy {
            $0.entityID == GraphChatTestSupport.projectEntityID
        })
        #expect(transitioned.fieldReferences.map(\.fieldID) == [retainedFieldID])
        #expect(transitioned.resultContexts.isEmpty)
        #expect(transitioned.referenceTargets == .empty)
        #expect(transitioned.lastResetReason == .scopeChanged)
    }

    private func requireSendable<T: Sendable>(_ value: T) {
        _ = value
    }

    private func queryRow(
        node: NodeRefKey,
        label: String,
        nodeEvidence: GraphEvidence,
        cellEvidence: GraphEvidence,
        field: GraphSchemaFieldResolution,
        value: GraphChatQueryCellValue
    ) -> GraphChatQueryResultRow {
        GraphChatQueryResultRow(
            node: node,
            label: label,
            cells: [
                GraphChatQueryCell(
                    fieldID: field.fieldID,
                    fieldName: field.name,
                    unit: field.unit,
                    value: value,
                    evidenceID: cellEvidence.id
                )
            ],
            evidenceIDs: [nodeEvidence.id, cellEvidence.id]
        )
    }

    private func makeNodeEvidence(
        node: NodeRefKey,
        ownerEntityID: UUID,
        suffix: String
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: GraphChatTestSupport.graphID,
                sourceKind: node.kind == .entity ? .entity : .attribute,
                sourceID: node.id,
                node: GraphSourceNodeReference(kind: node.kind, id: node.id),
                owner: GraphSourceNodeReference(
                    kind: .entity,
                    id: ownerEntityID
                )
            ),
            summary: suffix,
            navigationTitle: suffix,
            identitySuffix: suffix
        )
    }

    private func makeFieldEvidence(
        node: NodeRefKey,
        ownerEntityID: UUID,
        fieldID: UUID,
        suffix: String
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: GraphChatTestSupport.graphID,
                sourceKind: .detailValue,
                sourceID: UUID(),
                node: GraphSourceNodeReference(kind: node.kind, id: node.id),
                owner: GraphSourceNodeReference(
                    kind: .entity,
                    id: ownerEntityID
                ),
                fieldID: fieldID
            ),
            summary: suffix,
            navigationTitle: suffix,
            identitySuffix: suffix
        )
    }
}
