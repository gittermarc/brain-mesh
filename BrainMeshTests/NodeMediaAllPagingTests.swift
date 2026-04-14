import Foundation
import Testing
@testable import BrainMesh

struct NodeMediaAllPagingTests {

    @Test
    func applyPage_appendsUniqueItems_advancesOffset_andTracksRemainingCount() {
        let existing = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), title: "Existing")
        let incoming = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 200), title: "Incoming")
        let state = NodeMediaAllPageState(
            items: [existing],
            totalCount: 3,
            offset: 0,
            isLoading: true,
            hasMore: true,
            pageSize: 12
        )

        let progress = NodeMediaAllPagePlanner.applyPage([existing, incoming], to: state)

        #expect(progress.items.map(\.id) == [existing.id, incoming.id])
        #expect(progress.offset == 2)
        #expect(progress.hasMore)
    }

    @Test
    func applyPage_marksHasMoreFalseWhenPageIsEmpty() {
        let existing = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), title: "Existing")
        let state = NodeMediaAllPageState(
            items: [existing],
            totalCount: 4,
            offset: 2,
            isLoading: true,
            hasMore: true,
            pageSize: 12
        )

        let progress = NodeMediaAllPagePlanner.applyPage([], to: state)

        #expect(progress.items.map(\.id) == [existing.id])
        #expect(progress.offset == 2)
        #expect(progress.hasMore == false)
    }

    @Test
    func applyPage_marksHasMoreFalseWhenOnlyDuplicatesArrive() {
        let existing = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), title: "Existing")
        let state = NodeMediaAllPageState(
            items: [existing],
            totalCount: 5,
            offset: 1,
            isLoading: true,
            hasMore: true,
            pageSize: 12
        )

        let progress = NodeMediaAllPagePlanner.applyPage([existing], to: state)

        #expect(progress.items.map(\.id) == [existing.id])
        #expect(progress.offset == 1)
        #expect(progress.hasMore == false)
    }

    @Test
    func applyPage_usesPageSizeFallbackWhenTotalCountIsUnknown() {
        let first = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 100), title: "First")
        let second = makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 200), title: "Second")
        let state = NodeMediaAllPageState(pageSize: 2)

        let partialProgress = NodeMediaAllPagePlanner.applyPage([first, second], to: state)
        let partialState = NodeMediaAllPageState(
            items: partialProgress.items,
            totalCount: 0,
            offset: partialProgress.offset,
            isLoading: false,
            hasMore: partialProgress.hasMore,
            pageSize: 2
        )
        let finalProgress = NodeMediaAllPagePlanner.applyPage([makeItem(id: UUID(), createdAt: Date(timeIntervalSince1970: 300), title: "Third")], to: partialState)

        #expect(partialProgress.hasMore)
        #expect(finalProgress.items.count == 3)
        #expect(finalProgress.offset == 3)
        #expect(finalProgress.hasMore == false)
    }

    private func makeItem(id: UUID, createdAt: Date, title: String) -> AttachmentListItem {
        AttachmentListItem(
            id: id,
            createdAt: createdAt,
            graphID: UUID(),
            ownerKindRaw: NodeKind.entity.rawValue,
            ownerID: UUID(),
            contentKindRaw: AttachmentContentKind.file.rawValue,
            title: title,
            originalFilename: "\(title).dat",
            contentTypeIdentifier: "public.data",
            fileExtension: "dat",
            byteCount: 1,
            localPath: nil
        )
    }
}
