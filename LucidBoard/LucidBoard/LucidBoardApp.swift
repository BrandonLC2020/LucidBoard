//
//  LucidBoardApp.swift
//  LucidBoard
//
//  Created by Brandon Lamer-Connolly on 4/13/26.
//

import SwiftUI

@main
struct LucidBoardApp: App {
    @StateObject private var boardVM = BoardViewModel(board: Board(
        id: UUID(),
        userId: UUID(),
        title: "My First Board",
        backgroundColor: "#FFFFFF",
        backgroundLayout: .grid,
        createdAt: Date(),
        updatedAt: Date()
    ))
    
    var body: some Scene {
        WindowGroup {
            BoardView(viewModel: boardVM)
        }
    }
}
