//
//  GraphChatOrchestrator.swift
//  BrainMesh
//
//  UI-independent orchestration for graph-scoped, streamed model answers.
//

import Foundation

nonisolated enum GraphChatConcurrentRequestPolicy: String, CaseIterable, Hashable, Sendable {
    case cancelPrevious
}

nonisolated struct GraphChatConversationContextPolicy: Hashable, Sendable {
    let maximumSummaryLength: Int
    let maximumQuestionLength: Int
    let maximumAnswerLength: Int
    let maximumEvidenceSummaries: Int

    static let `default` = GraphChatConversationContextPolicy(
        maximumSummaryLength: 2_000,
        maximumQuestionLength: 400,
        maximumAnswerLength: 900,
        maximumEvidenceSummaries: 12
    )

    init(
        maximumSummaryLength: Int,
        maximumQuestionLength: Int,
        maximumAnswerLength: Int,
        maximumEvidenceSummaries: Int
    ) {
        precondition(maximumSummaryLength > 0)
        precondition(maximumQuestionLength > 0)
        precondition(maximumAnswerLength > 0)
        precondition(maximumEvidenceSummaries > 0)
        self.maximumSummaryLength = maximumSummaryLength
        self.maximumQuestionLength = maximumQuestionLength
        self.maximumAnswerLength = maximumAnswerLength
        self.maximumEvidenceSummaries = maximumEvidenceSummaries
    }
}

