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

actor GraphChatFakeToolExecutionGate {
    private var isReleased = false

    func waitUntilReleased() async throws {
        while isReleased == false {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        try Task.checkCancellation()
    }

    func release() {
        isReleased = true
    }
}

actor GraphChatFakeToolRunnerRecorder {
    private struct RequestWaiter {
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var requests: [GraphChatModelToolRequest] = []
    private var cancellationCount = 0
    private var requestWaiters: [RequestWaiter] = []

    func record(_ request: GraphChatModelToolRequest) {
        requests.append(request)
        resumeSatisfiedRequestWaiters()
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

    func waitUntilRequestCount(_ minimumCount: Int) async {
        guard requests.count < minimumCount else {
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters.append(
                RequestWaiter(
                    minimumCount: minimumCount,
                    continuation: continuation
                )
            )
        }
    }

    private func resumeSatisfiedRequestWaiters() {
        var pending: [RequestWaiter] = []
        for waiter in requestWaiters {
            if requests.count >= waiter.minimumCount {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        requestWaiters = pending
    }
}

nonisolated struct EvidenceRegisteringFakeToolRunnerFactory: GraphChatModelToolRunnerFactory {
    let recorder: GraphChatFakeToolRunnerRecorder
    let executionGate: GraphChatFakeToolExecutionGate?
    let evidenceByTool: [GraphChatToolKind: [GraphEvidence]]
    let responseTextByTool: [GraphChatToolKind: String]
    let artifactDraftsByTool: [GraphChatToolKind: [GraphChatAnswerArtifactDraft]]
    let registeredKinds: Set<GraphChatToolKind>
    let registeredIdentifiers: Set<String>?
    let delayNanoseconds: UInt64

    init(
        recorder: GraphChatFakeToolRunnerRecorder = GraphChatFakeToolRunnerRecorder(),
        executionGate: GraphChatFakeToolExecutionGate? = nil,
        evidenceByTool: [GraphChatToolKind: [GraphEvidence]] = [:],
        responseTextByTool: [GraphChatToolKind: String] = [:],
        artifactDraftsByTool: [GraphChatToolKind: [GraphChatAnswerArtifactDraft]] = [:],
        registeredKinds: Set<GraphChatToolKind> = Set(GraphChatToolKind.allCases),
        registeredIdentifiers: Set<String>? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.recorder = recorder
        self.executionGate = executionGate
        self.evidenceByTool = evidenceByTool
        self.responseTextByTool = responseTextByTool
        self.artifactDraftsByTool = artifactDraftsByTool
        self.registeredKinds = registeredKinds
        self.registeredIdentifiers = registeredIdentifiers
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
        responseLanguage: GraphChatResponseLanguage,
        referenceDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> any GraphChatModelToolRunning {
        EvidenceRegisteringFakeToolRunner(
            scope: scope,
            budget: budget,
            evidenceRegistry: evidenceRegistry,
            artifactRegistry: artifactRegistry,
            artifactTransactionID: artifactTransactionID,
            conversationTransaction: conversationTransaction,
            recorder: recorder,
            executionGate: executionGate,
            evidenceByTool: evidenceByTool,
            responseTextByTool: responseTextByTool,
            artifactDraftsByTool: artifactDraftsByTool,
            registeredKinds: registeredKinds,
            registeredIdentifiers: registeredIdentifiers,
            delayNanoseconds: delayNanoseconds
        )
    }
}

private actor EvidenceRegisteringFakeToolRunner: GraphChatModelToolRunning {
    private let scope: GraphChatScope
    private let budget: GraphChatToolBudget
    private let evidenceRegistry: GraphChatEvidenceRegistry
    private let artifactRegistry: GraphChatAnswerArtifactRegistry
    private let artifactTransactionID: GraphChatAnswerArtifactTransactionID
    private let conversationTransaction: GraphChatConversationStateTransaction
    private let recorder: GraphChatFakeToolRunnerRecorder
    private let executionGate: GraphChatFakeToolExecutionGate?
    private let evidenceByTool: [GraphChatToolKind: [GraphEvidence]]
    private let responseTextByTool: [GraphChatToolKind: String]
    private let artifactDraftsByTool: [GraphChatToolKind: [GraphChatAnswerArtifactDraft]]
    private let toolKinds: Set<GraphChatToolKind>
    private let toolIdentifiers: Set<String>?
    private let delayNanoseconds: UInt64

    init(
        scope: GraphChatScope,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        artifactRegistry: GraphChatAnswerArtifactRegistry,
        artifactTransactionID: GraphChatAnswerArtifactTransactionID,
        conversationTransaction: GraphChatConversationStateTransaction,
        recorder: GraphChatFakeToolRunnerRecorder,
        executionGate: GraphChatFakeToolExecutionGate?,
        evidenceByTool: [GraphChatToolKind: [GraphEvidence]],
        responseTextByTool: [GraphChatToolKind: String],
        artifactDraftsByTool: [GraphChatToolKind: [GraphChatAnswerArtifactDraft]],
        registeredKinds: Set<GraphChatToolKind>,
        registeredIdentifiers: Set<String>?,
        delayNanoseconds: UInt64
    ) {
        self.scope = scope
        self.budget = budget
        self.evidenceRegistry = evidenceRegistry
        self.artifactRegistry = artifactRegistry
        self.artifactTransactionID = artifactTransactionID
        self.conversationTransaction = conversationTransaction
        self.recorder = recorder
        self.executionGate = executionGate
        self.evidenceByTool = evidenceByTool
        self.responseTextByTool = responseTextByTool
        self.artifactDraftsByTool = artifactDraftsByTool
        self.toolKinds = registeredKinds
        self.toolIdentifiers = registeredIdentifiers
        self.delayNanoseconds = delayNanoseconds
    }

    func registeredToolKinds() -> Set<GraphChatToolKind> {
        toolKinds
    }

    func registeredToolIdentifiers() -> Set<String> {
        toolIdentifiers ?? Set(toolKinds.map(\.rawValue))
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
            if let executionGate {
                try await executionGate.waitUntilReleased()
            }
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
        var artifactIDs: [GraphChatAnswerArtifactID] = []
        for draft in artifactDraftsByTool[request.kind, default: []] {
            try Task.checkCancellation()
            artifactIDs.append(
                try await artifactRegistry.stage(
                    draft,
                    transactionID: artifactTransactionID,
                    evidenceRegistry: evidenceRegistry
                )
            )
        }
        return GraphChatModelToolResponse(
            tool: request.kind,
            state: evidence.isEmpty ? .noEvidence : .success,
            content: responseTextByTool[request.kind] ?? "Fake read-only result.",
            evidenceIDs: evidence.map(\.id),
            artifactIDs: artifactIDs
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
        responseLanguageSelector: GraphChatResponseLanguageSelector = GraphChatResponseLanguageSelector(fallback: .german),
        artifactRevalidator: any GraphChatAnswerArtifactRevalidating = GraphChatLiveAnswerArtifactRevalidator(),
        evidenceValidator: any GraphEvidenceValidating = PassthroughGraphEvidenceValidator()
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
            artifactRevalidator: artifactRevalidator,
            evidenceValidator: evidenceValidator,
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
    static func makeProviderSessionFactory(
        provider: any GraphChatModelProvider,
        schemaProvider: any GraphSchemaSnapshotProviding,
        toolRunnerFactory: any GraphChatModelToolRunnerFactory,
        budgetPolicy: GraphChatToolBudgetPolicy = .default
    ) -> GraphChatProviderSessionFactory {
        GraphChatProviderSessionFactory(
            provider: provider,
            schemaProvider: schemaProvider,
            toolRunnerFactory: toolRunnerFactory,
            standardToolBudgetPolicy: budgetPolicy,
            conversationStateReducer: GraphChatConversationStateReducer(),
            referenceResolver: GraphChatConversationReferenceResolver(),
            requestBuilder: GraphChatProviderRequestBuilder(),
            errorMapper: GraphChatProviderErrorMapper(),
            referenceDate: { Date(timeIntervalSince1970: 1_735_732_800) },
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "Europe/Berlin")!
        )
    }

    static func makeProviderAttemptInput(
        graphID: UUID = GraphChatTestSupport.graphID,
        chatScope: GraphChatScope? = nil
    ) -> (
        key: GraphChatOrchestrationScopeKey,
        artifactSession: GraphChatArtifactSessionResources,
        baseState: GraphChatConversationState,
        context: GraphChatConversationContextSnapshot
    ) {
        let graphScope = GraphScope(graphID: graphID)
        let resolvedChatScope = chatScope ?? .entireGraph(graphScope)
        let key = GraphChatOrchestrationScopeKey(
            graphScope: graphScope,
            chatScope: resolvedChatScope
        )
        let artifactSessionID = GraphChatAnswerArtifactSessionID()
        let artifactSession = GraphChatArtifactSessionResources(
            key: key,
            sessionID: artifactSessionID,
            registry: GraphChatAnswerArtifactRegistry(
                graphScope: graphScope,
                scope: resolvedChatScope,
                sessionID: artifactSessionID
            )
        )
        let baseState = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: resolvedChatScope,
            resetReason: .newConversation
        )
        let context = GraphChatConversationContextBuilder().makeSnapshot(
            from: baseState.snapshot
        )
        return (key, artifactSession, baseState, context)
    }

    static func makeInitialProviderResources(
        sessionFactory: GraphChatProviderSessionFactory,
        graphID: UUID = GraphChatTestSupport.graphID,
        chatScope: GraphChatScope? = nil,
        responseLanguage: GraphChatResponseLanguage = .english
    ) async throws -> GraphChatProviderSessionResources {
        let input = makeProviderAttemptInput(
            graphID: graphID,
            chatScope: chatScope
        )
        return try await sessionFactory.makeInitialSession(
            for: input.key,
            artifactSession: input.artifactSession,
            conversationBaseState: input.baseState,
            conversationContext: input.context,
            responseLanguage: responseLanguage
        )
    }

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
