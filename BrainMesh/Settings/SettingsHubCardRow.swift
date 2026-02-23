//
//  SettingsHubCardRow.swift
//  BrainMesh
//
//  Created by Marc Fechner on 23.02.26.
//

import SwiftUI

struct SettingsHubCardRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsHubIconBadge(systemImage: systemImage)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsHubIconBadge: View {
    let systemImage: String

    var body: some View {
        ZStack {
            Circle()
                .fill(.thinMaterial)
                .frame(width: 40, height: 40)
                .overlay {
                    Circle()
                        .strokeBorder(.quaternary)
                }

            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .accessibilityHidden(true)
    }
}

private struct SettingsHubCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.quaternary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
    }
}

extension View {
    func settingsHubCardStyle(showsAccessoryChevron: Bool) -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.trailing, showsAccessoryChevron ? 18 : 0)
            .overlay(alignment: .trailing) {
                if showsAccessoryChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 24)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(SettingsHubCardBackground())
    }
}

#Preview {
    NavigationStack {
        List {
            NavigationLink {
                Text("Darstellung")
            } label: {
                SettingsHubCardRow(
                    systemImage: "paintpalette",
                    title: "Darstellung",
                    subtitle: "Look, Presets & Performance"
                )
            }
            .settingsHubCardStyle(showsAccessoryChevron: false)

            Button {
            } label: {
                SettingsHubCardRow(
                    systemImage: "square.and.arrow.down",
                    title: "Import",
                    subtitle: "Bild- und Video-Kompression"
                )
            }
            .buttonStyle(.plain)
            .settingsHubCardStyle(showsAccessoryChevron: true)
        }
        .navigationTitle("Einstellungen")
    }
}
