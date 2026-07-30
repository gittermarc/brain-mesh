//
//  GraphChatProviderExecutor.swift
//  BrainMesh
//
//  Raw provider stream consumption without answer or artifact validation.
//

import Foundation

nonisolated enum GraphChatProviderForwardedEvent: Hashable, Sendable {
    case toolActivity(GraphChatToolActivity)
    case partialAnswer(String)
}

nonisolated struct GraphChatProviderExecutor: Sendable {
    private let provider: any GraphChatModelProvider
    private let sessionFactory: GraphChatProviderSessionFactory

    init(
        provider: any GraphChatModelProvider,
        sessionFactory: GraphChatProviderSessionFactory
    ) {
        self.provider = provider
        self.sessionFactory = sessionFactory
    }

    func execute(
        resources: GraphChatProviderSessionResources,
        request: GraphChatModelRequest,
        onEvent: @escaping @Sendable (GraphChatProviderForwardedEvent) -> Void
    ) async throws -> GraphChatProviderFinalAnswer {
        // Keep stream ownership in an unstructured task. If the calling task is
        // cancelled, cancelling its AsyncStream iterator directly would trigger
        // the provider stream's termination handler before cancelGeneration can
        // target the still-active provider session.
        let consumptionTask = Task {
            try await consume(
                resources: resources,
                request: request,
                onEvent: onEvent
            )
        }

        return try await withTaskCancellationHandler(
            operation: {
                do {
                    let finalAnswer = try await consumptionTask.value
                    try Task.checkCancellation()
                    return finalAnswer
                } catch {
                    guard Task.isCancelled else {
                        if let providerError =
                            error as? GraphChatProviderError {
                            throw await presentationSafeError(
                                providerError,
                                resources: resources
                            )
                        }
                        if let toolError = error as? GraphChatToolError {
                            throw await presentationSafeError(
                                toolError,
                                resources: resources
                            )
                        }
                        if let graphChatError = error as? GraphChatError {
                            throw await presentationSafeError(
                                graphChatError,
                                resources: resources
                            )
                        }
                        throw error
                    }
                    await sessionFactory.requestCancellation(resources)
                    throw CancellationError()
                }
            },
            onCancel: {
                Task {
                    await sessionFactory.requestCancellation(resources)
                }
            }
        )
    }

    private func consume(
        resources: GraphChatProviderSessionResources,
        request: GraphChatModelRequest,
        onEvent: @escaping @Sendable (GraphChatProviderForwardedEvent) -> Void
    ) async throws -> GraphChatProviderFinalAnswer {
        let providerStream = try await provider.streamResponse(
            sessionID: resources.sessionID,
            request: request
        )
        let presentationFirewall = GraphChatPresentationStreamFirewall(
            registry: resources.presentationRegistry,
            language: resources.responseLanguage
        )
        var finalAnswer: GraphChatProviderFinalAnswer?

        do {
            for try await event in providerStream {
                try Task.checkCancellation()
                switch event {
                case .toolActivity(let activity):
                    onEvent(.toolActivity(activity))
                case .partialAnswer(let partial):
                    // Foundation Models exposes cumulative structured snapshots.
                    // Rechecking the whole visible value prevents split aliases
                    // such as "E" followed by "E1" from ever being published.
                    let rawText = partial.directAnswer.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if rawText.isEmpty == false {
                        if let text = await presentationFirewall
                            .presentCumulativeText(rawText) {
                            onEvent(.partialAnswer(text))
                        }
                    }
                case .completed(let answer):
                    finalAnswer = answer
                }
            }
        } catch {
            if Task.isCancelled {
                await sessionFactory.requestCancellation(resources)
                throw CancellationError()
            }
            throw error
        }

        do {
            try Task.checkCancellation()
        } catch {
            await sessionFactory.requestCancellation(resources)
            throw error
        }
        guard let finalAnswer else {
            throw GraphChatProviderError(
                code: .unexpected,
                message:
                    "Das Modell hat keine vollständige strukturierte Antwort geliefert."
            )
        }
        await sessionFactory.completeProviderStream(resources)
        return finalAnswer
    }

    private func presentationSafeError(
        _ error: GraphChatProviderError,
        resources: GraphChatProviderSessionResources
    ) async -> GraphChatProviderError {
        GraphChatProviderError(
            code: error.code,
            message: await presentationSafeMessage(
                error.message,
                resources: resources
            )
        )
    }

    private func presentationSafeError(
        _ error: GraphChatToolError,
        resources: GraphChatProviderSessionResources
    ) async -> GraphChatToolError {
        GraphChatToolError(
            code: error.code,
            message: safeToolFailureMessage(
                for: error.code,
                language: resources.responseLanguage
            )
        )
    }

    private func safeToolFailureMessage(
        for code: GraphChatToolErrorCode,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, code) {
        case (.german, .invalidInput):
            return "Der Tool-Aufruf konnte fachlich nicht validiert werden."
        case (.english, .invalidInput):
            return "The tool call could not be validated."
        case (.german, .graphScopeMismatch):
            return "Die Anfrage liegt außerhalb des freigegebenen Chat-Scopes."
        case (.english, .graphScopeMismatch):
            return "The request is outside the authorized chat scope."
        case (.german, .budgetExceeded):
            return "Das sichere Tool-Budget für diese Anfrage wurde erreicht."
        case (.english, .budgetExceeded):
            return "The safe tool budget for this request was reached."
        case (.german, .cancelled):
            return "Die Graph-Chat-Anfrage wurde abgebrochen."
        case (.english, .cancelled):
            return "The graph chat request was cancelled."
        case (.german, .indexUnavailable),
            (.german, .sourceUnavailable),
            (.german, .unavailable):
            return "Die Graph-Daten konnten für diese Anfrage nicht sicher gelesen werden."
        case (.english, .indexUnavailable),
            (.english, .sourceUnavailable),
            (.english, .unavailable):
            return "The graph data could not be read safely for this request."
        }
    }

    private func presentationSafeError(
        _ error: GraphChatError,
        resources: GraphChatProviderSessionResources
    ) async -> GraphChatError {
        let registry = await resources.presentationRegistry.snapshot()
        let firewall = GraphChatPresentationFirewall()
        let fallback = GraphChatResponseLocalizer(
            language: resources.responseLanguage
        ).unsafePresentation()

        func safeMessage(_ message: String) -> String {
            switch firewall.present(message, using: registry) {
            case .safe(let value):
                return value
            case .unsafe:
                return fallback
            }
        }
        return GraphChatError(
            code: error.code,
            message: safeMessage(error.message),
            recoverySuggestion: error.recoverySuggestion.map(safeMessage),
            bindingDiagnosticReason:
                error.bindingDiagnosticReason
        )
    }

    private func presentationSafeMessage(
        _ message: String,
        resources: GraphChatProviderSessionResources
    ) async -> String {
        let registry = await resources.presentationRegistry.snapshot()
        switch GraphChatPresentationFirewall().present(
            message,
            using: registry
        ) {
        case .safe(let value):
            return value
        case .unsafe:
            return GraphChatResponseLocalizer(
                language: resources.responseLanguage
            ).unsafePresentation()
        }
    }
}
