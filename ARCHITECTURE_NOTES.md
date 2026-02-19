# BrainMesh – Architecture Notes (Deep Dive)
_Generated: 2026-02-19_

This document is intentionally opinionated and focuses on the project’s **risk surface**: storage/sync correctness, performance hot paths, and maintainability leverage points. Anything that cannot be verified from code is marked **UNKNOWN** and collected in **Open Questions**.

---

## Big Files List (Top 15 by lines)
(From repository scan of `*.swift` under `BrainMesh/`.)

| Rank | Lines | File | Purpose | Why risky |
|---:|---:|---|---|---|
| 1 | 533 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | Canvas drawing (edges/nodes/labels/notes) | Hot render path; per-frame loops + allocations; hard to reason about invalidation/perf regressions. |
| 2 | 496 | `BrainMesh/Mainscreen/EntitiesHomeView.swift` | Entities list/grid UI + routing | Large SwiftUI view; many states + layouts; risk of excessive invalidation and compile times. |
| 3 | 479 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | Shared node detail UI components (hero card, async image view, pills) | Large UI building block; many subviews in one file; changes can cascade compile time and runtime invalidation. |
| 4 | 431 | `BrainMesh/Appearance/AppearanceModels.swift` | Appearance settings models (persistable colors, settings structs) | Large “model soup”; easy to introduce breaking Codable changes; touches many UI screens. |
| 5 | 412 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | Background snapshot loader for graph canvas | Algorithmic complexity; uses IN predicates and per-entity attribute sorting; correctness/perf sensitive. |
| 6 | 408 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | Node image management UI (import, delete, gallery) | Touches image decode + disk I/O + hydration; risk of main-thread work & large memory spikes. |
| 7 | 395 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | Connections UI + data plumbing for node detail | Potentially heavy connection loading; risk of fetches on main and large lists. |
| 8 | 366 | `BrainMesh/Mainscreen/EntitiesHomeLoader.swift` | Background loader for EntitiesHome (search + counts) | Fetches all attributes/links then filters in memory; can be expensive on large stores (mitigated by TTL cache). |
| 9 | 362 | `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` | Reusable stats cards/charts components | Large SwiftUI component collection; UI changes ripple; risk of layout cost on older devices. |
| 10 | 361 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | Node detail media gallery (attachments/photos grids) | Grid thumbnails can explode concurrent work; thumbnail generation must remain throttled. |
| 11 | 358 | `BrainMesh/Icons/AllSFSymbolsPickerView.swift` | SF Symbols catalog picker UI | Large lists + search; needs careful virtualization to avoid memory/time spikes. |
| 12 | 347 | `BrainMesh/Mainscreen/BulkLinkView.swift` | Bulk create links UI + logic | User action can trigger large DB writes; needs progress + cancellation to avoid hangs. |
| 13 | 343 | `BrainMesh/PhotoGallery/PhotoGallerySection.swift` | Photo gallery section UI (grid/scroll) | Scrolling hotspots with image decode; must rely on async thumbnails. |
| 14 | 326 | `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` | Graph canvas screen orchestration (states, toolbars, navigation) | High state density; easy to introduce feedback loops and re-render storms. |
| 15 | 320 | `BrainMesh/Onboarding/OnboardingSheetView.swift` | Onboarding guided steps UI | Touches SwiftData fetches + pickers; must avoid disruptive background work. |

---

## Hot Path Analysis

### 1) Rendering / Scrolling

#### Graph canvas rendering
Files:
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView.swift`
- `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ `GraphCanvasScreen+*.swift`)

Why this is hot:
- **Per-frame draw loops**: `renderCanvas(in:size:alphas:theme:colorScheme:)` iterates `drawEdges` and draws a `Path` for each, then draws nodes/labels/notes. This is O(E + V) per frame. (`GraphCanvasView+Rendering.swift`)
- **Per-frame transform/cache build**: `buildFrameCache(center:alphas:)` is called at the start of `renderCanvas` and builds dictionaries like `screenPoints[...]` for nodes each frame. That’s heavy work on every draw pass. (`GraphCanvasView+Rendering.swift`)
- **Physics tick on main run loop**: `Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true)` drives `stepSimulation()` (positions/velocities dictionaries) and therefore frequent `@State` updates and view invalidations. (`GraphCanvasView+Physics.swift`)

