//
//  FoundationModelsGraphChatProvider.swift
//  BrainMesh
//
//  On-device Foundation Models provider for iOS 26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@Generable
private nonisolated struct FoundationGraphChatGeneratedSection {
    @Guide(description: "Short optional section title. Use an empty string when no title is needed.")
    var title: String

    @Guide(description: "Section text based only on tool results.")
    var text: String

    @Guide(description: "Evidence UUID strings that were present in tool results.", .maximumCount(20))
    var evidenceIDs: [String]
}

@Generable
private nonisolated struct FoundationGraphChatGeneratedFilter {
    @Guide(description: "Human-readable field name from the validated query result.")
    var fieldName: String

    @Guide(description: "Human-readable filter operation from the validated query result.")
    var operationDescription: String

    @Guide(description: "Human-readable filter value. Use an empty string when no value exists.")
    var valueDescription: String
}

@Generable
private nonisolated struct FoundationGraphChatGeneratedFollowUp {
    @Guide(description: "Short title for a safe read-only follow-up question.")
    var title: String

    @Guide(description: "Complete follow-up prompt that asks only for read-only graph information.")
    var prompt: String
}

@Generable
private nonisolated struct FoundationGraphChatGeneratedAnswer {
    @Guide(description: "Direct concise answer based only on tool results.")
    var directAnswer: String

    @Guide(description: "Optional supporting answer sections.", .maximumCount(6))
    var sections: [FoundationGraphChatGeneratedSection]

    @Guide(description: "All Evidence UUID strings used by the direct answer and sections.", .maximumCount(40))
    var evidenceIDs: [String]

    @Guide(description: "Filters reported by deterministic tools.", .maximumCount(12))
    var appliedFilters: [FoundationGraphChatGeneratedFilter]

    @Guide(description: "Optional read-only follow-up suggestions.", .maximumCount(3))
    var followUps: [FoundationGraphChatGeneratedFollowUp]

    @Guide(description: "True when tool results do not contain enough evidence for a reliable answer.")
    var hasInsufficientEvidence: Bool
}

private actor FoundationGraphChatToolActivityReporter {
    private var continuation: GraphChatProviderEventStream.Continuation?

    func attach(_ continuation: GraphChatProviderEventStream.Continuation) {
        self.continuation = continuation
    }

    func detach() {
        continuation = nil
    }

    func start(_ tool: GraphChatToolKind) -> UUID {
        let id = UUID()
        continuation?.yield(
            .toolActivity(
                GraphChatToolActivity(
                    id: id,
                    tool: tool,
                    state: .started
                )
            )
        )
        return id
    }

    func finish(_ tool: GraphChatToolKind, id: UUID) {
        continuation?.yield(
            .toolActivity(
                GraphChatToolActivity(
                    id: id,
                    tool: tool,
                    state: .finished
                )
            )
        )
    }
}

private nonisolated struct FoundationDescribeGraphSchemaTool: Tool {
    let name = "describeGraphSchema"
    let description = "Read the compact active graph schema and its E and F aliases."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "F aliases for which examples are useful.", .maximumCount(8))
        var exampleFieldAliases: [String]
    }

    let runner: any GraphChatModelToolRunning
    let reporter: FoundationGraphChatToolActivityReporter

    func call(arguments: Arguments) async throws -> String {
        try await callTool(
            request: .describeSchema(exampleFieldAliases: arguments.exampleFieldAliases),
            runner: runner,
            reporter: reporter
        )
    }
}

private nonisolated struct FoundationSearchGraphTool: Tool {
    let name = "searchGraph"
    let description = "Search the active graph and return compact node aliases plus validated Evidence IDs."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Short search text for labels, notes, details, links, or attachment metadata.")
        var query: String

        @Guide(description: "Maximum number of results.", .range(1...20))
        var limit: Int
    }

    let runner: any GraphChatModelToolRunning
    let reporter: FoundationGraphChatToolActivityReporter

    func call(arguments: Arguments) async throws -> String {
        try await callTool(
            request: .searchGraph(query: arguments.query, limit: arguments.limit),
            runner: runner,
            reporter: reporter
        )
    }
}

