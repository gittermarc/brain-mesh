import SwiftUI
import SwiftData
import Foundation

extension DetailsValueEditorSheet {
    @MainActor
    func warmUpCompletionIndexIfNeeded() {
        guard field.type == .singleLineText || field.type == .multiLineText else { return }
        guard didWarmUpCompletionIndex == false else { return }
        guard let gid = resolvedGraphID else { return }

        didWarmUpCompletionIndex = true

        Task { @MainActor in
            await DetailsCompletionIndex.shared.ensureLoaded(graphID: gid, fieldID: field.id, in: modelContext)
            refreshTopCompletionIfPossible()
            refreshMultiLineSuggestionsIfPossible()
        }
    }

    @MainActor
    func refreshTopCompletionIfPossible() {
        guard field.type == .singleLineText else {
            topCompletion = nil
            return
        }

        // Only show completions while actively editing the field.
        guard isSingleLineTextFocused else {
            topCompletion = nil
            return
        }

        guard let gid = resolvedGraphID else {
            topCompletion = nil
            return
        }

        // If the user typed a trailing whitespace, stop suggesting.
        if let last = stringInput.last, last.isWhitespace {
            topCompletion = nil
            return
        }

        let current = stringInput

        completionTask?.cancel()
        completionTask = Task {
            let suggestion = await DetailsCompletionIndex.shared.topSuggestion(graphID: gid, fieldID: field.id, prefix: current)
            if Task.isCancelled { return }
            await MainActor.run {
                self.topCompletion = suggestion
            }
        }
    }

    @MainActor
    func refreshMultiLineSuggestionsIfPossible() {
        guard field.type == .multiLineText else {
            multiLineSuggestions = []
            return
        }

        guard isMultiLineTextFocused else {
            multiLineSuggestions = []
            return
        }

        guard let gid = resolvedGraphID else {
            multiLineSuggestions = []
            return
        }

        guard let token = lastTokenAtTextEnd(in: stringInput) else {
            multiLineSuggestions = []
            return
        }

        multiLineTask?.cancel()
        multiLineTask = Task {
            let list = await DetailsCompletionIndex.shared.suggestions(
                graphID: gid,
                fieldID: field.id,
                prefix: token,
                limit: 3
            )
            if Task.isCancelled { return }
            await MainActor.run {
                self.multiLineSuggestions = list
            }
        }
    }

    @MainActor
    func acceptTopCompletionIfPossible() {
        guard field.type == .singleLineText else { return }
        guard isSingleLineTextFocused else { return }
        guard let suggestion = topCompletion else { return }

        // Workaround for occasional SwiftUI TextField state races while editing:
        // apply on the next runloop tick so the active editing session doesn't overwrite us.
        let accepted = suggestion.text

        completionTask?.cancel()
        completionTask = nil
        topCompletion = nil

        DispatchQueue.main.async {
            self.stringInput = accepted
            self.isSingleLineTextFocused = true
            self.refreshTopCompletionIfPossible()
        }
    }

    @MainActor
    func applyMultiLineSuggestion(_ suggestion: DetailsCompletionSuggestion) {
        guard field.type == .multiLineText else { return }

        // Replace only the last token at the text end (after whitespace/newline separation).
        if let range = lastTokenRangeAtTextEnd(in: stringInput) {
            stringInput.replaceSubrange(range, with: suggestion.text)
        } else {
            // If empty, insert the suggestion.
            if stringInput.isEmpty {
                stringInput = suggestion.text
            } else {
                // If the user ended with whitespace, don't guess. Append directly.
                stringInput += suggestion.text
            }
        }

        refreshMultiLineSuggestionsIfPossible()
    }

    private func lastTokenAtTextEnd(in text: String) -> String? {
        guard let range = lastTokenRangeAtTextEnd(in: text) else { return nil }
        let token = String(text[range])
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : token
    }

    private func lastTokenRangeAtTextEnd(in text: String) -> Range<String.Index>? {
        if text.isEmpty { return nil }
        guard let last = text.last, !(last.isWhitespace || last.isNewline) else { return nil }

        // Find the last separator (whitespace/newline). The token starts right after it.
        if let sep = text.lastIndex(where: { $0.isWhitespace || $0.isNewline }) {
            let start = text.index(after: sep)
            if start >= text.endIndex { return nil }
            return start..<text.endIndex
        }
        return text.startIndex..<text.endIndex
    }
}
