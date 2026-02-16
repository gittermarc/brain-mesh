# ARCHITECTURE_NOTES

## Scope of this document

This file focuses on **risk, hotspots, and refactor levers** with concrete pointers to the codebase. Anything not directly supported by code is marked **UNKNOWN** and collected in **Open Questions**.

## Big Files List (Top 15 by lines)

| Lines | File | Purpose | Why risky |
| --- | --- | --- | --- |
| 600 | BrainMesh.xcodeproj/project.pbxproj | Xcode project configuration (targets, build settings, file references). | Merge-conflict prone; small changes can ripple into build settings/signing. |
| 532 | BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift | Canvas drawing for nodes/edges/labels/thumbnails. | Per-frame work; changes easily impact FPS/battery and cause view invalidation. |
| 527 | BrainMesh/Icons/IconCatalogData.json | Icon catalog data (searchable list for icon picker). | Large static data; loading/parsing can impact startup/scroll perf if not cached. |
| 384 | BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift | Graph data loading (global + neighborhood), caching, layout seeding, log instrumentation. | High fan-out state mutations; risk of inconsistent graph state / racey reloads. |
| 329 | BrainMesh/GraphCanvas/GraphCanvasScreen.swift | Graph screen state composition + wiring into GraphCanvasView (tabs, sheets, derived caches). | Large SwiftUI state surface; small edits can cause invalidation storms. |
| 325 | BrainMesh/Mainscreen/BulkLinkView.swift | Bulk link creation UI (multi-select nodes, bidirectional option, etc.). | Complex selection state; easy to introduce logic bugs or slow queries. |
| 319 | BrainMesh/Onboarding/OnboardingSheetView.swift | Onboarding sheet: multi-step UI, progress, actions. | UI complexity; easy to regress navigation/state gating. |
| 314 | BrainMesh/PhotoGallery/PhotoGallerySection.swift | Detail-only photo gallery section (PhotosPicker integration + import pipeline wiring). | Heavy image I/O + async; easy to trigger blank-sheet/presentation races. |
| 307 | BrainMesh/Mainscreen/EntitiesHomeView.swift | Entity list root (graph switcher, search, custom fetch, navigation). | Custom fetch logic + debouncing; risk of stale list or accidental cross-graph mixing. |
| 297 | BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift | Full-screen / paging gallery viewer, zooming, image decode/background loading. | Async decode + view presentation; risk of memory spikes & sheet dismissal races. |
| 289 | BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift | Gallery browser grid/list with thumbnails, selection, navigation. | Thumbnail rendering + caching; scroll perf sensitive. |
| 282 | BrainMesh/GraphStatsView.swift | Stats tab UI and service wiring. | Multiple async loads; risk of repeated fetch/count work on invalidations. |
| 277 | BrainMesh/Models.swift | Core SwiftData models for graphs/entities/attributes/links + search folding. | Schema changes affect migrations/CloudKit; relationship macros can break builds. |
| 272 | BrainMesh/Appearance/AppearanceModels.swift | Display/appearance settings models (themes, presets, serialization). | Settings drift can cause inconsistent UI; large enums affect compile-time. |
| 268 | BrainMesh/Icons/IconPickerView.swift | Icon picker UI: search, sections, selection. | Large lists; scroll perf and search indexing sensitive. |

## Hot Path Analysis

### Rendering / Scrolling (SwiftUI)

#### Graph canvas (primary FPS/battery hotspot)
Key files:
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (Canvas drawing)
- `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift` (30 FPS simulation tick + pairwise forces)
- `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (state, derived caches, overlay wiring)
- `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift` (graph building; not per-frame but affects perceived responsiveness)

Why it’s a hotspot (concrete reasons):
- **Per-frame Canvas work**: rendering draws edges + nodes + labels every frame; changes can easily trigger more invalidations.
  - Rendering code lives in `GraphCanvasView+Rendering.swift`.
- **O(n²) interaction loop**: physics uses a nested loop over `simNodes` for repulsion (`for i ... for j ...`) in `GraphCanvasView+Physics.swift` (see `stepSimulation`).
- **High-frequency state changes**: `positions` and `velocities` update every tick; any extra work in the view update path gets multiplied.
- **Derived state matters**: the project already caches `drawEdgesCache` and `lensCache` in `GraphCanvasScreen` to avoid recomputing in `body` (see `recomputeDerivedState()` in `GraphCanvasScreen.swift`).

Practical “don’t accidentally regress this” checklist:
- [ ] No disk reads / image decoding in `GraphCanvasView` drawing closures.
- [ ] No SwiftData fetches triggered by `positions`/`velocities` updates (render path must stay pure).
- [ ] Keep expensive filters/groupings out of `body`; compute them on load and store in state (current approach is good).
- [ ] Keep physics tick stable: avoid allocating new arrays/dicts per tick if possible.

Where to look for regressions:
- `GraphCanvasView+Physics.swift`: `stepSimulation()` (repulsion + springs + integration).
- `GraphCanvasView+Rendering.swift`: loops over edges/nodes; label/notes drawing.
- `GraphCanvasScreen.swift`: `.onChange(of: ...)` hooks; ensure they don’t fire per tick.

#### List-heavy screens (scroll performance)
- Entities list: `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - Uses explicit `FetchDescriptor` + manual dedupe/sort in `fetchEntities(folded:)`.
  - Hotspot reason: rebuilding and sorting large arrays on every debounced search / graph change.
  - Good: work happens in `.task(id: taskToken)` with debounce; not inside `body`.

