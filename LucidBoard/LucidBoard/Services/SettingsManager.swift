import Foundation
import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("app_settings") private var settingsData: Data = Data()
    
    @Published var settings: AppSettings {
        didSet {
            save()
        }
    }
    
    private init() {
        let data = UserDefaults.standard.data(forKey: "app_settings") ?? Data()
        if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            settingsData = encoded
        }
    }
}
