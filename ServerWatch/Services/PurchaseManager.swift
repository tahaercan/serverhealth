import Foundation
import StoreKit

/// Manages the user's "Pro" subscription state via StoreKit 2.
///
/// - Loads the single yearly subscription product from the App Store
/// - Listens for `Transaction.updates` so renewals / new purchases from
///   another device flip `isPro` automatically
/// - Exposes `purchase()` and `restore()` for the paywall to drive
///
/// Wire as `@StateObject` at the App root and share via `.environmentObject`.
@MainActor
final class PurchaseManager: ObservableObject {

    /// Single-tier subscription product ID. Must match the SKU created in
    /// App Store Connect under the "Server Health Pro" subscription group.
    static let productID = "com.serverhealth.app.pro.yearly"

    // MARK: - Published state

    @Published private(set) var product: Product?
    /// True when the user has an active Pro subscription (verified by Apple).
    @Published private(set) var isPro: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    /// Most recent purchase/restore error message for UI surfacing. Cleared
    /// on the next attempt.
    @Published var lastErrorMessage: String?

    // MARK: - Lifecycle

    private var updatesTask: Task<Void, Never>?

    init() {
        // Spin up the cross-device transaction listener immediately so we
        // don't miss a renewal that happens while the app is open.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                if case .verified(let txn) = result {
                    await self.refreshEntitlement()
                    await txn.finish()
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Product load + entitlement check

    /// Fetch the subscription product from the App Store. Idempotent.
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            self.product = products.first
        } catch {
            // Product not configured yet (during dev), or no network. Paywall
            // falls back to the default placeholder price; gating still works
            // because isPro reflects entitlement, not product availability.
            self.lastErrorMessage = error.localizedDescription
        }
        // Always refresh entitlement after load — covers fresh installs that
        // already have an active subscription (e.g. user reinstalled the app).
        await refreshEntitlement()
    }

    /// Re-check current entitlements with Apple. Sets `isPro` accordingly.
    func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result, txn.productID == Self.productID {
                entitled = true
                break
            }
        }
        self.isPro = entitled
    }

    // MARK: - Purchase flow

    func purchase() async {
        guard let product = product, !isPurchasing else { return }
        isPurchasing = true
        lastErrorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let txn):
                    await refreshEntitlement()
                    await txn.finish()
                case .unverified(_, let error):
                    lastErrorMessage = error.localizedDescription
                }
            case .userCancelled:
                break  // silent — user knows they tapped Cancel
            case .pending:
                // Ask-to-Buy / SCA — entitlement will flip via Transaction.updates
                break
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restore() async {
        lastErrorMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Display helpers

    /// Localized price + period, e.g. "$19.99 / year" or "₺499 / yıl".
    /// Falls back to a hard-coded marketing string when the product hasn't
    /// loaded yet so the paywall never renders blank.
    var priceText: String {
        guard let product = product else { return "$19.99 / year" }
        let perYear = String(localized: "/ year")
        return "\(product.displayPrice) \(perYear)"
    }

    /// Anchoring helper: same price divided by 12, formatted in the
    /// product's locale. Empty string when the product hasn't loaded.
    var monthlyEquivalentText: String {
        guard let product = product else { return "≈ $1.67 / month" }
        let monthly = (product.price / 12) as Decimal
        let formatted = monthly.formatted(product.priceFormatStyle)
        let perMonth = String(localized: "/ month")
        return "≈ \(formatted) \(perMonth)"
    }
}
