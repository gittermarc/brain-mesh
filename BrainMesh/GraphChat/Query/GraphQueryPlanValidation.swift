//
//  GraphQueryPlanValidation.swift
//  BrainMesh
//
//  Strict alias, type, scope, date, choice, and limit validation.
//

import Foundation

nonisolated enum GraphQueryPlanValidationIssueCode: String, CaseIterable, Hashable, Sendable {
    case unsupportedVersion
    case unknownEntityAlias
    case unknownFieldAlias
    case fieldEntityMismatch
    case invalidOperator
    case invalidValueType
    case emptyValue
    case invalidRange
    case invalidChoiceValue
    case ambiguousChoiceValue
    case invalidLimit
    case invalidFilterCount
    case invalidProjectionCount
    case graphScopeMismatch
    case unknownScopeEntity
    case unknownScopeNode
    case scopeEntityMismatch
    case duplicateProjection
    case invalidAggregation
}

nonisolated struct GraphQueryPlanValidationIssue: Hashable, Sendable, Identifiable {
    let code: GraphQueryPlanValidationIssueCode
    let path: String
    let message: String

    var id: String {
        "\(path):\(code.rawValue):\(message)"
    }
}

nonisolated struct GraphQueryPlanValidationError: Error, LocalizedError, Equatable, Sendable {
    let issues: [GraphQueryPlanValidationIssue]

    var errorDescription: String? {
        issues.map(\.message).joined(separator: "\n")
    }
}

