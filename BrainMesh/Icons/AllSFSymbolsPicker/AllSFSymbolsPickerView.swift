//
//  AllSFSymbolsPickerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 18.02.26.
//

import SwiftUI
import UIKit

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
                    AllSFSymbolsPickerErrorCard(message: errorMessage) {
                        model.reload()
                    }
                }

                if let direct = directSymbolCandidate {
                    AllSFSymbolsPickerDirectEntryButton(symbolName: direct) {
                        onPick(direct)
                    }
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
                                AllSFSymbolsPickerSymbolCell(
                                    symbol: symbol,
                                    isSelected: selectedSymbol == symbol
                                ) {
                                    onPick(symbol)
                                }
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
        .searchable(
            text: $model.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Symbol suchen …"
        )
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
}
