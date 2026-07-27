import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat typed intent core")
struct GraphChatTypedIntentCoreTests {
    @Test
    func allDomainContractsAreSendableAndDeterministicallyHashable()
        throws
    {
        let fixture = TypedIntentContractFixture()
        let intents = try fixture.allIntentFamilies()

        requireHashableSendable(
            GraphChatTypedIntentDomainVersion.v1
        )
        requireHashableSendable(
            GraphChatTypedIntentKind.allCases
        )
        requireHashableSendable(
            GraphChatTypedIntentResolutionSource.allCases
        )
        requireHashableSendable(
            GraphChatTypedIntentResolutionOrigin.allCases
        )
        requireHashableSendable(
            GraphChatTypedIntentResolutionQuality.allCases
        )
        requireHashableSendable(
            GraphChatTypedIntentExpectedCardinality.allCases
        )
        requireHashableSendable(
            GraphChatTypedIntentFactExpectation.allCases
        )
        requireHashableSendable(fixture.binding)
        requireHashableSendable(fixture.scope)
        requireHashableSendable(fixture.resolution)
        requireHashableSendable(fixture.limits)
        requireHashableSendable(fixture.firstEntity)
        requireHashableSendable(fixture.firstField)
        requireHashableSendable(fixture.firstNode)
        for intent in intents {
            requireHashableSendable(intent)
            requireHashableSendable(intent.payload)
        }

        #expect(
            Set(intents.map(\.kind))
                == Set(GraphChatTypedIntentKind.allCases)
        )
        #expect(
            Set(intents + intents).count == intents.count
        )
        let copies = try fixture.allIntentFamilies()
        #expect(intents == copies)
    }

    @Test
    func foundationalSingleFieldIsAdaptedWithoutLosingBindings()
        throws
    {
        let fixture = FoundationalAdapterFixture()
        let source = fixture.singleFieldIntent
        let adaptation =
            try GraphChatFoundationalIntentAdapter()
                .adapt(source)
        requireHashableSendable(adaptation)
        let intent = adaptation.intent

        #expect(intent.version == .v1)
        #expect(intent.kind == .nodeDetails)
        #expect(intent.scope.graphScope == source.graphScope)
        #expect(intent.scope.chatScope == source.chatScope)
        #expect(intent.scope.queryScope == source.queryScope)
        #expect(
            intent.responseLanguage
                == source.responseLanguage
        )
        #expect(
            intent.binding.requestID
                == source.binding.requestID
        )
        #expect(
            intent.binding.conversationID
                == source.binding.conversationID
        )
        #expect(
            intent.binding.turnID
                == source.binding.requestID
        )
        #expect(
            intent.binding.sourceTurnID
                == source.binding.sourceTurnID
        )
        #expect(
            intent.binding.clarificationID
                == source.binding.clarificationID
        )
        #expect(
            intent.resolution.source
                == .foundationalFastPath
        )
        #expect(
            intent.resolution.origin
                == .localizedFieldSynonym
        )
        #expect(
            intent.resolution.quality
                == .constrainedSynonym
        )
        #expect(
            intent.expectedCardinality == .zeroOrOne
        )
        #expect(
            intent.factExpectation
                == .authoritativeSingleField
        )
        #expect(intent.limits.resultLimit == 1)
        #expect(
            intent.limits.maximumResultLimit
                == GraphQueryPlanLimits.maximumResultLimit
        )

        guard case .nodeDetails(let details) =
            intent.payload else {
            Issue.record("Expected typed node details.")
            return
        }
        #expect(details.entity.id == source.entity.id)
        #expect(
            details.entity.alias == source.entity.alias
        )
        #expect(
            details.entity.displayName
                == source.entity.displayName
        )
        #expect(
            details.node.node == source.node?.node
        )
        #expect(
            details.node.displayName
                == source.node?.displayName
        )
        #expect(details.fields.count == 1)
        #expect(details.fields[0].id == source.field?.id)
        #expect(
            details.fields[0].alias
                == source.field?.alias
        )
        #expect(
            details.fields[0].type
                == source.field?.type
        )

        guard case .queryDetailValues(let action) =
            adaptation.action else {
            Issue.record("Expected a local query action.")
            return
        }
        let sourceField = try #require(source.field)
        #expect(action.plan.scope == source.queryScope)
        #expect(action.plan.limit == 1)
        #expect(
            action.plan.projection == [
                .nodeIdentity,
                .field(sourceField.alias),
            ]
        )
        guard case .authoritativeSingleField =
            action.resultContract else {
            Issue.record(
                "Expected an authoritative single-field contract."
            )
            return
        }
    }

    @Test
    func foundationalCollectionIsAdaptedWithoutLosingScopeOrLimit()
        throws
    {
        let fixture = FoundationalAdapterFixture()
        let source = fixture.collectionIntent
        let adaptation =
            try GraphChatFoundationalIntentAdapter()
                .adapt(source)
        requireHashableSendable(adaptation)
        let intent = adaptation.intent

        #expect(intent.kind == .entityCollection)
        #expect(intent.scope.graphScope == source.graphScope)
        #expect(intent.scope.chatScope == source.chatScope)
        #expect(intent.scope.queryScope == source.queryScope)
        #expect(
            intent.binding.requestID
                == source.binding.requestID
        )
        #expect(
            intent.binding.conversationID
                == source.binding.conversationID
        )
        #expect(
            intent.binding.sourceTurnID
                == source.binding.sourceTurnID
        )
        #expect(
            intent.binding.clarificationID
                == source.binding.clarificationID
        )
        #expect(
            intent.resolution.origin
                == .clarificationSelection
        )
        #expect(
            intent.resolution.quality
                == .revalidatedClarification
        )
        #expect(
            intent.expectedCardinality == .zeroOrMore
        )
        #expect(intent.factExpectation == .none)
        #expect(
            intent.limits.resultLimit
                == GraphQueryPlanLimits.maximumResultLimit
        )

        guard case .entityCollection(let collection) =
            intent.payload else {
            Issue.record("Expected a typed collection.")
            return
        }
        #expect(collection.entity.id == source.entity.id)
        #expect(collection.projectedFields.isEmpty)

        guard case .queryDetailValues(let action) =
            adaptation.action else {
            Issue.record("Expected a local query action.")
            return
        }
        #expect(action.plan.filters.isEmpty)
        #expect(action.plan.aggregation == nil)
        #expect(action.plan.projection == [.nodeIdentity])
        #expect(
            action.plan.limit
                == GraphQueryPlanLimits.maximumResultLimit
        )
        #expect(action.resultContract == .entityCollection)
    }

    @Test
    func artifactStagingFailureRollsBackEveryKernelResource()
        async throws
    {
        let fixture = LocalKernelExecutionFixture()
        let reportRecorder = CleanupReportRecorder()
        let observability = LocalIntentObservabilityRecorder()
        let commitRecorder = KernelCommitRecorder()
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: fixture.graphScope,
            scope: fixture.chatScope,
            sessionID: fixture.artifactSessionID,
            budget: GraphChatAnswerArtifactRegistryBudget(
                maximumArtifactCount: 1,
                maximumTotalByteCount: 1,
                maximumArtifactByteCount: 1
            )
        )
        let artifactSession =
            GraphChatArtifactSessionResources(
                key: fixture.scopeKey,
                sessionID: fixture.artifactSessionID,
                registry: registry
            )
        let executor = fixture.executor(
            observability: observability,
            observer:
                GraphChatLocalIntentExecutionKernelObserver {
                    report in
                    await reportRecorder.record(report)
                }
        )

        await #expect(
            throws:
                GraphChatAnswerArtifactRegistryError
                    .artifactTooLarge(
                        maximumByteCount: 1
                    )
        ) {
            _ = try await executor.execute(
                intent: fixture.intent,
                schemaContext: fixture.schemaContext,
                providerPlan: fixture.providerPlan,
                requestID: fixture.requestID,
                artifactSession: artifactSession,
                onActivity: { _ in },
                validateCurrentRequest: {},
                finalize: { _ in
                    throw KernelTestError
                        .unexpectedFinalization
                },
                commit: { _ in
                    await commitRecorder.record()
                }
            )
        }
        let report = try #require(
            await reportRecorder.snapshot().last
        )
        let lifecycle =
            await observability.lifecycleEvents()

        #expect(report.outcome == .rolledBack)
        #expect(report.evidenceCount == 0)
        #expect(report.presentationEntryCount == 0)
        #expect(report.stagedArtifactCount == 0)
        #expect(report.ledgerEntryCount == 0)
        #expect(report.ledgerIsBound == false)
        #expect(report.conversationRestoredToBase)
        #expect(await commitRecorder.count() == 0)
        #expect(await registry.snapshotForTesting().isEmpty)
        #expect(
            lifecycle == [
                .foundationalAdapted,
                .executionStarted,
                .executionRolledBack,
            ]
        )
    }

    @Test
    func outerCommitFailureRemovesCommittedSessionArtifacts()
        async throws
    {
        let fixture = LocalKernelExecutionFixture()
        let reportRecorder = CleanupReportRecorder()
        let observability = LocalIntentObservabilityRecorder()
        let commitRecorder = KernelCommitRecorder()
        let registry = GraphChatAnswerArtifactRegistry(
            graphScope: fixture.graphScope,
            scope: fixture.chatScope,
            sessionID: fixture.artifactSessionID
        )
        let artifactSession =
            GraphChatArtifactSessionResources(
                key: fixture.scopeKey,
                sessionID: fixture.artifactSessionID,
                registry: registry
            )
        let executor = fixture.executor(
            observability: observability,
            observer:
                GraphChatLocalIntentExecutionKernelObserver {
                    report in
                    await reportRecorder.record(report)
                }
        )

        await #expect(
            throws: KernelTestError.expectedCommitFailure
        ) {
            _ = try await executor.execute(
                intent: fixture.intent,
                schemaContext: fixture.schemaContext,
                providerPlan: fixture.providerPlan,
                requestID: fixture.requestID,
                artifactSession: artifactSession,
                onActivity: { _ in },
                validateCurrentRequest: {},
                finalize: { execution in
                    let retained =
                        try await execution.artifactRegistry
                            .commit(
                                transactionID:
                                    execution.artifactContext
                                        .transactionID,
                                retaining:
                                    execution.primaryResult
                                        .artifactIDs
                            )
                    let answer = GraphChatAnswer(
                        directAnswer: "Projekt Atlas",
                        evidence:
                            execution.primaryResult.evidence,
                        artifactIDs: retained,
                        hasInsufficientEvidence: false
                    )
                    let state =
                        try await execution
                            .conversationTransaction
                            .finalizedState(
                                requestID:
                                    fixture.requestID,
                                completedAt:
                                    fixture.completedAt,
                                validatedEvidenceIDs:
                                    answer.evidenceIDs
                            )
                    return GraphChatFinalizedTurn(
                        answer: answer,
                        conversationState: state,
                        committedArtifactIDs: retained,
                        completion:
                            GraphChatTurnCompletionInfo(
                                requestID:
                                    fixture.requestID,
                                completedAt:
                                    fixture.completedAt,
                                source: .local,
                                evidenceCount:
                                    answer.evidence.count,
                                requestedArtifactCount:
                                    retained.count,
                                committedArtifactCount:
                                    retained.count
                            )
                    )
                },
                commit: { _ in
                    await commitRecorder.record()
                    throw KernelTestError.expectedCommitFailure
                }
            )
        }
        let report = try #require(
            await reportRecorder.snapshot().last
        )
        let lifecycle =
            await observability.lifecycleEvents()

        #expect(await commitRecorder.count() == 1)
        #expect(await registry.snapshotForTesting().isEmpty)
        #expect(report.outcome == .rolledBack)
        #expect(report.evidenceCount == 0)
        #expect(report.presentationEntryCount == 0)
        #expect(report.stagedArtifactCount == 0)
        #expect(report.ledgerEntryCount == 0)
        #expect(report.ledgerIsBound == false)
        #expect(report.conversationRestoredToBase)
        #expect(
            lifecycle == [
                .foundationalAdapted,
                .executionStarted,
                .executionRolledBack,
            ]
        )
    }

    private func requireHashableSendable<
        Value: Hashable & Sendable
    >(
        _ value: Value
    ) {
        _ = value
    }
}

