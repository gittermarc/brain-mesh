//
//  GraphChatMessageActionDependencies.swift
//  BrainMesh
//
//  System adapters and session-local stores used by centralized message actions.
//

import Foundation
import UIKit

@MainActor
protocol GraphChatClipboardWriting {
    func write(_ text: String)
}

@MainActor
struct SystemGraphChatClipboardWriter: GraphChatClipboardWriting {
    func write(_ text: String) {
        UIPasteboard.general.string = text
    }
}

@MainActor
protocol GraphChatAccessibilityAnnouncing {
    func announce(_ message: String)
}

@MainActor
struct SystemGraphChatAccessibilityAnnouncer: GraphChatAccessibilityAnnouncing {
    func announce(_ message: String) {
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }
}

nonisolated protocol GraphChatFeedbackStoring: Sendable {
    func records(for scope: GraphChatScope) async -> [GraphChatFeedbackRecord]
    func save(
        _ record: GraphChatFeedbackRecord,
        for scope: GraphChatScope
    ) async
    func remove(
        messageID: UUID,
        for scope: GraphChatScope
    ) async
    func remove(
        messageIDs: [UUID],
        for scope: GraphChatScope
    ) async
    func removeAll(for scope: GraphChatScope) async
}

actor InMemoryGraphChatFeedbackStore: GraphChatFeedbackStoring {
    private var recordsByScope: [GraphChatScope: [UUID: GraphChatFeedbackRecord]] = [:]

    func records(for scope: GraphChatScope) -> [GraphChatFeedbackRecord] {
        recordsByScope[scope, default: [:]]
            .values
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.localMessageID.uuidString < rhs.localMessageID.uuidString
            }
    }

    func save(
        _ record: GraphChatFeedbackRecord,
        for scope: GraphChatScope
    ) {
        recordsByScope[scope, default: [:]][record.localMessageID] = record
    }

    func remove(
        messageID: UUID,
        for scope: GraphChatScope
    ) {
        recordsByScope[scope]?[messageID] = nil
        removeEmptyScope(scope)
    }

    func remove(
        messageIDs: [UUID],
        for scope: GraphChatScope
    ) {
        guard recordsByScope[scope] != nil else {
            return
        }
        for messageID in messageIDs {
            recordsByScope[scope]?[messageID] = nil
        }
        removeEmptyScope(scope)
    }

    func removeAll(for scope: GraphChatScope) {
        recordsByScope.removeValue(forKey: scope)
    }

    private func removeEmptyScope(_ scope: GraphChatScope) {
        if recordsByScope[scope]?.isEmpty == true {
            recordsByScope.removeValue(forKey: scope)
        }
    }
}
