import Foundation
import Testing
@testable import BrainMesh

struct GraphCanvasViewPresetStoreTests {

    @Test
    func saveAddsPreset() {
        let defaults = makeDefaults()
        let store = GraphCanvasViewPresetStore(defaults: defaults)
        let graphID = UUID()
        let preset = makePreset(graphID: graphID, name: "Global", updatedAt: Date(timeIntervalSince1970: 100))

        store.save(preset)

        let presets = store.presets(graphID: graphID, limit: 10)
        #expect(presets.count == 1)
        #expect(presets.first?.id == preset.id)
        #expect(presets.first?.name == "Global")
    }

    @Test
    func saveUpdatesPresetWithSameID() {
        let defaults = makeDefaults()
        let store = GraphCanvasViewPresetStore(defaults: defaults)
        let graphID = UUID()
        let presetID = UUID()

        store.save(makePreset(id: presetID, graphID: graphID, name: "Old", updatedAt: Date(timeIntervalSince1970: 100)))
        store.save(makePreset(id: presetID, graphID: graphID, name: "Updated", updatedAt: Date(timeIntervalSince1970: 200)))

        let presets = store.presets(graphID: graphID, limit: 10)
        #expect(presets.count == 1)
        #expect(presets.first?.name == "Updated")
        #expect(presets.first?.updatedAt == Date(timeIntervalSince1970: 200))
    }

    @Test
    func presetsAreScopedByGraph() {
        let defaults = makeDefaults()
        let store = GraphCanvasViewPresetStore(defaults: defaults)
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let firstPresetID = UUID()
        let secondPresetID = UUID()

        store.save(makePreset(id: firstPresetID, graphID: firstGraphID, name: "First", updatedAt: Date(timeIntervalSince1970: 100)))
        store.save(makePreset(id: secondPresetID, graphID: secondGraphID, name: "Second", updatedAt: Date(timeIntervalSince1970: 200)))

        #expect(store.presets(graphID: firstGraphID, limit: 10).map(\.id) == [firstPresetID])
        #expect(store.presets(graphID: secondGraphID, limit: 10).map(\.id) == [secondPresetID])
    }

    @Test
    func limitPerGraphIsEnforced() {
        let defaults = makeDefaults()
        let store = GraphCanvasViewPresetStore(defaults: defaults, maxPresetsPerGraph: 2)
        let graphID = UUID()
        let firstPresetID = UUID()
        let secondPresetID = UUID()
        let thirdPresetID = UUID()

        store.save(makePreset(id: firstPresetID, graphID: graphID, name: "First", updatedAt: Date(timeIntervalSince1970: 100)))
        store.save(makePreset(id: secondPresetID, graphID: graphID, name: "Second", updatedAt: Date(timeIntervalSince1970: 200)))
        store.save(makePreset(id: thirdPresetID, graphID: graphID, name: "Third", updatedAt: Date(timeIntervalSince1970: 300)))

        #expect(store.presets(graphID: graphID, limit: 10).map(\.id) == [thirdPresetID, secondPresetID])
    }

    @Test
    func deleteRemovesOnlySelectedPreset() {
        let defaults = makeDefaults()
        let store = GraphCanvasViewPresetStore(defaults: defaults)
        let firstGraphID = UUID()
        let secondGraphID = UUID()
        let firstPresetID = UUID()
        let secondPresetID = UUID()

        store.save(makePreset(id: firstPresetID, graphID: firstGraphID, name: "First", updatedAt: Date(timeIntervalSince1970: 100)))
        store.save(makePreset(id: secondPresetID, graphID: secondGraphID, name: "Second", updatedAt: Date(timeIntervalSince1970: 200)))

        store.remove(id: firstPresetID, graphID: firstGraphID)

        #expect(store.presets(graphID: firstGraphID, limit: 10).isEmpty)
        #expect(store.presets(graphID: secondGraphID, limit: 10).map(\.id) == [secondPresetID])
    }

    @Test
    func corruptStoredDataFallsBackToEmptyState() {
        let defaults = makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: BMAppStorageKeys.graphCanvasViewPresetsV1)

        let store = GraphCanvasViewPresetStore(defaults: defaults)

        #expect(store.presets.isEmpty)
        #expect(defaults.data(forKey: BMAppStorageKeys.graphCanvasViewPresetsV1) == nil)
    }

    @Test
    func legacyCodableMissingFieldsUseFallbacks() throws {
        let defaults = makeDefaults()
        let graphID = UUID()
        let presetID = UUID()
        let legacyPreset = LegacyPreset(
            id: presetID,
            graphID: graphID,
            name: "Legacy",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let data = try JSONEncoder().encode([legacyPreset])
        defaults.set(data, forKey: BMAppStorageKeys.graphCanvasViewPresetsV1)

        let store = GraphCanvasViewPresetStore(defaults: defaults)
        let preset = try #require(store.presets(graphID: graphID, limit: 10).first)

        #expect(preset.id == presetID)
        #expect(preset.name == "Legacy")
        #expect(preset.focusEntityID == nil)
        #expect(preset.selectedNodeKey == nil)
        #expect(preset.hops == 1)
        #expect(preset.showAttributes == true)
        #expect(preset.workMode == .explore)
        #expect(preset.lensEnabled == true)
        #expect(preset.lensHideNonRelevant == false)
        #expect(preset.lensDepth == 2)
        #expect(preset.maxNodes == 140)
        #expect(preset.maxLinks == 800)
        #expect(preset.scale == 1.0)
        #expect(preset.panWidth == 0)
        #expect(preset.panHeight == 0)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "GraphCanvasViewPresetStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makePreset(
        id: UUID = UUID(),
        graphID: UUID,
        name: String,
        updatedAt: Date
    ) -> GraphCanvasViewPreset {
        GraphCanvasViewPreset(
            id: id,
            graphID: graphID,
            name: name,
            createdAt: Date(timeIntervalSince1970: 50),
            updatedAt: updatedAt,
            focusEntityID: nil,
            focusLabel: nil,
            selectedNodeKindRaw: nil,
            selectedNodeID: nil,
            hops: 1,
            showAttributes: true,
            workModeRaw: WorkMode.explore.rawValue,
            lensEnabled: true,
            lensHideNonRelevant: false,
            lensDepth: 2,
            maxNodes: 140,
            maxLinks: 800,
            collisionStrength: 0.030,
            scale: 1.0,
            panWidth: 0,
            panHeight: 0
        )
    }
}

private struct LegacyPreset: Encodable {
    let id: UUID
    let graphID: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
}
