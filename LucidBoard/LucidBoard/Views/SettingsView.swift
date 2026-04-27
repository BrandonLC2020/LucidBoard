//
//  SettingsView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var settingsManager = SettingsManager.shared

    var body: some View {
        List {
            Section("Note Defaults") {
                ColorPicker("Default Color", selection: Binding(
                    get: { Color(hex: settingsManager.settings.defaultNoteColor) },
                    set: { settingsManager.settings.defaultNoteColor = $0.toHex() ?? "#FFF9C4" }
                ))

                Picker("Default Template", selection: $settingsManager.settings.defaultNoteTemplate) {
                    ForEach(NoteTemplate.allCases, id: \.self) { template in
                        Text(template.rawValue.capitalized).tag(template)
                    }
                }
            }

            Section("Canvas") {
                Picker("Default Layout", selection: $settingsManager.settings.defaultBackgroundLayout) {
                    ForEach(BackgroundLayout.allCases, id: \.self) { layout in
                        Text(layout.rawValue.capitalized).tag(layout)
                    }
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $settingsManager.settings.preferredColorScheme) {
                    ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.rawValue.capitalized).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
