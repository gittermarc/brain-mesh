//
//  ProCenterView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 27.02.26.
//

import SwiftUI

struct ProCenterView: View {

    @EnvironmentObject private var proStore: ProEntitlementStore

    @State private var showPaywall: Bool = false
    @State private var selectedFeature: ProFeature = .moreGraphs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                features

                if let errorMessage = proStore.lastError {
                    ProStatusMessageCard(message: errorMessage)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("BrainMesh Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await proStore.refreshEntitlements()
            await proStore.loadProductsIfNeeded()
        }
        .sheet(isPresented: $showPaywall) {
            ProPaywallView(feature: selectedFeature)
                .environmentObject(proStore)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5)
                            }
                            .frame(width: 50, height: 50)

                        Image(systemName: "sparkles")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.tint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("BrainMesh Pro")
                            .font(.title3.weight(.semibold))

                        Text(statusSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                statusBadge
            }

            Text("Pro erweitert BrainMesh um mehr Arbeitsbereiche, Graph-Schutz und den quellenbasierten Chat mit deinem Graphen. Deine vorhandenen Daten bleiben erhalten; Kauf, Wiederherstellung und Verwaltung laufen sicher über den App Store.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aktionen")
                .font(.headline)

            if !proStore.isProActive {
                Button {
                    openPaywall(for: .moreGraphs)
                } label: {
                    Label("Pro freischalten", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(proStore.isPurchasing || proStore.isLoadingProducts)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await proStore.restorePurchases() }
                } label: {
                    Label("Wiederherstellen", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(proStore.isPurchasing)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    Label("Verwalten", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(proStore.entitlement == .unknown)
            }

            if proStore.isPurchasing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Kauf wird verarbeitet")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.top, 2)
            }

            Text("Abos verwaltest du jederzeit über deine Apple-ID. BrainMesh speichert keine Zahlungsdaten in der App.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.20), lineWidth: 0.5)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enthalten")
                .font(.headline)

            VStack(spacing: 12) {
                ProFeatureCard(
                    feature: .moreGraphs,
                    isProActive: proStore.isProActive,
                    onTap: { openPaywall(for: .moreGraphs) }
                )

                ProFeatureCard(
                    feature: .graphProtection,
                    isProActive: proStore.isProActive,
                    onTap: { openPaywall(for: .graphProtection) }
                )

                GraphChatProFeatureCard(
                    isProActive: proStore.isProActive,
                    onTap: { openPaywall(for: .chatWithGraph) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSubtitle: String {
        switch proStore.entitlement {
        case .unknown:
            return "Status wird geprüft"
        case .pro:
            return "Status: Aktiv"
        case .free:
            return "Status: Nicht aktiv"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch proStore.entitlement {
        case .unknown:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.85)
                Text("Prüfung")
            }
            .statusCapsule()
        case .pro:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .symbolRenderingMode(.hierarchical)
                Text("Aktiv")
            }
            .statusCapsule()
        case .free:
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                Text("Nicht aktiv")
            }
            .statusCapsule()
        }
    }

    private func openPaywall(for feature: ProFeature) {
        guard !proStore.isProActive else { return }
        selectedFeature = feature
        showPaywall = true
    }
}

private struct GraphChatProFeatureCard: View {
    let isProActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                            .frame(width: 50, height: 50)
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.tint)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(ProFeature.chatWithGraph.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("ON DEVICE")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Text(ProFeature.chatWithGraph.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                    if isProActive {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("In Pro enthalten")
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }

                HStack(spacing: 12) {
                    Label("Direkte Quellen", systemImage: "checkmark.seal")
                    Label("Sichtbare Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Text("Das Systemmodell wird nur auf unterstützten Geräten verwendet. Attachment-Inhalte und Cloud-Provider gehören nicht zu diesem MVP.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isProActive)
        .accessibilityElement(children: .combine)
    }
}

private struct ProStatusMessageCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Store-Status")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
        }
    }
}

private struct ProFeatureCard: View {
    let feature: ProFeature
    let isProActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.5)
                        }
                        .frame(width: 42, height: 42)

                    Image(systemName: icon)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(feature.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if isProActive {
                    Text("Inklusive")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color(.separator).opacity(0.20), lineWidth: 0.5)
                        }
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isProActive)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch feature {
        case .moreGraphs:
            return "square.grid.2x2.fill"
        case .graphProtection:
            return "lock.shield.fill"
        case .chatWithGraph:
            return "bubble.left.and.bubble.right"
        }
    }
}

private extension View {
    func statusCapsule() -> some View {
        self
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color(.separator).opacity(0.25), lineWidth: 0.5)
            }
            .foregroundStyle(.secondary)
    }
}

#Preview {
    NavigationStack {
        ProCenterView()
    }
    .environmentObject(ProEntitlementStore())
}
