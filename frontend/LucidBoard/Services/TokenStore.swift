import Foundation
import Security

protocol TokenStore: AnyObject {
    nonisolated var currentToken: String? { get }
    nonisolated var currentUserId: UUID? { get }
    nonisolated var isCurrentTokenExpired: Bool { get }
    nonisolated func save(token: String, userId: UUID)
    nonisolated func clear()
}

extension TokenStore {
    nonisolated var isCurrentTokenExpired: Bool {
        guard let token = currentToken else { return true }
        return Self.jwtIsExpired(token)
    }

    static func jwtIsExpired(_ jwt: String) -> Bool {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return true }
        var b64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        b64.append(String(repeating: "=", count: (4 - b64.count % 4) % 4))
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return true }
        return Date(timeIntervalSince1970: exp) <= Date()
    }
}

final class InMemoryTokenStore: TokenStore {
    nonisolated(unsafe) private(set) var currentToken: String?
    nonisolated(unsafe) private(set) var currentUserId: UUID?

    nonisolated func save(token: String, userId: UUID) {
        currentToken = token
        currentUserId = userId
    }

    nonisolated func clear() {
        currentToken = nil
        currentUserId = nil
    }
}

final class KeychainTokenStore: TokenStore {
    private let service = "com.lucidboard.api.token"
    private let tokenAccount = "access_token"
    private let userIdAccount = "user_id"

    nonisolated var currentToken: String? { read(account: tokenAccount).flatMap { String(data: $0, encoding: .utf8) } }
    nonisolated var currentUserId: UUID? {
        read(account: userIdAccount)
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(UUID.init(uuidString:))
    }

    nonisolated func save(token: String, userId: UUID) {
        write(account: tokenAccount, value: Data(token.utf8))
        write(account: userIdAccount, value: Data(userId.uuidString.utf8))
    }

    nonisolated func clear() {
        delete(account: tokenAccount)
        delete(account: userIdAccount)
    }

    // --- Keychain helpers ---

    nonisolated private func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    nonisolated private func write(account: String, value: Data) {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = value
        SecItemAdd(query as CFDictionary, nil)
    }

    nonisolated private func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess ? item as? Data : nil
    }

    nonisolated private func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
