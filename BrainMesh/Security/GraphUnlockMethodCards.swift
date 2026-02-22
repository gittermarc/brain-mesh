//
//  GraphUnlockMethodCards.swift
//  BrainMesh
//

import SwiftUI

struct GraphUnlockBiometricsCard: View {
    let biometricsLabel: String
    let biometricsIcon: String
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GraphUnlockCardContainer {
                HStack(alignment: .center, spacing: 12) {
                    GraphUnlockMiniBadge(systemImage: biometricsIcon)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mit \(biometricsLabel) entsperren")
                            .font(.headline)
                        Text("Schnell & sicher")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    GraphUnlockTrailingIndicator(isWorking: isWorking, showsChevron: true)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(isWorking ? 0.85 : 1)
    }
}

struct GraphUnlockPasswordCard: View {
    @Binding var password: String
    let isWorking: Bool
    let onSubmit: () -> Void

    var body: some View {
        GraphUnlockCardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    GraphUnlockMiniBadge(systemImage: "key.fill")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Passwort")
                            .font(.headline)
                        Text("Alternativ per Passwort entsperren")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                SecureField("Passwort eingeben", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .onSubmit(onSubmit)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.quaternary)
                    }

                Button(action: onSubmit) {
                    HStack {
                        Text("Entsperren")
                        Spacer(minLength: 0)
                        GraphUnlockTrailingIndicator(isWorking: isWorking, showsChevron: false)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || trimmedPassword.isEmpty)
            }
        }
        .opacity(isWorking ? 0.95 : 1)
    }

    private var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GraphUnlockCardContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.quaternary)
            }
    }
}

private struct GraphUnlockMiniBadge: View {
    let systemImage: String

    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .frame(width: 40, height: 40)
                .overlay {
                    Circle().strokeBorder(.quaternary)
                }

            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .accessibilityHidden(true)
    }
}

private struct GraphUnlockTrailingIndicator: View {
    let isWorking: Bool
    let showsChevron: Bool

    var body: some View {
        ZStack {
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isWorking ? 0 : 1)
            }

            ProgressView()
                .controlSize(.small)
                .opacity(isWorking ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}
