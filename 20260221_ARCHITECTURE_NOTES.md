# ARCHITECTURE_NOTES

_Last updated: 2026-02-21_  
_Project: BrainMesh (iOS app)_

This document is intentionally “engineering notes”: tradeoffs, risks, hot paths, and concrete refactor options with file-level anchors.

---

## Repository / Codebase shape (quick stats)
- Swift files: **226**
- Highest Swift file density by folder (count of `.swift` files under BrainMesh/):
  - `BrainMesh/Mainscreen/` → 81 files
  - `BrainMesh/Settings/` → 36 files
  - `BrainMesh/Attachments/` → 20 files
  - `BrainMesh/Stats/` → 19 files
  - `BrainMesh/GraphCanvas/` → 17 files
  - `BrainMesh/PhotoGallery/` → 9 files
  - `BrainMesh/Onboarding/` → 9 files
  - `BrainMesh/Security/` → 6 files
  - `BrainMesh/Icons/` → 6 files
  - `BrainMesh/GraphPicker/` → 6 files

---

## Big Files List (Top 15 by line count)

| Lines | File | Primary role | Why risky |
|---:|---|---|---|
| 698 | `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` | Entity detail: All-Attributes snapshot + filtering/sorting (pinned details) | Runs on @MainActor; rebuild does SwiftData fetchCount and potentially broad value fetches per pinned field during typing. High chance of UI hitching regressions. |
| 532 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | Graph canvas rendering (Canvas draw of nodes/edges, labels, notes) | Per-frame draw loops; small changes can multiply work. Hard to test visually; performance regressions show as FPS drops/battery. |
| 515 | `BrainMesh/Models.swift` | SwiftData model definitions + search helpers | Schema changes affect persistence + CloudKit. Also high churn file causing compile and merge friction. |
| 504 | `BrainMesh/Onboarding/OnboardingSheetView.swift` | Onboarding flow UI (multi-step + 'Turbo: Details') | Large single file with many navigation/picker states; easy to introduce sheet/routing bugs and increases compile churn. |
| 491 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | Shared detail-screen building blocks (Entity + Attribute) | High fan-out: used by multiple detail screens; small change can ripple widely and increase incremental compile time. |
| 469 | `BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaFieldsList.swift` | Details schema builder: editable list of custom fields | Complex editing/move/delete state; risk of subtle UI state bugs and validation edge cases. |
| 411 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | Off-main SwiftData loader for canvas (global + neighborhood BFS) | Scaling-sensitive (nodes/links caps, BFS hops). Must maintain cancellation and avoid passing @Model across concurrency boundaries. |
| 410 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | Gallery management UI for node images (Entity/Attribute) | Image grids and hydration can be memory/I/O heavy; regressions show as scroll jank and spikes. |
| 397 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` | Off-main loader for Entities tab (search + counts) | Counts paths scan all attributes/links; can become O(N) per refresh. Small UX toggles can inadvertently enable expensive work. |
| 394 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | Connections UI + routing (links between nodes) | Touches navigation and link creation flows; high correctness risk (wrong IDs, wrong kind) and shared usage. |
| 388 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` | Entities tab host view (NavigationStack + search + sheets) | Multiple sheet states and reload triggers; risk of duplicate loads, state races, and subtle UI regressions. |
| 388 | `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` | Details values UI (render/edit typed field values) | Many field types and formatting rules; easy to regress type handling and validation. |
| 386 | `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` | Attribute detail host view (state + media + counts) | Complex sheet orchestration and shared components; changes often touch multiple sections. |
| 362 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | Media gallery UI shared by detail screens | Image-heavy UI with adaptive grids; performance sensitive (thumbnailing, layout) and often a source of scroll jank. |
| 361 | `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` | Reusable Stats UI card components | Low runtime risk; but large shared UI component file can create compile churn and inconsistent styling if edited ad-hoc. |

---

## Hot Path analysis

