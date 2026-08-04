//
//  GraphChatCapabilityQuestionValidator.swift
//  BrainMesh
//
//  Production-path proof for concrete graph-chat guidance questions.
//

import Foundation

nonisolated struct GraphChatCapabilityQuestionValidation:
    Hashable,
    Sendable
{
    let capabilityID: GraphChatCapabilityID
    let compilerFamily: GraphChatCapabilityCompilerFamily
    let typedIntentKind: GraphChatTypedIntentKind
    let readPlanFamily: GraphChatCapabilityReadPlanFamily
    let readPlanVersion: GraphChatComposableReadPlanVersion
    let queryPlanVersion: Int
}

nonisolated struct GraphChatCapabilityQuestionValidator:
    Sendable
{
    private let foundationalCompiler:
        GraphChatFoundationalIntentCompiler
    private let foundationalAdapter:
        GraphChatFoundationalIntentAdapter
    private let relationshipFastPath:
        GraphChatRelationshipFastPathCompiler
    private let composableReadFastPath:
        GraphChatComposableReadFastPathCompiler
    private let requestBuilder:
        GraphChatIntentInterpreterRequestBuilder
    private let draftValidator:
        GraphChatSemanticDraftValidator
    private let semanticResolver:
        GraphChatSemanticIntentResolver
    private let instrumentation:
        GraphChatSuggestionsInstrumentation

    init(
        foundationalCompiler:
            GraphChatFoundationalIntentCompiler =
                GraphChatFoundationalIntentCompiler(),
        foundationalAdapter:
            GraphChatFoundationalIntentAdapter =
                GraphChatFoundationalIntentAdapter(),
        relationshipFastPath:
            GraphChatRelationshipFastPathCompiler =
                GraphChatRelationshipFastPathCompiler(),
        composableReadFastPath:
            GraphChatComposableReadFastPathCompiler =
                GraphChatComposableReadFastPathCompiler(),
        requestBuilder:
            GraphChatIntentInterpreterRequestBuilder =
                GraphChatIntentInterpreterRequestBuilder(),
        draftValidator:
            GraphChatSemanticDraftValidator =
                GraphChatSemanticDraftValidator(),
        semanticResolver:
            GraphChatSemanticIntentResolver =
                GraphChatSemanticIntentResolver(),
        instrumentation:
            GraphChatSuggestionsInstrumentation = .disabled
    ) {
        self.foundationalCompiler = foundationalCompiler
        self.foundationalAdapter = foundationalAdapter
        self.relationshipFastPath = relationshipFastPath
        self.composableReadFastPath =
            composableReadFastPath
        self.requestBuilder = requestBuilder
        self.draftValidator = draftValidator
        self.semanticResolver = semanticResolver
        self.instrumentation = instrumentation
    }

    func validate(
        question: String,
        capability: GraphChatCapability,
        schemaContext: GraphSchemaContext,
        chatScope: GraphChatScope,
        language: GraphChatResponseLanguage,
        mentionCatalog: GraphMentionCatalog? = nil
    ) -> GraphChatCapabilityQuestionValidation? {
        instrumentation.record(
            .capabilityValidation(capability.id)
        )
        let catalog = mentionCatalog ?? GraphMentionCatalog(
            schemaContext: schemaContext
        )
        guard
            GraphChatCapabilityCatalog.capability(
                withID: capability.id
            ) == capability,
            schemaContext.graphScope == chatScope.graphScope,
            schemaContext.aliases.graphScope
                == schemaContext.graphScope,
            schemaContext.foundationalAliases.graphScope
                == schemaContext.graphScope,
            catalog.graphScope == schemaContext.graphScope
        else {
            return nil
        }
        let normalizedQuestion = question
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard
            normalizedQuestion.count
                <= GraphChatIntentLimitPolicy
                    .default.maximumQuestionLength,
            normalizedQuestion.isEmpty == false,
            GraphChatSemanticSafety
                .containsTechnicalIdentifier(
                    normalizedQuestion
                ) == false,
            GraphChatResponseLanguageSelector(
                fallback: language
            ).language(for: normalizedQuestion)
                == language
        else {
            return nil
        }

        let requestID = Self.requestID
        let conversationState =
            GraphChatConversationState.initial(
                graphScope: schemaContext.graphScope,
                chatScope: chatScope,
                conversationID: Self.conversationID
            )
        let providerPlan = makeProviderPlan(
            question: normalizedQuestion,
            language: language,
            state: conversationState
        )
        let foundationalInput =
            GraphChatFoundationalIntentCompilerInput(
                requestID: requestID,
                question: normalizedQuestion,
                graphScope: schemaContext.graphScope,
                chatScope: chatScope,
                responseLanguage: language,
                conversationState: conversationState,
                schemaContext: schemaContext,
                selectedCandidate: nil,
                sourceTurnID: nil,
                clarificationID: nil
            )

        do {
            try Task.checkCancellation()
            instrumentation.record(
                .intentCompiler(
                    capability.productionPath.compilerFamily
                )
            )
            let adaptation: GraphChatTypedIntentAdaptation
            switch capability.productionPath.compilerFamily {
            case .foundationalEntityCollection,
                .foundationalNodeProfile:
                guard case .compiled(let intent) =
                        foundationalCompiler.compile(
                            foundationalInput,
                            mentionCatalog: catalog
                        ) else {
                    return nil
                }
                adaptation = try foundationalAdapter.adapt(
                    intent
                )

            case .deterministicDirectRelationship:
                guard foundationalCompiler.compile(
                    foundationalInput,
                    mentionCatalog: catalog
                ) == .notRecognized,
                composableReadFastPath.compile(
                    question: normalizedQuestion,
                    language: language,
                    schemaContext: schemaContext,
                    chatScope: chatScope,
                    mentionCatalog: catalog
                ) == nil,
                let draft = relationshipFastPath.compile(
                    question: normalizedQuestion,
                    language: language
                ) else {
                    return nil
                }
                adaptation = try semanticAdaptation(
                    draft: draft,
                    providerPlan: providerPlan,
                    schemaContext: schemaContext,
                    requestID: requestID,
                    mentionCatalog: catalog
                )

            case .deterministicFrequencyRelationship:
                guard foundationalCompiler.compile(
                    foundationalInput,
                    mentionCatalog: catalog
                ) == .notRecognized,
                let draft = composableReadFastPath.compile(
                    question: normalizedQuestion,
                    language: language,
                    schemaContext: schemaContext,
                    chatScope: chatScope,
                    mentionCatalog: catalog
                ) else {
                    return nil
                }
                adaptation = try semanticAdaptation(
                    draft: draft,
                    providerPlan: providerPlan,
                    schemaContext: schemaContext,
                    requestID: requestID,
                    mentionCatalog: catalog
                )
            }

            guard adaptation.intent.kind
                    == capability.productionPath.typedIntentKind else {
                return nil
            }
            try Task.checkCancellation()
            instrumentation.record(
                .readPlanValidation(capability.id)
            )
            let validated = try makePlanValidator().validate(
                adaptation.readPlan,
                for: adaptation.intent,
                schemaContext: schemaContext,
                providerPlan: providerPlan
            )
            guard matches(
                validated.plan.resultContract,
                family:
                    capability.productionPath.readPlanFamily
            ), matches(
                validated.action,
                compilerFamily:
                    capability.productionPath.compilerFamily
            ) else {
                return nil
            }
            return GraphChatCapabilityQuestionValidation(
                capabilityID: capability.id,
                compilerFamily:
                    capability.productionPath.compilerFamily,
                typedIntentKind: adaptation.intent.kind,
                readPlanFamily:
                    capability.productionPath.readPlanFamily,
                readPlanVersion: validated.plan.version,
                queryPlanVersion:
                    validated.plan.queryPlanVersion
            )
        } catch {
            return nil
        }
    }

    private func semanticAdaptation(
        draft: GraphChatUntrustedSemanticIntentDraft,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        mentionCatalog: GraphMentionCatalog
    ) throws -> GraphChatTypedIntentAdaptation {
        let request = try requestBuilder.makeRequest(
            providerPlan: providerPlan,
            schemaContext: schemaContext
        )
        let validatedDraft = try draftValidator.validate(
            draft,
            for: request
        )
        let resolution = try semanticResolver.resolve(
            draft: validatedDraft,
            selectedEntityID: nil,
            selectedRelationshipCounterpartEntityID: nil,
            selectedComposableIntermediateEntityID: nil,
            selectedFields: [],
            selectedNodes: [],
            currentResolvedScope: nil,
            providerPlan: providerPlan,
            schemaContext: schemaContext,
            requestID: requestID,
            sourceTurnID: nil,
            clarificationID: nil,
            referenceDate: Self.referenceDate,
            mentionCatalog: mentionCatalog
        )
        guard case .compiled(let adaptation) = resolution else {
            throw GraphChatCapabilityQuestionValidationError
                .notCompiled
        }
        return adaptation
    }

    private func makeProviderPlan(
        question: String,
        language: GraphChatResponseLanguage,
        state: GraphChatConversationState
    ) -> GraphChatProviderTurnPlan {
        GraphChatProviderTurnPlan(
            scopeKey: GraphChatOrchestrationScopeKey(
                graphScope: state.graphScope,
                chatScope: state.chatScope
            ),
            normalizedQuestion: question,
            providerQuestion: question,
            responseLanguage: language,
            requestBaseState: state,
            expectedCommittedState: state,
            conversationContext:
                GraphChatConversationContextBuilder()
                    .makeSnapshot(from: state.snapshot),
            currentReference: nil,
            currentResolvedScope: nil,
            continuationOperation: nil,
            foundationalContinuation: nil,
            semanticContinuation: nil
        )
    }

    private func makePlanValidator()
        -> GraphChatComposableReadPlanValidator {
        GraphChatComposableReadPlanValidator(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            referenceDate: { Self.referenceDate }
        )
    }

    private func matches(
        _ resultContract:
            GraphChatComposableReadResultContract,
        family: GraphChatCapabilityReadPlanFamily
    ) -> Bool {
        switch (family, resultContract) {
        case (.entityCollection, .entityCollection),
            (.nodeProfile, .nodeProfile),
            (.directRelationships, .relationships),
            (
                .composableNodeCollection,
                .composableNodeCollection
            ):
            return true
        default:
            return false
        }
    }

    private func matches(
        _ action: GraphChatLocalIntentAction,
        compilerFamily: GraphChatCapabilityCompilerFamily
    ) -> Bool {
        switch (compilerFamily, action) {
        case (
            .foundationalEntityCollection,
            .queryDetailValues
        ), (
            .foundationalNodeProfile,
            .nodeDetails
        ), (
            .deterministicDirectRelationship,
            .relationships
        ), (
            .deterministicFrequencyRelationship,
            .composableRead
        ):
            return true
        default:
            return false
        }
    }

    private static let requestID = UUID(
        uuidString: "C4100000-0000-0000-0000-000000000001"
    )!
    private static let conversationID = UUID(
        uuidString: "C4100000-0000-0000-0000-000000000002"
    )!
    private static let referenceDate = Date(
        timeIntervalSinceReferenceDate: 0
    )
}

private nonisolated enum GraphChatCapabilityQuestionValidationError:
    Error,
    Sendable
{
    case notCompiled
}
