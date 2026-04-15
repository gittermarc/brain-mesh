import Foundation

nonisolated extension DetailFieldType {
    var supportsGraphDetailsFocus: Bool {
        switch self {
        case .numberInt, .numberDouble, .date, .toggle, .singleChoice:
            return true
        case .singleLineText, .multiLineText:
            return false
        }
    }
}

enum GraphDetailsFocusMode: String, Equatable, Sendable {
    case highlight
    case onlyMatches
}

enum GraphDetailsMatchValue: Equatable, Sendable {
    case choice(String)
    case toggle(Bool)
    case int(Int)
    case double(Double)
    case date(Date)
}



enum GraphDetailsComparisonOperator: String, CaseIterable, Equatable, Sendable, Identifiable {
    case equals
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
    case isEmpty
    case isNotEmpty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .equals:
            return "="
        case .lessThan:
            return "<"
        case .lessThanOrEqual:
            return "≤"
        case .greaterThan:
            return ">"
        case .greaterThanOrEqual:
            return "≥"
        case .isEmpty:
            return "Ist leer"
        case .isNotEmpty:
            return "Ist nicht leer"
        }
    }

    var requiresValue: Bool {
        switch self {
        case .isEmpty, .isNotEmpty:
            return false
        case .equals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual:
            return true
        }
    }

    static func supported(for fieldType: DetailFieldType) -> [GraphDetailsComparisonOperator] {
        switch fieldType {
        case .singleChoice, .toggle:
            return [.equals, .isEmpty, .isNotEmpty]
        case .numberInt, .numberDouble, .date:
            return [.equals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual, .isEmpty, .isNotEmpty]
        case .singleLineText, .multiLineText:
            return []
        }
    }

    func makeComparison(value: GraphDetailsMatchValue?) -> GraphDetailsMatchComparison? {
        switch self {
        case .equals:
            guard let value else { return nil }
            return .equals(value)
        case .lessThan:
            guard let value else { return nil }
            return .lessThan(value)
        case .lessThanOrEqual:
            guard let value else { return nil }
            return .lessThanOrEqual(value)
        case .greaterThan:
            guard let value else { return nil }
            return .greaterThan(value)
        case .greaterThanOrEqual:
            guard let value else { return nil }
            return .greaterThanOrEqual(value)
        case .isEmpty:
            return .isEmpty
        case .isNotEmpty:
            return .isNotEmpty
        }
    }
}

enum GraphDetailsMatchComparison: Equatable, Sendable {
    case equals(GraphDetailsMatchValue)
    case lessThan(GraphDetailsMatchValue)
    case lessThanOrEqual(GraphDetailsMatchValue)
    case greaterThan(GraphDetailsMatchValue)
    case greaterThanOrEqual(GraphDetailsMatchValue)
    case isEmpty
    case isNotEmpty
}

struct GraphDetailsMatchRule: Equatable, Sendable {
    let fieldID: UUID
    let fieldName: String
    let fieldType: DetailFieldType
    let comparison: GraphDetailsMatchComparison
}

struct GraphDetailsFocusState: Equatable, Sendable {
    let entityID: UUID
    let entityName: String
    let rule: GraphDetailsMatchRule
    let mode: GraphDetailsFocusMode
}

struct GraphDetailsPreparedField: Equatable, Sendable {
    let id: UUID
    let entityID: UUID
    let name: String
    let type: DetailFieldType
    let sortIndex: Int
    let isPinned: Bool
    let unit: String?
    let options: [String]

    nonisolated init(
        id: UUID,
        entityID: UUID,
        name: String,
        type: DetailFieldType,
        sortIndex: Int,
        isPinned: Bool,
        unit: String?,
        options: [String]
    ) {
        self.id = id
        self.entityID = entityID
        self.name = name
        self.type = type
        self.sortIndex = sortIndex
        self.isPinned = isPinned
        self.unit = unit
        self.options = options
    }

    init(field: MetaDetailFieldDefinition) {
        self.id = field.id
        self.entityID = field.entityID
        self.name = field.name
        self.type = field.type
        self.sortIndex = field.sortIndex
        self.isPinned = field.isPinned
        self.unit = field.unit
        self.options = field.options
    }
}

struct GraphDetailsPreparedValue: Equatable, Sendable {
    let stringValue: String?
    let intValue: Int?
    let doubleValue: Double?
    let dateValue: Date?
    let boolValue: Bool?

