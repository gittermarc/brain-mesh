//
//  BrainMeshSearchRanking.swift
//  BrainMesh
//
//  Deterministic ranking helpers for global BrainMesh search.
//

import Foundation

nonisolated enum BrainMeshSearchFieldPriority: Int, Sendable {
    case primaryLabel = 0
    case secondaryLabel = 1
    case metadata = 2
    case notes = 3
}

nonisolated struct BrainMeshSearchRankingField: Hashable, Sendable {
    let text: String
    let foldedText: String
    let reason: String
    let priority: BrainMeshSearchFieldPriority

    init(text: String, reason: String, priority: BrainMeshSearchFieldPriority) {
        self.text = text
        self.foldedText = BMSearch.fold(text)
        self.reason = reason
        self.priority = priority
    }
}

nonisolated struct BrainMeshSearchRankingMatch: Hashable, Sendable {
    let score: Int
    let matchReason: String
}

nonisolated enum BrainMeshSearchRanking {
    private enum MatchQuality: Int {
        case exact = 0
        case prefix = 1
        case contains = 2
    }

    static func bestMatch(
        foldedQuery: String,
        fields: [BrainMeshSearchRankingField]
    ) -> BrainMeshSearchRankingMatch? {
        let query = BMSearch.fold(foldedQuery)
        guard query.isEmpty == false else { return nil }

        var best: BrainMeshSearchRankingMatch?

        for field in fields where field.foldedText.isEmpty == false {
            guard let quality = matchQuality(query: query, foldedText: field.foldedText) else { continue }
            let score = field.priority.rawValue * 3 + quality.rawValue
            let candidate = BrainMeshSearchRankingMatch(score: score, matchReason: field.reason)
            if shouldReplace(current: best, with: candidate) {
                best = candidate
            }
        }

        return best
    }

    static func sortedCandidates(_ candidates: [BrainMeshSearchCandidate]) -> [BrainMeshSearchCandidate] {
        candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            if lhs.result.kind.sortPrecedence != rhs.result.kind.sortPrecedence {
                return lhs.result.kind.sortPrecedence < rhs.result.kind.sortPrecedence
            }
            if lhs.foldedTitle != rhs.foldedTitle {
                return lhs.foldedTitle < rhs.foldedTitle
            }
            if lhs.foldedSubtitle != rhs.foldedSubtitle {
                return lhs.foldedSubtitle < rhs.foldedSubtitle
            }
            return lhs.result.id.uuidString < rhs.result.id.uuidString
        }
    }

    private static func matchQuality(query: String, foldedText: String) -> MatchQuality? {
        if foldedText == query {
            return .exact
        }
        if foldedText.hasPrefix(query) {
            return .prefix
        }
        if foldedText.contains(query) {
            return .contains
        }
        return nil
    }

    private static func shouldReplace(
        current: BrainMeshSearchRankingMatch?,
        with candidate: BrainMeshSearchRankingMatch
    ) -> Bool {
        guard let current else { return true }
        if candidate.score != current.score {
            return candidate.score < current.score
        }
        return candidate.matchReason < current.matchReason
    }
}

nonisolated struct BrainMeshSearchCandidate: Hashable, Sendable {
    let result: BrainMeshSearchResult
    let score: Int
    let foldedTitle: String
    let foldedSubtitle: String

    init(result: BrainMeshSearchResult, score: Int) {
        self.result = result
        self.score = score
        self.foldedTitle = BMSearch.fold(result.title)
        self.foldedSubtitle = BMSearch.fold(result.subtitle)
    }
}
