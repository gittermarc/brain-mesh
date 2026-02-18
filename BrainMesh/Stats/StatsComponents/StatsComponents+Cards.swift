//
//  StatsComponents+Cards.swift
//  BrainMesh
//

import SwiftUI

// MARK: - Small UI building blocks

struct StatsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
            )
    }
}

struct InfoPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

struct KPICard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?
    let sparkline: [Double]?
    let sparklineLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let sparkline, sparkline.isEmpty == false {
                MiniLineChart(values: sparkline)
                    .frame(height: 24)
                    .accessibilityLabel(sparklineLabel ?? title)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

struct PlaceholderBlock: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct StatLine: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

struct BreakdownRow: View {
    let icon: String
    let label: String
    let count: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 22)
                    .foregroundStyle(.secondary)
                Text(label)
                Spacer()
                Text("\(count)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            ProgressView(value: Double(count), total: Double(max(1, total)))
        }
    }
}

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
    }
}

// MARK: - Media/Structure rows

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

struct StatsRow: View {
    let icon: String
    let label: String
    let value: Int?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            if let value {
                Text("\(value)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            } else {
                Text("—")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatsRowText: View {
    let icon: String
    let label: String
    let value: String?

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
            Spacer()
            if let value {
                Text(value)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            } else {
                Text("—")
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
