//
//  GraphCanvasViewPresetStore.swift
//  BrainMesh
//
//  UserDefaults-backed local saved views for GraphCanvas.
//

import Combine
import Foundation

final class GraphCanvasViewPresetStore: ObservableObject {
    static let defaultMaxPresetsPerGraph = 20

    @Published private(set) var presets: [GraphCanvasViewPreset]

    private let defaults: UserDefaults
    private let storageKey: String
    private let maxPresetsPerGraph: Int
    private let encoder = JSONEncoder()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = BMAppStorageKeys.graphCanvasViewPresetsV1,
        maxPresetsPerGraph: Int = GraphCanvasViewPresetStore.defaultMaxPresetsPerGraph
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.maxPresetsPerGraph = max(1, maxPresetsPerGraph)
        self.presets = GraphCanvasViewPresetStore.loadPresets(
            defaults: defaults,
            storageKey: storageKey,
            maxPresetsPerGraph: self.maxPresetsPerGraph
        )
    }

    func save(_ preset: GraphCanvasViewPreset) {
        presets.removeAll { $0.id == preset.id }
        presets.insert(preset, at: 0)
        presets = GraphCanvasViewPresetStore.prunedAndSorted(
            presets,
            maxPresetsPerGraph: maxPresetsPerGraph
        )
        persist()
    }

    func presets(
        graphID: UUID,
        limit: Int = GraphCanvasViewPresetStore.defaultMaxPresetsPerGraph
    ) -> [GraphCanvasViewPreset] {
        let safeLimit = max(0, limit)
        guard safeLimit > 0 else { return [] }

        return presets
            .filter { $0.graphID == graphID }
            .sorted(by: GraphCanvasViewPresetStore.sortPresets)
            .prefix(safeLimit)
            .map { $0 }
    }

    func remove(id: UUID, graphID: UUID) {
        presets = presets.filter { $0.id != id || $0.graphID != graphID }
        persist()
    }

    func clear(graphID: UUID) {
        presets = presets.filter { $0.graphID != graphID }
        persist()
    }

    private func persist() {
        do {
            let data = try encoder.encode(presets)
            defaults.set(data, forKey: storageKey)
        } catch {
            defaults.removeObject(forKey: storageKey)
        }
    }

    nonisolated private static func loadPresets(
        defaults: UserDefaults,
        storageKey: String,
        maxPresetsPerGraph: Int
    ) -> [GraphCanvasViewPreset] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }

        do {
            let decoded = try JSONDecoder().decode([GraphCanvasViewPreset].self, from: data)
            return prunedAndSorted(decoded, maxPresetsPerGraph: maxPresetsPerGraph)
        } catch {
            defaults.removeObject(forKey: storageKey)
            return []
        }
    }

    nonisolated static func prunedAndSorted(
        _ source: [GraphCanvasViewPreset],
        maxPresetsPerGraph: Int
    ) -> [GraphCanvasViewPreset] {
        var deduped: [UUID: GraphCanvasViewPreset] = [:]
        for preset in source {
            let existing = deduped[preset.id]
            if existing == nil || sortPresets(preset, existing!) {
                deduped[preset.id] = preset
            }
        }

        let sorted = deduped.values.sorted(by: sortPresets)
        var countsByGraph: [UUID: Int] = [:]
        var output: [GraphCanvasViewPreset] = []
        output.reserveCapacity(sorted.count)

        for preset in sorted {
            let count = countsByGraph[preset.graphID, default: 0]
            guard count < maxPresetsPerGraph else { continue }
            countsByGraph[preset.graphID] = count + 1
            output.append(preset)
        }

        return output
    }

    nonisolated static func sortPresets(
        _ lhs: GraphCanvasViewPreset,
        _ rhs: GraphCanvasViewPreset
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        let lhsName = BMSearch.fold(lhs.name)
        let rhsName = BMSearch.fold(rhs.name)
        if lhsName != rhsName {
            return lhsName < rhsName
        }

        if lhs.graphID != rhs.graphID {
            return lhs.graphID.uuidString < rhs.graphID.uuidString
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
