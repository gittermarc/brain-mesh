//
//  NodeDetailShared+Connections.Card.swift
//  BrainMesh
//
//  Preview card (detail screen) for connections.
//

import SwiftUI

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
