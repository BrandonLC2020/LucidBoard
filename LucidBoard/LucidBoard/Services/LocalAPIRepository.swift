import Foundation

final class LocalAPIRepository: AppRepository {
    private let baseURL: String
    private let tokenStore: TokenStore

    init(baseURL: String, tokenStore: TokenStore) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
    }

    nonisolated func signInAnonymously() async throws { fatalError("Task 18") }
    nonisolated var isSignedIn: Bool { fatalError("Task 18") }
    nonisolated func fetchBoards() async throws -> [Board] { fatalError("Task 18") }
    nonisolated func updateBoard(_ board: Board) async throws { fatalError("Task 18") }
    nonisolated func fetchNotes(boardId: UUID) async throws -> [Note] { fatalError("Task 18") }
    nonisolated func upsertNote(_ note: Note) async throws { fatalError("Task 18") }
    nonisolated func deleteNote(id: UUID) async throws { fatalError("Task 18") }
    nonisolated func fetchProfile() async throws -> AppSettings? { fatalError("Task 18") }
    nonisolated func updateProfile(settings: AppSettings) async throws { fatalError("Task 18") }
    nonisolated func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] { fatalError("Task 18") }
    nonisolated func subscribeToNotes(boardId: UUID, onChange: @escaping (NoteChange) -> Void) -> NoteSubscription {
        InertNoteSubscription()
    }
}
