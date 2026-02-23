//
//  StatsRows.swift
//  BrainMesh
//

import SwiftUI

// MARK: - Rows / lines

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
