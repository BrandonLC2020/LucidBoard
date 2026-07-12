# SPEC.md: LucidBoard

## 1. Project Overview
**LucidBoard** is a spatial, infinite-canvas sticky note application tailored for iPadOS and macOS. It translates the tactile satisfaction of physical sticky notes into a digital workspace, supercharged by AI clustering, semantic organization, and real-time synchronization. The iOS counterpart will serve as a lightweight companion app for quick data entry.

**Design Philosophy:**
The UI must be entirely unobtrusive, leveraging a "lucid" aesthetic. The interface should rely on floating toolbars and reactive, translucent components (frosted/liquid glass) to allow the spatial canvas and the user's content to take center stage.

## 2. Technology Stack
* **Target Platforms:** iPadOS (Primary), macOS (Primary), iOS (Companion).
* **Frontend Framework:** SwiftUI.
* **Drawing & Touch:** PencilKit (`PKCanvasView`), native SwiftUI Gestures (`MagnificationGesture`, `DragGesture`).
* **Backend & Auth:** Supabase (Swift SDK).
* **Database:** PostgreSQL (via Supabase).
* **AI & Vector Storage:** Supabase `pgvector` extension + Supabase Edge Functions (for embedding generation).
* **Architecture Pattern:** MVVM (Model-View-ViewModel) with structured concurrency (Swift `async/await`).

## 3. Core Features & Implementation Mandates

### 3.1. The Infinite Canvas
* **Implementation:** Must utilize a highly optimized 2D coordinate system. 
* **Interaction:** * Mac: Trackpad panning and two-finger pinch-to-zoom.
    * iPad: Multi-touch panning and zooming. 
* **Performance:** Canvas nodes (notes) must be efficiently rendered. Avoid re-rendering the entire canvas when a single note's state changes.

### 3.2. Note Taking & PencilKit
* **Pencil Support:** Utilize `PKCanvasView` for sub-millisecond drawing latency on iPadOS. 
* **Data Structure:** Notes should support both raw text input (for keyboard/companion app entry) and `PKDrawing` data serialization for handwritten notes.

### 3.3. Real-Time Synchronization
* **Supabase Realtime:** The canvas must reflect changes across devices instantly. Use Supabase Realtime channels to broadcast cursor positions (optional) and note updates (X/Y coordinates, content edits, color changes).
* **Conflict Resolution:** Implement basic "last-write-wins" for note edits, relying on Postgres timestamps.

### 3.4. AI Auto-Clustering
* **Embedding Pipeline:** When a note is created or updated, trigger a Supabase Edge Function to generate a text embedding (e.g., using OpenAI or Gemini APIs).
* **Storage:** Store the resulting vector in a `pgvector` column on the `notes` table.
* **Clustering Action:** When the user triggers "Auto-Organize," execute a Postgres RPC (Remote Procedure Call) to perform a similarity search. Group notes with high cosine similarity by updating their spatial X/Y coordinates to form clusters on the canvas.

## 4. UI/UX & Styling Rules
**Coding Agent, strictly adhere to the following visual constraints:**
1.  **Material Design:** Use `.background(.ultraThinMaterial)` for all floating toolbars, menus, and overlays to achieve the "liquid glass" aesthetic.
2.  **No Rigid Sidebars:** Avoid standard `NavigationSplitView` or heavy sidebars for the primary canvas view. Controls must float over the canvas.
3.  **Depth & Shadows:** Use subtle, custom shadows (`.shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)`) to lift notes and UI elements off the canvas background.
4.  **Note Aesthetics:** Sticky notes should not be flat colored squares. Give them slight gradients, corner radii, and interactive spring animations (`.animation(.spring(), value: isDragging)`) when picked up or moved.

## 5. Database Schema (Supabase)

### `boards` Table
* `id`: UUID (Primary Key)
* `user_id`: UUID (Foreign Key -> auth.users)
* `title`: String
* `created_at`: Timestamp
* `updated_at`: Timestamp

### `notes` Table
* `id`: UUID (Primary Key)
* `board_id`: UUID (Foreign Key -> boards.id)
* `user_id`: UUID (Foreign Key -> auth.users)
* `content_text`: Text (Optional)
* `content_drawing`: Bytea / Data (For PKDrawing serialization, Optional)
* `color`: String (Hex code)
* `pos_x`: Float
* `pos_y`: Float
* `z_index`: Integer
* `embedding`: vector(1536) (pgvector column)
* `created_at`: Timestamp
* `updated_at`: Timestamp

## 6. Project Phasing & Milestones

* **Phase 1: Local Canvas & UI Foundation**
    * Setup SwiftUI project with cross-platform targets (macOS, iOS).
    * Implement the infinite panning/zooming canvas.
    * Create the frosted-glass floating toolbar.
    * Implement basic draggable note components.
* **Phase 2: Input & PencilKit**
    * Integrate `PKCanvasView` into the note component for iPadOS.
    * Handle serialization/deserialization of drawing data.
* **Phase 3: Supabase Integration & Sync**
    * Configure Supabase Auth and initialize the Postgres database.
    * Implement CRUD operations for Boards and Notes.
    * Wire up Supabase Realtime subscriptions for live canvas updates.
* **Phase 4: AI & pgvector**
    * Write Supabase Edge Functions for embedding generation.
    * Implement the `pgvector` similarity search logic.
    * Build the frontend "Auto-Cluster" animation logic to move notes into groups.

## 7. Agent Instructions
* Write modular, composable SwiftUI views. Keep the canvas logic separate from the note rendering logic.
* Ensure all network calls and database interactions are isolated in dedicated Service or Repository classes, not directly in the SwiftUI Views.
* Prioritize native Apple APIs and avoid third-party Swift packages unless absolutely necessary (excluding the Supabase SDK).
* Document complex spatial math (calculating offsets, zoom scales, and screen-to-canvas coordinate conversions) thoroughly.
