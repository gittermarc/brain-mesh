import Foundation
@testable import BrainMesh

actor FakeGraphSchemaSnapshotProvider: GraphSchemaSnapshotProviding {
    private var contextsByGraphID: [UUID: GraphSchemaContext]
    private var requestedScopes: [GraphScope] = []

    init(contexts: [GraphSchemaContext]) {
        self.contextsByGraphID = Dictionary(
            uniqueKeysWithValues: contexts.map { ($0.graphScope.graphID, $0) }
        )
    }

    func makeSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) throws -> GraphSchemaContext {
        requestedScopes.append(scope)
        guard let context = contextsByGraphID[scope.graphID] else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Missing fake schema context."
            )
        }
        return context
    }

    func setContext(_ context: GraphSchemaContext) {
        contextsByGraphID[context.graphScope.graphID] = context
    }

    func requestCount() -> Int {
        requestedScopes.count
    }
}

nonisolated struct GraphChatFakeToolRunnerSnapshot: Sendable {
    let requests: [GraphChatModelToolRequest]
    let cancellationCount: Int
}

actor GraphChatFakeToolRunnerRecorder {
    private var requests: [GraphChatModelToolRequest] = []
    private var cancellationCount = 0

    func record(_ request: GraphChatModelToolRequest) {
        requests.append(request)
    }

    func recordCancellation() {
        cancellationCount += 1
    }

    func snapshot() -> GraphChatFakeToolRunnerSnapshot {
        GraphChatFakeToolRunnerSnapshot(
            requests: requests,
            cancellationCount: cancellationCount
        )
    }
}

