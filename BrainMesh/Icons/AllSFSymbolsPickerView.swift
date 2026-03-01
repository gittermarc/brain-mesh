//
//  AllSFSymbolsPickerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 18.02.26.
//

import SwiftUI
import UIKit
import Combine

struct AllSFSymbolsPickerView: View {

    let selectedSymbol: String?
    let onPick: (String) -> Void

    @StateObject private var model = AllSFSymbolsPickerViewModel()

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage = model.errorMessage {
                    errorSection(message: errorMessage)
                }

                if let direct = directSymbolCandidate {
                    directEntrySection(symbolName: direct)
                }

                if model.isLoading && model.displayedSymbols.isEmpty && model.searchResults.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView("Lade SF Symbols …")
                        Spacer()
                    }
                    .padding(.top, 24)
                } else {
                    let title = model.isSearching ? "Ergebnisse" : "Alle Symbole"
                    let symbols = model.isSearching ? model.searchResults : model.displayedSymbols

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(title)
                                .font(.headline)
                            Spacer()
                            Text(model.countLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(symbols, id: \.self) { symbol in
                                symbolCell(symbol)
                                    .onAppear {
                                        model.loadMoreIfNeeded(currentItem: symbol)
                                    }
                            }
                        }

                        if model.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.top, 8)
                        }

                        if !model.isLoading && symbols.isEmpty {
                            Text("Keine Treffer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("Alle SF Symbols")
        .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Symbol suchen …")
        .onChange(of: model.searchText) { _, newValue in
            model.scheduleSearch(term: newValue)
        }
        .task {
            model.loadIfNeeded()
        }
        .onDisappear {
            model.cancelSearch()
        }
    }

    private var directSymbolCandidate: String? {
        let trimmed = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains(".") || trimmed.contains("-") || trimmed.contains("_") || trimmed.count >= 2 else {
            return nil
        }
        return UIImage(systemName: trimmed) != nil ? trimmed : nil
    }

    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Katalog nicht verfügbar", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                model.reload()
            } label: {
                Text("Neu laden")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
    }

    private func directEntrySection(symbolName: String) -> some View {
        Button {
            onPick(symbolName)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AnyShapeStyle(Color.secondary.opacity(0.35)), lineWidth: 1)
                        )
                    Image(systemName: symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 56, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Direkt verwenden")
                        .font(.body)
                    Text(symbolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func symbolCell(_ symbol: String) -> some View {
        let isSelected = (selectedSymbol == symbol)

        return Button {
            onPick(symbol)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                AnyShapeStyle(isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.25)),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                VStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(symbol))
    }
}

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