Concrete hotspot reasons (code-level):
- “**MainActor contention / frequent invalidation**”: Timer-driven state updates at 30 FPS.
- “**Per-frame allocations**”: creating `Path()` per edge and building temporary dictionaries/arrays in the render function.
- “**Work proportional to graph size**”: nodes/edges scale up quickly; render + physics cost is linear.

Mitigations already present:
- The canvas supports **Lens/Spotlight** to hide non-relevant nodes/edges (`lens.hideNonRelevant`) before drawing. (`GraphCanvasView+Rendering.swift`)
- The physics simulation has an “idle/sleep” mechanism (tick counter + stopping timer) to reduce background cost. (`GraphCanvasView+Physics.swift`)
- Data for the canvas is loaded off-main via `actor GraphCanvasDataLoader` returning a value snapshot. (`GraphCanvasDataLoader.swift`)

Risk / failure modes:
- Large graphs can cause “scroll/jank” and battery drain if the physics timer keeps running due to tiny residual velocity.
- Subtle state changes (e.g. selection, lens, drag) may trigger full redraws and churn dictionaries.

Refactor levers (high ROI):
- Split rendering into smaller functions that can **avoid rebuilding caches** when inputs unchanged:
  - Example split targets: `FrameCache` building, edge draw, node draw, label draw, note draw.
- Avoid per-edge `Path()` allocations by using a reusable `Path` or batched drawing.
- Consider switching Timer→display-linked driver (**UNKNOWN** whether feasible/desired with SwiftUI `Canvas` in this project).

#### Thumbnail-heavy grids (attachments / photos)
Files:
- `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift`

Concrete hotspot reasons:
- “**Unbounded work from grids**”: large grids can request many thumbnails at once.
- “**Expensive generators**”: QuickLookThumbnailing + `AVAssetImageGenerator` are costly.
- “**Disk + decode churn**”: repeated scrolling will thrash if caching isn’t correct.

Mitigations already present:
- `AttachmentThumbnailStore` uses:
  - `NSCache` memory cache with `countLimit = 250`
  - Disk cache in Application Support (`thumb_<id>.jpg`)
  - An `AsyncLimiter(maxConcurrent: 3)` to cap concurrent generations
  - Per-attachment `inFlight` task de-duplication (prevents duplicate generation). (`AttachmentThumbnailStore.swift`)

Risk / failure modes:
- If UI requests thumbnails at varying sizes, cache keys may fragment (**UNKNOWN** if multiple sizes are cached; current cache key appears to be `attachmentID` only, which implies “one canonical thumbnail per attachment”).
- QuickLook can still spike CPU even when limited to 3 concurrent tasks on older devices.

Refactor levers:
- Standardize requested thumbnail sizes in UI and treat the store output as a fixed canonical size.
- Add metrics for “thumbnail miss rate” and generation duration (hook into `BMLog` / `BMDuration`).

---

### 2) Sync / Storage (SwiftData + CloudKit)

#### ModelContainer + CloudKit
Files:
- `BrainMesh/BrainMeshApp.swift`
- `BrainMesh/BrainMesh.entitlements`
- `BrainMesh/Info.plist`

Facts from code:
- SwiftData is configured with CloudKit via:
  - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)` (`BrainMeshApp.swift`)
- In DEBUG, failing CloudKit init → `fatalError` (hard crash).
- In Release, failing CloudKit init → fallback to local-only `ModelConfiguration(schema: schema)`.

Risk / failure modes:
- Silent fallback to local-only in release can lead to “why isn’t it syncing?” situations without visible UI feedback.
- CloudKit conflict resolution is implicit via SwiftData defaults; explicit merge strategy is **UNKNOWN**.

Refactor levers:
- Add a debug/settings surface for:
  - current container mode (CloudKit vs local-only)
  - last sync timestamp / basic “is iCloud available” flags (**UNKNOWN** how to query cleanly with SwiftData; may require CloudKit APIs)

#### Graph scoping and “OR predicate” hazards
Files:
- `BrainMesh/GraphBootstrap.swift`
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`

