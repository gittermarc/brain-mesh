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

                if let e = proStore.lastError {
                    Text(e)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
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

            Text("Pro schaltet mehr Graphen frei und lässt dich Graphen schützen. Verwalten und Wiederherstellen geht hier – kaufen (falls nötig) direkt per Paywall.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .disabled(proStore.isPurchasing)
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
                    Text("Kauf läuft …")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.top, 2)
            }
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusSubtitle: String {
        switch proStore.entitlement {
        case .unknown:
            return "Status wird geprüft …"
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
                Text("Prüfe …")
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
