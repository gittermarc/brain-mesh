//
//  GraphChatAuthoritativeFactRenderer.swift
//  BrainMesh
//
//  Deterministic localized rendering of a single typed graph fact.
//

import Foundation

nonisolated struct GraphChatAuthoritativeFactRenderer: Sendable {
    func render(
        _ fact: GraphChatAuthoritativeFact,
        language: GraphChatResponseLanguage
    ) -> String {
        precondition(fact.hasExactlyOneValue)
        let node = singleLine(fact.nodeDisplayName)
        let field = singleLine(fact.fieldDisplayName)
        let value = formattedValue(
            fact.value,
            fieldType: fact.fieldType,
            unit: fact.unit,
            language: language,
            timeZoneIdentifier: fact.dateTimeZoneIdentifier
        )

        if fact.fieldType == .multiLineText {
            switch language {
            case .german:
                return "\(field) von \(node):\n\(value)"
            case .english:
                return "\(field) of \(node):\n\(value)"
            }
        }

        let sentence: String
        switch language {
        case .german:
            sentence = "\(field) von \(node): \(value)"
        case .english:
            sentence = "\(field) of \(node): \(value)"
        }
        return terminated(sentence)
    }

    private func formattedValue(
        _ value: GraphChatAnswerArtifactValue,
        fieldType: DetailFieldType,
        unit: String?,
        language: GraphChatResponseLanguage,
        timeZoneIdentifier: String
    ) -> String {
        let base: String
        switch value {
        case .text(let text):
            base = fieldType == .multiLineText
                ? multiLine(text)
                : singleLine(text)
        case .integer(let integer):
            base = formattedNumber(
                NSDecimalNumber(value: integer),
                language: language
            )
        case .decimal(let decimal):
            base = formattedNumber(
                NSDecimalNumber(decimal: decimal),
                language: language
            )
        case .boolean(let boolean):
            switch (language, boolean) {
            case (.german, true):
                base = "Ja"
            case (.german, false):
                base = "Nein"
            case (.english, true):
                base = "Yes"
            case (.english, false):
                base = "No"
            }
        case .date(let date):
            base = formattedDate(
                date,
                language: language,
                timeZoneIdentifier: timeZoneIdentifier
            )
        case .choice(let choice):
            base = singleLine(choice.label)
        case .dateTime(_),
            .duration(_),
            .percentage(_),
            .missing:
            preconditionFailure(
                "Unsupported authoritative single-field value."
            )
        }

        guard let unit = normalizedUnit(unit) else {
            return base
        }
        return "\(base) \(unit)"
    }

    private func formattedNumber(
        _ value: NSDecimalNumber,
        language: GraphChatResponseLanguage
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(
            identifier: language == .german ? "de_DE" : "en_US"
        )
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 38
        formatter.roundingMode = .halfEven
        return formatter.string(from: value) ?? value.stringValue
    }

    private func formattedDate(
        _ date: Date,
        language: GraphChatResponseLanguage,
        timeZoneIdentifier: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(
            identifier: language == .german ? "de_DE" : "en_US"
        )
        formatter.timeZone =
            TimeZone(identifier: timeZoneIdentifier)
            ?? TimeZone(secondsFromGMT: 0)!
        formatter.dateFormat = language == .german
            ? "dd.MM.yyyy"
            : "MM/dd/yyyy"
        return formatter.string(from: date)
    }

    private func singleLine(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private func multiLine(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedUnit(_ value: String?) -> String? {
        value.map(singleLine).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func terminated(_ value: String) -> String {
        guard let last = value.last,
              ".!?".contains(last) == false else {
            return value
        }
        return value + "."
    }
}
