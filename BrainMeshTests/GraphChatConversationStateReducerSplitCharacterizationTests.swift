import Foundation
import Testing
@testable import BrainMesh

struct GraphChatConversationStateReducerSplitCharacterizationTests {
    @Test
    func searchPayloadKeepsOnlyReferencesBackedByValidatedEvidence() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let reducer = GraphChatConversationStateReducer()
        let validNode = NodeRefKey(
            kind: .attribute,
            id: UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
        )
        let unvalidatedNode = NodeRefKey(
            kind: .attribute,
            id: UUID(uuidString: "81000000-0000-0000-0000-000000000002")!
        )
        let validEvidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: validNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "search-valid"
        )
        let unvalidatedEvidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: unvalidatedNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "search-unvalidated"
        )
        let output = SearchGraphOutput(
            query: "project",
            hits: [
                makeSearchHit(
                    node: validNode,
                    ownerEntityID: GraphChatTestSupport.projectEntityID,
                    title: "Validated Project",
                    evidenceID: validEvidence.id
                ),
                makeSearchHit(
                    node: unvalidatedNode,
                    ownerEntityID: GraphChatTestSupport.projectEntityID,
                    title: "Unvalidated Project",
                    evidenceID: unvalidatedEvidence.id
                ),
            ]
        )
        let eventID = UUID(uuidString: "81000000-0000-0000-0000-000000000010")!
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: UUID(uuidString: "81000000-0000-0000-0000-000000000011")!
        )

        let reduced = try reducer.reduce(
            initial,
            event: GraphChatConversationTrustedEvent(
                id: eventID,
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .searchResolved(
                    output: output,
                    state: .success,
                    evidence: [validEvidence]
                )
            )
        ).state

        #expect(reduced.nodeReferences.map(\.node) == [validNode])
        #expect(reduced.resultContexts.map(\.id) == [eventID])
        #expect(reduced.resultContexts[0].references.map(\.reference) == [.node(validNode)])
        #expect(reduced.resultContexts[0].evidenceIDs == [validEvidence.id])
        #expect(reduced.referenceTargets.ordinal == [.node(validNode)])
    }

    @Test
    func neighborsPayloadHonorsTrustedGraphAndChatScopeBoundaries() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let centerNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let chatScope = GraphChatScope.node(centerNode, in: graphScope)
        let reducer = GraphChatConversationStateReducer()
        let validNeighbor = NodeRefKey(
            kind: .attribute,
            id: UUID(uuidString: "82000000-0000-0000-0000-000000000001")!
        )
        let unvalidatedNeighbor = NodeRefKey(
            kind: .attribute,
            id: UUID(uuidString: "82000000-0000-0000-0000-000000000002")!
        )
        let centerEvidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: centerNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "neighbors-center"
        )
        let validConnectionEvidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: validNeighbor,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "neighbors-valid"
        )
        let unvalidatedConnectionEvidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: unvalidatedNeighbor,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "neighbors-unvalidated"
        )
        let output = GetNeighborsOutput(
            center: GraphNodeSummaryDTO(
                scope: graphScope,
                nodeKey: centerNode,
                label: "Center",
                notes: "",
                iconSymbolName: nil,
                ownerEntityID: GraphChatTestSupport.projectEntityID,
                ownerLabel: "Projects"
            ),
            connections: [
                GraphChatNeighborConnection(
                    id: UUID(uuidString: "82000000-0000-0000-0000-000000000011")!,
                    direction: .outgoing,
                    neighbor: validNeighbor,
                    neighborLabel: "Validated Neighbor",
                    note: nil,
                    evidenceID: validConnectionEvidence.id
                ),
                GraphChatNeighborConnection(
                    id: UUID(uuidString: "82000000-0000-0000-0000-000000000012")!,
                    direction: .incoming,
                    neighbor: unvalidatedNeighbor,
                    neighborLabel: "Unvalidated Neighbor",
                    note: nil,
                    evidenceID: unvalidatedConnectionEvidence.id
                ),
            ],
            evidenceIDs: [centerEvidence.id, validConnectionEvidence.id]
        )
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: UUID(uuidString: "82000000-0000-0000-0000-000000000020")!
        )
        let validEvent = GraphChatConversationTrustedEvent(
            id: UUID(uuidString: "82000000-0000-0000-0000-000000000021")!,
            graphScope: graphScope,
            chatScope: chatScope,
            payload: .neighborsResolved(
                output: output,
                state: .success,
                evidence: [centerEvidence, validConnectionEvidence]
            )
        )

        let reduced = try reducer.reduce(initial, event: validEvent).state

        #expect(reduced.nodeReferences.map(\.node) == [centerNode, validNeighbor])
        #expect(reduced.resultContexts[0].references.map(\.reference) == [
            .node(centerNode),
            .node(validNeighbor),
        ])

        let mismatchedScope = GraphChatScope.entireGraph(graphScope)
        #expect(throws: GraphChatConversationStateError.chatScopeMismatch) {
            try reducer.reduce(
                initial,
                event: GraphChatConversationTrustedEvent(
                    graphScope: graphScope,
                    chatScope: mismatchedScope,
                    payload: validEvent.payload
                )
            )
        }

        let foreignGraphID = UUID(uuidString: "82000000-0000-0000-0000-000000000099")!
        let foreignEvidence = makeNodeEvidence(
            graphID: foreignGraphID,
            node: centerNode,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "neighbors-foreign"
        )
        #expect(throws: GraphChatConversationStateError.evidenceGraphMismatch) {
            try reducer.reduce(
                initial,
                event: GraphChatConversationTrustedEvent(
                    graphScope: graphScope,
                    chatScope: chatScope,
                    payload: .neighborsResolved(
                        output: output,
                        state: .success,
                        evidence: [foreignEvidence]
                    )
                )
            )
        }
    }

    @Test
    func statsPayloadProducesDeterministicResultContext() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let reducer = GraphChatConversationStateReducer()
        let firstHub = NodeRefKey(
            kind: .entity,
            id: UUID(uuidString: "83000000-0000-0000-0000-000000000001")!
        )
        let secondHub = NodeRefKey(
            kind: .entity,
            id: UUID(uuidString: "83000000-0000-0000-0000-000000000002")!
        )
        let graphEvidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .graph,
                sourceID: graphScope.graphID
            ),
            summary: "stats",
            identitySuffix: "stats-graph"
        )
        let firstEvidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: firstHub,
            ownerEntityID: firstHub.id,
            suffix: "stats-first"
        )
        let secondEvidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: secondHub,
            ownerEntityID: secondHub.id,
            suffix: "stats-second"
        )
        let output = GraphStatsOutput(
            counts: GraphChatStatsCounts(
                entities: 2,
                attributes: 0,
                links: 1,
                notes: 0,
                attachments: 0,
                images: 0,
                attachmentBytes: 0
            ),
            nodeCount: 2,
            linkCount: 1,
            isolatedNodeCount: 0,
            hubs: [
                GraphChatStatsHub(
                    node: firstHub,
                    label: "First Hub",
                    degree: 2,
                    evidenceID: firstEvidence.id
                ),
                GraphChatStatsHub(
                    node: secondHub,
                    label: "Second Hub",
                    degree: 1,
                    evidenceID: secondEvidence.id
                ),
            ],
            healthScore: 100,
            healthIssueCount: 0,
            evidenceIDs: [graphEvidence.id, firstEvidence.id, secondEvidence.id]
        )
        let event = GraphChatConversationTrustedEvent(
            id: UUID(uuidString: "83000000-0000-0000-0000-000000000010")!,
            graphScope: graphScope,
            chatScope: chatScope,
            payload: .statsResolved(
                output: output,
                state: .success,
                evidence: [graphEvidence, firstEvidence, secondEvidence]
            )
        )
        let initial = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: UUID(uuidString: "83000000-0000-0000-0000-000000000011")!
        )

        let firstReduction = try reducer.reduce(initial, event: event)
        let secondReduction = try reducer.reduce(initial, event: event)

        #expect(firstReduction.state == secondReduction.state)
        #expect(firstReduction.evictedItemCount == secondReduction.evictedItemCount)
        #expect(firstReduction.state.resultContexts.count == 1)
        #expect(firstReduction.state.resultContexts[0].references.map(\.reference) == [
            .node(firstHub),
            .node(secondHub),
        ])
        #expect(firstReduction.state.resultContexts[0].technicalDescription
            == "Graph-Statistik mit 2 revalidierten Hubs")
    }

    @Test
    func clarificationRequestedAndResolvedChangeOnlyPendingClarification() throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let reducer = GraphChatConversationStateReducer()
        let base = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: UUID(uuidString: "84000000-0000-0000-0000-000000000001")!
        )
        let clarification = GraphChatPendingClarification(
            id: UUID(uuidString: "84000000-0000-0000-0000-000000000002")!,
            decision: .conversationReference,
            options: [
                GraphChatPendingClarificationOption(
                    id: "latest",
                    title: "Latest results",
                    proposal: .latestResults
                )
            ],
            sourceTurnID: nil,
            graphScope: graphScope,
            chatScope: chatScope,
            continuationOperation: .answerAboutReference,
            continuationQuestion: "Which result?",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_000_300)
        )

        let requested = try reducer.reduce(
            base,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .clarificationRequested(clarification)
            )
        ).state

        var expectedRequested = base
        expectedRequested.pendingClarification = requested.pendingClarification
        #expect(requested == expectedRequested)

        let resolved = try reducer.reduce(
            requested,
            event: GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .clarificationResolved
            )
        ).state

        #expect(resolved == base)
    }

    @Test
    func transactionFinalizationReferencesOnlyAppliedResultContextsAndProvidedEvidence() async throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let base = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: UUID(uuidString: "85000000-0000-0000-0000-000000000001")!
        )
        let transaction = GraphChatConversationStateTransaction(
            baseState: base,
            reducer: GraphChatConversationStateReducer()
        )
        let node = NodeRefKey(
            kind: .attribute,
            id: UUID(uuidString: "85000000-0000-0000-0000-000000000002")!
        )
        let evidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: node,
            ownerEntityID: GraphChatTestSupport.projectEntityID,
            suffix: "transaction"
        )
        let resultContextID = UUID(uuidString: "85000000-0000-0000-0000-000000000003")!
        let searchEvent = GraphChatConversationTrustedEvent(
            id: resultContextID,
            graphScope: graphScope,
            chatScope: chatScope,
            payload: .searchResolved(
                output: SearchGraphOutput(
                    query: "transaction",
                    hits: [
                        makeSearchHit(
                            node: node,
                            ownerEntityID: GraphChatTestSupport.projectEntityID,
                            title: "Transaction Result",
                            evidenceID: evidence.id
                        )
                    ]
                ),
                state: .success,
                evidence: [evidence]
            )
        )

        try await transaction.apply(searchEvent)
        let requestID = UUID(uuidString: "85000000-0000-0000-0000-000000000004")!
        let finalized = try await transaction.finalizedState(
            requestID: requestID,
            completedAt: Date(timeIntervalSince1970: 1_700_000_100),
            validatedEvidenceIDs: [evidence.id]
        )

        let turn = try #require(finalized.turnContexts.last)
        #expect(turn.id == requestID)
        #expect(turn.toolKinds == [.searchGraph])
        #expect(turn.resultContextIDs == [resultContextID])
        #expect(turn.evidenceIDs == [evidence.id])
    }

    @Test
    func transactionResetRestoresExactBaseSnapshot() async throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let base = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: UUID(uuidString: "86000000-0000-0000-0000-000000000001")!
        )
        let transaction = GraphChatConversationStateTransaction(
            baseState: base,
            reducer: GraphChatConversationStateReducer()
        )
        let node = NodeRefKey(
            kind: .entity,
            id: UUID(uuidString: "86000000-0000-0000-0000-000000000002")!
        )
        let evidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: node,
            ownerEntityID: node.id,
            suffix: "reset"
        )

        try await transaction.apply(
            GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .validatedEvidence(
                    tool: .getNode,
                    state: .success,
                    evidence: [evidence]
                )
            )
        )
        #expect(await transaction.snapshot() != base)

        await transaction.resetToBase()

        #expect(await transaction.snapshot() == base)
        #expect(await transaction.baseSnapshot() == base)
    }

    @Test
    func failedTransactionEventLeavesCandidateStateUntouched() async throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let base = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: UUID(uuidString: "87000000-0000-0000-0000-000000000001")!
        )
        let transaction = GraphChatConversationStateTransaction(
            baseState: base,
            reducer: GraphChatConversationStateReducer()
        )
        let node = NodeRefKey(
            kind: .entity,
            id: UUID(uuidString: "87000000-0000-0000-0000-000000000002")!
        )
        let evidence = makeNodeEvidence(
            graphID: graphScope.graphID,
            node: node,
            ownerEntityID: node.id,
            suffix: "atomic"
        )
        try await transaction.apply(
            GraphChatConversationTrustedEvent(
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .validatedEvidence(
                    tool: .getNode,
                    state: .success,
                    evidence: [evidence]
                )
            )
        )
        let beforeFailure = await transaction.snapshot()
        let foreignGraphScope = GraphScope(
            graphID: UUID(uuidString: "87000000-0000-0000-0000-000000000099")!
        )

        await #expect(throws: GraphChatConversationStateError.graphScopeMismatch) {
            try await transaction.apply(
                GraphChatConversationTrustedEvent(
                    graphScope: foreignGraphScope,
                    chatScope: GraphChatScope.entireGraph(foreignGraphScope),
                    payload: .validatedEvidence(
                        tool: .searchGraph,
                        state: .success,
                        evidence: []
                    )
                )
            )
        }

        #expect(await transaction.snapshot() == beforeFailure)
    }

    @Test
    func repeatedIdenticalBudgetedInputsProduceTheSameEvictionOrder() throws {
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
            maximumTechnicalDescriptionLength: 80,
            maximumLabelLength: 40
        )
        let reducer = GraphChatConversationStateReducer(policy: policy)
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let conversationID = UUID(uuidString: "88000000-0000-0000-0000-000000000001")!
        let nodes = (1...3).map { index in
            NodeRefKey(
                kind: .entity,
                id: UUID(
                    uuidString: String(
                        format: "88000000-0000-0000-0000-%012d",
                        index + 10
                    )
                )!
            )
        }
        let events = nodes.enumerated().map { index, node in
            let evidence = makeNodeEvidence(
                graphID: graphScope.graphID,
                node: node,
                ownerEntityID: node.id,
                suffix: "budget-\(index)"
            )
            return GraphChatConversationTrustedEvent(
                id: UUID(
                    uuidString: String(
                        format: "88000000-0000-0000-0001-%012d",
                        index + 1
                    )
                )!,
                graphScope: graphScope,
                chatScope: chatScope,
                payload: .validatedEvidence(
                    tool: .searchGraph,
                    state: .success,
                    evidence: [evidence]
                )
            )
        }

        let first = try reduce(
            events: events,
            reducer: reducer,
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: conversationID
        )
        let second = try reduce(
            events: events,
            reducer: reducer,
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: conversationID
        )

        #expect(first == second)
        #expect(first.nodeReferences.map(\.node) == Array(nodes.suffix(2)))
        #expect(first.resultContexts.map(\.id) == events.suffix(2).map(\.id))
        #expect(first.budgetEvictionCount > 0)
    }

    private func reduce(
        events: [GraphChatConversationTrustedEvent],
        reducer: GraphChatConversationStateReducer,
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        conversationID: UUID
    ) throws -> GraphChatConversationState {
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: conversationID
        )
        for event in events {
            state = try reducer.reduce(state, event: event).state
        }
        return state
    }

    private func makeSearchHit(
        node: NodeRefKey,
        ownerEntityID: UUID,
        title: String,
        evidenceID: GraphEvidenceID
    ) -> GraphChatSearchHit {
        GraphChatSearchHit(
            sourceReference: GraphSourceReference(
                graphID: GraphChatTestSupport.graphID,
                sourceKind: node.kind == .entity ? .entity : .attribute,
                sourceID: node.id,
                node: GraphSourceNodeReference(kind: node.kind, id: node.id),
                owner: GraphSourceNodeReference(kind: .entity, id: ownerEntityID)
            ),
            kind: node.kind == .entity ? .entity : .attribute,
            title: title,
            subtitle: "",
            matchReason: "fixture",
            evidenceID: evidenceID
        )
    }

    private func makeNodeEvidence(
        graphID: UUID,
        node: NodeRefKey,
        ownerEntityID: UUID,
        suffix: String
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphID,
                sourceKind: node.kind == .entity ? .entity : .attribute,
                sourceID: node.id,
                node: GraphSourceNodeReference(kind: node.kind, id: node.id),
                owner: GraphSourceNodeReference(kind: .entity, id: ownerEntityID)
            ),
            summary: suffix,
            navigationTitle: suffix,
            identitySuffix: suffix
        )
    }
}
