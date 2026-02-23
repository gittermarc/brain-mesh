# ARCHITECTURE_NOTES

Last updated: 2026-02-23

Scope note: This document is derived from the uploaded repo snapshot. Anything not directly evidenced in code is marked as **UNKNOWN** and tracked in *Open Questions*.

## Repo-scale quick facts
- Swift files: 261
- Total Swift LOC (raw line count): 34868
- Deployment target: iOS 26.0 (`BrainMesh.xcodeproj/project.pbxproj`)
- Persistence: SwiftData + CloudKit `.automatic` (private DB) (BrainMesh/BrainMeshApp.swift)
- Only file importing `CloudKit`: BrainMesh/Settings/SyncRuntime.swift

## Big files list (Top 15 by line count)
| Lines | File | Purpose | Why risky |
|---:|---|---|---|
| 630 | `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` | Entity → Attributes snapshot model (row building + caching + sort/filter) | Large stateful list model; correctness/perf regressions affect core navigation |
| 532 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | Canvas drawing (edges/nodes/labels/notes + per-frame caches) | Hot path: per-frame loops + dict rebuilds; scales with maxLinks |
| 504 | `BrainMesh/Onboarding/OnboardingSheetView.swift` | Onboarding host sheet (routing + pickers + progress) | Complex routing state; sheet stacking regressions |
| 491 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | Shared detail UI building blocks (hero/pills/sections) | Shared across entity+attribute; high blast radius |
| 411 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | Off-main graph snapshot loading (SwiftData fetch + BFS neighborhood) | Perf-sensitive: BFS + multi-fetch; detached tasks; snapshot sendability |
| 410 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | Node gallery management list (paging, thumb, delete) | Can become scroll hot path (thumbs + cache misses) |
| 401 | `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` | Attribute detail host view (queries + sheets + layout) | Multiple queries/sheets; easy to add fetch-in-render regressions |
| 394 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | Shared connections UI + routing (incoming/outgoing segments) | Shared routing; correctness bugs show everywhere |
| 388 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` | Entities tab host view (search, debounce, layout switching) | Task-trigger storms and invalidation risk |
| 388 | `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` | Details values rendering (custom fields) | Large per-field render; can become expensive with many fields |
| 381 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` | Off-main entities snapshot loader (search + counts caches) | Can scan entire graph for counts; cancellation correctness |
| 362 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | Shared media gallery UI (grid/tiles/viewer routing) | Thumbnail/materialization coordination risk |
| 357 | `BrainMesh/Icons/AllSFSymbolsPickerView.swift` | SF Symbols picker (search/index + grid) | Memory + paging risk (large datasets) |
| 356 | `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` | Graph tab host view (state machine, sheets, reload triggers) | Many state vars and triggers; reload storms |
| 346 | `BrainMesh/Mainscreen/BulkLinkView.swift` | Bulk link creation (multi-select + duplicate handling) | Correctness (duplicates/bidirectional links) |

## Hot path analysis

### Rendering / scrolling

#### Graph canvas rendering (Canvas draw loop)
- File: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- Concrete reasons:
  - `renderCanvas(...)` loops over `drawEdges` and `nodes` on every redraw.
  - `buildFrameCache(...)` rebuilds dictionaries (`screenPoints`, `labelOffsets`) and reconstructs `keyByIdentifier` every frame.
  - Notes rendering can scan `directedEdgeNotes` via `prepareOutgoingNotes(...)` when `alphas.showNotes` and `selection != nil`.
- Risk patterns:
  - **Per-frame dictionary rebuild** → allocations + hashing on the render thread.
  - **Edge loop scales with maxLinks** (default `maxLinks = 800` in `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`).

#### Graph canvas physics (30 FPS timer + O(n²) repulsion)
- File: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- Concrete reasons:
  - Timer: `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` drives `stepSimulation()`.
  - `stepSimulation()` performs a pair loop over nodes for repulsion/collision: O(n²).
  - `positions = pos` / `velocities = vel` updates every tick → frequent SwiftUI invalidations.
- Existing mitigations (evidence in code):
  - Spotlight physics: simulate only `physicsRelevant` when selection is active.
  - Sleep: stops timer after ~3 seconds of low motion (idle tick counter logic).

#### Graph canvas data loading
- Files: `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- Concrete reasons:
  - Loader uses detached `ModelContext` and BFS neighborhood mode.
  - Predicates include `frontierIDs.contains(...)` and `visibleIDs.contains(...)` (captured arrays inside `#Predicate`).
  - `GraphCanvasScreen.loadGraph(...)` commits snapshot state “in one go” to avoid partial state overrides.
- Risk patterns:
  - **Large captured arrays in predicates** → can degrade fetch performance for large neighborhoods.
  - **Multiple fetch passes per hop** in neighborhood mode.

#### EntitiesHome search + counts
- Files: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`, `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Concrete reasons:
  - View triggers `.task(id: taskToken)` with debounce (250ms).
  - Loader may compute counts by fetching *all* `MetaAttribute` and/or *all* `MetaLink` for a graph on cache miss (`computeAttributeCounts`, `computeLinkCounts`).
  - Counts cache TTL is short (`countsCacheTTLSeconds = 8`).
- Risk patterns:
  - **Full table scans** on cache miss.
  - **Cancellation correctness** is required to avoid UI flicker/stale state.

### Sync / storage

#### SwiftData container init + fallback
- File: `BrainMesh/BrainMeshApp.swift`
- Evidence:
  - Creates CloudKit-enabled container via `cloudKitDatabase: .automatic`.
  - Debug: CloudKit init failure → `fatalError`.
  - Release: fallback to local-only ModelConfiguration; updates `SyncRuntime.storageMode`.

