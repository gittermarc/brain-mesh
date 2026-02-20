//
//  OnboardingStepCardView.swift
//  BrainMesh
//

import SwiftUI

struct OnboardingStepCardView: View {
    let number: Int?
    let title: String
    let subtitle: String
    let systemImage: String
    let isDone: Bool
    let actionTitle: String
    let actionEnabled: Bool
    let disabledHint: String
    let isOptional: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.thinMaterial)
                        .frame(width: 40, height: 40)

                    Image(systemName: isDone ? "checkmark" : systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isDone ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tint))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(numberTitle)
                            .font(.headline)

                        if isOptional {
                            Text("Optional")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                                .overlay {
                                    Capsule().strokeBorder(.quaternary)
                                }
                        }
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if isDone {
                Label("Erledigt", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Button(action: action) {
                    Label(actionTitle, systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!actionEnabled)

                if !actionEnabled {
                    Text(disabledHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.quaternary)
        }
    }

    private var numberTitle: String {
        if let number {
            return "\(number). \(title)"
        }
        return title
    }
}
