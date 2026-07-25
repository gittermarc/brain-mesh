//
//  GraphChatRequestPreflightTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat request preflight")
struct GraphChatRequestPreflightTests {
    private let requestID = UUID(
        uuidString: "A0000000-0000-0000-0000-000000000001"
    )!
    private let requestedAt = Date(timeIntervalSince1970: 1_785_000_000)

    @Test
    func graphAndChatScopeMismatchIsRejected() async {
        let graphScope = GraphScope(
            graphID: UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
        )
        let foreignGraphScope = GraphScope(
            graphID: UUID(uuidString: "A1000000-0000-0000-0000-000000000002")!
        )
        let state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )

        do {
            _ = try await makePreflight().evaluate(
                input(
                    question: "Which projects are open?",
                    graphScope: graphScope,
                    chatScope: .entireGraph(foreignGraphScope),
                    state: state
                )
            )
            Issue.record("Expected graph/chat scope mismatch to fail.")
        } catch let error as GraphChatError {
            #expect(error.code == .invalidRequest)
            #expect(error.message == "Der Chat-Scope gehört nicht zum aktiven Graphen.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func emptyQuestionIsRejected() async {
        let fixture = Fixture()

        do {
            _ = try await fixture.preflight.evaluate(
                input(
                    question: " \n\t ",
                    graphScope: fixture.graphScope,
                    chatScope: fixture.chatScope,
                    state: fixture.state
                )
            )
            Issue.record("Expected an empty question to fail.")
        } catch let error as GraphChatError {
            #expect(error.code == .invalidRequest)
            #expect(error.message == "Die Graph-Chat-Frage darf nicht leer sein.")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func whitespaceAndMaximumLengthAreNormalizedDeterministically() async throws {
        let fixture = Fixture()
        let longQuestion = String(repeating: "x", count: 4_100)
        let result = try await fixture.preflight.evaluate(
            input(
                question: " \n\(longQuestion)\t ",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try providerPlan(from: result)

        #expect(plan.normalizedQuestion.count == 4_000)
        #expect(plan.normalizedQuestion == String(longQuestion.prefix(4_000)))
        #expect(plan.providerQuestion == plan.normalizedQuestion)
    }

    @Test
    func responseLanguageIsSelectedFromEachNormalizedQuestion() async throws {
        let fixture = Fixture(
            fallbackLanguage: .english
        )
        let german = try providerPlan(
            from: try await fixture.preflight.evaluate(
                input(
                    question: " Welche Projekte sind überfällig? ",
                    graphScope: fixture.graphScope,
                    chatScope: fixture.chatScope,
                    state: fixture.state
                )
            )
        )
        let english = try providerPlan(
            from: try await fixture.preflight.evaluate(
                input(
                    question: " Which projects are overdue? ",
                    graphScope: fixture.graphScope,
                    chatScope: fixture.chatScope,
                    state: fixture.state
                )
            )
        )

        #expect(german.responseLanguage == .german)
        #expect(english.responseLanguage == .english)
    }

    @Test
    func unsupportedWithoutPendingClarificationCreatesOnlyALocalPlan() async throws {
        let fixture = Fixture()
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Lösche den Node Phoenix.",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try localPlan(from: result)

        #expect(plan.answer.state == .unsupported(.graphMutation))
        #expect(plan.answer.evidence.isEmpty)
        #expect(plan.answer.artifactIDs.isEmpty)
        if case .provider = result {
            Issue.record("Unsupported preflight must not produce a provider plan.")
        }
    }

    @Test
    func pendingClarificationTakesPriorityOverUnsupportedDetection() async throws {
        let fixture = Fixture(nodeCount: 2, includesResult: false)
        let state = stateWithPendingClarification(
            fixture: fixture,
            expiresAt: requestedAt.addingTimeInterval(600)
        )
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Lösche den Node Phoenix.",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: state
            )
        )
        let plan = try localPlan(from: result)

        guard case .clarification(let clarification) = plan.answer.state else {
            Issue.record("Expected the existing clarification to be repeated.")
            return
        }
        #expect(clarification.id == state.pendingClarification?.id)
        #expect(plan.answer.state != .unsupported(.graphMutation))
    }

    @Test
    func expiredClarificationCreatesALocalStaleAnswerAndClearsTheBaseState() async throws {
        let fixture = Fixture(nodeCount: 2, includesResult: false)
        let state = stateWithPendingClarification(
            fixture: fixture,
            expiresAt: requestedAt
        )
        let result = try await fixture.preflight.evaluate(
            input(
                question: "1",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: state
            )
        )
        let plan = try localPlan(from: result)

        guard case .clarification(let clarification) = plan.answer.state else {
            Issue.record("Expected a stale clarification answer.")
            return
        }
        #expect(clarification.options.isEmpty)
        #expect(plan.baseState.pendingClarification == nil)
        #expect(plan.expectedCommittedState == state)
    }

    @Test
    func unknownClarificationSelectionPresentsTheSameClarificationAgain() async throws {
        let fixture = Fixture(nodeCount: 2, includesResult: false)
        let state = stateWithPendingClarification(
            fixture: fixture,
            expiresAt: requestedAt.addingTimeInterval(600)
        )
        let pending = try #require(state.pendingClarification)
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Something else",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: state
            )
        )
        let plan = try localPlan(from: result)

