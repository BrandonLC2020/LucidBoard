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

private struct NoteIDRecord: Decodable { let id: UUID }

class BoardViewModel: ObservableObject {
    @Published var board: Board
    @Published var noteViewModels: [UUID: NoteViewModel] = [:]
    
    // Canvas State
    @Published var offset: CGSize = .zero
    @Published var scale: CGFloat = 1.0
    @Published var isOrganizing: Bool = false
    
    // Last gesture state to handle cumulative panning/zooming
    var lastOffset: CGSize = .zero
    var lastScale: CGFloat = 1.0
    
    // Track local updates to prevent server broadcast feedback loops
    private var lastLocalUpdates: [UUID: Date] = [:]
    private let broadcastBuffer: TimeInterval = 2.0 // Ignore broadcasts for 2s after local change
    
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
                createViewModel(for: note)
            }
        } catch {
            print("Error fetching notes: \(error)")
        }
    }
    
    private func createViewModel(for note: Note) {
        let vm = NoteViewModel(note: note)
        vm.onLocalUpdate = { [weak self] id in
            self?.lastLocalUpdates[id] = Date()
        }
        noteViewModels[note.id] = vm
    }
    
    @MainActor
    private func subscribeToRealtime() async {
        do {
            let client = try supabase.client
            let channel = client.channel("notes_board_\(board.id.uuidString)")
            
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
        } catch {
            print("Error subscribing to realtime: \(error)")
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
                let record: NoteIDRecord = try action.oldRecord.decode()
                noteViewModels.removeValue(forKey: record.id)
            } catch {
                print("Error decoding delete note id: \(error)")
            }
        default:
            break
        }
    }

    private func updateOrAddNote(_ note: Note) {
        // If we recently updated this note locally, ignore incoming broadcasts to prevent jank
        if let lastLocal = lastLocalUpdates[note.id], Date().timeIntervalSince(lastLocal) < broadcastBuffer {
            return
        }

        if let existingVM = noteViewModels[note.id] {
            // Don't interrupt a note that the local user is actively dragging.
            guard !existingVM.isDragging else { return }
            
            if note.updatedAt > existingVM.note.updatedAt {
                withAnimation(.spring()) {
                    existingVM.note = note
                }
            }
        } else {
            createViewModel(for: note)
        }
    }
    
    func updateBackgroundColor(_ color: String) {
        board.backgroundColor = color
        board.updatedAt = Date()
        syncBoard()
    }
    
    func updateBackgroundLayout(_ layout: BackgroundLayout) {
        board.backgroundLayout = layout
        board.updatedAt = Date()
        syncBoard()
    }
    
    private func syncBoard() {
        Task {
            try? await supabase.updateBoard(board)
        }
    }
    
    // Auto-Organize (Phase 4, Step 4)
    @MainActor
    func triggerAutoOrganize() async {
        guard !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }
        do {
            let newPositions = try await supabase.autoOrganize(boardId: board.id)
            for (id, pos) in newPositions {
                if let noteVM = noteViewModels[id] {
                    lastLocalUpdates[id] = Date() // Mark as local update to prevent snap-back
                    withAnimation(.spring(response: 1.0, dampingFraction: 0.7)) {
                        noteVM.note.posX = pos.0
                        noteVM.note.posY = pos.1
                    }
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
        lastLocalUpdates[id] = Date()
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
            template: .plain,
            checklistItems: [],
            createdAt: Date(),
            updatedAt: Date()
        )
        
        lastLocalUpdates[newNote.id] = Date()
        createViewModel(for: newNote)
        
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
