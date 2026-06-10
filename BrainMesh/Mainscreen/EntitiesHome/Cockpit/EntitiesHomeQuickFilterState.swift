//
//  EntitiesHomeQuickFilterState.swift
//  BrainMesh
//
//  Pure quick-filter application for Entities Home Cockpit.
//

import Foundation

nonisolated enum EntitiesHomeQuickFilterEngine {
    static func effectiveFilter(selectedFilter: EntitiesHomeQuickFilter, isSearchActive: Bool) -> EntitiesHomeQuickFilter {
        isSearchActive ? .all : selectedFilter
    }

    static func filteredRows(
        _ rows: [EntitiesHomeRow],
        selectedFilter: EntitiesHomeQuickFilter,
        snapshot: EntitiesHomeCockpitSnapshot,
        isSearchActive: Bool
    ) -> [EntitiesHomeRow] {
        let filter = effectiveFilter(selectedFilter: selectedFilter, isSearchActive: isSearchActive)
        guard filter != .all else { return rows }
        guard let filterSnapshot = snapshot.quickFilterSnapshot(for: filter) else { return rows }
        guard filterSnapshot.matchingEntityIDs.isEmpty == false else { return [] }
        return rows.filter { row in
            filterSnapshot.matchingEntityIDs.contains(row.id)
        }
    }

    static func shouldShowFilterEmptyState(
        allRows: [EntitiesHomeRow],
        filteredRows: [EntitiesHomeRow],
        selectedFilter: EntitiesHomeQuickFilter,
        isSearchActive: Bool
    ) -> Bool {
        let filter = effectiveFilter(selectedFilter: selectedFilter, isSearchActive: isSearchActive)
        return filter != .all && allRows.isEmpty == false && filteredRows.isEmpty
    }
}
