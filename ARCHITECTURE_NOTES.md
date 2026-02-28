# ARCHITECTURE_NOTES.md — BrainMesh

> Scope: This document is intentionally technical. All factual claims are backed by concrete file paths. Anything unclear is marked **UNKNOWN** and collected in “Open Questions”.

## Big Files List (Top 15 by lines)
| # | File | Lines | Primary types |
|---:|---|---:|---|
| 1 | `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` | 499 | struct EntitiesHomeRow, struct EntitiesHomeSnapshot, actor EntitiesHomeLoader |
| 2 | `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` | 474 | struct GraphCanvasScreen |
| 3 | `GraphCanvas/GraphCanvasDataLoader.swift` | 442 | struct GraphCanvasSnapshot, actor GraphCanvasDataLoader |
| 4 | `Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 410 | struct NodeImagesManageView |
| 5 | `Mainscreen/EntitiesHome/EntitiesHomeView.swift` | 404 | struct EntitiesHomeView, struct EntityDetailRouteView, enum EntitiesHomeSortOption |
| 6 | `Mainscreen/Details/NodeDetailsValuesCard.swift` | 388 | struct NodeDetailsValuesCard |
| 7 | `Mainscreen/BulkLinkView.swift` | 367 | struct BulkLinkView, struct BulkLinkCompletion |
| 8 | `Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 362 | struct NodeGalleryThumbGrid, struct NodeGalleryThumbTile, struct NodeMediaAllView |
| 9 | `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift` | 359 | extensions/helpers |
| 10 | `Icons/AllSFSymbolsPickerView.swift` | 357 | struct AllSFSymbolsPickerView, class AllSFSymbolsPickerViewModel |
| 11 | `PhotoGallery/PhotoGallerySection.swift` | 344 | struct PhotoGallerySection, struct PhotoGalleryViewerRequest |
| 12 | `Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` | 341 | struct NodeConnectionsAllView |
| 13 | `Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` | 331 | class MarkdownAccessoryView, enum Action, class EdgeFadeView, enum Edge |
| 14 | `Attachments/AttachmentImportPipeline.swift` | 326 | struct PreparedAttachmentImport, enum AttachmentImportPipeline, enum AttachmentImportPipelineError |
| 15 | `Pro/ProCenterView.swift` | 322 | struct ProCenterView |

### Why these are risky (quick rationale)
- **UI mega-views** (state explosion, many sheets/alerts, hard-to-test paths):
  - `Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ related partials)
  - `Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
- **Background loaders** (correctness + cancellation + cache invalidation):
  - `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - `GraphCanvas/GraphCanvasDataLoader.swift`
- **Media & imports** (I/O heavy, concurrency, memory pressure):
  - `Attachments/AttachmentImportPipeline.swift`
  - `PhotoGallery/PhotoGallerySection.swift`
- **StoreKit** (transaction edge cases, product loading, verification):
  - `Pro/ProCenterView.swift` (+ `Pro/ProEntitlementStore.swift`)

---

## Hot Path Analyse

### 1) Rendering / Scrolling (SwiftUI invalidations, expensive computations)
#### Graph Canvas (highest risk)
**Files**
- Simulation: `GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Rendering: `GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift` + `GraphCanvasView+Draw*.swift`
- Screen orchestration / state: `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`

**Why hotspot**
- **O(n²) per tick**: physics uses a pair loop `for i in 0..<simNodes.count { for j in (i+1)..<simNodes.count { ... } }` at 30 Hz Timer (`Timer.scheduledTimer(withTimeInterval: 1/30, ...)`) in `GraphCanvasView+Physics.swift`.
- **Main-thread contention**: the Timer runs on the main run loop; `positions/velocities` are SwiftUI bindings that update frequently, driving view invalidations.
- **Expensive Canvas drawing**:
  - Edge drawing loops through `drawEdges` every frame (`GraphCanvasView+DrawEdges.swift`).
  - Label “halo” draws up to 8 extra Text draws per label (`GraphCanvasView+DrawLabels.swift`).

**Existing mitigations in code**
- **Spotlight physics**: simulation can restrict to “relevant” nodes via `physicsRelevant` (computed in `GraphCanvasScreen.updateDerivedCaches()` in `GraphCanvasScreen.swift`).
- **Lens**: can hide/dim non-relevant nodes/edges; reduces draw and physics work (`GraphCanvas/GraphCanvasTypes.swift`).

