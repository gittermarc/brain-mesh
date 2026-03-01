//
//  AllSFSymbolsPickerViewModel.swift
//  BrainMesh
//
//  Extracted from AllSFSymbolsPickerView.swift
//

import Foundation
import Combine

@MainActor
final class AllSFSymbolsPickerViewModel: ObservableObject {

    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String? = nil

    @Published var searchText: String = ""
    @Published var isSearching: Bool = false

    @Published var displayedSymbols: [String] = []
    @Published var searchResults: [String] = []

    private var allSymbols: [String] = []
    private var searchIndex: IconSearchIndex? = nil

    private let pageSize: Int = 720

    private var loadTask: Task<Void, Never>? = nil
    private var loadToken: UUID = UUID()

    private var loadMoreTask: Task<Void, Never>? = nil
    private var loadMoreToken: UUID = UUID()

    private var searchTask: Task<Void, Never>? = nil
    private var searchToken: UUID = UUID()

    var countLabel: String {
        if isSearching {
            if searchResults.isEmpty && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "0"
            }
            return "\(searchResults.count)"
        }

        if allSymbols.isEmpty {
            return ""
        }

        return "\(displayedSymbols.count) / \(allSymbols.count)"
    }

    func loadIfNeeded() {
        guard !isLoading else { return }
        guard allSymbols.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        loadTask?.cancel()
        let token = UUID()
        loadToken = token

        let pageSize = self.pageSize

        loadTask = Task(priority: .utility) { [pageSize] in
            do {
                try Task.checkCancellation()

                let symbols = try SFSymbolsCatalog.loadAllSymbolNames()
                try Task.checkCancellation()

                let index = IconSearchIndex(symbols: symbols)
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.allSymbols = symbols
                    self.searchIndex = index
                    self.displayedSymbols = Array(symbols.prefix(pageSize))
                    self.isLoading = false

                    if !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.scheduleSearch(term: self.searchText)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard self.loadToken == token else { return }
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func reload() {
        loadTask?.cancel()
        loadMoreTask?.cancel()
        cancelSearch()

        loadToken = UUID()
        loadMoreToken = UUID()

        allSymbols = []
        searchIndex = nil
        displayedSymbols = []
        searchResults = []
        isSearching = false
        isLoadingMore = false

        loadIfNeeded()
    }

    func loadMoreIfNeeded(currentItem: String) {
        guard !isSearching else { return }
        guard !isLoadingMore else { return }
        guard !isLoading else { return }
        guard !allSymbols.isEmpty else { return }
        guard displayedSymbols.count < allSymbols.count else { return }

        let threshold = max(0, displayedSymbols.count - 80)
        if let idx = displayedSymbols.firstIndex(of: currentItem), idx >= threshold {
            loadMore()
        }
    }

    private func loadMore() {
        guard !isSearching else { return }
        guard !isLoadingMore else { return }
        guard displayedSymbols.count < allSymbols.count else { return }

        isLoadingMore = true

        loadMoreTask?.cancel()
        let token = UUID()
        loadMoreToken = token

        // Snapshot state on MainActor, then slice off-main.
        let snapshotAll = allSymbols
        let start = displayedSymbols.count
        let end = min(snapshotAll.count, start + pageSize)

        loadMoreTask = Task(priority: .utility) { [snapshotAll, start, end] in
            if Task.isCancelled { return }

            guard start < end else {
                await MainActor.run {
                    guard self.loadMoreToken == token else { return }
                    self.isLoadingMore = false
                }
                return
            }

            let more = Array(snapshotAll[start..<end])

            if Task.isCancelled { return }

            await MainActor.run {
                guard self.loadMoreToken == token else { return }
                guard !self.isSearching else {
                    self.isLoadingMore = false
                    return
                }
                guard self.displayedSymbols.count == start else {
                    self.isLoadingMore = false
                    return
                }

                self.displayedSymbols.append(contentsOf: more)
                self.isLoadingMore = false
            }
        }
    }

    func scheduleSearch(term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cancel any inflight work that could update the grid while searching.
        loadMoreTask?.cancel()
        loadMoreToken = UUID()
        isLoadingMore = false

        searchTask?.cancel()

        guard !trimmed.isEmpty else {
            searchToken = UUID()
            isSearching = false
            searchResults = []
            return
        }

        isSearching = true

        let token = UUID()
        searchToken = token

        let indexSnapshot = searchIndex

        searchTask = Task(priority: .userInitiated) { [trimmed, indexSnapshot] in
            do {
                try await Task.sleep(nanoseconds: 160_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let results = indexSnapshot?.search(term: trimmed, limit: 1200) ?? []

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.searchToken == token else { return }

                // Only apply if the user hasn't changed the term in the meantime.
                let current = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard current == trimmed else { return }

                self.searchResults = results
            }
        }
    }

    func cancelSearch() {
        searchToken = UUID()
        searchTask?.cancel()
        searchTask = nil
    }
}
