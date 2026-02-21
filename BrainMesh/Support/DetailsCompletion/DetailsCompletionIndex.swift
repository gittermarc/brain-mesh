//
//  DetailsCompletionIndex.swift
//  BrainMesh
//
//  Created by Marc Fechner on 21.02.26.
//

import Foundation
import SwiftData

/// In-memory completion index for text-based detail fields.
///
/// Design goals:
/// - Load once per (graphID, fieldID) and cache in-memory.
/// - Matching is case/diacritic-insensitive via `BMSearch.fold`.
/// - Ranking is frequency-first.
/// - Hard limits keep memory and matching predictable.
///
/// Usage (later in UI integration):
/// 1) `await DetailsCompletionIndex.shared.ensureLoaded(graphID:fieldID:in:)` when opening the editor.
/// 2) On each keystroke: `await ...suggestions(graphID:fieldID:prefix:)` (no fetch).
actor DetailsCompletionIndex {
    static let shared = DetailsCompletionIndex()

    // MARK: - Config

    struct Config: Sendable {
        /// Minimum prefix length required before we return any suggestions.
        var minPrefixLength: Int = 2
        /// Upper bound for how many unique strings we keep per field.
        var maxUniqueCandidates: Int = 600
        /// Default max number of suggestions to return.
        var defaultSuggestionLimit: Int = 8

        init(minPrefixLength: Int = 2, maxUniqueCandidates: Int = 600, defaultSuggestionLimit: Int = 8) {
            self.minPrefixLength = max(0, minPrefixLength)
            self.maxUniqueCandidates = max(1, maxUniqueCandidates)
            self.defaultSuggestionLimit = max(1, defaultSuggestionLimit)
        }
    }

    private let config: Config

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Cache

    struct Key: Hashable, Sendable {
        let graphID: UUID
        let fieldID: UUID
    }

    private struct Entry: Hashable, Sendable {
        let text: String
        let folded: String
        let count: Int
    }

    private struct Cache: Sendable {
        let entries: [Entry] // sorted by count desc, then stable alpha
    }

    private var caches: [Key: Cache] = [:]

    // MARK: - Public API

    func isLoaded(graphID: UUID, fieldID: UUID) -> Bool {
        caches[Key(graphID: graphID, fieldID: fieldID)] != nil
    }

    /// Loads and caches the index for a given (graphID, fieldID) once.
    /// Safe to call multiple times; subsequent calls are no-ops.
    func ensureLoaded(graphID: UUID, fieldID: UUID, in modelContext: ModelContext) async {
        let key = Key(graphID: graphID, fieldID: fieldID)
        if caches[key] != nil { return }

        do {
            let cache = try await Self.buildCache(
                graphID: graphID,
                fieldID: fieldID,
                in: modelContext,
                maxUnique: config.maxUniqueCandidates
            )
            caches[key] = cache
        } catch {
            // Keep behavior predictable: if a fetch fails, we just don't provide suggestions.
            caches[key] = Cache(entries: [])
        }
    }

    func invalidate(graphID: UUID, fieldID: UUID) {
        caches[Key(graphID: graphID, fieldID: fieldID)] = nil
    }

    func invalidateAll() {
        caches.removeAll(keepingCapacity: false)
    }

    /// Returns frequency-ranked suggestions for a given prefix.
    /// This does **not** hit SwiftData; call `ensureLoaded` beforehand.
    func suggestions(
        graphID: UUID,
        fieldID: UUID,
        prefix: String,
        limit: Int? = nil
    ) async -> [DetailsCompletionSuggestion] {
        let cleanedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanedPrefix.count >= config.minPrefixLength else { return [] }

        let key = Key(graphID: graphID, fieldID: fieldID)
        guard let cache = caches[key], !cache.entries.isEmpty else { return [] }

        let foldedPrefix = BMSearch.fold(cleanedPrefix)
        if foldedPrefix.isEmpty { return [] }

        let maxResults = min(limit ?? config.defaultSuggestionLimit, config.maxUniqueCandidates)
        if maxResults <= 0 { return [] }

        var result: [DetailsCompletionSuggestion] = []
        result.reserveCapacity(min(maxResults, 16))

        // `entries` are already sorted by count desc, so we can keep order by filtering.
        for e in cache.entries {
            if e.folded.hasPrefix(foldedPrefix) {
                result.append(DetailsCompletionSuggestion(text: e.text, count: e.count))
                if result.count >= maxResults { break }
            }
        }
        return result
    }

    func topSuggestion(graphID: UUID, fieldID: UUID, prefix: String) async -> DetailsCompletionSuggestion? {
        let list = await suggestions(graphID: graphID, fieldID: fieldID, prefix: prefix, limit: 1)
        return list.first
    }

    // MARK: - Build

    private static func buildCache(
        graphID: UUID,
        fieldID: UUID,
        in modelContext: ModelContext,
        maxUnique: Int
    ) async throws -> Cache {
        let gid = graphID
        let fid = fieldID

        // SwiftData ModelContext is typically main-actor bound in SwiftUI apps.
        let rawValues: [String] = try await MainActor.run {
            let fd = FetchDescriptor(
                predicate: #Predicate<MetaDetailFieldValue> { v in
                    v.fieldID == fid && (v.graphID == gid || v.graphID == nil)
                }
            )
            // No sorting needed for aggregation.
            let rows = try modelContext.fetch(fd)
            return rows.compactMap { $0.stringValue }
        }

        if rawValues.isEmpty {
            return Cache(entries: [])
        }

        var counts: [String: Int] = [:]
        counts.reserveCapacity(min(rawValues.count, maxUnique))

        for v in rawValues {
            let cleaned = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty { continue }
            counts[cleaned, default: 0] += 1
        }

        if counts.isEmpty {
            return Cache(entries: [])
        }

        var entries: [Entry] = []
        entries.reserveCapacity(min(counts.count, maxUnique))
        for (text, count) in counts {
            entries.append(Entry(text: text, folded: BMSearch.fold(text), count: count))
        }

        entries.sort { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.text.localizedCaseInsensitiveCompare(b.text) == .orderedAscending
        }

        if entries.count > maxUnique {
            entries = Array(entries.prefix(maxUnique))
        }

        return Cache(entries: entries)
    }
}