**Remaining risk**
- For large graphs, even with node/edge caps, physics + Canvas can dominate CPU and battery.
- Frequent re-renders may also affect overlays and action chips that sit in the same ZStack (`GraphCanvasScreen.swift`).

#### Entities Home list/grid
**Files**
- View: `Mainscreen/EntitiesHome/EntitiesHomeView.swift`
- Loader: `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`

**Why hotspot**
- Home supports debounced search + optional counts (attributes/links) and notes previews; worst case it can trigger repeated loads while typing.
- Loader does multi-source search:
  - entities by `nameFolded/notesFolded`
  - attributes by `searchLabelFolded/notesFolded` (then resolves owners)
  - links by `noteFolded`
  - See `EntitiesHomeLoader.fetchEntities(...)` in `EntitiesHomeLoader.swift`.

**Existing mitigations**
- Off-main loading via `actor EntitiesHomeLoader` and value-only snapshots.
- TTL caches for counts (`countsCacheTTLSeconds = 8`) to reduce repeated full scans while typing (`EntitiesHomeLoader.swift`).

**Remaining risk**
- Cache invalidation correctness: edits must call `invalidateCache(for:)` consistently (otherwise stale counts).
- Complex search query path increases risk of “unexpected” results ordering or duplicates (there is de-dupe logic for entities via `unique[e.id]`).

#### Node detail screens (Entity / Attribute)
**Files**
- Entity: `Mainscreen/EntityDetail/EntityDetailView.swift`
- Attribute: `Mainscreen/AttributeDetail/*`
- Links query builder: `Mainscreen/NodeLinksQueryBuilder.swift`
- “All connections” off-main loader UI: `Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`, `...Connections.AllView.swift`

**Why hotspot**
- `EntityDetailView` declares `@Query var outgoingLinks/incomingLinks` (see top of `EntityDetailView.swift`). The built queries (via `NodeLinksQueryBuilder`) have **no fetchLimit** and are sorted by `createdAt` descending.
- For nodes with many links, SwiftData may load large arrays on the main actor, impacting screen open + scrolling.

**Existing mitigations**
- There is a dedicated loader for the “Alle Verbindungen” screen (`NodeConnectionsLoader` actor), suggesting awareness that this path can be large.

**Remaining risk**
- The *default* detail screen path still has potentially unbounded `@Query` link lists.

---

### 2) Sync / Storage (CloudKit ops, fetch strategies, caching)
**Core setup**
- `BrainMeshApp.swift` creates the SwiftData container with `cloudKitDatabase: .automatic` and sets a runtime flag via `SyncRuntime.shared.setStorageMode(.cloudKit)`.
- Release builds fall back to local-only container on CloudKit init failure (same file).
- iCloud account status is fetched via `CKContainer(accountStatus)` in `Settings/SyncRuntime.swift`.

**Data migrations / backfills**
- Startup calls in `AppRootView.bootstrapGraphing()`:
  - Ensure at least one graph exists (`GraphBootstrap.ensureAtLeastOneGraph`)
  - Backfill missing `graphID` (`GraphBootstrap.migrateLegacyRecordsIfNeeded`)
  - Backfill folded note indices (`GraphBootstrap.backfillFoldedNotesIfNeeded`)
  - File: `GraphBootstrap.swift`

**Cache layers**
- Entity/Attribute main photos:
  - SwiftData: `MetaEntity.imageData` / `MetaAttribute.imageData`
  - Disk cache: `ImageStore.swift` writes to Application Support `BrainMeshImages` (and stores `imagePath` in models)
  - Hydration: `ImageHydrator.swift` (actor) syncs `imageData` → disk cache.
- Attachments:
  - SwiftData: `MetaAttachment.fileData` marked `@Attribute(.externalStorage)` (`Attachments/MetaAttachment.swift`)
  - Disk cache: `Attachments/AttachmentStore.swift` (and related thumbnail/duration stores)
  - Hydration: `Attachments/AttachmentHydrator.swift` (actor)

**Risks / gotchas**
- **CloudKit record size pressure**: Entities/Attributes store image bytes as plain `Data?` (no `.externalStorage`) in `MetaEntity.swift` / `MetaAttribute.swift`. Whether this becomes a problem depends on how aggressively images are compressed before storing — **UNKNOWN** without analyzing import flows end-to-end.
- **Local-only fallback in Release**: Great for resilience, but can mask CloudKit config errors in production unless surfaced clearly (there is UI for this in `Settings/SyncRuntime.swift`).

