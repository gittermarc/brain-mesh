//
//  GraphChatFoundationalIntentCoordinator.swift
//  BrainMesh
//
//  Intent trust boundary consuming the request pipeline's authoritative schema context.
//

import Foundation

nonisolated enum GraphChatFoundationalIntentResolution: Sendable {
    case local(GraphChatLocalTurnPlan)
    case compiled(
        intent: GraphChatFoundationalIntent,
        schemaContext: GraphSchemaContext
    )
    case providerFallback(
        schemaContext: GraphSchemaContext
    )
}

nonisolated struct GraphChatFoundationalIntentCoordinator: Sendable {
    private let compiler: GraphChatFoundationalIntentCompiler
    private let observability:
        any GraphChatObservabilityRecording

    init(
        compiler: GraphChatFoundationalIntentCompiler =
            GraphChatFoundationalIntentCompiler(),
        observability:
            any GraphChatObservabilityRecording =
                NoOpGraphChatObservabilityRecorder()
    ) {
        self.compiler = compiler
        self.observability = observability
    }

    /// The coordinator has no repository or schema-service dependency. The request pipeline owns
    /// the one turn-scoped load and supplies that exact context here.
    func resolve(
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        requestedAt: Date,
        schemaContext: GraphSchemaContext
    ) async throws -> GraphChatFoundationalIntentResolution {
        try Task.checkCancellation()
        guard schemaContext.graphScope == providerPlan.scopeKey.graphScope,
              schemaContext.aliases.graphScope
                == providerPlan.scopeKey.graphScope,
              schemaContext.foundationalAliases.graphScope
                == providerPlan.scopeKey.graphScope else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message:
                    "Das geladene Schema gehört nicht zum aktiven Graphen."
            )
        }
        let foundationalSchemaContext = GraphSchemaContext(
            identity: schemaContext.identity,
            graphScope: schemaContext.graphScope,
            snapshot: schemaContext.snapshot,
            aliases: schemaContext.foundationalAliases,
            foundationalAliases: schemaContext.foundationalAliases
        )

        let continuation = providerPlan.foundationalContinuation
        if let sourceTurnID = continuation?.sourceTurnID,
           providerPlan.requestBaseState.turnContexts.contains(
            where: { $0.id == sourceTurnID }
           ) == false {
            throw GraphChatError(
                code: .invalidRequest,
                message:
                    "Die ursprüngliche fachliche Rückfrage ist nicht mehr im Conversation-State gebunden."
            )
        }
        let compilation = compiler.compile(
            GraphChatFoundationalIntentCompilerInput(
                requestID: requestID,
                question: providerPlan.providerQuestion,
                graphScope: providerPlan.scopeKey.graphScope,
                chatScope: providerPlan.scopeKey.chatScope,
                responseLanguage: providerPlan.responseLanguage,
                conversationState: providerPlan.requestBaseState,
                schemaContext: foundationalSchemaContext,
                selectedCandidate: continuation?.selection,
                sourceTurnID: continuation?.sourceTurnID,
                clarificationID: continuation?.clarificationID
            )
        )

        switch compilation {
        case .compiled(let intent):
            return .compiled(
                intent: intent,
                schemaContext: foundationalSchemaContext
            )
        case .notRecognized:
            return .providerFallback(
                schemaContext: schemaContext
            )
        case .rejected(let rejection):
            throw GraphChatError(
                code: .invalidRequest,
                message: rejectionMessage(rejection)
            )
        case .clarification(let clarification):
            await observability.record(
                .bindingDiagnostic(
                    GraphChatBindingDiagnosticMetric(
                        reason:
                            .multiplePlausibleCandidates
                    )
                )
            )
            let pending = pendingClarification(
                clarification,
                providerPlan: providerPlan,
                requestID: requestID,
                requestedAt: requestedAt
            )
            let answer = GraphChatAnswer(
                state: .clarification(
                    GraphChatClarification(
                        id: pending.id,
                        question: clarification.question,
                        options: pending.options.map {
                            GraphChatClarificationOption(
                                id: $0.id,
                                title: $0.title
                            )
                        }
                    )
                ),
                directAnswer: clarification.question,
                hasInsufficientEvidence: true
            )
            return .local(
                GraphChatLocalTurnPlan(
                    scopeKey: providerPlan.scopeKey,
                    normalizedQuestion: providerPlan.normalizedQuestion,
                    responseLanguage: providerPlan.responseLanguage,
                    answer: answer,
                    baseState: providerPlan.requestBaseState,
                    expectedCommittedState:
                        providerPlan.expectedCommittedState,
                    pendingClarification: pending
                )
            )
        }
    }

    private func pendingClarification(
        _ clarification: GraphChatFoundationalClarification,
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        requestedAt: Date
    ) -> GraphChatPendingClarification {
        GraphChatPendingClarification(
            id: requestID,
            decision: .foundationalIntent,
            options: clarification.options.map {
                GraphChatPendingClarificationOption(
                    id: $0.id,
                    title: $0.title,
                    proposal: .alias($0.id),
                    foundationalSelection: $0.selection
                )
            },
            sourceTurnID: requestID,
            graphScope: providerPlan.scopeKey.graphScope,
            chatScope: providerPlan.scopeKey.chatScope,
            continuationOperation: .answerAboutReference,
            continuationQuestion: providerPlan.providerQuestion,
            createdAt: requestedAt,
            expiresAt: requestedAt.addingTimeInterval(
                GraphChatIntentLimitPolicy
                    .default.pendingClarificationLifetime
            )
        )
    }

    private func rejectionMessage(
        _ rejection: GraphChatFoundationalIntentRejection
    ) -> String {
        switch rejection {
        case .graphScopeMismatch:
            return "Der lokale Intent gehört nicht zum aktiven Graphen."
        case .chatScopeMismatch:
            return "Der lokale Intent gehört nicht zum aktiven Chat-Scope."
        case .staleClarification:
            return "Die fachliche Auswahl ist nicht mehr aktuell."
        case .unauthorizedSelection:
            return "Die fachliche Auswahl liegt außerhalb des autorisierten Chat-Scopes."
        case .schemaIntegrityViolation:
            return "Das aktuelle Graph-Schema ist für diese lokale Abfrage nicht eindeutig."
        }
    }
}
