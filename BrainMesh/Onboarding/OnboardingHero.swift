//
//  OnboardingHero.swift
//  BrainMesh
//

import SwiftUI

struct OnboardingHeroView: View {
    let progress: OnboardingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            progressCard
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "circle.grid.cross")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.quaternary)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Willkommen in BrainMesh")
                        .font(.title2.weight(.bold))
                    Text("In 3 kleinen Schritten zum ersten sinnvollen Graphen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text("Keine Sorge: Du musst kein Graph-Theorie-Semester absolvieren. Du baust einfach dein Wissen wie LEGO zusammen – Node für Node.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fortschritt")
                    .font(.headline)
                Spacer()
                Text("\(progress.completedSteps)/\(progress.totalSteps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(progress.completedSteps), total: Double(progress.totalSteps))

            OnboardingMiniExplainerView()
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }
}
