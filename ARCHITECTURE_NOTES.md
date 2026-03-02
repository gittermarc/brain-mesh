# ARCHITECTURE_NOTES.md

_Generated: 2026-03-01 • Project: BrainMesh_

## Big Files List (Top 15 by line count)
These are the largest Swift files in the current snapshot. Large files are not automatically “bad”, but they correlate strongly with:
- merge conflicts
- higher compile times
- accidental coupling (UI + loading + caching + routing in one file)
- performance footguns (expensive work creeping into render path)

- `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` — **428 lines**
  - Purpose: Graph transfer UI state + import/export orchestration (ViewModel).
  - Risk: mixes UI state + async import/export + SwiftData queries; cancellation/error propagation can get messy.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 lines**
  - Purpose: Manage node image gallery, thumbnails, actions (SwiftUI view).
  - Risk: big SwiftUI bodies tend to accumulate expensive computed work and multiple `.task`/sheet routes.
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **368 lines**
  - Purpose: Bulk create links UI (SwiftUI view).
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **363 lines**
  - Purpose: Gallery grid components for node details.
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` — **346 lines**
  - Purpose: Entity detail screen (SwiftUI) with multiple sections/flows.
  - Risk: big SwiftUI bodies tend to accumulate expensive computed work and multiple `.task`/sheet routes.
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **345 lines**
  - Purpose: Photo gallery section UI + import actions.
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — **342 lines**
  - Purpose: All connections list UI (SwiftUI).
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` — **336 lines**
  - Purpose: Graph import logic (SwiftData writes, format mapping).
  - Risk: SwiftData writes + remapping; bugs can cause data loss/duplication.
- `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **332 lines**
  - Purpose: UIKit accessory / toolbar for Markdown editing.
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/Attachments/AttachmentImportPipeline.swift` — **327 lines**
  - Purpose: Attachment import pipeline (prepare/import items, UTType handling).
  - Risk: deals with file/UTType + byte handling; easy to accidentally do heavy work on MainActor.
- `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift` — **325 lines**
  - Purpose: Viewer UI for a gallery item.
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/Pro/ProCenterView.swift` — **323 lines**
  - Purpose: Pro center / upsell hub UI.
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` — **319 lines**
  - Purpose: Gallery browsing UI with PhotosUI integration.
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` — **318 lines**
  - Purpose: Stats root view UI.
  - Risk: file is large; likely mixes UI + async/loading + state.
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard/NodeDetailsValuesCard+Components.swift` — **315 lines**
  - Purpose: Details values card UI components.
  - Risk: file is large; likely mixes UI + async/loading + state.

## Hot Path Analysis

### Rendering / Scrolling
- **Graph physics tick (30 FPS on main run loop)**
  - File: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - Reason:
    - Uses `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` to call `stepSimulation()` frequently.
    - `stepSimulation()` performs a pair loop over nodes for repulsion/collisions (`for i in 0..<simNodes.count { for j in (i+1)..<simNodes.count { ... } }`), i.e. **O(n²)** in the number of simulated nodes.
    - Each tick copies dictionaries (`var pos = positions`, `var vel = velocities`), then assigns them back — can cause allocations + SwiftUI invalidations if not carefully gated.
  - Existing mitigations:
    - `simulationAllowed` gate + sleep when idle (stops timer after ~3 seconds of low movement).
    - “Spotlight physics” via `physicsRelevant` set to reduce simulated nodes.

- **GraphCanvas render invalidation pressure**
  - Files:
    - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (state + caches)
    - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+DerivedState.swift` (cached derived render state)
  - Reason:
    - `positions/velocities` update at 30 FPS; if derived state (edges/lens/etc.) recomputes in `body`, it multiplies per-frame cost.
  - Existing mitigations:
    - Cached `drawEdgesCache`, `lensCache`, `physicsRelevantCache` stored in `@State` to keep `body` cheap.
    - MiniMap throttling snapshot (`miniMapPositionsSnapshot`) to avoid redrawing MiniMap on every tick.

- **Thumbnail-heavy lists (gallery/media)**
  - Files:
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` (row `.task(id:)` loads thumbnail)
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
    - `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`, `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift`
  - Reason:
    - Many cells start async work via `.task(id:)` when scrolled into view.
    - Risk of “cache-miss stampede” if each cell triggers file hydration/thumbnail decode.
  - Existing mitigations:
    - `AttachmentHydrator` uses `AsyncLimiter(maxConcurrent: 2)` + `inFlight` dedupe (`BrainMesh/Attachments/AttachmentHydrator.swift`).
    - `ImageStore.loadUIImageAsync` de-duplicates in-flight loads (`BrainMesh/ImageStore.swift`).

