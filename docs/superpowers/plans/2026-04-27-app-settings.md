# App Settings & Sidebar Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a centralized settings system with local/cloud sync and a sidebar-based navigation architecture.

**Architecture:** Use a `SettingsManager` singleton to coordinate `@AppStorage` for local persistence and Supabase for cloud profiles. Transition the main UI to a sidebar-drawer layout.

**Tech Stack:** SwiftUI, Supabase, Combine.

---

### Task 1: Data Model & Local Persistence

**Files:**
- Create: `LucidBoard/LucidBoard/Models/AppSettings.swift`
- Create: `LucidBoard/LucidBoard/Services/SettingsManager.swift`

- [ ] **Step 1: Define AppSettings and AppColorScheme**

```swift
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
```

- [ ] **Step 2: Implement SettingsManager with local persistence**

```swift
import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @AppStorage("app_settings") private var settingsData: Data = Data()
    
    @Published var settings: AppSettings = AppSettings() {
        didSet {
            saveLocally()
        }
    }
    
    private init() {
        loadLocally()
    }
    
    private func loadLocally() {
        if let decoded = try? JSONDecoder().decode(AppSettings.self, from: settingsData) {
            self.settings = decoded
        }
    }
    
    private func saveLocally() {
        if let encoded = try? JSONEncoder().encode(settings) {
            settingsData = encoded
        }
    }
}
```

- [ ] **Step 3: Verify local persistence in a test**
Run: `xcode-native ExecuteSnippet` with a script that modifies settings, restarts "manager", and asserts equality.

- [ ] **Step 4: Commit**
```bash
git add LucidBoard/LucidBoard/Models/AppSettings.swift LucidBoard/LucidBoard/Services/SettingsManager.swift
git commit -m "feat: add AppSettings model and local SettingsManager"
```

---

### Task 2: Supabase Schema & Sync Logic

**Files:**
- Modify: `SCHEMA.sql`
- Modify: `LucidBoard/LucidBoard/Services/SupabaseService.swift`
- Modify: `LucidBoard/LucidBoard/Services/SettingsManager.swift`

- [ ] **Step 1: Add profiles table to SCHEMA.sql**

```sql
CREATE TABLE IF NOT EXISTS profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    settings JSONB DEFAULT '{}'::jsonb,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
```

- [ ] **Step 2: Extend SupabaseService for profiles**

```swift
// In SupabaseService.swift
func fetchProfile() async throws -> AppSettings? {
    let user = try await client.auth.session.user
    let profile: [String: AppSettings]? = try await client.from("profiles")
        .select("settings")
        .eq("id", value: user.id)
        .single()
        .execute()
        .value
    return profile?["settings"]
}

func updateProfile(settings: AppSettings) async throws {
    let user = try await client.auth.session.user
    try await client.from("profiles")
        .upsert(["id": user.id.uuidString, "settings": settings, "updated_at": Date()])
        .execute()
}
```

- [ ] **Step 3: Add cloud sync logic to SettingsManager**
Use a `PassthroughSubject` to debounce sync calls.

- [ ] **Step 4: Commit**
```bash
git add SCHEMA.sql LucidBoard/LucidBoard/Services/SupabaseService.swift LucidBoard/LucidBoard/Services/SettingsManager.swift
git commit -m "feat: add Supabase profile sync logic"
```

---

### Task 3: Sidebar UI Implementation

**Files:**
- Create: `LucidBoard/LucidBoard/Views/SidebarView.swift`
- Modify: `LucidBoard/LucidBoard/Views/BoardView.swift`

- [ ] **Step 1: Create SidebarView**

```swift
import SwiftUI

struct SidebarView: View {
    @Binding var isShowing: Bool
    @Binding var navigationPath: NavigationPath
    
    var body: some View {
        ZStack {
            if isShowing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { isShowing = false }
                
                HStack {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("LucidBoard")
                            .font(.title.bold())
                            .padding(.top, 60)
                        
                        Divider()
                        
                        Button(action: { isShowing = false }) {
                            Label("Board Canvas", systemImage: "square.grid.2x2")
                        }
                        
                        Button(action: { 
                            isShowing = false
                            navigationPath.append("settings")
                        }) {
                            Label("App Settings", systemImage: "gearshape.fill")
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .frame(width: 280)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .leading))
                    
                    Spacer()
                }
            }
        }
        .animation(.easeInOut, value: isShowing)
    }
}
```

- [ ] **Step 2: Update BoardView to include Sidebar**
Wrap content in `NavigationStack` and add the Hamburger button.

- [ ] **Step 3: Commit**
```bash
git add LucidBoard/LucidBoard/Views/SidebarView.swift LucidBoard/LucidBoard/Views/BoardView.swift
git commit -m "feat: implement sidebar navigation drawer"
```

---

### Task 4: Settings UI Implementation

**Files:**
- Create: `LucidBoard/LucidBoard/Views/SettingsView.swift`

- [ ] **Step 1: Implement SettingsView**

```swift
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
```

- [ ] **Step 2: Commit**
```bash
git add LucidBoard/LucidBoard/Views/SettingsView.swift
git commit -m "feat: implement SettingsView with preference controls"
```

---

### Task 5: Integration & Default Application

**Files:**
- Modify: `LucidBoard/LucidBoard/ViewModels/BoardViewModel.swift`
- Modify: `LucidBoard/LucidBoard/LucidBoardApp.swift`

- [ ] **Step 1: Update BoardViewModel to use defaults**

```swift
// In BoardViewModel.swift -> addNote(at:)
let settings = SettingsManager.shared.settings
let newNote = Note(
    // ... other fields
    color: settings.defaultNoteColor,
    template: settings.defaultNoteTemplate,
    // ...
)
```

- [ ] **Step 2: Apply AppColorScheme in LucidBoardApp**

```swift
// In LucidBoardApp.swift
WindowGroup {
    BoardView(viewModel: boardVM)
        .preferredColorScheme(colorScheme)
}

private var colorScheme: Color? {
    switch SettingsManager.shared.settings.preferredColorScheme {
    case .light: return .light
    case .dark: return .dark
    case .system: return nil
    }
}
```

- [ ] **Step 3: Final Verification**
Verify:
1. Opening sidebar navigates to Settings.
2. Changing default color in Settings applies to new notes.
3. Theme toggle changes app appearance.

- [ ] **Step 4: Commit**
```bash
git add LucidBoard/LucidBoard/ViewModels/BoardViewModel.swift LucidBoard/LucidBoard/LucidBoardApp.swift
git commit -m "feat: integrate app settings into note creation and theming"
```
