//
//  AttributeLinksPreviewLoadTriggerPolicy.swift
//  BrainMesh
//
//  Value-only lifecycle policy for Attribute Detail link-preview reloads.
//

import Foundation

nonisolated struct AttributeLinksPreviewLoadTaskKey: Hashable, Sendable {
    let attributeID: UUID
    let graphID: UUID?
}

nonisolated struct AttributeLinksPreviewLoadTriggerPolicy: Equatable, Sendable {
    private(set) var loadedTaskKey: AttributeLinksPreviewLoadTaskKey?
    private(set) var isAddLinkPresented: Bool = false
    private(set) var isBulkLinkPresented: Bool = false

    mutating func registerTaskKey(
        _ taskKey: AttributeLinksPreviewLoadTaskKey
    ) -> Bool {
        guard loadedTaskKey != taskKey else { return false }
        loadedTaskKey = taskKey
        return true
    }

    mutating func resetTaskLifecycle() {
        loadedTaskKey = nil
    }

    mutating func registerAddLinkPresentation(_ isPresented: Bool) -> Bool {
        let shouldReload = isAddLinkPresented && !isPresented
        isAddLinkPresented = isPresented
        return shouldReload
    }

    mutating func registerBulkLinkPresentation(_ isPresented: Bool) -> Bool {
        let shouldReload = isBulkLinkPresented && !isPresented
        isBulkLinkPresented = isPresented
        return shouldReload
    }
}
