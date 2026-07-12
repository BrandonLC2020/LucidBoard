//
//  LucidBoardApp.swift
//  LucidBoard
//
//  Created by Brandon Lamer-Connolly on 4/13/26.
//

import SwiftUI

private struct AppRepositoryKey: EnvironmentKey {
    static let defaultValue: AppRepository = SupabaseRepository()
}

extension EnvironmentValues {
    var appRepository: AppRepository {
        get { self[AppRepositoryKey.self] }
        set { self[AppRepositoryKey.self] = newValue }
    }
}

@main
struct LucidBoardApp: App {
    private let appRepository: AppRepository
    @StateObject private var settingsManager: SettingsManager
    @StateObject private var boardVM: BoardViewModel

    init() {
        FontRegistrar.registerBundledFonts()

        let repo = AppRepositoryFactory.makeFromBundle()
        self.appRepository = repo
        let initialBoard = Board(
            id: UUID(),
            userId: UUID(),
            title: "My First Board",
            backgroundColor: "#FFFFFF",
            backgroundLayout: .grid,
            createdAt: Date(),
            updatedAt: Date()
        )
        _settingsManager = StateObject(wrappedValue: SettingsManager(repository: repo))
        _boardVM = StateObject(wrappedValue: BoardViewModel(board: initialBoard, repository: repo))

        Task { try? await repo.signInAnonymously() }
    }

    var body: some Scene {
        WindowGroup {
            BoardView(viewModel: boardVM)
                .environment(\.appRepository, appRepository)
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