nonisolated struct EvidenceRegisteringFakeToolRunnerFactory: GraphChatModelToolRunnerFactory {
    let recorder: GraphChatFakeToolRunnerRecorder
    let evidenceByTool: [GraphChatToolKind: [GraphEvidence]]
    let responseTextByTool: [GraphChatToolKind: String]
    let registeredKinds: Set<GraphChatToolKind>
    let delayNanoseconds: UInt64

    init(
        recorder: GraphChatFakeToolRunnerRecorder = GraphChatFakeToolRunnerRecorder(),
        evidenceByTool: [GraphChatToolKind: [GraphEvidence]] = [:],
        responseTextByTool: [GraphChatToolKind: String] = [:],
        registeredKinds: Set<GraphChatToolKind> = Set(GraphChatToolKind.allCases),
        delayNanoseconds: UInt64 = 0
    ) {
        self.recorder = recorder
        self.evidenceByTool = evidenceByTool
        self.responseTextByTool = responseTextByTool
        self.registeredKinds = registeredKinds
        self.delayNanoseconds = delayNanoseconds
    }

    func makeRunner(
        scope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        artifactRegistry: GraphChatAnswerArtifactRegistry,
        artifactTransactionID: GraphChatAnswerArtifactTransactionID,
        conversationTransaction: GraphChatConversationStateTransaction,
        conversationContext: GraphChatConversationContextSnapshot,
        referenceResolver: GraphChatConversationReferenceResolver,
        referenceDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> any GraphChatModelToolRunning {
        EvidenceRegisteringFakeToolRunner(
            scope: scope,
            budget: budget,
            evidenceRegistry: evidenceRegistry,
            conversationTransaction: conversationTransaction,
            recorder: recorder,
            evidenceByTool: evidenceByTool,
            responseTextByTool: responseTextByTool,
            registeredKinds: registeredKinds,
            delayNanoseconds: delayNanoseconds
        )
    }
}

private actor EvidenceRegisteringFakeToolRunner: GraphChatModelToolRunning {
    private let scope: GraphChatScope
    private let budget: GraphChatToolBudget
    private let evidenceRegistry: GraphChatEvidenceRegistry
    private let conversationTransaction: GraphChatConversationStateTransaction
    private let recorder: GraphChatFakeToolRunnerRecorder
    private let evidenceByTool: [GraphChatToolKind: [GraphEvidence]]
    private let responseTextByTool: [GraphChatToolKind: String]
    private let toolKinds: Set<GraphChatToolKind>
    private let delayNanoseconds: UInt64

    init(
        scope: GraphChatScope,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        conversationTransaction: GraphChatConversationStateTransaction,
        recorder: GraphChatFakeToolRunnerRecorder,
        evidenceByTool: [GraphChatToolKind: [GraphEvidence]],
        responseTextByTool: [GraphChatToolKind: String],
        registeredKinds: Set<GraphChatToolKind>,
        delayNanoseconds: UInt64
    ) {
        self.scope = scope
        self.budget = budget
        self.evidenceRegistry = evidenceRegistry
        self.conversationTransaction = conversationTransaction
        self.recorder = recorder
        self.evidenceByTool = evidenceByTool
        self.responseTextByTool = responseTextByTool
        self.toolKinds = registeredKinds
        self.delayNanoseconds = delayNanoseconds
    }

    func registeredToolKinds() -> Set<GraphChatToolKind> {
        toolKinds
    }

    func run(
        _ request: GraphChatModelToolRequest
    ) async throws -> GraphChatModelToolResponse {
        guard toolKinds.contains(request.kind) else {
            throw GraphChatToolError(
                code: .unavailable,
                message: "The fake tool is not registered."
            )
        }
        _ = try await budget.beginCall(
            tool: request.kind,
            requestedResultCount: 1,
            toolMaximumResultCount: 1
        )
        await recorder.record(request)
        do {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            await recorder.recordCancellation()
            throw GraphChatToolError.cancelled()
        }

        let evidence = evidenceByTool[request.kind, default: []]
        guard evidence.allSatisfy({ $0.sourceReference.graphID == scope.graphScope.graphID }) else {
            throw GraphChatToolError(
                code: .graphScopeMismatch,
                message: "The fake evidence belongs to another graph."
            )
        }
        try await evidenceRegistry.register(evidence)
        try await budget.consumeEvidence(evidence.count)
        try await conversationTransaction.apply(
            GraphChatConversationTrustedEvent(
                graphScope: scope.graphScope,
                chatScope: scope,
                payload: .validatedEvidence(
                    tool: request.kind,
                    state: evidence.isEmpty ? .noEvidence : .success,
                    evidence: evidence
                )
            )
        )
        return GraphChatModelToolResponse(
            tool: request.kind,
            state: evidence.isEmpty ? .noEvidence : .success,
            content: responseTextByTool[request.kind] ?? "Fake read-only result.",
            evidenceIDs: evidence.map(\.id)
        )
    }
}

nonisolated enum GraphChatProviderTestSupport {
    static func makeEvidence(
        graphID: UUID = GraphChatTestSupport.graphID,
        sourceID: UUID = UUID(),
        summary: String = "Validated fake evidence"
    ) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphID,
                sourceKind: .entity,
                sourceID: sourceID
            ),
            summary: summary,
            identitySuffix: sourceID.uuidString
        )
    }

    static func makeFinalAnswer(
        responseState: GraphChatProviderResponseState = .answer,
        directAnswer: String = "Validated answer",
        evidenceIDs: [GraphEvidenceID] = [],
        artifactIDs: [GraphChatAnswerArtifactID] = [],
        sections: [GraphChatProviderAnswerSection] = [],
        appliedFilters: [GraphChatProviderAppliedFilter] = [],
        followUpSuggestions: [GraphChatProviderFollowUpSuggestion] = [],
        hasInsufficientEvidence: Bool = false,
        referenceProposal: GraphChatConversationReferenceProposal? = nil,
        clarificationQuestion: String? = nil,
        clarificationOptionAliases: [String] = [],
        unsupportedCapability: GraphChatUnsupportedCapability? = nil
    ) -> GraphChatProviderFinalAnswer {
        GraphChatProviderFinalAnswer(
            responseState: responseState,
            directAnswer: directAnswer,
            sections: sections,
            evidenceIDValues: evidenceIDs.map { $0.rawValue.uuidString },
            artifactIDValues: artifactIDs.map { $0.rawValue.uuidString },
            appliedFilters: appliedFilters,
            followUpSuggestions: followUpSuggestions,
            hasInsufficientEvidence: hasInsufficientEvidence,
            referenceProposal: referenceProposal,
            clarificationQuestion: clarificationQuestion,
            clarificationOptionAliases: clarificationOptionAliases,
            unsupportedCapability: unsupportedCapability
        )
    }

    static func makeOrchestrator(
        provider: any GraphChatModelProvider,
        factory: any GraphChatModelToolRunnerFactory,
        graphIDs: [UUID] = [GraphChatTestSupport.graphID],
        budgetPolicy: GraphChatToolBudgetPolicy = .default,
        conversationStatePolicy: GraphChatConversationStatePolicy = .default,
        referenceResolver: GraphChatConversationReferenceResolver = GraphChatConversationReferenceResolver(),
        responseLanguageSelector: GraphChatResponseLanguageSelector = GraphChatResponseLanguageSelector(fallback: .german)
    ) -> GraphChatOrchestrator {
        let contexts = graphIDs.map { GraphChatTestSupport.makeSchemaContext(graphID: $0) }
        return GraphChatOrchestrator(
            provider: provider,
            schemaProvider: FakeGraphSchemaSnapshotProvider(contexts: contexts),
            toolRunnerFactory: factory,
            toolBudgetPolicy: budgetPolicy,
            conversationStatePolicy: conversationStatePolicy,
            referenceResolver: referenceResolver,
            responseLanguageSelector: responseLanguageSelector,
            referenceDate: { Date(timeIntervalSince1970: 1_735_732_800) },
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "Europe/Berlin")!
        )
    }

    static func collect(
        _ stream: GraphChatEventStream
    ) async -> [GraphChatStreamEvent] {
        var events: [GraphChatStreamEvent] = []
        for await event in stream {
            events.append(event)
        }
        return events
    }

    static func waitUntil(
        maximumYields: Int = 1_000,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<maximumYields {
            if await condition() {
                return
            }
            await Task.yield()
        }
    }
}

