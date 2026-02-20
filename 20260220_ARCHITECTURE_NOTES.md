# ARCHITECTURE_NOTES.md

> Generated from repository scan on **2026-02-20**.  
> No existing `ARCHITECTURE_NOTES.md` found inside the ZIP. (**UNKNOWN** whether an older version exists outside the ZIP.)

## Big Files List (Top 15 by lines)
| Datei (relativ) | Zeilen |
|---|---:|
| Mainscreen/Details/DetailsSchemaBuilderView.swift | 725 |
| Mainscreen/NodeDetailShared/MarkdownTextView.swift | 661 |
| GraphCanvas/GraphCanvasView+Rendering.swift | 532 |
| Settings/Appearance/DisplaySettingsView.swift | 529 |
| Models.swift | 515 |
| Mainscreen/EntityDetail/EntityAttributesAllListModel.swift | 510 |
| Onboarding/OnboardingSheetView.swift | 504 |
| Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift | 493 |
| Mainscreen/EntityDetail/EntityDetailView+AttributesSection.swift | 460 |
| GraphCanvas/GraphCanvasDataLoader.swift | 411 |
| Mainscreen/NodeDetailShared/NodeImagesManageView.swift | 410 |
| Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift | 394 |
| Mainscreen/EntitiesHome/EntitiesHomeView.swift | 384 |
| Mainscreen/EntitiesHome/EntitiesHomeLoader.swift | 371 |
| Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift | 362 |

### Why “big files” are risky here
- SwiftUI views in large files tend to accumulate multiple responsibilities (data loading, state, UI layout, actions, sheets).
- With Swift 6 + “Default Actor Isolation: MainActor”, big files also tend to accumulate concurrency annotations and warnings.
- Incremental compile performance suffers when “one file changes everything”.

## Hot path analysis

### Rendering / scrolling
1) **Graph canvas render/physics loop**
- Files:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Gestures.swift`
- Why it’s hot:
  - Physics + rendering is potentially running at high frequency (per frame / timer).
  - Any allocations inside tight loops (arrays/dicts) will show up as jank and battery burn.
- What’s already good:
  - Render caches are explicitly stored in state (`labelCache`, `imagePathCache`, `iconSymbolCache`) in `GraphCanvasScreen.swift` to avoid SwiftData fetches on render.
- Primary risks:
  - **MainActor contention** if physics updates drive large `@State` diffs frequently.
  - **Excessive view invalidation** if caches/positions update too broadly.

2) **Entities Home search + counts**
- Files:
  - UI: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` (+ `EntitiesHomeList/Grid`)
  - Loader: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Why it’s hot:
  - Typing in search can trigger repeated reloads.
  - Counts require scanning attributes/links unless cached.
- What’s already good:
  - Loader is an **actor** returning value-only `EntitiesHomeSnapshot`.
  - Counts have a small TTL cache (`countsCacheTTLSeconds = 8`) and can be toggled.
- Remaining risk:
  - Feature creep: UI options can create “derived state explosions” (lots of toggles driving reload keys).

3) **Node detail media galleries / manage screens**
- Files:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - `BrainMesh/Attachments/*` (hydration, thumbnails, import pipeline)
- Why it’s hot:
  - Media screens naturally involve I/O (externalStorage fetch), image decode, thumbnail generation.
- What’s already good:
  - Global throttles via `AsyncLimiter` and per-id “in-flight” de-dupe exist in hydrators/stores.
  - Background container injection from `BrainMeshApp.init()` is in place.
- Remaining risk:
  - Prefetch/hydration might still run at inconvenient times if not carefully gated (especially on navigation).

### Sync / storage
- Core file: `BrainMesh/BrainMeshApp.swift`
  - CloudKit-backed SwiftData config by default.
  - Release fallback to local-only storage when CloudKit init fails.
- Migration helpers:
  - `BrainMesh/GraphBootstrap.swift` (legacy records missing `graphID`)
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (avoid store-unfriendly OR predicates)
- Primary risks:
  - **Silent mode change** in Release: app may become local-only without the user noticing unless Settings surfaces it.
  - **Schema evolution**: SwiftData/CloudKit schema changes can be painful; current code tries to keep schema stable using scalar ids + optional graphID for gentle migration.

### Concurrency
- Baseline: project compiled with Swift 6 & MainActor default isolation (per user notes).
- Good patterns present:
  - Loader actors returning **value snapshots** (don’t cross actor boundaries with @Model).
  - Detached work uses `ModelContext(container)` with `autosaveEnabled = false`.
