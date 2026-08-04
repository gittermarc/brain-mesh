//
//  GraphChatComposerController.swift
//  BrainMesh
//
//  Small local Observation owner for keyboard-driven draft changes.
//

import Foundation
import Observation

@MainActor
@Observable
final class GraphChatComposerController {
    private(set) var text: String

    private let checkpointHandler: @MainActor (String) -> Void
    @ObservationIgnored
    private var lastCheckpointedText: String
    @ObservationIgnored
    private var acceptsUpdates = true

    init(
        initialText: String = "",
        checkpointHandler: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        let bounded = Self.bounded(initialText)
        text = bounded
        lastCheckpointedText = bounded
        self.checkpointHandler = checkpointHandler
    }

    var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSubmissionText: Bool {
        normalizedText.isEmpty == false
    }

    func submissionText() -> String? {
        let normalized = normalizedText
        return normalized.isEmpty ? nil : normalized
    }

    /// Keyboard input remains local to this Observation owner.
    func updateFromUser(_ value: String) {
        guard acceptsUpdates else {
            return
        }
        let bounded = Self.bounded(value)
        guard text != bounded else {
            return
        }
        text = bounded
    }

    /// Programmatic prompts are semantic events and may be checkpointed
    /// immediately without routing every subsequent keystroke globally.
    func replaceText(
        _ value: String,
        checkpoint: Bool
    ) {
        guard acceptsUpdates else {
            return
        }
        let bounded = Self.bounded(value)
        if text != bounded {
            text = bounded
        }
        if checkpoint {
            checkpointLatest()
        }
    }

    func checkpointLatest() {
        guard acceptsUpdates,
              lastCheckpointedText != text else {
            return
        }
        lastCheckpointedText = text
        checkpointHandler(text)
    }

    /// Discarding deactivates the old owner so a late SwiftUI onDisappear
    /// cannot restore stale text into a changed graph or scope.
    func deactivate(preserveDraft: Bool) {
        guard acceptsUpdates else {
            return
        }
        if preserveDraft {
            checkpointLatest()
        } else {
            replaceText("", checkpoint: true)
        }
        acceptsUpdates = false
        if text.isEmpty == false {
            text = ""
        }
    }

    private nonisolated static func bounded(
        _ value: String
    ) -> String {
        String(
            value.prefix(
                GraphChatIntentLimitPolicy
                    .default.maximumQuestionLength
            )
        )
    }
}
