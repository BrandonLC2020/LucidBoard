import Foundation

// MARK: - Error types

enum LocalAPIError: Error {
    case unauthorized
    case notFound
    case validation(String)
    case network(URLError)
    case server(status: Int, code: String?)
    case decoding(Error)
}

// MARK: - Private response shapes

private struct SignupResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let user: SignupUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }
}

private struct SignupUser: Decodable {
    let id: UUID
    let isAnonymous: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case isAnonymous = "is_anonymous"
    }
}

private struct APIError: Decodable {
    let detail: String?
    let code: String?
}

private struct NotePosition: Decodable {
    let id: UUID
    let newX: Float
    let newY: Float

    enum CodingKeys: String, CodingKey {
        case id
        case newX = "new_x"
        case newY = "new_y"
    }
}

private struct BoardUpdatePayload: Encodable {
    let title: String
    let backgroundColor: String
    let backgroundLayout: BackgroundLayout

    enum CodingKeys: String, CodingKey {
        case title
        case backgroundColor = "background_color"
        case backgroundLayout = "background_layout"
    }
}

private struct ProfilePayload: Encodable {
    let settings: AppSettings
}

private struct MatchNotesPayload: Encodable {
    let boardUUID: UUID

    enum CodingKeys: String, CodingKey {
        case boardUUID = "board_uuid"
    }
}

// MARK: - NotePayload (handles contentDrawing → base64)

private struct NotePayload: Encodable {
    let id: UUID
    let boardId: UUID
    let userId: UUID
    let contentText: String?
    let contentDrawing: String?  // base64-encoded
    let color: String
    let posX: Float
    let posY: Float
    let zIndex: Int
    let template: NoteTemplate
    let checklistItems: [ChecklistItem]?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case boardId = "board_id"
        case userId = "user_id"
        case contentText = "content_text"
        case contentDrawing = "content_drawing"
        case color
        case posX = "pos_x"
        case posY = "pos_y"
        case zIndex = "z_index"
        case template
        case checklistItems = "checklist_items"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from note: Note) {
        self.id = note.id
        self.boardId = note.boardId
        self.userId = note.userId
        self.contentText = note.contentText
        self.contentDrawing = note.contentDrawing.map { $0.base64EncodedString() }
        self.color = note.color
        self.posX = note.posX
        self.posY = note.posY
        self.zIndex = note.zIndex
        self.template = note.template
        self.checklistItems = note.checklistItems
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
    }
}

// MARK: - LocalAPIRepository

final class LocalAPIRepository: AppRepository {
    private let baseURL: String
    private let tokenStore: TokenStore
    private let session: URLSession

