//
//  GraphStatsView+Header.swift
//  BrainMesh
//

import Foundation
import SwiftUI

extension GraphStatsView {

    // MARK: - Dashboard Header

    var dashboardHeader: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dashboard")
                            .font(.headline)

                        if let g = dashboardGraph {
                            HStack(spacing: 8) {
                                Text(g.name)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)

                                if g.id == activeGraphID {
                                    Text("Aktiv")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(.thinMaterial)
                                        )
                                }
                            }
                        } else {
                            Text("Kein Graph")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 14) {
                    InfoPill(icon: "square.stack.3d.up", text: "Graphen: \(uniqueGraphs.count)")
                    InfoPill(icon: "square.grid.2x2", text: "Knoten: \(formatInt(dashboardCounts?.entities, plus: dashboardCounts?.attributes))")
                    InfoPill(icon: "paperclip", text: "Anhänge: \(formatInt(dashboardCounts?.attachments))")
                }
            }
        }
    }
}
