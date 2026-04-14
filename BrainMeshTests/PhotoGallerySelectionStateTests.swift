import Foundation
import Testing
@testable import BrainMesh

struct PhotoGallerySelectionStateTests {

    @Test
    func init_prefersRequestedStartSelectionWhenPresent() {
        let first = UUID()
        let second = UUID()

        let state = PhotoGallerySelectionState(
            attachmentIDs: [first, second],
            startSelectionID: second
        )

        #expect(state.selectedAttachmentID == second)
        #expect(state.selectedIndex == 1)
        #expect(state.indexLabel == "2/2")
    }

    @Test
    func init_fallsBackToFirstAttachmentWhenRequestedSelectionIsMissing() {
        let first = UUID()
        let second = UUID()

        let state = PhotoGallerySelectionState(
            attachmentIDs: [first, second],
            startSelectionID: UUID()
        )

        #expect(state.selectedAttachmentID == first)
        #expect(state.indexLabel == "1/2")
    }

    @Test
    func syncAttachmentIDs_preservesCurrentSelectionWhenStillAvailable() {
        let first = UUID()
        let second = UUID()
        var state = PhotoGallerySelectionState(
            attachmentIDs: [first, second],
            startSelectionID: second
        )

        state.syncAttachmentIDs([UUID(), second, UUID()])

        #expect(state.selectedAttachmentID == second)
        #expect(state.selectedIndex == 1)
        #expect(state.indexLabel == "2/3")
    }

    @Test
    func nextSelectionAfterDeletingCurrent_prefersItemAtSameVisualPosition() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var state = PhotoGallerySelectionState(
            attachmentIDs: [first, second, third],
            startSelectionID: second
        )

        #expect(state.nextSelectionAfterDeletingCurrent() == third)

        state.select(third)
        #expect(state.nextSelectionAfterDeletingCurrent() == second)
    }

    @Test
    func nextSelectionAfterDeletingCurrent_returnsNilWhenGalleryBecomesEmpty() {
        let only = UUID()
        let state = PhotoGallerySelectionState(
            attachmentIDs: [only],
            startSelectionID: only
        )

        #expect(state.nextSelectionAfterDeletingCurrent() == nil)
    }
}
