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
        var finalAnswer: GraphChatProviderFinalAnswer?

        do {
            for try await event in providerStream {
                try Task.checkCancellation()
                switch event {
                case .toolActivity(let activity):
                    onEvent(.toolActivity(activity))
                case .partialAnswer(let partial):
                    let text = partial.directAnswer.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if text.isEmpty == false {
                        onEvent(.partialAnswer(text))
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
}