actor GraphChatOrchestrator {
    private struct ScopeKey: Hashable, Sendable {
        let graphScope: GraphScope
        let chatScope: GraphChatScope
    }

    private struct SessionResources {
        let key: ScopeKey
        let sessionID: GraphChatModelSessionID
        let schemaContext: GraphSchemaContext
        let budget: GraphChatToolBudget
        let evidenceRegistry: GraphChatEvidenceRegistry
        let toolRunner: any GraphChatModelToolRunning
    }

    private struct ActiveGeneration {
        let requestID: UUID
        let task: Task<Void, Never>
        var sessionID: GraphChatModelSessionID?
    }

    private let provider: any GraphChatModelProvider
    private let schemaProvider: any GraphSchemaSnapshotProviding
    private let toolRunnerFactory: any GraphChatModelToolRunnerFactory
    private let toolBudgetPolicy: GraphChatToolBudgetPolicy
    private let concurrentRequestPolicy: GraphChatConcurrentRequestPolicy
    private let contextPolicy: GraphChatConversationContextPolicy
    private let referenceDate: @Sendable () -> Date
    private let calendar: Calendar
    private let timeZone: TimeZone

    private var preparedSession: SessionResources?
    private var activeGeneration: ActiveGeneration?
    private var conversationScopeKey: ScopeKey?
    private var conversationSummary: String?

    init(
        provider: any GraphChatModelProvider,
        schemaProvider: any GraphSchemaSnapshotProviding = GraphSchemaService.shared,
        toolRunnerFactory: any GraphChatModelToolRunnerFactory,
        toolBudgetPolicy: GraphChatToolBudgetPolicy = .default,
        concurrentRequestPolicy: GraphChatConcurrentRequestPolicy = .cancelPrevious,
        contextPolicy: GraphChatConversationContextPolicy = .default,
        referenceDate: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current
    ) {
        self.provider = provider
        self.schemaProvider = schemaProvider
        self.toolRunnerFactory = toolRunnerFactory
        self.toolBudgetPolicy = toolBudgetPolicy
        self.concurrentRequestPolicy = concurrentRequestPolicy
        self.contextPolicy = contextPolicy
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.timeZone = timeZone
    }

    func prepare(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async throws {
        let key = try validatedKey(graphScope: graphScope, chatScope: chatScope)
        try await cancelActiveGenerationForNewRequest()
        await discardPreparedSession(unlessMatching: key)

        if preparedSession?.key == key {
            return
        }

        let resources = try await makeSessionResources(for: key)
        do {
            try await provider.prewarm(
                sessionID: resources.sessionID,
                promptPrefix: "A read-only question about the active graph will follow."
            )
            preparedSession = resources
        } catch {
            await provider.discardSession(sessionID: resources.sessionID)
            throw mapError(error)
        }
    }

    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream {
        let requestID = UUID()
        let pair = GraphChatEventStream.makeStream()

        do {
            try await cancelActiveGenerationForNewRequest()
            let key = try validatedKey(graphScope: graphScope, chatScope: chatScope)
            await discardPreparedSession(unlessMatching: key)
            resetConversationContextIfNeeded(for: key)

            let task = Task { [weak self] in
                guard let self else {
                    pair.continuation.yield(
                        .failure(
                            GraphChatError(
                                code: .unexpected,
                                message: "Der Graph-Chat-Orchestrator wurde verworfen."
                            )
                        )
                    )
                    pair.continuation.finish()
                    return
                }
                await self.performRequest(
                    requestID: requestID,
                    question: question,
                    key: key,
                    continuation: pair.continuation
                )
            }
            activeGeneration = ActiveGeneration(
                requestID: requestID,
                task: task,
                sessionID: nil
            )
            pair.continuation.onTermination = { @Sendable [weak self] _ in
                Task {
                    await self?.cancel(requestID: requestID)
                }
            }
        } catch {
            pair.continuation.yield(.started(requestID: requestID))
            pair.continuation.yield(.failure(mapError(error)))
            pair.continuation.finish()
        }

        return pair.stream
    }

    func cancelCurrentGeneration() async {
        guard let activeGeneration else {
            return
        }
        activeGeneration.task.cancel()
        if let sessionID = activeGeneration.sessionID {
            await provider.cancelGeneration(sessionID: sessionID)
        }
        await activeGeneration.task.value
    }

    func discardSession() async {
        await cancelCurrentGeneration()
        if let preparedSession {
            await provider.discardSession(sessionID: preparedSession.sessionID)
            self.preparedSession = nil
        }
        conversationScopeKey = nil
        conversationSummary = nil
    }

    private func performRequest(
        requestID: UUID,
        question: String,
        key: ScopeKey,
        continuation: GraphChatEventStream.Continuation
    ) async {
        continuation.yield(.started(requestID: requestID))
        defer {
            continuation.finish()
            clearActiveGeneration(requestID: requestID)
        }

        do {
            let normalizedQuestion = try validateQuestion(question)
            let initialResources = try await takeOrCreateSessionResources(for: key)
            setActiveSessionID(initialResources.sessionID, requestID: requestID)
            let answer = try await generateWithSingleContextRetry(
                resources: initialResources,
                question: normalizedQuestion,
                requestID: requestID,
                continuation: continuation
            )
            try Task.checkCancellation()
            updateConversationContext(
                key: key,
                question: normalizedQuestion,
                answer: answer
            )
            continuation.yield(.completed(answer))
        } catch is CancellationError {
            continuation.yield(.cancelled)
        } catch let error as GraphChatProviderError where error.code == .cancelled {
            continuation.yield(.cancelled)
        } catch let error as GraphChatToolError where error.code == .cancelled {
            continuation.yield(.cancelled)
        } catch {
            continuation.yield(.failure(mapError(error)))
        }
    }

    private func generateWithSingleContextRetry(
        resources initialResources: SessionResources,
        question: String,
        requestID: UUID,
        continuation: GraphChatEventStream.Continuation
    ) async throws -> GraphChatAnswer {
        var resources = initialResources
        var retryCount = 0

        while true {
            do {
                let summary = retryCount == 0 ? conversationSummary : nil
                let answer = try await consumeProviderStream(
                    resources: resources,
                    question: question,
                    conversationSummary: summary,
                    continuation: continuation
                )
                await provider.discardSession(sessionID: resources.sessionID)
                return answer
            } catch let error as GraphChatProviderError
                where error.code == .contextWindowExceeded && retryCount == 0 {
                await provider.discardSession(sessionID: resources.sessionID)
                retryCount += 1
                resources = try await replaceSession(in: resources)
                setActiveSessionID(resources.sessionID, requestID: requestID)
            } catch {
                if Task.isCancelled {
                    await provider.cancelGeneration(sessionID: resources.sessionID)
                }
                await provider.discardSession(sessionID: resources.sessionID)
                throw error
            }
        }
    }

    private func consumeProviderStream(
        resources: SessionResources,
        question: String,
        conversationSummary: String?,
        continuation: GraphChatEventStream.Continuation
    ) async throws -> GraphChatAnswer {
        let request = GraphChatModelRequest(
            question: question,
            schemaPrompt: schemaPrompt(
                from: resources.schemaContext,
                chatScope: resources.key.chatScope
            ),
            conversationSummary: conversationSummary
        )
        let providerStream = try await provider.streamResponse(
            sessionID: resources.sessionID,
            request: request
        )
        var finalAnswer: GraphChatProviderFinalAnswer?

        do {
            for try await event in providerStream {
                try Task.checkCancellation()
                switch event {
                case .toolActivity(let activity):
                    continuation.yield(.toolActivity(activity))
                case .partialAnswer(let partial):
                    let text = partial.directAnswer.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if text.isEmpty == false {
                        continuation.yield(.partialAnswer(text))
                    }
                case .completed(let answer):
                    finalAnswer = answer
                }
            }
        } catch {
            if Task.isCancelled {
                await provider.cancelGeneration(sessionID: resources.sessionID)
                throw CancellationError()
            }
            throw error
        }

        try Task.checkCancellation()
        guard let finalAnswer else {
            throw GraphChatProviderError(
                code: .unexpected,
                message: "Das Modell hat keine vollständige strukturierte Antwort geliefert."
            )
        }
        return await validatedAnswer(
            from: finalAnswer,
            registry: resources.evidenceRegistry
        )
    }

    private func validatedAnswer(
        from providerAnswer: GraphChatProviderFinalAnswer,
        registry: GraphChatEvidenceRegistry
    ) async -> GraphChatAnswer {
        var allEvidence: [GraphEvidence] = await registry.validatedEvidence(
            for: providerAnswer.evidenceIDValues
        )
        var sections: [GraphChatAnswerSection] = []
        sections.reserveCapacity(providerAnswer.sections.count)

        for section in providerAnswer.sections {
            let sectionEvidence = await registry.validatedEvidence(
                for: section.evidenceIDValues
            )
            allEvidence.append(contentsOf: sectionEvidence)
            sections.append(
                GraphChatAnswerSection(
                    title: section.title,
                    text: section.text,
                    evidenceIDs: sectionEvidence.map(\.id)
                )
            )
        }

        let validatedEvidence = GraphEvidenceCollection(allEvidence).values
        return GraphChatAnswer(
            directAnswer: providerAnswer.directAnswer,
            sections: sections,
            evidence: validatedEvidence,
            appliedFilters: providerAnswer.appliedFilters.map { filter in
                GraphChatAppliedFilter(
                    fieldName: filter.fieldName,
                    operationDescription: filter.operationDescription,
                    valueDescription: filter.valueDescription
                )
            },
            followUpSuggestions: providerAnswer.followUpSuggestions.map { suggestion in
                GraphChatFollowUpSuggestion(
                    title: suggestion.title,
                    prompt: suggestion.prompt
                )
            },
            hasInsufficientEvidence: providerAnswer.hasInsufficientEvidence
                || validatedEvidence.isEmpty
        )
    }

    private func takeOrCreateSessionResources(
        for key: ScopeKey
    ) async throws -> SessionResources {
        if let preparedSession, preparedSession.key == key {
            self.preparedSession = nil
            return preparedSession
        }
        return try await makeSessionResources(for: key)
    }

    private func makeSessionResources(
        for key: ScopeKey
    ) async throws -> SessionResources {
        let availability = await provider.availability()
        guard availability.isAvailable else {
            throw availabilityError(availability)
        }

        let schemaContext: GraphSchemaContext
        do {
            schemaContext = try await schemaProvider.makeSnapshot(
                in: key.graphScope,
                exampleFieldIDs: []
            )
        } catch {
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Das Schema des aktiven Graphen konnte nicht geladen werden.",
                recoverySuggestion: "Öffne den Graphen erneut und versuche es noch einmal."
            )
        }
        guard schemaContext.graphScope == key.graphScope else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Das geladene Schema gehört nicht zum aktiven Graphen."
            )
        }

        let budget = GraphChatToolBudget(policy: toolBudgetPolicy)
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: key.chatScope)
        let toolRunner = toolRunnerFactory.makeRunner(
            scope: key.chatScope,
            schemaContext: schemaContext,
            budget: budget,
            evidenceRegistry: evidenceRegistry,
            referenceDate: referenceDate(),
            calendar: calendar,
            timeZone: timeZone
        )
        let registeredKinds = await toolRunner.registeredToolKinds()
        guard registeredKinds == Set(GraphChatToolKind.allCases) else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Für den Graph-Chat sind nicht exakt die kontrollierten read-only Tools registriert."
            )
        }

        let configuration = GraphChatModelSessionConfiguration(
            graphScope: key.graphScope,
            chatScope: key.chatScope,
            schemaContext: schemaContext,
            instructions: systemInstructions(for: key.chatScope),
            toolRunner: toolRunner
        )
        do {
            let sessionID = try await provider.createSession(configuration: configuration)
            return SessionResources(
                key: key,
                sessionID: sessionID,
                schemaContext: schemaContext,
                budget: budget,
                evidenceRegistry: evidenceRegistry,
                toolRunner: toolRunner
            )
        } catch {
            throw mapError(error)
        }
    }

    private func replaceSession(
        in resources: SessionResources
    ) async throws -> SessionResources {
        let configuration = GraphChatModelSessionConfiguration(
            graphScope: resources.key.graphScope,
            chatScope: resources.key.chatScope,
            schemaContext: resources.schemaContext,
            instructions: systemInstructions(for: resources.key.chatScope),
            toolRunner: resources.toolRunner
        )
        let sessionID = try await provider.createSession(configuration: configuration)
        return SessionResources(
            key: resources.key,
            sessionID: sessionID,
            schemaContext: resources.schemaContext,
            budget: resources.budget,
            evidenceRegistry: resources.evidenceRegistry,
            toolRunner: resources.toolRunner
        )
    }

    private func cancelActiveGenerationForNewRequest() async throws {
        guard let activeGeneration else {
            return
        }
        switch concurrentRequestPolicy {
        case .cancelPrevious:
            activeGeneration.task.cancel()
            if let sessionID = activeGeneration.sessionID {
                await provider.cancelGeneration(sessionID: sessionID)
            }
            await activeGeneration.task.value
        }
    }

    private func cancel(requestID: UUID) async {
        guard let activeGeneration, activeGeneration.requestID == requestID else {
            return
        }
        activeGeneration.task.cancel()
        if let sessionID = activeGeneration.sessionID {
            await provider.cancelGeneration(sessionID: sessionID)
        }
    }

    private func setActiveSessionID(
        _ sessionID: GraphChatModelSessionID,
        requestID: UUID
    ) {
        guard var activeGeneration, activeGeneration.requestID == requestID else {
            return
        }
        activeGeneration.sessionID = sessionID
        self.activeGeneration = activeGeneration
    }

    private func clearActiveGeneration(requestID: UUID) {
        guard activeGeneration?.requestID == requestID else {
            return
        }
        activeGeneration = nil
    }

    private func discardPreparedSession(unlessMatching key: ScopeKey) async {
        guard let preparedSession, preparedSession.key != key else {
            return
        }
        await provider.discardSession(sessionID: preparedSession.sessionID)
        self.preparedSession = nil
    }

    private func validatedKey(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) throws -> ScopeKey {
        guard graphScope == chatScope.graphScope else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Der Chat-Scope gehört nicht zum aktiven Graphen."
            )
        }
        return ScopeKey(graphScope: graphScope, chatScope: chatScope)
    }

    private func validateQuestion(_ question: String) throws -> String {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Die Graph-Chat-Frage darf nicht leer sein."
            )
        }
        return String(normalized.prefix(4_000))
    }

    private func resetConversationContextIfNeeded(for key: ScopeKey) {
        guard conversationScopeKey != key else {
            return
        }
        conversationScopeKey = key
        conversationSummary = nil
    }

    private func updateConversationContext(
        key: ScopeKey,
        question: String,
        answer: GraphChatAnswer
    ) {
        let evidenceLines = answer.evidence
            .prefix(contextPolicy.maximumEvidenceSummaries)
            .map { evidence in
                "- \(evidence.id.rawValue.uuidString): \(bounded(evidence.summary, limit: 180))"
            }
        let summary = [
            "Previous question: \(bounded(question, limit: contextPolicy.maximumQuestionLength))",
            "Validated answer: \(bounded(answer.directAnswer, limit: contextPolicy.maximumAnswerLength))",
            "Validated evidence:",
            evidenceLines.isEmpty ? "- none" : evidenceLines.joined(separator: "\n")
        ].joined(separator: "\n")
        conversationScopeKey = key
        conversationSummary = bounded(
            summary,
            limit: contextPolicy.maximumSummaryLength
        )
    }

    private func schemaPrompt(
        from context: GraphSchemaContext,
        chatScope: GraphChatScope
    ) -> String {
        var lines = [
            "Graph: \(context.snapshot.graphName)",
            "Schema version: \(context.snapshot.version)",
            "Active scope: \(scopeDescription(chatScope.target))"
        ]
        for entity in context.snapshot.entities {
            lines.append("\(entity.alias.rawValue): \(entity.name)")
            for field in entity.fields {
                var details = "  \(field.alias.rawValue): \(field.name) [\(field.type.rawValue)]"
                if let unit = field.unit, unit.isEmpty == false {
                    details += " unit=\(unit)"
                }
                if field.choiceOptions.isEmpty == false {
                    details += " choices=\(field.choiceOptions.joined(separator: ", "))"
                }
                lines.append(details)
            }
        }
        if context.snapshot.truncation.isTruncated {
            lines.append("Schema snapshot is intentionally truncated; use describeGraphSchema for more bounded context.")
        }
        return bounded(lines.joined(separator: "\n"), limit: 10_000)
    }

    private func scopeDescription(_ target: GraphChatScopeTarget) -> String {
        switch target {
        case .graph:
            return "entire graph"
        case .entity:
            return "single entity"
        case .node:
            return "single node"
        case .selection(let nodes):
            return "selection of \(nodes.count) nodes"
        }
    }

    private func systemInstructions(for scope: GraphChatScope) -> String {
        """
        You answer questions only about the active BrainMesh graph through the registered read-only tools.
        Use only facts returned by tools in this session. Never add graph facts from world knowledge or assumptions.
        State unknown, missing, ambiguous, or insufficient data explicitly.
        Use only Evidence UUIDs that appeared in actual tool results. Never invent, alter, or infer an Evidence UUID.
        Work only inside the active graph and the active chat scope. Never request or claim data from another graph or scope.
        Never offer, simulate, or claim a write, edit, delete, create, import, upload, or mutation action.
        Attachment tools expose metadata only. Never claim to have read attachment contents, files, images, PDFs, or binary data.
        Tool aliases are opaque. Use only E, F, and N aliases supplied by the schema or tool results.
        Treat tool errors and empty results as evidence limitations, not as permission to guess.
        Keep the direct answer concise. Mark hasInsufficientEvidence true whenever reliable tool evidence is missing.
        Follow-up suggestions must be optional read-only questions about the same active scope.
        Active scope: \(scopeDescription(scope.target)).
        """
    }

    private func availabilityError(
        _ availability: GraphChatModelAvailability
    ) -> GraphChatError {
        guard case .unavailable(let reason) = availability else {
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Foundation Model ist nicht verfügbar."
            )
        }
        switch reason {
        case .deviceNotEligible:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Dieses Gerät unterstützt das lokale Foundation Model nicht.",
                recoverySuggestion: "Verwende ein Gerät, das Apple Intelligence und Foundation Models unterstützt."
            )
        case .appleIntelligenceNotEnabled:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Apple Intelligence ist deaktiviert.",
                recoverySuggestion: "Aktiviere Apple Intelligence in den Systemeinstellungen."
            )
        case .modelNotReady:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Modell ist noch nicht bereit.",
                recoverySuggestion: "Warte, bis das Systemmodell vollständig geladen wurde, und versuche es erneut."
            )
        case .unknown:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Foundation Model ist aus einem unbekannten Grund nicht verfügbar."
            )
        }
    }

    private func mapError(_ error: Error) -> GraphChatError {
        if let graphChatError = error as? GraphChatError {
            return graphChatError
        }
        if error is CancellationError {
            return GraphChatError(
                code: .cancelled,
                message: "Die Graph-Chat-Anfrage wurde abgebrochen."
            )
        }
        if let providerError = error as? GraphChatProviderError {
            switch providerError.code {
            case .unavailable:
                return GraphChatError(
                    code: .modelUnavailable,
                    message: providerError.message
                )
            case .invalidSession:
                return GraphChatError(
                    code: .invalidRequest,
                    message: providerError.message
                )
            case .concurrentRequest:
                return GraphChatError(
                    code: .concurrentRequest,
                    message: providerError.message
                )
            case .contextWindowExceeded:
                return GraphChatError(
                    code: .contextWindowExceeded,
                    message: providerError.message,
                    recoverySuggestion: "Stelle eine kürzere oder konkretere Frage."
                )
            case .cancelled:
                return GraphChatError(
                    code: .cancelled,
                    message: providerError.message
                )
            case .toolBudgetExceeded:
                return GraphChatError(
                    code: .toolBudgetExceeded,
                    message: providerError.message,
                    recoverySuggestion: "Stelle eine engere Frage mit weniger Teilaspekten."
                )
            case .toolFailure:
                return GraphChatError(
                    code: .toolFailure,
                    message: providerError.message
                )
            case .unsupportedLanguage:
                return GraphChatError(
                    code: .unavailable,
                    message: providerError.message,
                    recoverySuggestion: "Formuliere die Frage in einer vom Gerät unterstützten Sprache."
                )
            case .safetyGuardrail:
                return GraphChatError(
                    code: .unavailable,
                    message: providerError.message
                )
            case .unexpected:
                return GraphChatError(
                    code: .unexpected,
                    message: providerError.message
                )
            }
        }
        if let toolError = error as? GraphChatToolError {
            switch toolError.code {
            case .cancelled:
                return GraphChatError(code: .cancelled, message: toolError.message)
            case .budgetExceeded:
                return GraphChatError(
                    code: .toolBudgetExceeded,
                    message: toolError.message,
                    recoverySuggestion: "Stelle eine engere Frage mit weniger Teilaspekten."
                )
            case .invalidInput, .graphScopeMismatch:
                return GraphChatError(code: .invalidQueryPlan, message: toolError.message)
            case .indexUnavailable, .sourceUnavailable, .unavailable:
                return GraphChatError(code: .toolFailure, message: toolError.message)
            }
        }
        return GraphChatError(
            code: .unexpected,
            message: "Die Graph-Chat-Anfrage konnte nicht abgeschlossen werden."
        )
    }

    private func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit))
    }
}
