//
//  ProPaywallView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 27.02.26.
//

import SwiftUI
import StoreKit

struct ProPaywallView: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var proStore: ProEntitlementStore

    let feature: ProFeature

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    header

                    benefits

                    products

                    actions

                    footnotes
                }
                .padding(16)
            }
            .navigationTitle("BrainMesh Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .task {
                await proStore.loadProductsIfNeeded()
                await proStore.refreshEntitlements()
            }
            .onChange(of: proStore.isProActive) { _, isPro in
                if isPro {
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(feature.title)
                .font(.title2.weight(.semibold))

            Text(feature.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if proStore.isProActive {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Pro ist aktiv")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inklusive")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(feature.bullets, id: \.self) { b in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                        Text(b)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var products: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Abo wählen")
                .font(.headline)

            if proStore.isLoadingProducts {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lade Preise …")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            } else if proStore.products.isEmpty {
                Text("Keine Produkte verfügbar.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 12) {
                    ForEach(proStore.products, id: \.id) { p in
                        ProProductCard(
                            product: p,
                            isBestValue: p.id == ProProductIDs.yearly,
                            isPurchasing: proStore.isPurchasing,
                            onPurchase: {
                                Task { await proStore.purchase(p) }
                            }
                        )
                    }
                }
            }

            if let e = proStore.lastError {
                Text(e)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await proStore.restorePurchases() }
            } label: {
                Label("Käufe wiederherstellen", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(proStore.isPurchasing)

            Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                Label("Abo verwalten", systemImage: "gear")
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hinweise")
                .font(.headline)

            Text("• Du kannst jederzeit kündigen – der Zugriff bleibt bis zum Ende der Laufzeit bestehen.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("• Entsperren geschützter Graphen bleibt immer möglich (auch ohne Pro).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProProductCard: View {

    let product: Product
    let isBestValue: Bool
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    if let s = subtitle {
                        Text(s)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isBestValue {
                    Text("Best Value")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text(product.displayPrice)
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    onPurchase()
                } label: {
                    Label("Kaufen", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPurchasing)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var title: String {
        if let period = product.subscription?.subscriptionPeriod {
            return period.localizedTitle
        }
        return "Abo"
    }

    private var subtitle: String? {
        if let period = product.subscription?.subscriptionPeriod {
            return period.localizedSubtitle
        }
        return nil
    }
}

private extension Product.SubscriptionPeriod {

    var localizedTitle: String {
        switch unit {
        case .month:
            return value == 1 ? "Monatlich" : "Alle \(value) Monate"
        case .year:
            return value == 1 ? "Jährlich" : "Alle \(value) Jahre"
        case .week:
            return value == 1 ? "Wöchentlich" : "Alle \(value) Wochen"
        case .day:
            return value == 1 ? "Täglich" : "Alle \(value) Tage"
        @unknown default:
            return "Abo"
        }
    }

    var localizedSubtitle: String? {
        switch unit {
        case .month:
            return "Perfekt zum Starten"
        case .year:
            return "Sparen im Jahresabo"
        case .week, .day:
            return nil
        @unknown default:
            return nil
        }
    }
}
