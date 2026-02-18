//
//  IconPickerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import UIKit

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("BMRecentSymbolNames") private var recentRaw: String = ""

    @Binding var selection: String?
    @State private var searchText: String = ""
    @State private var resolvedSearchResults: [String] = []
    @State private var isSearching: Bool = false
    @State private var searchToken: Int = 0
    @State private var searchTask: Task<Void, Never>? = nil

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 44, maximum: 56), spacing: 12, alignment: .top)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    noneSection

                    if let direct = directSymbolCandidate {
                        directEntrySection(symbolName: direct)
                    }

                    if hasSearch {
                        if isSearching && resolvedSearchResults.isEmpty {
                            searchingSection
                        } else if !resolvedSearchResults.isEmpty {
                            symbolGridSection(title: "Ergebnisse", symbols: resolvedSearchResults)
                        } else {
                            noResultsSection
                        }
                    } else {
                        allSymbolsNavigationRow

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
            .searchable(text: $searchText, prompt: "Symbol suchen oder Namen eingeben (z.B. tag, cube, calendar)")
            .onAppear {
                scheduleSearch(for: searchText)
            }
            .onDisappear {
                searchTask?.cancel()
            }
            .onChange(of: searchText) { _, newValue in
                scheduleSearch(for: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
        }
    }

    private var searchTextTrimmed: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearch: Bool {
        !searchTextTrimmed.isEmpty
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

    private var allSymbolsNavigationRow: some View {
        NavigationLink {
            AllSFSymbolsPickerView(selectedSymbol: selection) { picked in
                select(picked)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AnyShapeStyle(Color.secondary.opacity(0.35)), lineWidth: 1)
                        )
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 56, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Alle SF Symbols …")
                        .font(.body)
                    Text("Systemkatalog durchsuchen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var directSymbolCandidate: String? {
        let raw = searchTextTrimmed
        guard !raw.isEmpty else { return nil }

        let candidates: [String] = raw == raw.lowercased()
            ? [raw]
            : [raw, raw.lowercased()]

        for c in candidates {
            guard !c.isEmpty else { continue }
            if IconCatalog.allSymbols.contains(c) { return nil }
            if UIImage(systemName: c) != nil { return c }
        }

        return nil
    }

    private var noResultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kein Treffer")
                .font(.headline)
                .padding(.top, 4)
            Text("Tipp: Du kannst hier auch den exakten SF-Symbol-Namen eintippen (z.B. „person.crop.circle.badge.checkmark“). Wenn das Symbol existiert, erscheint oben „Direkt verwenden“.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var searchingSection: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Suche …")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func scheduleSearch(for raw: String) {
        searchToken += 1
        let token = searchToken

        searchTask?.cancel()

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resolvedSearchResults = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            // Small debounce: keep typing smooth.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }

            let results = IconCatalog.search(term: trimmed, limit: 360)
            await MainActor.run {
                guard token == searchToken else { return }
                resolvedSearchResults = results
                isSearching = false
            }
        }
    }

    private func directEntrySection(symbolName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Direkt verwenden")
                .font(.headline)
                .padding(.top, 4)

            Button {
                select(symbolName)
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
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 56, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(symbolName)
                            .font(.body)
                        Text("Eingegebener Symbolname")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if selection == symbolName {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
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
            select(name)
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

    private func select(_ name: String) {
        selection = name
        let updated = RecentSymbolStore.bump(name, in: recentSymbols)
        recentRaw = RecentSymbolStore.encode(updated)
        dismiss()
    }
}
