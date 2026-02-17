//
//  StatsComponents.swift
//  BrainMesh
//

import Foundation
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

// MARK: - Mini charts + Trends

struct TrendMiniMetric: View {
    let icon: String
    let title: String
    let labels: [String]
    let values: [Int]
    let delta: GraphTrendDelta

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(delta.current)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                Text(deltaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            MiniBarChart(values: values)
                .frame(height: 28)
                .accessibilityLabel("\(title) pro Tag")

            if labels.count == values.count {
                HStack {
                    Text(labels.first ?? "")
                    Spacer()
                    Text(labels.last ?? "")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private var deltaText: String {
        let current = delta.current
        let previous = delta.previous

        if previous == 0 {
            if current == 0 { return "vs davor: —" }
            return "vs davor: neu"
        }

        let diff = current - previous
        let sign = diff > 0 ? "+" : ""
        let pct = Int((Double(diff) / Double(previous) * 100).rounded())
        let pctSign = pct > 0 ? "+" : ""
        return "vs davor: \(sign)\(diff) (\(pctSign)\(pct)%)"
    }
}

struct MiniBarChart: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(1, values.max() ?? 1)
            let width = geo.size.width
            let height = geo.size.height
            let spacing: CGFloat = 4
            let count = max(1, values.count)
            let barWidth = (width - CGFloat(count - 1) * spacing) / CGFloat(count)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    let ratio = CGFloat(v) / CGFloat(maxVal)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.secondary.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(.primary.opacity(0.65))
                                .frame(height: max(2, height * ratio)),
                            alignment: .bottom
                        )
                        .frame(width: barWidth)
                        .accessibilityValue("\(v)")
                }
            }
        }
    }
}

struct MiniLineChart: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = values.count

            if count <= 1 {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.secondary.opacity(0.25))
            } else {
                let minV = values.min() ?? 0
                let maxV = values.max() ?? 1
                let span = max(0.000_001, maxV - minV)

                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.secondary.opacity(0.18))

                    Path { path in
                        for i in 0..<count {
                            let x = w * CGFloat(i) / CGFloat(count - 1)
                            let norm = (values[i] - minV) / span
                            let y = h - h * CGFloat(norm)
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(.primary.opacity(0.65), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
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

// MARK: - Formatting helpers

func formatBytes(_ bytes: Int64?) -> String? {
    guard let bytes else { return nil }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

func formatInt(_ value: Int?) -> String {
    guard let value else { return "—" }
    return "\(value)"
}

func formatInt(_ a: Int?, plus b: Int?) -> String {
    guard let a, let b else { return "—" }
    return "\(a + b)"
}

func formatRatio(numerator: Int, denominator: Int) -> String {
    if denominator <= 0 { return "—" }
    let value = Double(numerator) / Double(denominator)
    let rounded = (value * 100).rounded() / 100
    return "\(rounded)"
}