### 1) Rendering / Scrolling
#### Graph canvas render loop
Files:
- BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift
- BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift
- BrainMesh/GraphCanvas/GraphCanvasScreen.swift

Observed hot-path reasons:
- Canvas draws edges and nodes in tight loops every render pass (`for e in drawEdges`, `for n in nodes`) in `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`.
- Physics updates mutate large `@State` dictionaries (`positions`, `velocities`) in `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`, which triggers frequent view invalidation.
- The code already mitigates this with cached derived state (`drawEdgesCache`, `lensCache`, `physicsRelevantCache`) and a per-frame screen cache (`FrameCache`).

Watch points:
- Any additional per-node/per-edge text layout or geometry work inside `renderCanvas(...)`.
- Any new per-tick work inside `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`.

#### Entities Home search/list
Files:
- BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift
- BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift
- BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeList.swift
- BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeGrid.swift

Observed hot-path reasons:
- Typing into `.searchable` triggers a debounced `.task(id: taskToken)` in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`.
- Loader work can still be expensive on large datasets:
  - Fetches entities by `nameFolded.contains(term)` and attributes by `searchLabelFolded.contains(term)`, then resolves owners (see `fetchEntities(...)` in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`).
  - Optional counts scan all attributes or links for the graph (`computeAttributeCounts(...)` / `computeLinkCounts(...)`).
  - TTL cache exists (`countsCacheTTLSeconds = 8`) but counts remain a latency/battery multiplier.

Watch points:
- Changes that compute counts more often or by default.
- Changes that widen the task token (causing more reload triggers).

#### Entity detail: “All Attributes” list
Files:
- BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift

Observed hot-path reasons:
- `EntityAttributesAllListModel` is `@MainActor` and rebuilds rows while typing (`scheduleRebuild` → 150ms debounce → rebuild).
- During rebuild it performs SwiftData work on the main actor:
  - per pinned field: `fetchCount` on `MetaDetailFieldValue`
  - pinned values refetch: `fetchPinnedValuesLookup(...)` queries by `fieldID` only (potentially broad)
  - grouping by media may run attachment checks/fetches (same file)

Watch points:
- The pinned-field loop + `fetchPinnedValuesLookup(...)` query shape.

#### Attachments: list + thumbnailing + cache hydration
Files:
- BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift
- BrainMesh/Attachments/AttachmentThumbnailStore.swift
- BrainMesh/Attachments/AttachmentHydrator.swift

Observed hot-path reasons:
- List paging (`pageSize = 40`) and per-row previews.
- Thumbnail generation involves AVFoundation and is throttled with `AsyncLimiter`.
- Cache hydration is off-main and throttled (`AsyncLimiter(maxConcurrent: 2)`), but can still contend on disk I/O.

---

### 2) Sync / Storage
#### ModelContainer initialization and storage modes
Files:
- BrainMesh/BrainMeshApp.swift
- BrainMesh/Settings/SyncRuntime.swift
- BrainMesh/BrainMesh.entitlements

Observed facts:
- CloudKit-backed SwiftData store is created via `.automatic` database in `BrainMesh/BrainMeshApp.swift`.
- DEBUG crashes on CloudKit init failure; Release falls back to local-only.
- `SyncRuntime` surfaces container id and iCloud account status.

Watch points:
- Any schema list changes in `BrainMesh/BrainMeshApp.swift` (CloudKit + migration risk).
- Any new large `Data` properties not using `.externalStorage`.

#### Binary data pressure
Files:
- BrainMesh/Models.swift (`imageData` on entity/attribute)
- BrainMesh/Attachments/MetaAttachment.swift (`fileData` uses `.externalStorage`)
- BrainMesh/Images/ImageImportPipeline.swift
- BrainMesh/Attachments/AttachmentImportPipeline.swift

Observed facts:
- Attachment bytes are stored with `.externalStorage`.
- Entity/attribute images are plain `Data?` (comments say to keep them small).

