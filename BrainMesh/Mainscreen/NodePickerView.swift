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

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    let kind: NodeKind
    let onPick: (NodeRef) -> Void

    @State private var searchText = ""
    @State private var items: [NodeRef] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let emptySearchLimit = 50
    private let searchLimit = 200
    private let debounceNanos: UInt64 = 250_000_000

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
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
                                Text("Suche…").foregroundStyle(.secondary)
                            }
                        }
                        ForEach(items) { item in
                            Button { onPick(item) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.iconSymbolName ?? (item.kind == .entity ? "cube" : "tag"))
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 22)
                                        .foregroundStyle(.tint)
                                    Text(item.label)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(kind == .entity ? "Entität wählen" : "Attribut wählen")
            .searchable(text: $searchText, prompt: "Suchen…")
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

            items = rows.compactMap(toNodeRef)
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func toNodeRef(_ dto: NodePickerRowDTO) -> NodeRef? {
        guard let kind = NodeKind(rawValue: dto.kindRaw) else { return nil }
        return NodeRef(kind: kind, id: dto.id, label: dto.label, iconSymbolName: dto.iconSymbolName)
    }
}
