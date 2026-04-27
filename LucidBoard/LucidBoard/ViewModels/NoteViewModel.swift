//
//  NoteViewModel.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI
import Combine
import PencilKit

class NoteViewModel: ObservableObject, Identifiable {
    @Published var note: Note
    @Published var isDragging: Bool = false
    @Published var drawing: PKDrawing = PKDrawing()
    
    // Callback to notify the board of local changes
    var onLocalUpdate: ((UUID) -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    private let supabase = SupabaseService.shared
    
    init(note: Note) {
        self.note = note
        
        // Deserialize drawing if present
        if let drawingData = note.contentDrawing {
            do {
                self.drawing = try PKDrawing(data: drawingData)
            } catch {
                print("Error deserializing drawing: \(error)")
            }
        }
        
        // Observe drawing changes
        $drawing
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] newDrawing in
                guard let self = self else { return }
                self.note.contentDrawing = newDrawing.dataRepresentation()
                self.syncNote()
            }
            .store(in: &cancellables)
    }
    
    func syncNote() {
        self.note.updatedAt = Date()
        onLocalUpdate?(note.id)
        Task {
            try? await supabase.upsertNote(self.note)
        }
    }
    
    var id: UUID { note.id }
    
    func updatePosition(to point: CGPoint) {
        note.posX = Float(point.x)
        note.posY = Float(point.y)
        onLocalUpdate?(note.id)
    }
    
    func finalizePosition() {
        syncNote()
    }
    
    // Template & Checklist Actions
    
    func updateTemplate(_ template: NoteTemplate) {
        note.template = template
        if template == .checklist && (note.checklistItems == nil || note.checklistItems?.isEmpty == true) {
            note.checklistItems = [ChecklistItem()]
        }
        syncNote()
    }
    
    func addChecklistItem() {
        if note.checklistItems == nil {
            note.checklistItems = []
        }
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
