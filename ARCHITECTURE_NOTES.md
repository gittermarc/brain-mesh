# ARCHITECTURE_NOTES.md
_Last updated: 2026-02-18_

> Scope note: This doc is based on a static scan of the repo snapshot in the provided zip. Anything not verifiable from source is marked **UNKNOWN** and collected in “Open Questions”.

## Big Files List (Top 15 by lines)
Each item: path → purpose → why it’s risky (maintenance/perf).

1. `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (~532)
   - Purpose: Canvas drawing (nodes/edges/labels/overlays), hit testing-ish glue.
   - Risk: **Hot render path**; large SwiftUI view composition can amplify invalidations + compile-time.

2. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift` (~489)
   - Purpose: “Anhänge verwalten” sheet (paging, import file/video, preview, delete).
   - Risk: Mixed responsibilities + lots of UI state + async work; easy to regress UX; compile-time hotspot.

3. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (~411)
   - Purpose: Off-main snapshot fetch/build for canvas (nodes/edges/caches).
   - Risk: Complex fetch + transformation logic; concurrency + correctness risks if snapshot contract changes.

4. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` (~408)
   - Purpose: Image manage flow for Entity/Attribute (pick, cache, delete, preview).
   - Risk: Many UI states + system pickers (FaceID/Hidden Album edge cases) + cache coordination.

5. `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` (~408)
   - Purpose: Stats UI building blocks (cards, KPI tiles, rows, charts-ish).
   - Risk: Giant “UI toolbox” file; compile-time drag; accidental coupling across stats sections.

6. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` (~394)
   - Purpose: Connections section (links list) for detail pages; uses loader snapshot.
   - Risk: A lot of row/UI logic in one file; potential main-thread contention in delete/edit flows.

7. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` (~360)
   - Purpose: Media grid gallery on detail pages (adaptive grid + preview).
   - Risk: Scroll perf + thumbnail loading + layout recalcs.

8. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` (~359)
   - Purpose: Shared header + base detail layout for entity/attribute.
   - Risk: Central hub file; changes ripple widely.

9. `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (~348)
   - Purpose: Canvas host: state machine, toolbars, coordination.
   - Risk: “God view” risk; subtle state invalidations can wreck perf.

10. `BrainMesh/Mainscreen/BulkLinkView.swift` (~346)
   - Purpose: Create many links at once (multi picker + duplicate handling).
   - Risk: Can touch large datasets; uses main-context fetch for existing links (potential stalls).

11. `BrainMesh/PhotoGallery/PhotoGallerySection.swift` (~342)
   - Purpose: Photo gallery section for details; bridges to browser/viewer.
   - Risk: Thumbnail pipeline + navigation glue in one place.

12. `BrainMesh/Onboarding/OnboardingSheetView.swift` (~319)
   - Purpose: Onboarding host sheet.
   - Risk: Mostly compile-time; lower runtime risk.

13. `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` (~316)
   - Purpose: Gallery browser (grid/list), disk-cached thumbs.
   - Risk: High fan-out thumbnail requests; must stay throttled.

14. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` (~305)
   - Purpose: Highlight cards (summary/metrics) on detail pages.
   - Risk: Potential expensive derived computations if not cached.

15. `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift` (~297)
   - Purpose: Fullscreen viewer for images/videos.
   - Risk: Low-medium; mainly state + AV/zoom.

---

## Hot Path Analyse

### 1) Rendering / Scrolling (SwiftUI invalidations, expensive work in render path)

#### Graph Canvas (highest risk)
- Files:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ `GraphCanvasScreen+*.swift`)
- Why hotspot:
  - **O(n²) pair loop** for repulsion/collision: `GraphCanvasView+Physics.swift` uses nested loops (`i < j`) over `simNodes`.
  - **30 FPS timer on main runloop** (`Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true)` in `GraphCanvasView+Physics.swift`) → risks main-thread contention if simulation or rendering is heavy.
  - **Canvas redraw cost**: large number of nodes/edges amplifies draw calls; text measurement/drawing is typically expensive.
- Existing mitigations already in code (good):
  - Pair loop is optimized (compute once, apply symmetric forces).
  - “Spotlight physics” reduces simulated nodes (`physicsRelevant`) and sleeps timer when idle (Idle/Sleep block).
  - Off-main snapshot loading via `GraphCanvasDataLoader` (`BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`) avoids main-thread fetch stalls.
  - Micro-logging for physics tick duration via `BMLog.physics` (`BrainMesh/Observability/BMObservability.swift`).
