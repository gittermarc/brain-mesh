# ARCHITECTURE_NOTES

Last updated: 2026-02-26 (Europe/Berlin)

## Scope & Ground Rules
This document only states things that are evidenced in the current ZIP. Anything unclear is marked **UNKNOWN** and collected in **Open Questions**.

Priorities covered (in order):
1) Sync/Storage/Model (SwiftData/CloudKit)  
2) Entry Points + Navigation  
3) Large Views/Services (maintainability/performance)  
4) Conventions + typical workflows

---

## 1) Sync / Storage / Model

### SwiftData container + CloudKit configuration
Source: `BrainMesh/BrainMeshApp.swift`
- Schema registration:
  - `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`
- CloudKit enabled:
  - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
- Failure behavior:
  - DEBUG: **hard fail** (`fatalError`) if CloudKit container fails to initialize.
  - RELEASE: fallback to local-only `ModelConfiguration(schema: schema)` and `SyncRuntime.shared.setStorageMode(.localOnly)`.

### Sync runtime visibility
Sources:
- `BrainMesh/Settings/SyncRuntime.swift`
- `BrainMesh/Settings/SettingsView+SyncSection.swift`
- `BrainMesh/BrainMeshApp.swift` (startup call)
What exists:
- A runtime object to surface:
  - whether CloudKit-backed storage is active (vs local-only)
  - current iCloud account status via CloudKit API (refresh on launch)

### Graph scoping + legacy migration
Sources:
- `BrainMesh/AppRootView.swift` (activeGraphID in AppStorage)
- `BrainMesh/GraphBootstrap.swift` (ensure default graph, migrate legacy)
Observed:
- Many models include `graphID: UUID?` (MetaGraph itself is graph identity; other models optionally scoped).
- On startup:
  - `GraphBootstrap.ensureAtLeastOneGraph(using:)`
  - If `activeGraphID` is invalid, it is set to the default graph.
  - `GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID:using:)` shifts legacy records.

### Data model duplication risk: lock fields
Sources:
- `BrainMesh/Models/MetaGraph.swift`
- `BrainMesh/Models/MetaEntity.swift`
- `BrainMesh/Models/MetaAttribute.swift`
Pattern:
- Lock-related fields repeated across models:
  - biometrics enabled, password enabled, salt/hash, iterations, computed flags
Risk:
- Easy to drift (e.g., one model computes `isProtected` differently).
Refactor leverage:
- Shared protocol/extension or composition model (see Refactor Map).

---

## 2) Entry Points + Navigation

### App entry
- `BrainMesh/BrainMeshApp.swift` (`@main`)
  - Initializes `ModelContainer`
  - Creates stores/coordinators (appearance, display, onboarding, lock, system modals)
  - Calls `AppLoadersConfigurator.configureAllLoaders(with:)`

### Root view orchestration
- `BrainMesh/AppRootView.swift`
  - Embeds `ContentView()` (tabs)
  - Global `.sheet` for onboarding (`OnboardingSheetView`)
  - Global `.fullScreenCover` for graph unlock (`GraphUnlockView`)
  - ScenePhase policy:
    - debounced background lock to avoid dismissing system pickers
    - periodic image hydration (24h throttle) via `ImageHydrator.shared.hydrateIncremental(...)`

### Tabs
- `BrainMesh/ContentView.swift`
  - Tab 1: `EntitiesHomeView()`
  - Tab 2: `GraphCanvasScreen()`
  - Tab 3: `GraphStatsView()`
  - Tab 4: `SettingsView(...)` inside `NavigationStack`

---

## 3) Big Files List (Top 15 by line count)

> Method: count of physical lines in `*.swift` under `BrainMesh/` in this ZIP.

- 01. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` — **491** lines — Shared node detail UI components
- 02. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **411** lines — Graph canvas / snapshot loading / visualization
- 03. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410** lines — Shared node detail UI components
- 04. `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` — **401** lines — Attribute detail screen
- 05. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` — **394** lines — Shared node detail UI components
- 06. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **388** lines — Entities home list UI or loader
- 07. `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388** lines — Details schema/value UI
- 08. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **381** lines — Entities home list UI or loader
- 09. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362** lines — Shared node detail UI components
- 10. `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **357** lines — Icon/SF Symbols picker
- 11. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **356** lines — Graph canvas / snapshot loading / visualization
- 12. `BrainMesh/Mainscreen/BulkLinkView.swift` — **346** lines — Mixed / UNKNOWN
- 13. `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **344** lines — Photo gallery UI/actions
- 14. `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **331** lines — Shared node detail UI components
- 15. `BrainMesh/Attachments/AttachmentImportPipeline.swift` — **326** lines — Attachment import/hydration/storage


Why big files are risky (general):
- Merge conflict magnets (UI code churn + multi-feature ownership)
- Hidden performance work (fetch/sort/aggregation) creeps into view lifecycle
- Hard to test because state + UI + data access co-mingle

