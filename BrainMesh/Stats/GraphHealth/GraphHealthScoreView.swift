//
//  GraphHealthScoreView.swift
//  BrainMesh
//

import SwiftUI

struct GraphHealthScoreView: View {
    let presentation: GraphHealthCenterPresentation

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(presentation.scoreValue)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("/100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(presentation.scoreValue), total: 100)
                .frame(width: 92)
                .tint(.accentColor)

            Text(presentation.scoreTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health Score \(presentation.scoreValue) von 100, \(presentation.scoreTitle)")
    }
}