---

### 3) Concurrency (MainActor, Task lifetimes, cancellation, thread safety)
**Good patterns already present**
- Off-main data loading via actors + `AnyModelContainer` wrapper:
  - `Support/AnyModelContainer.swift`
  - Configured centrally in `Support/AppLoadersConfigurator.swift`
- Cancellation checks in long loops:
  - `EntitiesHomeLoader.swift`, `GraphCanvasDataLoader.swift`, `GraphCanvasScreen+Loading.swift`

**Known risky patterns**
- **Timer-driven simulation on main**: `GraphCanvasView+Physics.swift` uses `Timer.scheduledTimer` → tight loop with heavy work.
- **`Task.detached` usage**:
  - Loader configuration fan-out (`Support/AppLoadersConfigurator.swift`)
  - iCloud account refresh on launch (`BrainMeshApp.swift`)
  - Cache size computation in settings (`Settings/SyncMaintenanceView.swift`)
  Detached tasks are fine, but make lifetime/cancellation harder to reason about if they grow.

**Thread-safety notes**
- Several snapshot structs are marked `@unchecked Sendable` (e.g., `GraphCanvasSnapshot`, `GraphStatsSnapshot`) to keep patches minimal. This is okay if they contain only value types; audit required if these start carrying reference types.

---

## Refactor Map

### A) Concrete Splits (which file → which new files)
#### Entities Home UI split (maintainability)
- From: `Mainscreen/EntitiesHome/EntitiesHomeView.swift`
- To (suggested):
  - `EntitiesHomeView+Toolbar.swift` (toolbar, search, view options)
  - `EntitiesHomeView+States.swift` (empty/loading/error states)
  - `EntitiesHomeView+ListGrid.swift` (list/grid renderers)
  - `EntitiesHomeView+Routing.swift` (navigation destinations/sheets)
- Benefit: fewer merge conflicts + easier to test “state” rendering.

#### Node media management split (complex flows)
- From: `Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
- To:
  - `NodeImagesManageView+Import.swift` (PhotosPicker/import pipeline calls)
  - `NodeImagesManageView+Actions.swift` (rename/delete/move)
  - `NodeImagesManageView+UI.swift` (grid/list UI)
- Benefit: isolate I/O-heavy code from view layout; easier to reason about memory pressure.

#### GraphCanvas screen split (already partially split; continue)
- From: `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ existing partials)
- Additional suggestions:
  - `GraphCanvasScreen+JumpRouting.swift` (jump staging/consumption)
  - `GraphCanvasScreen+SelectionActions.swift` (action chip actions)
  - `GraphCanvasScreen+PerformanceGates.swift` (simulationAllowed, derived caches)
- Benefit: makes the “load + selection + overlays” interplay more readable.

### B) Cache / Index ideas (what to cache, invalidation)
- **Link counts & adjacency index for Graph canvas**
  - Today: Graph canvas loader fetches links and filters by node ids (`GraphCanvasDataLoader.loadGlobal`).
  - Idea: maintain a lightweight in-memory adjacency map keyed by `graphID` with TTL (similar to EntitiesHome counts cache) to speed up repeated “neighborhood” loads when the user pans/zooms.
  - Risk: invalidation after link edits must be precise (hook into link creation/deletion flows).
  - Files to touch:
    - `GraphCanvas/GraphCanvasDataLoader.swift`
    - link creation flows (`Mainscreen/AddLinkView.swift`, `Mainscreen/NodeAddLinkSheet.swift`) + deletion flows (**UNKNOWN** exact paths for link deletion UI; investigate).

- **Details fields index**
  - Details schema is per entity (`MetaDetailFieldDefinition`) and values per attribute (`MetaDetailFieldValue`).
  - If UI frequently needs “pinned fields” for many attributes, precompute a `pinnedFieldIDsByEntityID` map.
  - Likely touchpoints:
    - `Models/DetailsModels.swift`
    - UI: `Mainscreen/Details/NodeDetailsValuesCard.swift`

### C) Vereinheitlichungen (Patterns, services, DI)
- Standardize a “Loader protocol” shape:
  - configure(container:) + loadSnapshot(args...) + invalidateCache(...)
  - Several loaders already follow this; documenting it would reduce drift.
  - Files: `Support/AppLoadersConfigurator.swift`, each `*Loader.swift`.
