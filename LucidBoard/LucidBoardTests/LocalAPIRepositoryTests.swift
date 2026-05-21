import Foundation
import Testing
@testable import LucidBoard

@MainActor
@Suite(.serialized)
struct LocalAPIRepositoryTests {
    private func makeRepo(tokenStore: InMemoryTokenStore) -> (LocalAPIRepository, MockURLProtocol.Type) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let repo = LocalAPIRepository(baseURL: "http://test.invalid", tokenStore: tokenStore, session: session)
        MockURLProtocol.reset()
        return (repo, MockURLProtocol.self)
    }

    @Test func signInAnonymously_postsToSignupAndStoresToken() async throws {
        let tokenStore = InMemoryTokenStore()
        let (repo, _) = makeRepo(tokenStore: tokenStore)
        MockURLProtocol.responder = { req in
            #expect(req.url?.path == "/auth/v1/signup")
            #expect(req.url?.query == "anonymous=true")
            let body = """
            {"access_token":"eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig","token_type":"bearer","expires_in":3600,"user":{"id":"11111111-1111-1111-1111-111111111111","is_anonymous":true}}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        try await repo.signInAnonymously()
        #expect(tokenStore.currentToken?.hasPrefix("eyJ") == true)
        #expect(tokenStore.currentUserId?.uuidString.lowercased() == "11111111-1111-1111-1111-111111111111")
    }

    @Test func fetchBoards_attachesBearerHeader() async throws {
        let tokenStore = InMemoryTokenStore()
        tokenStore.save(token: "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig", userId: UUID())
        let (repo, _) = makeRepo(tokenStore: tokenStore)
        MockURLProtocol.responder = { req in
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        let boards = try await repo.fetchBoards()
        #expect(boards.count == 0)
    }

    @Test func unauthorized_triggersResignAndRetry() async throws {
        let tokenStore = InMemoryTokenStore()
        tokenStore.save(token: "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig", userId: UUID())
        let (repo, _) = makeRepo(tokenStore: tokenStore)

        // Use an actor for thread-safe counter access from the URLProtocol callback.
        let counter = Counter()
        MockURLProtocol.responder = { req in
            counter.bumpSync()
            let count = counter.valueSync
            if req.url?.path == "/auth/v1/signup" {
                let body = """
                {"access_token":"eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjk5OTk5OTk5OTl9.sig","token_type":"bearer","expires_in":3600,"user":{"id":"22222222-2222-2222-2222-222222222222","is_anonymous":true}}
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            if count < 3 {
                return (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
            }
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    "[]".data(using: .utf8)!)
        }
        _ = try await repo.fetchBoards()
        #expect(counter.valueSync >= 3)
    }

    @Test func localAPI_subscribeToNotes_returnsInert() {
        let (repo, _) = makeRepo(tokenStore: InMemoryTokenStore())
        var called = false
        let sub = repo.subscribeToNotes(boardId: UUID()) { _ in called = true }
        sub.cancel()
        #expect(called == false)
    }
}

// MARK: - Helpers

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var valueSync: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func bumpSync() { lock.lock(); defer { lock.unlock() }; _value += 1 }
}

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responder: ((URLRequest) -> (HTTPURLResponse, Data))?

    static func reset() { responder = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "no responder", code: 0))
            return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
