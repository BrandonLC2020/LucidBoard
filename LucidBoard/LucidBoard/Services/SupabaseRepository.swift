import Foundation

final class SupabaseRepository: AppRepository {
    nonisolated func signInAnonymously() async throws { fatalError("Task 17") }
    nonisolated var isSignedIn: Bool { fatalError("Task 17") }
    nonisolated func fetchBoards() async throws -> [Board] { fatalError("Task 17") }
    nonisolated func updateBoard(_ board: Board) async throws { fatalError("Task 17") }
    nonisolated func fetchNotes(boardId: UUID) async throws -> [Note] { fatalError("Task 17") }
    nonisolated func upsertNote(_ note: Note) async throws { fatalError("Task 17") }
    nonisolated func deleteNote(id: UUID) async throws { fatalError("Task 17") }
    nonisolated func fetchProfile() async throws -> AppSettings? { fatalError("Task 17") }
    nonisolated func updateProfile(settings: AppSettings) async throws { fatalError("Task 17") }
    nonisolated func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] { fatalError("Task 17") }
    nonisolated func subscribeToNotes(boardId: UUID, onChange: @escaping (NoteChange) -> Void) -> NoteSubscription {
        fatalError("Task 17")
    }
}
