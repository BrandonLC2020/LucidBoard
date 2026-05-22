import Testing
import SwiftUI
@testable import LucidBoard

struct SettingsManagerTests {

    @Test func testSettingsManagerPersistence() async throws {
        let manager = SettingsManager.shared
        
        // Reset to default
        manager.settings = AppSettings()
        
        // Set initial state
        manager.settings.preferredColorScheme = .light
        manager.settings.isSyncEnabled = false
        manager.settings.defaultNoteColor = "#FF0000"
        
        #expect(manager.settings.preferredColorScheme == .light)
        #expect(manager.settings.isSyncEnabled == false)
        #expect(manager.settings.defaultNoteColor == "#FF0000")
        
        // Change state
        manager.settings.preferredColorScheme = .dark
        manager.settings.isSyncEnabled = true
        
        #expect(manager.settings.preferredColorScheme == .dark)
        #expect(manager.settings.isSyncEnabled == true)
    }
}
