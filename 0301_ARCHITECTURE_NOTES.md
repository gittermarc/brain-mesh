# ARCHITECTURE_NOTES.md

> Scope: This document is **derived from the current repository snapshot** (Archiv.zip).  
> Anything not directly observable in code/config is marked as **UNKNOWN** and listed in **Open Questions**.

## Big Files List (Top 15 Swift files by lines)
These files are “risk multipliers”: large surface area, more merge conflicts, harder reviews, more chance to accidentally put work on the MainActor.

1. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **499 LoC**
2. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **474 LoC**
3. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **442 LoC**
4. `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **429 LoC**
5. `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` — **427 LoC**
6. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 LoC**
7. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **404 LoC**
8. `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388 LoC**
9. `BrainMesh/Mainscreen/BulkLinkView.swift` — **367 LoC**
10. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362 LoC**
11. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift` — **359 LoC**
12. `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` — **345 LoC**
13. `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **344 LoC**
14. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — **341 LoC**
15. `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` — **335 LoC**

### Notes / Why each is risky (very short)
1. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — off-main loader + search + caches; correctness + perf sensitive (caching TTL, predicates, N+1 risk).
2. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — high-frequency state changes (positions/velocities), lots of UI state; easy to regress perf.
3. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — BFS neighborhood + multiple fetches + in-memory filters; risk for big graphs and cancellation correctness.
4. `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — huge UI + data; compile time + maintenance risk (less runtime risk).
5. `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` — many states + SwiftData interactions + file importer/exporter; easy to create edge-case UI races.
6. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — image pipelines + SwiftData + caching; memory and UI responsiveness risk.
7. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — navigation + debounce + loader plumbing; UI race risk around sheets and reload triggers.
8. `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — detail rendering; less risky, but touched frequently by schema changes.
9. `BrainMesh/Mainscreen/BulkLinkView.swift` — batch operations + dedupe + pickers; correctness and UX risk, plus potential MainActor fetches.
10. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — media-heavy UI; memory/perf risk.
11. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift` — complex overlay UI on top of a 30 FPS canvas; invalidation risk.
12. `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` — “god view” for entity details; frequent changes; hard to test.
13. `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — media list + actions; perf risk on large galleries.
14. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — potentially big connection lists; needs strict off-main loading.
15. `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` — data import/remap; risk of data duplication/loss; needs deterministic batching/cancellation.

### Other large (non-Swift) files worth knowing
- `BrainMesh.xcodeproj/project.pbxproj` — ~600 lines (project configuration; easy to cause merge conflicts).
- `BrainMesh/Icons/IconCatalogData.json` — ~527 lines (icon data; large static payload).

## Hot Path Analyse

### 1) Rendering / Scrolling (SwiftUI invalidations, expensive work in UI)
#### Graph tab (highest risk)
- **High-frequency invalidations**:
  - `GraphCanvasScreen` holds `positions`/`velocities` as `@State` and updates them via a **Timer-based 30 FPS simulation** in `GraphCanvasView` (`BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift`).
  - Mitigation already in place: derived caches (`drawEdgesCache`, `lensCache`, `physicsRelevantCache`) to avoid recomputation during physics ticks (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`).
- **MainActor fetch during interaction** (**hotspot**):
  - `expand(from:)` does `modelContext.fetch(...)` on `@MainActor` for every expand (out/in links) (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Expand.swift`).
  - Risk: UI hitch while user taps nodes repeatedly; cap helps, but the hitch is still on the UI thread.
- **Per-node fetch in expansion** (**hotspot**):
  - Expansion resolves node meta via `fetchEntity/fetchAttribute` (SwiftData fetch-by-id) for each newly added node (`GraphCanvasScreen+Expand.swift` + `GraphCanvasScreen+Helpers.swift`).
  - Risk: repeated small fetches → latency spikes, especially on devices under load.
- **Canvas + overlays coupling**:
  - Complex overlays live in `GraphCanvasScreen+Overlays.swift` and can invalidate together with physics updates if not careful (selection/peek chips, etc.).