### Sync / Storage
- **CloudKit-backed SwiftData container + fallback**
  - File: `BrainMesh/BrainMeshApp.swift`
  - Reason:
    - CloudKit init is a common failure point (entitlements/signing/iCloud state).
    - Behavior differs between DEBUG (fatalError) and Release (fallback to local-only). This is intentional but can confuse users if not surfaced clearly.
  - Surface status:
    - `SyncRuntime` publishes `storageMode` and `iCloudAccountStatusText` (`BrainMesh/Settings/SyncRuntime.swift`).

- **External-storage attachments + on-demand cache hydration**
  - Files:
    - Model: `BrainMesh/Attachments/MetaAttachment.swift` (`@Attribute(.externalStorage) var fileData: Data?`)
    - Hydration: `BrainMesh/Attachments/AttachmentHydrator.swift`
    - Store paths: `BrainMesh/Attachments/AttachmentStore.swift`
  - Reason:
    - External storage implies bytes may need to be fetched from disk/iCloud; calling this on main can stall.
    - Hydrator is designed to be called from cells and must stay aggressively throttled.

- **Image cache hydration**
  - Files:
    - `BrainMesh/ImageHydrator.swift` (background scan + disk writes)
    - `BrainMesh/ImageStore.swift` (memory+disk cache; async de-dup load; async save/delete)
  - Reason:
    - Devices syncing new data can have `imageData` but no local `imagePath` cache file; hydration must not block UI.

### Concurrency / Task Lifetimes
- **Central loader configuration is fire-and-forget**
  - File: `BrainMesh/Support/AppLoadersConfigurator.swift`
  - Reason:
    - Uses a static `Task(priority: .utility)` to configure multiple singletons/actors.
    - It cancels the previous configure task but does not currently expose status to the UI.
  - Risk:
    - If a screen is opened before configuration finishes, some loaders may be unconfigured and throw/skip. Many loaders guard this, but behavior can vary. **UNKNOWN** whether all callers handle “not configured” consistently.

- **`Task.detached` usage (audit targets)**
  - Highest concentration of detach calls:
    - `BrainMesh/ImageStore.swift` — `Task.detached` x3
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeAttachmentsManageView+Import.swift` — `Task.detached` x2
    - `BrainMesh/PhotoGallery/PhotoGalleryActions.swift` — `Task.detached` x2
    - `BrainMesh/Attachments/AttachmentsSection+Import.swift` — `Task.detached` x2
    - `BrainMesh/Attachments/AttachmentThumbnailStore.swift` — `Task.detached` x2
    - `BrainMesh/Attachments/MediaAllLoader.swift` — `Task.detached` x2
    - `BrainMesh/Stats/GraphStatsLoader.swift` — `Task.detached` x2
    - `BrainMesh/BrainMeshApp.swift` — `Task.detached` x1
    - `BrainMesh/NotesAndPhotoSection.swift` — `Task.detached` x1
    - `BrainMesh/ImageHydrator.swift` — `Task.detached` x1
  - Guidance:
    - Detached tasks break structured concurrency; they won’t automatically cancel with a parent task unless you manage them.
    - In several places you already do the right thing: `await Task.detached { ... }.value` + throttle + `inFlight` dedupe.
    - Red flag cases are “fire-and-forget detached” without a handle, token, or limiter.

## Refactor Map (Concrete, project-specific)

### Mechanical Splits (reduce coupling / compile time)
- `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` → split by responsibility
  - Suggested cut:
    - `GraphTransferViewModel.swift` (Published state + public API)
    - `GraphTransferViewModel+Import.swift` (import flow orchestration)
    - `GraphTransferViewModel+Export.swift` (export flow orchestration)
    - `GraphTransferViewModel+Errors.swift` (error mapping + alerts)
  - Risk: low if move-only; medium if you change async boundaries.

- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` → split UI + row + actions
  - Suggested cut:
    - `NodeImagesManageView.swift` (screen shell)
    - `NodeImagesManageRow.swift` (row view + thumbnail loading)
    - `NodeImagesManageActions.swift` (set main / delete / open)
  - Benefit: avoids re-render cascades and makes thumbnail lifecycle/cancellation reviewable.

- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` (346 lines) → split by sections
  - Suggested cut: `EntityDetailView+Header`, `+Details`, `+Links`, `+Media`, `+Sheets` (pattern already used in `AttributeDetailView*.swift`).

### Performance / Hotpath Refactors
- **GraphCanvas Expand off-main**
  - Current file: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Expand.swift`
  - Issue: method `expand(from:)` is `@MainActor` and performs SwiftData fetches (`modelContext.fetch(outFD/inFD)`).
  - Proposed change:
    - Add an actor API on `GraphCanvasDataLoader` such as `expandDelta(from:activeGraphID:includeAttributes:limits:existingKeys:) -> Delta` using a background `ModelContext`.
    - UI commits the delta on MainActor and uses a token/stale guard to ignore late results.
  - Benefit: reduces UI jank when expanding dense neighborhoods.