Facts from code:
- Models (`MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`) store `graphID: UUID?` for scoping.
- The project explicitly avoids optional-scoping predicates like:
  - `(gid == nil OR record.graphID == gid)`
  because it can force in-memory filtering (not store-translatable) and become catastrophic when models contain external storage blobs.
  - This is specifically called out in `AttachmentGraphIDMigration.swift`.

Current mitigations:
- `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)` moves legacy records (`graphID == nil`) into the default graph at startup.
- `AttachmentGraphIDMigration.migrateLegacyGraphIDIfNeeded(...)` provides a targeted migration for attachments.

Risk / failure modes:
- Any remaining “legacy” `graphID == nil` records can force code into slower paths and keep optional predicates alive.
- Multi-device sync can resurrect edge cases (e.g. duplicates of `MetaGraph.id`) which the project currently repairs via `GraphDedupeService`.

Refactor levers:
- Make “graphID presence” an invariant:
  - Add a one-time “migration completion sweep” and report counts in debug UI.
  - Consider making `graphID` non-optional in the model (requires migration; **UNKNOWN** SwiftData migration strategy desired).

#### Binary blobs in the synced model
Files:
- `BrainMesh/Models.swift` (node images)
- `BrainMesh/Attachments/MetaAttachment.swift` (attachments)

Facts from code:
- Node images are stored as `Data?` in the model (`imageData`), and cached as a local file referenced by `imagePath`.
- Attachments store bytes as `@Attribute(.externalStorage) var fileData: Data?`.

Risk / failure modes:
- Node images (non-external storage) can pressure record sizes and increase sync churn if larger-than-expected images are imported.
- Local cache pointers (`imagePath`, `localPath`) are strings and may sync across devices; the code treats them as relative filenames, not absolute paths (`ImageStore.swift`, `AttachmentStore.swift`). That’s good, but still requires hydration to ensure local file exists.

Mitigations already present:
- `ImageHydrator` and `AttachmentHydrator` create cache files incrementally and dedupe work via `inFlight` tasks.

Refactor levers:
- Define and enforce max image byte size at import time (**UNKNOWN** current enforcement; inspect image import pipeline if needed).
- Consider external storage for images if they can be large (requires careful migration).

---

### 3) Concurrency (MainActor, Task lifetimes, cancellation, thread safety)

#### Background loaders using detached tasks
Files (representative):
- `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- `BrainMesh/Stats/GraphStatsLoader.swift`
- `BrainMesh/Mainscreen/NodePickerLoader.swift`
- `BrainMesh/Mainscreen/LinkCleanup.swift` (`NodeRenameService`)

Facts from code:
- Loaders are `actor`s configured once with `AnyModelContainer`.
- They commonly use:
  - `Task.detached(priority: .utility) { ... ModelContext(container.container) ... }`
- Most set `context.autosaveEnabled = false` and do explicit `save()` in write paths.

Risk / failure modes:
- Detached tasks are not automatically canceled when UI navigates away unless you explicitly propagate cancellation.
- Accidental passing of `@Model` instances across concurrency boundaries is explicitly avoided (DTO pattern), but regressions are easy when adding features.

Mitigation patterns already in use:
- DTO snapshots returned to UI, navigation by `id` only (e.g. `NodePickerRowDTO` in `NodePickerLoader.swift`).
- Work de-duplication via `inFlight` dictionaries (e.g. `NodeRenameService` in `LinkCleanup.swift`, hydrators).

Refactor levers:
- Create a shared “BackgroundModelContextFactory” that:
  - creates contexts consistently
  - sets `autosaveEnabled` and optional `transactionAuthor`
  - optionally injects logging around fetch/save durations

#### Canvas physics scheduling
File:
- `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`

Facts from code:
- Simulation uses `Timer` at 30Hz on the main run loop.
- There is an idle mechanism that stops the timer when the system is “sleeping”.

Risk / failure modes:
- High node counts → heavy per-tick dictionary math → main thread stalls.
- “Never sleeps” if minor jitter prevents idle tick threshold from being reached.

Refactor levers:
- Represent simulation state in a struct and keep it off the view when possible.
- Cap node count participating in physics more aggressively (already partially done via lens; verify).
- Add debug metrics: nodes simulated, tick duration (use `BMLog.physics` + `BMDuration`).

---

## Refactor Map (Concrete options)

### A) File splits (maintainability + compile times)
High-value splits (P0/P1):
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - Split into:
    - `GraphCanvasRender_FrameCache.swift` (FrameCache struct + build)
    - `GraphCanvasRender_Edges.swift`
    - `GraphCanvasRender_Nodes.swift`
    - `GraphCanvasRender_Labels.swift`
    - `GraphCanvasRender_Notes.swift`
  - Rationale: render path is sensitive; smaller units make perf review easier.
- `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - Extract:
    - Search + header controls
    - Entities list/grid body
    - Row view(s)
    - Toolbar + sheet routing
  - Rationale: reduce state coupling; keep routing separate from layout.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
  - Extract:
    - `NodeHeroCard`
    - `NodeAsyncPreviewImageView`
    - Pills + small components
  - Rationale: high churn file; changes likely affect multiple detail screens.

