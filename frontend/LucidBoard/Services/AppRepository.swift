import Foundation

enum NoteChange {
    case upsert(Note)
    case delete(id: UUID)
}

protocol NoteSubscription {
    func cancel()
}

protocol AppRepository {
    // Auth
    nonisolated func signInAnonymously() async throws
    nonisolated var isSignedIn: Bool { get }

    // Boards
    nonisolated func fetchBoards() async throws -> [Board]
    nonisolated func updateBoard(_ board: Board) async throws

    // Notes
    nonisolated func fetchNotes(boardId: UUID) async throws -> [Note]
    nonisolated func upsertNote(_ note: Note) async throws
    nonisolated func deleteNote(id: UUID) async throws

    // Profile
    nonisolated func fetchProfile() async throws -> AppSettings?
    nonisolated func updateProfile(settings: AppSettings) async throws

    // AI
    nonisolated func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)]

    // Realtime
    nonisolated func subscribeToNotes(
        boardId: UUID,
        onChange: @escaping (NoteChange) -> Void
    ) -> NoteSubscription
}

final class InertNoteSubscription: NoteSubscription {
    func cancel() {}
}

enum AppRepositoryFactory {
    static func make(
        backendKind: String,
        localAPIBaseURL: String,
        tokenStore: TokenStore
    ) -> AppRepository {
        switch backendKind {
        case "local":
            return LocalAPIRepository(baseURL: localAPIBaseURL, tokenStore: tokenStore)
        default:
            return SupabaseRepository()
        }
    }

    /// Pick a repository based on build configuration and overrides.
    ///
    /// Priority order:
    ///   1. `LUCIDBOARD_BACKEND_KIND` environment variable (useful for tests and scheme overrides)
    ///   2. `BACKEND_KIND` / `LOCAL_API_URL` keys in `Info.plist` if present
    ///   3. Compile-time default: `local` in Debug builds, `supabase` in Release
    static func makeFromBundle() -> AppRepository {
        let envKind = ProcessInfo.processInfo.environment["LUCIDBOARD_BACKEND_KIND"]
        let plistKind = Bundle.main.object(forInfoDictionaryKey: "BACKEND_KIND") as? String
        let backendKind = envKind ?? plistKind ?? defaultBackendKind
        let envURL = ProcessInfo.processInfo.environment["LUCIDBOARD_LOCAL_API_URL"]
        let plistURL = Bundle.main.object(forInfoDictionaryKey: "LOCAL_API_URL") as? String
        let baseURL = envURL ?? plistURL ?? "http://127.0.0.1:8000"
        return make(backendKind: backendKind, localAPIBaseURL: baseURL, tokenStore: KeychainTokenStore())
    }

    private static var defaultBackendKind: String {
        #if DEBUG
        return "local"
        #else
        return "supabase"
        #endif
    }
}
