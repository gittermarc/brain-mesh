//
//  StatsComponents+Charts.swift
//  BrainMesh
//

import SwiftUI

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
