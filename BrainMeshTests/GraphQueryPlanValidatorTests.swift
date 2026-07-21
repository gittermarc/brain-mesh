import Foundation
import Testing

@testable import BrainMesh

struct GraphQueryPlanValidatorTests {

    @Test
    func validatesAllSevenFieldTypesAndResolvesAliasesToTrustedIDs() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let validator = GraphChatTestSupport.makeValidator()
        let plan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F1"),
                    operation: .contains,
                    value: .text("Roadmap")
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F2"),
                    operation: .startsWith,
                    value: .text("Risiko")
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F3"),
                    operation: .between,
                    value: .integerRange(
                        GraphQueryIntegerRange(lowerBound: 2, upperBound: 8)
                    )
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F4"),
                    operation: .greaterThanOrEqual,
                    value: .decimal(1_000.5)
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F5"),
                    operation: .inYear,
                    value: .year(2024)
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F6"),
                    operation: .equals,
                    value: .boolean(true)
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F7"),
                    operation: .oneOf,
                    value: .choices(["offen", "  in   arbeit "])
                )
            ],
            sorting: [
                GraphQuerySort(
                    key: .field(GraphFieldAlias("F3")),
                    direction: .descending
                )
            ],
            projection: [
                .nodeIdentity,
                .field(GraphFieldAlias("F7"))
            ],
            aggregation: .maximum(GraphFieldAlias("F4")),
            limit: 100
        )

        let validated = try validator.validate(plan, against: context)

        #expect(validated.graphScope == context.graphScope)
        #expect(validated.entityID == GraphChatTestSupport.projectEntityID)
        #expect(validated.scope == .graph)
        #expect(validated.filters.count == 7)
        #expect(validated.filters.map(\.fieldType) == DetailFieldType.allCases)
        #expect(validated.limit == 100)
        #expect(validated.sorting == [
            GraphValidatedQuerySort(
                key: .field(validated.filters[2].fieldID),
                direction: .descending
            )
        ])
        #expect(validated.projection.count == 2)

        guard case .choices(let choices) = validated.filters[6].value else {
            Issue.record("Expected resolved choice values")
            return
        }
        #expect(choices.map(\.canonicalValue) == ["Offen", "In Arbeit"])
        #expect(choices.map(\.originalValue) == ["offen", "  in   arbeit "])

        guard case .maximum(let aggregatedFieldID) = validated.aggregation else {
            Issue.record("Expected maximum aggregation")
            return
        }
        #expect(aggregatedFieldID == validated.filters[3].fieldID)
    }


    @Test
    func operatorMatrixMatchesEverySupportedFieldTypeCombination() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let validator = GraphChatTestSupport.makeValidator()
        let cases: [(GraphFieldAlias, DetailFieldType, Set<GraphQueryFilterOperator>)] = [
            (
                GraphFieldAlias("F1"),
                .singleLineText,
                [.contains, .equals, .startsWith, .isPresent, .isMissing]
            ),
            (
                GraphFieldAlias("F2"),
                .multiLineText,
                [.contains, .equals, .startsWith, .isPresent, .isMissing]
            ),
            (
                GraphFieldAlias("F3"),
                .numberInt,
                [
                    .equals,
                    .lessThan,
                    .lessThanOrEqual,
                    .greaterThan,
                    .greaterThanOrEqual,
                    .between,
                    .isPresent,
                    .isMissing
                ]
            ),
            (
                GraphFieldAlias("F4"),
                .numberDouble,
                [
                    .equals,
                    .lessThan,
                    .lessThanOrEqual,
                    .greaterThan,
                    .greaterThanOrEqual,
                    .between,
                    .isPresent,
                    .isMissing
                ]
            ),
            (
                GraphFieldAlias("F5"),
                .date,
                [
                    .before,
                    .after,
                    .between,
                    .inYear,
                    .inMonth,
                    .isOverdue,
                    .isPresent,
                    .isMissing
                ]
            ),
            (
                GraphFieldAlias("F6"),
                .toggle,
                [.equals, .isPresent, .isMissing]
            ),
            (
                GraphFieldAlias("F7"),
                .singleChoice,
                [.equals, .oneOf, .isPresent, .isMissing]
            )
        ]

        for (alias, type, validOperations) in cases {
            for operation in GraphQueryFilterOperator.allCases {
                let value = validValue(for: type, operation: operation)
                let plan = GraphQueryPlan(
                    entityAlias: GraphEntityAlias("E1"),
                    filters: [
                        GraphQueryFilter(
                            fieldAlias: alias,
                            operation: operation,
                            value: value
                        )
                    ]
                )

                if validOperations.contains(operation) {
                    _ = try validator.validate(plan, against: context)
                } else {
                    let error = GraphChatTestSupport.validationError(
                        for: plan,
                        context: context,
                        validator: validator
                    )
                    #expect(error?.issues.map(\.code) == [.invalidOperator])
                }
            }
        }
    }

    @Test
    func rejectsInvalidOperatorTypeCombinations() {
        let plan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F1"),
                    operation: .lessThan,
                    value: .text("A")
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F3"),
                    operation: .contains,
                    value: .integer(1)
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F5"),
                    operation: .startsWith,
                    value: .date(.now)
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F6"),
                    operation: .between,
                    value: .boolean(true)
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F7"),
                    operation: .contains,
                    value: .choice("Offen")
                )
            ]
        )
        let error = GraphChatTestSupport.validationError(for: plan)

        #expect(error?.issues.count == 5)
        #expect(error?.issues.allSatisfy { $0.code == .invalidOperator } == true)
    }

    @Test
    func rejectsUnknownAliasesAndFieldsFromAnotherEntity() {
        let unknownEntity = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E99")
        )
        let unknownField = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F99"),
                    operation: .equals,
                    value: .text("A")
                )
            ]
        )
        let foreignField = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F8"),
                    operation: .equals,
                    value: .text("Owner")
                )
            ]
        )

        #expect(codes(for: unknownEntity) == [.unknownEntityAlias])
        #expect(codes(for: unknownField) == [.unknownFieldAlias])
        #expect(codes(for: foreignField) == [.fieldEntityMismatch])
    }

    @Test
    func choiceNormalizationIsExplicitAndRejectsInvalidOrAmbiguousValues() throws {
        let validator = GraphChatTestSupport.makeValidator()
        let normalizedPlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F7"),
                    operation: .equals,
                    value: .choice("  in   arbeit ")
                )
            ]
        )
        let normalized = try validator.validate(
            normalizedPlan,
            against: GraphChatTestSupport.makeSchemaContext()
        )

        guard case .choice(let choice) = normalized.filters[0].value else {
            Issue.record("Expected a resolved choice")
            return
        }
        #expect(choice.originalValue == "  in   arbeit ")
        #expect(choice.canonicalValue == "In Arbeit")

        let invalidPlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F7"),
                    operation: .equals,
                    value: .choice("Blockiert")
                )
            ]
        )
        #expect(codes(for: invalidPlan) == [.invalidChoiceValue])

        let ambiguousPlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F7"),
                    operation: .equals,
                    value: .choice("CAFE")
                )
            ]
        )
        let ambiguousError = GraphChatTestSupport.validationError(
            for: ambiguousPlan,
            context: GraphChatTestSupport.makeSchemaContext(
                choiceOptions: ["Café", "Cafe"]
            )
        )
        #expect(ambiguousError?.issues.map(\.code) == [.ambiguousChoiceValue])
    }

    @Test
    func enforcesHardLimitsAndPlanVersion() {
        let tooSmall = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            limit: 0
        )
        let tooLarge = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            limit: GraphQueryPlanLimits.maximumResultLimit + 1
        )
        let unsupported = GraphQueryPlan(
            version: GraphQueryPlan.currentVersion + 1,
            entityAlias: GraphEntityAlias("E1")
        )

        #expect(codes(for: tooSmall) == [.invalidLimit])
        #expect(codes(for: tooLarge) == [.invalidLimit])
        #expect(codes(for: unsupported) == [.unsupportedVersion])
    }

    @Test
    func validatesEntityNodeAndSelectionScopesInsideActiveGraph() throws {
        let context = GraphChatTestSupport.makeSchemaContext()
        let validator = GraphChatTestSupport.makeValidator()
        let graphScope = context.graphScope
        let entityNode = NodeRefKey(
            kind: .entity,
            id: GraphChatTestSupport.projectEntityID
        )
        let attributeNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let entityPlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            scope: .entity(GraphChatTestSupport.projectEntityID, in: graphScope)
        )
        let nodePlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            scope: .node(attributeNode, in: graphScope)
        )
        let selectionPlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            scope: try .selection([attributeNode, entityNode], in: graphScope)
        )

        #expect(
            try validator.validate(entityPlan, against: context).scope
                == .entity(GraphChatTestSupport.projectEntityID)
        )
        #expect(
            try validator.validate(nodePlan, against: context).scope
                == .node(attributeNode)
        )
        #expect(
            try validator.validate(selectionPlan, against: context).scope
                == .selection([entityNode, attributeNode])
        )
    }

    @Test
    func rejectsForeignGraphUnknownNodesAndScopeEntityMismatches() {
        let context = GraphChatTestSupport.makeSchemaContext()
        let foreignGraphScope = GraphScope(graphID: GraphChatTestSupport.otherGraphID)
        let attributeNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let foreignGraphPlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            scope: .node(attributeNode, in: foreignGraphScope)
        )
        let unknownNodePlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            scope: .node(
                NodeRefKey(kind: .attribute, id: UUID()),
                in: context.graphScope
            )
        )
        let wrongEntityPlan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            scope: .entity(
                GraphChatTestSupport.personEntityID,
                in: context.graphScope
            )
        )

        #expect(codes(for: foreignGraphPlan) == [.graphScopeMismatch])
        #expect(codes(for: unknownNodePlan) == [.unknownScopeNode])
        #expect(codes(for: wrongEntityPlan) == [.scopeEntityMismatch])
    }

    @Test
    func rejectsInvalidRangesDuplicateProjectionAndUnsupportedAggregation() {
        let plan = GraphQueryPlan(
            entityAlias: GraphEntityAlias("E1"),
            filters: [
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F3"),
                    operation: .between,
                    value: .integerRange(
                        GraphQueryIntegerRange(lowerBound: 10, upperBound: 1)
                    )
                ),
                GraphQueryFilter(
                    fieldAlias: GraphFieldAlias("F4"),
                    operation: .equals,
                    value: .decimal(.infinity)
                )
            ],
            projection: [.nodeIdentity, .nodeIdentity],
            aggregation: .minimum(GraphFieldAlias("F1"))
        )
        let error = GraphChatTestSupport.validationError(for: plan)
        let issueCodes = error?.issues.map(\.code) ?? []

        #expect(issueCodes.filter { $0 == .invalidRange }.count == 2)
        #expect(issueCodes.contains(.duplicateProjection))
        #expect(issueCodes.contains(.invalidAggregation))
    }


    private func validValue(
        for type: DetailFieldType,
        operation: GraphQueryFilterOperator
    ) -> GraphQueryFilterValue {
        if operation == .isPresent || operation == .isMissing || operation == .isOverdue {
            return .none
        }

        switch type {
        case .singleLineText, .multiLineText:
            return .text("Value")
        case .numberInt:
            if operation == .between {
                return .integerRange(
                    GraphQueryIntegerRange(lowerBound: 1, upperBound: 2)
                )
            }
            return .integer(1)
        case .numberDouble:
            if operation == .between {
                return .decimalRange(
                    GraphQueryDoubleRange(lowerBound: 1, upperBound: 2)
                )
            }
            return .decimal(1)
        case .date:
            switch operation {
            case .between:
                return .dateInterval(
                    GraphQueryDateInterval(
                        lowerBound: Date(timeIntervalSince1970: 1),
                        upperBoundExclusive: Date(timeIntervalSince1970: 2)
                    )
                )
            case .inYear:
                return .year(2024)
            case .inMonth:
                return .month(GraphQueryYearMonth(year: 2024, month: 6))
            default:
                return .date(Date(timeIntervalSince1970: 1))
            }
        case .toggle:
            return .boolean(true)
        case .singleChoice:
            if operation == .oneOf {
                return .choices(["Offen", "Fertig"])
            }
            return .choice("Offen")
        }
    }

    private func codes(for plan: GraphQueryPlan) -> [GraphQueryPlanValidationIssueCode] {
        GraphChatTestSupport.validationError(for: plan)?.issues.map(\.code) ?? []
    }
}
