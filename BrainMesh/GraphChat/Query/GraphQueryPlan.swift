//
//  GraphQueryPlan.swift
//  BrainMesh
//
//  Versioned, provider-independent graph query plans.
//

import Foundation

nonisolated struct GraphQueryIntegerRange: Hashable, Sendable {
    let lowerBound: Int
    let upperBound: Int
}

nonisolated struct GraphQueryDoubleRange: Hashable, Sendable {
    let lowerBound: Double
    let upperBound: Double
}

nonisolated struct GraphQueryDateInterval: Hashable, Sendable {
    let lowerBound: Date
    let upperBoundExclusive: Date
}

nonisolated struct GraphQueryYearMonth: Hashable, Sendable {
    let year: Int
    let month: Int
}

nonisolated enum GraphQueryFilterOperator: String, CaseIterable, Hashable, Sendable {
    case contains
    case equals
    case startsWith
    case isPresent
    case isMissing
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
    case between
    case before
    case after
    case inYear
    case inMonth
    case isOverdue
    case oneOf
}

nonisolated enum GraphQueryFilterValue: Hashable, Sendable {
    case none
    case text(String)
    case integer(Int)
    case integerRange(GraphQueryIntegerRange)
    case decimal(Double)
    case decimalRange(GraphQueryDoubleRange)
    case date(Date)
    case dateInterval(GraphQueryDateInterval)
    case year(Int)
    case month(GraphQueryYearMonth)
    case boolean(Bool)
    case choice(String)
    case choices([String])
}

nonisolated struct GraphQueryFilter: Hashable, Sendable {
    let fieldAlias: GraphFieldAlias
    let operation: GraphQueryFilterOperator
    let value: GraphQueryFilterValue
}

nonisolated enum GraphQuerySortKey: Hashable, Sendable {
    case nodeName
    case field(GraphFieldAlias)
}

nonisolated enum GraphQuerySortDirection: String, CaseIterable, Hashable, Sendable {
    case ascending
    case descending
}

nonisolated struct GraphQuerySort: Hashable, Sendable {
    let key: GraphQuerySortKey
    let direction: GraphQuerySortDirection
}

nonisolated enum GraphQueryProjection: Hashable, Sendable {
    case nodeIdentity
    case field(GraphFieldAlias)
}

nonisolated enum GraphQueryAggregation: Hashable, Sendable {
    case count
    case groupCount(GraphFieldAlias)
    case minimum(GraphFieldAlias)
    case maximum(GraphFieldAlias)
}

nonisolated struct GraphQueryPlan: Hashable, Sendable {
    static let currentVersion = 1

    let version: Int
    let entityAlias: GraphEntityAlias
    let scope: GraphChatScope?
    let filters: [GraphQueryFilter]
    let sorting: [GraphQuerySort]
    let projection: [GraphQueryProjection]
    let aggregation: GraphQueryAggregation?
    let limit: Int?

    init(
        version: Int = GraphQueryPlan.currentVersion,
        entityAlias: GraphEntityAlias,
        scope: GraphChatScope? = nil,
        filters: [GraphQueryFilter] = [],
        sorting: [GraphQuerySort] = [],
        projection: [GraphQueryProjection] = [.nodeIdentity],
        aggregation: GraphQueryAggregation? = nil,
        limit: Int? = nil
    ) {
        self.version = version
        self.entityAlias = entityAlias
        self.scope = scope
        self.filters = filters
        self.sorting = sorting
        self.projection = projection
        self.aggregation = aggregation
        self.limit = limit
    }
}

nonisolated enum GraphResolvedQueryScope: Hashable, Sendable {
    case graph
    case entity(UUID)
    case node(NodeRefKey)
    case selection([NodeRefKey])
}

nonisolated struct GraphResolvedChoiceValue: Hashable, Sendable {
    let originalValue: String
    let canonicalValue: String
}

nonisolated enum GraphValidatedFilterValue: Hashable, Sendable {
    case none
    case text(String)
    case integer(Int)
    case integerRange(GraphQueryIntegerRange)
    case decimal(Double)
    case decimalRange(GraphQueryDoubleRange)
    case date(Date)
    case dateInterval(GraphQueryDateInterval)
    case boolean(Bool)
    case choice(GraphResolvedChoiceValue)
    case choices([GraphResolvedChoiceValue])
}

nonisolated struct GraphValidatedQueryFilter: Hashable, Sendable {
    let fieldID: UUID
    let fieldType: DetailFieldType
    let operation: GraphQueryFilterOperator
    let value: GraphValidatedFilterValue
    let valueDescription: String?

    init(
        fieldID: UUID,
        fieldType: DetailFieldType,
        operation: GraphQueryFilterOperator,
        value: GraphValidatedFilterValue,
        valueDescription: String? = nil
    ) {
        self.fieldID = fieldID
        self.fieldType = fieldType
        self.operation = operation
        self.value = value
        self.valueDescription = valueDescription
    }
}

nonisolated enum GraphValidatedSortKey: Hashable, Sendable {
    case nodeName
    case field(UUID)
}

nonisolated struct GraphValidatedQuerySort: Hashable, Sendable {
    let key: GraphValidatedSortKey
    let direction: GraphQuerySortDirection
}

nonisolated enum GraphValidatedProjection: Hashable, Sendable {
    case nodeIdentity
    case field(UUID)
}

nonisolated enum GraphValidatedAggregation: Hashable, Sendable {
    case count
    case groupCount(UUID)
    case minimum(UUID)
    case maximum(UUID)
}

nonisolated struct ValidatedGraphQueryPlan: Hashable, Sendable {
    let version: Int
    let graphScope: GraphScope
    let entityID: UUID
    let scope: GraphResolvedQueryScope
    let filters: [GraphValidatedQueryFilter]
    let sorting: [GraphValidatedQuerySort]
    let projection: [GraphValidatedProjection]
    let aggregation: GraphValidatedAggregation?
    let limit: Int
}

nonisolated enum GraphQueryPlanLimits {
    static let defaultResultLimit =
        GraphChatIntentLimitPolicy
            .default.defaultQueryResultCount
    static let maximumResultLimit =
        GraphChatIntentLimitPolicy
            .default.maximumQueryResultCount
}