- Icon picker: `BrainMesh/Icons/IconPickerView.swift` + `IconCatalog.swift`
  - Hotspot reason: large symbol lists + search filtering; `IconCatalog` decodes `IconCatalogData.json` on first access.
  - Risk: first presentation of icon picker can stutter if JSON decode/search index build happens on the main thread.

- Gallery browser: `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` / `PhotoGalleryThumbnailView.swift`
  - Hotspot reason: many thumbnails; image decoding/caching determines scroll smoothness.

### Sync / Storage (SwiftData + CloudKit)

Key files:
- Container setup: `BrainMesh/BrainMeshApp.swift`
- Core models: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- Legacy migration: `BrainMesh/GraphBootstrap.swift`
- Main image import + caching: `BrainMesh/NotesAndPhotoSection.swift`, `BrainMesh/ImageHydrator.swift`, `BrainMesh/ImageStore.swift`
- Attachments: `BrainMesh/Attachments/*`
- Gallery images: `BrainMesh/PhotoGallery/PhotoGalleryImportController.swift`

What’s actually implemented (and therefore safe to state):
- CloudKit sync is **implicitly** provided by SwiftData using `ModelConfiguration(cloudKitDatabase: .automatic)` (`BrainMesh/BrainMeshApp.swift`).
- iCloud container is `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`).
- There is **no direct CloudKit API usage** (`import CloudKit` not found).

Hotspots / risk areas:
1) **Main-thread image decoding + compression + file I/O**  
   - `BrainMesh/NotesAndPhotoSection.swift` -> `importPhoto(_:)` is `@MainActor` and performs:
     - `item.loadTransferable(Data.self)` (async, OK)
     - `ImageImportPipeline.decodeImageSafely(...)` (CPU-heavy)
     - `ImageImportPipeline.prepareJPEGForCloudKit(...)` (CPU-heavy)
     - `ImageStore.saveJPEG(...)` (disk write)
   - Same pattern exists in `PhotoGalleryImportController.importPickedImages(...)` (also `@MainActor`) and in `ImageHydrator.hydrate(...)` (writes JPEGs via `ImageStore.saveJPEG`).
   - Why it matters: this can cause **visible UI stalls** during imports or startup hydration, especially with many images.

2) **Schema/migration pressure**
   - `graphID` is optional on most models and migration exists for entities/attributes/links (`GraphBootstrap.migrateLegacyRecordsIfNeeded`), but not for attachments.
   - Any schema-level change to `@Model` types affects CloudKit syncing behavior (**migration plan needed**).

3) **External storage asymmetry**
   - Attachments use `@Attribute(.externalStorage)` for `fileData` (`MetaAttachment.swift`).
   - Entity/Attribute main images use `imageData: Data?` without `externalStorage` (`Models.swift`).
   - Whether this is acceptable depends on expected image sizes (**UNKNOWN**; see Open Questions).

### Concurrency

Patterns used in this repo (with concrete examples):
- `.task(id:)` for debounced reloads
  - `EntitiesHomeView.swift`: `.task(id: taskToken)` includes `Task.sleep` for debounce and honors cancellation.
- `Task { ... }` fire-and-forget reloads on `.onChange`
  - `GraphCanvasScreen.swift`: `.onChange(of: activeGraphIDString)` starts `Task { await loadGraph(...) }` without a stored handle.
  - Risk: rapid changes can overlap loads and produce inconsistent intermediate UI state.
