//
//  GraphPickerSheet.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import SwiftUI
import SwiftData

struct GraphPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var showAdd = false
    @State private var newName = ""

    @State private var renameGraph: MetaGraph?
    @State private var renameText: String = ""

    private var activeID: UUID? { UUID(uuidString: activeGraphIDString) }

    // ✅ Dedupe by UUID (wenn durch Sync/Bootstrap derselbe Graph doppelt auftaucht)
    private var uniqueGraphs: [MetaGraph] {
        var seen = Set<UUID>()
        return graphs.filter { seen.insert($0.id).inserted }
    }

    private var hiddenDuplicateCount: Int {
        max(0, graphs.count - uniqueGraphs.count)
    }

    var body: some View {
        NavigationStack {
            List {
                if uniqueGraphs.isEmpty {
                    Text("Keine Graphen gefunden (das sollte eigentlich nicht passieren).")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(uniqueGraphs) { g in
                        Button {
                            activeGraphIDString = g.id.uuidString
                            dismiss()
                        } label: {
                            HStack {
                                Text(g.name)
                                Spacer()
                                if g.id == activeID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                renameGraph = g
                                renameText = g.name
                            } label: {
                                Label("Umbenennen", systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                    }
                }

                if hiddenDuplicateCount > 0 {
                    Section("Hinweis") {
                        Text("Ich habe \(hiddenDuplicateCount) doppelte Graph-Einträge ausgeblendet (gleiche ID).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button(role: .destructive) {
                            cleanupDuplicateGraphs()
                        } label: {
                            Label("Duplikate entfernen", systemImage: "trash")
                        }
                    }
                }

                Section {
                    Text("Tipp: Links und Picker sind immer auf den aktiven Graph begrenzt – damit du nicht aus Versehen zwei Welten zusammenklebst.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Graphen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("Neuer Graph", isPresented: $showAdd) {
                TextField("Name", text: $newName)
                Button("Abbrechen", role: .cancel) { newName = "" }
                Button("Erstellen") {
                    let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let g = MetaGraph(name: cleaned.isEmpty ? "Neuer Graph" : cleaned)
                    modelContext.insert(g)
                    try? modelContext.save()
                    activeGraphIDString = g.id.uuidString
                    dismiss()
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Jeder Graph ist eine eigene Wissensdatenbank.")
            }
            .alert("Graph umbenennen", isPresented: Binding(
                get: { renameGraph != nil },
                set: { if !$0 { renameGraph = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Abbrechen", role: .cancel) { renameGraph = nil }
                Button("Speichern") {
                    guard let g = renameGraph else { return }
                    let cleaned = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    g.name = cleaned.isEmpty ? g.name : cleaned
                    try? modelContext.save()
                    renameGraph = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // ✅ Löscht nur überzählige Duplikate mit identischer UUID (behält den ältesten)
    private func cleanupDuplicateGraphs() {
        var byID: [UUID: [MetaGraph]] = [:]
        for g in graphs {
            byID[g.id, default: []].append(g)
        }

        for (_, list) in byID where list.count > 1 {
            let sorted = list.sorted { $0.createdAt < $1.createdAt }
            for dup in sorted.dropFirst() {
                modelContext.delete(dup)
            }
        }

        try? modelContext.save()
    }
}
