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

    @EnvironmentObject private var graphLock: GraphLockCoordinator

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var showAdd = false
    @State private var newName = ""

    @State private var showSecurity = false
    @State private var securityGraph: MetaGraph?

    @State private var renameGraph: MetaGraph?
    @State private var renameText: String = ""

    // ✅ Delete flow
    @State private var deleteGraph: MetaGraph?
    @State private var isDeleting = false
    @State private var deleteError: String?

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
                            if g.isProtected && !graphLock.isUnlocked(graphID: g.id) {
                                graphLock.requestUnlock(
                                    for: g,
                                    purpose: .switchGraph,
                                    onSuccess: {
                                        activeGraphIDString = g.id.uuidString
                                        dismiss()
                                    },
                                    onCancel: {
                                        // do nothing
                                    }
                                )
                            } else {
                                activeGraphIDString = g.id.uuidString
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(g.name)
                                Spacer()

                                if g.isProtected {
                                    Image(systemName: graphLock.isUnlocked(graphID: g.id) ? "lock.open" : "lock.fill")
                                        .foregroundStyle(.secondary)
                                }

                                if g.id == activeID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeleting)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {

                            Button {
                                securityGraph = g
                                showSecurity = true
                            } label: {
                                Label("Schutz", systemImage: "lock")
                            }
                            .tint(.gray)

                            Button {
                                renameGraph = g
                                renameText = g.name
                            } label: {
                                Label("Umbenennen", systemImage: "pencil")
                            }
                            .tint(.indigo)

                            Button(role: .destructive) {
                                deleteGraph = g
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
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
                        .disabled(isDeleting)
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
                        .disabled(isDeleting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isDeleting)
                }
            }

            .overlay {
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Lösche…").foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }

            // MARK: Add graph
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

            // MARK: Rename
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

            // MARK: Delete confirm
            .alert("Graph löschen?", isPresented: Binding(
                get: { deleteGraph != nil },
                set: { if !$0 { deleteGraph = nil } }
            )) {
                Button("Abbrechen", role: .cancel) { deleteGraph = nil }

                Button("Löschen", role: .destructive) {
                    guard let g = deleteGraph else { return }
                    Task { await deleteGraphCompletely(graphUUID: g.id) }
                }
            } message: {
                if let g = deleteGraph {
                    let isActive = (g.id == activeID)
                    let isLast = (uniqueGraphs.count <= 1)
                    if isLast {
                        Text("Dieser Graph ist der letzte. Wenn du ihn löschst, wird automatisch ein neuer leerer „Default“-Graph angelegt.")
                    } else if isActive {
                        Text("Dieser Graph ist aktuell aktiv. Nach dem Löschen wird automatisch auf einen anderen Graph umgeschaltet.")
                    } else {
                        Text("Das löscht den Graph inkl. Entitäten, Attributen, Links, Notizen und Bildern. Diese Aktion kann nicht rückgängig gemacht werden.")
                    }
                } else {
                    Text("")
                }
            }

            // MARK: Delete error
            .alert("Löschen fehlgeschlagen", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
        }
        .sheet(isPresented: $showSecurity) {
            if let g = securityGraph {
                GraphSecuritySheet(graph: g)
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

    // MARK: - Graph deletion (inkl. Inhalte + lokale Bilder)

    @MainActor
    private func deleteGraphCompletely(graphUUID: UUID) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        do {
            // 1) Fallback active graph bestimmen (falls wir den aktiven löschen)
            let currentActive = UUID(uuidString: activeGraphIDString)
            let deletingIsActive = (currentActive == graphUUID)

            // Kandidaten: alle Graphs außer dem zu löschenden (unique, stabil)
            let remaining = uniqueGraphs
                .filter { $0.id != graphUUID }
                .sorted { $0.createdAt < $1.createdAt }

            var newActive: UUID? = nil

            if deletingIsActive {
                if let first = remaining.first {
                    newActive = first.id
                } else {
                    // letzter Graph -> direkt neuen erstellen (damit App nie "ohne Graph" ist)
                    let fresh = MetaGraph(name: "Default")
                    modelContext.insert(fresh)
                    newActive = fresh.id
                }
            }

            if let newActive {
                activeGraphIDString = newActive.uuidString
            }

            // 2) Betroffene Objekte laden
            // Entities im Graph
            graphLock.lock(graphID: graphUUID)

            let gid = graphUUID
            let entsFD = FetchDescriptor<MetaEntity>(
                predicate: #Predicate { e in e.graphID == gid }
            )
            let entities = try modelContext.fetch(entsFD)

            // Links im Graph
            let linksFD = FetchDescriptor<MetaLink>(
                predicate: #Predicate { l in l.graphID == gid }
            )
            let links = try modelContext.fetch(linksFD)

            // Orphan Attributes (falls jemals entstanden)
            let orphansFD = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate { a in a.graphID == gid && a.owner == nil }
            )
            let orphans = try modelContext.fetch(orphansFD)

            // Graph-Duplikate mit gleicher id (Sync-Schluckauf)
            let graphsToDelete = graphs.filter { $0.id == gid }

            // 3) Lokale Bilder sammeln (bevor wir löschen)
            var imagePaths = Set<String>()

            for e in entities {
                if let p = e.imagePath, !p.isEmpty { imagePaths.insert(p) }
                // Attributes hängen i.d.R. dran (Cascade), aber wir lesen Pfade vorsichtshalber vorher aus
                for a in e.attributesList {
                    if let p = a.imagePath, !p.isEmpty { imagePaths.insert(p) }
                }
            }
            for a in orphans {
                if let p = a.imagePath, !p.isEmpty { imagePaths.insert(p) }
            }

            // 3b) Attachments aufräumen (Records + lokaler Cache)
            // 1) normaler Fall: graphID gesetzt
            AttachmentCleanup.deleteAttachments(graphID: gid, in: modelContext)

            // 2) defensiv: graphID == nil, aber Owner wird gerade gelöscht
            for e in entities {
                AttachmentCleanup.deleteAttachments(ownerKind: .entity, ownerID: e.id, graphID: nil, in: modelContext)
                for a in e.attributesList {
                    AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: a.id, graphID: nil, in: modelContext)
                }
            }
            for a in orphans {
                AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: a.id, graphID: nil, in: modelContext)
            }

            // 4) Löschen (Reihenfolge: Links -> Orphans -> Entities -> Graphs)
            for l in links { modelContext.delete(l) }
            for a in orphans { modelContext.delete(a) }
            for e in entities { modelContext.delete(e) } // cascade entfernt owned attributes
            for g in graphsToDelete { modelContext.delete(g) }

            try modelContext.save()

            // 5) Lokale Files aufräumen (nicht CloudKit, nur Device)
            for p in imagePaths {
                ImageStore.delete(path: p)
            }

            // UI sauber schließen, wenn wir gerade den aktiven Graph gewechselt haben
            // (Optional: ich würde es drinlassen, fühlt sich „fertig“ an)
            deleteGraph = nil

        } catch {
            deleteError = error.localizedDescription
        }
    }
}
