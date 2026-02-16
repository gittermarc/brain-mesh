//
//  NodeDetailShared+Connections.swift
//  BrainMesh
//
//  Shared connections UI and routing for Entity/Attribute detail screens.
//

import SwiftUI
import SwiftData

enum NodeLinkDirectionSegment: String, CaseIterable, Identifiable {
    case outgoing
    case incoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outgoing: return "Ausgehend"
        case .incoming: return "Eingehend"
        }
    }

    var systemImage: String {
        switch self {
        case .outgoing: return "arrow.up.right"
        case .incoming: return "arrow.down.left"
        }
    }
}

struct NodeConnectionsCard: View {
    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    let outgoing: [MetaLink]
    let incoming: [MetaLink]

    @Binding var segment: NodeLinkDirectionSegment
    let previewLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Verbindungen", systemImage: "link")

            Picker("", selection: $segment) {
                ForEach(NodeLinkDirectionSegment.allCases) { seg in
                    Label(seg.title, systemImage: seg.systemImage)
                        .tag(seg)
                }
            }
            .pickerStyle(.segmented)

            let links = (segment == .outgoing ? outgoing : incoming)
            if links.isEmpty {
                NodeEmptyStateRow(
                    text: segment == .outgoing ? "Keine ausgehenden Links." : "Keine eingehenden Links.",
                    ctaTitle: "Im Toolbelt hinzufügen",
                    ctaSystemImage: "link",
                    ctaAction: {}
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(links.prefix(previewLimit)) { link in
                        NavigationLink {
                            NodeLinkListDestinationView(link: link, direction: segment)
                        } label: {
                            NodeLinkRow(
                                direction: segment,
                                title: segment == .outgoing ? link.targetLabel : link.sourceLabel,
                                note: link.note
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    NodeConnectionsAllView(
                        ownerKind: ownerKind,
                        ownerID: ownerID,
                        graphID: graphID,
                        initialSegment: segment
                    )
                } label: {
                    Label("Alle", systemImage: "chevron.right")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}

private struct NodeLinkListDestinationView: View {
    let link: MetaLink
    let direction: NodeLinkDirectionSegment

    var body: some View {
        let kind: NodeKind = (direction == .outgoing ? link.targetKind : link.sourceKind)
        let id: UUID = (direction == .outgoing ? link.targetID : link.sourceID)

        return NodeDestinationView(kind: kind, id: id)
    }
}

private struct NodeLinkRow: View {
    let direction: NodeLinkDirectionSegment
    let title: String
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct NodeConnectionsAllView: View {
    @Environment(\.modelContext) private var modelContext

    let ownerKind: NodeKind
    let ownerID: UUID
    let graphID: UUID?

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @State private var segment: NodeLinkDirectionSegment

    init(ownerKind: NodeKind, ownerID: UUID, graphID: UUID?, initialSegment: NodeLinkDirectionSegment = .outgoing) {
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.graphID = graphID
        _segment = State(initialValue: initialSegment)

        _outgoingLinks = NodeLinksQueryBuilder.outgoingLinksQuery(kind: ownerKind, id: ownerID, graphID: graphID)
        _incomingLinks = NodeLinksQueryBuilder.incomingLinksQuery(kind: ownerKind, id: ownerID, graphID: graphID)
    }

    var body: some View {
        List {
            Section {
                Picker("", selection: $segment) {
                    ForEach(NodeLinkDirectionSegment.allCases) { seg in
                        Label(seg.title, systemImage: seg.systemImage)
                            .tag(seg)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(currentLinks) { link in
                    NavigationLink {
                        NodeDestinationView(kind: targetKind(for: link), id: targetID(for: link))
                    } label: {
                        NodeLinkListRow(direction: segment, title: targetLabel(for: link), note: link.note)
                    }
                }
                .onDelete(perform: deleteLinks)
            }
        }
        .navigationTitle("Verbindungen")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }

    private var currentLinks: [MetaLink] {
        segment == .outgoing ? outgoingLinks : incomingLinks
    }

    private func targetKind(for link: MetaLink) -> NodeKind {
        segment == .outgoing ? link.targetKind : link.sourceKind
    }

    private func targetID(for link: MetaLink) -> UUID {
        segment == .outgoing ? link.targetID : link.sourceID
    }

    private func targetLabel(for link: MetaLink) -> String {
        segment == .outgoing ? link.targetLabel : link.sourceLabel
    }

    private func deleteLinks(at offsets: IndexSet) {
        let list = currentLinks
        for idx in offsets {
            guard list.indices.contains(idx) else { continue }
            modelContext.delete(list[idx])
        }
        try? modelContext.save()
    }
}

private struct NodeLinkListRow: View {
    let direction: NodeLinkDirectionSegment
    let title: String
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: direction.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

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
