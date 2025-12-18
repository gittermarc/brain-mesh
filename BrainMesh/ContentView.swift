//
//  ContentView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

// MARK: - NodeRef

struct NodeRef: Identifiable, Hashable {
    let kind: NodeKind
    let id: UUID
    let label: String
}

// MARK: - Root Tabs

struct ContentView: View {
    var body: some View {
        TabView {
            EntitiesHomeView()
                .tabItem { Label("Entitäten", systemImage: "list.bullet") }

            GraphCanvasScreen()
                .tabItem { Label("Graph", systemImage: "circle.grid.cross") }

            GraphStatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
        }
    }
}

// MARK: - Entities Home

struct EntitiesHomeView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @Query(sort: [SortDescriptor(\MetaEntity.name)])
    private var entities: [MetaEntity]

    @State private var searchText = ""
    @State private var showAddEntity = false
    @State private var showGraphPicker = false

    private var activeGraphName: String {
        if let id = activeGraphID, let g = graphs.first(where: { $0.id == id }) { return g.name }
        return graphs.first?.name ?? "Graph"
    }

    private var scopedEntities: [MetaEntity] {
        guard let gid = activeGraphID else { return entities } // falls Bootstrap noch nicht gelaufen ist
        return entities.filter { $0.graphID == gid || $0.graphID == nil }
    }

    private var filteredEntities: [MetaEntity] {
        let base = scopedEntities
        let s = BMSearch.fold(searchText)
        guard !s.isEmpty else { return base }
        return base.filter { e in
            e.nameFolded.contains(s) || e.attributesList.contains(where: { $0.searchLabelFolded.contains(s) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredEntities) { entity in
                    NavigationLink {
                        EntityDetailView(entity: entity)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entity.name).font(.headline)
                            Text("\(entity.attributesList.count) Attribute")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteEntities)
            }
            .navigationTitle("Entitäten")
            .searchable(text: $searchText, prompt: "Entität oder Attribut suchen…")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showGraphPicker = true } label: {
                        Label(activeGraphName, systemImage: "square.stack.3d.up")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddEntity = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAddEntity) {
                AddEntityView()
            }
            .sheet(isPresented: $showGraphPicker) {
                GraphPickerSheet()
            }
        }
    }

    private func deleteEntities(at offsets: IndexSet) {
        for index in offsets {
            let entity = filteredEntities[index]
            deleteLinks(referencing: .entity, id: entity.id, graphID: entity.graphID ?? activeGraphID)
            modelContext.delete(entity)
        }
    }

    private func deleteLinks(referencing kind: NodeKind, id: UUID, graphID: UUID?) {
        let k = kind.rawValue
        let nodeID = id
        let gid = graphID

        let fdSource = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.sourceKindRaw == k &&
                l.sourceID == nodeID &&
                (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdSource) {
            for l in links { modelContext.delete(l) }
        }

        let fdTarget = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.targetKindRaw == k &&
                l.targetID == nodeID &&
                (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdTarget) {
            for l in links { modelContext.delete(l) }
        }
    }
}

// MARK: - AddEntityView

struct AddEntityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle("Neue Entität")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let e = MetaEntity(name: cleaned, graphID: activeGraphID)
                        modelContext.insert(e)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - EntityDetailView

