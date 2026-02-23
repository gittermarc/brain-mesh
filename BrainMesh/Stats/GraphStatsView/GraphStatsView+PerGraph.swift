//
//  GraphStatsView+PerGraph.swift
//  BrainMesh
//

import Foundation
import SwiftUI

extension GraphStatsView {

    // MARK: - Legacy

    var hasLegacyData: Bool {
        guard let legacy = perGraph[nil] else { return false }
        return legacy.isEmpty == false
    }

    var legacyCard: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Unzugeordnet (Legacy)")
                        .font(.headline)
                    Spacer()
                }

                Text("Hier landet alles, was noch keine graphID hat. Normalerweise sollte das nach dem Bootstrap/Migration 0 sein.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                GraphStatsCompact(counts: perGraph[nil])
            }
        }
    }

    // MARK: - Per Graph

    var perGraphDisclosure: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup(isExpanded: $showPerGraph) {
                    VStack(spacing: 12) {
                        if let perGraphLoadError {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                                Text(perGraphLoadError)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.bottom, 4)
                        }

                        ForEach(uniqueGraphs) { g in
                            GraphStatsCard(
                                title: g.name,
                                subtitle: (g.id == activeGraphID) ? "Aktiv" : nil,
                                counts: perGraph[g.id]
                            )
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    HStack {
                        Text("Pro Graph")
                            .font(.headline)
                        Spacer()

                        if showPerGraph && isLoadingPerGraphCounts {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Text("\(uniqueGraphs.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}
