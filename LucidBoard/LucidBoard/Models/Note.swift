//
//  Note.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import Foundation

enum NoteTemplate: String, Codable, CaseIterable {
    case plain
    case checklist
    case lined
    case circle
    case diamond
}

struct ChecklistItem: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var isCompleted: Bool
    
    init(id: UUID = UUID(), text: String = "", isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }
}

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    let boardId: UUID
    let userId: UUID
    var contentText: String?
    var contentDrawing: Data?
    var color: String
    var posX: Float
    var posY: Float
    var zIndex: Int
    var template: NoteTemplate
    var checklistItems: [ChecklistItem]?
    var createdAt: Date
    var updatedAt: Date
    
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
}
