import Foundation
import Testing
@testable import BrainMesh

struct GraphDetailsMatcherTests {

    @Test
    func summary_isEmptyWithoutActiveFocus() {
        let preparedState = GraphDetailsPreparedState(
            attributes: [
                GraphDetailsPreparedAttribute(
                    nodeKey: makeAttributeKey("00000000-0000-0000-0000-000000000101"),
                    attributeID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                    entityID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    valuesByFieldID: [:]
                )
            ],
            fieldsByEntityID: [:]
        )

        let summary = GraphDetailsMatcher.summary(
            focusState: nil,
            preparedState: preparedState
        )

        #expect(summary == .empty)
    }

    @Test
    func summary_matchesOnlyVisibleAttributesOfTargetEntity() {
        let entityID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherEntityID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let fieldID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!

        let field = GraphDetailsPreparedField(
            id: fieldID,
            entityID: entityID,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            isPinned: true,
            unit: nil,
            options: ["Geplant", "In Arbeit", "Fertig"]
        )

        let matchingNode = makeAttributeKey("00000000-0000-0000-0000-000000000101")
        let nonMatchingNode = makeAttributeKey("00000000-0000-0000-0000-000000000102")
        let otherEntityNode = makeAttributeKey("00000000-0000-0000-0000-000000000201")

        let preparedState = GraphDetailsPreparedState(
            attributes: [
                GraphDetailsPreparedAttribute(
                    nodeKey: matchingNode,
                    attributeID: matchingNode.uuid,
                    entityID: entityID,
                    valuesByFieldID: [fieldID: .init(stringValue: "In Arbeit", intValue: nil, doubleValue: nil, dateValue: nil, boolValue: nil)]
                ),
                GraphDetailsPreparedAttribute(
                    nodeKey: nonMatchingNode,
                    attributeID: nonMatchingNode.uuid,
                    entityID: entityID,
                    valuesByFieldID: [fieldID: .init(stringValue: "Geplant", intValue: nil, doubleValue: nil, dateValue: nil, boolValue: nil)]
                ),
                GraphDetailsPreparedAttribute(
                    nodeKey: otherEntityNode,
                    attributeID: otherEntityNode.uuid,
                    entityID: otherEntityID,
                    valuesByFieldID: [fieldID: .init(stringValue: "In Arbeit", intValue: nil, doubleValue: nil, dateValue: nil, boolValue: nil)]
                )
            ],
            fieldsByEntityID: [entityID: [field]]
        )

        let focusState = GraphDetailsFocusState(
            entityID: entityID,
            entityName: "Projekt",
            rule: GraphDetailsMatchRule(
                fieldID: fieldID,
                fieldName: "Status",
                fieldType: .singleChoice,
                comparison: .equals(.choice("In Arbeit"))
            ),
            mode: .highlight
        )

        let summary = GraphDetailsMatcher.summary(
            focusState: focusState,
            preparedState: preparedState
        )

        #expect(summary.hasActiveFocus == true)
        #expect(summary.isFieldAvailable == true)
        #expect(summary.inspectedAttributeCount == 2)
        #expect(summary.matchCount == 1)
        #expect(summary.matchedAttributeNodeKeys == Set([matchingNode]))
    }

    @Test
    func matcher_supportsEmptyAndNotEmptyComparisonsForStructuredFields() {
        let field = GraphDetailsPreparedField(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Deadline",
            type: .date,
            sortIndex: 0,
            isPinned: false,
            unit: nil,
            options: []
        )

        let emptyValue = GraphDetailsPreparedValue(
            stringValue: nil,
            intValue: nil,
            doubleValue: nil,
            dateValue: nil,
            boolValue: nil
        )
        let filledValue = GraphDetailsPreparedValue(
            stringValue: nil,
            intValue: nil,
            doubleValue: nil,
            dateValue: Date(timeIntervalSince1970: 1_700_000_000),
            boolValue: nil
        )

        let emptyRule = GraphDetailsMatchRule(
            fieldID: field.id,
            fieldName: field.name,
            fieldType: .date,
            comparison: .isEmpty
        )
        let filledRule = GraphDetailsMatchRule(
            fieldID: field.id,
            fieldName: field.name,
            fieldType: .date,
            comparison: .isNotEmpty
        )

        #expect(GraphDetailsMatcher.matches(rule: emptyRule, field: field, value: emptyValue) == true)
        #expect(GraphDetailsMatcher.matches(rule: emptyRule, field: field, value: filledValue) == false)
        #expect(GraphDetailsMatcher.matches(rule: filledRule, field: field, value: emptyValue) == false)
        #expect(GraphDetailsMatcher.matches(rule: filledRule, field: field, value: filledValue) == true)
    }

    @Test
    func matcher_supportsNumericAndDateComparisons() {
        let intField = GraphDetailsPreparedField(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Punkte",
            type: .numberInt,
            sortIndex: 0,
            isPinned: false,
            unit: nil,
            options: []
        )
        let dateField = GraphDetailsPreparedField(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
            entityID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Deadline",
            type: .date,
            sortIndex: 1,
            isPinned: false,
            unit: nil,
            options: []
        )

        let intValue = GraphDetailsPreparedValue(
            stringValue: nil,
            intValue: 7,
            doubleValue: nil,
            dateValue: nil,
            boolValue: nil
        )
        let dateValue = GraphDetailsPreparedValue(
            stringValue: nil,
            intValue: nil,
            doubleValue: nil,
            dateValue: Date(timeIntervalSince1970: 1_700_000_000),
            boolValue: nil
        )

        let greaterThanRule = GraphDetailsMatchRule(
            fieldID: intField.id,
            fieldName: intField.name,
            fieldType: .numberInt,
            comparison: .greaterThan(.int(5))
        )
        let lessThanRule = GraphDetailsMatchRule(
            fieldID: dateField.id,
            fieldName: dateField.name,
            fieldType: .date,
            comparison: .lessThan(.date(Date(timeIntervalSince1970: 1_800_000_000)))
        )

        #expect(GraphDetailsMatcher.matches(rule: greaterThanRule, field: intField, value: intValue) == true)
        #expect(GraphDetailsMatcher.matches(rule: lessThanRule, field: dateField, value: dateValue) == true)
    }

    private func makeAttributeKey(_ uuidString: String) -> NodeKey {
        NodeKey(kind: .attribute, uuid: UUID(uuidString: uuidString)!)
    }
}