### B) Cache / index ideas (performance)
- Entities Home counts:
  - Current: `EntitiesHomeLoader.computeAttributeCounts` and `computeLinkCounts` fetch *all* attributes/links for a graph, then filter in memory because `#Predicate` does not reliably support UUID array `.contains` (documented in-file). (`EntitiesHomeLoader.swift`)
  - Options:
    - Maintain per-entity counters (attributesCount, linksCount) as stored fields updated on insert/delete. (Requires careful write paths; **risk**: counters can drift; needs repair job.)
    - For link counts, denormalize “entity link count” into `MetaEntity` and update via central service on link changes.
    - Implement a repair “recount” job in settings, reusing current compute logic.
- Graph canvas snapshot:
  - `GraphCanvasDataLoader` sorts attributes per entity (`e.attributesList.sorted`) during snapshot creation. (`GraphCanvasDataLoader.swift`)
  - Option: store a pre-sorted `attributesList` (or cached sort keys) if sort cost becomes visible.
- Thumbnail store:
  - Ensure the cache key accounts for the requested size if the UI needs multiple sizes (**UNKNOWN** current UI usage patterns).

### C) Unification / pattern tightening (DI + services)
- Service configuration:
  - Currently configured in `BrainMeshApp.init` via multiple `Task.detached` calls (`EntitiesHomeLoader`, `GraphCanvasDataLoader`, `NodePickerLoader`, `GraphStatsLoader`, `AttachmentHydrator`, `ImageHydrator`, etc.). (`BrainMeshApp.swift`)
  - Option: create a single “AppServices” composer that configures all services and holds references.
- ModelContext usage:
  - Standardize “write contexts” vs “read contexts”:
    - reads: `autosaveEnabled = false`, never call `insert/delete` unless intended
    - writes: explicit save + error handling + optional `transactionAuthor`

---

## Risks & Edge Cases
(Storage/sync correctness is the top risk category for this codebase.)

- **CloudKit init fallback**: in release, a failure falls back to local store without surfacing a UI indicator (`BrainMeshApp.swift`). Risk: silent “no sync”.
- **Duplicate graph IDs**: project already has a repair service for duplicate `MetaGraph.id` records (`GraphDedupeService.swift`). Risk: other duplicates might exist for other models (**UNKNOWN** if observed).
- **Migration correctness**:
  - graphID migration is split across boot + attachments migration; ensure it runs before any heavy queries that use optional predicates. (`AppRootView.swift`, `GraphBootstrap.swift`, `AttachmentGraphIDMigration.swift`)
- **Offline and multi-device**:
  - Conflict behavior is implicit; how “last write wins” is applied is **UNKNOWN**.
- **Large binary payloads**:
  - Attachments use external storage; images do not. Risk: node images can bloat sync if not kept small.
- **Data loss in delete flows**:
  - Graph deletion deletes all content and clears local cached images (`GraphDeletionService.swift`). Ensure UI makes this irreversible action explicit (UI detail **UNKNOWN** if sufficiently clear).

---

## Observability / Debuggability
Files:
- `BrainMesh/Observability/BMObservability.swift`
- Most loaders/services also use `Logger(subsystem: "BrainMesh", category: "...")`

