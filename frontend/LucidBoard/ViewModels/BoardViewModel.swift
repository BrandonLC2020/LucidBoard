//
//  BoardViewModel.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI
import Combine

class BoardViewModel: ObservableObject {
    @Published var board: Board
    @Published var noteViewModels: [UUID: NoteViewModel] = [:]

    // Canvas State
    @Published var offset: CGSize = .zero
    @Published var scale: CGFloat = 1.0
    @Published var isOrganizing: Bool = false
    @Published var syncError: String?

    private var syncErrorDismissTask: Task<Void, Never>?
    private let syncErrorAutoDismiss: TimeInterval = 5.0

    // Last gesture state to handle cumulative panning/zooming
    var lastOffset: CGSize = .zero
    var lastScale: CGFloat = 1.0

    // Track local updates to prevent server broadcast feedback loops
    private var lastLocalUpdates: [UUID: Date] = [:]
    private let broadcastBuffer: TimeInterval = 2.0 // Ignore broadcasts for 2s after local change

    private let repository: AppRepository
    private var subscription: NoteSubscription?

    init(board: Board, repository: AppRepository) {
        self.board = board
        self.repository = repository

        Task {
            await fetchNotes()
            await MainActor.run { self.subscribe() }
        }
    }

    deinit { subscription?.cancel() }

    @MainActor
    func fetchNotes() async {
        do {
            let notes = try await repository.fetchNotes(boardId: board.id)
            for note in notes {
                createViewModel(for: note)
            }
        } catch {
            setSyncError("Couldn't load your notes. Check your connection and try again.")
        }
    }

    private func createViewModel(for note: Note) {
        let vm = NoteViewModel(note: note, repository: repository)
        vm.onLocalUpdate = { [weak self] id in self?.lastLocalUpdates[id] = Date() }
        vm.onSyncError = { [weak self] in self?.setSyncError("Couldn't save your changes. They're only stored on this device for now.") }
        noteViewModels[note.id] = vm
    }

    /// Surfaces a failed sync instead of letting it fail silently. Optimistic local edits stay
    /// on screen either way, so a swallowed error would otherwise read to the user as "saved."
    @MainActor
    private func setSyncError(_ message: String) {
        syncError = message
        syncErrorDismissTask?.cancel()
        syncErrorDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.syncErrorAutoDismiss ?? 5.0))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.syncError = nil }
        }
    }

    @MainActor
    func dismissSyncError() {
        syncErrorDismissTask?.cancel()
        syncError = nil
    }

    @MainActor
    private func subscribe() {
        subscription = repository.subscribeToNotes(boardId: board.id) { [weak self] change in
            Task { @MainActor in self?.handleChange(change) }
        }
    }

    @MainActor
    private func handleChange(_ change: NoteChange) {
        switch change {
        case .upsert(let note): updateOrAddNote(note)
        case .delete(let id): noteViewModels.removeValue(forKey: id)
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
        Task { @MainActor in
            do {
                try await repository.updateBoard(board)
            } catch {
                setSyncError("Couldn't save your board settings. They're only stored on this device for now.")
            }
        }
    }

    // Auto-Organize
    @MainActor
    func triggerAutoOrganize() async {
        guard !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }
        do {
            let newPositions = try await repository.autoOrganize(boardId: board.id)
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
            setSyncError("Auto-Organize couldn't complete. Check your connection and try again.")
        }
    }

    @MainActor
    func deleteNote(id: UUID) {
        noteViewModels.removeValue(forKey: id)
        Task { @MainActor in
            do {
                try await repository.deleteNote(id: id)
            } catch {
                setSyncError("Couldn't delete that note. It may reappear once you're back online.")
            }
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
        let settings = SettingsManager.shared.settings
        let newNote = Note(
            id: UUID(),
            boardId: board.id,
            userId: board.userId,
            contentText: "",
            contentDrawing: nil,
            color: settings.defaultNoteColor,
            posX: Float(point.x),
            posY: Float(point.y),
            zIndex: (noteViewModels.values.map { $0.note.zIndex }.max() ?? 0) + 1,
            template: settings.defaultNoteTemplate,
            checklistItems: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        lastLocalUpdates[newNote.id] = Date()
        createViewModel(for: newNote)

        Task { @MainActor in
            do {
                try await repository.upsertNote(newNote)
            } catch {
                setSyncError("Couldn't save your new note. It's only stored on this device for now.")
            }
        }
    }

    // Canvas transformation logic
    func handlePanGesture(_ translation: CGSize) {
        offset = CGSize(
            width: lastOffset.width + translation.width,
            height: lastOffset.height + translation.height
        )
    }

    func finalizePanGesture() { lastOffset = offset }

    func handleZoomGesture(_ magnification: CGFloat) { scale = lastScale * magnification }

    func finalizeZoomGesture() { lastScale = scale }
}
