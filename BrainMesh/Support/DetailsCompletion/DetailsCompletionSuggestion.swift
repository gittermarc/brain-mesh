//
//  DetailsCompletionSuggestion.swift
//  BrainMesh
//
//  Created by Marc Fechner on 21.02.26.
//

import Foundation

/// A ranked completion suggestion for a text-based detail field.
///
/// - `text`: The suggested full string to insert.
/// - `count`: How often this exact string was used in this graph for this field.
struct DetailsCompletionSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let count: Int

    init(text: String, count: Int) {
        self.text = text
        self.count = count
        self.id = text
    }
}