    nonisolated init(
        stringValue: String?,
        intValue: Int?,
        doubleValue: Double?,
        dateValue: Date?,
        boolValue: Bool?
    ) {
        self.stringValue = stringValue
        self.intValue = intValue
        self.doubleValue = doubleValue
        self.dateValue = dateValue
        self.boolValue = boolValue
    }

    init(value: MetaDetailFieldValue) {
        self.stringValue = value.stringValue
        self.intValue = value.intValue
        self.doubleValue = value.doubleValue
        self.dateValue = value.dateValue
        self.boolValue = value.boolValue
    }
}

struct GraphDetailsPreparedAttribute: Equatable, Sendable {
    let nodeKey: NodeKey
    let attributeID: UUID
    let entityID: UUID
    let valuesByFieldID: [UUID: GraphDetailsPreparedValue]
}

struct GraphDetailsPreparedState: Equatable, Sendable {
    let attributes: [GraphDetailsPreparedAttribute]
    let fieldsByEntityID: [UUID: [GraphDetailsPreparedField]]

    static let empty = GraphDetailsPreparedState(attributes: [], fieldsByEntityID: [:])

    var visibleAttributeNodeKeys: Set<NodeKey> {
        Set(attributes.map(\.nodeKey))
    }

    func fields(for entityID: UUID) -> [GraphDetailsPreparedField] {
        fieldsByEntityID[entityID] ?? []
    }

    func field(entityID: UUID, fieldID: UUID) -> GraphDetailsPreparedField? {
        fields(for: entityID).first(where: { $0.id == fieldID })
    }

    static func build(
        entities: [MetaEntity],
        attributes: [MetaAttribute]
    ) -> GraphDetailsPreparedState {
        guard !attributes.isEmpty else {
            return .empty
        }

        let visibleEntityIDs = Set(attributes.compactMap { $0.owner?.id })

        var fieldsByEntityID: [UUID: [GraphDetailsPreparedField]] = [:]
        for entity in entities where visibleEntityIDs.contains(entity.id) {
            let fields = entity.detailFieldsList
                .filter { $0.type.supportsGraphDetailsFocus }
                .map { GraphDetailsPreparedField(field: $0) }
            if !fields.isEmpty {
                fieldsByEntityID[entity.id] = fields
            }
        }

        let preparedAttributes = attributes
            .compactMap { attribute -> GraphDetailsPreparedAttribute? in
                guard let owner = attribute.owner else { return nil }

                var valuesByFieldID: [UUID: GraphDetailsPreparedValue] = [:]
                valuesByFieldID.reserveCapacity(attribute.detailValuesList.count)
                for value in attribute.detailValuesList {
                    if valuesByFieldID[value.fieldID] == nil {
                        valuesByFieldID[value.fieldID] = GraphDetailsPreparedValue(value: value)
                    }
                }

                return GraphDetailsPreparedAttribute(
                    nodeKey: NodeKey(kind: .attribute, uuid: attribute.id),
                    attributeID: attribute.id,
                    entityID: owner.id,
                    valuesByFieldID: valuesByFieldID
                )
            }
            .sorted { $0.nodeKey.identifier < $1.nodeKey.identifier }

        guard !preparedAttributes.isEmpty else {
            return .empty
        }

        return GraphDetailsPreparedState(
            attributes: preparedAttributes,
            fieldsByEntityID: fieldsByEntityID
        )
    }
}

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


extension GraphDetailsMatchComparison {
    var comparisonOperator: GraphDetailsComparisonOperator {
        switch self {
        case .equals:
            return .equals
        case .lessThan:
            return .lessThan
        case .lessThanOrEqual:
            return .lessThanOrEqual
        case .greaterThan:
            return .greaterThan
        case .greaterThanOrEqual:
            return .greaterThanOrEqual
        case .isEmpty:
            return .isEmpty
        case .isNotEmpty:
            return .isNotEmpty
        }
    }

    var value: GraphDetailsMatchValue? {
        switch self {
        case .equals(let value),
             .lessThan(let value),
             .lessThanOrEqual(let value),
             .greaterThan(let value),
             .greaterThanOrEqual(let value):
            return value
        case .isEmpty, .isNotEmpty:
            return nil
        }
    }
}

extension GraphDetailsFocusMode {
    var title: String {
        switch self {
        case .highlight:
            return "Hervorheben"
        case .onlyMatches:
            return "Nur Treffer"
        }
    }
}

extension GraphDetailsPreparedField {
    var supportedComparisonOperators: [GraphDetailsComparisonOperator] {
        GraphDetailsComparisonOperator.supported(for: type)
    }
}

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