- **Physics: reduce allocations on tick**
  - File: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - Possible levers (keep behavior identical):
    - Avoid full dictionary copy if only a subset of nodes is simulated (`physicsRelevant` case).
    - Precompute arrays of positions for `simNodes` per tick to reduce dictionary lookups inside the pair loop.
    - Add a hard cap for simulated nodes when `physicsRelevant == nil` (fail-safe for pathological graphs).
  - Risk: medium (behavior and “feel” can change).

- **Thumbnail pipeline: cancellation + backpressure**
  - Files: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`, gallery views.
  - Levers:
    - Ensure thumbnail tasks respect cancellation quickly (check `Task.isCancelled` between decode steps).
    - Consider a shared global limiter for thumbnail decode in addition to hydration IO limiter (to keep CPU spikes under control).
  - Risk: low if you only add cancellation checks / limiters.

### Cache / Index Ideas
- **Graph-scoped predicate helpers**
  - Many fetches repeat `(graphID == gid || graphID == nil)`; consolidating into helper builders reduces bugs and makes migration cleanup easier.
  - Candidate location: `BrainMesh/Support/GraphScopePredicates.swift` (new).

- **Denormalized labels are already present (good)**
  - `MetaLink` stores `sourceLabel` / `targetLabel` in addition to IDs.
  - Ensure rename flows consistently update denormalized link labels (`BrainMesh/Mainscreen/NodeRenameService.swift` is configured in `AppLoadersConfigurator`).

## Risks & Edge Cases
- **CloudKit init failure modes**:
  - Debug crash vs Release fallback is intentional, but it can hide real sync failures in TestFlight if you’re not careful.
  - If Release falls back, users silently lose sync unless Settings surfaces it clearly.

- **Graph-scoped migration state**:
  - `graphID` is optional across models; as long as legacy data exists, queries must keep the `|| nil` part.
  - Removing legacy paths prematurely can “hide” data (not deleted, just not fetched).

- **Import/Export correctness**:
  - Import code writes multiple model types and remaps IDs. Bugs can create dangling endpoints or duplicate graphs.
  - Good: there is an in-memory roundtrip test (`BrainMeshTests/GraphTransferRoundtripTests.swift`).

- **Attachment storage pressure**:
  - External storage reduces CloudKit record size risk, but large attachments still impact iCloud quota + sync times.
  - UI should avoid ever reading `fileData` on main.

## Observability / Debuggability
- Logging categories + timer helper: `BrainMesh/Observability/BMObservability.swift` (`BMLog.load`, `BMLog.expand`, `BMLog.physics`).
- Physics tick logging: `GraphCanvasView+Physics.swift` logs rolling windows (avg/max ms) every 60 ticks.
- Recommended additions:
  - Log loader timings in `EntitiesHomeLoader` and `GraphStatsLoader` (start/end + counts).
  - Log CloudKit mode changes (cloudKit vs localOnly) once per session to correlate user-reported “no sync”.

## Open Questions (UNKNOWN)
- Release signing entitlements: does distribution build set `aps-environment` to `production`? (`BrainMesh/BrainMesh.entitlements` currently has `development`).
- StoreKit product IDs: are "01"/"02" placeholders or final product IDs? (`BrainMesh/Info.plist`, `BrainMesh/Pro/ProEntitlementStore.swift`).
- CloudKit schema lifecycle: is CloudKit already deployed to production, and are there known migration constraints? **UNKNOWN** (no explicit migration plan found).
- Are there any background refresh / BGTaskScheduler jobs planned beyond CloudKit push? **UNKNOWN** (no BGTaskScheduler usage found).

## First 3 Refactors I would do (P0)

### P0.1 — GraphCanvas: Expand off-main + stale-guard
- **Goal:** Prevent UI stalls when expanding dense nodes by moving SwiftData fetches off MainActor.
- **Files:**
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Expand.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift` (+new Delta API file)
- **Risk:** medium (touches a user-facing hot path; must keep behavior identical).
- **Expected benefit:** less scroll/jank during expand; cleaner concurrency semantics (token/cancellation).

### P0.2 — GraphTransferViewModel: mechanical split
- **Goal:** Reduce coupling/merge conflicts and make import/export flows auditable and testable.
- **Files:** `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` (+3–4 new extension files).
- **Risk:** low (move-only if you keep access levels in mind).
- **Expected benefit:** faster iteration on import/export UX + fewer accidental regressions.

### P0.3 — NodeImagesManageView: extract row + thumbnail lifecycle
- **Goal:** Make thumbnail work/cancellation explicit and keep the screen body small.
- **Files:** `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` (split into screen + row + actions).
- **Risk:** low (pure UI refactor if move-only).
- **Expected benefit:** less SwiftUI invalidation churn, easier to add future gallery features without growing a new god-file.
