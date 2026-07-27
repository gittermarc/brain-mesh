//
//  GraphChatIntentInterpreter.swift
//  BrainMesh
//
//  Tool-free contract for an untrusted, bounded semantic intent draft.
//

import Foundation

nonisolated enum GraphChatSemanticIntentFamily:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case findNodes
    case entityList
    case unrecognized
    case openEnded
}

nonisolated enum GraphChatSemanticFindTarget:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case anyEntry
    case entities
    case attributes
    case entityNodes
}

nonisolated enum GraphChatSemanticResultAmount:
    Hashable,
    Sendable
{
    case standard
    case all
    case first(Int)
}

nonisolated enum GraphChatSemanticConversationReference:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case none
    case currentSelection
}

/// This is deliberately not a resolved identity. Every string remains
/// untrusted until the app validates and binds it against the live schema.
nonisolated struct GraphChatUntrustedSemanticIntentDraft:
    Hashable,
    Sendable
{
    let family: GraphChatSemanticIntentFamily
    let entityTerm: String?
    let searchTerm: String?
    let findTarget: GraphChatSemanticFindTarget
    let resultAmount: GraphChatSemanticResultAmount
    let conversationReference: GraphChatSemanticConversationReference
    let responseLanguage: GraphChatResponseLanguage

    init(
        family: GraphChatSemanticIntentFamily,
        entityTerm: String? = nil,
        searchTerm: String? = nil,
        findTarget: GraphChatSemanticFindTarget = .anyEntry,
        resultAmount: GraphChatSemanticResultAmount = .standard,
        conversationReference: GraphChatSemanticConversationReference = .none,
        responseLanguage: GraphChatResponseLanguage
    ) {
        self.family = family
        self.entityTerm = entityTerm
        self.searchTerm = searchTerm
        self.findTarget = findTarget
        self.resultAmount = resultAmount
        self.conversationReference = conversationReference
        self.responseLanguage = responseLanguage
    }
}

nonisolated struct GraphChatSemanticSchemaEntity:
    Hashable,
    Sendable
{
    let displayName: String
    let fieldDisplayNames: [String]
}

/// The interpreter request contains no graph, entity, field, node, result,
/// evidence, artifact, conversation, or turn identifiers.
nonisolated struct GraphChatIntentInterpreterRequest:
    Hashable,
    Sendable
{
    let normalizedQuestion: String
    let responseLanguage: GraphChatResponseLanguage
    let schemaEntities: [GraphChatSemanticSchemaEntity]
    let conversationDescriptions: [String]
    let scopeDescription: String
}

nonisolated enum GraphChatIntentInterpreterErrorCode:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case unavailable
    case cancelled
    case contextWindowExceeded
    case unsupportedLanguage
    case safetyGuardrail
    case invalidOutput
    case unexpected
}

nonisolated struct GraphChatIntentInterpreterError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    let code: GraphChatIntentInterpreterErrorCode
    let message: String

    var errorDescription: String? {
        message
    }

    static func cancelled() -> GraphChatIntentInterpreterError {
        GraphChatIntentInterpreterError(
            code: .cancelled,
            message: "Die lokale Intent-Interpretation wurde abgebrochen."
        )
    }
}

nonisolated protocol GraphChatIntentInterpreting: Sendable {
    func availability() async -> GraphChatModelAvailability

    func interpret(
        _ request: GraphChatIntentInterpreterRequest
    ) async throws -> GraphChatUntrustedSemanticIntentDraft
}

/// Compatibility default for injected test and non-Foundation-Models
/// environments. Production explicitly installs the Foundation Models
/// implementation.
nonisolated struct PassThroughGraphChatIntentInterpreter:
    GraphChatIntentInterpreting
{
    func availability() async -> GraphChatModelAvailability {
        .available
    }

    func interpret(
        _ request: GraphChatIntentInterpreterRequest
    ) async throws -> GraphChatUntrustedSemanticIntentDraft {
        try Task.checkCancellation()
        return GraphChatUntrustedSemanticIntentDraft(
            family: .openEnded,
            responseLanguage: request.responseLanguage
        )
    }
}

nonisolated enum GraphChatSemanticDraftValidationError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case languageMismatch
    case technicalIdentifier
    case overlongValue
    case invalidRequestedCount
    case invalidCombination

    var errorDescription: String? {
        switch self {
        case .languageMismatch:
            return "Die Antwortsprache des Semantic Draft stimmt nicht mit der Anfrage überein."
        case .technicalIdentifier:
            return "Der Semantic Draft enthält einen technischen Identifikator."
        case .overlongValue:
            return "Der Semantic Draft enthält einen überlangen Wert."
        case .invalidRequestedCount:
            return "Der Semantic Draft enthält eine ungültige gewünschte Ergebnismenge."
        case .invalidCombination:
            return "Der Semantic Draft enthält eine nicht unterstützte Kombination."
        }
    }
}

