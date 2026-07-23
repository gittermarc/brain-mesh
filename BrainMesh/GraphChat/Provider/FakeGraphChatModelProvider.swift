//
//  FakeGraphChatModelProvider.swift
//  BrainMesh
//
//  Fully deterministic provider and tool doubles for unit tests.
//

import Foundation

nonisolated enum FakeGraphChatProviderStep: Sendable {
    case event(GraphChatProviderStreamEvent)
    case toolRequest(GraphChatModelToolRequest)
    case failure(GraphChatProviderError)
    case waitForCancellation
}

nonisolated struct FakeGraphChatProviderScript: Sendable {
    let steps: [FakeGraphChatProviderStep]
    let delayNanoseconds: UInt64

    init(
        steps: [FakeGraphChatProviderStep],
        delayNanoseconds: UInt64 = 0
    ) {
        self.steps = steps
        self.delayNanoseconds = delayNanoseconds
    }
}

nonisolated struct FakeGraphChatModelProviderSnapshot: Sendable {
    let createdSessions: [GraphChatModelSessionID]
    let prewarmedSessions: [GraphChatModelSessionID]
    let streamedSessions: [GraphChatModelSessionID]
    let cancelledSessions: [GraphChatModelSessionID]
    let discardedSessions: [GraphChatModelSessionID]
    let sessionConfigurations: [GraphChatModelSessionID: GraphChatModelSessionConfiguration]
    let streamedRequests: [GraphChatModelRequest]
    let toolResponses: [GraphChatModelToolResponse]
}

actor FakeGraphChatModelProvider: GraphChatModelProvider {
    private struct SessionState: Sendable {
        let configuration: GraphChatModelSessionConfiguration
        var generationTask: Task<Void, Never>?
    }

    private var currentAvailability: GraphChatModelAvailability
    private var queuedScripts: [FakeGraphChatProviderScript]
    private var sessions: [GraphChatModelSessionID: SessionState] = [:]
    private var createdSessions: [GraphChatModelSessionID] = []
    private var prewarmedSessions: [GraphChatModelSessionID] = []
    private var streamedSessions: [GraphChatModelSessionID] = []
    private var cancelledSessions: [GraphChatModelSessionID] = []
    private var discardedSessions: [GraphChatModelSessionID] = []
    private var sessionConfigurations: [GraphChatModelSessionID: GraphChatModelSessionConfiguration] = [:]
    private var streamedRequests: [GraphChatModelRequest] = []
    private var toolResponses: [GraphChatModelToolResponse] = []

    init(
        availability: GraphChatModelAvailability = .available,
        scripts: [FakeGraphChatProviderScript] = []
    ) {
        self.currentAvailability = availability
        self.queuedScripts = scripts
    }

    func availability() -> GraphChatModelAvailability {
        currentAvailability
    }

    func setAvailability(_ availability: GraphChatModelAvailability) {
        currentAvailability = availability
    }

    func enqueue(_ script: FakeGraphChatProviderScript) {
        queuedScripts.append(script)
    }

    func createSession(
        configuration: GraphChatModelSessionConfiguration
    ) throws -> GraphChatModelSessionID {
        guard currentAvailability.isAvailable else {
            throw GraphChatProviderError(
                code: .unavailable,
                message: "Das Fake-Modell ist nicht verfügbar."
            )
        }
        let id = GraphChatModelSessionID()
        sessions[id] = SessionState(
            configuration: configuration,
            generationTask: nil
        )
        createdSessions.append(id)
        sessionConfigurations[id] = configuration
        return id
    }

    func prewarm(
        sessionID: GraphChatModelSessionID,
        promptPrefix: String?
    ) throws {
        guard sessions[sessionID] != nil else {
            throw invalidSession()
        }
        prewarmedSessions.append(sessionID)
    }

    func streamResponse(
        sessionID: GraphChatModelSessionID,
        request: GraphChatModelRequest
    ) throws -> GraphChatProviderEventStream {
        guard var session = sessions[sessionID] else {
            throw invalidSession()
        }
        guard session.generationTask == nil else {
            throw GraphChatProviderError(
                code: .concurrentRequest,
                message: "Für diese Session läuft bereits eine Fake-Generierung."
            )
        }
        let script = queuedScripts.isEmpty
            ? FakeGraphChatProviderScript(steps: [])
            : queuedScripts.removeFirst()
        streamedSessions.append(sessionID)
        streamedRequests.append(request)

        var continuationReference: GraphChatProviderEventStream.Continuation?
        let stream = GraphChatProviderEventStream { continuation in
            continuationReference = continuation
        }
        guard let continuation = continuationReference else {
            throw GraphChatProviderError(
                code: .unexpected,
                message: "Der Fake-Stream konnte nicht initialisiert werden."
            )
        }

        let runner = session.configuration.toolRunner
        let task = Task {
            do {
                for step in script.steps {
                    try Task.checkCancellation()
                    if script.delayNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: script.delayNanoseconds)
                    }
                    switch step {
                    case .event(let event):
                        continuation.yield(event)
                    case .toolRequest(let toolRequest):
                        let activityID = UUID()
                        continuation.yield(
                            .toolActivity(
                                GraphChatToolActivity(
                                    id: activityID,
                                    tool: toolRequest.kind,
                                    state: .started
                                )
                            )
                        )
                        let response = try await runner.run(toolRequest)
                        toolResponses.append(response)
                        continuation.yield(
                            .toolActivity(
                                GraphChatToolActivity(
                                    id: activityID,
                                    tool: toolRequest.kind,
                                    state: .finished
                                )
                            )
                        )
                    case .failure(let error):
                        throw error
                    case .waitForCancellation:
                        try await Task.sleep(nanoseconds: UInt64.max)
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: GraphChatProviderError.cancelled())
            } catch {
                continuation.finish(throwing: error)
            }
            self.generationFinished(sessionID: sessionID)
        }
        session.generationTask = task
        sessions[sessionID] = session
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return stream
    }

    func cancelGeneration(sessionID: GraphChatModelSessionID) {
        guard let task = sessions[sessionID]?.generationTask else {
            return
        }
        cancelledSessions.append(sessionID)
        task.cancel()
    }

    func discardSession(sessionID: GraphChatModelSessionID) {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }
        session.generationTask?.cancel()
        discardedSessions.append(sessionID)
    }

    func snapshot() -> FakeGraphChatModelProviderSnapshot {
        FakeGraphChatModelProviderSnapshot(
            createdSessions: createdSessions,
            prewarmedSessions: prewarmedSessions,
            streamedSessions: streamedSessions,
            cancelledSessions: cancelledSessions,
            discardedSessions: discardedSessions,
            sessionConfigurations: sessionConfigurations,
            streamedRequests: streamedRequests,
            toolResponses: toolResponses
        )
    }

    private func generationFinished(sessionID: GraphChatModelSessionID) {
        guard var session = sessions[sessionID] else {
            return
        }
        session.generationTask = nil
        sessions[sessionID] = session
    }

    private func invalidSession() -> GraphChatProviderError {
        GraphChatProviderError(
            code: .invalidSession,
            message: "Die Fake-Modell-Session existiert nicht mehr."
        )
    }
}