- Concrete watch-outs / failure modes:
  - If derived caches in `GraphCanvasScreen` are recomputed on every state change, you get **exzessive View invalidation** (esp. during drag/zoom).
  - If label/image caches are not keyed correctly, you can trigger repeat image decode or repeated string layout.

#### Node detail pages (lists/grids, attachments)
- Files:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Helpers.swift` (thumbnail row)
  - `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- Why hotspot:
  - **Thumbnail fan-out**: a grid/list can trigger dozens of thumbnail requests quickly.
  - **External blob access**: attachments store `fileData` as `.externalStorage` (`MetaAttachment.swift`). If queries fall back to in-memory filtering, SwiftData can touch blobs unexpectedly (catastrophic).
- Existing mitigations already in code (good):
  - `AttachmentThumbnailStore` throttles generation (`AsyncLimiter(maxConcurrent: 3)`) + inFlight dedupe + disk cache (`thumb_v2_<id>.jpg`).
  - `AttachmentHydrator` throttles cache materialization (`AsyncLimiter(maxConcurrent: 2)`) + dedupe.
  - GraphID migration avoids OR predicates on attachments (`AttachmentGraphIDMigration.swift`).
- Concrete watch-outs:
  - `NodeDetailShared+Sheets.Attachments.swift` mixes paging + import + preview; easy to accidentally do heavy work on main.
  - `Task.detached` work won’t auto-cancel unless you check `Task.isCancelled` (important in thumbnail/materialization pipelines).

#### Entities Home list
- Files:
  - `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
- Why hotspot:
  - Home is a “first screen”; any main-thread stall is felt immediately.
- Current state (good):
  - Loader is off-main, returns `EntitiesHomeSnapshot` (DTO).
  - Attribute counts avoid N+1 by dictionary counting and TTL cache.

---

### 2) Sync / Storage (CloudKit ops, fetch strategies, caching, background triggers)

#### SwiftData + CloudKit (automatic)
- File: `BrainMesh/BrainMeshApp.swift`
  - `ModelConfiguration(cloudKitDatabase: .automatic)` indicates SwiftData CloudKit sync using the configured iCloud container.
- Risks:
  - **Large blobs** (attachments `fileData` `.externalStorage`) can stress sync + local storage.
  - **Schema evolution**: adding fields or changing relationships needs careful migration strategy.
  - **Conflict resolution**: no explicit merge policy found → behavior depends on SwiftData defaults (**UNKNOWN** exact semantics).
- Concrete checks:
  - Keep attachment queries store-translatable (no OR, no UUID-array contains predicates).
  - Avoid fetching `MetaAttachment` when you only need counts/metadata; prefer DTO projections in loaders.

#### Local cache lifecycle
- Files:
  - `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/Attachments/AttachmentStore.swift`, `AttachmentHydrator.swift`, `AttachmentThumbnailStore.swift`
  - Maintenance actions are exposed in `BrainMesh/Settings/SettingsView.swift`.
- Risks / edge cases:
  - Cache files can become stale/orphaned if records deleted on another device.
  - Disk usage can grow unbounded if thumbs aren’t pruned.

---

### 3) Concurrency (MainActor, Task lifetimes, cancellation, thread safety)

#### Actor loader pattern (good baseline)
- Pattern:
  - actor holds `container: AnyModelContainer?`
  - public method launches `Task.detached(priority: .utility)` with a background `ModelContext` and returns DTO
- Examples:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
  - `BrainMesh/Mainscreen/NodePickerLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
- Risk points:
  - `AnyModelContainer` is `@unchecked Sendable` (defined in `BrainMesh/Attachments/AttachmentHydrator.swift`).
  - `Task.detached` ignores parent cancellation by default; add `Task.checkCancellation()` around heavy work.
- Places to verify:
  - Stats cancels overlapping loads via stored `loadTask` (`BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`) — good.
  - Canvas load cancellation strategy: **UNKNOWN** without profiling plus checking `GraphCanvasScreen+Loading.swift`.
  - Attachments manage sheet runs async work from UI; ensure long work doesn’t block main.

#### ScenePhase / lock interaction (subtle UX hotspot)
- Files:
  - `BrainMesh/AppRootView.swift`
  - `BrainMesh/Support/SystemModalCoordinator.swift`
