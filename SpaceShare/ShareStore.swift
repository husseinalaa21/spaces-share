import Foundation
import Combine
import SwiftUI
import SpaceShareKit
import UniformTypeIdentifiers

struct SelectedFile: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let data: Data
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file) }
}
enum ShareError: LocalizedError {
    case message(String), signedOut
    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        case .signedOut: return "Your session expired. Please sign in again."
        }
    }
}
@MainActor final class ShareStore: ObservableObject {
    @Published var onboardingStep: PostLoginStep = .home
    @Published var showSettings = false
    @Published private(set) var membership: MembershipResponse?
    @Published private(set) var checkingMembership = false
    @Published private(set) var membershipError: String?
    private let network: URLSession
    private let defaults: UserDefaults
    private var membershipRequest: Task<Void, Never>?
    private var restoreStarted = false
    init(network: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.network = network; self.defaults = defaults
    }
    @Published var account: SpacechatAuth.Account?
    @Published var restoring = true
    @Published var busy = false
    @Published var loading = false
    @Published var error: String?
    @Published var folders: [SharedFolder] = []
    @Published var policy: SharePolicy?
    @Published var uploadProgress = 0.0
    @Published var uploadStatus = ""
    private var generation = UUID()
    // Preserve upload receipts and request identity across retries after a lost response.
    private var receipts: [UUID: String] = [:]
    private var draftRequestID = UUID().uuidString
    var session: String? { account?.session }
    var member: Bool { membership?.isActive ?? (policy?.member == true) }
    var canOfferPurchase: Bool { membership?.isConfirmed == true && !member && membershipError == nil && !checkingMembership }
    var membershipTitle: String { membership?.prepaidInfo?.title ?? "Spacechat membership" }
    var membershipStatus: String {
        if checkingMembership { return "Checking membership…" }
        if member { return membershipTitle }
        if membershipError != nil { return "Membership unavailable" }
        return membership?.isConfirmed == true ? "Free account" : "Checking membership…"
    }
    var maxFiles: Int { policy?.maxFiles ?? 20 }
    var maxBytes: Int { policy?.maxBytes ?? 3 * 1024 * 1024 }

