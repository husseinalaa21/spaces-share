import SwiftUI
import SpacesShareKit

struct MembershipPage: View {
    @EnvironmentObject private var store: ShareStore
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(store.member ? "MembershipActiveCover" : "MembershipOfferCover")
                    .resizable().scaledToFit().accessibilityHidden(true)
                    .frame(maxWidth: 580)
                VStack(spacing: 22) {
                    if store.checkingMembership || (store.membership == nil && store.membershipError == nil) {
                        ProgressView("Checking your Spacechat membership…")
                            .padding(.vertical, 30)
                    } else if let error = store.membershipError {
                        Text("Let's check your membership").font(ShareTheme.heading)
                        ErrorCard(message: error) { Task { await store.refreshMembership() } }
                    } else if store.member {
                        Label("MEMBERSHIP ACTIVE", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(ShareTheme.blue)
                        Text("You're already a member.").font(ShareTheme.pageTitle)
                        Text("Your active Spacechat membership is ready to use in Spaces Share.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        membershipBenefits
                        if let expiry = store.membership?.prepaidInfo?.expiryDate {
                            Text("Current access through \(expiry.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button { store.finishMembershipPage() } label: {
                            Text("Continue").frame(maxWidth: .infinity)
                        }.buttonStyle(ShareActionStyle())
                    } else {
                        Text("More room to share.").font(ShareTheme.pageTitle)
                        Text("One Spacechat membership. More space for your photos, documents, and everything you share.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        membershipBenefits
                        Button { store.finishMembershipPage(openSettings: true) } label: {
                            Text("Subscribe").frame(maxWidth: .infinity)
                        }.buttonStyle(ShareActionStyle())
                            .accessibilityHint("Opens Settings to buy membership with Apple.")
                        Button("Continue with free account") { store.finishMembershipPage() }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24).padding(.bottom, 28).frame(maxWidth: 520)
            }.frame(maxWidth: .infinity)
        }
        .background(.white)
    }
    private var membershipBenefits: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("100 shared folders", systemImage: "folder")
            Label("Keep links without expiry", systemImage: "infinity")
            Label("Your existing Spacechat account", systemImage: "person.crop.circle")
        }
        .font(ShareTheme.rowTitle).foregroundStyle(ShareTheme.ink)
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(ShareTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
    }
}
