import Foundation

enum AppColorScheme: String, Codable, CaseIterable {
    case light, dark, system
}

struct AppSettings: Codable, Equatable {
    var defaultNoteColor: String = "#FFF9C4"
    var defaultNoteTemplate: NoteTemplate = .plain
    var defaultBackgroundLayout: BackgroundLayout = .grid
    var preferredColorScheme: AppColorScheme = .system
    var isSyncEnabled: Bool = true
}