- `Task.detached` for background work / I/O
  - `ImageHydrator.swift`, `SettingsView.swift`, `PhotoGalleryViewerView.swift`, `AttachmentThumbnailStore.swift`.
  - Usually awaited; good for keeping heavy work off the main actor.

MainActor contention to watch:
- The project uses `@MainActor` on a lot of logic that also does heavy CPU/I/O (notably image pipelines). That can block UI even if everything is “async”.

Actionable checklist:
- [ ] Any image decode/compress should run off-main; only SwiftData mutations happen on main actor.
- [ ] Any loader triggered by `.onChange` that can fire frequently should be cancellable (store a `Task` handle).
- [ ] Timers (physics) must stop on `onDisappear` (already done in `GraphCanvasView.swift`).

## Refactor Map

### Concrete splits

These are “structure only” splits (no behavior change) that reduce risk and improve compile times:

1) `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (532 lines)
   - Split into:
     - `GraphCanvas/Rendering/GraphCanvasRendering+Edges.swift`
     - `GraphCanvas/Rendering/GraphCanvasRendering+Nodes.swift`
     - `GraphCanvas/Rendering/GraphCanvasRendering+Labels.swift`
     - `GraphCanvas/Rendering/GraphCanvasRendering+Thumbnails.swift`
   - Rationale: isolate per-frame drawing concerns; easier profiling and safer edits.

2) `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift` (384 lines)
   - Split into:
     - `GraphCanvas/Loading/GraphLoader.swift` (pure data fetch/build)
     - `GraphCanvas/Loading/GraphLayoutSeeding.swift`
     - `GraphCanvas/Loading/GraphNodeCaches.swift` (label/image/icon caches)
   - Rationale: loading is “hot” for perceived responsiveness and bug-prone.

3) Photo gallery / import
   - `BrainMesh/PhotoGallery/PhotoGallerySection.swift` (UI + wiring)
   - `BrainMesh/PhotoGallery/PhotoGalleryImportController.swift` (pipeline)
   - Keep pipeline in controller, but move heavy decode/compress off-main (see next section).

### Cache / Index ideas

Already present (good patterns):
- Folded search fields (`nameFolded`, `searchLabelFolded`) to avoid runtime transforms (`BrainMesh/Models.swift`, `EntitiesHomeView.fetchEntities`).
- Graph canvas derived render caches (`drawEdgesCache`, `lensCache`) to avoid per-frame recompute (`GraphCanvasScreen.swift`).

Additional ideas (low to medium risk):
1) Cancellable graph loader task
   - Store a `@State private var loadTask: Task<Void, Never>?` in `GraphCanvasScreen`.
   - Cancel+replace on `activeGraphIDString`/`hops`/`showAttributes` changes.
   - Benefit: avoids overlapping loads and transient inconsistent state.

2) Move image pipeline off-main
   - Decode + compress + disk write in `Task.detached`.
   - Then `await MainActor.run { imageData = jpeg; imagePath = filename; try? modelContext.save() }`.
   - Files: `NotesAndPhotoSection.swift`, `ImageHydrator.swift`, `PhotoGalleryImportController.swift`.
   - Benefit: avoids UI stalls.

3) Graph-scoped predicate helpers
   - Create one place for “graphID filter semantics” to avoid subtle inconsistencies.
   - Candidate: `GraphScope.swift` with helpers that return `#Predicate` fragments is **NOT** possible directly; but you can wrap FetchDescriptor constructors or provide small per-model builders.
   - Files: `EntitiesHomeView.swift`, `NodeLinksQueryBuilder.swift`, `AttachmentCleanup.swift`, `GraphCanvasScreen+Loading.swift`.

### Vereinheitlichungen (Patterns / Services / DI)

- Services already exist (`GraphStatsService`, `GraphDedupeService`, `GraphDeletionService`).
- The “Graph session” is global state via `GraphSession.shared` + `@AppStorage` (`BrainMesh/GraphSession.swift`).
  - Consider consolidating on one approach:
    - Either always read `@AppStorage("BMActiveGraphID")` directly (current approach in most views),
    - or always funnel through `GraphSession` (would reduce duplication but is a larger change).

- Keep SwiftData access patterns consistent:
  - Use `fetchCount` for stats-like views (already done in `GraphStatsService`).
  - Use debounced tasks for search (already done in `EntitiesHomeView`).

## Risiken & Edge Cases

