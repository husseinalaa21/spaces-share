import SwiftUI
import UniformTypeIdentifiers
struct ShareSettings: View {
    @EnvironmentObject private var store: ShareStore
    @State private var signOut = false
    @State private var phrase = false
    @EnvironmentObject private var purchases: ShareMembershipStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(ShareTheme.pageTitle)
                    Text("@\(store.account?.username ?? "")").font(.footnote).foregroundStyle(ShareTheme.secondary)
                }
                section("ACCOUNT") {
                    row("person.crop.circle", "Signed in as", "Spacechat phrase account · @\(store.account?.username ?? "")")
                    Button { phrase = true } label: { row("key.fill", "Recovery phrase", "View, download, or copy your phrase", chevron: true) }.buttonStyle(.plain)
                    row("icloud", "Cloud storage", "Photos and documents stored with Spacechat")
                }
                section("MEMBERSHIP") {
                    MembershipSettingsControls()
                }
                if let error = store.error { ErrorCard(message: error) }
                section("ABOUT") {
                    link("lifepreserver", "Support", "Help with your account and files", "https://www.spacechat.app/contact-us")
                    link("hand.raised", "Privacy Policy", "How Spacechat handles your data", "https://www.spacechat.app/privacy")
                    link("doc.text", "Terms of Use", "Spacechat membership and service terms", "https://www.spacechat.app/membership-terms")
                    link("person.crop.circle.badge.minus", "Delete Spacechat account", "Request deletion of your Spacechat account", "https://www.spacechat.app/account-deletion")
                }
                Button { signOut = true } label: { row("rectangle.portrait.and.arrow.right", "Sign out", "Return to sign-in on this device") }.buttonStyle(.plain).foregroundStyle(.red)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                VStack(spacing: 6) {
                    ShareLogo(size: 60)
                    Text("SpaceShare · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")").font(.caption)
                    Text("Powered by Spacechat").font(.caption2)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 4)
            }.padding(16).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.toolbar(.hidden).background(ShareTheme.canvas)
            .confirmationDialog("Sign out of this account?", isPresented: $signOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { store.signOut() }
            } message: { Text("Save your recovery phrase first. Your links stay active until they expire or you delete them.") }
            .sheet(isPresented: $phrase) { RecoverySheet() }
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
            VStack(spacing: 0, content: content).background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }
    private func row(_ icon: String, _ title: String, _ subtitle: String, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(ShareTheme.blue).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if chevron { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
        }.padding(14).contentShape(Rectangle())
    }
    private func link(_ icon: String, _ title: String, _ subtitle: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) { row(icon, title, subtitle, chevron: true) }.buttonStyle(.plain)
    }
}
struct RecoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            RecoveryPhrasePage(isOnboarding: false)
                .navigationTitle("Recovery phrase").shareInlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.shareSheetSize()
    }
}
