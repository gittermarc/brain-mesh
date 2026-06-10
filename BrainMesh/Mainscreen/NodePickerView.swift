//
//  NodePickerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI

/// Skalierender Picker (mit Suchfeld), graph-scoped.
struct NodePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var recentNodeStore: RecentNodeStore

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    let kind: NodeKind
    let onPick: (NodeRef) -> Void

    @State private var searchText = ""
    @State private var items: [NodeRef] = []
    @State private var recentItems: [NodeRef] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let emptySearchLimit = 50
    private let searchLimit = 200
    private let recentLimit = 8
    private let debounceNanos: UInt64 = 250_000_000

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Fehler").font(.headline)
                        Text(loadError)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Erneut versuchen") { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List {
                        if isLoading {
                            HStack {
                                ProgressView()
                                Text("Suche läuft")
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }

                        pickerContent
                    }
                }
            }
            .navigationTitle(kind == .entity ? "Entität wählen" : "Attribut wählen")
            .searchable(text: $searchText, prompt: "Suchen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task(id: BMSearch.fold(searchText)) {
                let folded = BMSearch.fold(searchText)
                isLoading = true
                loadError = nil

                if folded.isEmpty {
                    await reload(forFolded: "")
                    return
                }

                try? await Task.sleep(nanoseconds: debounceNanos)
                if Task.isCancelled { return }
                await reload(forFolded: folded)
            }
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        let shouldShowRecents = BMSearch.fold(searchText).isEmpty && recentItems.isEmpty == false
        let visibleItems = itemsExcludingRecents

        if shouldShowRecents {
            Section {
                ForEach(recentItems) { item in
                    pickerButton(for: item, isRecent: true)
                }
            } header: {
                Label("Zuletzt gewählt", systemImage: "clock.arrow.circlepath")
            }
        }

        if visibleItems.isEmpty && isLoading == false && shouldShowRecents == false {
            ContentUnavailableView {
                Label(emptyStateTitle, systemImage: "magnifyingglass")
            } description: {
                Text(emptyStateMessage)
            }
        } else if shouldShowRecents && visibleItems.isEmpty == false {
            Section(kind == .entity ? "Alle Entitäten" : "Alle Attribute") {
                ForEach(visibleItems) { item in
                    pickerButton(for: item, isRecent: false)
                }
            }
        } else {
            ForEach(visibleItems) { item in
                pickerButton(for: item, isRecent: false)
            }
        }
    }

    private var itemsExcludingRecents: [NodeRef] {
        guard BMSearch.fold(searchText).isEmpty, recentItems.isEmpty == false else { return items }
        let recentKeys = Set(recentItems.map { NodeRefKey(nodeRef: $0) })
        return items.filter { item in
            recentKeys.contains(NodeRefKey(nodeRef: item)) == false
        }
    }

    private var emptyStateTitle: String {
        BMSearch.fold(searchText).isEmpty ? "Noch keine passenden Nodes" : "Keine Treffer"
    }

    private var emptyStateMessage: String {
        if BMSearch.fold(searchText).isEmpty {
            return kind == .entity
                ? "Im aktuellen Graph sind noch keine Entitäten auswählbar."
                : "Im aktuellen Graph sind noch keine Attribute auswählbar."
        }

        return kind == .entity
            ? "Keine Entität passt zu deiner Suche."
            : "Kein Attribut passt zu deiner Suche."
    }

    private func pickerButton(for item: NodeRef, isRecent: Bool) -> some View {
        Button { onPick(item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.iconSymbolName ?? (item.kind == .entity ? "cube" : "tag"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .foregroundStyle(.primary)

                    if isRecent {
                        Text("Zuletzt gewählt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityLabel(item.label)
        .accessibilityHint(kind == .entity ? "Wählt diese Entität aus" : "Wählt dieses Attribut aus")
    }

    @MainActor private func reload() async {
        await reload(forFolded: BMSearch.fold(searchText))
    }

    @MainActor private func reload(forFolded folded: String) async {
        isLoading = true
        loadError = nil

        do {
            let gid = activeGraphID
            let limit = folded.isEmpty ? emptySearchLimit : searchLimit

            let rows: [NodePickerRowDTO]
            switch kind {
            case .entity:
                rows = try await NodePickerLoader.shared.loadEntities(graphID: gid, foldedSearch: folded, limit: limit)
            case .attribute:
                rows = try await NodePickerLoader.shared.loadAttributes(graphID: gid, foldedSearch: folded, limit: limit)
            }

            let loadedItems = rows.compactMap(toNodeRef)
            let loadedRecents: [NodeRef]
            if folded.isEmpty {
                loadedRecents = try await loadRecentItems(graphID: gid)
            } else {
                loadedRecents = []
            }

            items = loadedItems
            recentItems = loadedRecents
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            isLoading = false
            recentItems = []
            loadError = error.localizedDescription
        }
    }

    @MainActor private func loadRecentItems(graphID: UUID?) async throws -> [NodeRef] {
        let recentIDs = recentNodeStore
            .recentItems(graphID: graphID, nodeKind: kind, limit: recentLimit)
            .map(\.nodeID)
        guard recentIDs.isEmpty == false else { return [] }

        let rows = try await NodePickerLoader.shared.loadExistingRows(
            graphID: graphID,
            kind: kind,
            ids: recentIDs
        )
        return rows.compactMap(toNodeRef)
    }

    private func toNodeRef(_ dto: NodePickerRowDTO) -> NodeRef? {
        guard let kind = NodeKind(rawValue: dto.kindRaw) else { return nil }
        return NodeRef(kind: kind, id: dto.id, label: dto.label, iconSymbolName: dto.iconSymbolName)
    }
}
