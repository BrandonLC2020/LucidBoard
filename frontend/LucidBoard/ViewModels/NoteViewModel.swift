//
//  NoteViewModel.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI
import Combine

class NoteViewModel: ObservableObject, Identifiable {
    @Published var note: Note
    @Published var isDragging: Bool = false
    /// Raw PencilKit drawing data. Kept as `Data` (not `PKDrawing`) so this view model stays
    /// buildable on platforms without PencilKit (native macOS); only `PencilKitView` — compiled
    /// for iOS/visionOS only — knows how to interpret the bytes.
    @Published var drawingData: Data?

    // Callback to notify the board of local changes
    var onLocalUpdate: ((UUID) -> Void)?
    // Callback to surface a failed sync to the board (and, from there, the user)
    var onSyncError: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private let repository: AppRepository

    init(note: Note, repository: AppRepository) {
        self.note = note
        self.repository = repository
        self.drawingData = note.contentDrawing

        // Observe drawing changes
        $drawingData
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] newData in
                guard let self else { return }
                self.note.contentDrawing = newData
                self.syncNote()
            }
            .store(in: &cancellables)
    }

    func syncNote() {
        self.note.updatedAt = Date()
        onLocalUpdate?(note.id)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.upsertNote(self.note)
            } catch {
                await MainActor.run { self.onSyncError?() }
            }
        }
    }

    var id: UUID { note.id }

    func updatePosition(to point: CGPoint) {
        note.posX = Float(point.x)
        note.posY = Float(point.y)
        onLocalUpdate?(note.id)
    }

    func finalizePosition() { syncNote() }

    // Template & Checklist Actions

    func updateTemplate(_ template: NoteTemplate) {
        note.template = template
        if template == .checklist && (note.checklistItems == nil || note.checklistItems?.isEmpty == true) {
            note.checklistItems = [ChecklistItem()]
        }
        syncNote()
    }

    func addChecklistItem() {
        if note.checklistItems == nil { note.checklistItems = [] }
        note.checklistItems?.append(ChecklistItem())
        syncNote()
    }

    func toggleChecklistItem(id: UUID) {
        if let index = note.checklistItems?.firstIndex(where: { $0.id == id }) {
            note.checklistItems?[index].isCompleted.toggle()
            syncNote()
        }
    }

    func updateChecklistItemText(id: UUID, text: String) {
        if let index = note.checklistItems?.firstIndex(where: { $0.id == id }) {
            note.checklistItems?[index].text = text
            syncNote()
        }
    }

    func deleteChecklistItem(id: UUID) {
        note.checklistItems?.removeAll(where: { $0.id == id })
        syncNote()
    }
}