- Remaining risks:
  - `@unchecked Sendable` DTOs are used in several loaders. They’re likely safe (value types), but it’s better to tighten them to real `Sendable` to avoid footguns.

## Refactor map (concrete splits)

### 1) Details schema builder (largest single file)
- Current: `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift` (~725 lines)
- Responsibilities currently mixed:
  - listing & editing schema fields
  - enforcing constraints (pin limit, ordering, field types)
  - UI sheets/alerts and actions
- Proposed split (tool-limit friendly: 4–6 files)
  1. `DetailsSchemaBuilderView.swift` — shell + wiring only
  2. `DetailsSchemaBuilderModel.swift` — all mutation rules (add/remove/reorder/pin/options validation)
  3. `DetailsSchemaFieldRow.swift` — row UI
  4. `DetailsSchemaFieldEditorSheet.swift` — edit UI for one field
  5. `DetailsSchemaSections.swift` — small subviews (pinned/unpinned sections, empty states)
- Performance benefit:
  - Fewer view invalidations due to cleaner state boundaries.
  - Easier to audit for accidental fetches/computations in `body`.

### 2) Markdown rendering
- Current: `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift` (~661 lines)
- Risks:
  - Hard to reason about WebView lifetime / caching / command handling when everything lives in one file.
  - Any “recreate web view on state change” bug becomes a performance and battery problem.
- Proposed split (3–5 files)
  - `MarkdownTextView.swift` — public API + SwiftUI wrapper
  - `MarkdownWebView.swift` — `UIViewRepresentable` / coordinator
  - `MarkdownRenderer.swift` — HTML generation / sanitization (**if present; otherwise keep UNKNOWN**)
  - `MarkdownCommands.swift` already exists (good).

### 3) Models file
- Current: `BrainMesh/Models.swift` (~515 lines) contains multiple @Model types + enums/helpers
- Proposed split (low risk, high merge/compile benefit; 6–8 files)
  - `Models/NodeKind.swift`
  - `Models/BMSearch.swift`
  - `Models/MetaGraph.swift`
  - `Models/MetaEntity.swift`
  - `Models/MetaAttribute.swift`
  - `Models/MetaLink.swift` (plus `DetailFieldType` if desired)
  - `Models/MetaDetailFieldDefinition.swift`
  - `Models/MetaDetailFieldValue.swift`
- Notes:
  - Keep the SwiftData schema list in `BrainMeshApp.swift` updated.
  - Keep any shared enums accessible across files.

### 4) Display settings UI
- Current: `BrainMesh/Settings/Appearance/DisplaySettingsView.swift` (~529 lines)
- Proposed split (3–6 files)
  - `DisplaySettingsView.swift` — container + navigation
  - `DisplaySettingsSection*.swift` — sections grouped by feature area (Entities Home, Graph Canvas, Media, Typography, etc.)
  - `DisplaySettingsPreview*.swift` — preview rows/cards, if any.

## Cache / index ideas (where it actually matters)
- **Entity/Attribute search**: keep `folded` fields in models (already done: `nameFolded`, `searchLabelFolded`) and prefer predicates on folded strings.
- **Counts**:
  - keep `EntitiesHomeLoader` TTL cache (already implemented)
  - add explicit invalidation on mutations (entity/attribute/link create/delete) to prevent “stale” UI after edits.
- **Media**:
  - ensure hydration is always concurrency-limited (already present via `AsyncLimiter`)
  - ensure a per-screen “only hydrate visible items” policy for large grids (UI-level optimization; currently **UNKNOWN** how aggressively it’s done).

## Unifications / patterns worth standardizing
1. **Loader pattern**
   - shared recipe: “configured with AnyModelContainer” → “Task.detached” → “ModelContext(autosaveEnabled=false)” → “return value snapshot”
2. **Graph scoping**
   - centralize `(graphID == activeGraphID)` predicate fragments and legacy migration policies.
3. **AppStorage keys**
   - use `BMAppStorageKeys.*` everywhere (avoid string literals).
4. **Sendable hygiene**
   - replace `@unchecked Sendable` where possible.

## Risks & edge cases
- Data loss/migration:
  - graph scoping migrations must remain idempotent (current helpers appear idempotent).
  - attachments with `externalStorage` are especially sensitive to store-unfriendly queries.