#### Entities tab (list)
- **Typing/search churn**:
  - `EntitiesHomeView` reloads via `.task(id: taskToken)` with a 250ms debounce (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`).
  - Loader work is off-main (good), but the UI can still churn if state changes too often (e.g. toggles + search + graph switch at once).
- **Row rendering + thumbnails**:
  - Thumbnails should come from cache (`imagePath` + async load). Any synchronous image load in cells would be a hotspot (**UNKNOWN** until row component code is audited).

#### Detail screens (media-heavy)
- Media management views like `NodeImagesManageView` and `NodeDetailShared+MediaGallery` are sensitive to memory (thumbnail decoding) and to the attachment/image hydration pipeline (`BrainMesh/Mainscreen/NodeDetailShared/*`, `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`).

### 2) Sync / Storage (CloudKit, fetch strategies, caching, lifecycle)
- **CloudKit container init + fallback**:
  - In `BrainMeshApp.init()` the app attempts CloudKit `.automatic`. In Release only, it falls back to local-only if CloudKit init fails (`BrainMesh/BrainMeshApp.swift`).
  - Risk: “it works on my device” scenarios (local-only silently) unless surfaced clearly in UI; `SyncRuntime.storageMode` exists (`BrainMesh/Settings/SyncRuntime.swift`).
- **Legacy migration work on startup**:
  - `AppRootView.bootstrapGraphing()` calls:
    - `GraphBootstrap.ensureAtLeastOneGraph`
    - `GraphBootstrap.migrateLegacyRecordsIfNeeded`
    - `GraphBootstrap.backfillFoldedNotesIfNeeded`
    (`BrainMesh/AppRootView.swift`, `BrainMesh/GraphBootstrap.swift`)
  - Risk: large datasets can stall startup if these do more work than expected (they try to keep checks cheap via `fetchLimit = 1`, good).
- **External storage blobs**:
  - Attachments use `@Attribute(.externalStorage)` for `fileData` (`BrainMesh/Attachments/MetaAttachment.swift`).
  - Risk: large blobs + CloudKit quotas, and cold-device cache misses → hydration stampedes (mitigated by `AttachmentHydrator` throttling).
- **Local caches**:
  - Images cache: `Application Support/BrainMeshImages` (`BrainMesh/ImageStore.swift`)
  - Attachments cache: `Application Support/BrainMeshAttachments` (via `AttachmentStore`, `AttachmentHydrator`)
  - Risk: cache eviction/cleanup strategy is partly implemented (`BrainMesh/Attachments/AttachmentCleanup.swift`) but overall lifecycle policy is **UNKNOWN**.

### 3) Concurrency (MainActor, Task lifetimes, cancellation, thread safety)
- **Project-wide default actor isolation is MainActor**:
  - Build setting `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`BrainMesh.xcodeproj/project.pbxproj`).
  - Implication: “accidentally on main” is the default; you must opt-out explicitly (actors, detached tasks, nonisolated services).
- **Actors + AnyModelContainer pattern**:
  - Background loaders/hydrators hold `AnyModelContainer` and create their own short-lived `ModelContext` (`BrainMesh/Support/AnyModelContainer.swift`, `BrainMesh/Support/AppLoadersConfigurator.swift`).
  - Good: avoids passing `@Model` objects across threads.
  - Risk: many places use `@unchecked Sendable` for DTOs to keep patches small (e.g. `GraphCanvasSnapshot`, `EntitiesHomeSnapshot`, `GraphTransferViewModel`).
- **Task.detached usage**:
  - Used in multiple places (`BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`, `BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/ImageStore.swift`).
  - Risk: detached tasks do not inherit cancellation and can outlive the initiating UI event; some places include manual cancellation checks, others don’t.
- **ScenePhase edge cases handled explicitly**:
  - `AppRootView.scheduleDebouncedBackgroundLock()` includes a debounce + grace window to avoid dismissing Photos pickers during FaceID prompts (`BrainMesh/AppRootView.swift`, `BrainMesh/Support/SystemModalCoordinator.swift`). This is well-motivated but adds lifecycle complexity.

## Refactor Map

### A) Concrete Splits (file → suggested new files)
1. `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
   - Split by sections:
     - `EntityDetailView+Header.swift`
     - `EntityDetailView+AttributesList.swift`
     - `EntityDetailView+Attachments.swift`
     - `EntityDetailView+Actions.swift`
2. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
   - Keep `GraphCanvasScreen.swift` as composition shell, move state machines into:
     - `GraphCanvasState.swift` (struct holding nodes/edges/selection/caches)
     - `GraphCanvasLoadingController.swift` (load scheduling, stale-token guard)
     - `GraphCanvasJumpController.swift` (staged jump logic)
3. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
   - Extract:
     - `EntitiesHomeListContent.swift` (list/grid rendering)
     - `EntitiesHomeEmptyStates.swift`
     - `EntitiesHomeRouting.swift` (sheets/navigation)

### B) Cache-/Index-Ideen (what to cache, keys, invalidation)
1. **EntitiesHome link-note search**: avoid per-ID fetch
   - Current: if a link note matches, endpoints are resolved via per-ID SwiftData fetch loops (`EntitiesHomeLoader.fetchEntities` in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`).
   - Option: chunked ID fetches (e.g. 100 IDs at a time) if `#Predicate { ids.contains($0.id) }` is reliable for UUID arrays (currently commented as unreliable → **UNKNOWN**).
   - Option (safer): graph-scoped “entity lookup cache” in the loader that maps `UUID → (name, iconSymbolName, imagePath?)` and is refreshed with TTL, so link-note matches can be resolved without N+1.
2. **GraphCanvas expand**:
   - Add a loader method `expandSnapshot(from:)` in `GraphCanvasDataLoader` that returns nodes/edges/meta in one background fetch, so the main thread only commits state.
3. **Image/Attachment hydration**:
   - Persist hydration checkpoints (last hydrated record ID/time) to avoid scanning all `imageData != nil` every pass (`ImageHydrator.hydrate` currently scans all matching records).
   - Key candidate: `(graphID, updatedAt)` is **UNKNOWN** because models don’t expose an `updatedAt` field.

### C) Vereinheitlichungen (Patterns, Services, DI)
- Introduce a thin “LoaderRegistry” so `AppLoadersConfigurator.configureAllLoaders` doesn’t become an ever-growing list of `await ...configure(...)` calls (`BrainMesh/Support/AppLoadersConfigurator.swift`).
- Standardize loader API:
  - `configure(container:)`
  - `loadSnapshot(...)`
  - `invalidateCache(...)` where applicable
- Consider extracting Pro gating into a single helper used by GraphPicker, Security, etc. (`BrainMesh/Pro/*`, `BrainMesh/GraphPickerSheet.swift`).

## Risiken & Edge Cases
- **Data loss / duplication (Import/Export)**:
  - Import creates new IDs and remaps relationships (`BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`). Risk: partial import if cancelled mid-batch; code uses batching constants and cancellation strides (good). Verify `context.save()` batching semantics.
- **CloudKit fallback to local-only**:
  - In Release, app can silently run local-only (`BrainMesh/BrainMeshApp.swift`). Ensure UI makes this obvious (`SyncRuntime` exists).
- **GraphID optionality**:
  - `graphID: UUID?` across many models for legacy migration. Risk: mixed datasets and predicates that assume non-nil.
- **Security UX vs system pickers**:
  - Debounced background lock is a non-trivial lifecycle workaround; regression-prone if other modals are added (`AppRootView.swift`, `SystemModalCoordinator.swift`).
- **External storage quotas / large blobs**:
  - Attachments fileData uses externalStorage; imageData also stored in SwiftData. Quota/size management is **UNKNOWN** (no explicit size guards found).

## Observability / Debuggability
- OSLog categories:
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics` (`BrainMesh/Observability/BMObservability.swift`)
- Existing timing:
  - `GraphCanvasScreen+Loading.swift` logs load time + node/edge counts.
  - `GraphCanvasScreen+Expand.swift` logs expand time.
- Suggested additions:
  - log cache-hit ratios in `EntitiesHomeLoader` (counts cache) and hydration operations (Image/Attachment).

## Open Questions (alles was UNKNOWN ist)
- CloudKit conflict resolution / merge policy (no explicit configuration found).
- Production push/aps environment setup (entitlements currently `development`; build-specific switching is **UNKNOWN**).
- Any background sync triggers beyond CloudKit remote notifications (no explicit BGTaskScheduler usage found → **UNKNOWN**).
- Cache lifecycle policy (when/how caches are purged, max sizes, error handling) beyond existing cleanup helpers.
- Any multi-user collaboration / sharing intent (no CKShare usage found; feature intent is **UNKNOWN**).
- Whether the StoreKit config file (`BrainMesh Pro.storekit`) is excluded from release builds or shipped (Xcode config is **UNKNOWN**).

## First 3 Refactors I would do (P0)
### P0.1 — Move Graph expand off the MainActor
- **Ziel:** Keine UI-Hänger beim Expandieren/Nachladen im Graph.
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Expand.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (neue API `expandSnapshot`)
  - ggf. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Loading.swift`
- **Risiko:** Mittel (Behavior muss identisch bleiben; careful about selection/pinning/caches).
- **Erwarteter Nutzen:** Spürbar bessere Responsiveness bei großen Graphen; weniger Main-thread contention.

### P0.2 — Fix N+1 link-endpoint resolution in EntitiesHome search
- **Ziel:** Link-Notiz-Suche bleibt schnell auch mit vielen Links (kein per-ID Fetch Loop).
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - ggf. neue Helper: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeEntityLookupCache.swift`
- **Risiko:** Niedrig–Mittel (Suchresultate müssen identisch bleiben; graphID filtering sauber halten).
- **Erwarteter Nutzen:** Deutlich weniger I/O bei Suche; stabilere Latenz beim Tippen.

### P0.3 — Cancellation hygiene for detached work (hydrators + stats)
- **Ziel:** Keine Tasks, die weiterlaufen obwohl UI weg ist / user action abgebrochen wurde.
- **Betroffene Dateien:**
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - ggf. `BrainMesh/ImageStore.swift` (in-flight loader tasks)
- **Risiko:** Niedrig (meist additive `Task.checkCancellation()` + replace detached with inheriting tasks where safe).
- **Erwarteter Nutzen:** Bessere Battery/CPU, weniger surprise stalls, klarere Task-Lifetimes.
