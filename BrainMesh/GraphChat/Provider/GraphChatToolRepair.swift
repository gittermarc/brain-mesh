//
//  GraphChatToolRepair.swift
//  BrainMesh
//
//  Request-bound, exactly-once repair contracts for semantic model tool calls.
//

import Foundation

nonisolated enum GraphChatToolRepairReason: String, CaseIterable, Codable, Hashable, Sendable {
    case unknownEntityAlias
    case fieldEntityMismatch
    case invalidOperator
    case conversationReferenceMismatch
    case similarName
    case schemaIncompatibility
}

nonisolated enum GraphChatToolNonRepairableReason: String, CaseIterable, Hashable, Sendable {
    case graphScopeViolation
    case unauthorizedNodeOrSelectionScope
    case repositoryOrStorageFailure
    case cancellation
    case sessionOrTurnMismatch
    case manipulatedTechnicalIdentifier
    case staleConversationReference
    case securityOrToolBudgetExceeded
}

nonisolated enum GraphChatToolFailureTaxonomy: Hashable, Sendable {
    case repairable(GraphChatToolRepairReason)
    case nonRepairable(GraphChatToolNonRepairableReason)

    static func nonRepairableReason(
        for error: Error
    ) -> GraphChatToolNonRepairableReason {
        if error is CancellationError {
            return .cancellation
        }
        if let error = error as? GraphChatToolNonRepairableError {
            return error.reason
        }
        if let error = error as? GraphChatToolError {
            switch error.code {
            case .graphScopeMismatch:
                return .graphScopeViolation
            case .budgetExceeded:
                return .securityOrToolBudgetExceeded
            case .cancelled:
                return .cancellation
            case .indexUnavailable, .sourceUnavailable, .unavailable:
                return .repositoryOrStorageFailure
            case .invalidInput:
                return .sessionOrTurnMismatch
            }
        }
        if let error = error as? GraphQueryPlanValidationError {
            if error.issues.contains(where: {
                $0.code == .graphScopeMismatch
            }) {
                return .graphScopeViolation
            }
            if error.issues.contains(where: {
                [
                    .unknownScopeEntity,
                    .unknownScopeNode,
                    .scopeEntityMismatch,
                ].contains($0.code)
            }) {
                return .unauthorizedNodeOrSelectionScope
            }
            if error.issues.contains(where: {
                $0.code == .invalidLimit
            }) {
                return .securityOrToolBudgetExceeded
            }
        }
        if let error = error as? GraphChatQueryEngineError {
            switch error {
            case .graphScopeMismatch:
                return .graphScopeViolation
            case .entityMismatch:
                return .unauthorizedNodeOrSelectionScope
            case .resultLimitExceeded, .evidenceLimitExceeded:
                return .securityOrToolBudgetExceeded
            case .sourceUnavailable:
                return .repositoryOrStorageFailure
            }
        }
        return .repositoryOrStorageFailure
    }
}

nonisolated struct GraphChatToolNonRepairableError: Error, Sendable {
    let reason: GraphChatToolNonRepairableReason
    let publicError: GraphChatToolError
}

nonisolated enum GraphChatToolRepairExpectedCategory: String, CaseIterable, Codable, Hashable,
    Sendable
{
    case entityAlias
    case fieldAlias
    case filterOperator
    case fieldValue
    case sortField
    case projectionField
    case aggregationField
    case conversationReference
}

nonisolated enum GraphChatToolRepairCandidateCategory: String, CaseIterable, Codable, Hashable,
    Sendable
{
    case entity
    case field
}

nonisolated struct GraphChatToolRepairCandidate: Codable, Hashable, Sendable {
    let alias: String
    let displayName: String
    let category: GraphChatToolRepairCandidateCategory
    let dataType: String?
}

nonisolated struct GraphChatToolRepairCurrentContext: Codable, Hashable, Sendable {
    let referenceAlias: String
    let entityAlias: String
    let entityName: String
    let referenceKind: String
    let nodeCount: Int
}

