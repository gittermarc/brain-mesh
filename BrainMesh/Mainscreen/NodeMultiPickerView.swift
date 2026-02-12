//
//  NodeMultiPickerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData

/// Multi-select picker (with search), graph-scoped. Designed for bulk-link flows.
struct NodeMultiPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    let source: NodeRef
    let graphID: UUID?

    @Binding var selection: Set<NodeRef>
    let alreadyLinkedTargets: Set<NodeRefKey>
    @Binding var showOnlyUnlinked: Bool

    @State private var scope: Scope = .all
    @State private var searchText = ""
    @State private var items: [NodeRef] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let emptySearchLimit = 50
    private let searchLimit = 200
    private let debounceNanos: UInt64 = 250_000_000

    var body: some View {
        List {
            Section {
                Picker("Zieltyp", selection: $scope) {
                    Text("Alle").tag(Scope.all)
                    Text("Entitäten").tag(Scope.entities)
                    Text("Attribute").tag(Scope.attributes)
                }
                .pickerStyle(.segmented)

                Toggle("Nur ohne bestehende Verlinkung", isOn: $showOnlyUnlinked)
            }

            if showOnlyUnlinked && !selectedAlreadyLinked.isEmpty {
                Section {
                    ForEach(selectedAlreadyLinked, id: \.self) { item in
                        SelectableRow(item: item, isSelected: true) {
                            selection.remove(item)
                        }
                    }
                } header: {
                    Text("Bereits verlinkt")
                } footer: {
                    Text("Diese Ziele sind schon mit der Quelle verbunden. Du kannst sie hier abwählen.")
                }
            }

            Section {
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Suche…").foregroundStyle(.secondary)
                        }
                    }

                    ForEach(displayItems, id: \.self) { item in
                        let selected = selection.contains(item)
                        SelectableRow(item: item, isSelected: selected) {
                            toggle(item)
                        }
                    }
                }
            } footer: {
                if selection.isEmpty {
                    Text("Keine Ziele ausgewählt.")
                } else {
                    Text("Ausgewählt: \(selection.count)")
                }
            }
        }
        .navigationTitle("Ziele auswählen")
        .searchable(text: $searchText, prompt: "Suchen…")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fertig") { dismiss() }
            }
        }
        .task { await reload() }
        .task(id: scope) { await reload() }
        .task(id: searchText) {
            let folded = BMSearch.fold(searchText)
            isLoading = true
            loadError = nil
            try? await Task.sleep(nanoseconds: debounceNanos)
            if Task.isCancelled { return }
            await reload(forFolded: folded)
        }
    }

    private var scopedGraphID: UUID? {
        graphID ?? activeGraphID
    }

    private var selectedAlreadyLinked: [NodeRef] {
        Array(selection)
            .filter { $0.kind != source.kind || $0.id != source.id }
            .filter { alreadyLinkedTargets.contains(NodeRefKey(nodeRef: $0)) }
            .sorted(by: { BMSearch.fold($0.label) < BMSearch.fold($1.label) })
    }

    private var displayItems: [NodeRef] {
        items
            .filter { $0.kind != source.kind || $0.id != source.id }
            .filter { item in
                guard showOnlyUnlinked else { return true }
                // If it's already linked, hide it unless it's currently selected (so the user can unselect).
                if selection.contains(item) { return true }
                return !alreadyLinkedTargets.contains(NodeRefKey(nodeRef: item))
            }
    }

    private func toggle(_ item: NodeRef) {
        if selection.contains(item) {
            selection.remove(item)
        } else {
            selection.insert(item)
        }
    }

    @MainActor private func reload() async {
        await reload(forFolded: BMSearch.fold(searchText))
    }

    @MainActor private func reload(forFolded folded: String) async {
        isLoading = true
        loadError = nil

        do {
            switch scope {
            case .entities:
                items = try fetchEntities(foldedSearch: folded, limit: folded.isEmpty ? emptySearchLimit : searchLimit)
            case .attributes:
                items = try fetchAttributes(foldedSearch: folded, limit: folded.isEmpty ? emptySearchLimit : searchLimit)
            case .all:
                let entityLimit = folded.isEmpty ? emptySearchLimit / 2 : searchLimit / 2
                let attributeLimit = folded.isEmpty ? emptySearchLimit / 2 : searchLimit / 2
                let e = try fetchEntities(foldedSearch: folded, limit: max(10, entityLimit))
                let a = try fetchAttributes(foldedSearch: folded, limit: max(10, attributeLimit))
                items = (e + a)
                    .sorted(by: { BMSearch.fold($0.label) < BMSearch.fold($1.label) })
            }
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func fetchEntities(foldedSearch s: String, limit: Int) throws -> [NodeRef] {
        let gid = scopedGraphID
        var fd: FetchDescriptor<MetaEntity>

        if s.isEmpty {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    gid == nil || e.graphID == gid || e.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            let term = s
            fd = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    (gid == nil || e.graphID == gid || e.graphID == nil) &&
                    e.nameFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        }

        fd.fetchLimit = limit
        return try modelContext.fetch(fd).map { NodeRef(kind: .entity, id: $0.id, label: $0.name, iconSymbolName: $0.iconSymbolName) }
    }

    private func fetchAttributes(foldedSearch s: String, limit: Int) throws -> [NodeRef] {
        let gid = scopedGraphID
        var fd: FetchDescriptor<MetaAttribute>

        if s.isEmpty {
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    gid == nil || a.graphID == gid || a.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        } else {
            let term = s
            fd = FetchDescriptor(
                predicate: #Predicate<MetaAttribute> { a in
                    (gid == nil || a.graphID == gid || a.graphID == nil) &&
                    a.searchLabelFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        }

        fd.fetchLimit = limit
        return try modelContext.fetch(fd).map { NodeRef(kind: .attribute, id: $0.id, label: $0.displayName, iconSymbolName: $0.iconSymbolName) }
    }
}

private enum Scope: Int, CaseIterable {
    case all
    case entities
    case attributes
}

private struct SelectableRow: View {
    let item: NodeRef
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.iconSymbolName ?? (item.kind == .entity ? "cube" : "tag"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                    Text(item.kind == .entity ? "Entität" : "Attribut")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .contentShape(Rectangle())
        }
    }
}
