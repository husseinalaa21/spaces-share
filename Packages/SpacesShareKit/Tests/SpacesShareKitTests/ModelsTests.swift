import XCTest
@testable import SpacesShareKit
final class ModelsTests: XCTestCase {
    func testServerMillisecondsAndExpiryBoundary() throws {
        let json = #"{"id":"a","title":"Folder","createdAt":1000000,"expiresAt":1600000,"url":"/s/a","files":[]}"#
        let folder = try JSONDecoder().decode(SharedFolder.self, from: Data(json.utf8))
        XCTAssertTrue(folder.isActive(at: Date(timeIntervalSince1970: 1599)))
        XCTAssertFalse(folder.isActive(at: Date(timeIntervalSince1970: 1600)))
    }
    func testPermanentFolderHasNoExpiry() throws {
        let json = #"{"id":"a","title":"Folder","createdAt":1000000,"expiresAt":null,"url":"/s/a","files":[]}"#
        let folder = try JSONDecoder().decode(SharedFolder.self, from: Data(json.utf8))
        XCTAssertNil(folder.expiryDate)
        XCTAssertTrue(folder.isActive(at: .distantFuture))
    }
}

final class MembershipTests: XCTestCase {
    func decode(_ json: String) throws -> MembershipResponse {
        try JSONDecoder().decode(MembershipResponse.self, from: Data(json.utf8))
    }
    func testMetadataDoesNotGrantMembership() throws {
        let value = try decode(#"{"ok":true,"prepaidActive":false,"prepaidInfo":{"planId":"vip","planTitle":"VIP"}}"#)
        XCTAssertTrue(value.isConfirmed)
        XCTAssertFalse(value.isActive)
    }
    func testMissingStatusIsUnknownAndServerFailureNeverGrants() throws {
        XCTAssertFalse(try decode(#"{"ok":true}"#).isConfirmed)
        let failed = try decode(#"{"ok":false,"prepaidActive":true,"error":"Try again"}"#)
        XCTAssertFalse(failed.isConfirmed)
        XCTAssertFalse(failed.isActive)
    }
    func testPaidResponseAndMilliseconds() throws {
        let value = try decode(#"{"ok":true,"prepaidActive":true,"prepaidInfo":{"planTitle":"Spacechat VIP","subscriptionExpiresAt":1800000000000}}"#)
        XCTAssertTrue(value.isActive)
        XCTAssertEqual(value.prepaidInfo?.title, "Spacechat VIP")
        XCTAssertEqual(value.prepaidInfo?.expiryDate, Date(timeIntervalSince1970: 1800000000))
    }
    func testLegacyFoldersAndProtectedFoldersDecode() throws {
        for state in ["", ",\"pinProtected\":true"] {
            let json = "{\"id\":\"a\",\"title\":\"Test\",\"createdAt\":0,\"url\":\"/s/a\",\"files\":[]\(state)}"
            let folder = try JSONDecoder().decode(SharedFolder.self, from: Data(json.utf8))
            XCTAssertEqual(folder.pinProtected == true, !state.isEmpty)
        }
    }
}
