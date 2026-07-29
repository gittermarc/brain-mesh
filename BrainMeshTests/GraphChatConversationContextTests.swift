//
//  GraphChatConversationContextTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat conversation provider context")
struct GraphChatConversationContextTests {
    @Test
    func snapshotContainsOnlyBoundedValidatedAliasesAndTechnicalSummaries() {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let entityID = UUID()
        let node = NodeRefKey(kind: .attribute, id: UUID())
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.nodeReferences = [
            GraphChatConversationNodeReference(
                node: node,
                label: "Phoenix",
                ownerEntityID: entityID,
                evidenceIDs: []
            )
        ]
        state.referenceTargets = GraphChatConversationReferenceTargets(
            singular: .node(node),
            plural: [.node(node)],
            ordinal: [.node(node)],
            group: nil,
            compared: []
        )
        state.turnContexts = [
            GraphChatConversationTurnContext(
                id: UUID(),
                completedAt: Date(timeIntervalSince1970: 10),
                toolKinds: [.searchGraph],
                resultContextIDs: [],
                evidenceIDs: [],
                technicalDescription: "Validated search result with one node"
            )
        ]

        let snapshot = GraphChatConversationContextBuilder().makeSnapshot(
            from: state.snapshot
        )
        let formatted = GraphChatConversationContextFormatter().format(
            snapshot,
            language: .english
        )

        #expect(snapshot.lastNodeAlias != nil)
        #expect(formatted.contains("Phoenix"))
        #expect(formatted.contains("Validated search result with one node"))
        #expect(formatted.contains(graphScope.graphID.uuidString) == false)
        #expect(formatted.count <= GraphChatConversationContextBudget.default.maximumFormattedCharacters)
    }

    @Test
    func resultAndTurnBudgetsRetainTheMostRecentValidatedContexts() {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.resultContexts = (0..<6).map { index in
            GraphChatConversationResultContext(
                id: UUID(),
                kind: .search,
                state: .success,
                entityID: nil,
                references: [],
                groupReferences: [],
                evidenceIDs: [],
                appliedFilters: [],
                technicalDescription: "Result \(index)"
            )
        }
        state.turnContexts = (0..<8).map { index in
            GraphChatConversationTurnContext(
                id: UUID(),
                completedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                toolKinds: [.searchGraph],
                resultContextIDs: [state.resultContexts[index % state.resultContexts.count].id],
                evidenceIDs: [],
                technicalDescription: "Turn \(index)"
            )
        }
        let budget = GraphChatConversationContextBudget(
            maximumAliases: 16,
            maximumResults: 2,
            maximumResultItems: 4,
            maximumGroups: 2,
            maximumTurns: 3,
            maximumFormattedCharacters: 2_000
        )

        let snapshot = GraphChatConversationContextBuilder(budget: budget).makeSnapshot(
            from: state.snapshot
        )

        #expect(snapshot.results.count == 2)
        #expect(snapshot.results.map(\.technicalDescription) == ["Result 4", "Result 5"])
        #expect(snapshot.turns.count == 3)
        #expect(snapshot.turns.map(\.technicalDescription) == ["Turn 5", "Turn 6", "Turn 7"])
    }

    @Test
    func resultItemBudgetPrioritizesTheNewestStableResultOrder() throws {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let entityID = UUID()
        let oldNodes = (0..<3).map { _ in NodeRefKey(kind: .attribute, id: UUID()) }
        let newNodes = (0..<3).map { _ in NodeRefKey(kind: .attribute, id: UUID()) }
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.nodeReferences = (oldNodes + newNodes).enumerated().map { index, node in
            GraphChatConversationNodeReference(
                node: node,
                label: "Node \(index + 1)",
                ownerEntityID: entityID,
                evidenceIDs: []
            )
        }
        state.resultContexts = [
            resultContext(nodes: oldNodes, entityID: entityID, description: "Old result"),
            resultContext(nodes: newNodes, entityID: entityID, description: "Newest result"),
        ]
        let budget = GraphChatConversationContextBudget(
            maximumAliases: 32,
            maximumResults: 2,
            maximumResultItems: 3,
            maximumGroups: 2,
            maximumTurns: 2,
            maximumFormattedCharacters: 2_000
        )

        let snapshot = GraphChatConversationContextBuilder(budget: budget).makeSnapshot(
            from: state.snapshot
        )
        let newest = try #require(snapshot.results.last)
        let oldest = try #require(snapshot.results.first)
        let newestAlias = try #require(snapshot.alias(newest.alias))

        #expect(newest.technicalDescription == "Newest result")
        #expect(newest.itemAliases.count == 3)
        #expect(oldest.itemAliases.isEmpty)
        guard case .resultSet(_, let nodes, _) = newestAlias.target else {
            Issue.record("Expected a bounded result-set alias.")
            return
        }
        #expect(nodes == newNodes)
    }