### Data loss / integrity
- Attachments are not in a SwiftData relationship graph (no cascade). Any delete flow that removes entities/attributes must explicitly call cleanup (`AttachmentCleanup`, plus link cleanup where applicable).
- `graphID` is optional and “legacy records” are supported by predicates; this can accidentally mix data between graphs if predicates are inconsistent across screens.

### Migration risks
- Changing `@Model` schema (fields, relationship macros, externalStorage) can require a migration plan, especially with CloudKit-backed SwiftData.
- Current migration helper (`GraphBootstrap`) only migrates `MetaEntity`, `MetaAttribute`, `MetaLink`.

### Offline + multi-device
- SwiftData CloudKit sync behavior is implicit. The app does not expose a sync status UI; diagnosing “why device B didn’t get data yet” is currently hard (**UX/ops risk**, not necessarily correctness).

### Performance edge cases
- Importing many high-res images may block the main thread during decode/compress/write (see Hot Path: Sync/Storage).
- Very large graphs:
  - Physics: O(n²) repulsion loop in `GraphCanvasView+Physics.swift`.
  - Rendering: edge drawing cost scales with edge count; `maxNodes/maxLinks` caps exist in `GraphCanvasScreen.swift` but the user can still load sizeable data.

## Observability / Debuggability

Existing instrumentation:
- `BrainMesh/Observability/BMObservability.swift` defines:
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics` (os.Logger)
  - `BMDuration` (cheap elapsed time measurement)
- Used in:
  - `GraphCanvasScreen+Loading.swift` (logs loadGraph duration and counts)
  - `GraphCanvasView+Physics.swift` (tick timing / sleep behavior)

Suggestions (concrete, low risk):
- Add “slow tick” logging in `GraphCanvasView+Physics.swift`:
  - log when a tick exceeds a threshold (e.g. > 16ms / 33ms) using `BMDuration`.
- Add import pipeline timing:
  - wrap decode/compress/write in `BMDuration` in `NotesAndPhotoSection.swift` and `PhotoGalleryImportController.swift` (once moved off-main, timing becomes easier and safer).

## Open Questions (UNKNOWN)

- **CloudKit / SwiftData migration strategy**: how are schema changes handled in production? (No explicit migration tooling found; SwiftData CloudKit migrations can be tricky.)
- **Expected image sizes** for `MetaEntity.imageData` / `MetaAttribute.imageData`: are you guaranteeing “small JPEGs” only? If not, `externalStorage` or alternate storage may be required.
- **Conflict resolution policy**: if two devices edit the same entity/attribute/link concurrently, what should win? (No explicit merge strategy in code.)
- **Graph sharing / collaboration**: is multi-user sharing planned? (No CloudKit Share usage found; may be out of scope.)
- **Attachment cache location & lifetime**: where exactly are preview files stored, and what is the intended cleanup policy beyond manual “clear cache”? (Some cleanup exists, but policy is not documented.)
- **Security expectations**: should graph lock apply to all screens or only graph-specific views? Current enforcement occurs in `AppRootView` via `GraphLockCoordinator`, but desired UX is **UNKNOWN**.

## First 3 Refactors I would do (P0)

### P0.1 — Move image decode/compress/file I/O off the MainActor
- **Goal**: eliminate UI stalls during photo import and startup hydration.
- **Affected files**:
  - `BrainMesh/NotesAndPhotoSection.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryImportController.swift`
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/ImageStore.swift` (may stay sync; just call it off-main)
- **Risk**: medium  
  - SwiftData writes must stay on the main actor; you need a clean boundary (`Task.detached` for CPU/I/O, `MainActor.run` for model mutations).
- **Expected benefit**: high  
  - smoother imports, less startup hitching, better perceived performance.

### P0.2 — Make GraphCanvas reloads cancellable (single loader task)
- **Goal**: avoid overlapping `loadGraph()` executions when graph/hops/toggles change quickly.
- **Affected files**:
  - `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift`
- **Risk**: low to medium  
  - mostly orchestration; behavior should remain the same but timing becomes deterministic.
- **Expected benefit**: medium  
  - fewer transient inconsistencies, less wasted work, easier debugging.

### P0.3 — Split the largest per-frame rendering file into focused units
- **Goal**: reduce compile times + make performance changes safer.
- **Affected files**:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` -> new `GraphCanvas/Rendering/*` files
- **Risk**: low  
  - should be pure refactor if signatures stay the same.
- **Expected benefit**: medium  
  - easier profiling, smaller diffs, fewer accidental regressions.
