# PLAN.md: LucidBoard Implementation Plan

## 1. Background & Motivation
LucidBoard is a spatial, infinite-canvas sticky note application tailored for iPadOS and macOS. The application leverages a "lucid" aesthetic with floating toolbars and frosted glass overlays. Its core functionality enables a digital workspace analogous to physical sticky notes, enhanced by real-time synchronization via Supabase and AI-driven spatial clustering using `pgvector`. 

The iOS counterpart will act as a lightweight companion app primarily for quick text entry, while iPadOS utilizes Apple's PencilKit (`PKCanvasView`) for sub-millisecond drawing latency.

## 2. Scope & Impact
This plan outlines the architecture, database layout, UI components, and the step-by-step rollout across four implementation phases.
The implementation incorporates:
- **State Management:** Granular ViewModels (`@ObservedObject` per note) to strictly isolate view updates, maximizing canvas rendering performance.
- **Sync Strategy:** Optimistic UI Updates for fluid manipulation (drag, zoom, color changes) before confirming with the Supabase Realtime backend.
- **Tech Stack:** SwiftUI, Supabase SDK (Swift), PencilKit, PostgreSQL (`pgvector`), and Supabase Edge Functions.

## 3. Proposed Solution

### 3.1. Architecture & State Management
We will employ a robust MVVM pattern configured for structured concurrency:
- **`BoardViewModel`:** Manages the overall canvas state (zoom, pan offset) and a collection of note models. It tracks note IDs rather than full object states to avoid triggering broad view invalidations.
- **`NoteViewModel`:** Granular `@ObservedObject` for each individual note. It handles its own X/Y coordinates, `PKDrawing` serialization, color state, and sync status. Updates to a single note will only trigger re-renders for that specific view.

### 3.2. Real-Time Synchronization
- **Supabase Realtime Channel:** Subscribed to the `notes` table filtered by `board_id`.
- **Optimistic Updates:** When a user moves or edits a note, the UI will reflect the change instantly. The `NoteViewModel` will debounce network calls (e.g., 300ms) and dispatch updates to Supabase. If an error occurs, the UI will roll back to the last known server state.

### 3.3. Infinite Canvas Implementation
- **Coordinate Space:** A highly optimized 2D coordinate system using native SwiftUI gestures (`MagnificationGesture`, `DragGesture`). 
- **View Hierarchy:** A base `ZStack` containing iterative `NoteView`s, wrapped in a `GeometryReader`. The view will apply `.scaleEffect` and `.offset` to the container while individual notes maintain their relative spatial positions.

## 4. Implementation Plan

### Phase 1: Local Canvas & UI Foundation
- **Step 1:** Configure the Xcode project, enabling macOS and iOS targets. Set up basic app lifecycle (`LucidBoardApp`).
- **Step 2:** Implement the infinite canvas engine. Create gesture handlers to manage the `BoardViewModel`'s zoom scale and pan offset.
- **Step 3:** Develop the "lucid" UI elements: frosted glass (`.background(.ultraThinMaterial)`), floating toolbars, and custom shadow properties (`.shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)`).
- **Step 4:** Build the fundamental `NoteView` component with interactive spring animations for dragging.

### Phase 2: Input & PencilKit
- **Step 1:** Create a PencilKit wrapper `UIViewRepresentable` (`PKCanvasView`) tailored for the iPadOS target.
- **Step 2:** Integrate the PencilKit canvas into the `NoteView`, ensuring touch events are distinct from canvas panning gestures.
- **Step 3:** Implement serialization logic to convert `PKDrawing` data to `Data` (bytea) for storage, and deserialization back into views.

### Phase 3: Supabase Integration & Sync
- **Step 1:** Integrate the Supabase Swift SDK via Swift Package Manager.
- **Step 2:** Set up `auth.users`, `boards`, and `notes` tables in PostgreSQL matching the schema detailed in the Spec.
- **Step 3:** Implement Supabase Authentication (Anonymous or Email/Password).
- **Step 4:** Develop the `SupabaseService` class to handle CRUD operations.
- **Step 5:** Wire up Supabase Realtime subscriptions to push updates to active `NoteViewModel`s. Establish the debounce and optimistic update logic.

### Phase 4: AI & pgvector
- **Step 1:** Deploy the `pgvector` extension on the Supabase instance. Add the `embedding` column to the `notes` table.
- **Step 2:** Write a Supabase Edge Function to generate text embeddings upon note creation/modification (using an external provider like OpenAI/Gemini).
- **Step 3:** Write a Postgres RPC (`match_notes`) to calculate cosine similarity and perform spatial grouping logic based on embeddings.
- **Step 4:** Implement the frontend "Auto-Cluster" action. Upon receiving updated coordinates from the RPC, animate the notes into their new clusters via SwiftUI's `withAnimation`.

## 5. Verification & Testing
- **Unit Tests:** Verify `PKDrawing` serialization, state management transitions within `NoteViewModel`, and gesture math (coordinate translation).
- **UI Tests:** Simulate iPad touch gestures, verify dragging, and ensure "frosted glass" modifiers render correctly without visual glitches.
- **Integration Tests:** Test Supabase service calls, Realtime payload parsing, and verify Edge Function embedding outputs map correctly to simulated data.

## 6. Migration & Rollback
- **Database Migrations:** SQL migrations will be managed within the Supabase dashboard (or CLI), ensuring that `pgvector` index creation can be cleanly rolled back if performance issues arise.
- **UI Degradation:** If `PKCanvasView` fails on an unsupported device profile, fallback gracefully to a standard `TextEditor`.
- **Sync Failure:** If optimistic sync calls repeatedly fail, flag the note visually (e.g., a subtle red outline) and offer a manual retry mechanism.