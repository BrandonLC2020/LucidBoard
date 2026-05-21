import XCTest
@testable import LucidBoard

final class TokenStoreTests: XCTestCase {
    func test_storesAndRetrievesToken() {
        let store = InMemoryTokenStore()
        store.save(token: "abc.def.ghi", userId: UUID(uuidString: "00000000-0000-0000-0000-00000000DEAD")!)
        XCTAssertEqual(store.currentToken, "abc.def.ghi")
        XCTAssertEqual(store.currentUserId?.uuidString.lowercased(), "00000000-0000-0000-0000-00000000dead")
    }

    func test_clearEmptiesStorage() {
        let store = InMemoryTokenStore()
        store.save(token: "x", userId: UUID())
        store.clear()
        XCTAssertNil(store.currentToken)
        XCTAssertNil(store.currentUserId)
    }

    func test_isExpiredTrueForExpiredJWT() {
        let store = InMemoryTokenStore()
        // exp = 1 (Jan 1 1970)
        let expiredJWT = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.sig"
        store.save(token: expiredJWT, userId: UUID())
        XCTAssertTrue(store.isCurrentTokenExpired)
    }

    func test_isExpiredFalseForFutureJWT() {
        let store = InMemoryTokenStore()
        // exp = 9999999999 (year 2286)
        let futureJWT = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig"
        store.save(token: futureJWT, userId: UUID())
        XCTAssertFalse(store.isCurrentTokenExpired)
    }
}
