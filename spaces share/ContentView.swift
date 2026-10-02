import SwiftUI
import SpacesShareKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct ShareLogo: View {
    var size: CGFloat = 170
    var body: some View {
        Image("ShareLogo").resizable().scaledToFit().frame(width: size, height: size)
            .blendMode(.multiply)
            .accessibilityHidden(true)
    }
}
struct ContentView: View {
    @EnvironmentObject private var store: ShareStore
    @EnvironmentObject private var purchases: ShareMembershipStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var composer = false
    @State private var selectedFolder: SharedFolder?
    var body: some View {
        Group {
            if store.restoring {
                VStack(spacing: 20) { ShareLogo(); ProgressView("Connecting to Spacechat…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
            } else if store.account == nil {
                SignInScreen()
            } else if store.onboardingStep == .backup {
                RecoveryPhrasePage()
            } else if store.onboardingStep == .membership {
                MembershipPage()
            } else {
                NavigationStack {
                    Group { if store.showSettings { ShareSettings() } else { home } }
                        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                        .background(store.showSettings ? ShareTheme.canvas : .white)
                }
                .sheet(isPresented: $composer) { UploadSheet() }
                .sheet(item: $selectedFolder) { FolderDetail(folder: $0) }
            }
        }
        .foregroundStyle(ShareTheme.ink)
        .onChange(of: store.account == nil) { _, signedOut in
            if signedOut { composer = false; selectedFolder = nil; store.showSettings = false }
        }
        .onChange(of: scenePhase) { _, value in if value == .active { Task { await store.refreshAccount(); await purchases.reconcile(store: store) } } }
    }
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Spaces Share").font(ShareTheme.pageTitle)
                        Text("A little space. A simple link.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShareLogo(size: 52)
                }
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.person.crop").font(.title2).foregroundStyle(ShareTheme.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.membershipStatus).font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(store.policy.map { "\(store.folders.filter { $0.isActive() }.count) of \($0.limit) folders · \($0.member ? "No expiry available" : "10-minute links")" } ?? "Connecting your sharing account…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(ShareTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
                if let error = store.error {
                    ErrorCard(message: error) { Task { await store.refreshAccount() } }
                }
                if store.loading && store.folders.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(30) }
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let active = store.folders.filter { $0.isActive(at: timeline.date) }
                    if active.isEmpty && !store.loading {
                        VStack(spacing: 16) {
                            ShareLogo(size: 150)
                            Text("Share something good.").font(ShareTheme.heading)
                            Text("Photos, documents, or a little of both.\nKeep them together in one public link.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button { store.resetDraft(); composer = true } label: { Label("Create your first link", systemImage: "plus") }
                                .buttonStyle(ShareActionStyle()).disabled(store.policy == nil)
                        }.frame(maxWidth: .infinity).padding(.vertical, 18)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("YOUR LINKS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(active) { folder in
                                Button { selectedFolder = folder } label: { FolderRow(folder: folder) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(16).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .refreshable { await store.refreshAccount() }
        .toolbar(.hidden)
    }
    private var bottomBar: some View {
        HStack(spacing: 2) {
            Button { selectSettings(true) } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(store.showSettings ? ShareTheme.ink : ShareTheme.ink.opacity(0.32))
                    .frame(width: 54, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
            .accessibilityAddTraits(store.showSettings ? .isSelected : [])
            Button { store.resetDraft(); composer = true } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .medium))
                    .foregroundStyle(store.policy == nil || store.busy ? ShareTheme.ink.opacity(0.25) : ShareTheme.ink)
                    .frame(width: 54, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Create a sharing link")
            .disabled(store.policy == nil || store.busy)
            Button { selectSettings(false) } label: {
                Image(systemName: "house.fill")
                    .foregroundStyle(store.showSettings ? ShareTheme.ink.opacity(0.32) : ShareTheme.ink)
                    .frame(width: 54, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Home")
            .accessibilityAddTraits(store.showSettings ? [] : .isSelected)
        }
        .font(.system(size: 17, weight: .semibold))
        .buttonStyle(SharePressStyle())
        .padding(6)
        .background(ShareTheme.pill, in: Capsule())
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(store.showSettings ? ShareTheme.canvas : .white)
    }

    private func selectSettings(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)) {
            store.showSettings = value
        }
    }

}
struct FolderRow: View {
    let folder: SharedFolder
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "folder.fill").font(.system(size: 25)).foregroundStyle(ShareTheme.blue)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(folder.title).font(.system(.body, design: .rounded, weight: .semibold)).lineLimit(2)
                Text("\(folder.files.count) file\(folder.files.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                ExpiryLabel(folder: folder)
            }
            Spacer()
            Image(systemName: "arrow.up.right").font(.subheadline.weight(.medium)).foregroundStyle(ShareTheme.blue)
        }.padding(14).background(ShareTheme.canvas, in: RoundedRectangle(cornerRadius: 14))
    }
}
struct ExpiryLabel: View {
    let folder: SharedFolder
    var body: some View {
        if let date = folder.expiryDate {
            HStack(spacing: 4) { Image(systemName: "clock"); if date > Date() { Text("Expires in"); Text(date, style: .timer) } else { Text("Expired") } }
                .font(.caption).foregroundStyle(.secondary)
        } else { Label("No expiry", systemImage: "infinity").font(.caption).foregroundStyle(ShareTheme.blue) }
    }
}
struct ErrorCard: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.circle").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if let retry { Button("Try again", action: retry).font(.subheadline.weight(.semibold)) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
struct FolderDetail: View {
    @EnvironmentObject private var store: ShareStore
    @Environment(\.dismiss) private var dismiss
    let folder: SharedFolder
    @State private var confirmDelete = false
    @State private var copied = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ShareLogo(size: 105).frame(maxWidth: .infinity)
                    Text(folder.title).font(ShareTheme.pageTitle)
                    ExpiryLabel(folder: folder)
                    if folder.pinProtected == true { Label("PIN protected", systemImage: "lock.fill").font(.caption) }
                    Link("Open shared page", destination: store.publicURL(folder.url)).font(.subheadline.weight(.semibold))
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        if folder.isActive(at: timeline.date) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(store.publicURL(folder.url).absoluteString).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                                HStack {
                                    ShareLink(item: store.publicURL(folder.url)) { Label("Share link", systemImage: "square.and.arrow.up") }.buttonStyle(ShareActionStyle())
                                    Button { copyText(store.publicURL(folder.url).absoluteString); copied = true } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "link") }.buttonStyle(ShareActionStyle(prominent: false))
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 14))
                            ForEach(folder.files) { file in
                                Link(destination: store.publicURL(folder.pinProtected == true ? folder.url : file.url)) {
                                    HStack(spacing: 12) {
                                        Image(systemName: file.isPhoto ? "photo" : "doc.text").frame(width: 24)
                                        VStack(alignment: .leading, spacing: 4) { Text(file.name).lineLimit(2); Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }
                                        Spacer(); Image(systemName: "arrow.down.circle")
                                    }.padding(.vertical, 10)
                                }
                            }
                        } else { ErrorCard(message: "This link has expired. Create a new folder to share these files again.") }
                    }
                    Text("Recipients can download these files after entering the PIN, if one is set. Downloads already saved by recipients cannot be revoked.").font(.caption).foregroundStyle(.secondary)
                    Button("Delete folder and revoke link", role: .destructive) { confirmDelete = true }.disabled(store.busy)
                    if let error = store.error { ErrorCard(message: error) }
                }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(ShareTheme.canvas).navigationTitle("Shared folder").shareInlineTitle().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.shareSheetSize()
            .confirmationDialog("Delete this folder?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete folder", role: .destructive) { Task { await store.delete(folder); if !store.folders.contains(where: { $0.id == folder.id }) { dismiss() } } }
            } message: { Text("Its public link will stop working immediately.") }
    }
}
@MainActor func copyText(_ text: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = text
#else
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
#endif
}

private struct ShareSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
#if os(macOS)
        content.frame(minWidth: 400, idealWidth: 480, minHeight: 540, idealHeight: 680)
#else
        content
#endif
    }
}
extension View { func shareSheetSize() -> some View { modifier(ShareSheetSizing()) } }
