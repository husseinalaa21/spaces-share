import Foundation

public enum PostLoginStep: Int, Sendable {
    case backup, membership, home
}

public struct MembershipInfo: Decodable, Sendable {
    public let planId: String?
    public let planTitle: String?
    public let subscriptionStatus: String?
    public let subscriptionExpiresAt: Double?
    public var title: String { planTitle ?? planId?.capitalized ?? "Spacechat membership" }
    public var expiryDate: Date? {
        guard let value = subscriptionExpiresAt, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }
}

/// Only an explicit server decision establishes membership. Metadata may also
/// accompany expired subscriptions and must never grant access by itself.
public struct MembershipResponse: Decodable, Sendable {
    public let ok: Bool
    public let prepaidActive: Bool?
    public let prepaidInfo: MembershipInfo?
    public let error: String?
    public var isConfirmed: Bool { ok && prepaidActive != nil }
    public var isActive: Bool { ok && prepaidActive == true }
}

public struct MembershipPurchaseConfiguration: Decodable, Sendable {
    public let ok: Bool
    public let available: Bool
    public let productId: String
    public let bundleId: String
    public let appAccountToken: UUID
}
