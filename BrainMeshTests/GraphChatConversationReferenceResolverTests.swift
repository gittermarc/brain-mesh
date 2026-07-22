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
        let otherGraph = GraphScope(graphID: UUID())
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
        #expect(reference.nodes == Array(fixture.nodes.prefix(2)))
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
                    groupReferences: [group],
                    evidenceIDs: [],
                    appliedFilters: [],
                    technicalDescription: "Validated project query"
                )
            ]
            state.groupReferences = [group]
            if hasGroupComparison {
                state.lastComparison = GraphChatConversationComparisonContext(
                    references: [.group(group.id)],
                    technicalDescription: "Compared validated status groups"
                )
            }
            state.referenceTargets = GraphChatConversationReferenceTargets(
                singular: hasSingularTarget ? .node(nodes[0]) : nil,
                plural: nodes.map(GraphChatConversationReference.node),
                ordinal: nodes.map(GraphChatConversationReference.node),
                group: .group(group.id),
                compared: hasGroupComparison ? [.group(group.id)] : []
            )

            let queryPlan: ValidatedGraphQueryPlan?
            switch queryRevalidation {
            case .none:
                queryPlan = nil
            case .same, .reordered:
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
            case .none:
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
