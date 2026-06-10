import Foundation
import Testing
@testable import BrainMesh

struct CommandCenterStateTests {

    @Test
    func emptyQueryShowsRecentsAndQuickActions() {
        let graphID = UUID()
        let recent = RecentNodeItem(
            graphID: graphID,
            nodeKindRaw: NodeKind.entity.rawValue,
            nodeID: UUID(),
            label: "Atlas",
            iconSymbolName: "cube",
            openedAt: Date(timeIntervalSince1970: 10)
        )

        let state = CommandCenterStateBuilder.state(
            query: "",
            snapshot: .empty,
            recents: [recent],
            isSearching: false,
            error: nil
        )

        #expect(state == .overview(recents: [recent], quickActions: CommandCenterQuickAction.allCases))
    }

    @Test
    func nonEmptyQueryGroupsSearchResults() {
        let entity = makeResult(kind: .entity, title: "Atlas", id: UUID())
        let detail = makeResult(kind: .detail, title: "Status: Gold", id: UUID())
        let attachment = makeResult(kind: .attachment, title: "Blueprint", id: UUID())
        let snapshot = BrainMeshSearchSnapshot(query: "a", results: [attachment, detail, entity])

        let state = CommandCenterStateBuilder.state(
            query: "a",
            snapshot: snapshot,
            recents: [],
            isSearching: false,
            error: nil
        )

        guard case .results(_, let sections) = state else {
            Issue.record("Expected results state")
            return
        }

        #expect(sections.map(\.kind) == [.entity, .detail, .attachment])
        #expect(sections.flatMap(\.results).map(\.id) == [entity.id, detail.id, attachment.id])
    }

    @Test
    func nonEmptyQueryWithoutResultsShowsNoResults() {
        let state = CommandCenterStateBuilder.state(
            query: "missing",
            snapshot: .empty,
            recents: [],
            isSearching: false,
            error: nil
        )

        #expect(state == .noResults(query: "missing"))
    }

    @Test
    func searchingStateAppearsWhenSearchIsRunningAndNoSnapshotExists() {
        let state = CommandCenterStateBuilder.state(
            query: "atlas",
            snapshot: .empty,
            recents: [],
            isSearching: true,
            error: nil
        )

        #expect(state == .searching)
    }

    @Test
    func userFacingErrorStateWinsOverSearchResults() {
        let message = CommandCenterUserFacingErrorMessage(title: "Fehler", message: "Bitte erneut versuchen.")
        let state = CommandCenterStateBuilder.state(
            query: "atlas",
            snapshot: BrainMeshSearchSnapshot(query: "atlas", results: [makeResult(kind: .entity, title: "Atlas", id: UUID())]),
            recents: [],
            isSearching: false,
            error: message
        )

        #expect(state == .error(message))
    }

    @Test
    func cancellationErrorDoesNotMapToUserFacingError() {
        let message = CommandCenterUserFacingErrorMessage.message(for: CancellationError())

        #expect(message == nil)
    }

    @Test
    func unknownErrorMapsToUserFacingSearchFailure() {
        let error = NSError(domain: "Test", code: 7)
        let message = CommandCenterUserFacingErrorMessage.message(for: error)

        #expect(message?.title == "Suche fehlgeschlagen")
        #expect(message?.message.isEmpty == false)
    }

    private func makeResult(kind: BrainMeshSearchResultKind, title: String, id: UUID) -> BrainMeshSearchResult {
        BrainMeshSearchResult(
            kind: kind,
            id: id,
            graphID: UUID(),
            title: title,
            subtitle: kind.title,
            iconSymbolName: kind.defaultIconSymbolName,
            matchReason: "Name",
            nodeKindRaw: kind == .entity ? NodeKind.entity.rawValue : nil,
            nodeID: kind == .entity ? id : nil,
            ownerKindRaw: nil,
            ownerID: nil
        )
    }
}