- Why it matters:
  - Some devices/iOS versions can briefly report `.background` during FaceID prompts inside pickers (Hidden album).
  - Auto-lock during that transient phase resets/dismisses the picker UI.
- Current mitigation:
  - Debounce lock if `systemModal.isSystemModalPresented` (`AppRootView`).
- Remaining risks:
  - Any future “system modal” must call `systemModal.beginSystemModal()/endSystemModal()` consistently; missing an `end` can prevent auto-lock.

---

## Refactor Map

### A) Konkrete Splits (Datei → neue Dateien)
Focus: split-only first (low risk), then behavioral refactors.

#### 1) Attachments manage sheet split (high leverage, low risk)
- Current: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift` (~489 lines)
- Suggested split:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeAttachmentsManageView.swift` (host + state)
  - `.../NodeAttachmentsManageView+Loading.swift` (paging + refresh)
  - `.../NodeAttachmentsManageView+Import.swift` (file/video import + progress)
  - `.../NodeAttachmentsManageView+Preview.swift` (preview routing, playback)
- Why:
  - Reduces compile-time hotspots and isolates “dangerous” logic (imports, file IO).
- Behavior change: none intended.

#### 2) GraphCanvas rendering split (medium risk, big readability)
- Current: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (~532 lines)
- Suggested split:
  - `BrainMesh/GraphCanvas/GraphCanvasRenderer.swift` (pure Canvas draw)
  - `BrainMesh/GraphCanvas/GraphCanvasNodeLayer.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasEdgeLayer.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasLabelLayer.swift`
- Optional: a `RenderSnapshot` struct (value-only) holding precomputed drawing primitives (positions, edge segments, label strings) computed off-main when possible.
- Why:
  - Makes render invalidation boundaries explicit.
  - Gives you a single place to add micro-profiling or caching (e.g., precomputed paths).

#### 3) Node image management split (low risk)
- Current: `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` (~408 lines)
- Suggested split:
  - `NodeImagesManageView.swift` (host)
  - `NodeImagesManageView+Picker.swift` (system picker presentation + modal coordinator hooks)
  - `NodeImagesManageView+Actions.swift` (save/delete/cache rebuild)
  - `NodeImagesManageView+Preview.swift` (fullscreen)
- Why:
  - System picker edge cases (Face ID / Hidden album) stay isolated and testable.

#### 4) Stats components toolbox split (compile-time win)
- Current: `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` (~408)
- Suggested split:
  - `StatsComponents+Cards.swift` (cards only)
  - `StatsComponents+KPI.swift` (KPI tiles/grid)
  - `StatsComponents+MiniCharts.swift` (sparklines / density bar)
  - `StatsComponents+Typography.swift` (small helpers)
- Why: prevents “everything recompiles when one card changes”.

---

### B) Cache-/Index-Ideen (what to cache, keys, invalidation)

#### 1) Attribute counts without full attribute fetch (bigger change)
- Problem:
  - `EntitiesHomeLoader.computeAttributeCounts` fetches all `MetaAttribute` for a graph, then filters in memory because `#Predicate` doesn’t reliably support UUID `contains` arrays.
- Option:
  - Add a denormalized `ownerID: UUID` field to `MetaAttribute` (in addition to relationship), keep it in sync on write.
  - Then you can fetch only relevant attributes with store-translatable predicates.
- Risk:
  - Data migration needed (backfill ownerID). Medium.

#### 2) Link adjacency cache for node details (optional)
- Node details often need “links for a node”.
- Option:
  - Keep a small in-memory cache keyed by `(graphID, nodeKey)` → `[LinkRowDTO]`, invalidated on link CRUD.
  - Loader: `NodeConnectionsLoader` already exists; add a short TTL or explicit invalidation hooks.
- Risk: low; must invalidate correctly.

#### 3) GraphCanvas precomputed edge lists by lens/filters
- If you switch lens/filter frequently, precompute:
  - `edgesForDisplay` and `nodeVisibility` keyed by `(graphID, lensConfigHash, searchTermFolded)`.
- Risk: low-medium; ensure memory doesn’t balloon (LRU).

#### 4) Thumbnail cache hygiene
- Disk thumbs: `thumb_v2_<id>.jpg` (AttachmentThumbnailStore).
- Add a periodic cleanup (Settings action or on launch):
  - list thumb files, remove those whose attachment ID no longer exists.
- Risk: low (best-effort).

