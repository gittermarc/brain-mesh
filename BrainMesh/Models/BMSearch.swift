//
//  BMSearch.swift
//  BrainMesh
//
//  Split aus Models.swift (P0.1).
//

import Foundation

// Helper für case-/diacritic-insensitive Suche
nonisolated enum BMSearch {
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
