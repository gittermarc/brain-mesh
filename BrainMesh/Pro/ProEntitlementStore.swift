//
//  ProEntitlementStore.swift
//  BrainMesh
//
//  Created by Marc Fechner on 27.02.26.
//

import Foundation
import StoreKit
import Combine

enum ProProductIDs {
    // You can override these in Info.plist.
    // Default values are "01" (monthly) and "02" (yearly) to match your App Store Connect preparation.
    static let monthlyInfoPlistKey = "BM_PRO_SUBSCRIPTION_ID_01"
    static let yearlyInfoPlistKey = "BM_PRO_SUBSCRIPTION_ID_02"

    static let monthlyFallback = "01"
    static let yearlyFallback = "02"

    static var monthly: String {
        (Bundle.main.object(forInfoDictionaryKey: monthlyInfoPlistKey) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
            ?? monthlyFallback
    }

    static var yearly: String {
        (Bundle.main.object(forInfoDictionaryKey: yearlyInfoPlistKey) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
            ?? yearlyFallback
    }

    static var all: [String] {
        // Keep order stable.
        [monthly, yearly].filter { !$0.isEmpty }
    }
}

@MainActor
final class ProEntitlementStore: ObservableObject {

    enum EntitlementState: Equatable {
        case unknown
        case free
        case pro
    }

    @Published private(set) var entitlement: EntitlementState = .unknown
    @Published private(set) var products: [Product] = []

    @Published private(set) var isLoadingProducts: Bool = false
    @Published private(set) var isPurchasing: Bool = false

    @Published private(set) var lastError: String? = nil

    var isProActive: Bool {
        entitlement == .pro
    }

    private let productIDs: [String]
    private var updatesTask: Task<Void, Never>?

    init(productIDs: [String]? = nil) {
        // Default arguments are evaluated at the call site (often nonisolated).
        // Resolve product ids inside the @MainActor initializer to avoid actor-isolation warnings.
        self.productIDs = productIDs ?? ProProductIDs.all

        updatesTask = Task {
            await listenForTransactions()
        }

        Task {
            await bootstrap()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func bootstrap() async {
        await refreshEntitlements()
        await loadProductsIfNeeded()
    }

    func loadProductsIfNeeded() async {
        guard !isLoadingProducts else { return }
        guard products.isEmpty else { return }
        await loadProducts()
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }

        isLoadingProducts = true
        lastError = nil
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: productIDs)
            products = fetched.sorted(by: ProEntitlementStore.productSort)
        } catch {
            lastError = "Produkte konnten nicht geladen werden."
            products = []
            print("⚠️ StoreKit products load failed: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }

        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending:
                // SCA / Ask to Buy
                break
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "Kauf fehlgeschlagen. Bitte versuche es erneut."
            print("⚠️ StoreKit purchase failed: \(error)")
        }
    }

    func restorePurchases() async {
        lastError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "Wiederherstellen fehlgeschlagen."
            print("⚠️ StoreKit restore failed: \(error)")
        }
    }

    func refreshEntitlements() async {
        var hasPro = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            guard productIDs.contains(transaction.productID) else { continue }

            // If revoked, ignore.
            if transaction.revocationDate != nil { continue }

            // If expired, ignore.
            if let exp = transaction.expirationDate, exp < Date() { continue }

            hasPro = true
            break
        }

        entitlement = hasPro ? .pro : .free
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? verified(result) else { continue }

            if productIDs.contains(transaction.productID) {
                await refreshEntitlements()
            }

            await transaction.finish()
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }

    private static func productSort(_ a: Product, _ b: Product) -> Bool {
        // Stable sort:
        // 1) Prefer auto-renewable subscriptions with known periods.
        // 2) Monthly before yearly (UI can still highlight yearly as "best value").
        let pa = a.subscription?.subscriptionPeriod
        let pb = b.subscription?.subscriptionPeriod

        switch (pa, pb) {
        case (nil, nil):
            return a.id < b.id
        case (nil, .some):
            return false
        case (.some, nil):
            return true
        case (.some(let x), .some(let y)):
            let wa = subscriptionWeight(x)
            let wb = subscriptionWeight(y)
            if wa != wb { return wa < wb }
            return a.id < b.id
        }
    }

    private static func subscriptionWeight(_ p: Product.SubscriptionPeriod) -> Int {
        // Lower = first
        switch p.unit {
        case .day:
            return 0
        case .week:
            return 1
        case .month:
            return 2
        case .year:
            return 3
        @unknown default:
            return 99
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
