//
//  IconPickerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("BMRecentSymbolNames") private var recentRaw: String = ""

    @Binding var selection: String?
    @State private var searchText: String = ""

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 12, alignment: .top)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    noneSection

                    if !searchResults.isEmpty {
                        symbolGridSection(title: "Ergebnisse", symbols: searchResults)
                    } else {
                        if !recentSymbols.isEmpty {
                            symbolGridSection(title: "Zuletzt verwendet", symbols: recentSymbols)
                        }
                        ForEach(IconCatalog.categories) { category in
                            symbolGridSection(title: category.title, symbols: category.symbols)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .navigationTitle("Icon wählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Symbol suchen (z.B. tag, cube, calendar)…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    private var noneSection: some View {
        Button {
            selection = nil
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 18, weight: .semibold))
                Text("Kein Icon")
                Spacer()
                if selection == nil {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var recentSymbols: [String] {
        RecentSymbolStore.decode(recentRaw)
    }

    private var searchResults: [String] {
        let term = BMSearch.fold(searchText)
        guard !term.isEmpty else { return [] }

        return IconCatalog.allSymbols
            .filter { BMSearch.fold($0).contains(term) }
    }

    private func symbolGridSection(title: String, symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                ForEach(symbols, id: \.self) { name in
                    symbolCell(name: name)
                }
            }
        }
    }

    private func symbolCell(name: String) -> some View {
        Button {
            selection = name
            let updated = RecentSymbolStore.bump(name, in: recentSymbols)
            recentRaw = RecentSymbolStore.encode(updated)
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                selection == name
                                    ? AnyShapeStyle(.tint)
                                    : AnyShapeStyle(Color.secondary.opacity(0.35)),
                                lineWidth: 1
                            )
                    )

                Image(systemName: name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 56, height: 44)
            .accessibilityLabel(Text(name))
        }
        .buttonStyle(.plain)
    }
}
