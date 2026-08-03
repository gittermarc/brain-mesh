//
//  GraphChatIntentInterpretationRenderer.swift
//  BrainMesh
//
//  Compact German and English presentation of app-owned interpretations.
//

import Foundation

nonisolated struct GraphChatIntentInterpretationRenderer:
    Sendable
{
    func presentation(
        for interpretation:
            GraphChatIntentInterpretation
    ) -> GraphChatIntentInterpretationPresentation {
        GraphChatIntentInterpretationPresentation(
            label:
                interpretation.responseLanguage
                    == .german
                ? "Verstanden als"
                : "Understood as",
            title: title(for: interpretation)
        )
    }

    func presentationStrings(
        for interpretation:
            GraphChatIntentInterpretation
    ) -> [String] {
        var values = [
            interpretation.presentation.label,
            interpretation.presentation.title,
        ]
        values.append(
            contentsOf:
                interpretation.entities.map(
                    \.displayName
                )
        )
        values.append(
            contentsOf:
                interpretation.nodes.map(
                    \.displayName
                )
        )
        for field in interpretation.fields {
            values.append(field.displayName)
            if let unit = field.unit {
                values.append(unit)
            }
        }
        for filter in interpretation.filters {
            values.append(filter.field.displayName)
            if let value = filterValue(
                filter,
                interpretation: interpretation
            ), value.isEmpty == false {
                values.append(value)
            }
        }
        for sort in interpretation.sorting {
            values.append(
                sortLabel(
                    sort,
                    language:
                        interpretation
                            .responseLanguage
                )
            )
        }
        if let grouping =
                interpretation.grouping {
            values.append(
                grouping.field.displayName
            )
        }
        if let aggregation =
                interpretation.aggregation {
            if case .groupCount(let field) =
                aggregation {
                values.append(field.displayName)
            }
        }
        return values
    }

    private func title(
        for interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        switch interpretation.intentKind {
        case .findNodes:
            return findTitle(interpretation)
        case .entityCollection:
            return collectionTitle(interpretation)
        case .countOrGroup:
            return aggregationTitle(interpretation)
        case .nodeDetails:
            return nodeDetailsTitle(interpretation)
        case .narrowResultSet:
            return refinementTitle(interpretation)
        case .compareNodes:
            return comparisonTitle(interpretation)
        case .inspectGraphState:
            return graphStateTitle(interpretation)
        case .relationships:
            return relationshipTitle(
                interpretation
            )
        }
    }

    private func relationshipTitle(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        guard let relationship =
                interpretation.relationship
        else {
            return interpretation.responseLanguage
                == .german
                ? "Direkte Verbindungen"
                : "Direct connections"
        }
        let direction: String
        switch (
            interpretation.responseLanguage,
            relationship.direction
        ) {
        case (.german, .incoming):
            direction = "eingehende"
        case (.german, .outgoing):
            direction = "ausgehende"
        case (.german, .both):
            direction = "direkte"
        case (.english, .incoming):
            direction = "incoming"
        case (.english, .outgoing):
            direction = "outgoing"
        case (.english, .both):
            direction = "direct"
        }
        if relationship.request
            == .linkNotesBetweenNodes,
           let counterpart =
                relationship.counterpartNode {
            return interpretation.responseLanguage
                == .german
                ? "Link-Notizen zwischen \(relationship.center.displayName) und \(counterpart.displayName)"
                : "Link notes between \(relationship.center.displayName) and \(counterpart.displayName)"
        }
        let counterpart =
            relationship.counterpartNode?
                .displayName
            ?? relationship
                .counterpartEntity?
                .displayName
        if let counterpart {
            return interpretation.responseLanguage
                == .german
                ? "\(direction.capitalized) Verbindungen von \(relationship.center.displayName) zu \(counterpart)"
                : "\(direction.capitalized) connections from \(relationship.center.displayName) to \(counterpart)"
        }
        return interpretation.responseLanguage
            == .german
            ? "\(direction.capitalized) Verbindungen von \(relationship.center.displayName)"
            : "\(direction.capitalized) connections of \(relationship.center.displayName)"
    }

    private func findTitle(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let language =
            interpretation.responseLanguage
        if interpretation.nodes.isEmpty == false {
            let names = joinedNames(
                interpretation.nodes.map(
                    \.displayName
                ),
                language: language
            )
            return language == .german
                ? "\(names) finden"
                : "Find \(names)"
        }
        if let entity =
                interpretation.entities.first {
            return language == .german
                ? "\(entity.displayName) finden"
                : "Find \(entity.displayName)"
        }
        return language == .german
            ? "Passende Einträge finden"
            : "Find matching entries"
    }

    private func collectionTitle(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let base = collectionPhrase(
            interpretation
        )
        return base
            + sortingClause(interpretation)
    }

    private func aggregationTitle(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let language =
            interpretation.responseLanguage
        let collection = collectionPhrase(
            interpretation
        )
        switch interpretation.aggregation {
        case .count:
            return language == .german
                ? "Anzahl der \(collection)"
                : "Number of \(collection)"
        case .groupCount(let field):
            return language == .german
                ? "\(collection), gruppiert nach \(field.displayName)"
                : "\(collection), grouped by \(field.displayName)"
        case nil:
            return collection
        }
    }

    private func nodeDetailsTitle(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let language =
            interpretation.responseLanguage
        guard let node =
                interpretation.nodes.first
        else {
            return language == .german
                ? "Details des ausgewählten Eintrags"
                : "Details for the selected entry"
        }
        let entitySuffix: String
        if let entity =
                interpretation.entities.first {
            entitySuffix =
                " (\(entity.displayName))"
        } else {
            entitySuffix = ""
        }
        if interpretation.fields.count == 1,
           let field =
                interpretation.fields.first {
            return language == .german
                ? "\(field.displayName) von \(node.displayName)\(entitySuffix)"
                : "\(field.displayName) for \(node.displayName)\(entitySuffix)"
        }
        if interpretation.fields.isEmpty {
            return language == .german
                ? "Details von \(node.displayName)\(entitySuffix)"
                : "Details for \(node.displayName)\(entitySuffix)"
        }
        let fields = joinedNames(
            interpretation.fields.map(
                \.displayName
            ),
            language: language
        )
        return language == .german
            ? "Details von \(node.displayName): \(fields)\(entitySuffix)"
            : "Details for \(node.displayName): \(fields)\(entitySuffix)"
    }

    private func refinementTitle(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let language =
            interpretation.responseLanguage
        let entity =
            interpretation.entities.first?
                .displayName
            ?? (
                language == .german
                ? "Einträge"
                : "Entries"
            )
        let base = language == .german
            ? "\(entity) aus den vorherigen Ergebnissen"
            : "\(entity) from the previous results"
        return base
            + filterClause(interpretation)
            + sortingClause(interpretation)
    }

    private func comparisonTitle(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let language =
            interpretation.responseLanguage
        let names = joinedNames(
            interpretation.nodes.map(
                \.displayName
            ),
            language: language
        )
        var title = language == .german
            ? "Vergleich von \(names)"
            : "Comparison of \(names)"
        if interpretation.fields.isEmpty == false {
            let fields = joinedNames(
                interpretation.fields.map(
                    \.displayName
                ),
                language: language
            )
            title += language == .german
                ? " nach \(fields)"
                : " by \(fields)"
        }
        if interpretation.entities.count == 1,
           let entity =
                interpretation.entities.first {
            title += " (\(entity.displayName))"
        }
        return title
    }

    private func graphStateTitle(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let language =
            interpretation.responseLanguage
        switch interpretation.graphStateAspect {
        case .overview:
            return language == .german
                ? "Überblick zum gesamten Graphen"
                : "Overview of the entire graph"
        case .counts:
            return language == .german
                ? "Anzahlen im gesamten Graphen"
                : "Counts for the entire graph"
        case .structure:
            return language == .german
                ? "Struktur des gesamten Graphen"
                : "Structure of the entire graph"
        case .health:
            return language == .german
                ? "Gesundheitszustand des gesamten Graphen"
                : "Health of the entire graph"
        case nil:
            return language == .german
                ? "Zustand des gesamten Graphen"
                : "State of the entire graph"
        }
    }

    private func collectionPhrase(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let language =
            interpretation.responseLanguage
        let entityNames = interpretation.entities.map(
            \.displayName
        )
        let entity = entityNames.isEmpty
            ? (
                language == .german
                ? "Einträge"
                : "Entries"
            )
            : entityNames.joined(separator: " → ")
        return entity
            + filterClause(interpretation)
    }

    private func filterClause(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        guard interpretation.filters.isEmpty
                == false
        else {
            return ""
        }
        let language =
            interpretation.responseLanguage
        let values = interpretation.filters.map {
            filterPhrase(
                $0,
                interpretation: interpretation
            )
        }
        return (language == .german
            ? " mit "
            : " with ")
            + joinedNames(
                values,
                language: language,
                maximumVisibleCount: 3
            )
    }

    private func filterPhrase(
        _ filter:
            GraphChatIntentInterpretationFilter,
        interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let language =
            interpretation.responseLanguage
        let operation = operationLabel(
            filter.operation,
            language: language
        )
        let value = filterValue(
            filter,
            interpretation: interpretation
        )
        guard let value,
              value.isEmpty == false
        else {
            return "\(filter.field.displayName): \(operation)"
        }
        if filter.operation == .equals {
            return "\(filter.field.displayName): \(value)"
        }
        return "\(filter.field.displayName): \(operation) \(value)"
    }

    private func sortingClause(
        _ interpretation:
            GraphChatIntentInterpretation
    ) -> String {
        let visibleSorting =
            interpretation.sorting.filter {
                sort in
                if case .nodeName = sort.key {
                    return sort.direction
                        != .ascending
                }
                return true
            }
        guard visibleSorting.isEmpty == false else {
            return ""
        }
        let language =
            interpretation.responseLanguage
        let values = visibleSorting.map { sort in
            let label = sortLabel(
                sort,
                language: language
            )
            let direction =
                sort.direction == .ascending
                ? (
                    language == .german
                    ? "aufsteigend"
                    : "ascending"
                )
                : (
                    language == .german
                    ? "absteigend"
                    : "descending"
                )
            return "\(label) \(direction)"
        }
        return (language == .german
            ? ", sortiert nach "
            : ", sorted by ")
            + joinedNames(
                values,
                language: language,
                maximumVisibleCount: 3
            )
    }

    private func sortLabel(
        _ sort: GraphChatIntentInterpretationSort,
        language: GraphChatResponseLanguage
    ) -> String {
        switch sort.key {
        case .nodeName:
            return language == .german
                ? "Name"
                : "Name"
        case .field(let field):
            return field.displayName
        }
    }

    private func operationLabel(
        _ operation: GraphQueryFilterOperator,
        language: GraphChatResponseLanguage
    ) -> String {
        switch operation {
        case .contains:
            return language == .german
                ? "enthält"
                : "contains"
        case .equals:
            return language == .german
                ? "entspricht"
                : "equals"
        case .startsWith:
            return language == .german
                ? "beginnt mit"
                : "starts with"
        case .isPresent:
            return language == .german
                ? "vorhanden"
                : "present"
        case .isMissing:
            return language == .german
                ? "fehlt"
                : "is missing"
        case .lessThan:
            return language == .german
                ? "kleiner als"
                : "less than"
        case .lessThanOrEqual:
            return language == .german
                ? "höchstens"
                : "at most"
        case .greaterThan:
            return language == .german
                ? "größer als"
                : "greater than"
        case .greaterThanOrEqual:
            return language == .german
                ? "mindestens"
                : "at least"
        case .between:
            return language == .german
                ? "zwischen"
                : "between"
        case .before:
            return language == .german
                ? "vor"
                : "before"
        case .after:
            return language == .german
                ? "nach"
                : "after"
        case .inYear:
            return language == .german
                ? "im Jahr"
                : "in"
        case .inMonth:
            return language == .german
                ? "im"
                : "in"
        case .isOverdue:
            return language == .german
                ? "überfällig"
                : "overdue"
        case .oneOf:
            return language == .german
                ? "einer von"
                : "one of"
        }
    }

    private func filterValue(
        _ filter:
            GraphChatIntentInterpretationFilter,
        interpretation:
            GraphChatIntentInterpretation
    ) -> String? {
        let language =
            interpretation.responseLanguage
        let timeZone =
            TimeZone(
                identifier:
                    interpretation
                        .formattingTimeZoneIdentifier
            ) ?? .gmt
        let unit = normalizedUnit(
            filter.field.unit
        )
        switch filter.value {
        case .none:
            return nil
        case .text(let value):
            return singleLine(value)
        case .integer(let value):
            return withUnit(
                number(value, language: language),
                unit: unit
            )
        case .integerRange(let range):
            return rangeText(
                lower:
                    number(
                        range.lowerBound,
                        language: language
                    ),
                upper:
                    number(
                        range.upperBound,
                        language: language
                    ),
                language: language,
                unit: unit
            )
        case .decimal(let value):
            return withUnit(
                decimal(
                    value,
                    language: language
                ),
                unit: unit
            )
        case .decimalRange(let range):
            return rangeText(
                lower:
                    decimal(
                        range.lowerBound,
                        language: language
                    ),
                upper:
                    decimal(
                        range.upperBound,
                        language: language
                    ),
                language: language,
                unit: unit
            )
        case .date(let value):
            return date(
                value,
                language: language,
                timeZone: timeZone
            )
        case .dateInterval(let interval):
            switch filter.operation {
            case .equals:
                return date(
                    interval.lowerBound,
                    language: language,
                    timeZone: timeZone
                )
            case .inYear:
                return year(
                    interval.lowerBound,
                    timeZone: timeZone
                )
            case .inMonth:
                return month(
                    interval.lowerBound,
                    language: language,
                    timeZone: timeZone
                )
            case .isOverdue:
                return nil
            default:
                let calendar =
                    calendar(timeZone)
                let upper =
                    calendar.date(
                        byAdding: .day,
                        value: -1,
                        to:
                            interval
                                .upperBoundExclusive
                    )
                    ?? interval
                        .upperBoundExclusive
                return rangeText(
                    lower:
                        date(
                            interval.lowerBound,
                            language: language,
                            timeZone: timeZone
                        ),
                    upper:
                        date(
                            upper,
                            language: language,
                            timeZone: timeZone
                        ),
                    language: language,
                    unit: nil
                )
            }
        case .boolean(let value):
            if language == .german {
                return value ? "Ja" : "Nein"
            }
            return value ? "Yes" : "No"
        case .choice(let value):
            return singleLine(
                value.canonicalValue
            )
        case .choices(let values):
            return joinedNames(
                values.map {
                    singleLine(
                        $0.canonicalValue
                    )
                },
                language: language,
                maximumVisibleCount: 4
            )
        }
    }

    private func joinedNames(
        _ values: [String],
        language: GraphChatResponseLanguage,
        maximumVisibleCount: Int = 3
    ) -> String {
        let normalized = values
            .map(singleLine)
            .filter { $0.isEmpty == false }
        guard normalized.isEmpty == false else {
            return language == .german
                ? "ausgewählten Einträgen"
                : "selected entries"
        }
        let visible = Array(
            normalized.prefix(
                maximumVisibleCount
            )
        )
        let omitted =
            normalized.count - visible.count
        var components = visible
        if omitted > 0 {
            components.append(
                language == .german
                    ? "\(omitted) weitere"
                    : "\(omitted) more"
            )
        }
        guard components.count > 1 else {
            return components[0]
        }
        let final = components.last!
        let initial = components.dropLast()
            .joined(separator: ", ")
        return initial
            + (
                language == .german
                ? " und "
                : " and "
            )
            + final
    }

    private func rangeText(
        lower: String,
        upper: String,
        language: GraphChatResponseLanguage,
        unit: String?
    ) -> String {
        let base = language == .german
            ? "\(lower) und \(upper)"
            : "\(lower) and \(upper)"
        return withUnit(base, unit: unit)
    }

    private func withUnit(
        _ value: String,
        unit: String?
    ) -> String {
        guard let unit,
              unit.isEmpty == false
        else {
            return value
        }
        return "\(value) \(unit)"
    }

    private func normalizedUnit(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }
        let normalized = singleLine(value)
        return normalized.isEmpty
            ? nil
            : normalized
    }

    private func number(
        _ value: Int,
        language: GraphChatResponseLanguage
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(
            identifier:
                language.localeIdentifier
        )
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(
            from: NSNumber(value: value)
        ) ?? String(value)
    }

    private func decimal(
        _ value: Double,
        language: GraphChatResponseLanguage
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(
            identifier:
                language.localeIdentifier
        )
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = true
        return formatter.string(
            from: NSNumber(value: value)
        ) ?? String(value)
    }

    private func date(
        _ value: Date,
        language: GraphChatResponseLanguage,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar =
            calendar(timeZone)
        formatter.locale = Locale(
            identifier:
                language.localeIdentifier
        )
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: value)
    }

    private func month(
        _ value: Date,
        language: GraphChatResponseLanguage,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar =
            calendar(timeZone)
        formatter.locale = Locale(
            identifier:
                language.localeIdentifier
        )
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(
            "LLLL yyyy"
        )
        return formatter.string(from: value)
    }

    private func year(
        _ value: Date,
        timeZone: TimeZone
    ) -> String {
        String(
            calendar(timeZone)
                .component(.year, from: value)
        )
    }

    private func calendar(
        _ timeZone: TimeZone
    ) -> Calendar {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone = timeZone
        return calendar
    }

    private func singleLine(
        _ value: String
    ) -> String {
        value
            .split(whereSeparator: {
                $0.isWhitespace
            })
            .joined(separator: " ")
    }
}
