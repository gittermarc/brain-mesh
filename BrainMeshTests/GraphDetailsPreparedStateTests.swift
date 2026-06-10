import Foundation
import Testing
@testable import BrainMesh
import SwiftData

struct GraphDetailsPreparedStateTests {

    @Test
    func build_keepsOnlyVisibleStructuredFieldsAndValues() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(context: testStore.context)

        let graph = builder.makeGraph(name: "Details Focus")
        let project = builder.makeEntity(name: "Projekt", in: graph)
        let visibleAttribute = builder.makeAttribute(name: "Launch", owner: project)
        let secondVisibleAttribute = builder.makeAttribute(name: "Review", owner: project)
        let unownedAttribute = MetaAttribute(name: "Orphan", graphID: graph.id)
        testStore.context.insert(unownedAttribute)

        let statusField = builder.makeDetailField(
            owner: project,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Geplant", "In Arbeit"],
            isPinned: true
        )
        let notesField = builder.makeDetailField(
            owner: project,
            name: "Notizen",
            type: .multiLineText,
            sortIndex: 1
        )

        builder.makeDetailValue(
            attribute: visibleAttribute,
            field: statusField,
            stringValue: "In Arbeit"
        )
        builder.makeDetailValue(
            attribute: visibleAttribute,
            field: notesField,
            stringValue: "Nur Textfelder dürfen nicht als Focus-Feld auftauchen."
        )
        builder.makeDetailValue(
            attribute: secondVisibleAttribute,
            field: statusField,
            stringValue: "Geplant"
        )
        try builder.save()

        let preparedState = GraphDetailsPreparedState.build(
            entities: [project],
            attributes: [visibleAttribute, secondVisibleAttribute, unownedAttribute]
        )

        #expect(Set(preparedState.attributes.map(\.attributeID)) == Set([visibleAttribute.id, secondVisibleAttribute.id]))
        #expect(preparedState.fields(for: project.id).map(\.id) == [statusField.id])
        #expect(preparedState.field(entityID: project.id, fieldID: notesField.id) == nil)
        #expect(preparedState.visibleAttributeNodeKeys == Set([
            NodeKey(kind: .attribute, uuid: visibleAttribute.id),
            NodeKey(kind: .attribute, uuid: secondVisibleAttribute.id)
        ]))

        let visiblePreparedAttribute = try #require(
            preparedState.attributes.first { $0.attributeID == visibleAttribute.id }
        )
        #expect(visiblePreparedAttribute.valuesByFieldID[statusField.id]?.stringValue == "In Arbeit")
        #expect(visiblePreparedAttribute.valuesByFieldID[notesField.id]?.stringValue == "Nur Textfelder dürfen nicht als Focus-Feld auftauchen.")
    }

    @Test
    func build_returnsEmptyWhenNoAttributesAreVisible() {
        let preparedState = GraphDetailsPreparedState.build(
            entities: [],
            attributes: []
        )

        #expect(preparedState == .empty)
    }
}