private struct TypedIntentContractFixture {
    let graphScope = GraphScope(
        graphID: UUID(
            uuidString:
                "A1000000-0000-0000-0000-000000000001"
        )!
    )
    let firstEntity = GraphChatTypedEntityIdentity(
        id: UUID(
            uuidString:
                "A1000000-0000-0000-0000-000000000002"
        )!,
        alias: GraphEntityAlias("E1"),
        displayName: "Projekte"
    )
    let secondEntity = GraphChatTypedEntityIdentity(
        id: UUID(
            uuidString:
                "A1000000-0000-0000-0000-000000000003"
        )!,
        alias: GraphEntityAlias("E2"),
        displayName: "Personen"
    )

    var firstField: GraphChatTypedFieldIdentity {
        GraphChatTypedFieldIdentity(
            id: UUID(
                uuidString:
                    "A1000000-0000-0000-0000-000000000004"
            )!,
            alias: GraphFieldAlias("F1"),
            displayName: "Status",
            ownerEntityID: firstEntity.id,
            type: .singleChoice,
            unit: nil
        )
    }

    var firstNode: GraphChatTypedNodeIdentity {
        GraphChatTypedNodeIdentity(
            node: NodeRefKey(
                kind: .attribute,
                id: UUID(
                    uuidString:
                        "A1000000-0000-0000-0000-000000000005"
                )!
            ),
            displayName: "Projekt Atlas",
            ownerEntityID: firstEntity.id
        )
    }

