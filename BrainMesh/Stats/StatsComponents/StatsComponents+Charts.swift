//
//  StatsComponents+Charts.swift
//  BrainMesh
//

import SwiftUI

// MARK: - Trends

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
