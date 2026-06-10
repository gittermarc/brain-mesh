import Foundation
import Testing
@testable import BrainMesh

struct RecentNodeStoreTests {

    @Test
    func recordOpenAddsNewItem() {
        let defaults = makeDefaults()
        let store = RecentNodeStore(defaults: defaults)
        let graphID = UUID()
        let nodeID = UUID()

        store.recordOpen(
            graphID: graphID,
            nodeKind: .entity,
            nodeID: nodeID,
            label: "Project Atlas",
            iconSymbolName: "cube",
            openedAt: Date(timeIntervalSince1970: 100)
        )

        let items = store.recentItems(graphID: graphID, limit: 10)
        #expect(items.count == 1)
        #expect(items.first?.graphID == graphID)
        #expect(items.first?.nodeKindRaw == NodeKind.entity.rawValue)
        #expect(items.first?.nodeID == nodeID)
        #expect(items.first?.label == "Project Atlas")
        #expect(items.first?.iconSymbolName == "cube")
        #expect(items.first?.nodeKey == NodeKey(kind: .entity, uuid: nodeID))
    }

    @Test
    func recordOpenDeduplicatesAndUpdatesExistingItem() {
        let defaults = makeDefaults()
        let store = RecentNodeStore(defaults: defaults)
        let graphID = UUID()
        let nodeID = UUID()

        store.recordOpen(
            graphID: graphID,
            nodeKind: .entity,
            nodeID: nodeID,
            label: "Old Name",
            iconSymbolName: "circle",
            openedAt: Date(timeIntervalSince1970: 100)
        )
        store.recordOpen(
            graphID: graphID,
            nodeKind: .entity,
            nodeID: nodeID,
            label: "New Name",
            iconSymbolName: "star",
            openedAt: Date(timeIntervalSince1970: 200)
        )

        let items = store.recentItems(graphID: graphID, limit: 10)
        #expect(items.count == 1)
        #expect(items.first?.label == "New Name")
        #expect(items.first?.iconSymbolName == "star")
        #expect(items.first?.openedAt == Date(timeIntervalSince1970: 200))
    }

    @Test
    func recentItemsAreScopedByGraph() {
        let defaults = makeDefaults()
        let store = RecentNodeStore(defaults: defaults)
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let firstNodeID = UUID()
        let secondNodeID = UUID()

        store.recordOpen(
            graphID: firstGraphID,
            nodeKind: .entity,
            nodeID: firstNodeID,
            label: "First Graph",
            iconSymbolName: nil,
            openedAt: Date(timeIntervalSince1970: 100)
        )
        store.recordOpen(
            graphID: secondGraphID,
            nodeKind: .entity,
            nodeID: secondNodeID,
            label: "Second Graph",
            iconSymbolName: nil,
            openedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(store.recentItems(graphID: firstGraphID, limit: 10).map(\.nodeID) == [firstNodeID])
        #expect(store.recentItems(graphID: secondGraphID, limit: 10).map(\.nodeID) == [secondNodeID])
    }

    @Test
    func recentItemsRespectLimit() {
        let defaults = makeDefaults()
        let store = RecentNodeStore(defaults: defaults)
        let graphID = UUID()
        let firstNodeID = UUID()
        let secondNodeID = UUID()
        let thirdNodeID = UUID()

        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: firstNodeID, label: "First", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 100))
        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: secondNodeID, label: "Second", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 200))
        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: thirdNodeID, label: "Third", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 300))

        #expect(store.recentItems(graphID: graphID, limit: 2).map(\.nodeID) == [thirdNodeID, secondNodeID])
    }

    @Test
    func maxItemsPerGraphIsEnforced() {
        let defaults = makeDefaults()
        let store = RecentNodeStore(defaults: defaults, maxItemsPerGraph: 2)
        let graphID = UUID()
        let firstNodeID = UUID()
        let secondNodeID = UUID()
        let thirdNodeID = UUID()

        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: firstNodeID, label: "First", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 100))
        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: secondNodeID, label: "Second", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 200))
        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: thirdNodeID, label: "Third", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 300))

        #expect(store.recentItems(graphID: graphID, limit: 10).map(\.nodeID) == [thirdNodeID, secondNodeID])
    }

    @Test
    func clearRemovesOnlySelectedGraph() {
        let defaults = makeDefaults()
        let store = RecentNodeStore(defaults: defaults)
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let firstNodeID = UUID()
        let secondNodeID = UUID()

        store.recordOpen(graphID: firstGraphID, nodeKind: .entity, nodeID: firstNodeID, label: "First", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 100))
        store.recordOpen(graphID: secondGraphID, nodeKind: .entity, nodeID: secondNodeID, label: "Second", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 200))

        store.clear(graphID: firstGraphID)

        #expect(store.recentItems(graphID: firstGraphID, limit: 10).isEmpty)
        #expect(store.recentItems(graphID: secondGraphID, limit: 10).map(\.nodeID) == [secondNodeID])
    }

    @Test
    func corruptStoredDataFallsBackToEmptyState() {
        let defaults = makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: BMAppStorageKeys.recentNodesV1)

        let store = RecentNodeStore(defaults: defaults)

        #expect(store.items.isEmpty)
        #expect(defaults.data(forKey: BMAppStorageKeys.recentNodesV1) == nil)
    }

    @Test
    func recentItemsCanBeFilteredByNodeKind() {
        let defaults = makeDefaults()
        let store = RecentNodeStore(defaults: defaults)
        let graphID = UUID()
        let entityID = UUID()
        let attributeID = UUID()

        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: entityID, label: "Entity", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 100))
        store.recordOpen(graphID: graphID, nodeKind: .attribute, nodeID: attributeID, label: "Attribute", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 200))

        #expect(store.recentItems(graphID: graphID, nodeKind: .entity, limit: 10).map(\.nodeID) == [entityID])
        #expect(store.recentItems(graphID: graphID, nodeKind: .attribute, limit: 10).map(\.nodeID) == [attributeID])
    }

    @Test
    func removeDeletesSingleNode() {
        let defaults = makeDefaults()
        let store = RecentNodeStore(defaults: defaults)
        let graphID = UUID()
        let firstNodeID = UUID()
        let secondNodeID = UUID()

        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: firstNodeID, label: "First", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 100))
        store.recordOpen(graphID: graphID, nodeKind: .entity, nodeID: secondNodeID, label: "Second", iconSymbolName: nil, openedAt: Date(timeIntervalSince1970: 200))
        store.remove(graphID: graphID, nodeKind: .entity, nodeID: secondNodeID)

        #expect(store.recentItems(graphID: graphID, limit: 10).map(\.nodeID) == [firstNodeID])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "RecentNodeStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
