//
//  NodePickerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

/// Skalierender Picker (mit Suchfeld), graph-scoped.
struct NodePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
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
            .task { await reload() }
            .task(id: searchText) {
                let folded = BMSearch.fold(searchText)
                isLoading = true
                loadError = nil
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
            switch kind {
            case .entity:
                items = try fetchEntities(foldedSearch: folded)
            case .attribute:
                items = try fetchAttributes(foldedSearch: folded)
            }
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func fetchEntities(foldedSearch s: String) throws -> [NodeRef] {
        let gid = activeGraphID
        var fd: FetchDescriptor<MetaEntity>

        if s.isEmpty {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    gid == nil || e.graphID == gid || e.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
            fd.fetchLimit = emptySearchLimit
        } else {
            let term = s
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    (gid == nil || e.graphID == gid || e.graphID == nil) &&
                    e.nameFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
            fd.fetchLimit = searchLimit
        }

        return try modelContext.fetch(fd).map { NodeRef(kind: .entity, id: $0.id, label: $0.name, iconSymbolName: $0.iconSymbolName) }
    }

    private func fetchAttributes(foldedSearch s: String) throws -> [NodeRef] {
        let gid = activeGraphID
        var fd: FetchDescriptor<MetaAttribute>

        if s.isEmpty {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    gid == nil || a.graphID == gid || a.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
            fd.fetchLimit = emptySearchLimit
        } else {
            let term = s
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    (gid == nil || a.graphID == gid || a.graphID == nil) &&
                    a.searchLabelFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
            fd.fetchLimit = searchLimit
        }

        return try modelContext.fetch(fd).map { NodeRef(kind: .attribute, id: $0.id, label: $0.displayName, iconSymbolName: $0.iconSymbolName) }
    }
}