#### Disk cache hydration
- Image hydration: `BrainMesh/ImageHydrator.swift`
  - Scans `MetaEntity` and `MetaAttribute` where `imageData != nil`.
  - Writes deterministic JPEG cache files; saves SwiftData only if `context.hasChanges`.
- Attachment hydration: `BrainMesh/Attachments/AttachmentHydrator.swift`
  - Called from UI cells; deduped per attachment id.
  - Fetches record by id in background `ModelContext`, writes bytes to Application Support.
- Risk patterns:
  - **Disk pressure** (local caches can grow).
  - **ExternalStorage blobs** (CloudKit sync payloads) — max sizes enforcement is **UNKNOWN**.

#### Legacy graphID migration
- File: `BrainMesh/GraphBootstrap.swift`
- Evidence:
  - Cheap existence checks use `fetchLimit = 1`.
  - Bulk backfill of `graphID` for entities/attributes/links, then `modelContext.save()`.
- Risk:
  - Runs from `AppRootView.bootstrapGraphing()` (BrainMesh/AppRootView.swift) on MainActor; could stall startup for huge legacy datasets.

### Concurrency

#### Actor loader pattern (general)
- Central configuration: `BrainMesh/Support/AppLoadersConfigurator.swift`
- Common structure across loaders:
  - Store `AnyModelContainer`
  - Create background `ModelContext` (`autosaveEnabled = false`)
  - `Task.detached(priority: .utility)` for fetch work
  - DTO snapshots returned to UI

#### Sharp edges
- `@unchecked Sendable` snapshots exist (e.g. `GraphCanvasSnapshot`, `GraphStatsSnapshot`):
  - Contract: value-only; must not include SwiftData models.
- Detached tasks must not capture SwiftData models or MainActor state:
  - Code usually copies primitive inputs before detaching, but this is easy to regress.

## Refactor map

### GraphCanvas: reduce per-frame allocations
- Target files:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- Concrete options:
  - Persist `keyByIdentifier` and rebuild only when node set changes.
  - Reuse buffers for `screenPoints`/`labelOffsets` (avoid new dictionaries each frame).
  - (Higher risk) replace O(n²) collision checks with spatial hashing / grid buckets.

### Details pinned values: add graph scoping
- Evidence: `EntityAttributesAllListModel+Lookups.fetchPinnedValuesLookup` fetches values by `fieldID` (no graph scope).
- Safer option:
  - Add `v.graphID == gid` filter when gid is known.
  - Optionally in-memory filter by attributeIDs of current entity.

### EntitiesHome counts: replace TTL with mutation-driven invalidation
- Evidence: TTL cache (8s) and full scans on cache miss.
- Option:
  - Invalidate cache on create/delete/update of entities/attributes/links.
  - Requires identifying mutation points (e.g. `AddEntityView`, `AddAttributeView`, `AddLinkView`, `BulkLinkView`).

### Big SwiftUI compile units
- Candidates:
  - `NodeDetailShared+Core.swift`
  - `EntitiesHomeView.swift`
  - `OnboardingSheetView.swift`
- Goal:
  - Reduce blast radius + compile churn by extracting subviews.

## Risks & edge cases
- Denormalized link labels must be updated on rename:
  - `NodeRenameService` in `BrainMesh/Mainscreen/LinkCleanup.swift` is the only evidenced mechanism.
- Debug vs Release diverges for CloudKit init failure:
  - fatal vs fallback (`BrainMesh/BrainMeshApp.swift`).
- Attachment size/quota policy is **UNKNOWN**:
  - No explicit enforcement found in attachment import/hydration paths.
- Graph lock state is in-memory:
  - `GraphLockCoordinator.unlockedGraphIDs` is not persisted; background lock clears it (`AppRootView` schedules `graphLock.lockAll()`).

## Observability / Debuggability
- Central helpers:
  - `BMLog` categories + `BMDuration` in `BrainMesh/Observability/BMObservability.swift`
- Graph load logs:
  - `BMLog.load` in `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift`
- Physics logs:
  - `BMLog.physics` in `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`

## Open questions (UNKNOWN)
1. CloudKit conflict behavior and merge policy beyond SwiftData defaults?
2. Versioned schema migration strategy vs automatic migration only?
3. Attachment size limits or compression policy?
4. Collaboration/sharing roadmap (no CKShare evidence today)?
5. Scale targets (max nodes/links/attachments) to guide algorithm choices?
6. Cache pruning strategy (manual vs automatic)?
7. Node-level locking roadmap (lock fields exist on Entity/Attribute but not enforced today)?

## First 3 refactors I would do (P0)

### P0.1 — Scope pinned detail value fetches by graph
- **Ziel:** DB-Arbeit reduzieren beim Bauen/Sortieren der pinned Chips.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel+Lookups.swift`
  - `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift`
- **Risiko:** niedrig
- **Erwarteter Nutzen:** schnellere Attribute-Listen bei pinned Feldern; bessere Multi-Graph-Skalierung

### P0.2 — Stabilize GraphCanvas per-frame caches
- **Ziel:** weniger per-frame Allocations/Hashing im Canvas rendern.
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - optional: `BrainMesh/GraphCanvas/GraphCanvasView.swift`
- **Risiko:** mittel
- **Erwarteter Nutzen:** weniger dropped frames beim Pan/Zoom und bei hohen Link-Zahlen

### P0.3 — Replace TTL-based counts caching
- **Ziel:** Such-Tippen unabhängig von der Gesamtgröße des Graphen machen.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - Mutation-Punkte: `AddEntityView`, `AddAttributeView`, `AddLinkView`, `BulkLinkView`
- **Risiko:** mittel
- **Erwarteter Nutzen:** weniger Full-Scans; stabilere UI beim Tippen