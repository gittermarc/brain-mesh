//
//  EntitiesHomeView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

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