- Offline:
  - SwiftData should queue sync until connectivity returns (**behavior is managed by the framework; specifics are UNKNOWN**).
- Security:
  - background lock must not disrupt system pickers; `AppRootView` already contains debounced lock logic.

## Observability / Debuggability
- `BrainMesh/Observability/BMObservability.swift` provides:
  - `BMLog.*` os.Logger categories
  - `BMDuration` for cheap timing
- Suggested additions (small):
  - time “graph switch → canvas ready” in `GraphCanvasDataLoader.loadSnapshot`
  - time “open Entities tab → first rows visible”
  - log when storage mode changes (`SyncRuntime.storageMode`)

## Roadmap (highest ROI first, cut to fit tool limits)

### P0 (easy + high ROI)
1. **Split DetailsSchemaBuilderView**
   - Why now: biggest file; lots of UI/state; easiest to carve into subviews + a model.
   - Cut: 4–6 files as proposed above.

2. **Split Models.swift**
   - Why now: low risk; improves merge/conflict behavior and incremental compiles.
   - Cut: 6–8 files; no behavioral change.

3. **Extract shared utilities (AnyModelContainer / AsyncLimiter)**
   - Why now: used across loaders/hydrators; makes patterns consistent.
   - Cut: 2–3 files.

### P1 (medium)
4. **MarkdownTextView split + WebView lifetime hardening**
   - Focus on preventing WebView recreation and isolating JS/command plumbing.

5. **DisplaySettingsView split**
   - Mostly maintainability; reduces “settings file owns everything”.

### P2 (bigger / performance)
6. **GraphCanvas render loop audit**
   - Measure allocations per tick; reduce state diff breadth; consider coalescing updates.
7. **Media gallery “visible-only” hydration**
   - Only hydrate thumbnails for on-screen cells; cancel on fast scroll.

## Open Questions (UNKNOWN)
- **UNKNOWN**: Are there specific performance issues observed in the canvas (FPS drops, battery) beyond general risk?
- **UNKNOWN**: What is the expected maximum graph size (nodes/links) on typical devices?
- **UNKNOWN**: Do you plan CloudKit sharing/collaboration? (No CKShare usage detected.)
- **UNKNOWN**: Any constraints from App Store privacy requirements beyond current Info.plist usage keys?

## First 3 Refactors I would do (P0)

### P0.1 — DetailsSchemaBuilderView split (largest UI hot spot)
- **Ziel:** Wartbarkeit + weniger “mega-view” Risiko; UI-State und Mutationslogik klar trennen.
- **Betroffene Dateien:**  
  - `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift`  
  - **NEW:** `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderModel.swift`  
  - **NEW:** 2–4 kleine Subviews/Sheets (siehe Refactor Map)
- **Risiko:** niedrig–mittel (viele UI-States; aber keine Datenmigration)
- **Erwarteter Nutzen:** bessere Orientierung, kleinere Compile Units, leichteres Testen der Regeln (Pin-Limit, Optionen, Sortierung).

### P0.2 — Models.swift split
- **Ziel:** Stabilere Merges + schnelleres Incremental Build bei Model/Enum Änderungen.
- **Betroffene Dateien:**  
  - `BrainMesh/Models.swift` → mehrere Dateien in `BrainMesh/Models/…`  
  - `BrainMesh/BrainMeshApp.swift` (Schema-Liste bleibt aktuell)
- **Risiko:** niedrig (nur File-Split, keine Logikänderung)
- **Erwarteter Nutzen:** weniger Konflikte, klarere Verantwortlichkeiten pro Modell.

### P0.3 — Shared Loader Utilities zentralisieren
- **Ziel:** Pattern vereinheitlichen und wiederverwendbar machen (`AnyModelContainer`, `AsyncLimiter`, evtl. “Loader template”).
- **Betroffene Dateien:**  
  - **MOVE/NEW:** `BrainMesh/Support/AnyModelContainer.swift`  
  - **MOVE/NEW:** `BrainMesh/Support/AsyncLimiter.swift`  
  - Updates in: `Attachments/AttachmentHydrator.swift`, `Attachments/AttachmentThumbnailStore.swift`, Loader-Akteure (falls sie das Utility nutzen)
- **Risiko:** niedrig (mechanisches Refactor)
- **Erwarteter Nutzen:** weniger Copy/Paste, bessere Lesbarkeit, konsistente Concurrency-Patterns.
