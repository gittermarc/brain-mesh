//
//  DetailsCompletionGhostOverlay.swift
//  BrainMesh
//
//  UI helpers for inline ("ghost") completion.
//

import SwiftUI

/// Renders a "ghost" completion behind a text input by drawing the full suggestion
/// where the already-typed prefix is invisible and only the remaining suffix is visible.
///
/// Notes:
/// - This is intentionally lightweight and purely visual (no state, no fetching).
/// - The visual match check is fold-based (case/diacritic-insensitive) via `BMSearch.fold`.
/// - The prefix that is hidden is based on the current text length, which is good enough
///   as long as suggestions come from a prefix match source (DetailsCompletionIndex).
struct DetailsCompletionGhostText: View {
    let currentText: String
    let suggestionText: String

    var body: some View {
        if let parts = Self.makeParts(currentText: currentText, suggestionText: suggestionText) {
            // Keep layout stable by reserving the prefix width, but hide it visually.
            (Text(parts.hiddenPrefix).foregroundStyle(.clear) + Text(parts.visibleSuffix).foregroundStyle(.tertiary))
                .lineLimit(1)
                .allowsHitTesting(false)
        }
    }

    private struct Parts {
        let hiddenPrefix: String
        let visibleSuffix: String
    }

    private static func makeParts(currentText: String, suggestionText: String) -> Parts? {
        let rawCurrent = currentText
        let rawSuggestion = suggestionText

        if rawCurrent.isEmpty { return nil }
        if rawSuggestion.isEmpty { return nil }

        // Trailing whitespace tends to make ghost completions confusing and can
        // visually misalign (space vs. letter widths). Keep it simple: no ghost.
        if let last = rawCurrent.last, last.isWhitespace { return nil }

        let foldedCurrent = BMSearch.fold(rawCurrent)
        let foldedSuggestion = BMSearch.fold(rawSuggestion)

        guard !foldedCurrent.isEmpty else { return nil }
        guard foldedSuggestion.hasPrefix(foldedCurrent) else { return nil }
        guard foldedSuggestion != foldedCurrent else { return nil }

        let prefixCount = min(rawCurrent.count, rawSuggestion.count)
        let hiddenPrefix = String(rawSuggestion.prefix(prefixCount))
        let visibleSuffix = String(rawSuggestion.dropFirst(prefixCount))

        if visibleSuffix.isEmpty { return nil }
        return Parts(hiddenPrefix: hiddenPrefix, visibleSuffix: visibleSuffix)
    }
}

private struct DetailsCompletionGhostOverlayModifier: ViewModifier {
    let currentText: String
    let suggestionText: String?
    let inset: EdgeInsets

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                if let suggestionText {
                    DetailsCompletionGhostText(currentText: currentText, suggestionText: suggestionText)
                        .padding(inset)
                }
            }
    }
}

extension View {
    /// Adds a subtle inline ghost completion overlay to a text input.
    ///
    /// Typical usage:
    /// `TextField("Text", text: $text).detailsCompletionGhost(currentText: text, suggestionText: suggestion?.text)`
    func detailsCompletionGhost(
        currentText: String,
        suggestionText: String?,
        inset: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    ) -> some View {
        modifier(DetailsCompletionGhostOverlayModifier(currentText: currentText, suggestionText: suggestionText, inset: inset))
    }
}

#Preview {
    struct Demo: View {
        @State private var text: String = "Mün"

        var body: some View {
            Form {
                Section {
                    TextField("Text", text: $text)
                        .detailsCompletionGhost(currentText: text, suggestionText: "München", inset: .init(top: 0, leading: 2, bottom: 0, trailing: 0))
                } header: {
                    Text("Ghost Overlay")
                }
            }
        }
    }

    return Demo()
}
