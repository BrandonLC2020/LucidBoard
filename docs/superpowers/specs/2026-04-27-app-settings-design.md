# Design Spec: App Settings & Sidebar Navigation

**Date:** 2026-04-27
**Topic:** App Settings, Defaults, and Sidebar Navigation
**Status:** Draft

## 1. Purpose
Enhance LucidBoard with a centralized settings system and a scalable navigation architecture. This allows users to customize their creation experience (default colors/templates) and manage app-wide preferences (theme, cloud sync).

## 2. Architecture & Data Model

### 2.1 AppSettings Model
A structure to hold user preferences, managed by a `SettingsManager` singleton.

```swift
struct AppSettings: Codable {
    var defaultNoteColor: String = "#FFF9C4" // Soft Yellow
    var defaultNoteTemplate: NoteTemplate = .plain
    var defaultBackgroundLayout: BackgroundLayout = .grid
    var preferredColorScheme: AppColorScheme = .system
    var isSyncEnabled: Bool = true
}

enum AppColorScheme: String, Codable, CaseIterable {
    case light, dark, system
}
```

### 2.2 Persistence Strategy (Hybrid)
- **Local:** Uses `@AppStorage` or `UserDefaults` to ensure settings are available immediately on launch, even offline.
- **Cloud:** A new `profiles` table in Supabase will store settings for authenticated users.
    - **Sync Logic:** `SettingsManager` listens for local changes and debounces an update to Supabase. On login, it merges/overwrites local settings with the cloud profile.

### 2.3 Supabase Schema
```sql
CREATE TABLE profiles (
    id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    settings JSONB DEFAULT '{}'::jsonb,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);
```

## 3. UI/UX Design

### 3.1 Sidebar Menu
A custom slide-in drawer replacing the current flat layout.
- **Trigger:** Hamburger icon (`line.3.horizontal`) in the top-left corner.
- **Visuals:** `ultraThinMaterial` blur, left-aligned.
- **Items:**
    - Profile Section (Auth status)
    - Navigation: "Board Canvas", "Settings", "Help" (Placeholder).

### 3.2 Settings View
A full-screen `List` based view.
- **Note Defaults Section:**
    - Default Color (ColorPicker/Swatches)
    - Default Template (Picker)
- **Canvas Section:**
    - Grid Style (Picker: Dots, Grid, Lines, Plain)
- **Appearance Section:**
    - Theme (Segmented Picker: Light, Dark, System)
- **Cloud & Account Section:**
    - Sync Toggle
    - Login/Logout Button

## 4. Components & Responsibilities

- **SettingsManager:** Single source of truth for settings state. Handles persistence logic.
- **SidebarView:** Manages the drawer state and navigation links.
- **SettingsView:** Provides the UI for modifying `AppSettings`.
- **BoardView Updates:**
    - Integrated Sidebar trigger.
    - Observes `SettingsManager` for background changes.
    - Uses default values from `SettingsManager` when creating new notes.

## 5. Success Criteria
- [ ] Users can change the default color for new notes.
- [ ] Users can toggle between Light and Dark mode app-wide.
- [ ] Settings persist across app restarts.
- [ ] Sidebar allows navigating between the board and settings.
- [ ] (Verification) New notes use the configured default color and template.

## 6. Testing Strategy
- **Unit Tests:** `SettingsManager` local persistence and Supabase sync logic.
- **UI Tests:** Verify sidebar opening/closing and navigation to Settings.
- **Integration Tests:** Verify that changing a default setting (e.g., color) immediately impacts the `addNote` behavior in `BoardViewModel`.
