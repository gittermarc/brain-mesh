//
//  GraphChatQueryIntentValueParser.swift
//  BrainMesh
//
//  Localized, deterministic typed values for app-compiled query intents.
//

import Foundation

nonisolated enum GraphChatQueryIntentValueParsingError:
    Error,
    LocalizedError,
    Hashable,
    Sendable
{
    case incompatibleRelation
    case invalidValue
    case ambiguousChoice

    var errorDescription: String? {
        switch self {
        case .incompatibleRelation:
            return "Die fachliche Filterrelation passt nicht zum ausgewählten Feldtyp."
        case .invalidValue:
            return "Der Filterwert konnte nicht eindeutig und typgerecht interpretiert werden."
        case .ambiguousChoice:
            return "Der Auswahlwert ist im aktuellen Feldschema nicht eindeutig."
        }
    }
}

nonisolated struct GraphChatQueryIntentValueParser:
    Hashable,
    Sendable
{
    private let calendar: Calendar
    private let timeZone: TimeZone

    init(
        calendar: Calendar,
        timeZone: TimeZone
    ) {
        var configuredCalendar = calendar
        configuredCalendar.timeZone = timeZone
        self.calendar = configuredCalendar
        self.timeZone = timeZone
    }

    func filter(
        _ draft: GraphChatSemanticFilterDraft,
        field: GraphSchemaFieldResolution,
        language: GraphChatResponseLanguage,
        referenceDate: Date
    ) throws -> GraphQueryFilter {
        let operation = try operation(
            for: draft,
            fieldType: field.type
        )
        guard GraphChatQueryOperatorCompatibility
            .allowedOperators(for: field.type)
            .contains(operation) else {
            throw GraphChatQueryIntentValueParsingError
                .incompatibleRelation
        }
        let value = try value(
            for: draft,
            operation: operation,
            field: field,
            language: language,
            referenceDate: referenceDate
        )
        return GraphQueryFilter(
            fieldAlias: field.alias,
            operation: operation,
            value: value
        )
    }

    private func operation(
        for draft: GraphChatSemanticFilterDraft,
        fieldType: DetailFieldType
    ) throws -> GraphQueryFilterOperator {
        switch fieldType {
        case .singleLineText, .multiLineText:
            switch draft.relation {
            case .unspecified, .contains:
                return .contains
            case .equals:
                return .equals
            case .startsWith:
                return .startsWith
            case .isPresent:
                return .isPresent
            case .isMissing:
                return .isMissing
            default:
                throw GraphChatQueryIntentValueParsingError
                    .incompatibleRelation
            }

        case .numberInt, .numberDouble:
            switch draft.relation {
            case .unspecified, .equals:
                return .equals
            case .lessThan:
                return .lessThan
            case .lessThanOrEqual:
                return .lessThanOrEqual
            case .greaterThan:
                return .greaterThan
            case .greaterThanOrEqual:
                return .greaterThanOrEqual
            case .between:
                return .between
            case .isPresent:
                return .isPresent
            case .isMissing:
                return .isMissing
            default:
                throw GraphChatQueryIntentValueParsingError
                    .incompatibleRelation
            }

        case .date:
            switch draft.relation {
            case .unspecified, .equals:
                return .equals
            case .before:
                return .before
            case .after:
                return .after
            case .between:
                return .between
            case .inYear:
                return .inYear
            case .inMonth:
                return .inMonth
            case .isOverdue:
                return .isOverdue
            case .isPresent:
                return .isPresent
            case .isMissing:
                return .isMissing
            default:
                throw GraphChatQueryIntentValueParsingError
                    .incompatibleRelation
            }

        case .toggle:
            switch draft.relation {
            case .unspecified, .equals:
                return .equals
            case .isPresent:
                return .isPresent
            case .isMissing:
                return .isMissing
            default:
                throw GraphChatQueryIntentValueParsingError
                    .incompatibleRelation
            }

        case .singleChoice:
            switch draft.relation {
            case .unspecified, .equals:
                return draft.values.count > 1
                    ? .oneOf
                    : .equals
            case .oneOf:
                return .oneOf
            case .isPresent:
                return .isPresent
            case .isMissing:
                return .isMissing
            default:
                throw GraphChatQueryIntentValueParsingError
                    .incompatibleRelation
            }
        }
    }

    private func value(
        for draft: GraphChatSemanticFilterDraft,
        operation: GraphQueryFilterOperator,
        field: GraphSchemaFieldResolution,
        language: GraphChatResponseLanguage,
        referenceDate: Date
    ) throws -> GraphQueryFilterValue {
        if operation == .isPresent
            || operation == .isMissing
            || operation == .isOverdue
        {
            guard draft.values.isEmpty else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .none
        }

        switch field.type {
        case .singleLineText, .multiLineText:
            guard draft.values.count == 1,
                  let text = normalized(draft.values[0]) else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .text(text)

        case .numberInt:
            if operation == .between {
                guard draft.values.count == 2,
                      let lower = integer(
                        draft.values[0],
                        language: language
                      ),
                      let upper = integer(
                        draft.values[1],
                        language: language
                      ),
                      lower <= upper else {
                    throw GraphChatQueryIntentValueParsingError
                        .invalidValue
                }
                return .integerRange(
                    GraphQueryIntegerRange(
                        lowerBound: lower,
                        upperBound: upper
                    )
                )
            }
            guard draft.values.count == 1,
                  let value = integer(
                    draft.values[0],
                    language: language
                  ) else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .integer(value)

        case .numberDouble:
            if operation == .between {
                guard draft.values.count == 2,
                      let lower = decimal(
                        draft.values[0],
                        language: language
                      ),
                      let upper = decimal(
                        draft.values[1],
                        language: language
                      ),
                      lower.isFinite,
                      upper.isFinite,
                      lower <= upper else {
                    throw GraphChatQueryIntentValueParsingError
                        .invalidValue
                }
                return .decimalRange(
                    GraphQueryDoubleRange(
                        lowerBound: lower,
                        upperBound: upper
                    )
                )
            }
            guard draft.values.count == 1,
                  let value = decimal(
                    draft.values[0],
                    language: language
                  ),
                  value.isFinite else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .decimal(value)

        case .date:
            return try dateValue(
                draft.values,
                operation: operation,
                language: language,
                referenceDate: referenceDate
            )

        case .toggle:
            guard draft.values.count == 1,
                  let value = boolean(
                    draft.values[0],
                    language: language
                  ) else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .boolean(value)

        case .singleChoice:
            if operation == .oneOf {
                guard draft.values.isEmpty == false else {
                    throw GraphChatQueryIntentValueParsingError
                        .invalidValue
                }
                var seen = Set<String>()
                let choices = try draft.values.map {
                    try canonicalChoice(
                        $0,
                        options: field.choiceOptions
                    )
                }.filter {
                    seen.insert(
                        GraphQueryChoiceNormalizer.normalize($0)
                    ).inserted
                }
                guard choices.isEmpty == false else {
                    throw GraphChatQueryIntentValueParsingError
                        .invalidValue
                }
                return .choices(choices)
            }
            guard draft.values.count == 1 else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .choice(
                try canonicalChoice(
                    draft.values[0],
                    options: field.choiceOptions
                )
            )
        }
    }

    private func dateValue(
        _ values: [String],
        operation: GraphQueryFilterOperator,
        language: GraphChatResponseLanguage,
        referenceDate: Date
    ) throws -> GraphQueryFilterValue {
        switch operation {
        case .inYear:
            guard values.count == 1,
                  isFourDigitYear(values[0]),
                  let year = integer(
                    values[0],
                    language: language,
                    allowsGrouping: false
                  ),
                  (1...9_999).contains(year) else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .year(year)

        case .inMonth:
            guard values.count == 1,
                  let month = yearMonth(
                    values[0],
                    language: language
                  ) else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .month(month)

        case .between:
            guard values.count == 2,
                  let lower = date(
                    values[0],
                    language: language,
                    referenceDate: referenceDate
                  ),
                  let inclusiveUpper = date(
                    values[1],
                    language: language,
                    referenceDate: referenceDate
                  ),
                  let upper = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: inclusiveUpper
                  ),
                  lower < upper else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .dateInterval(
                GraphQueryDateInterval(
                    lowerBound: lower,
                    upperBoundExclusive: upper
                )
            )

        case .equals, .before, .after:
            guard values.count == 1,
                  let value = date(
                    values[0],
                    language: language,
                    referenceDate: referenceDate
                  ) else {
                throw GraphChatQueryIntentValueParsingError
                    .invalidValue
            }
            return .date(value)

        default:
            throw GraphChatQueryIntentValueParsingError
                .incompatibleRelation
        }
    }

    private func integer(
        _ source: String,
        language: GraphChatResponseLanguage,
        allowsGrouping: Bool = true
    ) -> Int? {
        guard let value = normalizedNumeric(source) else {
            return nil
        }
        let grouping = language == .german ? "." : ","
        let escapedGrouping = NSRegularExpression
            .escapedPattern(for: grouping)
        let pattern: String
        if allowsGrouping {
            pattern =
                #"^[+-]?(?:[0-9]+|[0-9]{1,3}(?:"# +
                escapedGrouping +
                #"[0-9]{3})+)$"#
        } else {
            pattern = #"^[+-]?[0-9]+$"#
        }
        guard matches(value, pattern: pattern) else {
            return nil
        }
        return Int(
            value.replacingOccurrences(
                of: grouping,
                with: ""
            )
        )
    }

    private func decimal(
        _ source: String,
        language: GraphChatResponseLanguage
    ) -> Double? {
        guard let value = normalizedNumeric(source) else {
            return nil
        }
        let grouping = language == .german ? "." : ","
        let decimal = language == .german ? "," : "."
        let escapedGrouping = NSRegularExpression
            .escapedPattern(for: grouping)
        let escapedDecimal = NSRegularExpression
            .escapedPattern(for: decimal)
        let pattern =
            #"^[+-]?(?:[0-9]+|[0-9]{1,3}(?:"# +
            escapedGrouping +
            #"[0-9]{3})+)(?:"# +
            escapedDecimal +
            #"[0-9]+)?$"#
        guard matches(value, pattern: pattern) else {
            return nil
        }
        let canonical = value
            .replacingOccurrences(of: grouping, with: "")
            .replacingOccurrences(of: decimal, with: ".")
        guard let result = Double(canonical),
              result.isFinite else {
            return nil
        }
        return result
    }

    private func boolean(
        _ source: String,
        language: GraphChatResponseLanguage
    ) -> Bool? {
        let folded = BMSearch.fold(source)
        let trueValues: Set<String>
        let falseValues: Set<String>
        switch language {
        case .german:
            trueValues = [
                "ja",
                "wahr",
                "an",
                "aktiv",
                "wichtig",
                "markiert",
            ]
            falseValues = [
                "nein",
                "falsch",
                "aus",
                "inaktiv",
                "unwichtig",
                "unmarkiert",
            ]
        case .english:
            trueValues = [
                "yes",
                "true",
                "on",
                "active",
                "important",
                "marked",
            ]
            falseValues = [
                "no",
                "false",
                "off",
                "inactive",
                "unimportant",
                "unmarked",
            ]
        }
        if trueValues.contains(folded) {
            return true
        }
        if falseValues.contains(folded) {
            return false
        }
        return nil
    }

    private func canonicalChoice(
        _ source: String,
        options: [String]
    ) throws -> String {
        guard let value = normalized(source) else {
            throw GraphChatQueryIntentValueParsingError
                .invalidValue
        }
        if let exact = options.first(where: { $0 == value }) {
            return exact
        }
        let folded = GraphQueryChoiceNormalizer.normalize(value)
        let matches = options.filter {
            GraphQueryChoiceNormalizer.normalize($0) == folded
        }
        guard matches.isEmpty == false else {
            throw GraphChatQueryIntentValueParsingError
                .invalidValue
        }
        guard matches.count == 1, let match = matches.first else {
            throw GraphChatQueryIntentValueParsingError
                .ambiguousChoice
        }
        return match
    }

    private func date(
        _ source: String,
        language: GraphChatResponseLanguage,
        referenceDate: Date
    ) -> Date? {
        let folded = BMSearch.fold(source)
        let relativeOffset: Int?
        switch (language, folded) {
        case (.german, "heute"), (.english, "today"):
            relativeOffset = 0
        case (.german, "gestern"), (.english, "yesterday"):
            relativeOffset = -1
        case (.german, "morgen"), (.english, "tomorrow"):
            relativeOffset = 1
        default:
            relativeOffset = nil
        }
        if let relativeOffset {
            return calendar.date(
                byAdding: .day,
                value: relativeOffset,
                to: calendar.startOfDay(for: referenceDate)
            )
        }

        let normalizedSource = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = numericDateComponents(
            normalizedSource,
            language: language
        ) {
            return calendarDate(
                year: components.year,
                month: components.month,
                day: components.day
            )
        }
        return namedDate(
            normalizedSource,
            language: language
        )
    }

    private func numericDateComponents(
        _ source: String,
        language: GraphChatResponseLanguage
    ) -> (year: Int, month: Int, day: Int)? {
        let iso = source.split(separator: "-", omittingEmptySubsequences: false)
        if iso.count == 3,
           iso[0].count == 4,
           let year = Int(iso[0]),
           let month = Int(iso[1]),
           let day = Int(iso[2]),
           (1...9_999).contains(year) {
            return (year, month, day)
        }

        let separator: Character =
            language == .german ? "." : "/"
        let parts = source.split(
            separator: separator,
            omittingEmptySubsequences: false
        )
        guard parts.count == 3 else {
            return nil
        }
        switch language {
        case .german:
            guard parts[2].count == 4,
                  let day = Int(parts[0]),
                  let month = Int(parts[1]),
                  let year = Int(parts[2]),
                  (1...9_999).contains(year) else {
                return nil
            }
            return (year, month, day)
        case .english:
            guard parts[2].count == 4,
                  let month = Int(parts[0]),
                  let day = Int(parts[1]),
                  let year = Int(parts[2]),
                  (1...9_999).contains(year) else {
                return nil
            }
            return (year, month, day)
        }
    }

    private func namedDate(
        _ source: String,
        language: GraphChatResponseLanguage
    ) -> Date? {
        let tokens = BMSearch.fold(source)
            .components(
                separatedBy:
                    CharacterSet.alphanumerics.inverted
            )
            .filter { $0.isEmpty == false }
        guard tokens.count == 3 else {
            return nil
        }
        let day: Int?
        let year: Int?
        let monthToken: String
        switch language {
        case .german:
            day = Int(tokens[0])
            monthToken = tokens[1]
            year = Int(tokens[2])
        case .english:
            monthToken = tokens[0]
            day = Int(tokens[1])
            year = Int(tokens[2])
        }
        guard tokens[2].count == 4,
              let day, let year,
              (1...9_999).contains(year),
              let month = monthNumber(
                monthToken,
                language: language
              ) else {
            return nil
        }
        return calendarDate(
            year: year,
            month: month,
            day: day
        )
    }

    private func yearMonth(
        _ source: String,
        language: GraphChatResponseLanguage
    ) -> GraphQueryYearMonth? {
        let trimmed = source.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let iso = trimmed.split(
            separator: "-",
            omittingEmptySubsequences: false
        )
        if iso.count == 2,
           iso[0].count == 4,
           let year = Int(iso[0]),
           let month = Int(iso[1]),
           (1...9_999).contains(year),
           (1...12).contains(month) {
            return GraphQueryYearMonth(
                year: year,
                month: month
            )
        }

        let numericSeparator: Character =
            language == .german ? "." : "/"
        let numeric = trimmed.split(
            separator: numericSeparator,
            omittingEmptySubsequences: false
        )
        if numeric.count == 2,
           numeric[1].count == 4,
           let month = Int(numeric[0]),
           let year = Int(numeric[1]),
           (1...9_999).contains(year),
           (1...12).contains(month) {
            return GraphQueryYearMonth(
                year: year,
                month: month
            )
        }

        let tokens = BMSearch.fold(trimmed)
            .components(
                separatedBy:
                    CharacterSet.alphanumerics.inverted
            )
            .filter { $0.isEmpty == false }
        guard tokens.count == 2,
              tokens[1].count == 4,
              let month = monthNumber(
                tokens[0],
                language: language
              ),
              let year = Int(tokens[1]),
              (1...9_999).contains(year) else {
            return nil
        }
        return GraphQueryYearMonth(
            year: year,
            month: month
        )
    }

    private func monthNumber(
        _ source: String,
        language: GraphChatResponseLanguage
    ) -> Int? {
        let german = [
            "januar": 1,
            "februar": 2,
            "marz": 3,
            "april": 4,
            "mai": 5,
            "juni": 6,
            "juli": 7,
            "august": 8,
            "september": 9,
            "oktober": 10,
            "november": 11,
            "dezember": 12,
        ]
        let english = [
            "january": 1,
            "february": 2,
            "march": 3,
            "april": 4,
            "may": 5,
            "june": 6,
            "july": 7,
            "august": 8,
            "september": 9,
            "october": 10,
            "november": 11,
            "december": 12,
        ]
        return language == .german
            ? german[BMSearch.fold(source)]
            : english[BMSearch.fold(source)]
    }

    private func calendarDate(
        year: Int,
        month: Int,
        day: Int
    ) -> Date? {
        let components = DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            return nil
        }
        let roundTrip = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard roundTrip.year == year,
              roundTrip.month == month,
              roundTrip.day == day else {
            return nil
        }
        return calendar.startOfDay(for: date)
    }

    private func normalized(
        _ source: String
    ) -> String? {
        let value = source.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? nil : value
    }

    private func normalizedNumeric(
        _ source: String
    ) -> String? {
        normalized(source)?
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func isFourDigitYear(
        _ source: String
    ) -> Bool {
        guard let value = normalized(source) else {
            return false
        }
        return value.count == 4
            && value.allSatisfy {
                $0.isNumber
            }
    }

    private func matches(
        _ source: String,
        pattern: String
    ) -> Bool {
        guard let expression = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return false
        }
        let range = NSRange(
            source.startIndex..<source.endIndex,
            in: source
        )
        return expression.firstMatch(
            in: source,
            range: range
        )?.range == range
    }
}
