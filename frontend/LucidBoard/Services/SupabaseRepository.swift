import Foundation
import Supabase
import Realtime

private struct NoteIDRecord: Decodable { let id: UUID }

final class SupabaseRepository: AppRepository {
    private let service = SupabaseService.shared

    nonisolated func signInAnonymously() async throws {
        try await service.signInAnonymously()
    }

    nonisolated var isSignedIn: Bool {
        (try? service.client)?.auth.currentUser != nil
    }

    nonisolated func fetchBoards() async throws -> [Board] {
        try await service.fetchBoards()
    }

    nonisolated func updateBoard(_ board: Board) async throws {
        try await service.updateBoard(board)
    }

    nonisolated func fetchNotes(boardId: UUID) async throws -> [Note] {
        try await service.fetchNotes(boardId: boardId)
    }

    nonisolated func upsertNote(_ note: Note) async throws {
        try await service.upsertNote(note)
    }

    nonisolated func deleteNote(id: UUID) async throws {
        try await service.deleteNote(id: id)
    }

    nonisolated func fetchProfile() async throws -> AppSettings? {
        try await service.fetchProfile()
    }

    nonisolated func updateProfile(settings: AppSettings) async throws {
        try await service.updateProfile(settings: settings)
    }

    nonisolated func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] {
        try await service.autoOrganize(boardId: boardId)
    }

    nonisolated func subscribeToNotes(
        boardId: UUID,
        onChange: @escaping (NoteChange) -> Void
    ) -> NoteSubscription {
        let token = SupabaseSubscription()
        Task {
            do {
                let client = try service.client
                let channel = client.channel("notes_board_\(boardId.uuidString)")
                await token.setChannel(channel)
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "notes",
                    filter: "board_id=eq.\(boardId.uuidString)"
                )
                await channel.subscribe()
                for await change in changes {
                    switch change {
                    case .insert(let action):
                        if let note: Note = try? action.record.decode() { onChange(.upsert(note)) }
                    case .update(let action):
                        if let note: Note = try? action.record.decode() { onChange(.upsert(note)) }
                    case .delete(let action):
                        if let r: NoteIDRecord = try? action.oldRecord.decode() {
                            onChange(.delete(id: r.id))
                        }
                    default: break
                    }
                }
            } catch {
                print("Realtime subscribe failed: \(error)")
            }
        }
        return token
    }
}

private final actor SupabaseSubscription: NoteSubscription {
    private var channel: RealtimeChannelV2?

    nonisolated func cancel() {
        Task { [self] in
            guard let channel = await self.channel else { return }
            await channel.unsubscribe()
        }
    }

    func setChannel(_ channel: RealtimeChannelV2) {
        self.channel = channel
    }
}