Risk:
- Import pipeline changes that increase `imageData` size can increase sync and storage pressure.

---

### 3) Concurrency
Patterns used:
- Actor loaders configured once with `AnyModelContainer` and creating background `ModelContext` instances inside detached tasks.
- Cancellation tokens in UI hosts to avoid overlapping loads.

Watch points:
- `@unchecked Sendable` usage: keep the invariant that SwiftData models/contexts do not cross actor boundaries.
- Any new long loops should add cancellation checks like `Task.checkCancellation()`.

---

## Refactor Map (concrete options)

### A) File splits (maintainability, minimal behavior change)
1. Split BrainMesh/Models.swift into per-type files.
2. Split BrainMesh/Onboarding/OnboardingSheetView.swift into sections.
3. Further split high fan-out NodeDetailShared files (Core / Connections / Media).

### B) Performance levers
1. Make pinned-values lookup entity-scoped in BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift.
2. Revisit when counts are computed in BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift (avoid O(N) scans on common paths).
3. Prefer incremental rebuild on type-ahead lists: when only search changes, avoid SwiftData fetch.

### C) Unifications
1. Standardize “active graph context” helper across screens (EntitiesHome, GraphCanvas, Stats, Onboarding).
2. Extract loader/hydrator configuration from BrainMesh/BrainMeshApp.swift into a helper.

---

## Risks & Edge Cases
- Migration: beyond graphID repair in BrainMesh/GraphBootstrap.swift, there is no explicit migration layer in this snapshot (**UNKNOWN** if handled elsewhere).
- Multi-device conflicts: derived fields (`nameFolded`, `searchLabelFolded`, `imagePath`) rely on invariants; **UNKNOWN** if additional repair is needed under merge conflicts.
- Locking vs system pickers: lock debounce logic exists in BrainMesh/AppRootView.swift; changes here are high-risk UX-wise.
- Attachments: 25 MB limit (`maxBytes`) in BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift; keep user feedback reliable.

---

## Observability / Debuggability
- Exists: BrainMesh/Observability/BMObservability.swift (`BMLog`, `BMDuration`) and GraphCanvas load logs in BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift.
- High value additions:
  - EntitiesHome loader duration logs
  - EntityAttributesAllListModel rebuild duration + refetch decision logs

---

## Open Questions (UNKNOWN)
1. Privacy manifest: no `PrivacyInfo.xcprivacy` found in this repo snapshot. Is it handled elsewhere or still pending?
2. Secrets/config: no `.xcconfig` files found. Are there any environment-specific configs not checked in?
3. CloudKit migration strategy: beyond graphID repair, what is the plan/tooling for future SwiftData schema changes?
4. Sync troubleshooting depth: do you want more diagnostics than account status?
5. Dataset scale assumptions: what are the realistic upper bounds per graph?

---

## First 3 Refactors I would do (P0)

### P0.1 — Entity “All Attributes” rebuild: reduce main-actor fetches
- **Goal**: Keep typing/scrolling smooth by removing broad main-actor fetches.
- **Affected files**: BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift
- **Risk**: Medium
- **Expected benefit**: less UI hitching, lower memory churn, better responsiveness at scale.

### P0.2 — Split BrainMesh/Models.swift into per-model files
- **Goal**: Reduce incremental compile time and clarify ownership.
- **Affected files**: BrainMesh/Models.swift (+ file moves), BrainMesh/BrainMeshApp.swift (imports/paths only)
- **Risk**: Low
- **Expected benefit**: faster compiles, cleaner diffs, fewer merge conflicts.

### P0.3 — Centralize “active graph context” + loader configuration
- **Goal**: Reduce duplication across tabs and shrink `BrainMeshApp.swift`.
- **Affected files**:
  - BrainMesh/BrainMeshApp.swift
  - BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift
  - BrainMesh/GraphCanvas/GraphCanvasScreen.swift
  - BrainMesh/Stats/GraphStatsView/GraphStatsView.swift
  - BrainMesh/Onboarding/OnboardingSheetView.swift