nonisolated struct FakeGraphChatModelToolRunnerSnapshot: Sendable {
    let requests: [GraphChatModelToolRequest]
    let cancellationCount: Int
}

actor FakeGraphChatModelToolRunner: GraphChatModelToolRunning {
    private let toolKinds: Set<GraphChatToolKind>
    private let maximumCalls: Int?
    private let delayNanoseconds: UInt64
    private var responses: [GraphChatToolKind: GraphChatModelToolResponse]
    private var requests: [GraphChatModelToolRequest] = []
    private var cancellationCount = 0

    init(
        toolKinds: Set<GraphChatToolKind> = Set(GraphChatToolKind.allCases),
        responses: [GraphChatToolKind: GraphChatModelToolResponse] = [:],
        maximumCalls: Int? = nil,
        delayNanoseconds: UInt64 = 0
    ) {
        self.toolKinds = toolKinds
        self.responses = responses
        self.maximumCalls = maximumCalls
        self.delayNanoseconds = delayNanoseconds
    }

    func registeredToolKinds() -> Set<GraphChatToolKind> {
        toolKinds
    }

    func setResponse(
        _ response: GraphChatModelToolResponse,
        for tool: GraphChatToolKind
    ) {
        responses[tool] = response
    }

    func run(
        _ request: GraphChatModelToolRequest
    ) async throws -> GraphChatModelToolResponse {
        guard toolKinds.contains(request.kind) else {
            throw GraphChatToolError(
                code: .unavailable,
                message: "Das Fake-Tool ist nicht registriert."
            )
        }
        if let maximumCalls, requests.count >= maximumCalls {
            throw GraphChatToolError(
                code: .budgetExceeded,
                message: "Das Fake-Tool-Budget wurde erreicht."
            )
        }
        requests.append(request)
        do {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            cancellationCount += 1
            throw GraphChatToolError.cancelled()
        }
        return responses[request.kind] ?? GraphChatModelToolResponse(
            tool: request.kind,
            state: .noResults,
            content: "Keine Fake-Ergebnisse.",
            evidenceIDs: []
        )
    }

    func snapshot() -> FakeGraphChatModelToolRunnerSnapshot {
        FakeGraphChatModelToolRunnerSnapshot(
            requests: requests,
            cancellationCount: cancellationCount
        )
    }
}

nonisolated struct FakeGraphChatModelToolRunnerFactory: GraphChatModelToolRunnerFactory {
    let runner: any GraphChatModelToolRunning

    init(runner: any GraphChatModelToolRunning) {
        self.runner = runner
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
        runner
    }
}
