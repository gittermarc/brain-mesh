import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat grounding binding integration")
struct GraphChatGroundingBindingIntegrationTests {
    @Test
    func queryBindingUsesCompleteCatalogBeyondPromptLimits() throws {
        let fixture =
            GraphChatGroundingFixture
                .beyondInterpreterCatalogLimits()
        let compiler =
            GraphChatQueryIntentCompiler(
                calendar:
                    Calendar(
                        identifier: .gregorian
                    ),
                timeZone:
                    TimeZone(
                        secondsFromGMT: 0
                    )!
            )
        let result = try compiler.compile(
            draft:
                GraphChatUntrustedSemanticIntentDraft(
                    family:
                        .filteredCollection,
                    entityTerm:
                        "Remote Workloads",
                    filters: [
                        GraphChatSemanticFilterDraft(
                            fieldTerm:
                                "Escalation-Matrix",
                            relation: .contains,
                            values: ["Pager"]
                        ),
                    ],
                    responseLanguage:
                        .english
                ),
            selectedEntityID: nil,
            selectedFields: [],
            currentResolvedScope: nil,
            providerPlan:
                providerPlan(
                    fixture: fixture,
                    language: .english
                ),
            schemaContext: fixture.context,
            requestID: UUID(),
            sourceTurnID: nil,
            clarificationID: nil,
            referenceDate:
                Date(
                    timeIntervalSinceReferenceDate:
                        0
                )
        )
        guard case .compiled(let adaptation) =
                result,
              case .queryDetailValues(let action) =
                adaptation.action else {
            Issue.record(
                "Expected a locally compiled query"
            )
            return
        }
        #expect(
            adaptation.intent.payload
                .entities.first?.id
                == fixture.entityID(
                    named: "Remote Workload"
                )
        )
        #expect(
            action.plan.filters.first?
                .fieldAlias
                == fixture.field(
                    named: "Escalation Matrix"
                ).alias
        )
        #expect(
            adaptation.intent.resolution.quality
                == .constrainedSynonym
        )

        let lateFieldResult = try compiler.compile(
            draft:
                GraphChatUntrustedSemanticIntentDraft(
                    family:
                        .filteredCollection,
                    entityTerm:
                        "Catalog Entry 1",
                    filters: [
                        GraphChatSemanticFilterDraft(
                            fieldTerm:
                                "Late Field 13",
                            relation: .contains,
                            values: ["value"]
                        ),
                    ],
                    responseLanguage:
                        .english
                ),
            selectedEntityID: nil,
            selectedFields: [],
            currentResolvedScope: nil,
            providerPlan:
                providerPlan(
                    fixture: fixture,
                    language: .english
                ),
            schemaContext: fixture.context,
            requestID: UUID(),
            sourceTurnID: nil,
            clarificationID: nil,
            referenceDate:
                Date(
                    timeIntervalSinceReferenceDate:
                        0
                )
        )
        guard case .compiled(let lateAdaptation) =
                lateFieldResult,
              case .queryDetailValues(let lateAction) =
                lateAdaptation.action else {
            Issue.record(
                "Expected late field query compilation"
            )
            return
        }
        #expect(
            lateAction.plan.filters.first?
                .fieldAlias
                == fixture.field(
                    named: "Late Field 13"
                ).alias
        )
    }

    @Test
    func advancedNodeAndFieldBindingsUseSameResolver() throws {
        let fixture =
            GraphChatGroundingFixture.itOperations()
        let result = try
            GraphChatAdvancedIntentCompiler()
                .compile(
                    draft:
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .nodeDetails,
                            entityTerm:
                                "Incident Records",
                            nodeTerms: [
                                "Edge-Gateway 07",
                            ],
                            projectionTerms: [
                                "Severity Levels",
                            ],
                            responseLanguage:
                                .english
                        ),
                    selectedFields: [],
                    selectedNodes: [],
                    currentResolvedScope: nil,
                    providerPlan:
                        providerPlan(
                            fixture: fixture,
                            language:
                                .english
                        ),
                    schemaContext:
                        fixture.context,
                    requestID: UUID(),
                    sourceTurnID: nil,
                    clarificationID: nil
                )
        guard case .compiled(let adaptation) =
                result,
              case .nodeDetails(let details) =
                adaptation.intent.payload else {
            Issue.record(
                "Expected compiled node details"
            )
            return
        }
        #expect(
            details.entity.id
                == fixture.entityID(
                    named: "Incident Record"
                )
        )
        #expect(
            details.node.node
                == fixture.node(
                    named: "Edge Gateway 07"
                ).node
        )
        #expect(
            details.fields.map(\.id)
                == [
                    fixture.field(
                        named: "Severity Level"
                    ).fieldID,
                ]
        )
        #expect(
            adaptation.intent.resolution.quality
                == .constrainedSynonym
        )
    }

    @Test
    func advancedEntityClarificationSelectionIsRevalidated() throws {
        let fixture =
            GraphChatGroundingFixture(
                graphName: "Advanced ambiguity",
                entities: [
                    GraphChatGroundingEntityDefinition(
                        name: "Record",
                        nodeNames: ["Shared Item"],
                        fieldNames: []
                    ),
                    GraphChatGroundingEntityDefinition(
                        name: "Record",
                        nodeNames: ["Shared Item"],
                        fieldNames: []
                    ),
                ]
            )
        let compiler =
            GraphChatAdvancedIntentCompiler()
        let draft =
            GraphChatUntrustedSemanticIntentDraft(
                family: .nodeDetails,
                entityTerm: "Records",
                nodeTerms: ["Shared Item"],
                responseLanguage: .english
            )
        let plan = providerPlan(
            fixture: fixture,
            language: .english
        )
        let first = try compiler.compile(
            draft: draft,
            selectedEntityID: nil,
            selectedFields: [],
            selectedNodes: [],
            currentResolvedScope: nil,
            providerPlan: plan,
            schemaContext: fixture.context,
            requestID: UUID(),
            sourceTurnID: nil,
            clarificationID: nil
        )
        guard case .clarification(
            let clarification
        ) = first,
        let selectedEntityID =
            clarification.candidates.first?
                .entityID else {
            Issue.record(
                "Expected entity clarification"
            )
            return
        }

        let second = try compiler.compile(
            draft: draft,
            selectedEntityID:
                selectedEntityID,
            selectedFields: [],
            selectedNodes: [],
            currentResolvedScope: nil,
            providerPlan: plan,
            schemaContext: fixture.context,
            requestID: UUID(),
            sourceTurnID: nil,
            clarificationID: UUID()
        )
        guard case .compiled(let adaptation) =
                second,
              case .nodeDetails(let details) =
                adaptation.intent.payload else {
            Issue.record(
                "Selected entity should compile without another clarification"
            )
            return
        }
        #expect(
            details.entity.id == selectedEntityID
        )
        #expect(
            adaptation.intent.resolution.quality
                == .revalidatedClarification
        )
    }

    @Test
    func semanticBindingFailureCarriesContentFreeReason() async {
        let fixture =
            GraphChatGroundingFixture.library()
        let observer =
            GraphChatGroundingObservabilityProbe()
        let coordinator =
            GraphChatSemanticIntentCoordinator(
                interpreter:
                    GraphChatGroundingDraftInterpreter(
                        draft:
                            GraphChatUntrustedSemanticIntentDraft(
                                family:
                                    .entityList,
                                entityTerm:
                                    "Unknown Catalog",
                                responseLanguage:
                                    .english
                            )
                    ),
                observability: observer
            )

        do {
            _ = try await coordinator.resolve(
                providerPlan:
                    providerPlan(
                        fixture: fixture,
                        language: .english
                    ),
                schemaContext: fixture.context,
                requestID: UUID(),
                requestedAt:
                    Date(
                        timeIntervalSinceReferenceDate:
                            0
                    )
            )
            Issue.record(
                "Expected a grounding failure"
            )
        } catch let error as GraphChatError {
            #expect(error.code == .groundingFailure)
            #expect(
                error.bindingDiagnosticReason
                    == .entityNotBound
            )
            #expect(
                error.message.contains(
                    "Unknown Catalog"
                ) == false
            )
        } catch {
            Issue.record(
                "Unexpected error type: \(error)"
            )
        }
        #expect(
            await observer.reasons()
                == [.entityNotBound]
        )
    }

    @Test
    func bindingDiagnosticsDistinguishNodeFieldAndDraftFailures() async {
        let fixture =
            GraphChatGroundingFixture.library()
        let cases: [
            (
                GraphChatUntrustedSemanticIntentDraft,
                GraphChatBindingDiagnosticReason,
                String
            )
        ] = [
            (
                GraphChatUntrustedSemanticIntentDraft(
                    family: .nodeDetails,
                    nodeTerms: [
                        "Unbound Node Sentinel",
                    ],
                    responseLanguage: .english
                ),
                .nodeNotBound,
                "Unbound Node Sentinel"
            ),
            (
                GraphChatUntrustedSemanticIntentDraft(
                    family:
                        .filteredCollection,
                    entityTerm: "Autor",
                    filters: [
                        GraphChatSemanticFilterDraft(
                            fieldTerm:
                                "Unbound Field Sentinel",
                            relation: .contains,
                            values: ["value"]
                        ),
                    ],
                    responseLanguage: .english
                ),
                .fieldNotBound,
                "Unbound Field Sentinel"
            ),
            (
                GraphChatUntrustedSemanticIntentDraft(
                    family: .findNodes,
                    responseLanguage: .english
                ),
                .invalidDraftCombination,
                ""
            ),
        ]

        for (
            draft,
            expectedReason,
            privateSentinel
        ) in cases {
            let observer =
                GraphChatGroundingObservabilityProbe()
            let coordinator =
                GraphChatSemanticIntentCoordinator(
                    interpreter:
                        GraphChatGroundingDraftInterpreter(
                            draft: draft
                        ),
                    observability: observer
                )
            do {
                _ = try await coordinator.resolve(
                    providerPlan:
                        providerPlan(
                            fixture: fixture,
                            language: .english
                        ),
                    schemaContext: fixture.context,
                    requestID: UUID(),
                    requestedAt:
                        Date(
                            timeIntervalSinceReferenceDate:
                                0
                        )
                )
                Issue.record(
                    "Expected \(expectedReason)"
                )
            } catch let error as GraphChatError {
                #expect(
                    error.code == .groundingFailure
                )
                #expect(
                    error.bindingDiagnosticReason
                        == expectedReason
                )
                if privateSentinel.isEmpty == false {
                    #expect(
                        error.message.contains(
                            privateSentinel
                        ) == false
                    )
                }
            } catch {
                Issue.record(
                    "Unexpected error type: \(error)"
                )
            }
            #expect(
                await observer.reasons()
                    == [expectedReason]
            )
        }
    }

    @Test
    func ambiguityBecomesBoundPendingClarification() async throws {
        let fixture =
            GraphChatGroundingFixture(
                graphName: "Ambiguous entities",
                entities: [
                    GraphChatGroundingEntityDefinition(
                        name: "Record",
                        nodeNames: ["Alpha"],
                        fieldNames: []
                    ),
                    GraphChatGroundingEntityDefinition(
                        name: "Record",
                        nodeNames: ["Beta"],
                        fieldNames: []
                    ),
                ]
            )
        let observer =
            GraphChatGroundingObservabilityProbe()
        let coordinator =
            GraphChatSemanticIntentCoordinator(
                interpreter:
                    GraphChatGroundingDraftInterpreter(
                        draft:
                            GraphChatUntrustedSemanticIntentDraft(
                                family:
                                    .entityList,
                                entityTerm:
                                    "Records",
                                responseLanguage:
                                    .english
                            )
                    ),
                observability: observer
            )
        let plan = providerPlan(
            fixture: fixture,
            language: .english
        )
        let requestID = UUID()
        let result = try await coordinator.resolve(
            providerPlan: plan,
            schemaContext: fixture.context,
            requestID: requestID,
            requestedAt:
                Date(
                    timeIntervalSinceReferenceDate:
                        0
                )
        )

        guard case .local(let local) = result,
              case .clarification =
                local.answer.state,
              let pending =
                local.pendingClarification else {
            Issue.record(
                "Expected a local pending clarification"
            )
            return
        }
        #expect(pending.id == requestID)
        #expect(
            pending.graphScope
                == fixture.graphScope
        )
        #expect(
            pending.chatScope
                == plan.scopeKey.chatScope
        )
        #expect(pending.options.count == 2)
        #expect(
            await observer.reasons()
                == [
                    .multiplePlausibleCandidates,
                ]
        )
    }

    private func providerPlan(
        fixture: GraphChatGroundingFixture,
        language: GraphChatResponseLanguage
    ) -> GraphChatProviderTurnPlan {
        let chatScope =
            GraphChatScope.entireGraph(
                fixture.graphScope
            )
        let state =
            GraphChatConversationState.initial(
                graphScope:
                    fixture.graphScope,
                chatScope: chatScope
            )
        return GraphChatProviderTurnPlan(
            scopeKey:
                GraphChatOrchestrationScopeKey(
                    graphScope:
                        fixture.graphScope,
                    chatScope: chatScope
                ),
            normalizedQuestion: "grounding",
            providerQuestion: "grounding",
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
}

private nonisolated struct GraphChatGroundingDraftInterpreter:
    GraphChatIntentInterpreting
{
    let draft:
        GraphChatUntrustedSemanticIntentDraft

    func availability() async
        -> GraphChatModelAvailability
    {
        .available
    }

    func interpret(
        _ request:
            GraphChatIntentInterpreterRequest
    ) async throws
        -> GraphChatUntrustedSemanticIntentDraft
    {
        _ = request
        return draft
    }
}

private actor GraphChatGroundingObservabilityProbe:
    GraphChatObservabilityRecording
{
    private var values:
        [GraphChatBindingDiagnosticReason] = []

    func record(
        _ event: GraphChatObservabilityEvent
    ) {
        guard case .bindingDiagnostic(
            let metric
        ) = event else {
            return
        }
        values.append(metric.reason)
    }

    func reasons()
        -> [GraphChatBindingDiagnosticReason]
    {
        values
    }
}