extension GraphChatProviderTestSupport {
    @MainActor
    static func makeRealRuntimeFactory(
        store: BrainMeshTestStore,
        schemaService: GraphSchemaService,
        repository: GraphReadRepository
    ) -> GraphChatModelToolRuntimeFactory {
        let validator = GraphEvidenceSourceValidator(repository: repository)
        let noOpLogger = NoOpGraphChatToolLogger()
        return GraphChatModelToolRuntimeFactory(
            describeSchemaTool: DescribeGraphSchemaTool(
                schemaService: schemaService,
                evidenceValidator: validator,
                logger: noOpLogger
            ),
            searchGraphTool: SearchGraphTool(logger: noOpLogger),
            queryDetailValuesTool: QueryDetailValuesTool(
                queryEngine: GraphChatQueryEngine(
                    repository: repository,
                    evidenceValidator: validator
                ),
                logger: noOpLogger
            ),
            getNodeTool: GetNodeTool(
                repository: repository,
                evidenceValidator: validator,
                logger: noOpLogger
            ),
            getNeighborsTool: GetNeighborsTool(
                repository: NodeRepository(
                    container: AnyModelContainer(store.container)
                ),
                evidenceValidator: validator,
                logger: noOpLogger
            ),
            graphStatsTool: GraphStatsTool(
                reader: GraphStatsServiceReader(
                    container: AnyModelContainer(store.container)
                ),
                evidenceValidator: validator,
                logger: noOpLogger
            )
        )
    }

    static func providerFilters(
        _ filters: [GraphChatAppliedFilter]
    ) -> [GraphChatProviderAppliedFilter] {
        filters.map { filter in
            GraphChatProviderAppliedFilter(
                fieldName: filter.fieldName,
                operationDescription: filter.operationDescription,
                valueDescription: filter.valueDescription
            )
        }
    }
}
