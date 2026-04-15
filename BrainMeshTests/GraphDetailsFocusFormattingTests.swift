import Foundation
import Testing
@testable import BrainMesh

struct GraphDetailsFocusFormattingTests {

    @Test
    func supportedOperators_matchStructuredFieldTypes() {
        #expect(GraphDetailsComparisonOperator.supported(for: .singleChoice) == [.equals, .isEmpty, .isNotEmpty])
        #expect(GraphDetailsComparisonOperator.supported(for: .toggle) == [.equals, .isEmpty, .isNotEmpty])
        #expect(GraphDetailsComparisonOperator.supported(for: .numberInt) == [.equals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual, .isEmpty, .isNotEmpty])
        #expect(GraphDetailsComparisonOperator.supported(for: .numberDouble) == [.equals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual, .isEmpty, .isNotEmpty])
        #expect(GraphDetailsComparisonOperator.supported(for: .date) == [.equals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual, .isEmpty, .isNotEmpty])
        #expect(GraphDetailsComparisonOperator.supported(for: .singleLineText).isEmpty)
    }

    @Test
    func ruleText_formatsChoiceAndNumericValues() {
        let field = GraphDetailsPreparedField(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            isPinned: true,
            unit: nil,
            options: ["Geplant", "In Arbeit"]
        )
        let focus = GraphDetailsFocusState(
            entityID: field.entityID,
            entityName: "Projekt",
            rule: GraphDetailsMatchRule(
                fieldID: field.id,
                fieldName: field.name,
                fieldType: field.type,
                comparison: .equals(.choice("In Arbeit"))
            ),
            mode: .highlight
        )

        let numericField = GraphDetailsPreparedField(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            entityID: field.entityID,
            name: "Punkte",
            type: .numberInt,
            sortIndex: 1,
            isPinned: false,
            unit: nil,
            options: []
        )
        let numericFocus = GraphDetailsFocusState(
            entityID: numericField.entityID,
            entityName: "Projekt",
            rule: GraphDetailsMatchRule(
                fieldID: numericField.id,
                fieldName: numericField.name,
                fieldType: numericField.type,
                comparison: .greaterThan(.int(12))
            ),
            mode: .onlyMatches
        )

        #expect(GraphDetailsFocusFormatting.ruleText(focusState: focus, field: field) == "Status = In Arbeit")
        #expect(GraphDetailsFocusFormatting.ruleText(focusState: numericFocus, field: numericField) == "Punkte > 12")
    }

    @Test
    func makeComparison_requiresValueOnlyWhenNeeded() {
        #expect(GraphDetailsComparisonOperator.equals.makeComparison(value: nil) == nil)
        #expect(GraphDetailsComparisonOperator.isEmpty.makeComparison(value: nil) == .isEmpty)
        #expect(GraphDetailsComparisonOperator.isNotEmpty.makeComparison(value: nil) == .isNotEmpty)
        #expect(
            GraphDetailsComparisonOperator.greaterThan.makeComparison(value: .int(3))
            == .greaterThan(.int(3))
        )
    }
}
