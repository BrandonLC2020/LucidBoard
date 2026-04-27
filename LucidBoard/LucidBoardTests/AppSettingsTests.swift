import Testing
@testable import LucidBoard

struct AppSettingsTests {

    @Test func testAppSettingsInitialization() {
        let settings = AppSettings()
        
        #expect(settings.preferredColorScheme == .system)
        #expect(settings.isSyncEnabled == true)
        #expect(settings.defaultNoteColor == "#FFF9C4")
        #expect(settings.defaultNoteTemplate == .plain)
        #expect(settings.defaultBackgroundLayout == .grid)
    }
}