---

## 4) Hot Path Analysis

### 4.1 Rendering / Scrolling (SwiftUI invalidations, expensive work)

#### Confirmed: SwiftData fetches triggered from within view lifecycle
These are concrete “watch this” spots because they can scale with data size and run on the main thread unless explicitly offloaded.

1) `BrainMesh/Mainscreen/BulkLinkView.swift`
- **Reason:** `modelContext.fetch(...)` is executed from `.task { loadExistingLinkSets() }` (see lines around the `loadExistingLinkSets()` call).
- Risk:
  - Runs on main actor by default.
  - Fetch size grows with links in the graph.
  - Re-runs when view is re-created (navigation churn).
- Symptom:
  - Opening Bulk Link view may stutter on large graphs.

2) `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
- **Reason:** contains `modelContext.fetch(...)` after `var body` (detected via static scan).
- Risk:
  - Any fetch in render path or view-tied tasks can cause UI hitching, especially when managing many media items.
- **NOTE:** exact call sites should be reviewed when refactoring (but presence is confirmed).

3) `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
- **Reason:** contains `modelContext.fetch(...)` after `var body` (detected via static scan).
- Risk:
  - Connections sections are likely shown on detail screens; repeated invalidations can re-trigger work.

4) `BrainMesh/Onboarding/OnboardingSheetView.swift` and `BrainMesh/Onboarding/DetailsOnboardingSheetView.swift`
- **Reason:** contain `modelContext.fetch(...)` after `var body` (detected).
- Risk:
  - Onboarding is typically shown on fresh installs, but fetch-in-body is still a correctness/perf smell.

5) `BrainMesh/Security/GraphUnlockView.swift`
- **Reason:** contains `modelContext.fetch(...)` after `var body` (detected).
- Risk:
  - Unlock UX must feel instant; any fetch work here is user-visible latency.

#### Good pattern: snapshot loaders off-main
1) `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- **Reason:** uses `Task.detached(priority: .utility)` + creates a background `ModelContext` to run SwiftData fetches off the UI thread.
- Benefit:
  - Opening Graph tab should not block on large fetches as long as snapshot application on main is bounded.

2) `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`, `BrainMesh/Stats/GraphStatsLoader.swift`
- **Reason:** dedicated loaders suggest intent to keep heavy work out of `body`.
- **UNKNOWN:** whether every heavy computation is fully moved; verify screens for leftover computed aggregations.

### 4.2 Sync / Storage hot paths (CloudKit init, background triggers)
1) Startup CloudKit init
- Source: `BrainMesh/BrainMeshApp.swift`
- **Reason:** container init happens at app launch; DEBUG hard-fails.
- Risk:
  - Misconfigured signing/entitlements makes dev builds unusable (by design).
  - Release fallback could hide sync failures unless surfaced loudly in Settings (partially addressed by SyncRuntime).

2) Foreground triggers
- Source: `BrainMesh/AppRootView.swift`
- **Reason:** foreground runs:
  - `autoHydrateImagesIfDue()` (guarded: 24h throttle + “run once per launch”)
  - lock enforcement
- Good:
  - Throttling prevents repeated heavy hydration.
- Risk:
  - Any other features adding foreground `.task`/`.onChange` could regress into “startup soup”.

### 4.3 Concurrency hot paths (MainActor contention, task lifetimes)
1) Debounced background lock task
- Source: `BrainMesh/AppRootView.swift`
- **Reason:** stores `pendingBackgroundLockTask` and cancels on foreground — good lifecycle handling.
- Watchouts:
  - Ensure any other long-running tasks follow the same cancel-on-disappear pattern.

2) Detached tasks with ModelContext
- Source: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- **Reason:** uses a `ModelContext` inside `Task.detached`.
- Watchouts:
  - Ensure no SwiftData objects escape the detached context (use value DTOs only — appears intended).

---

## 5) Refactor Map (concrete, grounded)

### 5.1 Splits (large files → smaller units)
(These are mechanical splits: no logic changes, safer to review.)

- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
  - Split suggestion:
    - `NodeDetailShared+Header.swift`
    - `NodeDetailShared+Notes.swift`
    - `NodeDetailShared+Toolbelt.swift`
    - `NodeDetailShared+Sections.swift`
  - Benefit: reduces merge conflicts and “everything depends on everything”.

- `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Split suggestion:
    - `AttributeDetailView+Queries.swift` (Query builders + state initialization)
    - `AttributeDetailView+Layout.swift` (UI skeleton)
    - `AttributeDetailView+Sheets.swift` (sheet/alert wiring)
    - `AttributeDetailView+Actions.swift` (side-effecting actions, saves, deletes)
  - Benefit: isolates “render-only” vs “data access” vs “mutations”.

- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - Split suggestion:
    - `EntitiesHomeView+Toolbar.swift`
    - `EntitiesHomeView+List.swift`
    - `EntitiesHomeView+Sheets.swift`
  - Benefit: makes future performance changes less risky (view invalidation surface smaller).

- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - Split suggestion:
    - `GraphCanvasScreen+State.swift`
    - `GraphCanvasScreen+Toolbar.swift`
    - `GraphCanvasScreen+Selection.swift`
    - `GraphCanvasScreen+Sheets.swift`
  - Benefit: improves readability; keeps loader integration stable.

### 5.2 Move fetches out of views (performance + correctness)
Target files (confirmed scan):
- `BrainMesh/Mainscreen/BulkLinkView.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
- `BrainMesh/Security/GraphUnlockView.swift`
- `BrainMesh/Onboarding/OnboardingSheetView.swift`
- `BrainMesh/Onboarding/DetailsOnboardingSheetView.swift`

Concrete pattern:
- Create a small `actor` loader per feature (or extend existing loaders), using:
  - background `ModelContext` from configured `ModelContainer`
  - value-only snapshots
- Apply snapshots on main actor once.

### 5.3 Cache / Index ideas (bounded, with invalidation)
- **Link adjacency cache** for detail screens
  - Key: `(graphID, nodeKind, nodeID)`
  - Value: `incomingIDs/outgoingIDs + notes`
  - Invalidate:
    - when links are created/deleted for that node
- **Media preview cache** per node
  - Key: `(graphID, nodeKind, nodeID)`
  - Value: preview items + counts + lastUpdated timestamp
  - Invalidate:
    - when attachments change for that node
- **Folded-name indexes**
  - Already present pattern (`nameFolded`).
  - Ensure all “searchable” strings have normalized variants.

### 5.4 Unifications (patterns + DI)
- Standardize loader configuration:
  - Always register in `AppLoadersConfigurator.configureAllLoaders(with:)`
  - Prefer using `AnyModelContainer` wrapper
- Standardize “graph scoping”
  - One helper to build graphID-aware predicates to prevent accidental cross-graph fetches.

---

## 6) Risks & Edge Cases

### Data loss / migration
- Adding non-optional fields to SwiftData models can require migrations; current ZIP shows legacy migration for graph scoping, but no general migration framework.
- **UNKNOWN:** whether the app is expected to support schema evolution beyond “soft optional fields”.

### Offline + multi-device
- CloudKit-backed SwiftData should queue changes offline and sync later.
- **UNKNOWN:** any user-facing conflict UI, or testing strategy for multi-device merge conflicts.

### Locking interactions with system pickers
- There is an explicit debounce workaround in `BrainMesh/AppRootView.swift`.
- Risk: future background/foreground tasks might reintroduce picker dismissal if they present covers/sheets.

---

## 7) Observability / Debuggability

What exists:
- `os.Logger` is used at least in `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`.
- Sync status is surfaced via Settings (`SyncRuntime`).

Recommended minimal additions:
- Log durations for:
  - GraphCanvas snapshot load
  - EntitiesHome load
  - Stats load
- Add a debug-only “Data counts” panel (per model, scoped to active graph) to spot accidental global fetches.

---

## 8) Open Questions (UNKNOWN)
- CloudKit container identifier / entitlements configuration (no `*.entitlements` file in ZIP; likely in Xcode project settings).
- Any explicit merge/conflict strategy beyond SwiftData defaults.
- Background sync/refresh policy (push/CK subscription) beyond SwiftData.
- Whether `MetaAttachment.fileData` is bounded in practice or can blow memory on large media.
- Any external dependencies outside this ZIP (no `Package.resolved` found).

---

## First 3 Refactors I would do (P0)

### P0.1 — Eliminate confirmed SwiftData fetches from view lifecycle
- **Goal:** remove main-thread hitching + reduce “random” UI stalls as data grows.
- **Files:**
  - `BrainMesh/Mainscreen/BulkLinkView.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
  - `BrainMesh/Security/GraphUnlockView.swift`
  - `BrainMesh/Onboarding/OnboardingSheetView.swift`
  - `BrainMesh/Onboarding/DetailsOnboardingSheetView.swift`
- **Risk:** Low–Medium (mechanical move, but easy to break subtle UI timing).
- **Expected benefit:** noticeable smoothness on large graphs; fewer “why did this rerender fetch again?” moments.

### P0.2 — Split NodeDetailShared mega-files to reduce change collisions
- **Goal:** shrink merge conflicts + make performance work local and reviewable.
- **Files:**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
- **Risk:** Low (pure file split via extensions/subviews).
- **Expected benefit:** faster iteration, easier review, less “one file owns the app” syndrome.

### P0.3 — Introduce a link adjacency snapshot/cache for detail screens
- **Goal:** make connections sections scale: constant-time UI updates, bounded fetches.
- **Files:**
  - New: `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsSnapshot.swift`
  - Change: `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - Change: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
- **Risk:** Medium (cache invalidation correctness).
- **Expected benefit:** stable scrolling and instant open for node details even with many links.

