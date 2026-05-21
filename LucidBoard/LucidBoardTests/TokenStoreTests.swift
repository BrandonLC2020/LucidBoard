import Foundation
import Testing
@testable import LucidBoard

struct TokenStoreTests {

    @Test func storesAndRetrievesToken() {
        let store = InMemoryTokenStore()
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000DEAD")!
        store.save(token: "abc.def.ghi", userId: id)
        #expect(store.currentToken == "abc.def.ghi")
        #expect(store.currentUserId?.uuidString.lowercased() == "00000000-0000-0000-0000-00000000dead")
    }

    @Test func clearEmptiesStorage() {
        let store = InMemoryTokenStore()
        store.save(token: "x", userId: UUID())
        store.clear()
        #expect(store.currentToken == nil)
        #expect(store.currentUserId == nil)
    }

    @Test func isExpiredTrueForExpiredJWT() {
        let store = InMemoryTokenStore()
        // exp = 1 (Jan 1 1970)
        let expiredJWT = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjF9.sig"
        store.save(token: expiredJWT, userId: UUID())
        #expect(store.isCurrentTokenExpired)
    }

    @Test func isExpiredFalseForFutureJWT() {
        let store = InMemoryTokenStore()
        // exp = 9999999999 (year 2286)
        let futureJWT = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig"
        store.save(token: futureJWT, userId: UUID())
        #expect(!store.isCurrentTokenExpired)
    }
}