@Generable
private nonisolated struct FoundationGraphChatQueryFilterArguments {
    @Guide(description: "F alias from describeGraphSchema.")
    var fieldAlias: String

    @Guide(description: "One supported operator: contains, equals, startsWith, isPresent, isMissing, lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual, between, before, after, inYear, inMonth, isOverdue, or oneOf.")
    var operation: String

    @Guide(description: "Primary scalar value. Use an empty string when the operation has no value.")
    var value: String

    @Guide(description: "Second boundary for between. Use an empty string otherwise.")
    var secondValue: String

    @Guide(description: "Choice values for oneOf. Use an empty array otherwise.", .maximumCount(12))
    var values: [String]
}

private nonisolated struct FoundationQueryDetailValuesTool: Tool {
    let name = "queryDetailValues"
    let description = "Run a validated deterministic query using only E and F aliases within the active scope."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "E alias from describeGraphSchema.")
        var entityAlias: String

        @Guide(description: "Validated filters for this query.", .maximumCount(8))
        var filters: [FoundationGraphChatQueryFilterArguments]

        @Guide(description: "nodeName or an F alias. Use an empty string for no sorting.")
        var sortFieldAlias: String

        @Guide(description: "ascending or descending. Use an empty string for the default.")
        var sortDirection: String

        @Guide(description: "F aliases to return in addition to node identity.", .maximumCount(12))
        var projectionFieldAliases: [String]

        @Guide(description: "count, groupCount, minimum, maximum, or an empty string.")
        var aggregation: String

        @Guide(description: "F alias for groupCount, minimum, or maximum. Use an empty string otherwise.")
        var aggregationFieldAlias: String

        @Guide(description: "Maximum number of rows.", .range(1...50))
        var limit: Int
    }

    let runner: any GraphChatModelToolRunning
    let reporter: FoundationGraphChatToolActivityReporter

    func call(arguments: Arguments) async throws -> String {
        let filters = arguments.filters.map { filter in
            GraphChatModelQueryFilterRequest(
                fieldAlias: filter.fieldAlias,
                operation: filter.operation,
                value: nilIfEmpty(filter.value),
                secondValue: nilIfEmpty(filter.secondValue),
                values: filter.values
            )
        }
        let request = GraphChatModelQueryRequest(
            entityAlias: arguments.entityAlias,
            filters: filters,
            sortFieldAlias: nilIfEmpty(arguments.sortFieldAlias),
            sortDirection: nilIfEmpty(arguments.sortDirection),
            projectionFieldAliases: arguments.projectionFieldAliases,
            aggregation: nilIfEmpty(arguments.aggregation),
            aggregationFieldAlias: nilIfEmpty(arguments.aggregationFieldAlias),
            limit: arguments.limit
        )
        return try await callTool(
            request: .queryDetailValues(request),
            runner: runner,
            reporter: reporter
        )
    }
}

private nonisolated struct FoundationGetNodeTool: Tool {
    let name = "getNode"
    let description = "Read one previously returned E or N node alias, including typed values and attachment metadata only."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "E or N alias previously supplied by a tool.")
        var nodeAlias: String

        @Guide(description: "Maximum number of related detail, link, and attachment metadata records.", .range(0...30))
        var relatedLimit: Int
    }

    let runner: any GraphChatModelToolRunning
    let reporter: FoundationGraphChatToolActivityReporter

    func call(arguments: Arguments) async throws -> String {
        try await callTool(
            request: .getNode(
                nodeAlias: arguments.nodeAlias,
                relatedLimit: arguments.relatedLimit
            ),
            runner: runner,
            reporter: reporter
        )
    }
}

