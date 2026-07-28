//
//  GraphChatConversationReferenceResolverTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat conversation reference resolver")
struct GraphChatConversationReferenceResolverTests {
    @Test
    func davonResolvesToTheLastValidatedResultSet() async throws {
        let fixture = Fixture()
        let resolution = try await fixture.resolver.resolve(
            .latestResults,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let reference) = resolution else {
            Issue.record("Expected the last result set to resolve.")
            return
        }
        #expect(reference.kind == .resultSet)
        #expect(reference.nodes == fixture.nodes)
    }

    @Test
    func ordinalsUseTheStableStoredResultOrder() async throws {
        let fixture = Fixture()

        let first = try await fixture.resolver.resolve(
            .ordinal(1),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )
        let second = try await fixture.resolver.resolve(
            .ordinal(2),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let firstReference) = first,
            case .resolved(let secondReference) = second
        else {
            Issue.record("Expected both ordinals to resolve.")
            return
        }
        #expect(firstReference.singleNode == fixture.nodes[0])
        #expect(secondReference.singleNode == fixture.nodes[1])
    }

    @Test
    func ordinalOutsideTheStableOrderCreatesClarification() async throws {
        let fixture = Fixture()
        let resolution = try await fixture.resolver.resolve(
            .ordinal(99),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .clarification(let clarification) = resolution else {
            Issue.record("Expected an ordinal clarification.")
            return
        }
        #expect(clarification.issue == .ordinalOutOfBounds)
        #expect(clarification.options.count == fixture.nodes.count)
    }

    @Test
    func deletedNodeIsNeverReused() async throws {
        let fixture = Fixture(missingNodes: [1])
        let resolution = try await fixture.resolver.resolve(
            .ordinal(2),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        #expect(resolution == .rejected(.deletedReference))
    }

    @Test
    func referenceFromAnotherGraphIsRejected() async throws {
        let fixture = Fixture()
        let otherGraph = GraphScope(
            graphID: UUID(
                uuidString: "FA000000-0000-0000-0000-000000000001"
            )!
        )
        let resolution = try await fixture.resolver.resolve(
            .latestResults,
            in: fixture.context,
            expectedGraphScope: otherGraph,
            expectedChatScope: .entireGraph(otherGraph)
        )

        #expect(resolution == .rejected(.graphMismatch))
    }

    @Test
    func incompatibleScopeIsRejected() async throws {
        let fixture = Fixture()
        let unrelatedEntity = UUID()
        let scope = GraphChatScope.entity(unrelatedEntity, in: fixture.graphScope)
        let resolution = try await fixture.resolver.resolve(
            .ordinal(1),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: scope
        )

        #expect(resolution == .rejected(.scopeMismatch))
    }

    @Test
    func resultReferenceCannotBroadenASelectionScope() async throws {
        let fixture = Fixture(nodeCount: 3)
        let scope = try GraphChatScope.selection(
            Array(fixture.nodes.prefix(1)),
            in: fixture.graphScope
        )
        let context = GraphChatConversationContextSnapshot(
            conversationID: fixture.context.conversationID,
            graphScope: fixture.context.graphScope,
            chatScope: scope,
            aliases: fixture.context.aliases,
            results: fixture.context.results,
            turns: fixture.context.turns,
            latestResultAlias: fixture.context.latestResultAlias,
            lastEntityAlias: fixture.context.lastEntityAlias,
            lastFieldAlias: fixture.context.lastFieldAlias,
            lastGroupAlias: fixture.context.lastGroupAlias,
            lastNodeAlias: fixture.context.lastNodeAlias,
            lastComparisonAlias: fixture.context.lastComparisonAlias,
            currentReferenceAlias: fixture.context.currentReferenceAlias,
            lastValidatedQuery: fixture.context.lastValidatedQuery,
            resultRevalidations: fixture.context.resultRevalidations,
            pendingClarificationID: fixture.context.pendingClarificationID
        )
        let resolution = try await fixture.resolver.resolveScope(
            .latestResults,
            in: context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: scope
        )

        #expect(resolution == .rejected(.scopeMismatch))
    }

    @Test
    func lastEntityAndFieldResolveWithEntityCompatibility() async throws {
        let fixture = Fixture()
        let entity = try await fixture.resolver.resolve(
            .lastEntity,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope,
            expectedEntityID: fixture.entityID
        )
        let field = try await fixture.resolver.resolve(
            .lastField,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope,
            expectedEntityID: fixture.entityID
        )

        guard case .resolved(let entityReference) = entity,
            case .resolved(let fieldReference) = field
        else {
            Issue.record("Expected the last entity and field to resolve.")
            return
        }
        #expect(entityReference.entityID == fixture.entityID)
        #expect(fieldReference.fieldID == fixture.fieldID)
    }

    @Test
    func groupFollowUpUsesExactlyTheStoredGroupMembers() async throws {
        let fixture = Fixture()
        let resolution = try await fixture.resolver.resolve(
            .lastGroup,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let reference) = resolution else {
            Issue.record("Expected the group reference to resolve.")
            return
        }
        #expect(reference.kind == .group)
        #expect(reference.nodes == Array(fixture.nodes.prefix(2)))
    }

    @Test
    func comparedGroupsExpandToTheirValidatedMemberNodes() async throws {
        let fixture = Fixture(hasGroupComparison: true)
        let resolution = try await fixture.resolver.resolve(
            .lastCompared,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let reference) = resolution else {
            Issue.record("Expected the compared groups to resolve.")
            return
        }
        #expect(reference.kind == .comparison)
        #expect(reference.nodes == fixture.nodes)
    }

    @Test
    func firstThreeCreatesAValidatedSubsetWithoutChangingOrder() async throws {
        let fixture = Fixture(nodeCount: 5)
        let resolution = try await fixture.resolver.resolve(
            .latestResultsSubset(offset: 0, limit: 3),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let reference) = resolution else {
            Issue.record("Expected the subset to resolve.")
            return
        }
        #expect(reference.kind == .resultSubset)
        #expect(reference.nodes == Array(fixture.nodes.prefix(3)))
    }

    @Test
    func homogeneousResultsCreateATypedConversationScopeBoundToTheConversation() async throws {
        let fixture = Fixture(nodeCount: 3)
        let resolution = try await fixture.resolver.resolveScope(
            .latestResults,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let scope) = resolution else {
            Issue.record("Expected a typed homogeneous conversation scope.")
            return
        }
        #expect(scope.graphScope == fixture.graphScope)
        #expect(scope.chatScope == fixture.chatScope)
        #expect(scope.conversationID == fixture.context.conversationID)
        #expect(scope.entityID == fixture.entityID)
        #expect(scope.nodes == fixture.nodes)
        #expect(scope.origin == .latestResults)
        #expect(scope.revision.sourceResultID == fixture.context.results.last?.id)
        #expect(scope.revision.sourceReferenceCount == fixture.nodes.count)
    }

    @Test
    func oneNodeCurrentStillCreatesAConcreteEntityScope() async throws {
        let fixture = Fixture(nodeCount: 1)
        let resolution = try await fixture.resolver.resolveScope(
            .latestResults,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let scope) = resolution else {
            Issue.record("Expected a typed one-node conversation scope.")
            return
        }
        #expect(scope.entityID == fixture.entityID)
        #expect(scope.nodes == fixture.nodes)
    }

    @Test
    func emptyCurrentRemainsNoResults() async throws {
        let fixture = Fixture(nodeCount: 0)
        let resolution =
            try await fixture.resolver
                .resolveScope(
                    .latestResults,
                    in: fixture.context,
                    expectedGraphScope:
                        fixture.graphScope,
                    expectedChatScope:
                        fixture.chatScope
                )

        #expect(
            resolution
                == .noResults(.emptyResults)
        )
    }

    @Test
    func mixedEntityCurrentRequiresExistingClarification()
        async throws
    {
        let graphScope = GraphScope(
            graphID: UUID()
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let firstEntityID = UUID()
        let secondEntityID = UUID()
        let firstNode = NodeRefKey(
            kind: .attribute,
            id: UUID()
        )
        let secondNode = NodeRefKey(
            kind: .attribute,
            id: UUID()
        )
        var state =
            GraphChatConversationState.initial(
                graphScope: graphScope,
                chatScope: chatScope
            )
        state.entityReferences = [
            GraphChatConversationEntityReference(
                entityID: firstEntityID,
                name: "Projects",
                alias: nil
            ),
            GraphChatConversationEntityReference(
                entityID: secondEntityID,
                name: "People",
                alias: nil
            ),
        ]
        state.nodeReferences = [
            GraphChatConversationNodeReference(
                node: firstNode,
                label: "Atlas",
                ownerEntityID:
                    firstEntityID,
                evidenceIDs: []
            ),
            GraphChatConversationNodeReference(
                node: secondNode,
                label: "Ada",
                ownerEntityID:
                    secondEntityID,
                evidenceIDs: []
            ),
        ]
        let resultID = UUID()
        state.resultContexts = [
            GraphChatConversationResultContext(
                id: resultID,
                kind: .search,
                state: .success,
                entityID: nil,
                references: [
                    GraphChatConversationResultReference(
                        ordinal: 1,
                        reference:
                            .node(firstNode),
                        label: "Atlas",
                        evidenceIDs: []
                    ),
                    GraphChatConversationResultReference(
                        ordinal: 2,
                        reference:
                            .node(secondNode),
                        label: "Ada",
                        evidenceIDs: []
                    ),
                ],
                groupReferences: [],
                evidenceIDs: [],
                appliedFilters: [],
                technicalDescription:
                    "Validated mixed result"
            )
        ]
        state.referenceTargets =
            GraphChatConversationReferenceTargets(
                singular: nil,
                plural: [
                    .node(firstNode),
                    .node(secondNode),
                ],
                ordinal: [
                    .node(firstNode),
                    .node(secondNode),
                ],
                group: nil,
                compared: []
            )
        let context =
            GraphChatConversationContextBuilder()
                .makeSnapshot(
                    from: state.snapshot
                )
        let resolver =
            GraphChatConversationReferenceResolver(
                revalidator:
                    FakeReferenceRevalidator(
                        nodes: [
                            firstNode:
                                GraphChatRevalidatedConversationNode(
                                    node: firstNode,
                                    label: "Atlas",
                                    ownerEntityID:
                                        firstEntityID
                                ),
                            secondNode:
                                GraphChatRevalidatedConversationNode(
                                    node: secondNode,
                                    label: "Ada",
                                    ownerEntityID:
                                        secondEntityID
                                ),
                        ],
                        entities: [
                            firstEntityID:
                                GraphChatRevalidatedConversationEntity(
                                    entityID:
                                        firstEntityID,
                                    label:
                                        "Projects"
                                ),
                            secondEntityID:
                                GraphChatRevalidatedConversationEntity(
                                    entityID:
                                        secondEntityID,
                                    label: "People"
                                ),
                        ],
                        fields: [:],
                        queryResult: nil
                    )
            )
        let resolution =
            try await resolver.resolveScope(
                .latestResults,
                in: context,
                expectedGraphScope:
                    graphScope,
                expectedChatScope:
                    chatScope
            )
        guard case .clarification(
            let clarification
        ) = resolution else {
            Issue.record(
                "Expected mixed-entity clarification."
            )
            return
        }

        #expect(
            clarification.issue
                == .mixedEntities
        )
        #expect(
            clarification.options.count == 2
        )
    }