    var secondNode: GraphChatTypedNodeIdentity {
        GraphChatTypedNodeIdentity(
            node: NodeRefKey(
                kind: .attribute,
                id: UUID(
                    uuidString:
                        "A1000000-0000-0000-0000-000000000006"
                )!
            ),
            displayName: "Projekt Orion",
            ownerEntityID: firstEntity.id
        )
    }

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    var scope: GraphChatTypedIntentScope {
        GraphChatTypedIntentScope(
            graphScope: graphScope,
            chatScope: chatScope,
            queryScope: chatScope
        )
    }

    var binding: GraphChatTypedIntentBinding {
        GraphChatTypedIntentBinding(
            requestID: uuid(10),
            conversationID: uuid(11),
            turnID: uuid(10),
            sourceTurnID: uuid(12),
            clarificationID: uuid(13)
        )
    }

    var resolution: GraphChatTypedIntentResolution {
        GraphChatTypedIntentResolution(
            source: .appSemanticResolution,
            origin: .appRule,
            quality: .exact
        )
    }

    var limits: GraphChatTypedIntentLimits {
        GraphChatTypedIntentLimits(
            resultLimit: 20,
            maximumResultLimit: 200,
            maximumEvidenceCount: 20,
            maximumArtifactCount: 2
        )
    }

