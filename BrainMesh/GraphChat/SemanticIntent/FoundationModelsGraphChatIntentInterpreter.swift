//
//  FoundationModelsGraphChatIntentInterpreter.swift
//  BrainMesh
//
//  Tool-free, on-device semantic interpretation for the bounded intent draft.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@Generable
private nonisolated struct FoundationGraphChatGeneratedIntentDraft {
    @Guide(
        description:
            "Exactly one of findNodes, entityList, unrecognized, or openEnded."
    )
    var family: String

    @Guide(
        description:
            "Exact user-visible entity display name from the supplied schema when clearly meant; otherwise empty."
    )
    var entityTerm: String

    @Guide(
        description:
            "The user's literal search meaning only. Use an empty string when absent."
    )
    var searchTerm: String

    @Guide(
        description:
            "Exactly one of anyEntry, entities, attributes, or entityNodes."
    )
    var findTarget: String

    @Guide(
        description:
            "Exactly one of standard, all, or first."
    )
    var resultAmount: String

    @Guide(
        description:
            "Requested count for first, otherwise zero.",
        .range(0...10_000)
    )
    var firstCount: Int

    @Guide(
        description:
            "Exactly one of none or currentSelection."
    )
    var conversationReference: String

    @Guide(
        description:
            "Exactly one of german or english."
    )
    var responseLanguage: String
}

actor FoundationModelsGraphChatIntentInterpreter:
    GraphChatIntentInterpreting
{
    func availability() -> GraphChatModelAvailability {
        FoundationModelsGraphChatAvailability.current()
    }

    func interpret(
        _ request: GraphChatIntentInterpreterRequest
    ) async throws -> GraphChatUntrustedSemanticIntentDraft {
        guard availability().isAvailable else {
            throw GraphChatIntentInterpreterError(
                code: .unavailable,
                message:
                    "Das lokale Foundation Model ist für die Intent-Interpretation nicht verfügbar."
            )
        }

        do {
            try Task.checkCancellation()
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                tools: [],
                instructions: instructions
            )
            let stream = session.streamResponse(
                to: prompt(for: request),
                generating:
                    FoundationGraphChatGeneratedIntentDraft.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(sampling: .greedy)
            )
            let response = try await stream.collect()
            try Task.checkCancellation()
            return try draft(
                from: response.content,
                request: request
            )
        } catch is CancellationError {
            throw GraphChatIntentInterpreterError.cancelled()
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw GraphChatIntentInterpreterError(
                code: .contextWindowExceeded,
                message:
                    "Der begrenzte Intent-Kontext überschreitet das lokale Modellfenster."
            )
        } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
            throw GraphChatIntentInterpreterError(
                code: .unsupportedLanguage,
                message:
                    "Die Sprache der Anfrage wird vom lokalen Intent-Interpreter nicht unterstützt."
            )
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            throw GraphChatIntentInterpreterError(
                code: .safetyGuardrail,
                message:
                    "Die lokale Sicherheitsprüfung hat die Intent-Interpretation blockiert."
            )
        } catch let error as GraphChatIntentInterpreterError {
            throw error
        } catch {
            if Task.isCancelled {
                throw GraphChatIntentInterpreterError.cancelled()
            }
            throw GraphChatIntentInterpreterError(
                code: .unexpected,
                message:
                    "Das lokale Modell konnte keinen sicheren Semantic Draft erzeugen."
            )
        }
    }

    private var instructions: String {
        """
        You are a narrow semantic classifier. You have no tools and never answer the user.
        Return only the generated value. Describe user meaning, never technical execution.
        Never emit UUIDs, aliases, IDs, query plans, tool names, evidence, artifacts, repositories, navigation, limits chosen by the app, or prose answers.
        Use findNodes for natural search requests and entityList for natural requests to list nodes of one entity.
        Use unrecognized when the meaning does not match those families.
        Use openEnded only when the user explicitly asks an open-ended graph question that needs the legacy answer flow.
        When an entity type is clear, place only its exact supplied display name in entityTerm; never an alias or ID.
        Keep searchTerm to the subject being searched for, without entity-category filler when it is safely separable.
        Use entityNodes only when the user asks for nodes belonging to one entity.
        Use standard, all, or first only to preserve the user's requested amount; the app chooses the technical limit.
        Copy only short user-visible wording into entityTerm and searchTerm.
        Internal identities are unavailable and must never be invented.
        """
    }

    private func prompt(
        for request: GraphChatIntentInterpreterRequest
    ) -> String {
        let schema = request.schemaEntities.map { entity in
            let fields = entity.fieldDisplayNames.joined(
                separator: ", "
            )
            return fields.isEmpty
                ? "- \(entity.displayName)"
                : "- \(entity.displayName): \(fields)"
        }.joined(separator: "\n")
        let conversation = request.conversationDescriptions
            .map { "- \($0)" }
            .joined(separator: "\n")
        return """
        RESPONSE LANGUAGE
        \(request.responseLanguage.rawValue)

        USER-VISIBLE SCOPE
        \(request.scopeDescription)

        USER-VISIBLE SCHEMA NAMES
        \(schema.isEmpty ? "- none" : schema)

        SAFE CONVERSATION DESCRIPTIONS
        \(conversation.isEmpty ? "- none" : conversation)

        NORMALIZED USER QUESTION
        \(request.normalizedQuestion)
        """
    }

    private func draft(
        from generated:
            FoundationGraphChatGeneratedIntentDraft,
        request: GraphChatIntentInterpreterRequest
    ) throws -> GraphChatUntrustedSemanticIntentDraft {
        guard
            let family = GraphChatSemanticIntentFamily(
                rawValue: generated.family
            ),
            let target = GraphChatSemanticFindTarget(
                rawValue: generated.findTarget
            ),
            let reference =
                GraphChatSemanticConversationReference(
                    rawValue: generated.conversationReference
                ),
            let language = GraphChatResponseLanguage(
                rawValue: generated.responseLanguage
            )
        else {
            throw invalidOutput()
        }

        let amount: GraphChatSemanticResultAmount
        switch generated.resultAmount {
        case "standard":
            guard generated.firstCount == 0 else {
                throw invalidOutput()
            }
            amount = .standard
        case "all":
            guard generated.firstCount == 0 else {
                throw invalidOutput()
            }
            amount = .all
        case "first":
            guard generated.firstCount > 0 else {
                throw invalidOutput()
            }
            amount = .first(generated.firstCount)
        default:
            throw invalidOutput()
        }

        guard language == request.responseLanguage else {
            throw invalidOutput()
        }
        return GraphChatUntrustedSemanticIntentDraft(
            family: family,
            entityTerm: generated.entityTerm,
            searchTerm: generated.searchTerm,
            findTarget: target,
            resultAmount: amount,
            conversationReference: reference,
            responseLanguage: language
        )
    }

    private func invalidOutput()
        -> GraphChatIntentInterpreterError
    {
        GraphChatIntentInterpreterError(
            code: .invalidOutput,
            message:
                "Das lokale Modell hat einen ungültigen Semantic Draft erzeugt."
        )
    }
}

#else

actor FoundationModelsGraphChatIntentInterpreter:
    GraphChatIntentInterpreting
{
    func availability() -> GraphChatModelAvailability {
        FoundationModelsGraphChatAvailability.current()
    }

    func interpret(
        _ request: GraphChatIntentInterpreterRequest
    ) throws -> GraphChatUntrustedSemanticIntentDraft {
        throw GraphChatIntentInterpreterError(
            code: .unavailable,
            message:
                "Foundation Models ist in diesem SDK nicht verfügbar."
        )
    }
}

#endif
