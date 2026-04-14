import Foundation

struct PhotoGallerySelectionState: Equatable {
    private(set) var attachmentIDs: [UUID]
    private(set) var selectionID: UUID?

    init(attachmentIDs: [UUID] = [], startSelectionID: UUID? = nil) {
        self.attachmentIDs = attachmentIDs
        self.selectionID = Self.resolveSelection(
            availableIDs: attachmentIDs,
            preferredSelectionID: startSelectionID
        )
    }

    var selectedAttachmentID: UUID? {
        guard let selectionID, attachmentIDs.contains(selectionID) else { return nil }
        return selectionID
    }

    var selectedIndex: Int? {
        guard let selectedAttachmentID else { return nil }
        return attachmentIDs.firstIndex(of: selectedAttachmentID)
    }

    var indexLabel: String? {
        guard let selectedIndex else { return nil }
        return "\(selectedIndex + 1)/\(attachmentIDs.count)"
    }

    mutating func select(_ attachmentID: UUID) {
        guard attachmentIDs.contains(attachmentID) else { return }
        selectionID = attachmentID
    }

    mutating func syncAttachmentIDs(_ newAttachmentIDs: [UUID]) {
        attachmentIDs = newAttachmentIDs
        selectionID = Self.resolveSelection(
            availableIDs: newAttachmentIDs,
            preferredSelectionID: selectionID
        )
    }

    func nextSelectionAfterDeletingCurrent() -> UUID? {
        guard let selectedIndex else {
            return attachmentIDs.first
        }

        let remainingIDs = attachmentIDs.filter { $0 != selectionID }
        guard !remainingIDs.isEmpty else { return nil }

        let nextIndex = min(selectedIndex, remainingIDs.count - 1)
        return remainingIDs[nextIndex]
    }

    private static func resolveSelection(
        availableIDs: [UUID],
        preferredSelectionID: UUID?
    ) -> UUID? {
        guard !availableIDs.isEmpty else { return nil }

        if let preferredSelectionID, availableIDs.contains(preferredSelectionID) {
            return preferredSelectionID
        }

        return availableIDs.first
    }
}

struct PhotoGalleryBrowserPresentationState: Equatable {
    var viewerRequest: PhotoGalleryViewerRequest? = nil
    var confirmDeleteAttachmentID: UUID? = nil
    var errorMessage: String? = nil

    mutating func openViewer(startAttachmentID: UUID) {
        viewerRequest = PhotoGalleryViewerRequest(startAttachmentID: startAttachmentID)
    }

    mutating func clearViewerRequest() {
        viewerRequest = nil
    }

    mutating func requestDelete(attachmentID: UUID) {
        confirmDeleteAttachmentID = attachmentID
    }

    mutating func clearDeleteRequest() {
        confirmDeleteAttachmentID = nil
    }

    mutating func showError(_ message: String) {
        errorMessage = message
    }

    mutating func clearError() {
        errorMessage = nil
    }
}

struct PhotoGalleryViewerPresentationState: Equatable {
    var showActions: Bool = false
    var confirmDelete: Bool = false
    var errorMessage: String? = nil

    mutating func showError(_ message: String) {
        errorMessage = message
    }

    mutating func clearError() {
        errorMessage = nil
    }
}