    @Test
    func stableAliasesDoNotChangeWhenTheSameReferenceIsReformatted() {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let node = NodeRefKey(kind: .attribute, id: UUID())
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.nodeReferences = [
            GraphChatConversationNodeReference(
                node: node,
                label: "Phoenix",
                ownerEntityID: UUID(),
                evidenceIDs: []
            )
        ]
        state.referenceTargets = GraphChatConversationReferenceTargets(
            singular: .node(node),
            plural: [.node(node)],
            ordinal: [.node(node)],
            group: nil,
            compared: []
        )
        let builder = GraphChatConversationContextBuilder()

        let first = builder.makeSnapshot(from: state.snapshot)
        let second = builder.makeSnapshot(from: state.snapshot)

        #expect(first.aliases == second.aliases)
        #expect(first.lastNodeAlias == second.lastNodeAlias)
    }

    @Test
    func currentResultScopePreservesAuthoritativeResultContextID()
        throws
    {
        let graphScope = GraphScope(
            graphID: UUID()
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let entityID = UUID()
        let node = NodeRefKey(
            kind: .attribute,
            id: UUID()
        )
        let result = resultContext(
            nodes: [node],
            entityID: entityID,
            description: "Current result"
        )
        var state =
            GraphChatConversationState.initial(
                graphScope: graphScope,
                chatScope: chatScope
            )
        state.nodeReferences = [
            GraphChatConversationNodeReference(
                node: node,
                label: "Phoenix",
                ownerEntityID: entityID,
                evidenceIDs: []
            ),
        ]
        state.resultContexts = [result]

        let builder =
            GraphChatConversationContextBuilder()
        let preliminary =
            builder.makeSnapshot(
                from: state.snapshot
            )
        let resultAlias = try #require(
            preliminary.results.last?.alias
        )
        let reference =
            GraphChatResolvedConversationReference(
                kind: .resultSet,
                alias: resultAlias,
                nodes: [node],
                entityID: entityID,
                fieldID: nil,
                groupID: nil,
                label: "Current result"
            )
        let resolvedScope =
            GraphChatResolvedConversationScope(
                graphScope: graphScope,
                chatScope: chatScope,
                conversationID:
                    state.conversationID,
                entityID: entityID,
                nodes: [node],
                origin: .latestResults,
                revision:
                    GraphChatResolvedConversationScopeRevision(
                        sourceAlias:
                            resultAlias,
                        sourceResultID:
                            result.id,
                        sourceTurnID: nil,
                        sourceTurnCompletedAt:
                            nil,
                        sourceReferenceCount:
                            1,
                        validatedQueryPlan:
                            nil
                    ),
                reference: reference
            )
        let snapshot =
            builder.makeSnapshot(
                from: state.snapshot,
                currentResolvedScope:
                    resolvedScope
            )
        let current = try #require(
            snapshot.alias("CURRENT")
        )

