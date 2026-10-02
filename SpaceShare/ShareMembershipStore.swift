import Foundation
import Combine
import StoreKit
import SpaceShareKit

@MainActor final class ShareMembershipStore: ObservableObject {
    @Published private(set) var product: Product?
    @Published private(set) var loading = false
    @Published private(set) var working = false
    @Published private(set) var message: String?
    private var configuration: MembershipPurchaseConfiguration?
    private var observer: Task<Void, Never>?
    private var identity = UUID()
    private var processing = Set<UInt64>()

    func reset() {
        identity = UUID(); observer?.cancel(); observer = nil
        product = nil; configuration = nil; message = nil
        loading = false; working = false; processing = []
    }
    deinit { observer?.cancel() }

    func prepare(store: ShareStore) async {
        guard !loading, let session = store.session else { return }
        let version = identity
        loading = true; message = nil
        defer { if identity == version { loading = false } }
        do {
            let config = try await store.purchaseConfiguration()
            guard store.session == session, identity == version else { return }
            // The server advertises readiness before Apple can charge anyone.
            configuration = config
            let products = try await Product.products(for: [config.productId])
            guard store.session == session, identity == version else { return }
            product = products.first { $0.id == config.productId && $0.type == .autoRenewable }
            if product == nil { message = "Membership isn't available from the App Store right now. Please try again later." }
        } catch {
            if identity == version { message = "Membership purchases aren't available right now. Check your connection and try again." }
        }
    }

    func observe(store: ShareStore) {
        guard observer == nil else { return }
        let version = identity
        observer = Task { [weak self, weak store] in
            for await result in Transaction.updates {
                guard !Task.isCancelled, let self, let store, self.identity == version, store.session != nil else { return }
                do {
                    guard case .verified(let transaction) = result,
                          transaction.productID == "spaces_share_vip_monthly" else { continue }
                    if transaction.revocationDate != nil || (transaction.expirationDate ?? .distantPast) <= .now {
                        await self.reconcile(store: store); continue
                    }
                    if self.configuration == nil { await self.prepare(store: store) }
                    try await self.complete(result, store: store)
                } catch { if self.identity == version { self.message = error.localizedDescription } }
            }
        }
    }

    func buy(store: ShareStore) async {
        guard !working, let session = store.session else { return }
        let version = identity
        working = true; message = nil
        defer { if identity == version { working = false } }
        await store.refreshMembership()
        guard identity == version, store.session == session else { return }
        // A failed check is not a free account. Never sell a second membership
        // when Spacechat already confirms this account is paid.
        guard store.canOfferPurchase else {
            message = store.member ? "Your Spacechat membership is already active." : "Check your membership before purchasing."
            return
        }
        if configuration == nil || product == nil { await prepare(store: store) }
        guard identity == version, store.session == session,
              let config = configuration, let product else { return }
        do {
            if try await synchronizeExisting(store: store) { return }
            guard identity == version, store.session == session else { return }
            let result = try await product.purchase(options: [.appAccountToken(config.appAccountToken)])
            guard identity == version, store.session == session else { return }
            switch result {
            case .success(let verification): try await complete(verification, store: store)
            case .userCancelled: message = nil
            case .pending: message = "Your purchase is pending approval. Your membership will update when Apple approves it."
            @unknown default: message = "The purchase couldn't be completed. Please try again."
            }
        } catch {
            if identity == version { message = error.localizedDescription }
        }
    }

    func restore(store: ShareStore) async {
        guard !working, let session = store.session else { return }
        let version = identity
        working = true; message = nil
        defer { if identity == version { working = false } }
        do {
            await store.refreshMembership()
            guard identity == version, store.session == session else { return }
            if store.member { message = "Your existing Spacechat membership is active."; return }
            if configuration == nil { await prepare(store: store) }
            guard configuration != nil, identity == version, store.session == session else { return }
            try await AppStore.sync()
            guard identity == version, store.session == session else { return }
            let restored = try await synchronizeExisting(store: store)
            if !restored {
                await store.refreshAccount()
                guard identity == version, store.session == session else { return }
                message = store.member ? "Your membership is active." : "No SpaceShare subscription was found for this Apple Account. Memberships bought in Spacechat are loaded when you sign in with the same recovery phrase."
            }
        } catch {
            if identity == version { message = error.localizedDescription }
        }
    }

    func reconcile(store: ShareStore) async {
        // Latest includes expired/refunded transactions, so stale benefits can be
        // removed as well as renewed. Nothing is granted solely on this device.
        guard !working, let session = store.session else { return }
        let version = identity
        guard let result = await Transaction.latest(for: "spaces_share_vip_monthly"),
              case .verified(let transaction) = result else { return }
        do {
            let config = try await store.purchaseConfiguration()
            guard identity == version, store.session == session,
                  transaction.appAccountToken == config.appAccountToken else { return }
            configuration = config
            try await store.activateMembership(productID: transaction.productID, transactionID: String(transaction.id),
                originalID: String(transaction.originalID), signedTransaction: result.jwsRepresentation, expectedSession: session, syncOnly: true)
            await transaction.finish()
        } catch { if identity == version { message = "Your Apple membership needs to sync. Open Settings and use Restore Purchases to retry." } }
    }

    private func synchronizeExisting(store: ShareStore) async throws -> Bool {
        guard let config = configuration else { return false }
        var found = false
        var handled = Set<UInt64>()
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result,
               transaction.productID == config.productId,
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantPast) > .now {
                try await complete(result, store: store); handled.insert(transaction.id); found = true
            }
        }
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == config.productId,
               transaction.revocationDate == nil,
               (transaction.expirationDate ?? .distantPast) > .now,
               !handled.contains(transaction.id) {
                try await complete(result, store: store); found = true
            }
        }
        return found
    }

    private func complete(_ verification: VerificationResult<Transaction>, store: ShareStore) async throws {
        guard let config = configuration, let session = store.session else { throw ShareError.signedOut }
        guard case .verified(let transaction) = verification else {
            throw ShareError.message("Apple couldn't verify this purchase. Please try Restore Purchases.")
        }
        guard transaction.productID == config.productId,
              transaction.appAccountToken == config.appAccountToken else {
            throw ShareError.message("This Apple membership belongs to another Spacechat account. Sign in with that account's recovery phrase to restore it.")
        }
        guard transaction.revocationDate == nil, (transaction.expirationDate ?? .distantPast) > .now else {
            throw ShareError.message("This subscription is no longer active.")
        }
        guard !processing.contains(transaction.id) else { return }
        processing.insert(transaction.id)
        defer { processing.remove(transaction.id) }
        try await store.activateMembership(productID: transaction.productID, transactionID: String(transaction.id),
            originalID: String(transaction.originalID), signedTransaction: verification.jwsRepresentation, expectedSession: session)
        // Finish only once the same Spacechat account has received its benefits.
        await transaction.finish()
        if store.session == session {
            message = "Your membership is active."
            if store.onboardingStep != .backup { store.setOnboardingStep(.membership) }
        }
    }

    var purchaseTitle: String {
        guard let product else { return "Subscribe with Apple" }
        return "Subscribe · \(product.displayPrice) / \(period)"
    }
    var period: String {
        guard let value = product?.subscription?.subscriptionPeriod else { return "month" }
        let unit: String
        switch value.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return value.value == 1 ? unit : "\(value.value) \(unit)s"
    }
}