Current:
- `BMLog` offers dedicated categories: `load`, `expand`, `physics`.
- `BMDuration` is a lightweight timer to measure durations.

Recommendations:
- Add timing logs around:
  - `EntitiesHomeLoader.load(...)` end-to-end duration + counts compute duration.
  - `GraphCanvasDataLoader.loadSnapshot(...)` (hop count, nodes, links, time).
  - `AttachmentThumbnailStore.thumbnail(...)` (miss vs hit + generation time).
- Add a “debug overlay” view in the canvas to show:
  - node/edge counts, tick duration, render duration (**implementation currently UNKNOWN**).

---

## Open Questions (UNKNOWNs to resolve)
1. CloudKit conflict resolution and merge policy: **UNKNOWN** (SwiftData default behavior).
2. CloudKit database target: **UNKNOWN** which database `.automatic` maps to in this setup (private/shared/public).
3. Intended deployment target: project is set to `26.0` (`project.pbxproj`). Is that real or accidental?
4. Maximum intended graph sizes:
   - nodes/edges upper bound: **UNKNOWN**
   - attachment size limit: **UNKNOWN** (some code references “size limits”, but the actual limit policy needs confirming).
5. Image import enforcement:
   - max JPEG dimensions/bytes: **UNKNOWN** (check `Images/ImageImportPipeline.swift` if you want hard guarantees).
6. Are there “share/collab” features planned (CloudKit sharing): **UNKNOWN** (no CKShare usage found).
7. Migration strategy policy:
   - how to handle schema changes over time in SwiftData/CloudKit: **UNKNOWN**
8. Accessibility/perf target devices:
   - minimum RAM/CPU class: **UNKNOWN**
9. Unit/integration tests expectations:
   - data repair services and migrations have tests: **UNKNOWN**.

---

## First 3 Refactors I would do (P0)

### P0-1: Make graph scoping an invariant (finish the “graphID optional” era)
- **Ziel**
  - Ensure all persisted records that should be graph-scoped have a non-nil `graphID` so queries can stay strict and store-translatable.
- **Betroffene Dateien**
  - `BrainMesh/GraphBootstrap.swift`
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - Any fetch paths that still allow `graphID == nil` branches (e.g. loaders/services across `Mainscreen/`, `Stats/`, `GraphCanvas/`)
- **Risiko**
  - Migration bugs can cause data to “disappear” from the active graph if `graphID` assignment is wrong.
  - Requires careful ordering at startup (`AppRootView.runStartupIfNeeded()`).
- **Erwarteter Nutzen**
  - Removes the need for OR-style predicates that can force in-memory filtering.
  - Makes performance characteristics predictable (especially with `.externalStorage` attachments).
  - Simplifies service code and reduces “legacy branch” complexity.

### P0-2: Reduce EntitiesHomeLoader’s O(N) scans for counts
- **Ziel**
  - Stop fetching *all* `MetaAttribute` and `MetaLink` rows just to compute per-entity counters.
- **Betroffene Dateien**
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
  - Potentially `BrainMesh/Models.swift` (if you choose to persist counters on `MetaEntity`)
  - Any write paths that mutate links/attributes (e.g. `AddAttributeView`, `AddLinkView`, bulk link flows)
- **Risiko**
  - Persisted counters can drift unless every mutation path updates them correctly.
  - If you keep the scan-based repair as fallback, you must ensure both paths remain consistent.
- **Erwarteter Nutzen**
  - Faster “home list” load on large datasets and less memory pressure.
  - Less background CPU time → better battery and responsiveness.

### P0-3: Tame the canvas render+physics loop (make perf regressions harder)
- **Ziel**
  - Reduce per-frame allocations and main-thread work in the graph canvas so large graphs don’t jank.
- **Betroffene Dateien**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ partials affecting state churn)
- **Risiko**
  - Rendering/physics changes are “feel” sensitive; easy to break interaction semantics.
  - Requires careful profiling to avoid micro-optimizations that don’t move the needle.
- **Erwarteter Nutzen**
  - Smoother pan/zoom/drag on large graphs.
  - Lower CPU/battery usage due to fewer redraw triggers and less per-tick math.