struct EntityDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entity: MetaEntity

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @State private var showAddAttribute = false
    @State private var newAttributeName = ""
    @State private var showAddLink = false

    init(entity: MetaEntity) {
        self.entity = entity
        let id = entity.id
        let kindRaw = NodeKind.entity.rawValue
        let gid = entity.graphID

        _outgoingLinks = Query(
            filter: #Predicate<MetaLink> { l in
                l.sourceKindRaw == kindRaw && l.sourceID == id && (gid == nil || l.graphID == gid)
            },
            sort: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )

        _incomingLinks = Query(
            filter: #Predicate<MetaLink> { l in
                l.targetKindRaw == kindRaw && l.targetID == id && (gid == nil || l.graphID == gid)
            },
            sort: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        Form {
            Section("Entität") {
                TextField("Name", text: $entity.name)
            }
            NotesAndPhotoSection(
                notes: $entity.notes,
                imageData: $entity.imageData,
                imagePath: $entity.imagePath,
                stableID: entity.id
            )

            Section("Attribute") {
                if entity.attributesList.isEmpty {
                    Text("Noch keine Attribute.").foregroundStyle(.secondary)
                } else {
                    ForEach(entity.attributesList.sorted(by: { $0.name < $1.name })) { attr in
                        NavigationLink { AttributeDetailView(attribute: attr) } label: { Text(attr.name) }
                    }
                    .onDelete(perform: deleteAttributes)
                }

                Button { showAddAttribute = true } label: {
                    Label("Attribut hinzufügen", systemImage: "plus")
                }
            }

            LinksSection(
                titleOutgoing: "Links (ausgehend)",
                titleIncoming: "Links (eingehend)",
                outgoing: outgoingLinks,
                incoming: incomingLinks,
                onDeleteOutgoing: { offsets in for i in offsets { modelContext.delete(outgoingLinks[i]) } },
                onDeleteIncoming: { offsets in for i in offsets { modelContext.delete(incomingLinks[i]) } },
                onAdd: { showAddLink = true }
            )
        }
        .navigationTitle(entity.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Neues Attribut", isPresented: $showAddAttribute) {
            TextField("Name (z.B. 2023)", text: $newAttributeName)
            Button("Abbrechen", role: .cancel) { newAttributeName = "" }
            Button("Hinzufügen") {
                let cleaned = newAttributeName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { return }

                let attr = MetaAttribute(name: cleaned, owner: nil, graphID: entity.graphID)
                modelContext.insert(attr)
                entity.addAttribute(attr)

                newAttributeName = ""
                try? modelContext.save()
            }
        } message: {
            Text("Attribute sind frei benennbar.")
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkView(source: NodeRef(kind: .entity, id: entity.id, label: entity.name),
                        graphID: entity.graphID)
        }
    }

    private func deleteAttributes(at offsets: IndexSet) {
        let sorted = entity.attributesList.sorted(by: { $0.name < $1.name })
        for index in offsets {
            let attr = sorted[index]
            deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID)
            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
    }

    private func deleteLinks(referencing kind: NodeKind, id: UUID, graphID: UUID?) {
        let k = kind.rawValue
        let nodeID = id
        let gid = graphID

        let fdSource = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.sourceKindRaw == k && l.sourceID == nodeID && (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdSource) {
            for l in links { modelContext.delete(l) }
        }

        let fdTarget = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.targetKindRaw == k && l.targetID == nodeID && (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdTarget) {
            for l in links { modelContext.delete(l) }
        }
    }
}

// MARK: - AttributeDetailView

struct AttributeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var attribute: MetaAttribute

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @State private var showAddLink = false

    init(attribute: MetaAttribute) {
        self.attribute = attribute
        let id = attribute.id
        let kindRaw = NodeKind.attribute.rawValue
        let gid = attribute.graphID

        _outgoingLinks = Query(
            filter: #Predicate<MetaLink> { l in
                l.sourceKindRaw == kindRaw && l.sourceID == id && (gid == nil || l.graphID == gid)
            },
            sort: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )

        _incomingLinks = Query(
            filter: #Predicate<MetaLink> { l in
                l.targetKindRaw == kindRaw && l.targetID == id && (gid == nil || l.graphID == gid)
            },
            sort: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        Form {
            Section("Attribut") {
                TextField("Name", text: $attribute.name)
                if let e = attribute.owner {
                    Text("Entität: \(e.name)").foregroundStyle(.secondary)
                }
            }
            NotesAndPhotoSection(
                notes: $attribute.notes,
                imageData: $attribute.imageData,
                imagePath: $attribute.imagePath,
                stableID: attribute.id
            )

            LinksSection(
                titleOutgoing: "Links (ausgehend)",
                titleIncoming: "Links (eingehend)",
                outgoing: outgoingLinks,
                incoming: incomingLinks,
                onDeleteOutgoing: { offsets in for i in offsets { modelContext.delete(outgoingLinks[i]) } },
                onDeleteIncoming: { offsets in for i in offsets { modelContext.delete(incomingLinks[i]) } },
                onAdd: { showAddLink = true }
            )
        }
        .navigationTitle(attribute.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddLink) {
            AddLinkView(source: NodeRef(kind: .attribute, id: attribute.id, label: attribute.displayName),
                        graphID: attribute.graphID)
        }
    }
}

