import Foundation
import Testing
@testable import BrainMesh

struct GraphCanvasFocusHistoryStoreTests {

    @Test
    func recordFocusAddsNewItem() {
        let defaults = makeDefaults()
        let store = GraphCanvasFocusHistoryStore(defaults: defaults)
        let graphID = UUID()
        let entityID = UUID()
        let focusedAt = Date(timeIntervalSince1970: 100)

        store.recordFocus(
            graphID: graphID,
            entityID: entityID,
            label: "Project Atlas",
            focusedAt: focusedAt
        )

        let items = store.items(graphID: graphID, limit: 10)
        #expect(items.count == 1)
        #expect(items.first?.graphID == graphID)
        #expect(items.first?.entityID == entityID)
        #expect(items.first?.label == "Project Atlas")
        #expect(items.first?.focusedAt == focusedAt)
    }

    @Test
    func recordFocusDeduplicatesAndUpdatesExistingItem() {
        let defaults = makeDefaults()
        let store = GraphCanvasFocusHistoryStore(defaults: defaults)
        let graphID = UUID()
        let entityID = UUID()

        store.recordFocus(
            graphID: graphID,
            entityID: entityID,
            label: "Old Label",
            focusedAt: Date(timeIntervalSince1970: 100)
        )
        store.recordFocus(
            graphID: graphID,
            entityID: entityID,
            label: "New Label",
            focusedAt: Date(timeIntervalSince1970: 200)
        )

        let items = store.items(graphID: graphID, limit: 10)
        #expect(items.count == 1)
        #expect(items.first?.label == "New Label")
        #expect(items.first?.focusedAt == Date(timeIntervalSince1970: 200))
    }

    @Test
    func itemsAreScopedByGraph() {
        let defaults = makeDefaults()
        let store = GraphCanvasFocusHistoryStore(defaults: defaults)
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let firstEntityID = UUID()
        let secondEntityID = UUID()

        store.recordFocus(
            graphID: firstGraphID,
            entityID: firstEntityID,
            label: "First Graph",
            focusedAt: Date(timeIntervalSince1970: 100)
        )
        store.recordFocus(
            graphID: secondGraphID,
            entityID: secondEntityID,
            label: "Second Graph",
            focusedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(store.items(graphID: firstGraphID, limit: 10).map(\.entityID) == [firstEntityID])
        #expect(store.items(graphID: secondGraphID, limit: 10).map(\.entityID) == [secondEntityID])
    }

    @Test
    func maxItemsPerGraphIsEnforced() {
        let defaults = makeDefaults()
        let store = GraphCanvasFocusHistoryStore(defaults: defaults, maxItemsPerGraph: 2)
        let graphID = UUID()
        let firstEntityID = UUID()
        let secondEntityID = UUID()
        let thirdEntityID = UUID()

        store.recordFocus(graphID: graphID, entityID: firstEntityID, label: "First", focusedAt: Date(timeIntervalSince1970: 100))
        store.recordFocus(graphID: graphID, entityID: secondEntityID, label: "Second", focusedAt: Date(timeIntervalSince1970: 200))
        store.recordFocus(graphID: graphID, entityID: thirdEntityID, label: "Third", focusedAt: Date(timeIntervalSince1970: 300))

        #expect(store.items(graphID: graphID, limit: 10).map(\.entityID) == [thirdEntityID, secondEntityID])
    }

    @Test
    func clearRemovesOnlySelectedGraph() {
        let defaults = makeDefaults()
        let store = GraphCanvasFocusHistoryStore(defaults: defaults)
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let firstEntityID = UUID()
        let secondEntityID = UUID()

        store.recordFocus(graphID: firstGraphID, entityID: firstEntityID, label: "First", focusedAt: Date(timeIntervalSince1970: 100))
        store.recordFocus(graphID: secondGraphID, entityID: secondEntityID, label: "Second", focusedAt: Date(timeIntervalSince1970: 200))

        store.clear(graphID: firstGraphID)

        #expect(store.items(graphID: firstGraphID, limit: 10).isEmpty)
        #expect(store.items(graphID: secondGraphID, limit: 10).map(\.entityID) == [secondEntityID])
    }

    @Test
    func corruptStoredDataFallsBackToEmptyState() {
        let defaults = makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: BMAppStorageKeys.graphCanvasFocusHistoryV1)

        let store = GraphCanvasFocusHistoryStore(defaults: defaults)

        #expect(store.items.isEmpty)
        #expect(defaults.data(forKey: BMAppStorageKeys.graphCanvasFocusHistoryV1) == nil)
    }

    @Test
    func previousFocusSkipsCurrentEntity() {
        let defaults = makeDefaults()
        let store = GraphCanvasFocusHistoryStore(defaults: defaults)
        let graphID = UUID()
        let currentEntityID = UUID()
        let previousEntityID = UUID()

        store.recordFocus(graphID: graphID, entityID: previousEntityID, label: "Previous", focusedAt: Date(timeIntervalSince1970: 100))
        store.recordFocus(graphID: graphID, entityID: currentEntityID, label: "Current", focusedAt: Date(timeIntervalSince1970: 200))

        let previous = store.previousItem(graphID: graphID, currentEntityID: currentEntityID)
        #expect(previous?.entityID == previousEntityID)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "GraphCanvasFocusHistoryStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
