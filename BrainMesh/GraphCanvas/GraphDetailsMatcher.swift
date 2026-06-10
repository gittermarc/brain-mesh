import Foundation

struct GraphDetailsMatchSummary: Equatable, Sendable {
    let activeFocus: GraphDetailsFocusState?
    let field: GraphDetailsPreparedField?
    let candidateAttributeNodeKeys: Set<NodeKey>
    let matchedAttributeNodeKeys: Set<NodeKey>

    static let empty = GraphDetailsMatchSummary(
        activeFocus: nil,
        field: nil,
        candidateAttributeNodeKeys: [],
        matchedAttributeNodeKeys: []
    )

    var hasActiveFocus: Bool {
        activeFocus != nil
    }

    var isFieldAvailable: Bool {
        field != nil
    }

    var inspectedAttributeCount: Int {
        candidateAttributeNodeKeys.count
    }

    var matchCount: Int {
        matchedAttributeNodeKeys.count
    }
}

enum GraphDetailsMatcher {
    static func summary(
        focusState: GraphDetailsFocusState?,
        preparedState: GraphDetailsPreparedState
    ) -> GraphDetailsMatchSummary {
        guard let focusState else {
            return .empty
        }

        guard let field = preparedState.field(entityID: focusState.entityID, fieldID: focusState.rule.fieldID) else {
            return GraphDetailsMatchSummary(
                activeFocus: focusState,
                field: nil,
                candidateAttributeNodeKeys: [],
                matchedAttributeNodeKeys: []
            )
        }

        let candidates = preparedState.attributes.filter { $0.entityID == focusState.entityID }
        let candidateKeys = Set(candidates.map(\.nodeKey))

        let matchedKeys = Set(
            candidates.compactMap { attribute in
                matches(rule: focusState.rule, field: field, value: attribute.valuesByFieldID[field.id])
                ? attribute.nodeKey
                : nil
            }
        )

        return GraphDetailsMatchSummary(
            activeFocus: focusState,
            field: field,
            candidateAttributeNodeKeys: candidateKeys,
            matchedAttributeNodeKeys: matchedKeys
        )
    }

    static func matches(
        rule: GraphDetailsMatchRule,
        field: GraphDetailsPreparedField,
        value: GraphDetailsPreparedValue?
    ) -> Bool {
        guard field.id == rule.fieldID else { return false }
        guard field.type == rule.fieldType else { return false }
        guard field.type.supportsGraphDetailsFocus else { return false }

        switch rule.comparison {
        case .isEmpty:
            return isEmpty(fieldType: field.type, value: value)
        case .isNotEmpty:
            return !isEmpty(fieldType: field.type, value: value)
        case .equals(let expected):
            return compare(value: value, fieldType: field.type, expected: expected, relation: .equal)
        case .lessThan(let expected):
            return compare(value: value, fieldType: field.type, expected: expected, relation: .lessThan)
        case .lessThanOrEqual(let expected):
            return compare(value: value, fieldType: field.type, expected: expected, relation: .lessThanOrEqual)
        case .greaterThan(let expected):
            return compare(value: value, fieldType: field.type, expected: expected, relation: .greaterThan)
        case .greaterThanOrEqual(let expected):
            return compare(value: value, fieldType: field.type, expected: expected, relation: .greaterThanOrEqual)
        }
    }

    private enum GraphDetailsComparisonRelation {
        case equal
        case lessThan
        case lessThanOrEqual
        case greaterThan
        case greaterThanOrEqual
    }

    private static func isEmpty(
        fieldType: DetailFieldType,
        value: GraphDetailsPreparedValue?
    ) -> Bool {
        switch fieldType {
        case .singleChoice, .singleLineText, .multiLineText:
            let raw = (value?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty
        case .numberInt:
            return value?.intValue == nil
        case .numberDouble:
            return value?.doubleValue == nil
        case .date:
            return value?.dateValue == nil
        case .toggle:
            return value?.boolValue == nil
        }
    }

    private static func compare(
        value: GraphDetailsPreparedValue?,
        fieldType: DetailFieldType,
        expected: GraphDetailsMatchValue,
        relation: GraphDetailsComparisonRelation
    ) -> Bool {
        switch (fieldType, expected) {
        case (.singleChoice, .choice(let expectedChoice)):
            let raw = (value?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return false }
            return compareStrings(raw, expectedChoice, relation: relation)

        case (.toggle, .toggle(let expectedBool)):
            guard let current = value?.boolValue else { return false }
            let lhs = current ? 1 : 0
            let rhs = expectedBool ? 1 : 0
            return compareComparable(lhs, rhs, relation: relation)

        case (.numberInt, .int(let expectedInt)):
            guard let current = value?.intValue else { return false }
            return compareComparable(current, expectedInt, relation: relation)

        case (.numberDouble, .double(let expectedDouble)):
            guard let current = value?.doubleValue else { return false }
            return compareComparable(current, expectedDouble, relation: relation)

        case (.date, .date(let expectedDate)):
            guard let current = value?.dateValue else { return false }
            return compareComparable(current, expectedDate, relation: relation)

        default:
            return false
        }
    }

    private static func compareStrings(
        _ lhs: String,
        _ rhs: String,
        relation: GraphDetailsComparisonRelation
    ) -> Bool {
        switch relation {
        case .equal:
            return lhs == rhs
        case .lessThan:
            return lhs < rhs
        case .lessThanOrEqual:
            return lhs <= rhs
        case .greaterThan:
            return lhs > rhs
        case .greaterThanOrEqual:
            return lhs >= rhs
        }
    }

    private static func compareComparable<Value: Comparable>(
        _ lhs: Value,
        _ rhs: Value,
        relation: GraphDetailsComparisonRelation
    ) -> Bool {
        switch relation {
        case .equal:
            return lhs == rhs
        case .lessThan:
            return lhs < rhs
        case .lessThanOrEqual:
            return lhs <= rhs
        case .greaterThan:
            return lhs > rhs
        case .greaterThanOrEqual:
            return lhs >= rhs
        }
    }
}