        guard
            case .resultSet(
                let currentResultID,
                let currentNodes,
                let currentEntityID
            ) = current.target
        else {
            Issue.record(
                "Expected CURRENT to remain a result set."
            )
            return
        }
        #expect(currentResultID == result.id)
        #expect(currentNodes == [node])
        #expect(currentEntityID == entityID)
    }

    @Test
    func oldEvictedReferencesAreNotFormattedOrAvailableAsAliases() {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let oldNode = NodeRefKey(kind: .attribute, id: UUID())
        let currentNode = NodeRefKey(kind: .attribute, id: UUID())
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.nodeReferences = [
            GraphChatConversationNodeReference(
                node: currentNode,
                label: "Current",
                ownerEntityID: UUID(),
                evidenceIDs: []
            )
        ]
        state.referenceTargets = GraphChatConversationReferenceTargets(
            singular: .node(currentNode),
            plural: [.node(currentNode)],
            ordinal: [.node(currentNode)],
            group: nil,
            compared: []
        )

        let snapshot = GraphChatConversationContextBuilder().makeSnapshot(
            from: state.snapshot
        )
        let oldStableKey = GraphChatConversationReference.node(oldNode).stableKey

        #expect(
            snapshot.aliases.contains { alias in
                switch alias.target {
                case .node(let node, _):
                    return node == oldNode
                default:
                    return false
                }
            } == false)
        #expect(
            GraphChatConversationContextFormatter().format(snapshot, language: .english).contains(oldStableKey) == false
        )
    }

    @Test
    func lastValidatedQueryIsFormattedOnlyWithStableAliases() throws {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let entityID = UUID()
        let fieldID = UUID()
        let node = NodeRefKey(kind: .attribute, id: UUID())
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.entityReferences = [
            GraphChatConversationEntityReference(
                entityID: entityID,
                name: "Projects",
                alias: GraphEntityAlias("E1")
            )
        ]
        state.fieldReferences = [
            GraphChatConversationFieldReference(
                fieldID: fieldID,
                entityID: entityID,
                name: "Status",
                type: .singleChoice,
                unit: nil,
                alias: GraphFieldAlias("F1")
            )
        ]
        state.nodeReferences = [
            GraphChatConversationNodeReference(
                node: node,
                label: "Phoenix",
                ownerEntityID: entityID,
                evidenceIDs: []
            )
        ]
        state.resultContexts = [
            resultContext(
                nodes: [node],
                entityID: entityID,
                description: "Validated status query"
            )
        ]
        state.lastValidatedQueryPlan = ValidatedGraphQueryPlan(
            version: 1,
            graphScope: graphScope,
            entityID: entityID,
            scope: .graph,
            filters: [
                GraphValidatedQueryFilter(
                    fieldID: fieldID,
                    fieldType: .singleChoice,
                    operation: .equals,
                    value: .choice(
                        GraphResolvedChoiceValue(
                            originalValue: "Open",
                            canonicalValue: "Open"
                        )
                    ),
                    valueDescription: "Open"
                )
            ],
            sorting: [
                GraphValidatedQuerySort(
                    key: .field(fieldID),
                    direction: .ascending
                )
            ],
            projection: [.nodeIdentity, .field(fieldID)],
            aggregation: nil,
            limit: 20
        )

        let snapshot = GraphChatConversationContextBuilder().makeSnapshot(
            from: state.snapshot
        )
        let query = try #require(snapshot.lastValidatedQuery)
        let formatted = GraphChatConversationContextFormatter().format(
            snapshot,
            language: .english
        )

        #expect(query.entityAlias == "E1")
        #expect(query.filters.map(\.fieldAlias) == ["F1"])
        #expect(query.sorting.map(\.keyAlias) == ["F1"])
        #expect(formatted.contains("LAST VALIDATED QUERY"))
        #expect(formatted.contains(entityID.uuidString) == false)
        #expect(formatted.contains(fieldID.uuidString) == false)
        #expect(snapshot.resultRevalidations.count == 1)
    }

    @Test
    func pendingClarificationContinuationQuestionIsNeverExposedToProviderContext() {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let secretQuestion = "SECRET RAW USER QUESTION"
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.pendingClarification = GraphChatPendingClarification(
            id: UUID(),
            decision: .conversationReference,
            options: [
                GraphChatPendingClarificationOption(
                    id: "CI_ONE",
                    title: "Phoenix",
                    proposal: .alias("CI_ONE")
                )
            ],
            sourceTurnID: nil,
            graphScope: graphScope,
            chatScope: chatScope,
            continuationOperation: .openReference,
            continuationQuestion: secretQuestion,
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )

        let snapshot = GraphChatConversationContextBuilder().makeSnapshot(
            from: state.snapshot
        )
        let formatted = GraphChatConversationContextFormatter().format(
            snapshot,
            language: .english
        )

        #expect(snapshot.pendingClarificationID == state.pendingClarification?.id)
        #expect(formatted.contains(secretQuestion) == false)
    }

    private func resultContext(
        nodes: [NodeRefKey],
        entityID: UUID,
        description: String
    ) -> GraphChatConversationResultContext {
        GraphChatConversationResultContext(
            id: UUID(),
            kind: .query,
            state: .success,
            entityID: entityID,
            references: nodes.enumerated().map { index, node in
                GraphChatConversationResultReference(
                    ordinal: index + 1,
                    reference: .node(node),
                    label: "Node \(index + 1)",
                    evidenceIDs: []
                )
            },
            groupReferences: [],
            evidenceIDs: [],
            appliedFilters: [],
            technicalDescription: description
        )
    }
}
