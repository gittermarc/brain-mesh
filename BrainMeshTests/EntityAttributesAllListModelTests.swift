import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct EntityAttributesAllListModelTests {

    @Test
    func computePinnedFields_limitsToFirstThreeAndSortsBySortIndex() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Atlas", in: graph)

        let later = fixtures.makeDetailField(owner: entity, name: "Later", type: .numberInt, sortIndex: 30, isPinned: true)
        let first = fixtures.makeDetailField(owner: entity, name: "First", type: .numberInt, sortIndex: 10, isPinned: true)
        let skipped = fixtures.makeDetailField(owner: entity, name: "Skipped", type: .numberInt, sortIndex: 40, isPinned: true)
        let second = fixtures.makeDetailField(owner: entity, name: "Second", type: .singleChoice, sortIndex: 20, options: ["A", "B"], isPinned: true)
        _ = fixtures.makeDetailField(owner: entity, name: "Not pinned", type: .singleLineText, sortIndex: 5, isPinned: false)
        try fixtures.save()

        let pinned = EntityAttributesAllListModel.computePinnedFields(for: entity)

        #expect(pinned.map { $0.id } == [first.id, second.id, later.id])
        #expect(pinned.map { $0.name } == ["First", "Second", "Later"])
        #expect(pinned.contains(where: { $0.id == skipped.id }) == false)
    }

    @Test
    func sortAttributes_pinnedNumberAscending_placesMissingValuesLast() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Atlas", in: graph)
        let field = fixtures.makeDetailField(owner: entity, name: "Score", type: .numberInt, sortIndex: 0, isPinned: true)

        let low = fixtures.makeAttribute(name: "Low", owner: entity)
        let high = fixtures.makeAttribute(name: "High", owner: entity)
        let missing = fixtures.makeAttribute(name: "Missing", owner: entity)

        let lowValue = fixtures.makeDetailValue(attribute: low, field: field, intValue: 2)
        let highValue = fixtures.makeDetailValue(attribute: high, field: field, intValue: 9)
        try fixtures.save()

        let sorted = EntityAttributesAllListModel.sortAttributes(
            [missing, high, low],
            sortSelection: .pinned(fieldID: field.id, direction: .ascending),
            pinnedFields: [field],
            pinnedValuesByAttribute: [
                low.id: [field.id: lowValue],
                high.id: [field.id: highValue]
            ]
        )

        #expect(sorted.map { $0.id } == [low.id, high.id, missing.id])
    }

    @Test
    func rebuild_includesPinnedValuesInSearchAndBuildsPinnedChips() throws {
        let testStore = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: testStore.context)
        let graph = fixtures.makeGraph(name: "Primary")
        let entity = fixtures.makeEntity(name: "Atlas", in: graph)
        let status = fixtures.makeDetailField(
            owner: entity,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Todo", "Doing", "Done"],
            isPinned: true
        )

        let alpha = fixtures.makeAttribute(name: "Alpha", owner: entity, notes: "Alpha note")
        let beta = fixtures.makeAttribute(name: "Beta", owner: entity)
        _ = fixtures.makeDetailValue(attribute: alpha, field: status, stringValue: "Done")
        _ = fixtures.makeDetailValue(attribute: beta, field: status, stringValue: "Todo")
        try fixtures.save()

        let model = EntityAttributesAllListModel()
        model.rebuild(
            context: testStore.context,
            entity: entity,
            searchText: "done",
            showPinnedDetails: true,
            includeNotesPreview: false,
            sortSelection: .base(.nameAZ),
            grouping: .none
        )

        #expect(model.visibleRows.map { $0.title } == ["Alpha"])
        #expect(model.visibleRows.first?.notePreview == nil)
        #expect(model.visibleRows.first?.pinnedChips.map { $0.title } == ["Status: Done"])
        #expect(model.pinnedSortMenuOptions.map { $0.selection.rawValue } == [
            EntityAttributesAllSortSelection.pinned(fieldID: status.id, direction: .ascending).rawValue,
            EntityAttributesAllSortSelection.pinned(fieldID: status.id, direction: .descending).rawValue
        ])
    }

    @Test
    func sortSelection_rawValueRoundTripsAndFallsBackToDefault() {
        let fieldID = UUID()
        let selection = EntityAttributesAllSortSelection.pinned(fieldID: fieldID, direction: .descending)

        #expect(EntityAttributesAllSortSelection(rawValue: selection.rawValue) == selection)
        #expect(EntityAttributesAllSortSelection(rawValue: "not-a-real-selection") == .default)
        #expect(EntityAttributesAllSortSelection(rawValue: EntityAttributeSortMode.nameZA.rawValue) == .base(.nameZA))
    }
}
