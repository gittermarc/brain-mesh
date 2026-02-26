//
//  SettingsHubTile.swift
//  BrainMesh
//
//  Created by Marc Fechner on 26.02.26.
//

import SwiftUI

struct SettingsHubTile: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let showsAccessoryIndicator: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                SettingsHubTileIconBadge(systemImage: systemImage)

                Spacer(minLength: 0)

                if showsAccessoryIndicator {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsHubTileIconBadge: View {
    let systemImage: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5)
                }
                .frame(width: 42, height: 42)

            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .accessibilityHidden(true)
    }
}

struct SettingsHubTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink {
                    Text("Darstellung")
                } label: {
                    SettingsHubTile(
                        systemImage: "paintpalette",
                        title: "Darstellung",
                        subtitle: "Look, Presets & Performance",
                        showsAccessoryIndicator: false
                    )
                }
                .buttonStyle(SettingsHubTileButtonStyle())

                Button {
                } label: {
                    SettingsHubTile(
                        systemImage: "square.and.arrow.down",
                        title: "Import",
                        subtitle: "Bild- und Video-Kompression",
                        showsAccessoryIndicator: true
                    )
                }
                .buttonStyle(SettingsHubTileButtonStyle())
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