    @Test
    func multipleGroupsOfTheSameEntityResolveDeterministically() async throws {
        let fixture = Fixture(hasGroupComparison: true)
        let first = try await fixture.resolver.resolveScope(
            .lastCompared,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )
        let second = try await fixture.resolver.resolveScope(
            .lastCompared,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let firstScope) = first,
            case .resolved(let secondScope) = second
        else {
            Issue.record("Expected both same-entity group resolutions to succeed.")
            return
        }
        #expect(firstScope.entityID == fixture.entityID)
        #expect(firstScope.nodes == fixture.nodes)
        #expect(firstScope == secondScope)
    }

    @Test
    func typedScopeCannotBeReusedForAnotherGraph() async throws {
        let fixture = Fixture()
        let original = try await fixture.resolver.resolveScope(
            .latestResults,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )
        guard case .resolved(let scope) = original else {
            Issue.record("Expected the original scope to resolve.")
            return
        }
        let otherGraph = GraphScope(
            graphID: UUID(
                uuidString: "FA000000-0000-0000-0000-000000000001"
            )!
        )
        let resolution = try await fixture.resolver.resolveScope(
            .validatedScope(scope),
            in: fixture.context,
            expectedGraphScope: otherGraph,
            expectedChatScope: .entireGraph(otherGraph)
        )

        #expect(resolution == .rejected(.graphMismatch))
    }

