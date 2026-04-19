//
//  BoardViewModel.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI
import Combine
import Supabase
import Realtime

class BoardViewModel: ObservableObject {
    @Published var board: Board
    @Published var noteViewModels: [UUID: NoteViewModel] = [:]
    
    // Canvas State
    @Published var offset: CGSize = .zero
    @Published var scale: CGFloat = 1.0
    
    // Last gesture state to handle cumulative panning/zooming
    var lastOffset: CGSize = .zero
    var lastScale: CGFloat = 1.0
    
    private let supabase = SupabaseService.shared
    
    init(board: Board) {
        self.board = board
        
        Task {
            await fetchNotes()
            await subscribeToRealtime()
        }
    }
    
    @MainActor
    func fetchNotes() async {
        do {
            let notes = try await supabase.fetchNotes(boardId: board.id)
            for note in notes {
                noteViewModels[note.id] = NoteViewModel(note: note)
            }
        } catch {
            print("Error fetching notes: \(error)")
        }
    }
    
    @MainActor
    private func subscribeToRealtime() async {
        let channel = supabase.client.channel("notes_board_\(board.id.uuidString)")
        
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "notes",
            filter: "board_id=eq.\(board.id.uuidString)"
        )
        
        await channel.subscribe()
        
        Task {
            for await change in changes {
                await handleRealtimeChange(change)
            }
        }
    }
    
    @MainActor
    private func handleRealtimeChange(_ change: AnyAction) async {
        switch change {
        case .insert(let action):
            do {
                let note: Note = try action.record.decode()
                updateOrAddNote(note)
            } catch {
                print("Error decoding insert note: \(error)")
            }
        case .update(let action):
            do {
                let note: Note = try action.record.decode()
                updateOrAddNote(note)
            } catch {
                print("Error decoding update note: \(error)")
            }
        case .delete(let action):
            do {
                let note: Note = try action.oldRecord.decode()
                noteViewModels.removeValue(forKey: note.id)
            } catch {
                print("Error decoding delete note: \(error)")
            }
        default:
            break
        }
    }
    
    private func updateOrAddNote(_ note: Note) {
        if let existingVM = noteViewModels[note.id] {
            if note.updatedAt > existingVM.note.updatedAt {
                withAnimation(.spring()) {
                    existingVM.note = note
                }
            }
        } else {
            noteViewModels[note.id] = NoteViewModel(note: note)
        }
    }
    
    // Auto-Organize (Phase 4, Step 4)
    @MainActor
    func triggerAutoOrganize() async {
        do {
            let newPositions = try await supabase.autoOrganize(boardId: board.id)
            for (id, pos) in newPositions {
                if let noteVM = noteViewModels[id] {
                    withAnimation(.spring(response: 1.0, dampingFraction: 0.7)) {
                        noteVM.note.posX = pos.0
                        noteVM.note.posY = pos.1
                    }
                    // Sync the new position
                    noteVM.syncNote()
                }
            }
        } catch {
            print("Error auto-organizing: \(error)")
        }
    }
    
    @MainActor
    func deleteNote(id: UUID) {
        noteViewModels.removeValue(forKey: id)
        Task {
            try? await supabase.deleteNote(id: id)
        }
    }

    @MainActor
    func bringToFront(id: UUID) {
        guard let vm = noteViewModels[id] else { return }
        let maxZ = noteViewModels.values.map { $0.note.zIndex }.max() ?? 0
        guard vm.note.zIndex < maxZ else { return }
        vm.note.zIndex = maxZ + 1
        vm.syncNote()
    }

    func addNote(at point: CGPoint) {
        let newNote = Note(
            id: UUID(),
            boardId: board.id,
            userId: board.userId,
            contentText: "",
            contentDrawing: nil,
            color: "#FFFF00", // Default yellow
            posX: Float(point.x),
            posY: Float(point.y),
            zIndex: (noteViewModels.values.map { $0.note.zIndex }.max() ?? 0) + 1,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        noteViewModels[newNote.id] = NoteViewModel(note: newNote)
        
        Task {
            try? await supabase.upsertNote(newNote)
        }
    }
    
    // Canvas transformation logic
    func handlePanGesture(_ translation: CGSize) {
        offset = CGSize(
            width: lastOffset.width + translation.width,
            height: lastOffset.height + translation.height
        )
    }
    
    func finalizePanGesture() {
        lastOffset = offset
    }
    
    func handleZoomGesture(_ magnification: CGFloat) {
        scale = lastScale * magnification
    }
    
    func finalizeZoomGesture() {
        lastScale = scale
    }
}
