//
//  GraphStatsView+Trends.swift
//  BrainMesh
//

import Foundation
import SwiftUI

extension GraphStatsView {

    // MARK: - Trends (7 Tage)

    var trendsBreakdown: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Trends (7 Tage)")
                        .font(.headline)
                    Spacer()
                    if activeTrends == nil && loadError == nil {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let t = activeTrends {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        TrendMiniMetric(
                            icon: "link",
                            title: "Links",
                            labels: t.dayLabels,
                            values: t.linkCounts,
                            delta: t.linkDelta
                        )

                        TrendMiniMetric(
                            icon: "paperclip",
                            title: "Anhänge",
                            labels: t.dayLabels,
                            values: t.attachmentCounts,
                            delta: t.attachmentDelta
                        )
                    }
                } else {
                    PlaceholderBlock(text: "Trends werden geladen…")
                }
            }
        }
    }
}
