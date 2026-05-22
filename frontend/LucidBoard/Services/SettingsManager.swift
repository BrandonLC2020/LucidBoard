import Foundation
import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager(repository: AppRepositoryFactory.makeFromBundle())

    @AppStorage("app_settings") private var settingsData: Data = Data()

    @Published var settings: AppSettings {
        didSet {
            save()
            if settings.isSyncEnabled {
                syncSubject.send(settings)
            }
        }
    }

    private let repository: AppRepository
    private let syncSubject = PassthroughSubject<AppSettings, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(repository: AppRepository) {
        self.repository = repository
        let data = UserDefaults.standard.data(forKey: "app_settings") ?? Data()
        if let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }

        setupSync()

        // Initial fetch if logged in
        Task {
            await fetchRemoteSettings()
        }
    }

    private func setupSync() {
        syncSubject
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] settings in
                guard let self else { return }
                Task { try? await self.repository.updateProfile(settings: settings) }
            }
            .store(in: &cancellables)
    }

    private func fetchRemoteSettings() async {
        guard settings.isSyncEnabled else { return }
        do {
            if let remoteSettings = try await repository.fetchProfile() {
                await MainActor.run {
                    self.settings = remoteSettings
                }
            }
        } catch {
            // Silently fail if not logged in or network error
            print("Settings sync: \(error.localizedDescription)")
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            settingsData = encoded
        }
    }
}
