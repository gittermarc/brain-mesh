import Foundation
import Testing
@testable import BrainMesh

struct EntitiesHomeQuickFilterTests {

    @Test
    func filterKeepsExistingRowOrder() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let rows = [
            makeRow(id: first, name: "Beta"),
            makeRow(id: second, name: "Alpha"),
            makeRow(id: third, name: "Gamma")
        ]
        let snapshot = makeSnapshot(filter: .isolatedEntities, ids: [third, first])

        let filtered = EntitiesHomeQuickFilterEngine.filteredRows(
            rows,
            selectedFilter: .isolatedEntities,
            snapshot: snapshot,
            isSearchActive: false
        )

        #expect(filtered.map(\.id) == [first, third])
    }

    @Test
    func allFilterReturnsAllRows() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let rows = [makeRow(id: first, name: "First"), makeRow(id: second, name: "Second")]
        let snapshot = makeSnapshot(filter: .mediaRich, ids: [second])

        let filtered = EntitiesHomeQuickFilterEngine.filteredRows(
            rows,
            selectedFilter: .all,
            snapshot: snapshot,
            isSearchActive: false
        )

        #expect(filtered.map(\.id) == [first, second])
    }

    @Test
    func searchActiveIgnoresSelectedQuickFilter() {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
        let rows = [makeRow(id: first, name: "First"), makeRow(id: second, name: "Second")]
        let snapshot = makeSnapshot(filter: .mediaRich, ids: [second])

        let filtered = EntitiesHomeQuickFilterEngine.filteredRows(
            rows,
            selectedFilter: .mediaRich,
            snapshot: snapshot,
            isSearchActive: true
        )

        #expect(filtered.map(\.id) == [first, second])
        #expect(EntitiesHomeQuickFilterEngine.effectiveFilter(selectedFilter: .mediaRich, isSearchActive: true) == .all)
    }

    @Test
    func emptyStateOnlyAppearsForActiveNonAllFilter() {
        let row = makeRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!, name: "Only")

        #expect(EntitiesHomeQuickFilterEngine.shouldShowFilterEmptyState(
            allRows: [row],
            filteredRows: [],
            selectedFilter: .mediaRich,
            isSearchActive: false
        ))

        #expect(EntitiesHomeQuickFilterEngine.shouldShowFilterEmptyState(
            allRows: [row],
            filteredRows: [],
            selectedFilter: .all,
            isSearchActive: false
        ) == false)

        #expect(EntitiesHomeQuickFilterEngine.shouldShowFilterEmptyState(
            allRows: [row],
            filteredRows: [],
            selectedFilter: .mediaRich,
            isSearchActive: true
        ) == false)
    }

    private func makeSnapshot(filter: EntitiesHomeQuickFilter, ids: Set<UUID>) -> EntitiesHomeCockpitSnapshot {
        EntitiesHomeCockpitSnapshot(
            graphID: UUID(uuidString: "00000000-0000-0000-0000-000000000999")!,
            recentNodes: [],
            healthSummary: .empty,
            quickFilters: EntitiesHomeQuickFilter.allCases.map { item in
                if item == filter {
                    return EntitiesHomeQuickFilterSnapshot(filter: item, matchingEntityIDs: ids, count: ids.count)
                }
                return EntitiesHomeQuickFilterSnapshot(filter: item, matchingEntityIDs: [], count: 0)
            }
        )
    }

    private func makeRow(id: UUID, name: String) -> EntitiesHomeRow {
        EntitiesHomeRow(
            id: id,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            iconSymbolName: "cube",
            attributeCount: 0,
            linkCount: nil,
            notesPreview: nil,
            isNotesOnlyHit: false,
            imagePath: nil,
            hasImageData: false
        )
    }
}