    // Shared encoder/decoder with ISO 8601 dates.
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(baseURL: String, tokenStore: TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    nonisolated var isSignedIn: Bool {
        tokenStore.currentToken != nil && !tokenStore.isCurrentTokenExpired
    }

    // MARK: - Auth

    nonisolated func signInAnonymously() async throws {
        var req = try makeRequest(path: "/auth/v1/signup", query: "anonymous=true", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data()  // empty body — params are in query

        let (data, response) = try await performRaw(req)
        try checkStatus(response, data: data, isAuthEndpoint: true)

        let signup: SignupResponse
        do {
            signup = try decoder.decode(SignupResponse.self, from: data)
        } catch {
            throw LocalAPIError.decoding(error)
        }
        tokenStore.save(token: signup.accessToken, userId: signup.user.id)
    }

    // MARK: - Boards

    nonisolated func fetchBoards() async throws -> [Board] {
        let data = try await perform(path: "/api/boards", method: "GET")
        do {
            return try decoder.decode([Board].self, from: data)
        } catch {
            throw LocalAPIError.decoding(error)
        }
    }

    nonisolated func updateBoard(_ board: Board) async throws {
        let payload = BoardUpdatePayload(
            title: board.title,
            backgroundColor: board.backgroundColor,
            backgroundLayout: board.backgroundLayout
        )
        let body = try encoder.encode(payload)
        _ = try await perform(path: "/api/boards/\(board.id)", method: "PATCH", body: body)
    }

    // MARK: - Notes

    nonisolated func fetchNotes(boardId: UUID) async throws -> [Note] {
        let data = try await perform(path: "/api/boards/\(boardId)/notes", method: "GET")
        do {
            return try decoder.decode([Note].self, from: data)
        } catch {
            throw LocalAPIError.decoding(error)
        }
    }

    nonisolated func upsertNote(_ note: Note) async throws {
        let payload = NotePayload(from: note)
        let body = try encoder.encode(payload)
        _ = try await perform(path: "/api/notes/\(note.id)", method: "PUT", body: body)
    }

    nonisolated func deleteNote(id: UUID) async throws {
        _ = try await perform(path: "/api/notes/\(id)", method: "DELETE")
    }

    // MARK: - Profile

    nonisolated func fetchProfile() async throws -> AppSettings? {
        do {
            let data = try await perform(path: "/api/profile", method: "GET")
            let wrapper = try decoder.decode([String: AppSettings].self, from: data)
            return wrapper["settings"]
        } catch LocalAPIError.notFound {
            return nil
        } catch {
            throw error
        }
    }

    nonisolated func updateProfile(settings: AppSettings) async throws {
        let payload = ProfilePayload(settings: settings)
        let body = try encoder.encode(payload)
        _ = try await perform(path: "/api/profile", method: "PUT", body: body)
    }

    // MARK: - AI

    nonisolated func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] {
        let payload = MatchNotesPayload(boardUUID: boardId)
        let body = try encoder.encode(payload)
        let data = try await perform(path: "/api/rpc/match_notes", method: "POST", body: body)

        let positions: [NotePosition]
        do {
            positions = try decoder.decode([NotePosition].self, from: data)
        } catch {
            throw LocalAPIError.decoding(error)
        }
        return Dictionary(uniqueKeysWithValues: positions.map { ($0.id, ($0.newX, $0.newY)) })
    }

    // MARK: - Realtime

    nonisolated func subscribeToNotes(boardId: UUID, onChange: @escaping (NoteChange) -> Void) -> NoteSubscription {
        InertNoteSubscription()
    }

    // MARK: - Private helpers

    /// Build a URLRequest for the given path, optional query string, and HTTP method.
    private nonisolated func makeRequest(path: String, query: String? = nil, method: String) throws -> URLRequest {
        var urlStr = baseURL + path
        if let query { urlStr += "?" + query }
        guard let url = URL(string: urlStr) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        return req
    }

    /// Attach the Bearer token header if a valid token exists.
    private nonisolated func attachAuth(_ req: inout URLRequest) {
        if let token = tokenStore.currentToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Low-level send: wraps URLError into LocalAPIError.network.
    private nonisolated func performRaw(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: req)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return (data, httpResponse)
        } catch let urlError as URLError {
            throw LocalAPIError.network(urlError)
        }
    }

    /// High-level send: adds auth header, maps status codes, retries on 401.
    private nonisolated func perform(path: String, method: String, body: Data? = nil) async throws -> Data {
        var req = try makeRequest(path: path, method: method)
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        attachAuth(&req)

        let (data, response) = try await performRaw(req)

        // Retry-on-401: only for non-auth endpoints, only once.
        if response.statusCode == 401 {
            let isAuthEndpoint = path.hasPrefix("/auth/")
            if !isAuthEndpoint {
                // Re-sign-in silently.
                try await signInAnonymously()
                // Rebuild request with fresh token.
                var retryReq = try makeRequest(path: path, method: method)
                if let body {
                    retryReq.httpBody = body
                    retryReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                attachAuth(&retryReq)
                let (retryData, retryResponse) = try await performRaw(retryReq)
                try checkStatus(retryResponse, data: retryData, isAuthEndpoint: false)
                return retryData
            }
            try checkStatus(response, data: data, isAuthEndpoint: true)
        }

        try checkStatus(response, data: data, isAuthEndpoint: path.hasPrefix("/auth/"))
        return data
    }

    /// Map HTTP status to LocalAPIError (throws); otherwise returns normally.
    private nonisolated func checkStatus(_ response: HTTPURLResponse, data: Data, isAuthEndpoint: Bool) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw LocalAPIError.unauthorized
        case 404:
            throw LocalAPIError.notFound
        case 422:
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.detail ?? "Validation error"
            throw LocalAPIError.validation(message)
        default:
            let code = (try? JSONDecoder().decode(APIError.self, from: data))?.code
            throw LocalAPIError.server(status: response.statusCode, code: code)
        }
    }
}