    func restore() async {
        guard !restoreStarted else { return }
        restoreStarted = true
        defer { restoring = false }
        // Resume the stored session without creating another Spacechat login session.
        guard let token = SpacechatAuth.storedSession() else { return }
        account = SpacechatAuth.Account(id: "", session: token,
            username: defaults.string(forKey: "share.username") ?? "",
            displayName: "", isNewAccount: false, databaseMode: "browser", database: nil)
        onboardingStep = PostLoginStep(rawValue: defaults.integer(forKey: "share.onboardingStep")) ?? .backup
    }
    func signIn(_ phrase: String) async -> Bool {
        busy = true; error = nil
        defer { busy = false }
        do {
            let result = try await SpacechatAuth.login(phrase: phrase)
            resetAccountState()
            SpacechatAuth.storePhrase(phrase); SpacechatAuth.storeSession(result.session)
            setOnboardingStep(.backup)
            account = result
            defaults.set(result.username, forKey: "share.username")
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func signOut() {
        resetAccountState(); account = nil
        SpacechatAuth.clearStoredCredentials()
        defaults.removeObject(forKey: "share.username")
        defaults.removeObject(forKey: "share.onboardingStep")
        onboardingStep = .home
    }
    private func resetAccountState() {
        generation = UUID(); membershipRequest?.cancel(); membershipRequest = nil
        membership = nil; membershipError = nil; checkingMembership = false
        policy = nil; folders = []; receipts = [:]; loading = false
        showSettings = false; draftRequestID = UUID().uuidString; error = nil
    }
    func setOnboardingStep(_ step: PostLoginStep) {
        onboardingStep = step; defaults.set(step.rawValue, forKey: "share.onboardingStep")
    }
    func finishMembershipPage(openSettings: Bool = false) {
        showSettings = openSettings; setOnboardingStep(.home)
    }
    func refreshAccount() async {
        async let membershipCheck: Void = refreshMembership()
        async let folderCheck: Void = refresh()
        _ = await (membershipCheck, folderCheck)
    }
    func refreshMembership() async {
        guard session != nil else { return }
        if let membershipRequest { await membershipRequest.value; return }
        let version = generation
        checkingMembership = true; membershipError = nil
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.apiRequest("prepaid/check", body: ["includeDatabase": false], as: MembershipResponse.self)
                guard self.generation == version, !Task.isCancelled else { return }
                guard response.isConfirmed else { throw ShareError.message(response.error ?? "Couldn't confirm your membership. Please try again.") }
                self.membership = response
            } catch {
                if self.generation == version, !Task.isCancelled {
                    self.membershipError = "Couldn't check your Spacechat membership. Check your connection and try again."
                }
            }
            if self.generation == version { self.checkingMembership = false }
        }
        membershipRequest = task
        await task.value
        if generation == version { membershipRequest = nil }
    }
    func purchaseConfiguration() async throws -> MembershipPurchaseConfiguration {
        let result = try await request("purchase-config", as: MembershipPurchaseConfiguration.self)
        guard result.ok, result.available, result.bundleId == Bundle.main.bundleIdentifier else {
            throw ShareError.message("Membership purchases are not available right now. Please try again later.")
        }
        return result
    }
    func activateMembership(productID: String, transactionID: String, originalID: String, signedTransaction: String, expectedSession: String, syncOnly: Bool = false) async throws {
        guard session == expectedSession else { throw ShareError.signedOut }
        let result = try await apiRequest("ios/iap/complete", body: [
            "productId": productID, "transactionId": transactionID,
            "originalTransactionId": originalID, "signedTransactionInfo": signedTransaction,
            "bundleId": Bundle.main.bundleIdentifier ?? "", "syncOnly": syncOnly
        ], as: MembershipResponse.self)
        guard session == expectedSession else { throw ShareError.signedOut }
        guard result.isConfirmed, (syncOnly || result.isActive) else {
            throw ShareError.message(result.error ?? "Your Apple purchase is waiting for account activation. Use Restore Purchases to retry.")
        }
        membershipRequest?.cancel(); membershipRequest = nil; checkingMembership = false
        membership = result; membershipError = nil
        await refresh()
    }
    func request<T: Decodable>(_ endpoint: String, body: [String: Any] = [:], as: T.Type) async throws -> T {
        try await apiRequest("spaces-share/\(endpoint)", body: body, as: T.self)
    }
    func apiRequest<T: Decodable>(_ endpoint: String, body: [String: Any] = [:], as: T.Type) async throws -> T {
        guard let token = session else { throw ShareError.signedOut }
        var request = URLRequest(url: SpacechatAuth.baseURL.appendingPathComponent("api/\(endpoint)"))
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-spacechat-session")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ShareError.message("Unable to contact Spacechat.") }
        if response.statusCode == 401 {
            if session == token { signOut() }
            throw ShareError.signedOut
        }
        guard (200...299).contains(response.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if response.statusCode == 404 { throw ShareError.message("SpaceShare is not available on the server yet. Please try again after the server update.") }
            throw ShareError.message(json?["error"] as? String ?? "Couldn't complete your request. Please try again.")
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ShareError.message("The server returned an unexpected response. Please try again.") }
    }
    func refresh() async {
        guard session != nil, !loading else { return }
        loading = true; let version = generation
        defer { if generation == version { loading = false } }
        do {
            let result = try await request("list", as: FolderListResponse.self)
            guard generation == version else { return }
            policy = result.policy; folders = result.folders; error = nil
        } catch { if generation == version { self.error = error.localizedDescription } }
    }
    func publish(title: String, files: [SelectedFile], permanent: Bool, pin: String? = nil) async throws -> SharedFolder {
        if let pin, !pin.isEmpty, pin.range(of: "^[0-9]{4,8}$", options: .regularExpression) == nil { throw ShareError.message("Choose a PIN with 4 to 8 digits.") }
        if let pin, !pin.isEmpty, policy?.supportsPIN != true { throw ShareError.message("PIN protection is unavailable. Refresh your account and try again.") }
        guard !files.isEmpty, files.count <= maxFiles else { throw ShareError.message("Choose 1 to \(maxFiles) files.") }
        guard policy != nil else { throw ShareError.message("Refresh your account before uploading.") }
        guard !permanent || member else { throw ShareError.message("No expiry requires a Spacechat membership.") }
        guard files.allSatisfy({ !$0.data.isEmpty && $0.data.count <= maxBytes }) else { throw ShareError.message("Each file must be 3 MB or smaller.") }
        busy = true; uploadProgress = 0
        defer { busy = false; uploadStatus = "" }
        let version = generation
        var ids: [String] = []
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            uploadStatus = "Uploading \(index + 1) of \(files.count)…"
            if let receipt = receipts[file.id] { ids.append(receipt) }
            else {
                let result = try await request("upload", body: ["name": file.name, "base64": file.data.base64EncodedString()], as: UploadResponse.self)
                guard generation == version else { throw ShareError.signedOut }
                receipts[file.id] = result.id; ids.append(result.id)
            }
            uploadProgress = Double(index + 1) / Double(files.count + 1)
        }
        uploadStatus = "Creating your link…"
        do {
            let result = try await request("create", body: ["requestId": draftRequestID, "title": title, "fileIDs": ids, "permanent": permanent, "pin": pin ?? ""], as: CreateFolderResponse.self)
            guard generation == version else { throw ShareError.signedOut }
            uploadProgress = 1
            resetDraft()
            await refresh()
            return result.folder
        } catch {
            // A receipt may have expired; allow picking files again via Cancel.
            throw error
        }
    }
    func resetDraft() { receipts = [:]; draftRequestID = UUID().uuidString }
    func delete(_ folder: SharedFolder) async {
        busy = true; defer { busy = false }
        struct Result: Decodable { let ok: Bool }
        do {
            _ = try await request("delete", body: ["id": folder.id], as: Result.self)
            folders.removeAll { $0.id == folder.id }
        } catch { self.error = error.localizedDescription }
    }
    func publicURL(_ path: String) -> URL { URL(string: path, relativeTo: SpacechatAuth.baseURL)!.absoluteURL }
}
