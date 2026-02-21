//
//  DetailsCompletionSuggestionsChipsBar.swift
//  BrainMesh
//
//  Lightweight suggestion chips for details completion.
//

import SwiftUI

struct DetailsCompletionSuggestionsChipsBar: View {
    let suggestions: [DetailsCompletionSuggestion]
    var maxVisible: Int = 3
    var showsCounts: Bool = false
    var onSelect: (DetailsCompletionSuggestion) -> Void

    var body: some View {
        let visible = Array(suggestions.prefix(max(0, maxVisible)))
        if !visible.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visible) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.text)
                                    .lineLimit(1)

                                if showsCounts {
                                    Text("\(item.count)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(.quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    DetailsCompletionSuggestionsChipsBar(
        suggestions: [
            DetailsCompletionSuggestion(text: "München", count: 9),
            DetailsCompletionSuggestion(text: "Berlin", count: 6),
            DetailsCompletionSuggestion(text: "New York City", count: 4),
            DetailsCompletionSuggestion(text: "Hamburg", count: 3)
        ],
        maxVisible: 3,
        showsCounts: true,
        onSelect: { _ in }
    )
    .padding()
}