---

### C) Vereinheitlichungen (Patterns, Services, DI)
- Unify “configure container” in one place:
  - currently called from `BrainMesh/BrainMeshApp.swift` for multiple singletons.
- Extract `AnyModelContainer` into `BrainMesh/Support/AnyModelContainer.swift` and re-use everywhere.
- Introduce a small “GraphScope” type and safe predicate helpers to reduce OR mistakes.
- Naming rule suggestion:
  - *Store* = local file system cache (`ImageStore`, `AttachmentStore`)
  - *Loader* = off-main SwiftData fetch + DTO
  - *Hydrator* = ensures cache materialization (disk) and dedupes work

---

## Risiken & Edge Cases
- **Data loss risk**: any migration that rewrites `graphID` or denormalized IDs must be idempotent + safe on multi-device sync.
- **ExternalStorage**: avoid query patterns that force SwiftData into in-memory filtering for `MetaAttachment` (`fileData`).
- **Graph duplicates**: Stats view dedupes graphs by UUID (`uniqueGraphs` in `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`). Root cause is **UNKNOWN**.
- **App lock + system pickers**:
  - Fix exists (`AppRootView` + `SystemModalCoordinator`), but any new picker/modal must keep the counter correct.

---

## Observability / Debuggability
- Existing:
  - `BrainMesh/Observability/BMObservability.swift` provides `BMLog` categories and `BMDuration`.
  - Physics tick logging in `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`.
- Suggested next steps:
  - Add a “slow fetch logger” helper (debug-only): wrap `context.fetch` inside loaders and log durations > 50ms with `BMLog.load`.
  - Add “thumbnail stats” counters (generated per minute, disk-hit ratio) in `AttachmentThumbnailStore`.

---

## Open Questions (UNKNOWNs)
1. SwiftData conflict resolution: any custom merge/conflict handling? No explicit merge policy found. **UNKNOWN**.
2. CloudKit schema/migration strategy: how are breaking model changes handled across versions? **UNKNOWN**.
3. Canvas derived cache invalidation: are expensive derived computations re-run during drags/zoom? Needs profiling. **UNKNOWN**.
4. Why graph duplicates occur: Stats dedupe implies duplicates sometimes. Root cause not visible. **UNKNOWN**.
5. Test coverage quality: tests exist as targets, but not analyzed in depth. **UNKNOWN**.
6. Crash/analytics tooling: no SDK found. **UNKNOWN**.

---

## First 3 Refactors I would do (P0)

### P0.1 — Split Attachments Manage Sheet (pure refactor)
- **Ziel:** Compile-times runter + Ownership klar; weniger “alles-in-einer-Datei” für Import/Preview/Paging.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift`
  - (new) `BrainMesh/Mainscreen/NodeDetailShared/NodeAttachmentsManageView*.swift`
- **Risiko:** niedrig (mechanischer Split, keine Logikänderung geplant).
- **Erwarteter Nutzen:** schnelleres Iterieren in Attachments/Detail-Flows; weniger Regressionen beim Fixen von Import-Edge-Cases.

### P0.2 — Split GraphCanvas Rendering + Add Micro-Profiling Points
- **Ziel:** Render-Layer klar trennen und echte Bottlenecks messbar machen (Edges vs Labels vs Nodes).
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - (new) `BrainMesh/GraphCanvas/GraphCanvas*Layer.swift` / `GraphCanvasRenderer.swift`
  - optional: `BrainMesh/Observability/BMObservability.swift`
- **Risiko:** mittel (Renderpath ist empfindlich; kleine visuelle Unterschiede möglich, wenn man View-Hierarchie ändert).
- **Erwarteter Nutzen:** bessere Scroll/Zoom/Drag-Performance bei großen Graphen + deutlich wartbarer Rendering-Code.

### P0.3 — Split NodeImagesManageView + Harden system-modal bookkeeping
- **Ziel:** Image-Picker/Hidden-Album Edge Cases isolieren; weniger Risiko, dass ein Fix Auto-Lock/Picker wieder bricht.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - `BrainMesh/AppRootView.swift`
  - `BrainMesh/Support/SystemModalCoordinator.swift`
- **Risiko:** niedrig–mittel (Split ist mechanisch; aber Picker-Flow ist fragil).
- **Erwarteter Nutzen:** stabilere Media-Workflows, weniger “picker reset” Bugs, klarere Verantwortlichkeiten.