// MARK: - LinksSection

struct LinksSection: View {
    let titleOutgoing: String
    let titleIncoming: String

    let outgoing: [MetaLink]
    let incoming: [MetaLink]

    let onDeleteOutgoing: (IndexSet) -> Void
    let onDeleteIncoming: (IndexSet) -> Void
    let onAdd: () -> Void

    var body: some View {
        Section(titleOutgoing) {
            if outgoing.isEmpty {
                Text("Keine ausgehenden Links.").foregroundStyle(.secondary)
            } else {
                ForEach(outgoing) { link in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("→ \(link.targetLabel)")
                        if let note = link.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: onDeleteOutgoing)
            }

            Button(action: onAdd) {
                Label("Link hinzufügen", systemImage: "link.badge.plus")
            }
        }

        Section(titleIncoming) {
            if incoming.isEmpty {
                Text("Keine eingehenden Links.").foregroundStyle(.secondary)
            } else {
                ForEach(incoming) { link in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("← \(link.sourceLabel)")
                        if let note = link.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: onDeleteIncoming)
            }
        }
    }
}

// MARK: - AddLinkView

struct AddLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let source: NodeRef
    let graphID: UUID?

    @State private var targetKind: NodeKind = .entity
    @State private var selectedTarget: NodeRef?

    @State private var note: String = ""
    @State private var showPicker = false
    @State private var showDuplicateAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Quelle") { Text(source.label) }

                Section("Zieltyp") {
                    Picker("Zieltyp", selection: $targetKind) {
                        Text("Entität").tag(NodeKind.entity)
                        Text("Attribut").tag(NodeKind.attribute)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: targetKind) { _, _ in selectedTarget = nil }
                }

                Section("Ziel") {
                    Button { showPicker = true } label: {
                        HStack {
                            Text(selectedTarget?.label ?? "Bitte wählen…")
                                .foregroundStyle(selectedTarget == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notiz (optional)") {
                    TextField("z.B. Kontext", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Link hinzufügen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                        .disabled(selectedTarget == nil)
                }
            }
            .alert("Link existiert bereits", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Diese Verbindung ist schon vorhanden.")
            }
            .sheet(isPresented: $showPicker) {
                NodePickerView(kind: targetKind) { picked in
                    selectedTarget = picked
                    showPicker = false
                }
            }
        }
    }

    private func save() {
        guard let target = selectedTarget else { return }

        let sKind = source.kind.rawValue
        let sID = source.id
        let tKind = target.kind.rawValue
        let tID = target.id
        let gid = graphID

        let fd = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.sourceKindRaw == sKind &&
                l.sourceID == sID &&
                l.targetKindRaw == tKind &&
                l.targetID == tID &&
                (gid == nil || l.graphID == gid)
            }
        )

        if let existing = try? modelContext.fetch(fd), !existing.isEmpty {
            showDuplicateAlert = true
            return
        }

        let cleaned = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = cleaned.isEmpty ? nil : cleaned

        let link = MetaLink(
            sourceKind: source.kind,
            sourceID: source.id,
            sourceLabel: source.label,
            targetKind: target.kind,
            targetID: target.id,
            targetLabel: target.label,
            note: finalNote,
            graphID: gid
        )

        modelContext.insert(link)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - NodePickerView (skalierend, graph-scoped)

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
                        Text(loadError).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                            Button { onPick(item) } label: { Text(item.label) }
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

        return try modelContext.fetch(fd).map { NodeRef(kind: .entity, id: $0.id, label: $0.name) }
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

        return try modelContext.fetch(fd).map { NodeRef(kind: .attribute, id: $0.id, label: $0.displayName) }
    }
}
