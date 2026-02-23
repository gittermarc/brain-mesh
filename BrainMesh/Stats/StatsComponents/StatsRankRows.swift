//
//  StatsRankRows.swift
//  BrainMesh
//

import SwiftUI

// MARK: - Ranked rows (media/structure) + per-graph card

struct LargestAttachmentRow: View {
    let item: GraphLargestAttachment

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconForKind(item.contentKind))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatBytes(Int64(item.byteCount)) ?? "—")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var detailLine: String {
        let ext = item.fileExtension
        let kind = kindLabel(item.contentKind)
        if ext == "?" { return kind }
        return "\(kind) • .\(ext)"
    }

    private func kindLabel(_ kind: AttachmentContentKind) -> String {
        switch kind {
        case .file: return "Datei"
        case .video: return "Video"
        case .galleryImage: return "Bild"
        }
    }

    private func iconForKind(_ kind: AttachmentContentKind) -> String {
        switch kind {
        case .file: return "doc"
        case .video: return "video"
        case .galleryImage: return "photo"
        }
    }
}

struct HubRow: View {
    let rank: Int
    let hub: GraphHubItem

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
                .monospacedDigit()

            Image(systemName: iconForKind(hub.kind))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(hub.label)
                    .lineLimit(1)
                Text("Degree: \(hub.degree)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func iconForKind(_ kind: NodeKind) -> String {
        switch kind {
        case .entity: return "cube"
        case .attribute: return "tag"
        }
    }
}

struct MediaNodeRow: View {
    let rank: Int
    let item: GraphMediaNodeItem

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)
                .monospacedDigit()

            Image(systemName: iconForKind(item.kind))
                .frame(width: 22)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .lineLimit(1)
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(item.mediaCount)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    private var detailLine: String {
        let header = item.headerImageCount > 0 ? "Header 1" : "Header 0"
        return "Anhänge: \(item.attachmentCount) • \(header)"
    }

    private func iconForKind(_ kind: NodeKind) -> String {
        switch kind {
        case .entity: return "cube"
        case .attribute: return "tag"
        }
    }
}

// MARK: - Per-Graph cards

struct GraphStatsCard: View {
    let title: String
    let subtitle: String?
    let counts: GraphCounts?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chart.bar")
                    .foregroundStyle(.secondary)
            }

            GraphStatsCompact(counts: counts)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

struct GraphStatsCompact: View {
    let counts: GraphCounts?

    var body: some View {
        VStack(spacing: 8) {
            StatsRow(icon: "square.grid.2x2", label: "Entitäten", value: counts?.entities)
            StatsRow(icon: "tag", label: "Attribute", value: counts?.attributes)
            StatsRow(icon: "link", label: "Links", value: counts?.links)
            StatsRow(icon: "note.text", label: "Notizen", value: counts?.notes)
            StatsRow(icon: "photo", label: "Bilder", value: counts?.images)
            StatsRow(icon: "paperclip", label: "Anhänge", value: counts?.attachments)
            StatsRowText(icon: "externaldrive", label: "Anhänge Größe", value: formatBytes(counts?.attachmentBytes))
        }
    }
}
