//
//  NodeDetailShared+Connections.Destination.swift
//  BrainMesh
//
//  Destination routing for links (Entity / Attribute) + missing-state UI.
//

import SwiftUI
import SwiftData

struct NodeDestinationView: View {
    @Environment(\.modelContext) private var modelContext

    let kind: NodeKind
    let id: UUID

    var body: some View {
        switch kind {
        case .entity:
            if let e = fetchEntity(id: id) {
                EntityDetailView(entity: e)
            } else {
                NodeMissingView(title: "Entität nicht gefunden")
            }
        case .attribute:
            if let a = fetchAttribute(id: id) {
                AttributeDetailView(attribute: a)
            } else {
                NodeMissingView(title: "Attribut nicht gefunden")
            }
        }
    }

    private func fetchEntity(id: UUID) -> MetaEntity? {
        let nodeID = id
        let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate { e in e.id == nodeID })
        return (try? modelContext.fetch(fd).first)
    }

    private func fetchAttribute(id: UUID) -> MetaAttribute? {
        let nodeID = id
        let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in a.id == nodeID })
        return (try? modelContext.fetch(fd).first)
    }
}

struct NodeMissingView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text("Der Datensatz scheint nicht mehr zu existieren oder ist nicht synchronisiert.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}
