import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import SpacesShareKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
struct UploadSheet: View {
    @EnvironmentObject private var store: ShareStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var files: [SelectedFile] = []
    @State private var photos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var reading = false
    @State private var permanent = false
    @State private var usePIN = false
    @State private var pin = ""
    @State private var error: String?
    @State private var result: SharedFolder?
    @State private var confirmReplacement = false
    @State private var publishing: Task<Void, Never>?
    private var supported: [UTType] { ["pdf", "txt", "csv", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "jpg", "jpeg", "png", "gif", "webp", "heic", "heif"].compactMap { UTType(filenameExtension: $0) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let result {
                        VStack(spacing: 18) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(ShareTheme.blue)
                            Text("Your link is ready.").font(ShareTheme.heading)
                            Text(store.publicURL(result.url).absoluteString).font(.footnote).textSelection(.enabled).foregroundStyle(.secondary)
                            ShareLink(item: store.publicURL(result.url)) { Label("Share link", systemImage: "square.and.arrow.up") }.buttonStyle(ShareActionStyle())
                            Button("Copy link") { copyText(store.publicURL(result.url).absoluteString) }.buttonStyle(ShareActionStyle(prominent: false))
                            ExpiryLabel(folder: result)
                            if result.pinProtected == true { Label("PIN protected · send your PIN separately", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                            Link("Open shared page", destination: store.publicURL(result.url)).font(.subheadline.weight(.semibold))
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        Text("Bring your files together.").font(ShareTheme.heading)
                        Text("Upload a single file or a collection. Choose an open link or protect your files with a PIN.").font(.subheadline).foregroundStyle(.secondary)
                        TextField("Folder name", text: $title).textFieldStyle(.plain).padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                        HStack(spacing: 12) {
                            Button { importing = true } label: { pickerLabel("Documents", icon: "doc.badge.plus") }
                            PhotosPicker(selection: $photos, maxSelectionCount: max(1, store.maxFiles - files.count), matching: .images) { pickerLabel("Photos", icon: "photo.on.rectangle.angled") }
                        }.buttonStyle(SharePressStyle()).disabled(reading || store.busy || files.count >= store.maxFiles)
                        Text("Up to \(store.maxFiles) files per folder · 3 MB per file").font(.caption).foregroundStyle(.secondary)
                        if reading { ProgressView("Preparing files…") }
                        if !files.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(files) { file in
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc").foregroundStyle(ShareTheme.blue)
                                        VStack(alignment: .leading, spacing: 4) { Text(file.name).font(.subheadline).lineLimit(2); Text(file.sizeLabel).font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        Button { files.removeAll { $0.id == file.id } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Remove \(file.name)")
                                    }.padding(14)
                                    if file.id != files.last?.id { Divider().padding(.horizontal, 14) }
                                }
                            }.background(.white, in: RoundedRectangle(cornerRadius: 14))
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Link expiry", systemImage: "clock").font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Picker("Link expiry", selection: $permanent) {
                                Text("10 minutes").tag(false)
                                if store.member { Text("No expiry").tag(true) }
                            }.pickerStyle(.segmented)
                            if !store.member { Label("Members can keep links without expiry.", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary) }
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: $usePIN) { Label("Protect with a PIN", systemImage: "lock") }.disabled(store.policy?.supportsPIN != true)
                            if store.policy?.supportsPIN != true { Text("PIN protection is currently unavailable. Refresh and try again.").font(.caption).foregroundStyle(.secondary) }
                            if usePIN {
                                SecureField("4–8 digit PIN", text: $pin)
                                    .textContentType(.newPassword)
                                    .sharePINKeyboard()
                                    .padding(14).background(ShareTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
                                Text("Send the PIN separately. Recipients need it to view or download any file in this link.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 14))
                        if store.busy {
                            ProgressView(value: store.uploadProgress)
                            Text(store.uploadStatus).font(.caption).foregroundStyle(.secondary)
                        }
                        if let error { ErrorCard(message: error) }
                        Button {
                            if store.folders.filter({ $0.isActive() }).count >= (store.policy?.limit ?? 10) { confirmReplacement = true }
                            else { publish() }
                        } label: {
                            Label(store.busy ? "Creating your link…" : "Create public link", systemImage: "link").frame(maxWidth: .infinity)
                        }.buttonStyle(ShareActionStyle()).disabled(files.isEmpty || reading || store.busy || store.policy == nil || (usePIN && pin.range(of: "^[0-9]{4,8}$", options: .regularExpression) == nil))
                        Text("At your folder limit, creating a new link removes your oldest folder and revokes its link.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .disabled(store.busy)
            }.scrollDismissesKeyboard(.interactively).background(ShareTheme.canvas).navigationTitle(result == nil ? "New link" : "Ready to share").shareInlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(result == nil ? "Cancel" : "Done") { store.resetDraft(); dismiss() }.disabled(store.busy || reading) } }
        }.shareSheetSize().interactiveDismissDisabled(store.busy || reading)
            .fileImporter(isPresented: $importing, allowedContentTypes: supported, allowsMultipleSelection: true) { selection in
                switch selection {
                case .success(let urls):
                    reading = true
                    Task {
                        do {
                            guard files.count + urls.count <= store.maxFiles else { throw ShareError.message("Choose up to \(store.maxFiles) files per folder.") }
                            let loaded = try await Task.detached(priority: .userInitiated) {
                                try urls.map { url -> SelectedFile in
                                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                                    var coordinationError: NSError?
                                    var loaded: Result<Data, Error>?
                                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
                                        loaded = Result {
                                            let size = try coordinated.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                                            guard size > 0, size <= 3 * 1024 * 1024 else { throw ShareError.message("\(url.lastPathComponent) must be 3 MB or smaller.") }
                                            return try Data(contentsOf: coordinated)
                                        }
                                    }
                                    if let coordinationError { throw coordinationError }
                                    guard let loaded else { throw ShareError.message("Couldn't read \(url.lastPathComponent).") }
                                    return SelectedFile(name: url.lastPathComponent, data: try loaded.get())
                                }
                            }.value
                            files.append(contentsOf: loaded); error = nil
                        } catch { self.error = error.localizedDescription }
                        reading = false
                    }
                case .failure(let error): self.error = error.localizedDescription
                }
            }
            .onChange(of: usePIN) { _, enabled in if !enabled { pin = "" } }
            .onChange(of: photos) { _, items in
                guard !items.isEmpty else { return }
                reading = true
                Task {
                    do {
                        guard files.count + items.count <= store.maxFiles else { throw ShareError.message("Choose up to \(store.maxFiles) files.") }
                        var loaded: [SelectedFile] = []
                        for (index, item) in items.enumerated() {
                            guard let data = try await item.loadTransferable(type: Data.self) else { throw ShareError.message("Couldn't load a photo. Try downloading it from iCloud first.") }
                            let prepared = try await Task.detached(priority: .userInitiated) { try preparePhoto(data) }.value
                            loaded.append(SelectedFile(name: "Photo-\(files.count + index + 1).jpg", data: prepared))
                        }
                        files.append(contentsOf: loaded); error = nil
                    } catch { self.error = error.localizedDescription }
                    photos = []; reading = false
                }
            }
            .confirmationDialog("Replace your oldest folder?", isPresented: $confirmReplacement, titleVisibility: .visible) {
                Button("Replace and create link", role: .destructive) { publish() }
            } message: { Text("Your oldest folder's link will stop working. The new folder takes its place.") }
    }
    private func pickerLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 10) { Image(systemName: icon).font(.system(size: 27)); Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold)) }
            .foregroundStyle(ShareTheme.blue).frame(maxWidth: .infinity).padding(.vertical, 24)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
    private func publish() {
        error = nil
        publishing = Task {
            do { result = try await store.publish(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Shared folder" : title, files: files, permanent: permanent, pin: usePIN ? pin : nil); pin = "" }
            catch { self.error = error.localizedDescription }
        }
    }
}
// Decode thumbnails off the main thread to avoid loading full-resolution photos into UI memory.
import ImageIO
nonisolated private func preparePhoto(_ data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw ShareError.message("This photo format could not be read.") }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw ShareError.message("Couldn't prepare this photo.") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
    guard CGImageDestinationFinalize(destination), output.length <= 3 * 1024 * 1024 else { throw ShareError.message("This photo is too large. Choose a smaller version.") }
    return output as Data
}

extension View {
    @ViewBuilder func sharePINKeyboard() -> some View {
#if os(iOS)
        self.keyboardType(.numberPad)
#else
        self
#endif
    }
}
