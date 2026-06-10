import Foundation

enum GraphDetailsFocusFormatting {
    static func ruleText(
        focusState: GraphDetailsFocusState,
        field: GraphDetailsPreparedField?
    ) -> String {
        let resolvedField = field ?? GraphDetailsPreparedField(
            id: focusState.rule.fieldID,
            entityID: focusState.entityID,
            name: focusState.rule.fieldName,
            type: focusState.rule.fieldType,
            sortIndex: 0,
            isPinned: false,
            unit: nil,
            options: []
        )

        return "\(resolvedField.name) \(comparisonText(focusState.rule.comparison, field: resolvedField))"
    }

    static func comparisonText(
        _ comparison: GraphDetailsMatchComparison,
        field: GraphDetailsPreparedField?
    ) -> String {
        let symbol = comparison.comparisonOperator.title
        guard let value = comparison.value else {
            return symbol
        }
        let valueText = matchValueText(value, field: field)
        return "\(symbol) \(valueText)"
    }

    static func matchValueText(
        _ value: GraphDetailsMatchValue,
        field: GraphDetailsPreparedField?
    ) -> String {
        switch value {
        case .choice(let choice):
            return choice
        case .toggle(let boolValue):
            return boolValue ? "Ja" : "Nein"
        case .int(let intValue):
            if let unit = field?.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
                return "\(intValue) \(unit)"
            }
            return "\(intValue)"
        case .double(let doubleValue):
            let formatted = doubleValue.formatted(.number.precision(.fractionLength(0...2)))
            if let unit = field?.unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty {
                return "\(formatted) \(unit)"
            }
            return formatted
        case .date(let dateValue):
            return dateValue.formatted(date: .numeric, time: .omitted)
        }
    }
}