nonisolated struct GraphChatToolRepairResult: Hashable, Sendable {
    private nonisolated struct ModelPayload: Codable, Sendable {
        let status: String
        let reason: GraphChatToolRepairReason
        let argumentPath: String
        let expectedCategory: GraphChatToolRepairExpectedCategory
        let expectedDataType: String?
        let allowedCandidates: [GraphChatToolRepairCandidate]
        let allowedOperators: [String]
        let validatedCurrent: GraphChatToolRepairCurrentContext?
        let instruction: String
    }

    let reason: GraphChatToolRepairReason
    let argumentPath: String
    let expectedCategory: GraphChatToolRepairExpectedCategory
    let expectedDataType: String?
    let allowedCandidates: [GraphChatToolRepairCandidate]
    let allowedOperators: [GraphQueryFilterOperator]
    let validatedCurrent: GraphChatToolRepairCurrentContext?

    var modelContent: String {
        let payload = ModelPayload(
            status: "repairRequired",
            reason: reason,
            argumentPath: argumentPath,
            expectedCategory: expectedCategory,
            expectedDataType: expectedDataType,
            allowedCandidates: allowedCandidates,
            allowedOperators: allowedOperators.map(\.rawValue),
            validatedCurrent: validatedCurrent,
            instruction:
                "Correct the complete tool call once using only these validated options. Do not quote this repair payload in the user-visible answer."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let value = String(data: data, encoding: .utf8) else {
            return #"{"status":"repairRequired","instruction":"Retry the complete tool call once using only validated schema aliases."}"#
        }
        return value
    }
}

nonisolated enum GraphChatToolRepairTerminalState: String, Hashable, Sendable {
    case failed
    case budgetExhausted

    var modelContent: String {
        switch self {
        case .failed:
            return #"{"status":"repairFailed","instruction":"Do not retry the tool call. Return a safe domain clarification without technical error details."}"#
        case .budgetExhausted:
            return #"{"status":"repairBudgetExhausted","instruction":"Do not retry the tool call. Return a safe domain clarification without technical error details."}"#
        }
    }
}

nonisolated struct GraphChatToolRepairableError: Error, Hashable, Sendable {
    let result: GraphChatToolRepairResult
}

nonisolated struct GraphChatProviderRecoverySnapshot: Hashable, Sendable {
    let contextRetryCount: Int
    let repairOfferCount: Int
    let repairAttemptCount: Int
    let outcomes: [GraphChatToolRepairOutcome]
    let pendingRepair: GraphChatToolRepairResult?
}

actor GraphChatProviderRecoveryCoordinator {
    private struct PendingRepair: Sendable {
        let tool: GraphChatToolKind
        let result: GraphChatToolRepairResult
        var isInFlight: Bool
    }

    private let observability: any GraphChatObservabilityRecording
    private let maximumContextRetries = 1
    private let maximumRepairAttempts = 1
    private let maximumRecoveryActions = 2

    private var contextRetryCount = 0
    private var repairOfferCount = 0
    private var repairAttemptCount = 0
    private var outcomes: [GraphChatToolRepairOutcome] = []
    private var pendingRepair: PendingRepair?

    init(
        observability: any GraphChatObservabilityRecording =
            NoOpGraphChatObservabilityRecorder()
    ) {
        self.observability = observability
    }

    func reserveContextRetry() -> Bool {
        guard contextRetryCount < maximumContextRetries,
              recoveryActionCount < maximumRecoveryActions else {
            return false
        }
        contextRetryCount += 1
        return true
    }

    func offerRepair(
        _ result: GraphChatToolRepairResult,
        for tool: GraphChatToolKind
    ) async -> Bool {
        guard repairOfferCount < maximumRepairAttempts,
              repairAttemptCount < maximumRepairAttempts,
              pendingRepair == nil,
              recoveryActionCount < maximumRecoveryActions else {
            await record(
                .budgetExhausted,
                tool: tool,
                reason: result.reason
            )
            return false
        }
        repairOfferCount += 1
        pendingRepair = PendingRepair(
            tool: tool,
            result: result,
            isInFlight: false
        )
        await record(.offered, tool: tool, reason: result.reason)
        return true
    }

    func beginRepairAttempt(
        for tool: GraphChatToolKind
    ) -> GraphChatToolRepairResult? {
        guard var pendingRepair,
              pendingRepair.tool == tool,
              pendingRepair.isInFlight == false,
              repairAttemptCount < maximumRepairAttempts,
              recoveryActionCount < maximumRecoveryActions else {
            return nil
        }
        repairAttemptCount += 1
        pendingRepair.isInFlight = true
        self.pendingRepair = pendingRepair
        return pendingRepair.result
    }

    func completeRepairAttempt(
        succeeded: Bool,
        tool: GraphChatToolKind
    ) async {
        guard let pendingRepair,
              pendingRepair.tool == tool,
              pendingRepair.isInFlight else {
            return
        }
        self.pendingRepair = nil
        await record(
            succeeded ? .succeeded : .failed,
            tool: tool,
            reason: pendingRepair.result.reason
        )
    }

    func recordRepairNotAllowed(
        tool: GraphChatToolKind,
        reason: GraphChatToolNonRepairableReason
    ) async {
        await record(
            .notAllowed,
            tool: tool,
            reason: nil,
            nonRepairableReason: reason
        )
    }

    func pendingRepairResult() -> GraphChatToolRepairResult? {
        pendingRepair?.result
    }

    func snapshotForTesting() -> GraphChatProviderRecoverySnapshot {
        GraphChatProviderRecoverySnapshot(
            contextRetryCount: contextRetryCount,
            repairOfferCount: repairOfferCount,
            repairAttemptCount: repairAttemptCount,
            outcomes: outcomes,
            pendingRepair: pendingRepair?.result
        )
    }

    private var recoveryActionCount: Int {
        contextRetryCount + repairAttemptCount
    }

    private func record(
        _ outcome: GraphChatToolRepairOutcome,
        tool: GraphChatToolKind,
        reason: GraphChatToolRepairReason?,
        nonRepairableReason: GraphChatToolNonRepairableReason? = nil
    ) async {
        if outcomes.contains(outcome) == false {
            outcomes.append(outcome)
        }
        await observability.record(
            .toolRepair(
                GraphChatToolRepairMetric(
                    outcome: outcome,
                    tool: tool,
                    reason: reason,
                    nonRepairableReason: nonRepairableReason,
                    contextRetryCount: contextRetryCount
                )
            )
        )
    }
}

nonisolated enum GraphChatQueryOperatorCompatibility {
    static func dataTypeToken(
        for type: DetailFieldType
    ) -> String {
        switch type {
        case .singleLineText:
            return "singleLineText"
        case .multiLineText:
            return "multiLineText"
        case .numberInt:
            return "numberInt"
        case .numberDouble:
            return "numberDouble"
        case .date:
            return "date"
        case .toggle:
            return "toggle"
        case .singleChoice:
            return "singleChoice"
        }
    }

    static func allowedOperators(
        for type: DetailFieldType
    ) -> [GraphQueryFilterOperator] {
        switch type {
        case .singleLineText, .multiLineText:
            return [.contains, .equals, .startsWith, .isPresent, .isMissing]
        case .numberInt, .numberDouble:
            return [
                .equals,
                .lessThan,
                .lessThanOrEqual,
                .greaterThan,
                .greaterThanOrEqual,
                .between,
                .isPresent,
                .isMissing,
            ]
        case .date:
            return [
                .equals,
                .before,
                .after,
                .between,
                .inYear,
                .inMonth,
                .isOverdue,
                .isPresent,
                .isMissing,
            ]
        case .toggle:
            return [.equals, .isPresent, .isMissing]
        case .singleChoice:
            return [.equals, .oneOf, .isPresent, .isMissing]
        }
    }

    static func supportsMinimumMaximum(
        _ type: DetailFieldType
    ) -> Bool {
        switch type {
        case .numberInt, .numberDouble, .date:
            return true
        case .singleLineText, .multiLineText, .toggle, .singleChoice:
            return false
        }
    }
}

nonisolated struct GraphChatToolRepairHintBuilder: Sendable {
    private let schemaContext: GraphSchemaContext
    private let scope: GraphChatScope

    init(
        schemaContext: GraphSchemaContext,
        scope: GraphChatScope
    ) {
        self.schemaContext = schemaContext
        self.scope = scope
    }

    func unknownEntity(
        rawValue: String
    ) -> GraphChatToolRepairResult {
        let allCandidates = entityCandidates()
        let similar = similarCandidates(
            to: rawValue,
            candidates: allCandidates
        )
        return GraphChatToolRepairResult(
            reason: similar.isEmpty ? .unknownEntityAlias : .similarName,
            argumentPath: "entityAlias",
            expectedCategory: .entityAlias,
            expectedDataType: nil,
            allowedCandidates: similar.isEmpty
                ? Array(
                    allCandidates.prefix(
                        GraphChatIntentLimitPolicy
                            .default.maximumClarificationOptionCount
                    )
                )
                : similar,
            allowedOperators: [],
            validatedCurrent: nil
        )
    }

    func fieldIssue(
        rawValue: String,
        path: String,
        expectedCategory: GraphChatToolRepairExpectedCategory,
        entity: GraphSchemaEntityResolution,
        reason: GraphChatToolRepairReason,
        current: GraphChatToolRepairCurrentContext?
    ) -> GraphChatToolRepairResult {
        let allCandidates = fieldCandidates(for: entity.entityID)
        let similar = similarCandidates(
            to: rawValue,
            candidates: allCandidates
        )
        let resolvedReason: GraphChatToolRepairReason
        if reason == .schemaIncompatibility, similar.isEmpty == false {
            resolvedReason = .similarName
        } else {
            resolvedReason = reason
        }
        return GraphChatToolRepairResult(
            reason: resolvedReason,
            argumentPath: path,
            expectedCategory: expectedCategory,
            expectedDataType: nil,
            allowedCandidates: similar.isEmpty
                ? Array(allCandidates.prefix(12))
                : similar,
            allowedOperators: [],
            validatedCurrent: current
        )
    }

    func invalidOperator(
        path: String,
        field: GraphSchemaFieldResolution,
        current: GraphChatToolRepairCurrentContext?
    ) -> GraphChatToolRepairResult {
        GraphChatToolRepairResult(
            reason: .invalidOperator,
            argumentPath: path,
            expectedCategory: .filterOperator,
            expectedDataType:
                GraphChatQueryOperatorCompatibility.dataTypeToken(
                    for: field.type
                ),
            allowedCandidates: [
                GraphChatToolRepairCandidate(
                    alias: field.alias.rawValue,
                    displayName: field.name,
                    category: .field,
                    dataType:
                        GraphChatQueryOperatorCompatibility.dataTypeToken(
                            for: field.type
                        )
                )
            ],
            allowedOperators:
                GraphChatQueryOperatorCompatibility.allowedOperators(
                    for: field.type
                ),
            validatedCurrent: current
        )
    }

    func invalidValue(
        path: String,
        field: GraphSchemaFieldResolution,
        operation: GraphQueryFilterOperator,
        current: GraphChatToolRepairCurrentContext?
    ) -> GraphChatToolRepairResult {
        GraphChatToolRepairResult(
            reason: .schemaIncompatibility,
            argumentPath: path,
            expectedCategory: .fieldValue,
            expectedDataType:
                GraphChatQueryOperatorCompatibility.dataTypeToken(
                    for: field.type
                ),
            allowedCandidates: [
                GraphChatToolRepairCandidate(
                    alias: field.alias.rawValue,
                    displayName: field.name,
                    category: .field,
                    dataType:
                        GraphChatQueryOperatorCompatibility.dataTypeToken(
                            for: field.type
                        )
                )
            ],
            allowedOperators:
                GraphChatQueryOperatorCompatibility.allowedOperators(
                    for: field.type
                ).contains(operation)
                ? [operation]
                : [],
            validatedCurrent: current
        )
    }

    func conversationMismatch(
        path: String,
        entity: GraphSchemaEntityResolution,
        current: GraphChatToolRepairCurrentContext
    ) -> GraphChatToolRepairResult {
        GraphChatToolRepairResult(
            reason: .conversationReferenceMismatch,
            argumentPath: path,
            expectedCategory: .conversationReference,
            expectedDataType: nil,
            allowedCandidates: [
                GraphChatToolRepairCandidate(
                    alias: entity.alias.rawValue,
                    displayName: entity.name,
                    category: .entity,
                    dataType: nil
                )
            ],
            allowedOperators: [],
            validatedCurrent: current
        )
    }

    func currentContext(
        for resolvedScope: GraphChatResolvedConversationScope,
        entity: GraphSchemaEntityResolution
    ) -> GraphChatToolRepairCurrentContext {
        GraphChatToolRepairCurrentContext(
            referenceAlias: resolvedScope.reference.alias,
            entityAlias: entity.alias.rawValue,
            entityName: entity.name,
            referenceKind: resolvedScope.reference.kind.rawValue,
            nodeCount: resolvedScope.nodes.count
        )
    }

    private func entityCandidates() -> [GraphChatToolRepairCandidate] {
        schemaContext.aliases.entitiesByAlias.values
            .filter { isEntityAllowedByScope($0.entityID) }
            .sorted { $0.alias.rawValue < $1.alias.rawValue }
            .map {
                GraphChatToolRepairCandidate(
                    alias: $0.alias.rawValue,
                    displayName: $0.name,
                    category: .entity,
                    dataType: nil
                )
            }
    }

    private func isEntityAllowedByScope(
        _ entityID: UUID
    ) -> Bool {
        switch scope.target {
        case .graph:
            return true
        case .entity(let scopedEntityID):
            return entityID == scopedEntityID
        case .node(let node):
            return schemaContext.aliases.owningEntityID(for: node) == entityID
        case .selection(let nodes):
            return nodes.isEmpty == false
                && nodes.allSatisfy {
                    schemaContext.aliases.owningEntityID(for: $0)
                        == entityID
                }
        }
    }

    private func fieldCandidates(
        for entityID: UUID
    ) -> [GraphChatToolRepairCandidate] {
        schemaContext.aliases.fieldsByAlias.values
            .filter { $0.entityID == entityID }
            .sorted { $0.alias.rawValue < $1.alias.rawValue }
            .map {
                GraphChatToolRepairCandidate(
                    alias: $0.alias.rawValue,
                    displayName: $0.name,
                    category: .field,
                    dataType:
                        GraphChatQueryOperatorCompatibility.dataTypeToken(
                            for: $0.type
                        )
                )
            }
    }

    private func similarCandidates(
        to rawValue: String,
        candidates: [GraphChatToolRepairCandidate]
    ) -> [GraphChatToolRepairCandidate] {
        let input = Self.normalizedName(rawValue)
        guard input.count >= 3 else {
            return []
        }
        let ranked = candidates.compactMap {
            candidate -> (GraphChatToolRepairCandidate, Int)? in
            let aliasDistance = Self.editDistance(
                input,
                Self.normalizedName(candidate.alias)
            )
            let nameDistance = Self.editDistance(
                input,
                Self.normalizedName(candidate.displayName)
            )
            let distance = min(aliasDistance, nameDistance)
            let comparisonLength = max(
                input.count,
                Self.normalizedName(candidate.displayName).count
            )
            let maximumDistance = max(1, min(3, comparisonLength / 4))
            guard distance <= maximumDistance else {
                return nil
            }
            return (candidate, distance)
        }
        guard let minimumDistance = ranked.map(\.1).min() else {
            return []
        }
        return ranked
            .filter { $0.1 == minimumDistance }
            .map(\.0)
            .sorted { $0.alias < $1.alias }
    }

    private static func normalizedName(
        _ value: String
    ) -> String {
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
        return String(folded.filter(\.isLetter))
    }

    private static func editDistance(
        _ lhs: String,
        _ rhs: String
    ) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty {
            return right.count
        }
        if right.isEmpty {
            return left.count
        }
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitution = previous[rightIndex]
                    + (leftCharacter == rightCharacter ? 0 : 1)
                current[rightIndex + 1] = min(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1
                    ),
                    substitution
                )
            }
            previous = current
        }
        return previous[right.count]
    }
}
