//
//  LucidBoardApp.swift
//  LucidBoard
//
//  Created by Brandon Lamer-Connolly on 4/13/26.
//

import SwiftUI

@main
struct LucidBoardApp: App {
    @StateObject private var settingsManager = SettingsManager.shared
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
                .preferredColorScheme(colorScheme)
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch settingsManager.settings.preferredColorScheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}
