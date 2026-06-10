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
