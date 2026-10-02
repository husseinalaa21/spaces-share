import SwiftUI
import SpacesShareKit
import StoreKit

struct MembershipSettingsControls: View {
    @EnvironmentObject private var store: ShareStore
    @EnvironmentObject private var purchases: ShareMembershipStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: store.member ? "checkmark.seal.fill" : "star.circle")
                    .foregroundStyle(ShareTheme.blue).font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.membershipStatus).font(ShareTheme.rowTitle)
                    Text(store.member ? "100 folders · optional no expiry" : "Free: 10 folders · 10-minute links")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.checkingMembership || purchases.loading { ProgressView("Checking membership…").font(.caption) }
            if let error = store.membershipError { ErrorCard(message: error) { Task { await store.refreshMembership() } } }
            if store.member {
                if let expiry = store.membership?.prepaidInfo?.expiryDate {
                    Text("Access through \(expiry.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                }
                Link("Manage Apple subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    .font(.subheadline)
            } else if store.membership?.isConfirmed == true {
                Text("Spacechat membership gives you 100 shared folders and the option to keep links without expiry.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { Task { await purchases.buy(store: store) } } label: {
                    HStack {
                        if purchases.working { ProgressView().tint(.white) }
                        Text(purchases.working ? "Connecting to Apple…" : purchases.purchaseTitle)
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(ShareActionStyle())
                .disabled(!store.canOfferPurchase || purchases.product == nil || purchases.working || purchases.loading)
                if let product = purchases.product {
                    Text("\(product.displayPrice) per \(purchases.period). Charged to your Apple Account. Renews automatically until cancelled. Manage or cancel in your App Store settings.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let message = purchases.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { accountActions }
                VStack(alignment: .leading, spacing: 14) { accountActions }
            }.font(.caption.weight(.semibold)).disabled(purchases.working)
            if !store.member && purchases.product == nil && !purchases.loading {
                Button("Retry App Store connection") { Task { await purchases.prepare(store: store) } }
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
            }
            HStack(spacing: 18) {
                Link("Privacy", destination: URL(string: "https://www.spacechat.app/privacy")!)
                Link("Terms", destination: URL(string: "https://www.spacechat.app/membership-terms")!)
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .task(id: store.session) {
            await store.refreshMembership()
            if !store.member && store.membership?.isConfirmed == true { await purchases.prepare(store: store) }
        }
    }
    @ViewBuilder private var accountActions: some View {
        Button("Refresh membership") { Task { await store.refreshAccount() } }.frame(minHeight: 44)
        Button("Restore Purchases") { Task { await purchases.restore(store: store) } }.frame(minHeight: 44)
    }
}
