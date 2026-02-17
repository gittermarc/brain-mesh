//
//  NodeMultiPickerView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI

/// Multi-select picker (with search), graph-scoped. Designed for bulk-link flows.
struct NodeMultiPickerView: View {
    @Environment(\.dismiss) private var dismiss

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
        .task(id: ReloadKey(scope: scope, foldedSearch: BMSearch.fold(searchText))) {
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
            let gid = scopedGraphID
            switch scope {
            case .entities:
                let limit = folded.isEmpty ? emptySearchLimit : searchLimit
                let rows = try await NodePickerLoader.shared.loadEntities(graphID: gid, foldedSearch: folded, limit: limit)
                items = rows.compactMap(toNodeRef)
            case .attributes:
                let limit = folded.isEmpty ? emptySearchLimit : searchLimit
                let rows = try await NodePickerLoader.shared.loadAttributes(graphID: gid, foldedSearch: folded, limit: limit)
                items = rows.compactMap(toNodeRef)
            case .all:
                let entityLimit = folded.isEmpty ? emptySearchLimit / 2 : searchLimit / 2
                let attributeLimit = folded.isEmpty ? emptySearchLimit / 2 : searchLimit / 2
                async let eRows = NodePickerLoader.shared.loadEntities(
                    graphID: gid,
                    foldedSearch: folded,
                    limit: max(10, entityLimit)
                )
                async let aRows = NodePickerLoader.shared.loadAttributes(
                    graphID: gid,
                    foldedSearch: folded,
                    limit: max(10, attributeLimit)
                )

                let (eDTO, aDTO) = try await (eRows, aRows)
                let e = eDTO.compactMap(toNodeRef)
                let a = aDTO.compactMap(toNodeRef)
                items = (e + a)
                    .sorted(by: { BMSearch.fold($0.label) < BMSearch.fold($1.label) })
            }
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

private enum Scope: Int, CaseIterable {
    case all
    case entities
    case attributes
}

private struct ReloadKey: Hashable {
    let scope: Scope
    let foldedSearch: String
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
