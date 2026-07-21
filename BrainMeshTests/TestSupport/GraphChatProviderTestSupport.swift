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
        referenceDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> any GraphChatModelToolRunning {
        EvidenceRegisteringFakeToolRunner(
            scope: scope,
            budget: budget,
            evidenceRegistry: evidenceRegistry,
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
    private let recorder: GraphChatFakeToolRunnerRecorder
    private let evidenceByTool: [GraphChatToolKind: [GraphEvidence]]
    private let responseTextByTool: [GraphChatToolKind: String]
    private let toolKinds: Set<GraphChatToolKind>
    private let delayNanoseconds: UInt64

    init(
        scope: GraphChatScope,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        recorder: GraphChatFakeToolRunnerRecorder,
        evidenceByTool: [GraphChatToolKind: [GraphEvidence]],
        responseTextByTool: [GraphChatToolKind: String],
        registeredKinds: Set<GraphChatToolKind>,
        delayNanoseconds: UInt64
    ) {
        self.scope = scope
        self.budget = budget
        self.evidenceRegistry = evidenceRegistry
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
        directAnswer: String = "Validated answer",
        evidenceIDs: [GraphEvidenceID] = [],
        sections: [GraphChatProviderAnswerSection] = [],
        hasInsufficientEvidence: Bool = false
    ) -> GraphChatProviderFinalAnswer {
        GraphChatProviderFinalAnswer(
            directAnswer: directAnswer,
            sections: sections,
            evidenceIDValues: evidenceIDs.map { $0.rawValue.uuidString },
            appliedFilters: [],
            followUpSuggestions: [],
            hasInsufficientEvidence: hasInsufficientEvidence
        )
    }

    static func makeOrchestrator(
        provider: any GraphChatModelProvider,
        factory: any GraphChatModelToolRunnerFactory,
        graphIDs: [UUID] = [GraphChatTestSupport.graphID],
        budgetPolicy: GraphChatToolBudgetPolicy = .default
    ) -> GraphChatOrchestrator {
        let contexts = graphIDs.map { GraphChatTestSupport.makeSchemaContext(graphID: $0) }
        return GraphChatOrchestrator(
            provider: provider,
            schemaProvider: FakeGraphSchemaSnapshotProvider(contexts: contexts),
            toolRunnerFactory: factory,
            toolBudgetPolicy: budgetPolicy,
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
