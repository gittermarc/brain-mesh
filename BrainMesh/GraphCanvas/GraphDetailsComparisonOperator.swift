import Foundation

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
