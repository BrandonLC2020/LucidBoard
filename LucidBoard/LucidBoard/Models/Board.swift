//
//  Board.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import Foundation

enum BackgroundLayout: String, Codable, CaseIterable {
    case grid
    case dotGrid = "dot_grid"
    case horizontalLines = "horizontal_lines"
    case verticalLines = "vertical_lines"
    case plain
}

struct Board: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    var title: String
    var backgroundColor: String
    var backgroundLayout: BackgroundLayout
    var createdAt: Date
    var updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case backgroundColor = "background_color"
        case backgroundLayout = "background_layout"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
