import SwiftUI
import SpacesShareKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct RecoveryPhrasePage: View {
    @EnvironmentObject private var store: ShareStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isOnboarding = true
    @State private var revealed = false
    @State private var exporting = false
    @State private var notice: String?
    private var phrase: String { SpacechatAuth.storedPhrase() ?? "" }
    private var hasPhrase: Bool { SpacechatAuth.isValid(phrase) }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 34, weight: .semibold)).foregroundStyle(ShareTheme.blue)
                    .frame(width: 84, height: 84).background(ShareTheme.blue.opacity(0.08), in: Circle())
                VStack(spacing: 7) {
                    Text("Save Your Phrase").font(ShareTheme.pageTitle)
                    Text("Download it, or write it on paper.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if hasPhrase {
                    phraseCard
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { actions }
                        VStack(spacing: 10) { actions }
                    }
                    .buttonStyle(ShareActionStyle(prominent: false))
                } else {
                    ErrorCard(message: "Your recovery phrase isn't available on this device. Sign in again to view and save it.")
                    Button("Return to sign in") { store.signOut() }.buttonStyle(ShareActionStyle())
                }
                if let notice { Text(notice).font(.caption).foregroundStyle(.secondary).accessibilityAddTraits(.updatesFrequently) }
                Label("Keep these words private. Anyone with your phrase can access your Spacechat account.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                if isOnboarding && hasPhrase {
                    Button { revealed = false; store.setOnboardingStep(.membership) } label: {
                        Label("I Saved It, Continue", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(ShareActionStyle())
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 32)
            .frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .background(.white)
        .fileExporter(isPresented: $exporting, document: PhraseDocument(text: phrase + "\n"), contentType: .plainText, defaultFilename: "spacechat-recovery-phrase") { result in
            revealed = false
            switch result {
            case .success: notice = "Recovery phrase downloaded."
            case .failure: notice = "Couldn't save the file. Try again or use Copy."
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
        .onDisappear { revealed = false }
    }

    private var phraseCard: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 8)], spacing: 8) {
            ForEach(Array(phrase.split(separator: " ").enumerated()), id: \.offset) { index, word in
                HStack(spacing: 7) {
                    Text("\(index + 1).").foregroundStyle(.secondary)
                    Text(revealed ? String(word) : "••••••")
                }
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(revealed ? "Word \(index + 1), \(word)" : "Word \(index + 1), hidden")
            }
        }
        .padding(14).background(ShareTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
        .privacySensitive()
    }

    @ViewBuilder private var actions: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { revealed.toggle(); notice = nil }
        } label: {
            Label(revealed ? "Hide" : "View", systemImage: revealed ? "eye.slash" : "eye")
                .frame(maxWidth: .infinity)
        }
        Button { exporting = true } label: {
            Label("Download", systemImage: "arrow.down.doc").frame(maxWidth: .infinity)
        }
        Button {
            copyRecoveryPhrase(phrase); notice = "Recovery phrase copied."
        } label: {
            Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
        }
    }
}

@MainActor func copyRecoveryPhrase(_ phrase: String) {
    #if canImport(UIKit)
    UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: phrase]], options: [
        .localOnly: true, .expirationDate: Date().addingTimeInterval(120)
    ])
    #else
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(phrase, forType: .string)
    let copiedChange = NSPasteboard.general.changeCount
    Task {
        try? await Task.sleep(for: .seconds(120))
        if NSPasteboard.general.changeCount == copiedChange { NSPasteboard.general.clearContents() }
    }
    #endif
}