    func allIntentFamilies() throws -> [GraphChatTypedIntent] {
        [
            try intent(
                payload: .findNodes(
                    GraphChatTypedFindNodesIntent(
                        entity: firstEntity,
                        fields: [firstField],
                        nodeScope: [firstNode]
                    )
                ),
                cardinality: .zeroOrMore
            ),
            try intent(
                payload: .entityCollection(
                    GraphChatTypedEntityCollectionIntent(
                        entity: firstEntity,
                        projectedFields: [firstField]
                    )
                ),
                cardinality: .zeroOrMore
            ),
            try intent(
                payload: .countOrGroup(
                    GraphChatTypedCountOrGroupIntent(
                        entity: firstEntity,
                        operation: .group(field: firstField)
                    )
                ),
                cardinality: .zeroOrMore
            ),
            try intent(
                payload: .nodeDetails(
                    GraphChatTypedNodeDetailsIntent(
                        entity: firstEntity,
                        node: firstNode,
                        fields: [firstField]
                    )
                ),
                cardinality: .zeroOrOne,
                factExpectation:
                    .authoritativeSingleField
            ),
            try intent(
                payload: .narrowResultSet(
                    GraphChatTypedNarrowResultSetIntent(
                        sourceResultContextID: uuid(14),
                        entity: firstEntity,
                        nodes: [firstNode],
                        fields: [firstField]
                    )
                ),
                cardinality: .zeroOrMore
            ),
            try intent(
                payload: .compareNodes(
                    GraphChatTypedCompareNodesIntent(
                        entities: [firstEntity],
                        nodes: [firstNode, secondNode],
                        fields: [firstField]
                    )
                ),
                cardinality: .twoOrMore
            ),
            try intent(
                payload: .inspectGraphState(
                    GraphChatTypedInspectGraphStateIntent(
                        entity: nil
                    )
                ),
                cardinality: .zeroOrMore
            ),
        ]
    }

