//
//  GraphStatsView+Structure.swift
//  BrainMesh
//

import Foundation
import SwiftUI

extension GraphStatsView {

    // MARK: - Structure Breakdown

    var structureBreakdown: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Graph-Struktur")
                        .font(.headline)
                    Spacer()
                }

                if let s = activeStructure {
                    VStack(alignment: .leading, spacing: 10) {
                        StatLine(icon: "square.grid.2x2", label: "Knoten", value: "\(s.nodeCount)")
                        StatLine(icon: "link", label: "Links", value: "\(s.linkCount)")

                        Divider()

                        let isolated = s.isolatedNodeCount
                        let nodes = max(1, s.nodeCount)
                        let connected = max(0, nodes - isolated)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Isolierte Knoten")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(isolated)")
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                            ProgressView(value: Double(connected), total: Double(nodes))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Top Hubs")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if s.topHubs.isEmpty {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(Array(s.topHubs.enumerated()), id: \.element.id) { index, hub in
                                        HubRow(rank: index + 1, hub: hub)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    PlaceholderBlock(text: "Struktur wird berechnet…")
                }
            }
        }
    }
}
