import SwiftUI
import UniformTypeIdentifiers

struct PhraseDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct SignInScreen: View {
    @State private var showPhrase = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 14) {
                    Text("SpaceShare")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                    ShareLogo(size: 150).padding(.bottom, 2)
                    Text("Sign in to share your photos and documents\nwith one simple link.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Button { showPhrase = true } label: {
                        Label("Continue with Spacechat phrase", systemImage: "key.fill")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 18).padding(.vertical, 14)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(SharePressStyle())
                    .overlay(Capsule().stroke(.black.opacity(0.18), lineWidth: 1.5))
                    .clipShape(Capsule()).frame(maxWidth: 300).padding(.top, 12)
                    Text("One account across Spacechat and Spaces.")
                        .font(.caption).foregroundStyle(ShareTheme.secondary)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(ShareTheme.ink)
                .padding(24).frame(maxWidth: 460)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .background(.white)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                HStack(spacing: 24) {
                    Link("Privacy", destination: URL(string: "https://www.spacechat.app/privacy")!)
                    Link("Terms", destination: URL(string: "https://www.spacechat.app/membership-terms")!)
                }.font(.caption)
                Text("Powered by Spacechat")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(ShareTheme.secondary)
            }.padding(.vertical, 16).frame(maxWidth: .infinity).background(.white)
        }
        .sheet(isPresented: $showPhrase) { PhraseSignIn() }
    }
}

struct PhraseSignIn: View {
    private enum Mode { case type, create }
    @EnvironmentObject private var store: ShareStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode?
    @State private var phrase = ""
    @State private var revealed = false
    @State private var importing = false
    @State private var exporting = false
    @State private var saved = false
    @State private var copied = false
    @State private var localError: String?

    private var title: String {
        switch mode {
        case nil: return "Spacechat Phrase"
        case .type: return "Enter Your Phrase"
        case .create: return "New Phrase"
        }
    }
    private var canContinue: Bool {
        !store.busy && SpacechatAuth.isValid(phrase)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if mode == nil { chooser } else { editor }
                    if let message = localError ?? store.error { ErrorCard(message: message) }
                }.padding(20).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            .background(ShareTheme.canvas.ignoresSafeArea())
            .navigationTitle(title).shareInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == nil ? "Cancel" : "Back") {
                        if mode == nil { dismiss() }
                        else { mode = nil; phrase = ""; saved = false; copied = false; clearError() }
                    }.disabled(store.busy)
                }
            }
        }
        .shareSheetSize().interactiveDismissDisabled(store.busy)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .text], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8192 else {
                    throw ShareError.message("Choose a small text file containing your phrase.")
                }
                let candidate = SpacechatAuth.normalize(try String(contentsOf: url, encoding: .utf8))
                guard SpacechatAuth.isValid(candidate) else {
                    throw ShareError.message("That file doesn't contain a 12 to 18 word phrase.")
                }
                phrase = candidate; mode = .type; revealed = false; clearError()
            } catch { localError = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: PhraseDocument(text: phrase), contentType: .plainText, defaultFilename: "spacechat-recovery-phrase") { result in
            switch result {
            case .success: saved = true
            case .failure(let error): localError = error.localizedDescription
            }
        }
    }

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Use your recovery phrase").font(ShareTheme.heading)
                Text("The same phrase works in Spacechat — it's one account across both.")
                    .font(.footnote).foregroundStyle(.black.opacity(0.6))
            }
            choice("Upload Existing Phrase", subtitle: "Pick a saved phrase file", icon: "square.and.arrow.up") {
                clearError(); importing = true
            }
            choice("Type Existing Phrase", subtitle: "Enter your 12 to 18 words", icon: "keyboard") {
                phrase = ""; revealed = true; mode = .type; clearError()
            }
            Divider().padding(.vertical, 2)
            choice("Create New Phrase", subtitle: "Generate 12 words and start fresh", icon: "sparkles", prominent: true) {
                phrase = SpacechatAuth.generatePhrase(); saved = false; revealed = true; mode = .create; clearError()
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .create ? "These 12 words are your new account. After signing in, you can view, download, and copy them." : "Enter the 12 to 18 words for your account.")
                .font(.footnote).foregroundStyle(.black.opacity(0.6))
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if revealed {
                        TextEditor(text: $phrase).frame(minHeight: 112).scrollContentBackground(.hidden)
                            .accessibilityLabel("Recovery phrase")
                    } else {
                        SecureField("12 to 18 words", text: $phrase).frame(minHeight: 112)
                            .accessibilityLabel("Recovery phrase, hidden")
                    }
                }
                .font(.system(.subheadline, design: .monospaced))
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                .privacySensitive().autocorrectionDisabled().disabled(store.busy)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onChange(of: phrase) { _, value in
                    let normalized = SpacechatAuth.normalizeForEditing(value)
                    if value != normalized { phrase = normalized }
                    copied = false
                    if mode == .create { saved = false }
                }
                HStack {
                    Button(revealed ? "Hide words" : "Show words") { revealed.toggle() }
                    Spacer()
                    Text("\(SpacechatAuth.wordCount(phrase))/18 words")
                        .foregroundStyle(SpacechatAuth.isValid(phrase) ? .green : ShareTheme.secondary)
                }.font(.caption).frame(minHeight: 36)
            }
            if mode == .create {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { phraseActions }
                    VStack(spacing: 10) { phraseActions }
                }.buttonStyle(ShareActionStyle(prominent: false))
                Label("Anyone with these words can access your account. Spacechat cannot recover a lost phrase.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button {
                clearError()
                Task { if await store.signIn(phrase) { phrase = ""; dismiss() } }
            } label: {
                HStack {
                    if store.busy { ProgressView().tint(.white) }
                    Text(store.busy ? "Signing in…" : (mode == .create ? "Create & Continue" : "Continue"))
                }.frame(maxWidth: .infinity)
            }.buttonStyle(ShareActionStyle()).disabled(!canContinue)
            Text("Your phrase is stored in this device's Keychain and used only to sign in to Spacechat.")
                .font(.caption2).foregroundStyle(ShareTheme.secondary)
        }
        .disabled(store.busy)
    }

    @ViewBuilder private var phraseActions: some View {
        Button { phrase = SpacechatAuth.generatePhrase(); saved = false; revealed = true } label: {
            Label("Generate", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
        }
        Button { copyRecoveryPhrase(phrase); copied = true } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
        }
        Button { exporting = true } label: {
            Label("Save", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
        }
    }

    private func choice(_ title: String, subtitle: String, icon: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text(subtitle).font(.caption).opacity(0.65)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).opacity(0.4)
            }
            .multilineTextAlignment(.leading).foregroundStyle(prominent ? .white : .black)
            .padding(14).frame(maxWidth: .infinity)
            .background(prominent ? Color.black : .white, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(SharePressStyle())
    }
    private func clearError() { localError = nil; store.error = nil }
}
