//
//  StatsComponents+KPI.swift
//  BrainMesh
//

import SwiftUI

// MARK: - KPI cards

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