- Consider a small “AppServices” container for environment injection instead of many `@EnvironmentObject`:
  - Today `BrainMeshApp.swift` injects many stores (appearance, displaySettings, onboarding, graphLock, systemModals, proStore, tabRouter, graphJump).
  - This is functional but increases root wiring and preview complexity.

---

## Risiken & Edge Cases
- **Data loss / schema changes**:
  - Removing or changing SwiftData @Model fields requires migration planning. Example: duplicated lock fields exist on `MetaEntity`/`MetaAttribute` (`Models/MetaEntity.swift`, `Models/MetaAttribute.swift`) but usage appears only on `MetaGraph` (`Security/GraphLock/GraphLockCoordinator.swift`). Removing them would be a schema migration.
- **Offline + multi-device**
  - SwiftData+CloudKit is eventually consistent; UI that assumes immediate cross-device consistency needs testing (especially around link label denormalization and caches).
- **Locks + system pickers**
  - There is explicit debounce logic to avoid locking while Photos pickers are active (`AppRootView.swift` + `Support/SystemModalCoordinator.swift`). This is a real-world edge case and should stay covered by regression tests.

---

## Observability / Debuggability
- Logging categories: `Observability/BMObservability.swift` (`BMLog.load`, `BMLog.expand`, `BMLog.physics`)
- Suggested additions (low risk):
  - Add structured log events around:
    - Graph loads (already present in `GraphCanvasScreen+Loading.swift`)
    - EntitiesHome load durations (`EntitiesHomeLoader.swift` uses `Logger`)
    - StoreKit product load/purchase (`Pro/ProEntitlementStore.swift`)
  - Add a Settings toggle “Verbose logging” to gate log volume (**UNKNOWN** existing debug settings).

---

## Open Questions (UNKNOWN)
- **UNKNOWN**: CloudKit schema evolution strategy (how to handle breaking model changes; no explicit model versioning found in sources scanned).
- **UNKNOWN**: Expected maximum image sizes stored in `MetaEntity.imageData` / `MetaAttribute.imageData` (no `.externalStorage`).
- **UNKNOWN**: Are attribute–attribute links intended? (Model supports NodeKind in `MetaLink`, but GraphCanvas global load filters entity–entity in `GraphCanvasDataLoader.loadGlobal`.)
- **UNKNOWN**: Exact link deletion/cleanup flows and whether they invalidate caches deterministically (need to trace link UI actions).
- **UNKNOWN**: Whether remote notification handling is implemented beyond enabling `UIBackgroundModes=remote-notification` in `Info.plist`.

---

## First 3 Refactors I would do (P0)

### P0.1 — GraphCanvas: reduce main-thread simulation pressure
- **Ziel**: Make graph interaction smoother by reducing per-frame work and view invalidations.
- **Betroffene Dateien**
  - `GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - (optional) `GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift`
- **Risiko**: **Medium** (touches interactive core; regression risk in drag/pin/selection).
- **Erwarteter Nutzen**
  - Lower CPU/battery usage on large graphs
  - Fewer dropped frames (especially on older devices)

### P0.2 — Detail Screens: bound link fetching + lazy “All connections”
- **Ziel**: Avoid unbounded `@Query` link arrays on detail open; keep UI responsive for nodes with many links.
- **Betroffene Dateien**
  - `Mainscreen/EntityDetail/EntityDetailView.swift`
  - `Mainscreen/NodeLinksQueryBuilder.swift`
  - `Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift` (reuse)
- **Risiko**: **Low–Medium** (UI behavior changes; needs UX agreement).
- **Erwarteter Nutzen**
  - Faster screen open + smoother scrolling
  - More predictable memory usage

### P0.3 — Startup migrations: move heavy backfills off the main actor
- **Ziel**: Ensure first launch after updates stays fast even with lots of legacy records.
- **Betroffene Dateien**
  - `GraphBootstrap.swift`
  - `AppRootView.swift`
  - (new) `Support/StartupMigrationRunner.swift` (actor/service)
- **Risiko**: **Medium** (must respect SwiftData context/thread rules; needs careful testing).
- **Erwarteter Nutzen**
  - Less startup jank
  - Migrations can be throttled/cancellable and better observable