    @Test
    func typedScopeRevalidationRejectsNodesThatBecameStale() async throws {
        let fixture = Fixture()
        let original = try await fixture.resolver.resolveScope(
            .latestResults,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )
        guard case .resolved(let scope) = original else {
            Issue.record("Expected the original scope to resolve.")
            return
        }
        let staleResolver = GraphChatConversationReferenceResolver(
            revalidator: FakeReferenceRevalidator(
                nodes: [:],
                entities: [:],
                fields: [:],
                queryResult: nil
            )
        )
        let resolution = try await staleResolver.resolveScope(
            .validatedScope(scope),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        #expect(resolution == .rejected(.deletedReference))
    }

    @Test
    func unchangedQueryResultsRemainResolvableAfterRevalidation() async throws {
        let fixture = Fixture(queryRevalidation: .same)
        let resolution = try await fixture.resolver.resolve(
            .ordinal(2),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let reference) = resolution else {
            Issue.record("Expected the unchanged query result to resolve.")
            return
        }
        #expect(reference.singleNode == fixture.nodes[1])
    }

    @Test
    func reorderedQueryResultsAreRejectedAsStaleBeforeOrdinalResolution() async throws {
        let fixture = Fixture(queryRevalidation: .reordered)
        let resolution = try await fixture.resolver.resolve(
            .ordinal(1),
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        #expect(resolution == .rejected(.staleResults))
    }

    @Test
    func unavailableQueryRevalidationIsRejectedAsStale() async throws {
        let fixture = Fixture(queryRevalidation: .unavailable)
        let resolution = try await fixture.resolver.resolveScope(
            .latestResults,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        #expect(resolution == .rejected(.staleResults))
    }

    @Test
    func nodeDetailFollowUpResolvesTheSameValidatedObject() async throws {
        let fixture = Fixture(hasSingularTarget: true)
        let resolution = try await fixture.resolver.resolve(
            .lastNode,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .resolved(let reference) = resolution else {
            Issue.record("Expected the previously validated detail node to resolve.")
            return
        }
        #expect(reference.kind == .node)
        #expect(reference.singleNode == fixture.nodes[0])
    }

    @Test
    func ambiguousLastNodeDoesNotGuessAmongSeveralResults() async throws {
        let fixture = Fixture(hasSingularTarget: false)
        let resolution = try await fixture.resolver.resolve(
            .lastNode,
            in: fixture.context,
            expectedGraphScope: fixture.graphScope,
            expectedChatScope: fixture.chatScope
        )

        guard case .clarification(let clarification) = resolution else {
            Issue.record("Expected an ambiguity clarification.")
            return
        }
        #expect(clarification.issue == .ambiguous)
        #expect(clarification.options.count >= 2)
    }

    @Test
    func interpreterRequiresWholeWordsAndExplicitResultReferences() {
        let interpreter = GraphChatConversationReferenceInterpreter()

        #expect(interpreter.interpretation(for: "Welche Projekte sind diese Woche offen?") == nil)
        #expect(interpreter.interpretation(for: "What hypotheses are linked?") == nil)
        #expect(
            interpreter.interpretation(for: "Welche davon sind offen?")?.proposal
                == .latestResults
        )
        #expect(
            interpreter.interpretation(for: "Which of those are open?")?.proposal
                == .latestResults
        )
        #expect(
            interpreter.interpretation(for: "Sortiere diese Gruppe nach Name.")?.proposal
                == .lastGroup
        )
        #expect(
            interpreter.interpretation(for: "Sort this group by name.")?.proposal
                == .lastGroup
        )
        #expect(
            interpreter.interpretation(
                for: "Was weißt du über den letzten Node?"
            )?.proposal == .lastNode
        )
        #expect(
            interpreter.interpretation(for: "Show the last node.")?.proposal
                == .lastNode
        )
    }

    @Test
    func exactClarificationSelectionDoesNotFreelyInterpretOtherText() {
        let fixture = Fixture()
        let pending = GraphChatPendingClarification(
            id: UUID(),
            decision: .conversationReference,
            options: [
                GraphChatPendingClarificationOption(
                    id: "CI_ONE",
                    title: "Phoenix",
                    proposal: .alias("CI_ONE")
                ),
                GraphChatPendingClarificationOption(
                    id: "CI_TWO",
                    title: "Apollo",
                    proposal: .alias("CI_TWO")
                ),
            ],
            sourceTurnID: nil,
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            continuationOperation: .openReference,
            continuationQuestion: "Öffne die ausgewählte Referenz.",
            createdAt: Date(timeIntervalSince1970: 100),
            expiresAt: Date(timeIntervalSince1970: 1_000)
        )
        let interpreter = GraphChatConversationReferenceInterpreter()

        #expect(interpreter.clarificationSelection(for: "2", pending: pending)?.id == "CI_TWO")
        #expect(interpreter.clarificationSelection(for: "Phoenix", pending: pending)?.id == "CI_ONE")
        #expect(interpreter.clarificationSelection(for: "10", pending: pending) == nil)
        #expect(interpreter.clarificationSelection(for: "Irgendetwas anderes", pending: pending) == nil)
    }
}

