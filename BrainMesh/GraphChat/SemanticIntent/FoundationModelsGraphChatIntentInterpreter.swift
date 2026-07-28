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
private nonisolated struct FoundationGraphChatGeneratedFilterDraft {
    @Guide(
        description:
            "Exact user-visible field display name from the supplied schema."
    )
    var fieldTerm: String

    @Guide(
        description:
            "Exactly one of unspecified, contains, equals, startsWith, isPresent, isMissing, lessThan, lessThanOrEqual, greaterThan, greaterThanOrEqual, between, before, after, inYear, inMonth, isOverdue, or oneOf."
    )
    var relation: String

    @Guide(
        description:
            "Literal user values only. Use no values for isPresent, isMissing, and isOverdue; two for between; otherwise the explicitly requested values."
    )
    var values: [String]
}

@Generable
private nonisolated struct FoundationGraphChatGeneratedIntentDraft {
    @Guide(
        description:
            "Exactly one of findNodes, entityList, filteredCollection, count, groupCount, refinement, unrecognized, or openEnded."
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
            "Bounded semantic filters using only visible field names, domain relations, and literal user values."
    )
    var filters: [FoundationGraphChatGeneratedFilterDraft]

    @Guide(
        description:
            "Exactly one of none, nodeName, or field."
    )
    var sortTarget: String

    @Guide(
        description:
            "Exact visible field name when sortTarget is field; otherwise empty."
    )
    var sortFieldTerm: String

    @Guide(
        description:
            "Exactly one of unspecified, ascending, or descending."
    )
    var sortDirection: String

    @Guide(
        description:
            "Visible schema field names explicitly requested for display. Node identity is automatic; never include node name or IDs."
    )
    var projectionTerms: [String]

    @Guide(
        description:
            "Exact visible field name for groupCount; otherwise empty."
    )
    var groupFieldTerm: String

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
        Use findNodes for natural search requests and entityList for unfiltered collections of one entity.
        Use filteredCollection for a new collection constrained by one or more field meanings.
        Use count for a requested count and groupCount for counts grouped by one visible field.
        Use refinement for filtering, sorting, or projecting the revalidated current result set.
        Use unrecognized when the meaning does not match those families.
        Use openEnded only when the user explicitly asks an open-ended graph question that needs the legacy answer flow.
        When an entity type is clear, place only its exact supplied display name in entityTerm; never an alias or ID.
        Put only exact supplied field display names in filters, sortFieldTerm, projectionTerms, and groupFieldTerm.
        Node identity is projected by the app; never place node name in projectionTerms.
        Preserve user values literally. Describe only the semantic relation; the app chooses operators and parses typed values.
        Use conversationReference=currentSelection only when the user refers to prior results, such as these, those, davon, or diese Gruppe.
        Keep searchTerm to the subject being searched for, without entity-category filler when it is safely separable.
        Use entityNodes only when the user asks for nodes belonging to one entity.
        Use standard, all, or first only to preserve the user's requested amount; the app chooses the technical limit.
        Copy only short user-visible wording into semantic string fields.
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
            let sortDirection =
                GraphChatSemanticSortDirection(
                    rawValue: generated.sortDirection
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

        let filters = try generated.filters.map { source in
            guard
                let relation =
                    GraphChatSemanticFilterRelation(
                        rawValue: source.relation
                    )
            else {
                throw invalidOutput()
            }
            return GraphChatSemanticFilterDraft(
                fieldTerm: source.fieldTerm,
                relation: relation,
                values: source.values
            )
        }
        let sorting: GraphChatSemanticSortDraft?
        switch generated.sortTarget {
        case "none":
            guard generated.sortFieldTerm
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty,
                  sortDirection == .unspecified else {
                throw invalidOutput()
            }
            sorting = nil
        case GraphChatSemanticSortTarget.nodeName.rawValue:
            guard generated.sortFieldTerm
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty else {
                throw invalidOutput()
            }
            sorting = GraphChatSemanticSortDraft(
                target: .nodeName,
                fieldTerm: nil,
                direction: sortDirection
            )
        case GraphChatSemanticSortTarget.field.rawValue:
            sorting = GraphChatSemanticSortDraft(
                target: .field,
                fieldTerm: generated.sortFieldTerm,
                direction: sortDirection
            )
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
            filters: filters,
            sorting: sorting,
            projectionTerms:
                generated.projectionTerms,
            groupFieldTerm:
                generated.groupFieldTerm,
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