- **Risk**: Low–Medium
- **Expected benefit**: less duplication, fewer subtle inconsistencies, smaller files.



## Repro checklists for performance regressions
Use these to validate refactors quickly (manual “bench tests”).

### GraphCanvas
- Create or load a graph that hits:
  - `maxNodes` near the default (140) and above
  - `maxLinks` near the default (800) and above
- Actions:
  - rapidly pan/zoom
  - select nodes repeatedly (spotlight mode)
  - open/close Inspector sheet
- Watch for:
  - FPS drops while panning
  - delayed tap selection
  - spikes when selection toggles (lens recompute)

### EntitiesHome
- Enable expensive display options:
  - attribute counts and/or link counts (Display settings)
  - sorting by counts (attributesMost/linksMost)
- Actions:
  - type quickly into search
  - backspace repeatedly
  - switch graphs quickly via GraphPicker
- Watch for:
  - UI hitching while typing
  - repeated reloads without visible need
  - warm-cache vs cold-cache differences (counts cache TTL)

### Entity detail: All Attributes
- Configure:
  - pin 1–3 detail fields
  - enable pinned details display
  - choose pinned-field sorting
- Actions:
  - type quickly in search
  - toggle grouping modes (especially “hasMedia”)
- Watch for:
  - main-thread stalls during typing
  - pinned chips missing or wrong after edits
  - incorrect sort order when values missing

---

## More concrete refactor cuts (file-level)
These are “cut lists” meant to be copy/paste-able into issues/PR descriptions.

### Cut 1: Models split
- Move types out of `BrainMesh/Models.swift` into:
  - `BrainMesh/Models/NodeKind.swift` (NodeKind)
  - `BrainMesh/Models/BMSearch.swift` (BMSearch)
  - `BrainMesh/Models/MetaGraph.swift`
  - `BrainMesh/Models/MetaEntity.swift`
  - `BrainMesh/Models/MetaAttribute.swift`
  - `BrainMesh/Models/MetaLink.swift`
  - `BrainMesh/Models/DetailFieldType.swift` (DetailFieldType enum)
  - `BrainMesh/Models/MetaDetailFieldDefinition.swift`
  - `BrainMesh/Models/MetaDetailFieldValue.swift`
- Keep public API identical (type names, stored property names) to avoid breaking SwiftData schema.
- Do not change the schema list in `BrainMesh/BrainMeshApp.swift` beyond updating imports if needed.

### Cut 2: Onboarding split
- `BrainMesh/Onboarding/OnboardingSheetView.swift` → host-only
- New files (examples):
  - `BrainMesh/Onboarding/OnboardingHeaderSection.swift`
  - `BrainMesh/Onboarding/OnboardingProgressCard.swift`
  - `BrainMesh/Onboarding/OnboardingStepsSection.swift`
  - `BrainMesh/Onboarding/OnboardingTurboDetailsSection.swift`
  - `BrainMesh/Onboarding/OnboardingExamplesSection.swift`
- Motivation: this file has many state variables and multiple picker routes; splitting reduces merge conflicts.

### Cut 3: NodeDetailShared “media + attachments” as a mini-module
- Group related files under `BrainMesh/Mainscreen/NodeDetailShared/Media/` (folder move only):
  - `NodeDetailShared+MediaGallery.swift`
  - `NodeDetailShared+MediaAttachments.swift`
  - `NodeDetailShared+Sheets.Attachments.swift`
  - `NodeAttachmentsManageView+Loading.swift`
  - `NodeAttachmentsManageView+Import.swift`
  - `NodeAttachmentsManageView+Actions.swift`

---

## Open Questions (repeated, to keep in-view)
1. Privacy manifest missing from repo snapshot: confirm if required and where it lives.
2. Configuration strategy: confirm whether secrets/config exist outside the repo.
3. CloudKit migration plan beyond graphID repair.