private nonisolated struct FoundationGetNeighborsTool: Tool {
    let name = "getNeighbors"
    let description = "Read direct incoming and outgoing neighbors for a previously returned E or N node alias."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "E or N alias previously supplied by a tool.")
        var nodeAlias: String

        @Guide(description: "Maximum number of direct neighbors.", .range(0...30))
        var limit: Int
    }

    let runner: any GraphChatModelToolRunning
    let reporter: FoundationGraphChatToolActivityReporter

    func call(arguments: Arguments) async throws -> String {
        try await callTool(
            request: .getNeighbors(
                nodeAlias: arguments.nodeAlias,
                limit: arguments.limit
            ),
            runner: runner,
            reporter: reporter
        )
    }
}

private nonisolated struct FoundationGraphStatsTool: Tool {
    let name = "graphStats"
    let description = "Read bounded statistics for the entire active graph. Do not use for entity, node, or selection scopes."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Maximum number of high-degree nodes.", .range(0...25))
        var hubLimit: Int
    }

    let runner: any GraphChatModelToolRunning
    let reporter: FoundationGraphChatToolActivityReporter

    func call(arguments: Arguments) async throws -> String {
        try await callTool(
            request: .graphStats(hubLimit: arguments.hubLimit),
            runner: runner,
            reporter: reporter
        )
    }
}

private nonisolated func callTool(
    request: GraphChatModelToolRequest,
    runner: any GraphChatModelToolRunning,
    reporter: FoundationGraphChatToolActivityReporter
) async throws -> String {
    let activityID = await reporter.start(request.kind)
    do {
        let response = try await runner.run(request)
        await reporter.finish(request.kind, id: activityID)
        return response.content
    } catch {
        await reporter.finish(request.kind, id: activityID)
        throw error
    }
}

