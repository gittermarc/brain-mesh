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
    case filteredCollection
    case count
    case groupCount
    case refinement
    case nodeDetails
    case compareNodes
    case inspectGraphState
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

nonisolated enum GraphChatSemanticFilterRelation:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case unspecified
    case contains
    case equals
    case startsWith
    case isPresent
    case isMissing
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
    case between
    case before
    case after
    case inYear
    case inMonth
    case isOverdue
    case oneOf
}

nonisolated struct GraphChatSemanticFilterDraft:
    Hashable,
    Sendable
{
    let fieldTerm: String
    let relation: GraphChatSemanticFilterRelation
    let values: [String]
}

nonisolated enum GraphChatSemanticSortTarget:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case nodeName
    case field
}

nonisolated enum GraphChatSemanticSortDirection:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case unspecified
    case ascending
    case descending
}

nonisolated struct GraphChatSemanticSortDraft:
    Hashable,
    Sendable
{
    let target: GraphChatSemanticSortTarget
    let fieldTerm: String?
    let direction: GraphChatSemanticSortDirection
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
    let nodeTerms: [String]
    let findTarget: GraphChatSemanticFindTarget
    let resultAmount: GraphChatSemanticResultAmount
    let conversationReference: GraphChatSemanticConversationReference
    let filters: [GraphChatSemanticFilterDraft]
    let sorting: GraphChatSemanticSortDraft?
    let projectionTerms: [String]
    let groupFieldTerm: String?
    let graphStateAspect: GraphChatGraphStateAspect
    let responseLanguage: GraphChatResponseLanguage

    init(
        family: GraphChatSemanticIntentFamily,
        entityTerm: String? = nil,
        searchTerm: String? = nil,
        nodeTerms: [String] = [],
        findTarget: GraphChatSemanticFindTarget = .anyEntry,
        resultAmount: GraphChatSemanticResultAmount = .standard,
        conversationReference: GraphChatSemanticConversationReference = .none,
        filters: [GraphChatSemanticFilterDraft] = [],
        sorting: GraphChatSemanticSortDraft? = nil,
        projectionTerms: [String] = [],
        groupFieldTerm: String? = nil,
        graphStateAspect:
            GraphChatGraphStateAspect = .overview,
        responseLanguage: GraphChatResponseLanguage
    ) {
        self.family = family
        self.entityTerm = entityTerm
        self.searchTerm = searchTerm
        self.nodeTerms = nodeTerms
        self.findTarget = findTarget
        self.resultAmount = resultAmount
        self.conversationReference = conversationReference
        self.filters = filters
        self.sorting = sorting
        self.projectionTerms = projectionTerms
        self.groupFieldTerm = groupFieldTerm
        self.graphStateAspect = graphStateAspect
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
    static let maximumFieldTermLength = 160
    static let maximumFilterValueLength = 240
    static let maximumFilters = 8
    static let maximumValuesPerFilter = 8
    static let maximumProjectionTerms =
        GraphChatAnswerArtifactFactoryBudget
            .default.maximumColumns - 1
    static let maximumNodeTerms =
        GraphChatAdvancedIntentPolicy
            .default.maximumComparisonNodeCount
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
        let groupFieldTerm =
            GraphChatSemanticSafety.normalizedOptional(
                source.groupFieldTerm
            )
        let filters = try normalizedFilters(source.filters)
        let sorting = try normalizedSorting(source.sorting)
        let projectionTerms = try normalizedProjectionTerms(
            source.projectionTerms
        )
        let nodeTerms = try normalizedNodeTerms(
            source.nodeTerms
        )
        let semanticValues =
            [entityTerm, searchTerm, groupFieldTerm]
                .compactMap { $0 }
            + filters.flatMap {
                [$0.fieldTerm] + $0.values
            }
            + projectionTerms
            + nodeTerms
            + [sorting?.fieldTerm].compactMap { $0 }
        for value in semanticValues {
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
        if let groupFieldTerm {
            guard groupFieldTerm.count
                    <= GraphChatSemanticSafety
                        .maximumFieldTermLength else {
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
            guard filters.isEmpty,
                  sorting == nil,
                  projectionTerms.isEmpty,
                  groupFieldTerm == nil else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .entityList:
            guard entityTerm != nil,
                  searchTerm == nil,
                  source.findTarget == .anyEntry,
                  source.conversationReference == .none,
                  filters.isEmpty,
                  groupFieldTerm == nil else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .filteredCollection:
            guard
                entityTerm != nil,
                searchTerm == nil,
                source.findTarget == .anyEntry,
                source.conversationReference == .none,
                filters.isEmpty == false,
                groupFieldTerm == nil
            else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .count:
            guard
                entityTerm != nil
                    || source.conversationReference
                        == .currentSelection,
                searchTerm == nil,
                source.findTarget == .anyEntry,
                sorting == nil,
                projectionTerms.isEmpty,
                groupFieldTerm == nil,
                source.resultAmount == .standard
            else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .groupCount:
            guard
                entityTerm != nil
                    || source.conversationReference
                        == .currentSelection,
                searchTerm == nil,
                source.findTarget == .anyEntry,
                sorting == nil,
                projectionTerms.isEmpty,
                groupFieldTerm != nil
            else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .refinement:
            guard searchTerm == nil,
                  source.findTarget == .anyEntry,
                  source.conversationReference
                    == .currentSelection,
                  groupFieldTerm == nil,
                  filters.isEmpty == false
                    || sorting != nil
                    || projectionTerms.isEmpty == false else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .nodeDetails:
            guard
                searchTerm == nil,
                source.findTarget == .anyEntry,
                source.resultAmount == .standard,
                filters.isEmpty,
                sorting == nil,
                groupFieldTerm == nil,
                nodeTerms.count == 1
                    || nodeTerms.isEmpty
            else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .compareNodes:
            guard
                searchTerm == nil,
                source.findTarget == .anyEntry,
                source.resultAmount == .standard,
                filters.isEmpty,
                sorting == nil,
                groupFieldTerm == nil,
                nodeTerms.count >= 2
                    || nodeTerms.isEmpty
            else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .inspectGraphState:
            guard entityTerm == nil,
                  searchTerm == nil,
                  nodeTerms.isEmpty,
                  source.findTarget == .anyEntry,
                  source.resultAmount == .standard,
                  source.conversationReference == .none,
                  filters.isEmpty,
                  sorting == nil,
                  projectionTerms.isEmpty,
                  groupFieldTerm == nil else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }

        case .unrecognized, .openEnded:
            guard entityTerm == nil,
                  searchTerm == nil,
                  nodeTerms.isEmpty,
                  source.findTarget == .anyEntry,
                  source.resultAmount == .standard,
                  source.conversationReference == .none,
                  filters.isEmpty,
                  sorting == nil,
                  projectionTerms.isEmpty,
                  groupFieldTerm == nil else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }
        }

        return GraphChatUntrustedSemanticIntentDraft(
            family: source.family,
            entityTerm: entityTerm,
            searchTerm: searchTerm,
            nodeTerms: nodeTerms,
            findTarget: source.findTarget,
            resultAmount: source.resultAmount,
            conversationReference: source.conversationReference,
            filters: filters,
            sorting: sorting,
            projectionTerms: projectionTerms,
            groupFieldTerm: groupFieldTerm,
            graphStateAspect:
                source.graphStateAspect,
            responseLanguage: source.responseLanguage
        )
    }

    private func normalizedNodeTerms(
        _ source: [String]
    ) throws -> [String] {
        guard source.count
                <= GraphChatSemanticSafety.maximumNodeTerms
        else {
            throw GraphChatSemanticDraftValidationError
                .invalidCombination
        }
        var seen = Set<String>()
        return try source.compactMap { value in
            guard
                let normalized =
                    GraphChatSemanticSafety
                        .normalizedOptional(value),
                normalized.count
                    <= GraphChatSemanticSafety
                        .maximumSearchTermLength
            else {
                throw GraphChatSemanticDraftValidationError
                    .overlongValue
            }
            let key = BMSearch.fold(normalized)
            return seen.insert(key).inserted
                ? normalized
                : nil
        }
    }

    private func normalizedFilters(
        _ source: [GraphChatSemanticFilterDraft]
    ) throws -> [GraphChatSemanticFilterDraft] {
        guard source.count
                <= GraphChatSemanticSafety.maximumFilters else {
            throw GraphChatSemanticDraftValidationError
                .invalidCombination
        }
        return try source.map { filter in
            guard
                let fieldTerm =
                    GraphChatSemanticSafety.normalizedOptional(
                        filter.fieldTerm
                    ),
                fieldTerm.count
                    <= GraphChatSemanticSafety
                        .maximumFieldTermLength,
                filter.values.count
                    <= GraphChatSemanticSafety
                        .maximumValuesPerFilter
            else {
                throw GraphChatSemanticDraftValidationError
                    .overlongValue
            }
            let values = try filter.values.map { value in
                guard
                    let normalized =
                        GraphChatSemanticSafety
                            .normalizedOptional(value),
                    normalized.count
                        <= GraphChatSemanticSafety
                            .maximumFilterValueLength
                else {
                    throw GraphChatSemanticDraftValidationError
                        .overlongValue
                }
                return normalized
            }
            let expectedValueCount: ClosedRange<Int>
            switch filter.relation {
            case .isPresent, .isMissing, .isOverdue:
                expectedValueCount = 0...0
            case .between:
                expectedValueCount = 2...2
            case .oneOf:
                expectedValueCount =
                    1...GraphChatSemanticSafety
                        .maximumValuesPerFilter
            case .unspecified, .equals:
                expectedValueCount =
                    1...GraphChatSemanticSafety
                        .maximumValuesPerFilter
            case .contains, .startsWith, .lessThan,
                .lessThanOrEqual, .greaterThan,
                .greaterThanOrEqual, .before, .after,
                .inYear, .inMonth:
                expectedValueCount = 1...1
            }
            guard expectedValueCount.contains(values.count) else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }
            return GraphChatSemanticFilterDraft(
                fieldTerm: fieldTerm,
                relation: filter.relation,
                values: values
            )
        }
    }

    private func normalizedSorting(
        _ source: GraphChatSemanticSortDraft?
    ) throws -> GraphChatSemanticSortDraft? {
        guard let source else {
            return nil
        }
        let fieldTerm =
            GraphChatSemanticSafety.normalizedOptional(
                source.fieldTerm
            )
        switch source.target {
        case .nodeName:
            guard fieldTerm == nil else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }
        case .field:
            guard let fieldTerm,
                  fieldTerm.count
                    <= GraphChatSemanticSafety
                        .maximumFieldTermLength else {
                throw GraphChatSemanticDraftValidationError
                    .invalidCombination
            }
        }
        return GraphChatSemanticSortDraft(
            target: source.target,
            fieldTerm: fieldTerm,
            direction: source.direction
        )
    }

    private func normalizedProjectionTerms(
        _ source: [String]
    ) throws -> [String] {
        guard source.count
                <= GraphChatSemanticSafety
                    .maximumProjectionTerms else {
            throw GraphChatSemanticDraftValidationError
                .invalidCombination
        }
        return try source.map { value in
            guard
                let normalized =
                    GraphChatSemanticSafety
                        .normalizedOptional(value),
                normalized.count
                    <= GraphChatSemanticSafety
                        .maximumFieldTermLength
            else {
                throw GraphChatSemanticDraftValidationError
                    .overlongValue
            }
            return normalized
        }
    }
}
