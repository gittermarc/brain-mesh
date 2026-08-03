//
//  GraphChatDeterministicAnswerFallbackRenderer.swift
//  BrainMesh
//
//  Localized, value-only minimum answers derived from the authoritative primary tool result.
//

import Foundation

nonisolated struct GraphChatDeterministicAnswerFallbackRenderer: Sendable {
    private let maximumArtifactSummaries = 3
    private let maximumExamples = 3
    private let maximumDisplayLength = 120

    func render(
        source: GraphChatDeterministicAnswerFallbackSource,
        language: GraphChatResponseLanguage
    ) -> String {
        guard source.completionStatus == .succeeded else {
            return GraphChatResponseLocalizer(language: language).noResults()
        }

        var summaries: [String] = []
        for artifact in source.artifacts {
            guard summaries.count < maximumArtifactSummaries,
                  let summary = summary(
                    for: artifact,
                    language: language
                  ),
                  summaries.contains(summary) == false else {
                continue
            }
            summaries.append(summary)
        }
        if summaries.isEmpty == false {
            return summaries.joined(separator: " ")
        }
        return evidenceSummary(
            source.evidence,
            language: language
        )
    }

    func genericValidatedResult(
        language: GraphChatResponseLanguage
    ) -> String {
        switch language {
        case .german:
            return "Ich habe ein validiertes Ergebnis gefunden. Die zugehörigen Quellen sind in der Antwort verfügbar."
        case .english:
            return "I found a validated result. Its supporting sources are available with the answer."
        }
    }

    private func summary(
        for artifact: GraphChatAnswerArtifact,
        language: GraphChatResponseLanguage
    ) -> String? {
        switch artifact.payload {
        case .nodeProfile(let payload):
            return GraphChatNodeProfilePresentation(
                payload: payload,
                language: language
            ).plainText
        case .relationship(let payload):
            return GraphChatRelationshipPresentation(
                payload: payload
            ).plainText

        case .metric(let payload):
            return metricSummary(
                payload,
                language: language
            )

        case .resultList(let payload):
            return resultListSummary(
                payload,
                subject: artifact.querySummary?.entityLabel,
                queryLimit: artifact.querySummary?.limit,
                language: language
            )

        case .table(let payload):
            return tableSummary(
                payload,
                subject: artifact.querySummary?.entityLabel,
                title: artifact.title,
                isQueryResult: artifact.querySummary != nil,
                queryLimit: artifact.querySummary?.limit,
                language: language
            )

        case .ranking(let payload):
            return rankingSummary(
                payload,
                language: language
            )

        case .grouping(let payload):
            return groupingSummary(
                payload,
                subject: artifact.querySummary?.entityLabel,
                language: language
            )

        case .comparison(let payload):
            return comparisonSummary(
                payload,
                language: language
            )

        case .healthFinding(let payload):
            return healthSummary(
                payload,
                language: language
            )

        case .timeline(let payload):
            return timelineSummary(
                payload,
                language: language
            )
        }
    }

    private func metricSummary(
        _ payload: GraphChatAnswerArtifactMetricPayload,
        language: GraphChatResponseLanguage
    ) -> String {
        let title = cleaned(payload.title)
        let value = formattedValue(
            payload.value,
            unit: payload.unit,
            language: language
        )
        switch language {
        case .german:
            return "\(title): \(value)."
        case .english:
            return "\(title): \(value)."
        }
    }

    private func resultListSummary(
        _ payload: GraphChatAnswerArtifactResultListPayload,
        subject: String?,
        queryLimit: Int?,
        language: GraphChatResponseLanguage
    ) -> String {
        let total = payload.resultMetadata.totalCount
            ?? payload.resultMetadata.returnedCount
        let countSentence = resultCountSentence(
            total,
            subject: subject,
            language: language
        )
        let names = payload.rows.prefix(maximumExamples).map { row in
            let primary = cleaned(row.primaryText)
            guard let secondary = row.secondaryText.map(cleaned),
                  secondary.isEmpty == false else {
                return primary
            }
            return "\(primary) (\(secondary))"
        }.filter { $0.isEmpty == false }
        return countSentence
            + examplesSentence(
                names,
                total: total,
                language: language
            )
            + truncationSentence(
                payload.resultMetadata,
                queryLimit: queryLimit,
                language: language
            )
    }

    private func tableSummary(
        _ payload: GraphChatAnswerArtifactTablePayload,
        subject: String?,
        title: String,
        isQueryResult: Bool,
        queryLimit: Int?,
        language: GraphChatResponseLanguage
    ) -> String {
        if isQueryResult {
            let total = payload.resultMetadata.totalCount
                ?? payload.resultMetadata.returnedCount
            let names = tablePrimaryValues(
                payload,
                language: language
            )
            return resultCountSentence(
                total,
                subject: subject,
                language: language
            ) + examplesSentence(
                names,
                total: total,
                language: language
            ) + truncationSentence(
                payload.resultMetadata,
                queryLimit: queryLimit,
                language: language
            )
        }

        let details = tableDetailValues(
            payload,
            language: language
        )
        let safeTitle = cleaned(title)
        switch language {
        case .german:
            guard details.isEmpty == false else {
                return "Ich habe die validierten Details für \(safeTitle) gefunden."
            }
            return "Ich habe die validierten Details für \(safeTitle) gefunden. Die ersten Angaben sind \(joined(details, language: language))."
        case .english:
            guard details.isEmpty == false else {
                return "I found the validated details for \(safeTitle)."
            }
            return "I found the validated details for \(safeTitle). The first details are \(joined(details, language: language))."
        }
    }

    private func rankingSummary(
        _ payload: GraphChatAnswerArtifactRankingPayload,
        language: GraphChatResponseLanguage
    ) -> String {
        let total = payload.resultMetadata.totalCount
            ?? payload.resultMetadata.returnedCount
        let examples = payload.entries.prefix(maximumExamples).map { entry in
            "\(cleaned(entry.label)) (\(formattedValue(entry.value, language: language)))"
        }
        switch language {
        case .german:
            let lead = "Die Rangliste enthält \(total) Einträge."
            guard examples.isEmpty == false else {
                return lead
            }
            return "\(lead) Die ersten Einträge sind \(joined(examples, language: language))."
        case .english:
            let lead = "The ranking contains \(total) entries."
            guard examples.isEmpty == false else {
                return lead
            }
            return "\(lead) The first entries are \(joined(examples, language: language))."
        }
    }

    private func groupingSummary(
        _ payload: GraphChatAnswerArtifactGroupingPayload,
        subject: String?,
        language: GraphChatResponseLanguage
    ) -> String {
        let total = payload.groups.reduce(0) { $0 + $1.count }
        let groups = payload.groups.prefix(maximumExamples).map {
            "\(cleaned($0.label)): \($0.count)"
        }
        let safeSubject = subject.map(cleaned)
        switch language {
        case .german:
            let lead = safeSubject.map {
                "Ich habe \(total) \($0) in \(payload.groups.count) Gruppen zusammengefasst."
            } ?? "Ich habe \(total) Ergebnisse in \(payload.groups.count) Gruppen zusammengefasst."
            guard groups.isEmpty == false else {
                return lead
            }
            return "\(lead) Die ersten Gruppen sind \(joined(groups, language: language))."
        case .english:
            let lead = safeSubject.map {
                "I grouped \(total) \($0) into \(payload.groups.count) groups."
            } ?? "I grouped \(total) results into \(payload.groups.count) groups."
            guard groups.isEmpty == false else {
                return lead
            }
            return "\(lead) The first groups are \(joined(groups, language: language))."
        }
    }

    private func comparisonSummary(
        _ payload: GraphChatAnswerArtifactComparisonPayload,
        language: GraphChatResponseLanguage
    ) -> String {
        let subjects = payload.subjects.prefix(maximumExamples).map {
            cleaned($0.label)
        }
        let featureNames = payload.features.prefix(maximumExamples).map {
            cleaned($0.label)
        }
        switch language {
        case .german:
            var result = "Ich habe \(payload.subjects.count) Einträge anhand von \(payload.features.count) Merkmalen verglichen."
            if subjects.isEmpty == false {
                result += " Verglichen wurden \(joined(subjects, language: language))."
            }
            if featureNames.isEmpty == false {
                result += " Zu den Merkmalen gehören \(joined(featureNames, language: language))."
            }
            return result
        case .english:
            var result = "I compared \(payload.subjects.count) items across \(payload.features.count) features."
            if subjects.isEmpty == false {
                result += " The compared items are \(joined(subjects, language: language))."
            }
            if featureNames.isEmpty == false {
                result += " The features include \(joined(featureNames, language: language))."
            }
            return result
        }
    }

    private func healthSummary(
        _ payload: GraphChatAnswerArtifactHealthFindingPayload,
        language: GraphChatResponseLanguage
    ) -> String {
        let summary = cleaned(payload.summary)
        if summary.isEmpty == false {
            return summary
        }
        switch language {
        case .german:
            return "Der validierte Graph-Health-Befund betrifft \(payload.affectedElementCount) Elemente."
        case .english:
            return "The validated graph health finding affects \(payload.affectedElementCount) items."
        }
    }

    private func timelineSummary(
        _ payload: GraphChatAnswerArtifactTimelinePayload,
        language: GraphChatResponseLanguage
    ) -> String {
        let total = payload.resultMetadata.totalCount
            ?? payload.resultMetadata.returnedCount
        let examples = payload.entries.prefix(maximumExamples).map { entry in
            let title = cleaned(entry.title)
            let interval = formattedInterval(
                entry.interval,
                language: language
            )
            return "\(title) (\(interval))"
        }
        switch language {
        case .german:
            let lead = "Ich habe \(total) zeitliche Ergebnisse gefunden."
            guard examples.isEmpty == false else {
                return lead
            }
            return "\(lead) Die ersten Einträge sind \(joined(examples, language: language))."
        case .english:
            let lead = "I found \(total) timeline results."
            guard examples.isEmpty == false else {
                return lead
            }
            return "\(lead) The first entries are \(joined(examples, language: language))."
        }
    }

    private func evidenceSummary(
        _ evidence: [GraphEvidence],
        language: GraphChatResponseLanguage
    ) -> String {
        let names = evidence.compactMap { item -> String? in
            guard let title = item.navigationTitle else {
                return nil
            }
            let value = cleaned(title)
            return value.isEmpty ? nil : value
        }
        let uniqueNames = Array(
            names.reduce(into: [String]()) { result, name in
                if result.contains(name) == false {
                    result.append(name)
                }
            }.prefix(maximumExamples)
        )
        guard uniqueNames.isEmpty == false else {
            return genericValidatedResult(language: language)
        }
        switch language {
        case .german:
            return "Ich habe ein validiertes Ergebnis gefunden. Dazu gehören \(joined(uniqueNames, language: language))."
        case .english:
            return "I found a validated result. It includes \(joined(uniqueNames, language: language))."
        }
    }

    private func resultCountSentence(
        _ count: Int,
        subject: String?,
        language: GraphChatResponseLanguage
    ) -> String {
        let safeSubject = subject.map(cleaned)
        switch language {
        case .german:
            if let safeSubject, safeSubject.isEmpty == false {
                return "Ich habe \(count) \(safeSubject) gefunden."
            }
            return count == 1
                ? "Ich habe 1 Ergebnis gefunden."
                : "Ich habe \(count) Ergebnisse gefunden."
        case .english:
            if let safeSubject, safeSubject.isEmpty == false {
                return "I found \(count) \(safeSubject)."
            }
            return count == 1
                ? "I found 1 result."
                : "I found \(count) results."
        }
    }

    private func examplesSentence(
        _ examples: [String],
        total: Int,
        language: GraphChatResponseLanguage
    ) -> String {
        guard examples.isEmpty == false else {
            return ""
        }
        let values = joined(examples, language: language)
        switch language {
        case .german:
            if total == 1 {
                return " Das Ergebnis ist \(values)."
            }
            return " Die ersten Ergebnisse sind \(values)."
        case .english:
            if total == 1 {
                return " The result is \(values)."
            }
            return " The first results are \(values)."
        }
    }

    private func truncationSentence(
        _ metadata: GraphChatAnswerArtifactResultMetadata,
        queryLimit: Int?,
        language: GraphChatResponseLanguage
    ) -> String {
        guard metadata.truncation.isTruncated else {
            return ""
        }
        let onlySourceLimited =
            Set(metadata.truncation.reasons) == [.sourceLimited]
        if onlySourceLimited {
            switch language {
            case .german:
                return " Nicht alle Einträge konnten gegen die aktuelle Datenquelle revalidiert werden."
            case .english:
                return " Not every item could be revalidated against the current data source."
            }
        }
        if metadata.truncation.reasons
            .contains(.appPolicy) {
            switch language {
            case .german:
                return " Die Ausgabe ist durch das app-eigene Sicherheitsbudget begrenzt."
            case .english:
                return " The output is capped by the app-owned safety budget."
            }
        }
        guard metadata.truncation.reasons.contains(.queryLimit),
              queryLimit == GraphQueryPlanLimits.maximumResultLimit else {
            return ""
        }
        switch language {
        case .german:
            if let omitted = metadata.truncation.omittedCount,
               omitted > 0 {
                return " Die Ausgabe ist auf das Sicherheitslimit begrenzt; \(omitted) weitere Einträge sind nicht enthalten."
            }
            return " Die Ausgabe ist auf das zulässige Sicherheitslimit begrenzt."
        case .english:
            if let omitted = metadata.truncation.omittedCount,
               omitted > 0 {
                return " The output is capped at the safety limit; \(omitted) additional items are not included."
            }
            return " The output is capped at the allowed safety limit."
        }
    }

    private func tablePrimaryValues(
        _ payload: GraphChatAnswerArtifactTablePayload,
        language: GraphChatResponseLanguage
    ) -> [String] {
        guard let primaryColumn = payload.columns.first(where: {
            $0.role == .primary
        }) ?? payload.columns.first else {
            return []
        }
        return payload.rows.prefix(maximumExamples).compactMap { row in
            guard let cell = row.cells.first(where: {
                $0.columnID == primaryColumn.id
            }) else {
                return nil
            }
            return formattedValue(
                cell.value,
                presentation: primaryColumn.valuePresentation,
                unit: primaryColumn.unit,
                language: language
            )
        }
    }

    private func tableDetailValues(
        _ payload: GraphChatAnswerArtifactTablePayload,
        language: GraphChatResponseLanguage
    ) -> [String] {
        let columnsByID = Dictionary(
            uniqueKeysWithValues: payload.columns.map { ($0.id, $0) }
        )
        let fieldColumn = payload.columns.first { $0.key == "field" }
        let valueColumn = payload.columns.first { $0.key == "value" }
        let unitColumn = payload.columns.first { $0.key == "unit" }

        if let fieldColumn, let valueColumn {
            return payload.rows.prefix(maximumExamples).compactMap { row in
                guard let fieldCell = row.cells.first(where: {
                    $0.columnID == fieldColumn.id
                }),
                    let valueCell = row.cells.first(where: {
                        $0.columnID == valueColumn.id
                    })
                else {
                    return nil
                }
                let field = formattedValue(
                    fieldCell.value,
                    presentation: fieldColumn.valuePresentation,
                    language: language
                )
                var value = formattedValue(
                    valueCell.value,
                    presentation: valueColumn.valuePresentation,
                    unit: valueColumn.unit,
                    language: language
                )
                if let unitColumn,
                   let unitCell = row.cells.first(where: {
                       $0.columnID == unitColumn.id
                   }),
                   case .missing = unitCell.value {
                    // Missing optional units are intentionally omitted.
                } else if let unitColumn,
                          let unitCell = row.cells.first(where: {
                              $0.columnID == unitColumn.id
                          }) {
                    let unit = formattedValue(
                        unitCell.value,
                        presentation: unitColumn.valuePresentation,
                        language: language
                    )
                    if unit.isEmpty == false {
                        value += " \(unit)"
                    }
                }
                return "\(field): \(value)"
            }
        }

        return payload.rows.prefix(maximumExamples).compactMap { row in
            let values = row.cells.prefix(2).compactMap { cell -> String? in
                guard let column = columnsByID[cell.columnID] else {
                    return nil
                }
                let value = formattedValue(
                    cell.value,
                    presentation: column.valuePresentation,
                    unit: column.unit,
                    language: language
                )
                return value.isEmpty ? nil : "\(cleaned(column.title)): \(value)"
            }
            return values.isEmpty ? nil : values.joined(separator: ", ")
        }
    }

    private func formattedValue(
        _ value: GraphChatAnswerArtifactValue,
        presentation: GraphChatAnswerArtifactValuePresentation? = nil,
        unit: String? = nil,
        language: GraphChatResponseLanguage
    ) -> String {
        let locale = Locale(identifier: language.localeIdentifier)
        let base: String
        switch value {
        case .text(let value):
            base = cleaned(value)
        case .integer(let value):
            base = value.formatted(.number.locale(locale))
        case .decimal(let value):
            base = NSDecimalNumber(decimal: value).doubleValue.formatted(
                .number
                    .precision(.fractionLength(0...3))
                    .locale(locale)
            )
        case .boolean(let value):
            if value {
                base = presentation?.booleanTrueLabel
                    ?? (language == .german ? "Ja" : "Yes")
            } else {
                base = presentation?.booleanFalseLabel
                    ?? (language == .german ? "Nein" : "No")
            }
        case .date(let value):
            base = formattedDate(
                value,
                includesTime: presentation?.dateFormat == .localizedDateTime,
                language: language
            )
        case .dateTime(let value):
            base = formattedDate(
                value,
                includesTime: presentation?.dateFormat != .localizedDate,
                language: language
            )
        case .duration(let value):
            base = formattedDuration(
                value,
                language: language
            )
        case .percentage(let value):
            base = NSDecimalNumber(decimal: value).doubleValue.formatted(
                .percent
                    .precision(.fractionLength(0...1))
                    .locale(locale)
            )
        case .choice(let value):
            base = cleaned(
                presentation?.choiceLabels.first {
                    $0.value == value.value
                }?.label ?? value.label
            )
        case .missing:
            return presentation?.missingLabel
                ?? (language == .german ? "Fehlend" : "Missing")
        }

        guard let unit = unit.map(cleaned),
              unit.isEmpty == false else {
            return base
        }
        return "\(base) \(unit)"
    }

    private func formattedInterval(
        _ interval: GraphChatAnswerArtifactTimeInterval,
        language: GraphChatResponseLanguage
    ) -> String {
        let start = formattedDate(
            interval.start,
            includesTime: false,
            language: language
        )
        guard let end = interval.end else {
            return start
        }
        return "\(start)–\(formattedDate(end, includesTime: false, language: language))"
    }

    private func formattedDuration(
        _ interval: TimeInterval,
        language: GraphChatResponseLanguage
    ) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        var parts: [String] = []
        if days > 0 {
            parts.append(
                language == .german
                    ? "\(days) T."
                    : "\(days) d"
            )
        }
        if hours > 0 {
            parts.append(
                language == .german
                    ? "\(hours) Std."
                    : "\(hours) hr"
            )
        }
        if minutes > 0 {
            parts.append(
                language == .german
                    ? "\(minutes) Min."
                    : "\(minutes) min"
            )
        }
        if parts.isEmpty {
            parts.append(
                language == .german
                    ? "\(seconds) Sek."
                    : "\(seconds) sec"
            )
        }
        return parts.prefix(2).joined(separator: " ")
    }

    private func formattedDate(
        _ date: Date,
        includesTime: Bool,
        language: GraphChatResponseLanguage
    ) -> String {
        let style = Date.FormatStyle(
            date: .abbreviated,
            time: includesTime ? .shortened : .omitted,
            locale: Locale(identifier: language.localeIdentifier)
        )
        return date.formatted(style)
    }

    private func joined(
        _ values: [String],
        language: GraphChatResponseLanguage
    ) -> String {
        let bounded = Array(values.prefix(maximumExamples))
        guard let last = bounded.last else {
            return ""
        }
        guard bounded.count > 1 else {
            return last
        }
        let prefix = bounded.dropLast().joined(separator: ", ")
        return "\(prefix)\(language == .german ? " und " : " and ")\(last)"
    }

    private func cleaned(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumDisplayLength else {
            return trimmed
        }
        return String(trimmed.prefix(maximumDisplayLength))
    }
}