private nonisolated func nilIfEmpty(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

actor FoundationModelsGraphChatProvider: GraphChatModelProvider {
    private struct SessionState {
        let session: LanguageModelSession
        let configuration: GraphChatModelSessionConfiguration
        let reporter: FoundationGraphChatToolActivityReporter
        var generationTask: Task<Void, Never>?
    }

    private var sessions: [GraphChatModelSessionID: SessionState] = [:]

    func availability() -> GraphChatModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.unknown)
            }
        }
    }

    func createSession(
        configuration: GraphChatModelSessionConfiguration
    ) async throws -> GraphChatModelSessionID {
        guard availability().isAvailable else {
            throw GraphChatProviderError(
                code: .unavailable,
                message: "Das lokale Foundation Model ist auf diesem Gerät nicht verfügbar."
            )
        }
        guard configuration.graphScope == configuration.chatScope.graphScope,
              configuration.schemaContext.graphScope == configuration.graphScope else {
            throw GraphChatProviderError(
                code: .invalidSession,
                message: "Graph, Chat-Scope und Schema der Modell-Session stimmen nicht überein."
            )
        }
        let registeredKinds = await configuration.toolRunner.registeredToolKinds()
        guard registeredKinds == Set(GraphChatToolKind.allCases) else {
            throw GraphChatProviderError(
                code: .invalidSession,
                message: "Die Modell-Session benötigt exakt die kontrollierten read-only Graph-Tools."
            )
        }

        let reporter = FoundationGraphChatToolActivityReporter()
        let tools: [any Tool] = [
            FoundationDescribeGraphSchemaTool(
                runner: configuration.toolRunner,
                reporter: reporter
            ),
            FoundationSearchGraphTool(
                runner: configuration.toolRunner,
                reporter: reporter
            ),
            FoundationQueryDetailValuesTool(
                runner: configuration.toolRunner,
                reporter: reporter
            ),
            FoundationGetNodeTool(
                runner: configuration.toolRunner,
                reporter: reporter
            ),
            FoundationGetNeighborsTool(
                runner: configuration.toolRunner,
                reporter: reporter
            ),
            FoundationGraphStatsTool(
                runner: configuration.toolRunner,
                reporter: reporter
            )
        ]
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: tools,
            instructions: configuration.instructions
        )
        let id = GraphChatModelSessionID()
        sessions[id] = SessionState(
            session: session,
            configuration: configuration,
            reporter: reporter,
            generationTask: nil
        )
        return id
    }

    func prewarm(
        sessionID: GraphChatModelSessionID,
        promptPrefix: String?
    ) throws {
        guard let state = sessions[sessionID] else {
            throw invalidSession()
        }
        let prompt = promptPrefix.map { Prompt($0) }
        state.session.prewarm(promptPrefix: prompt)
    }

    func streamResponse(
        sessionID: GraphChatModelSessionID,
        request: GraphChatModelRequest
    ) throws -> GraphChatProviderEventStream {
        guard var state = sessions[sessionID] else {
            throw invalidSession()
        }
        guard state.generationTask == nil, state.session.isResponding == false else {
            throw GraphChatProviderError(
                code: .concurrentRequest,
                message: "Für diese Modell-Session läuft bereits eine Generierung."
            )
        }

        var continuationReference: GraphChatProviderEventStream.Continuation?
        let stream = GraphChatProviderEventStream { continuation in
            continuationReference = continuation
        }
        guard let continuation = continuationReference else {
            throw GraphChatProviderError(
                code: .unexpected,
                message: "Der Foundation-Models-Stream konnte nicht initialisiert werden."
            )
        }

        let task = Task { [weak self] in
            guard let self else {
                continuation.finish(
                    throwing: GraphChatProviderError(
                        code: .unexpected,
                        message: "Der Foundation-Models-Provider wurde verworfen."
                    )
                )
                return
            }
            await self.generate(
                sessionID: sessionID,
                request: request,
                continuation: continuation
            )
        }
        state.generationTask = task
        sessions[sessionID] = state
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return stream
    }

    func cancelGeneration(sessionID: GraphChatModelSessionID) {
        sessions[sessionID]?.generationTask?.cancel()
    }

    func discardSession(sessionID: GraphChatModelSessionID) async {
        guard let state = sessions.removeValue(forKey: sessionID) else {
            return
        }
        state.generationTask?.cancel()
        await state.reporter.detach()
    }

    private func generate(
        sessionID: GraphChatModelSessionID,
        request: GraphChatModelRequest,
        continuation: GraphChatProviderEventStream.Continuation
    ) async {
        guard let state = sessions[sessionID] else {
            continuation.finish(throwing: invalidSession())
            return
        }
        let reporter = state.reporter
        await reporter.attach(continuation)
        defer {
            Task { [reporter, sessionID] in
                await reporter.detach()
                self.generationFinished(sessionID: sessionID)
            }
        }

        do {
            let responseStream = state.session.streamResponse(
                to: prompt(for: request),
                generating: FoundationGraphChatGeneratedAnswer.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            for try await snapshot in responseStream {
                try Task.checkCancellation()
                let partial = snapshot.content
                guard let directAnswer = partial.directAnswer,
                      directAnswer.isEmpty == false else {
                    continue
                }
                continuation.yield(
                    .partialAnswer(
                        GraphChatProviderPartialAnswer(
                            directAnswer: directAnswer,
                            hasInsufficientEvidence: partial.hasInsufficientEvidence
                        )
                    )
                )
            }
            let finalResponse = try await responseStream.collect()
            try Task.checkCancellation()
            continuation.yield(
                .completed(providerAnswer(from: finalResponse.content))
            )
            continuation.finish()
        } catch is CancellationError {
            continuation.finish(throwing: GraphChatProviderError.cancelled())
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            continuation.finish(
                throwing: GraphChatProviderError(
                    code: .contextWindowExceeded,
                    message: "Das lokale Modell-Kontextfenster wurde überschritten."
                )
            )
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
            continuation.finish(
                throwing: GraphChatProviderError(
                    code: .unsupportedLanguage,
                    message: "Die Sprache der Anfrage wird vom lokalen Modell nicht unterstützt."
                )
            )
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            continuation.finish(
                throwing: GraphChatProviderError(
                    code: .safetyGuardrail,
                    message: "Die lokale Sicherheitsprüfung hat die Anfrage oder Antwort blockiert."
                )
            )
        } catch let error as LanguageModelSession.ToolCallError {
            if let toolError = error.underlyingError as? GraphChatToolError {
                continuation.finish(throwing: providerError(from: toolError))
            } else {
                continuation.finish(
                    throwing: GraphChatProviderError(
                        code: .toolFailure,
                        message: "Ein kontrolliertes read-only Graph-Tool konnte nicht ausgeführt werden."
                    )
                )
            }
        } catch let error as GraphChatToolError {
            continuation.finish(
                throwing: providerError(from: error)
            )
        } catch let error as GraphChatProviderError {
            continuation.finish(throwing: error)
        } catch {
            continuation.finish(
                throwing: GraphChatProviderError(
                    code: .unexpected,
                    message: "Das lokale Modell konnte die Antwort nicht erzeugen."
                )
            )
        }
    }

    private func generationFinished(sessionID: GraphChatModelSessionID) {
        guard var state = sessions[sessionID] else {
            return
        }
        state.generationTask = nil
        sessions[sessionID] = state
    }

    private func prompt(for request: GraphChatModelRequest) -> String {
        // PR 15 carries a trusted, bounded state snapshot through the provider boundary.
        // Provider-side reference resolution is intentionally deferred to PR 16.
        [
            "SCHEMA SNAPSHOT",
            request.schemaPrompt,
            "USER QUESTION",
            request.question
        ].joined(separator: "\n\n")
    }

    private func providerAnswer(
        from generated: FoundationGraphChatGeneratedAnswer
    ) -> GraphChatProviderFinalAnswer {
        GraphChatProviderFinalAnswer(
            directAnswer: generated.directAnswer,
            sections: generated.sections.map { section in
                GraphChatProviderAnswerSection(
                    title: nilIfEmpty(section.title),
                    text: section.text,
                    evidenceIDValues: section.evidenceIDs
                )
            },
            evidenceIDValues: generated.evidenceIDs,
            appliedFilters: generated.appliedFilters.map { filter in
                GraphChatProviderAppliedFilter(
                    fieldName: filter.fieldName,
                    operationDescription: filter.operationDescription,
                    valueDescription: nilIfEmpty(filter.valueDescription)
                )
            },
            followUpSuggestions: generated.followUps.map { followUp in
                GraphChatProviderFollowUpSuggestion(
                    title: followUp.title,
                    prompt: followUp.prompt
                )
            },
            hasInsufficientEvidence: generated.hasInsufficientEvidence
        )
    }

    private func providerError(from error: GraphChatToolError) -> GraphChatProviderError {
        switch error.code {
        case .cancelled:
            return .cancelled()
        case .budgetExceeded:
            return GraphChatProviderError(
                code: .toolBudgetExceeded,
                message: "Das kontrollierte Tool-Budget wurde erreicht."
            )
        case .invalidInput, .graphScopeMismatch, .indexUnavailable, .sourceUnavailable, .unavailable:
            return GraphChatProviderError(
                code: .toolFailure,
                message: error.message
            )
        }
    }

    private func invalidSession() -> GraphChatProviderError {
        GraphChatProviderError(
            code: .invalidSession,
            message: "Die Foundation-Models-Session existiert nicht mehr."
        )
    }
}

#else

actor FoundationModelsGraphChatProvider: GraphChatModelProvider {
    func availability() -> GraphChatModelAvailability {
        .unavailable(.deviceNotEligible)
    }

    func createSession(
        configuration: GraphChatModelSessionConfiguration
    ) throws -> GraphChatModelSessionID {
        throw unavailableError()
    }

    func prewarm(
        sessionID: GraphChatModelSessionID,
        promptPrefix: String?
    ) throws {
        throw unavailableError()
    }

    func streamResponse(
        sessionID: GraphChatModelSessionID,
        request: GraphChatModelRequest
    ) throws -> GraphChatProviderEventStream {
        throw unavailableError()
    }

    func cancelGeneration(sessionID: GraphChatModelSessionID) {}

    func discardSession(sessionID: GraphChatModelSessionID) {}

    private func unavailableError() -> GraphChatProviderError {
        GraphChatProviderError(
            code: .unavailable,
            message: "Foundation Models ist in diesem SDK nicht verfügbar."
        )
    }
}

#endif
