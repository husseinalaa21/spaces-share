import Foundation
public struct SharePolicy: Codable, Sendable {
    public let member: Bool
    public let limit: Int
    public let maxFiles: Int
    public let maxBytes: Int
    public let defaultLifetimeSeconds: Int
    public let canKeepForever: Bool
    public let supportsPIN: Bool?
}
public struct SharedFile: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let size: Int
    public let url: String
    public var isPhoto: Bool { type.hasPrefix("image/") }
}
public struct SharedFolder: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let createdAt: Double
    public let expiresAt: Double?
    public let url: String
    public let files: [SharedFile]
    public let pinProtected: Bool?
    public var expiryDate: Date? { expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    public func isActive(at date: Date = Date()) -> Bool { expiryDate.map { $0 > date } ?? true }
}
public struct FolderListResponse: Decodable, Sendable {
    public let policy: SharePolicy
    public let folders: [SharedFolder]
}
public struct CreateFolderResponse: Decodable, Sendable { public let folder: SharedFolder }
public struct UploadResponse: Decodable, Sendable { public let id: String }