extension GraphChatConversationReferenceResolverTests {
    fileprivate enum QueryRevalidationMode {
        case none
        case unavailable
        case same
        case reordered
    }

    fileprivate struct Fixture {
        let graphScope: GraphScope
        let chatScope: GraphChatScope
        let entityID: UUID
        let fieldID: UUID
        let nodes: [NodeRefKey]
        let context: GraphChatConversationContextSnapshot
        let resolver: GraphChatConversationReferenceResolver

        init(
            nodeCount: Int = 3,
            missingNodes: Set<Int> = [],
            hasSingularTarget: Bool = false,
            hasGroupComparison: Bool = false,
            queryRevalidation: QueryRevalidationMode = .none
        ) {
            let graphScope = GraphScope(graphID: UUID())
            let chatScope = GraphChatScope.entireGraph(graphScope)
            let entityID = UUID()
            let fieldID = UUID()
            let nodes = (0..<nodeCount).map { _ in
                NodeRefKey(kind: .attribute, id: UUID())
            }
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
            state.nodeReferences = nodes.enumerated().map { index, node in
                GraphChatConversationNodeReference(
                    node: node,
                    label: "Project \(index + 1)",
                    ownerEntityID: entityID,
                    evidenceIDs: []
                )
            }
            let group = GraphChatConversationGroupReference(
                id: "status:open",
                fieldID: fieldID,
                fieldName: "Status",
                valueDescription: "Open",
                count: min(2, nodes.count),
                evidenceIDs: [],
                memberNodes: Array(nodes.prefix(2))
            )
            let secondGroup = GraphChatConversationGroupReference(
                id: "status:closed",
                fieldID: fieldID,
                fieldName: "Status",
                valueDescription: "Closed",
                count: max(0, nodes.count - 2),
                evidenceIDs: [],
                memberNodes: Array(nodes.dropFirst(2))
            )
            let groups =
                hasGroupComparison
                ? [group, secondGroup]
                : [group]
            let resultID = UUID()
            state.resultContexts = [
                GraphChatConversationResultContext(
                    id: resultID,
                    kind: .query,
                    state: .success,
                    entityID: entityID,
                    references: nodes.enumerated().map { index, node in
                        GraphChatConversationResultReference(
                            ordinal: index + 1,
                            reference: .node(node),
                            label: "Project \(index + 1)",
                            evidenceIDs: []
                        )
                    },
                    groupReferences: groups,
                    evidenceIDs: [],
                    appliedFilters: [],
                    technicalDescription: "Validated project query"
                )
            ]
            state.groupReferences = groups
            if hasGroupComparison {
                state.lastComparison = GraphChatConversationComparisonContext(
                    references: groups.map { .group($0.id) },
                    technicalDescription: "Compared validated status groups"
                )
            }
            state.referenceTargets = GraphChatConversationReferenceTargets(
                singular: hasSingularTarget ? .node(nodes[0]) : nil,
                plural: nodes.map(GraphChatConversationReference.node),
                ordinal: nodes.map(GraphChatConversationReference.node),
                group: .group(group.id),
                compared:
                    hasGroupComparison
                    ? groups.map { .group($0.id) }
                    : []
            )

            let queryPlan: ValidatedGraphQueryPlan?
            switch queryRevalidation {
            case .none:
                queryPlan = nil
            case .unavailable, .same, .reordered:
                queryPlan = ValidatedGraphQueryPlan(
                    version: 1,
                    graphScope: graphScope,
                    entityID: entityID,
                    scope: .graph,
                    filters: [],
                    sorting: [],
                    projection: [.nodeIdentity],
                    aggregation: nil,
                    limit: max(nodeCount, 1)
                )
            }
            state.lastValidatedQueryPlan = queryPlan

            let currentQueryNodes: [NodeRefKey]?
            switch queryRevalidation {
            case .none, .unavailable:
                currentQueryNodes = nil
            case .same:
                currentQueryNodes = nodes
            case .reordered:
                currentQueryNodes = Array(nodes.reversed())
            }

            var revalidatedNodes: [NodeRefKey: GraphChatRevalidatedConversationNode] = [:]
            for (index, node) in nodes.enumerated() where missingNodes.contains(index) == false {
                revalidatedNodes[node] = GraphChatRevalidatedConversationNode(
                    node: node,
                    label: "Project \(index + 1)",
                    ownerEntityID: entityID
                )
            }
            let revalidator = FakeReferenceRevalidator(
                nodes: revalidatedNodes,
                entities: [
                    entityID: GraphChatRevalidatedConversationEntity(
                        entityID: entityID,
                        label: "Projects"
                    )
                ],
                fields: [
                    fieldID: GraphChatRevalidatedConversationField(
                        fieldID: fieldID,
                        entityID: entityID,
                        label: "Status"
                    )
                ],
                queryResult: currentQueryNodes.map {
                    GraphChatRevalidatedConversationQuery(
                        state: .success,
                        nodes: Array($0),
                        groups: []
                    )
                }
            )

            self.graphScope = graphScope
            self.chatScope = chatScope
            self.entityID = entityID
            self.fieldID = fieldID
            self.nodes = nodes
            self.context = GraphChatConversationContextBuilder().makeSnapshot(
                from: state.snapshot
            )
            self.resolver = GraphChatConversationReferenceResolver(
                revalidator: revalidator
            )
        }
    }

    fileprivate struct FakeReferenceRevalidator: GraphChatConversationReferenceRevalidating {
        let nodes: [NodeRefKey: GraphChatRevalidatedConversationNode]
        let entities: [UUID: GraphChatRevalidatedConversationEntity]
        let fields: [UUID: GraphChatRevalidatedConversationField]
        let queryResult: GraphChatRevalidatedConversationQuery?

        func node(
            _ node: NodeRefKey,
            in graphScope: GraphScope
        ) async throws -> GraphChatRevalidatedConversationNode? {
            nodes[node]
        }

        func entity(
            _ entityID: UUID,
            in graphScope: GraphScope
        ) async throws -> GraphChatRevalidatedConversationEntity? {
            entities[entityID]
        }

        func field(
            _ fieldID: UUID,
            in graphScope: GraphScope
        ) async throws -> GraphChatRevalidatedConversationField? {
            fields[fieldID]
        }

        func queryResult(
            for plan: ValidatedGraphQueryPlan
        ) async throws -> GraphChatRevalidatedConversationQuery? {
            queryResult
        }
    }
}