nonisolated enum GraphChatSemanticSafety {
    static let maximumEntityTermLength = 160
    static let maximumSearchTermLength = 240
    static let maximumRequestedCount = 10_000

    private static let forbiddenTechnicalWords: Set<String> = [
        "alias",
        "artifact",
        "artifactid",
        "artifactids",
        "describegraphschema",
        "evidence",
        "evidenceid",
        "evidenceids",
        "getneighbors",
        "getnode",
        "graphqueryplan",
        "graphstats",
        "navigation",
        "navigationtarget",
        "queryplan",
        "querydetailvalues",
        "repository",
        "resultlimit",
        "searchgraph",
        "toolrunner",
        "uuid",
    ]

    private static let uuidExpression = try? NSRegularExpression(
        pattern:
            #"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#
    )
    private static let aliasExpression = try? NSRegularExpression(
        pattern:
            #"(?i)\b(?:E|F|N)[_-]?\d+\b|\b(?:CR|CG|CI|CE|CF|CN|CC)(?:\d+|[_-][A-Z0-9]{1,40}(?:[_-]\d+)?)\b|\bCURRENT(?:[_-][A-Z0-9]{1,40})?\b|\bFOUNDATIONAL[_-][A-Z0-9]{1,40}\b|\bLAST[_-]COMPARISON\b"#
    )

    static func containsTechnicalIdentifier(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        if uuidExpression?.firstMatch(
            in: value,
            options: [],
            range: range
        ) != nil {
            return true
        }
        if aliasExpression?.firstMatch(
            in: value,
            options: [],
            range: range
        ) != nil {
            return true
        }
        let normalizedWords = value
            .lowercased()
            .components(
                separatedBy: CharacterSet.alphanumerics.inverted
            )
            .filter { $0.isEmpty == false }
        return normalizedWords.contains {
            forbiddenTechnicalWords.contains($0)
        }
    }

    static func normalizedOptional(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized.isEmpty ? nil : normalized
    }
}

nonisolated struct GraphChatSemanticDraftValidator:
    Hashable,
    Sendable
{
    func validate(
        _ source: GraphChatUntrustedSemanticIntentDraft,
        for request: GraphChatIntentInterpreterRequest
    ) throws -> GraphChatUntrustedSemanticIntentDraft {
        guard source.responseLanguage == request.responseLanguage else {
            throw GraphChatSemanticDraftValidationError
                .languageMismatch
        }

        let entityTerm = GraphChatSemanticSafety.normalizedOptional(
            source.entityTerm
        )
        let searchTerm = GraphChatSemanticSafety.normalizedOptional(
            source.searchTerm
        )
        for value in [entityTerm, searchTerm].compactMap({ $0 }) {
            guard GraphChatSemanticSafety.containsTechnicalIdentifier(value)
                    == false else {
                throw GraphChatSemanticDraftValidationError
                    .technicalIdentifier
            }
        }
        if let entityTerm {
            guard entityTerm.count
                    <= GraphChatSemanticSafety.maximumEntityTermLength else {
                throw GraphChatSemanticDraftValidationError
                    .overlongValue
            }
        }
        if let searchTerm {
            guard searchTerm.count
                    <= GraphChatSemanticSafety.maximumSearchTermLength else {
                throw GraphChatSemanticDraftValidationError
                    .overlongValue
            }
        }
        if case .first(let count) = source.resultAmount {
            guard count > 0,
                  count <= GraphChatSemanticSafety.maximumRequestedCount else {
                throw GraphChatSemanticDraftValidationError
                    .invalidRequestedCount
            }
        }

        switch source.family {
        case .findNodes:
            guard searchTerm != nil else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }
            if source.findTarget == .entityNodes {
                guard entityTerm != nil
                        || source.conversationReference
                            == .currentSelection else {
                    throw GraphChatSemanticDraftValidationError
                        .invalidCombination
                }
            }

        case .entityList:
            guard entityTerm != nil,
                  searchTerm == nil,
                  source.findTarget == .anyEntry else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .unrecognized, .openEnded:
            guard entityTerm == nil,
                  searchTerm == nil,
                  source.findTarget == .anyEntry,
                  source.resultAmount == .standard,
                  source.conversationReference == .none else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }
        }

        return GraphChatUntrustedSemanticIntentDraft(
            family: source.family,
            entityTerm: entityTerm,
            searchTerm: searchTerm,
            findTarget: source.findTarget,
            resultAmount: source.resultAmount,
            conversationReference: source.conversationReference,
            responseLanguage: source.responseLanguage
        )
    }
}
