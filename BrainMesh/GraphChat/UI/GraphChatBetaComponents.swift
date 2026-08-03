//
//  GraphChatBetaComponents.swift
//  BrainMesh
//
//  Shared badge, navigation, and compact guidance for the Graph Chat beta.
//

import SwiftUI

struct GraphChatBetaBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let copy: GraphChatBetaCopy

    var body: some View {
        Text(copy.badgeText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.orange.opacity(backgroundOpacity))
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.orange.opacity(borderOpacity),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                    )
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHidden(
                GraphChatBetaNavigationAccessibilityContract
                    .exposesBadgeSeparately == false
            )
            .accessibilityIdentifier("graph-chat-beta-badge")
    }

    private var foregroundColor: Color {
        if colorScheme == .dark {
            return colorSchemeContrast == .increased
                ? Color(red: 1, green: 0.79, blue: 0.36)
                : Color(red: 1, green: 0.68, blue: 0.24)
        }
        return colorSchemeContrast == .increased
            ? Color(red: 0.49, green: 0.19, blue: 0)
            : Color(red: 0.64, green: 0.27, blue: 0)
    }

    private var backgroundOpacity: Double {
        colorSchemeContrast == .increased ? 0.24 : 0.14
    }

    private var borderOpacity: Double {
        colorSchemeContrast == .increased ? 0.9 : 0.5
    }
}

struct GraphChatBetaNavigationTitle: View {
    let copy: GraphChatBetaCopy

    var body: some View {
        HStack(spacing: 7) {
            Text(copy.navigationTitle)
                .font(.headline)
            GraphChatBetaBadge(copy: copy)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.navigationAccessibilityLabel)
        .accessibilityIdentifier("graph-chat-beta-navigation-title")
    }
}

struct GraphChatBetaNavigationModifier: ViewModifier {
    let copy: GraphChatBetaCopy
    let onOpenInfo: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    GraphChatBetaNavigationTitle(copy: copy)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onOpenInfo) {
                        Image(systemName: "info.circle")
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(copy.infoButtonLabel)
                    .accessibilityHint(copy.infoButtonHint)
                    .accessibilityIdentifier("graph-chat-beta-info")
                }
            }
    }
}

extension View {
    func graphChatBetaNavigation(
        copy: GraphChatBetaCopy,
        onOpenInfo: @escaping () -> Void
    ) -> some View {
        modifier(
            GraphChatBetaNavigationModifier(
                copy: copy,
                onOpenInfo: onOpenInfo
            )
        )
    }
}

struct GraphChatBetaCompactNoticeCard: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let copy: GraphChatBetaCopy
    let surface: GraphChatBetaExperienceSurface
    let onOpenInfo: () -> Void

    var body: some View {
        if GraphChatBetaExperiencePolicy.visibility(
            on: surface
        ).showsCompactNotice {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(copy.compactTitle)
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(copy.compactMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenInfo) {
                    Label(
                        copy.compactActionTitle,
                        systemImage: "info.circle"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(copy.compactActionHint)
                .accessibilityIdentifier("graph-chat-beta-card-info")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                Color.orange.opacity(
                                    colorSchemeContrast == .increased
                                        ? 0.12
                                        : 0.07
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        Color.orange.opacity(
                            colorSchemeContrast == .increased ? 0.75 : 0.32
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                    )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("graph-chat-beta-compact-notice")
        }
    }
}