nonisolated struct GraphQueryPlanValidator: Sendable {
    private let dateInterpreter: GraphChatDateInterpreter
    private let defaultLimit: Int
    private let maximumLimit: Int
    private let maximumFilterCount: Int
    private let maximumProjectionFieldCount: Int

    init(
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate: Date,
        defaultLimit: Int = GraphQueryPlanLimits.defaultResultLimit,
        maximumLimit: Int = GraphQueryPlanLimits.maximumResultLimit,
        maximumFilterCount: Int =
            GraphChatIntentLimitPolicy
                .default.maximumFilterCount,
        maximumProjectionFieldCount: Int =
            GraphChatIntentLimitPolicy
                .default.maximumProjectionFieldCount
    ) {
        precondition(defaultLimit > 0)
        precondition(maximumLimit >= defaultLimit)
        precondition(maximumFilterCount > 0)
        precondition(maximumProjectionFieldCount > 0)
        self.dateInterpreter = GraphChatDateInterpreter(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: referenceDate
        )
        self.defaultLimit = defaultLimit
        self.maximumLimit = maximumLimit
        self.maximumFilterCount =
            maximumFilterCount
        self.maximumProjectionFieldCount =
            maximumProjectionFieldCount
    }

    func validate(
        _ plan: GraphQueryPlan,
        against context: GraphSchemaContext
    ) throws -> ValidatedGraphQueryPlan {
        var issues: [GraphQueryPlanValidationIssue] = []

        if plan.version != GraphQueryPlan.currentVersion {
            issues.append(
                issue(
                    .unsupportedVersion,
                    path: "version",
                    message: "Die Query-Plan-Version \(plan.version) wird nicht unterstützt."
                )
            )
        }

        let entityResolution = context.aliases.entity(for: plan.entityAlias)
        if entityResolution == nil {
            issues.append(
                issue(
                    .unknownEntityAlias,
                    path: "entityAlias",
                    message: "Der Entity-Alias \(plan.entityAlias.rawValue) existiert im aktuellen Schema nicht."
                )
            )
        }

        let resolvedLimit: Int
        if let limit = plan.limit {
            resolvedLimit = limit
            if limit < 1 || limit > maximumLimit {
                issues.append(
                    issue(
                        .invalidLimit,
                        path: "limit",
                        message: "Das Limit muss zwischen 1 und \(maximumLimit) liegen."
                    )
                )
            }
        } else {
            resolvedLimit = defaultLimit
        }

        let resolvedScope = resolveScope(
            plan.scope,
            selectedEntityID: entityResolution?.entityID,
            context: context,
            issues: &issues
        )

        var resolvedFilters: [GraphValidatedQueryFilter] = []
        if plan.filters.count > maximumFilterCount {
            issues.append(
                issue(
                    .invalidFilterCount,
                    path: "filters",
                    message:
                        "Der Query-Plan enthält zu viele Filter."
                )
            )
        }
        resolvedFilters.reserveCapacity(
            min(
                plan.filters.count,
                maximumFilterCount
            )
        )
        if let entityResolution {
            for (index, filter) in plan.filters
                .prefix(maximumFilterCount)
                .enumerated()
            {
                let path = "filters[\(index)]"
                if let resolved = resolveFilter(
                    filter,
                    selectedEntityID: entityResolution.entityID,
                    context: context,
                    path: path,
                    issues: &issues
                ) {
                    resolvedFilters.append(resolved)
                }
            }
        }

        var resolvedSorting: [GraphValidatedQuerySort] = []
        resolvedSorting.reserveCapacity(plan.sorting.count)
        if let entityResolution {
            for (index, sort) in plan.sorting.enumerated() {
                let path = "sorting[\(index)]"
                switch sort.key {
                case .nodeName:
                    resolvedSorting.append(
                        GraphValidatedQuerySort(
                            key: .nodeName,
                            direction: sort.direction
                        )
                    )
                case .field(let alias):
                    if let field = resolveField(
                        alias,
                        selectedEntityID: entityResolution.entityID,
                        context: context,
                        path: "\(path).key",
                        issues: &issues
                    ) {
                        resolvedSorting.append(
                            GraphValidatedQuerySort(
                                key: .field(field.fieldID),
                                direction: sort.direction
                            )
                        )
                    }
                }
            }
        }

        var resolvedProjection: [GraphValidatedProjection] = []
        let maximumProjectionItemCount =
            maximumProjectionFieldCount + 1
        let hasTooManyProjectionItems =
            plan.projection.count
                > maximumProjectionItemCount
        let projectionFieldCount =
            hasTooManyProjectionItems
            ? maximumProjectionFieldCount + 1
            : plan.projection.reduce(
                into: 0
            ) { count, projection in
                if case .field = projection {
                    count += 1
                }
            }
        if hasTooManyProjectionItems
            || projectionFieldCount
                > maximumProjectionFieldCount
        {
            issues.append(
                issue(
                    .invalidProjectionCount,
                    path: "projection",
                    message:
                        "Der Query-Plan enthält zu viele Projektionsfelder."
                )
            )
        }
        resolvedProjection.reserveCapacity(
            min(
                plan.projection.count,
                maximumProjectionItemCount
            )
        )
        var seenProjection = Set<GraphQueryProjection>()
        if let entityResolution {
            for (index, projection) in plan.projection
                .prefix(
                    maximumProjectionItemCount
                )
                .enumerated()
            {
                let path = "projection[\(index)]"
                guard seenProjection.insert(projection).inserted else {
                    issues.append(
                        issue(
                            .duplicateProjection,
                            path: path,
                            message: "Eine Projektion darf nicht doppelt angegeben werden."
                        )
                    )
                    continue
                }

                switch projection {
                case .nodeIdentity:
                    resolvedProjection.append(.nodeIdentity)
                case .field(let alias):
                    if let field = resolveField(
                        alias,
                        selectedEntityID: entityResolution.entityID,
                        context: context,
                        path: path,
                        issues: &issues
                    ) {
                        resolvedProjection.append(.field(field.fieldID))
                    }
                }
            }
        }

        let resolvedAggregation: GraphValidatedAggregation?
        if let aggregation = plan.aggregation, let entityResolution {
            resolvedAggregation = resolveAggregation(
                aggregation,
                selectedEntityID: entityResolution.entityID,
                context: context,
                issues: &issues
            )
        } else {
            resolvedAggregation = nil
        }

        guard issues.isEmpty else {
            throw GraphQueryPlanValidationError(issues: issues)
        }
        guard let entityResolution, let resolvedScope else {
            throw GraphQueryPlanValidationError(
                issues: [
                    issue(
                        .unknownEntityAlias,
                        path: "entityAlias",
                        message: "Der Query-Plan konnte nicht vollständig aufgelöst werden."
                    )
                ]
            )
        }

        return ValidatedGraphQueryPlan(
            version: plan.version,
            graphScope: context.graphScope,
            entityID: entityResolution.entityID,
            scope: resolvedScope,
            filters: resolvedFilters,
            sorting: resolvedSorting,
            projection: resolvedProjection,
            aggregation: resolvedAggregation,
            limit: resolvedLimit
        )
    }

    private func resolveScope(
        _ scope: GraphChatScope?,
        selectedEntityID: UUID?,
        context: GraphSchemaContext,
        issues: inout [GraphQueryPlanValidationIssue]
    ) -> GraphResolvedQueryScope? {
        guard let scope else {
            return .graph
        }
        guard scope.graphScope == context.graphScope else {
            issues.append(
                issue(
                    .graphScopeMismatch,
                    path: "scope.graphScope",
                    message: "Der Query-Scope gehört nicht zum aktiven Graphen."
                )
            )
            return nil
        }

        switch scope.target {
        case .graph:
            return .graph
        case .entity(let entityID):
            guard context.aliases.contains(entityID: entityID) else {
                issues.append(
                    issue(
                        .unknownScopeEntity,
                        path: "scope.entity",
                        message: "Die Entity des Query-Scopes existiert im aktiven Graphen nicht."
                    )
                )
                return nil
            }
            guard selectedEntityID == nil || selectedEntityID == entityID else {
                issues.append(
                    issue(
                        .scopeEntityMismatch,
                        path: "scope.entity",
                        message: "Der Query-Scope gehört nicht zur ausgewählten Entity."
                    )
                )
                return nil
            }
            return .entity(entityID)
        case .node(let node):
            guard let ownerEntityID = context.aliases.owningEntityID(for: node) else {
                issues.append(
                    issue(
                        .unknownScopeNode,
                        path: "scope.node",
                        message: "Der Node des Query-Scopes existiert im aktiven Graphen nicht."
                    )
                )
                return nil
            }
            guard selectedEntityID == nil || selectedEntityID == ownerEntityID else {
                issues.append(
                    issue(
                        .scopeEntityMismatch,
                        path: "scope.node",
                        message: "Der Node des Query-Scopes gehört nicht zur ausgewählten Entity."
                    )
                )
                return nil
            }
            return .node(node)
        case .selection(let nodes):
            var hasInvalidNode = false
            for (index, node) in nodes.enumerated() {
                guard let ownerEntityID = context.aliases.owningEntityID(for: node) else {
                    issues.append(
                        issue(
                            .unknownScopeNode,
                            path: "scope.selection[\(index)]",
                            message: "Ein ausgewählter Node existiert im aktiven Graphen nicht."
                        )
                    )
                    hasInvalidNode = true
                    continue
                }
                guard selectedEntityID == nil || selectedEntityID == ownerEntityID else {
                    issues.append(
                        issue(
                            .scopeEntityMismatch,
                            path: "scope.selection[\(index)]",
                            message: "Ein ausgewählter Node gehört nicht zur ausgewählten Entity."
                        )
                    )
                    hasInvalidNode = true
                    continue
                }
            }
            return hasInvalidNode ? nil : .selection(nodes)
        }
    }

    private func resolveFilter(
        _ filter: GraphQueryFilter,
        selectedEntityID: UUID,
        context: GraphSchemaContext,
        path: String,
        issues: inout [GraphQueryPlanValidationIssue]
    ) -> GraphValidatedQueryFilter? {
        guard
            let field = resolveField(
                filter.fieldAlias,
                selectedEntityID: selectedEntityID,
                context: context,
                path: "\(path).fieldAlias",
                issues: &issues
            )
        else {
            return nil
        }

        guard GraphChatQueryOperatorCompatibility
            .allowedOperators(for: field.type)
            .contains(filter.operation) else {
            issues.append(
                issue(
                    .invalidOperator,
                    path: "\(path).operation",
                    message: "Der Operator \(filter.operation.rawValue) passt nicht zum Feldtyp \(field.type.title)."
                )
            )
            return nil
        }

        guard
            let value = resolveFilterValue(
                filter.value,
                operation: filter.operation,
                field: field,
                path: "\(path).value",
                issues: &issues
            )
        else {
            return nil
        }

        return GraphValidatedQueryFilter(
            fieldID: field.fieldID,
            fieldType: field.type,
            operation: filter.operation,
            value: value,
            valueDescription: filterValueDescription(
                value,
                operation: filter.operation
            )
        )
    }

    private func filterValueDescription(
        _ value: GraphValidatedFilterValue,
        operation: GraphQueryFilterOperator
    ) -> String? {
        switch (operation, value) {
        case (.equals, .dateInterval(let interval)):
            return dateInterpreter.dateDescription(
                interval.lowerBound
            )
        case (.before, .date(let date)),
            (.after, .date(let date)):
            return dateInterpreter.dateDescription(
                date
            )
        case (.between, .dateInterval(let interval)):
            return dateInterpreter.intervalDescription(
                interval
            )
        case (.inYear, .dateInterval(let interval)),
            (.inMonth, .dateInterval(let interval)):
            return dateInterpreter.intervalDescription(interval)
        case (.isOverdue, .dateInterval(let interval)):
            return "vor \(dateInterpreter.dateDescription(interval.upperBoundExclusive))"
        default:
            return nil
        }
    }

    private func resolveFilterValue(
        _ value: GraphQueryFilterValue,
        operation: GraphQueryFilterOperator,
        field: GraphSchemaFieldResolution,
        path: String,
        issues: inout [GraphQueryPlanValidationIssue]
    ) -> GraphValidatedFilterValue? {
        if operation == .isPresent || operation == .isMissing || operation == .isOverdue {
            guard case .none = value else {
                issues.append(invalidValueTypeIssue(path: path, operation: operation))
                return nil
            }
            if operation == .isOverdue {
                return .dateInterval(dateInterpreter.overdueInterval())
            }
            return GraphValidatedFilterValue.none
        }

        switch (field.type, operation, value) {
        case (.singleLineText, .contains, .text(let text)),
            (.singleLineText, .equals, .text(let text)),
            (.singleLineText, .startsWith, .text(let text)),
            (.multiLineText, .contains, .text(let text)),
            (.multiLineText, .equals, .text(let text)),
            (.multiLineText, .startsWith, .text(let text)):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                issues.append(
                    issue(
                        .emptyValue,
                        path: path,
                        message: "Ein Textfilter benötigt einen nicht leeren Wert."
                    )
                )
                return nil
            }
            return .text(trimmed)

        case (.numberInt, .equals, .integer(let number)),
            (.numberInt, .lessThan, .integer(let number)),
            (.numberInt, .lessThanOrEqual, .integer(let number)),
            (.numberInt, .greaterThan, .integer(let number)),
            (.numberInt, .greaterThanOrEqual, .integer(let number)):
            return .integer(number)

        case (.numberInt, .between, .integerRange(let range)):
            guard range.lowerBound <= range.upperBound else {
                issues.append(invalidRangeIssue(path: path))
                return nil
            }
            return .integerRange(range)

        case (.numberDouble, .equals, .decimal(let number)),
            (.numberDouble, .lessThan, .decimal(let number)),
            (.numberDouble, .lessThanOrEqual, .decimal(let number)),
            (.numberDouble, .greaterThan, .decimal(let number)),
            (.numberDouble, .greaterThanOrEqual, .decimal(let number)):
            guard number.isFinite else {
                issues.append(invalidRangeIssue(path: path))
                return nil
            }
            return .decimal(number)

        case (.numberDouble, .between, .decimalRange(let range)):
            guard
                range.lowerBound.isFinite,
                range.upperBound.isFinite,
                range.lowerBound <= range.upperBound
            else {
                issues.append(invalidRangeIssue(path: path))
                return nil
            }
            return .decimalRange(range)

        case (.date, .equals, .date(let date)):
            do {
                return .dateInterval(
                    try dateInterpreter.interval(
                        forCalendarDay: date
                    )
                )
            } catch {
                issues.append(invalidRangeIssue(path: path))
                return nil
            }

        case (.date, .before, .date(let date)),
            (.date, .after, .date(let date)):
            return .date(date)

        case (.date, .between, .dateInterval(let interval)):
            do {
                return .dateInterval(try dateInterpreter.validate(interval: interval))
            } catch {
                issues.append(invalidRangeIssue(path: path))
                return nil
            }

        case (.date, .inYear, .year(let year)):
            do {
                return .dateInterval(try dateInterpreter.interval(forYear: year))
            } catch {
                issues.append(invalidRangeIssue(path: path))
                return nil
            }

        case (.date, .inMonth, .month(let month)):
            do {
                return .dateInterval(try dateInterpreter.interval(forMonth: month))
            } catch {
                issues.append(invalidRangeIssue(path: path))
                return nil
            }

        case (.toggle, .equals, .boolean(let boolean)):
            return .boolean(boolean)

        case (.singleChoice, .equals, .choice(let choice)):
            return resolveChoice(
                choice,
                options: field.choiceOptions,
                path: path,
                issues: &issues
            ).map(GraphValidatedFilterValue.choice)

        case (.singleChoice, .oneOf, .choices(let choices)):
            guard choices.isEmpty == false else {
                issues.append(
                    issue(
                        .emptyValue,
                        path: path,
                        message: "Ein oneOf-Filter benötigt mindestens einen Auswahlwert."
                    )
                )
                return nil
            }
            var resolved: [GraphResolvedChoiceValue] = []
            resolved.reserveCapacity(choices.count)
            for (index, choice) in choices.enumerated() {
                if let value = resolveChoice(
                    choice,
                    options: field.choiceOptions,
                    path: "\(path)[\(index)]",
                    issues: &issues
                ) {
                    resolved.append(value)
                }
            }
            return resolved.count == choices.count ? .choices(resolved) : nil

        default:
            issues.append(invalidValueTypeIssue(path: path, operation: operation))
            return nil
        }
    }

    private func resolveChoice(
        _ input: String,
        options: [String],
        path: String,
        issues: inout [GraphQueryPlanValidationIssue]
    ) -> GraphResolvedChoiceValue? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            issues.append(
                issue(
                    .emptyValue,
                    path: path,
                    message: "Ein Auswahlfilter benötigt einen nicht leeren Wert."
                )
            )
            return nil
        }

        if let exact = options.first(where: { $0 == trimmed }) {
            return GraphResolvedChoiceValue(
                originalValue: input,
                canonicalValue: exact
            )
        }

        let normalizedInput = GraphQueryChoiceNormalizer.normalize(trimmed)
        let matches = options.filter {
            GraphQueryChoiceNormalizer.normalize($0) == normalizedInput
        }
        guard matches.isEmpty == false else {
            issues.append(
                issue(
                    .invalidChoiceValue,
                    path: path,
                    message: "Der Auswahlwert \"\(input)\" ist für das Feld nicht definiert."
                )
            )
            return nil
        }
        guard matches.count == 1, let match = matches.first else {
            issues.append(
                issue(
                    .ambiguousChoiceValue,
                    path: path,
                    message: "Der Auswahlwert \"\(input)\" ist nach Normalisierung nicht eindeutig."
                )
            )
            return nil
        }
        return GraphResolvedChoiceValue(
            originalValue: input,
            canonicalValue: match
        )
    }

    private func resolveField(
        _ alias: GraphFieldAlias,
        selectedEntityID: UUID,
        context: GraphSchemaContext,
        path: String,
        issues: inout [GraphQueryPlanValidationIssue]
    ) -> GraphSchemaFieldResolution? {
        guard let field = context.aliases.field(for: alias) else {
            issues.append(
                issue(
                    .unknownFieldAlias,
                    path: path,
                    message: "Der Feld-Alias \(alias.rawValue) existiert im aktuellen Schema nicht."
                )
            )
            return nil
        }
        guard field.entityID == selectedEntityID else {
            issues.append(
                issue(
                    .fieldEntityMismatch,
                    path: path,
                    message: "Der Feld-Alias \(alias.rawValue) gehört nicht zur ausgewählten Entity."
                )
            )
            return nil
        }
        return field
    }

    private func resolveAggregation(
        _ aggregation: GraphQueryAggregation,
        selectedEntityID: UUID,
        context: GraphSchemaContext,
        issues: inout [GraphQueryPlanValidationIssue]
    ) -> GraphValidatedAggregation? {
        switch aggregation {
        case .count:
            return .count
        case .groupCount(let alias):
            return resolveField(
                alias,
                selectedEntityID: selectedEntityID,
                context: context,
                path: "aggregation",
                issues: &issues
            ).map { .groupCount($0.fieldID) }
        case .minimum(let alias), .maximum(let alias):
            guard
                let field = resolveField(
                    alias,
                    selectedEntityID: selectedEntityID,
                    context: context,
                    path: "aggregation",
                    issues: &issues
                )
            else {
                return nil
            }
            guard GraphChatQueryOperatorCompatibility
                .supportsMinimumMaximum(field.type) else {
                issues.append(
                    issue(
                        .invalidAggregation,
                        path: "aggregation",
                        message: "Minimum und Maximum sind nur für Zahlen- und Datumsfelder erlaubt."
                    )
                )
                return nil
            }
            switch aggregation {
            case .minimum:
                return .minimum(field.fieldID)
            case .maximum:
                return .maximum(field.fieldID)
            case .count, .groupCount:
                return nil
            }
        }
    }

    private func issue(
        _ code: GraphQueryPlanValidationIssueCode,
        path: String,
        message: String
    ) -> GraphQueryPlanValidationIssue {
        GraphQueryPlanValidationIssue(code: code, path: path, message: message)
    }

    private func invalidValueTypeIssue(
        path: String,
        operation: GraphQueryFilterOperator
    ) -> GraphQueryPlanValidationIssue {
        issue(
            .invalidValueType,
            path: path,
            message: "Der Filterwert passt nicht zum Operator \(operation.rawValue) und Feldtyp."
        )
    }

    private func invalidRangeIssue(path: String) -> GraphQueryPlanValidationIssue {
        issue(
            .invalidRange,
            path: path,
            message: "Der angegebene Bereich besitzt keine gültigen aufsteigenden Grenzen."
        )
    }
}

nonisolated enum GraphQueryChoiceNormalizer {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