        guard case .clarification(let clarification) = plan.answer.state else {
            Issue.record("Expected the clarification to be repeated.")
            return
        }
        #expect(clarification.id == pending.id)
        #expect(clarification.options.map(\.id) == pending.options.map(\.id))
        #expect(plan.baseState.pendingClarification == pending)
        #expect(plan.pendingClarification == nil)
    }

    @Test
    func validClarificationSelectionCreatesTheCorrectProviderPlan() async throws {
        let fixture = Fixture(nodeCount: 2, includesResult: false)
        let state = stateWithPendingClarification(
            fixture: fixture,
            expiresAt: requestedAt.addingTimeInterval(600)
        )
        let pending = try #require(state.pendingClarification)
        let selected = try #require(pending.options.first)
        let result = try await fixture.preflight.evaluate(
            input(
                question: selected.id,
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: state
            )
        )
        let plan = try providerPlan(from: result)

        #expect(plan.providerQuestion == pending.continuationQuestion)
        #expect(plan.continuationOperation == pending.continuationOperation)
        #expect(plan.requestBaseState.pendingClarification == nil)
        #expect(plan.expectedCommittedState == state)
        #expect(plan.currentReference?.alias == selected.id)
        #expect(plan.conversationContext.currentReferenceAlias == "CURRENT")
        let formattedContext = GraphChatConversationContextFormatter().format(
            plan.conversationContext,
            language: plan.responseLanguage
        )
        #expect(formattedContext.contains(pending.continuationQuestion) == false)
    }

    @Test
    func validImplicitReferenceCreatesACurrentReference() async throws {
        let fixture = Fixture(nodeCount: 3, includesResult: true)
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Which of those are overdue?",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try providerPlan(from: result)

        #expect(plan.currentReference?.kind == .resultSet)
        #expect(plan.currentReference?.nodes == fixture.nodes)
        #expect(plan.continuationOperation == .filterReferenceSet)
        #expect(plan.conversationContext.currentReferenceAlias == "CURRENT")
    }

    @Test
    func ambiguousReferenceCreatesALocalClarification() async throws {
        let fixture = Fixture(nodeCount: 2, includesResult: false)
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Open this item.",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try localPlan(from: result)

        guard case .clarification(let clarification) = plan.answer.state else {
            Issue.record("Expected an ambiguity clarification.")
            return
        }
        #expect(clarification.options.count == 2)
        #expect(plan.pendingClarification?.options.count == 2)
        #expect(plan.pendingClarification?.continuationOperation == .openReference)
    }

    @Test
    func missingContextWithoutOptionsIsDelegatedToTheProvider() async throws {
        let fixture = Fixture()
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Which of those are overdue?",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try providerPlan(from: result)

        #expect(plan.currentReference == nil)
        #expect(plan.conversationContext.currentReferenceAlias == nil)
        #expect(plan.providerQuestion == "Which of those are overdue?")
    }

    @Test
    func demonstrativeWordWithoutFollowUpCueDoesNotForceAReference() async throws {
        let fixture = Fixture(nodeCount: 2, includesResult: true)
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Diese Projekte sind offen.",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try providerPlan(from: result)

        #expect(plan.currentReference == nil)
        #expect(plan.continuationOperation == nil)
        #expect(plan.conversationContext.currentReferenceAlias == nil)
    }

    @Test
    func rawQuestionHistoryAndAssistantTextAreNotAddedToConversationContext() async throws {
        let fixture = Fixture(nodeCount: 1, includesResult: true)
        let rawQuestion = "RAW_USER_HISTORY_SENTINEL"
        let rawAssistantText = "RAW_ASSISTANT_TEXT_SENTINEL"
        let result = try await fixture.preflight.evaluate(
            input(
                question: rawQuestion,
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try providerPlan(from: result)
        let formatted = GraphChatConversationContextFormatter().format(
            plan.conversationContext,
            language: plan.responseLanguage
        )

        #expect(formatted.contains(rawQuestion) == false)
        #expect(formatted.contains(rawAssistantText) == false)
    }

    @Test
    func identicalInputsCreateIdenticalPreflightResults() async throws {
        let fixture = Fixture(nodeCount: 2, includesResult: true)
        let value = input(
            question: "Which projects are open?",
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            state: fixture.state
        )

        let first = try await fixture.preflight.evaluate(value)
        let second = try await fixture.preflight.evaluate(value)

        #expect(first == second)
    }

    @Test
    func inputConversationStateIsNotMutated() async throws {
        let fixture = Fixture(nodeCount: 2, includesResult: false)
        let original = stateWithPendingClarification(
            fixture: fixture,
            expiresAt: requestedAt.addingTimeInterval(600)
        )
        let selected = try #require(original.pendingClarification?.options.first)
        let value = input(
            question: selected.id,
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            state: original
        )

        let result = try await fixture.preflight.evaluate(value)
        let plan = try providerPlan(from: result)

        #expect(value.conversationState == original)
        #expect(value.conversationState.pendingClarification != nil)
        #expect(plan.requestBaseState.pendingClarification == nil)
    }

    @Test
    func deletedImplicitReferenceCreatesALocalRejectedAnswer() async throws {
        let fixture = Fixture(
            nodeCount: 1,
            includesResult: true,
            missingNodeIndices: [0]
        )
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Which of those are overdue?",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try localPlan(from: result)

        guard case .clarification(let clarification) = plan.answer.state else {
            Issue.record("Expected a rejected-reference clarification.")
            return
        }
        #expect(clarification.options.isEmpty)
        #expect(plan.pendingClarification == nil)
    }

    @Test
    func emptyValidatedResultReferenceCreatesALocalNoResultsAnswer() async throws {
        let fixture = Fixture(nodeCount: 0, includesResult: true)
        let result = try await fixture.preflight.evaluate(
            input(
                question: "Which of those are overdue?",
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                state: fixture.state
            )
        )
        let plan = try localPlan(from: result)

        #expect(plan.answer.state == .noResults)
        #expect(plan.answer.evidence.isEmpty)
        #expect(plan.pendingClarification == nil)
    }
}

extension GraphChatRequestPreflightTests {
    fileprivate struct Fixture {
        let graphScope: GraphScope
        let chatScope: GraphChatScope
        let entityID: UUID
        let nodes: [NodeRefKey]
        let state: GraphChatConversationState
        let preflight: GraphChatRequestPreflight

        init(
            nodeCount: Int = 0,
            includesResult: Bool = false,
            missingNodeIndices: Set<Int> = [],
            fallbackLanguage: GraphChatResponseLanguage = .german
        ) {
            let graphID = UUID(
                uuidString: "A2000000-0000-0000-0000-000000000001"
            )!
            let entityID = UUID(
                uuidString: "A3000000-0000-0000-0000-000000000001"
            )!
            let graphScope = GraphScope(graphID: graphID)
            let chatScope = GraphChatScope.entireGraph(graphScope)
            let nodes = (0..<nodeCount).map { index in
                NodeRefKey(
                    kind: .attribute,
                    id: UUID(
                        uuidString: String(
                            format: "A4000000-0000-0000-0000-%012d",
                            index + 1
                        )
                    )!
                )
            }
            var state = GraphChatConversationState.initial(
                graphScope: graphScope,
                chatScope: chatScope,
                conversationID: UUID(
                    uuidString: "A5000000-0000-0000-0000-000000000001"
                )!
            )
            state.nodeReferences = nodes.enumerated().map { index, node in
                GraphChatConversationNodeReference(
                    node: node,
                    label: "Project \(index + 1)",
                    ownerEntityID: entityID,
                    evidenceIDs: []
                )
            }
            if includesResult {
                state.resultContexts = [
                    GraphChatConversationResultContext(
                        id: UUID(
                            uuidString: "A6000000-0000-0000-0000-000000000001"
                        )!,
                        kind: .search,
                        state: nodes.isEmpty ? .noResults : .success,
                        entityID: entityID,
                        references: nodes.enumerated().map { index, node in
                            GraphChatConversationResultReference(
                                ordinal: index + 1,
                                reference: .node(node),
                                label: "Project \(index + 1)",
                                evidenceIDs: []
                            )
                        },
                        groupReferences: [],
                        evidenceIDs: [],
                        appliedFilters: [],
                        technicalDescription: "Validated project result"
                    )
                ]
            }

            let revalidatedNodes = Dictionary(
                uniqueKeysWithValues: nodes.enumerated().compactMap {
                    index, node -> (NodeRefKey, GraphChatRevalidatedConversationNode)? in
                    guard missingNodeIndices.contains(index) == false else {
                        return nil
                    }
                    return (
                        node,
                        GraphChatRevalidatedConversationNode(
                            node: node,
                            label: "Project \(index + 1)",
                            ownerEntityID: entityID
                        )
                    )
                }
            )
            let resolver = GraphChatConversationReferenceResolver(
                revalidator: FakeReferenceRevalidator(nodes: revalidatedNodes)
            )

            self.graphScope = graphScope
            self.chatScope = chatScope
            self.entityID = entityID
            self.nodes = nodes
            self.state = state
            self.preflight = GraphChatRequestPreflight(
                referenceResolver: resolver,
                responseLanguageSelector: GraphChatResponseLanguageSelector(
                    fallback: fallbackLanguage
                )
            )
        }
    }

    fileprivate struct FakeReferenceRevalidator:
        GraphChatConversationReferenceRevalidating
    {
        let nodes: [NodeRefKey: GraphChatRevalidatedConversationNode]

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
            nil
        }

        func field(
            _ fieldID: UUID,
            in graphScope: GraphScope
        ) async throws -> GraphChatRevalidatedConversationField? {
            nil
        }

        func queryResult(
            for plan: ValidatedGraphQueryPlan
        ) async throws -> GraphChatRevalidatedConversationQuery? {
            nil
        }
    }

    fileprivate func makePreflight() -> GraphChatRequestPreflight {
        GraphChatRequestPreflight(
            responseLanguageSelector: GraphChatResponseLanguageSelector(
                fallback: .english
            )
        )
    }

    fileprivate func input(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        state: GraphChatConversationState
    ) -> GraphChatRequestPreflightInput {
        GraphChatRequestPreflightInput(
            requestID: requestID,
            requestedAt: requestedAt,
            question: question,
            graphScope: graphScope,
            chatScope: chatScope,
            conversationState: state
        )
    }

    fileprivate func stateWithPendingClarification(
        fixture: Fixture,
        expiresAt: Date
    ) -> GraphChatConversationState {
        var state = fixture.state
        let context = GraphChatConversationContextBuilder().makeSnapshot(
            from: state.snapshot
        )
        let nodeAliases = context.aliases.filter { alias in
            if case .node = alias.target {
                return true
            }
            return false
        }
        state.pendingClarification = GraphChatPendingClarification(
            id: UUID(
                uuidString: "A7000000-0000-0000-0000-000000000001"
            )!,
            decision: .conversationReference,
            options: nodeAliases.prefix(8).map {
                GraphChatPendingClarificationOption(
                    id: $0.alias,
                    title: $0.label,
                    proposal: .alias($0.alias)
                )
            },
            sourceTurnID: UUID(
                uuidString: "A8000000-0000-0000-0000-000000000001"
            )!,
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            continuationOperation: .openReference,
            continuationQuestion: "Open the selected project.",
            createdAt: requestedAt.addingTimeInterval(-60),
            expiresAt: expiresAt
        )
        return state
    }

    fileprivate func providerPlan(
        from result: GraphChatRequestPreflightResult
    ) throws -> GraphChatProviderTurnPlan {
        guard case .provider(let plan) = result else {
            Issue.record("Expected a provider turn plan.")
            throw PreflightTestError.unexpectedResult
        }
        return plan
    }

    fileprivate func localPlan(
        from result: GraphChatRequestPreflightResult
    ) throws -> GraphChatLocalTurnPlan {
        guard case .local(let plan) = result else {
            Issue.record("Expected a local turn plan.")
            throw PreflightTestError.unexpectedResult
        }
        return plan
    }

    fileprivate enum PreflightTestError: Error {
        case unexpectedResult
    }
}