    private func intent(
        payload: GraphChatTypedIntentPayload,
        cardinality:
            GraphChatTypedIntentExpectedCardinality,
        factExpectation:
            GraphChatTypedIntentFactExpectation = .none
    ) throws -> GraphChatTypedIntent {
        try GraphChatTypedIntent(
            version: .v1,
            scope: scope,
            responseLanguage: .german,
            binding: binding,
            resolution: resolution,
            expectedCardinality: cardinality,
            factExpectation: factExpectation,
            limits: limits,
            payload: payload
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString: String(
                format:
                    "A1000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    }
}

private struct FoundationalAdapterFixture {
    let graphScope = GraphScope(
        graphID: UUID(
            uuidString:
                "A2000000-0000-0000-0000-000000000001"
        )!
    )
    let entity = GraphChatFoundationalEntityIdentity(
        id: UUID(
            uuidString:
                "A2000000-0000-0000-0000-000000000002"
        )!,
        alias: GraphEntityAlias("E1"),
        displayName: "Personen"
    )
    let node = GraphChatFoundationalNodeIdentity(
        node: NodeRefKey(
            kind: .attribute,
            id: UUID(
                uuidString:
                    "A2000000-0000-0000-0000-000000000003"
            )!
        ),
        displayName: "Person X",
        ownerEntityID: UUID(
            uuidString:
                "A2000000-0000-0000-0000-000000000002"
        )!
    )
    let field = GraphChatFoundationalFieldIdentity(
        id: UUID(
            uuidString:
                "A2000000-0000-0000-0000-000000000004"
        )!,
        alias: GraphFieldAlias("F1"),
        displayName: "Geburtsdatum",
        type: .date,
        unit: nil
    )
    let binding = GraphChatFoundationalIntentBinding(
        requestID: UUID(
            uuidString:
                "A2000000-0000-0000-0000-000000000005"
        )!,
        conversationID: UUID(
            uuidString:
                "A2000000-0000-0000-0000-000000000006"
        )!,
        sourceTurnID: UUID(
            uuidString:
                "A2000000-0000-0000-0000-000000000007"
        )!,
        clarificationID: UUID(
            uuidString:
                "A2000000-0000-0000-0000-000000000008"
        )!
    )

    var singleFieldIntent: GraphChatFoundationalIntent {
        GraphChatFoundationalIntent(
            kind: .singleNodeFieldValue,
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope),
            queryScope: .node(node.node, in: graphScope),
            responseLanguage: .german,
            entity: entity,
            field: field,
            node: node,
            expectedCardinality: .zeroOrOne,
            resultLimit: 1,
            origin: .localizedFieldSynonym,
            confidence: .constrainedSynonym,
            binding: binding
        )
    }

    var collectionIntent: GraphChatFoundationalIntent {
        GraphChatFoundationalIntent(
            kind: .entityAttributeCollection,
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope),
            queryScope: .entireGraph(graphScope),
            responseLanguage: .german,
            entity: entity,
            field: nil,
            node: nil,
            expectedCardinality: .zeroOrMore,
            resultLimit:
                GraphQueryPlanLimits.maximumResultLimit,
            origin: .clarificationSelection,
            confidence: .revalidatedClarification,
            binding: binding
        )
    }
}

private struct LocalKernelExecutionFixture: Sendable {
    let graphScope = GraphScope(
        graphID: GraphChatTestSupport.graphID
    )
    let requestID = UUID(
        uuidString:
            "A3000000-0000-0000-0000-000000000001"
    )!
    let conversationID = UUID(
        uuidString:
            "A3000000-0000-0000-0000-000000000002"
    )!
    let artifactSessionID =
        GraphChatAnswerArtifactSessionID(
            rawValue: UUID(
                uuidString:
                    "A3000000-0000-0000-0000-000000000003"
            )!
        )
    let completedAt =
        Date(timeIntervalSince1970: 1_800_000_100)

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    var scopeKey: GraphChatOrchestrationScopeKey {
        GraphChatOrchestrationScopeKey(
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    var schemaContext: GraphSchemaContext {
        GraphChatTestSupport.makeSchemaContext(
            graphID: graphScope.graphID
        )
    }

    var baseState: GraphChatConversationState {
        .initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: conversationID
        )
    }

    var providerPlan: GraphChatProviderTurnPlan {
        GraphChatProviderTurnPlan(
            scopeKey: scopeKey,
            normalizedQuestion: "liste projekte",
            providerQuestion: "Liste alle Projekte auf.",
            responseLanguage: .german,
            requestBaseState: baseState,
            expectedCommittedState: baseState,
            conversationContext:
                GraphChatConversationContextBuilder()
                    .makeSnapshot(
                        from: baseState.snapshot
                    ),
            currentReference: nil,
            currentResolvedScope: nil,
            continuationOperation: nil,
            foundationalContinuation: nil
        )
    }

    var intent: GraphChatFoundationalIntent {
        GraphChatFoundationalIntent(
            kind: .entityAttributeCollection,
            graphScope: graphScope,
            chatScope: chatScope,
            queryScope: chatScope,
            responseLanguage: .german,
            entity:
                GraphChatFoundationalEntityIdentity(
                    id:
                        GraphChatTestSupport
                            .projectEntityID,
                    alias: GraphEntityAlias("E1"),
                    displayName: "Projekte"
                ),
            field: nil,
            node: nil,
            expectedCardinality: .zeroOrMore,
            resultLimit:
                GraphQueryPlanLimits.maximumResultLimit,
            origin: .schemaDisplayName,
            confidence: .exact,
            binding:
                GraphChatFoundationalIntentBinding(
                    requestID: requestID,
                    conversationID: conversationID,
                    sourceTurnID: nil,
                    clarificationID: nil
                )
        )
    }

    func executor(
        observability:
            any GraphChatObservabilityRecording,
        observer:
            GraphChatLocalIntentExecutionKernelObserver
    ) -> GraphChatFoundationalIntentExecutor {
        GraphChatFoundationalIntentExecutor(
            queryExecutor:
                LocalCollectionQueryExecutor(
                    result: queryResult
                ),
            conversationStateReducer:
                GraphChatConversationStateReducer(),
            calendar:
                Calendar(identifier: .gregorian),
            timeZone:
                TimeZone(
                    identifier: "Europe/Berlin"
                )!,
            referenceDate: { completedAt },
            observability: observability,
            kernelObserver: observer
        )
    }

    private var queryResult: GraphChatQueryResult {
        let evidence =
            GraphChatProviderTestSupport.makeEvidence(
                graphID: graphScope.graphID,
                sourceID:
                    GraphChatTestSupport
                        .projectAttributeID
            )
        return GraphChatQueryResult(
            state: .success,
            rows: [
                GraphChatQueryResultRow(
                    node: NodeRefKey(
                        kind: .attribute,
                        id:
                            GraphChatTestSupport
                                .projectAttributeID
                    ),
                    label: "Projekt Atlas",
                    cells: [],
                    evidenceIDs: [evidence.id]
                )
            ],
            aggregation: nil,
            appliedFilters: [],
            evidence: [evidence],
            resultWindow: GraphChatResultWindow(
                totalCount: 1,
                returnedCount: 1,
                limit:
                    GraphQueryPlanLimits
                        .maximumResultLimit,
                limitReached: false,
                limitSource: .query
            )
        )
    }
}

private struct LocalCollectionQueryExecutor:
    GraphChatFoundationalQueryExecuting
{
    let result: GraphChatQueryResult

    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult {
        _ = plan
        return result
    }
}

private actor CleanupReportRecorder {
    private var reports:
        [GraphChatLocalIntentCleanupReport] = []

    func record(
        _ report: GraphChatLocalIntentCleanupReport
    ) {
        reports.append(report)
    }

    func snapshot() -> [GraphChatLocalIntentCleanupReport] {
        reports
    }
}

private actor LocalIntentObservabilityRecorder:
    GraphChatObservabilityRecording
{
    private var events: [GraphChatObservabilityEvent] = []

    func record(_ event: GraphChatObservabilityEvent) {
        events.append(event)
    }

    func lifecycleEvents()
        -> [GraphChatLocalIntentLifecycleEvent]
    {
        events.compactMap { event in
            guard case .localIntent(let metric) = event else {
                return nil
            }
            return metric.event
        }
    }
}

private actor KernelCommitRecorder {
    private var value = 0

    func record() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

private enum KernelTestError: Error {
    case unexpectedFinalization
    case expectedCommitFailure
}
