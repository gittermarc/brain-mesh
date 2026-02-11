//
//  IconSearchIndex.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import Foundation

struct IconSearchIndex: Sendable {

    struct Entry: Sendable {
        let symbol: String
        let key: String
    }

    private let entries: [Entry]

    init(symbols: [String]) {
        self.entries = symbols.map { symbol in
            Entry(symbol: symbol, key: Self.makeSearchKey(symbol))
        }
    }

    func search(term: String, limit: Int) -> [String] {
        let keyTerm = Self.makeSearchKey(term)
        guard !keyTerm.isEmpty else { return [] }

        var prefixMatches: [String] = []
        var containsMatches: [String] = []
        prefixMatches.reserveCapacity(min(48, limit))
        containsMatches.reserveCapacity(min(120, limit))

        for entry in entries {
            if entry.key.hasPrefix(keyTerm) {
                prefixMatches.append(entry.symbol)
            } else if entry.key.contains(keyTerm) {
                containsMatches.append(entry.symbol)
            }

            if prefixMatches.count + containsMatches.count >= limit {
                break
            }
        }

        if prefixMatches.count >= limit {
            return Array(prefixMatches.prefix(limit))
        }

        let remaining = max(0, limit - prefixMatches.count)
        if remaining == 0 { return prefixMatches }

        return prefixMatches + Array(containsMatches.prefix(remaining))
    }

    private static func makeSearchKey(_ s: String) -> String {
        let folded = BMSearch.fold(s)

        let replaced = folded
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        // Collapse whitespace
        return replaced
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
