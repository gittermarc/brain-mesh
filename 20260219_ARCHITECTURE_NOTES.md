# ARCHITECTURE_NOTES

> Generated from repository scan on 2026-02-19. Paths are relative to the repo root (e.g. `BrainMesh/...`).

## 0) Executive technical summary
- The codebase is already leaning into a **good performance pattern**: heavy SwiftData work is mostly pushed into **actor loaders** running with a **background `ModelContext`** and returning **value-only snapshots** to SwiftUI (e.g. `EntitiesHomeLoader`, `GraphStatsLoader`, `GraphCanvasDataLoader`).
- The highest remaining risk is concentrated in a few hotspots:
  - **GraphCanvas physics**: 30 FPS timer + O(n²) pair loops + dictionary copying each tick can dominate CPU and trigger broad SwiftUI invalidation (`BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`).
  - **UIKit bridging**: Markdown editor is a large, complex wrapper (`BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift`) and tends to be fragile around keyboard/accessory/undo.
  - **External storage & predicates**: anything that accidentally triggers in-memory filtering on `MetaAttachment.fileData` can become catastrophic. You already mitigated this with migration helpers (`BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).

## 1) Big Files List (Top 15 by lines)

| # | File | Lines | What it is | Why it’s risky |
|---:|---|---:|---|---|
| 1 | `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift` | 629 | UIKit-backed Markdown editor (UITextView wrapper + toolbar/preview/link helpers). | High fragility + compile ripple; UIKit/SwiftUI boundary bugs (keyboard, accessory, undo) tend to hide here. |
| 2 | `BrainMesh/Mainscreen/EntitiesHomeView.swift` | 625 | Entities home screen (list/grid/search + graph picker + add flow + loader orchestration). | Large view = high compile impact; easy to accidentally introduce fetches/computation into render path. |
| 3 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | 532 | GraphCanvas drawing (Canvas rendering, edge/node drawing, thumbnail tile). | Render-path sensitive; any synchronous work or per-frame allocations show up as jank/battery drain. |
| 4 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | 478 | Shared detail UI building blocks (hero card, async preview image, stat pills, anchors). | High fan-out (used everywhere) → small changes recompile lots; image loading mistakes affect many screens. |
| 5 | `BrainMesh/Settings/Appearance/AppearanceModels.swift` | 430 | Codable appearance models (colors, presets, typography, layout knobs). | Big model file causes compile churn; high coupling if UI reads deep settings paths everywhere. |
| 6 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | 411 | Off-main loader assembling nodes/edges snapshots for canvas, including neighborhood/focus logic. | Complex predicates + filtering; risk of in-memory filtering (contains/set membership) and large intermediate arrays. |
| 7 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 408 | Image management sheet (Photos picker, set main image, delete, etc.). | System pickers + large media; risk of blocking main, and interactions with graph lock/system modal state. |
| 8 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | 394 | Connections section UI + load logic for links and neighbor nodes. | Renames must keep link labels in sync; link queries can scale poorly if not scoped tightly. |
| 9 | `BrainMesh/Mainscreen/EntitiesHomeLoader.swift` | 362 | Actor loader computing entities list snapshot (+ optional link counts). | Hot-path for app’s main list; any regression affects perceived speed immediately. |
| 10 | `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` | 361 | Reusable stats card components. | UI utility file; risk is mostly compile-time (lots of call sites). |
| 11 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 360 | Media section UI (gallery thumbs, attachments, manage buttons). | Media-heavy UI; thumbnail generation + hydration sequencing can cause stutter if not isolated. |
| 12 | `BrainMesh/Icons/AllSFSymbolsPickerView.swift` | 357 | Full SF Symbols picker UI (the “show me everything” list). | Potential memory/UI cost if not lazily loaded; also a large file that can drag compile times. |
| 13 | `BrainMesh/Mainscreen/BulkLinkView.swift` | 346 | Bulk link creation UI/logic. | Can create many `MetaLink` records quickly; needs careful batching + graph scoping. |
| 14 | `BrainMesh/PhotoGallery/PhotoGallerySection.swift` | 342 | Gallery presentation components (tiles/sections). | If thumbnails are generated synchronously or too often, scrolling can hitch. |
| 15 | `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` | 325 | Canvas host screen + state + inspector wiring. | Many `@State` vars; easy to cause over-invalidation or state explosions. |

## 2) Hot Path analysis

### 2.1 Rendering & scrolling

#### GraphCanvas
- **Physics loop @ 30 FPS** via `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` (`BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`).
  - Hotspot reason: `stepSimulation()` is O(n²) for repulsion/collisions (pair loop) and operates on `Dictionary` copies (`var pos = positions`, `var vel = velocities`) every tick → allocation pressure + SwiftUI invalidation.
  - Mitigation already present: `physicsRelevant` “spotlight physics” reduces simulated nodes; also idle/sleep logic exists (`physicsIsSleeping`, `physicsIdleTicks`).
- **Canvas render path** uses `Canvas` (see `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`).
  - Hotspot reason: anything that changes `positions`/`velocities` invalidates the whole drawing; keep per-frame computations minimal and avoid disk I/O.
- **Thumbnail load** for selection uses background queue + cached thumbnail (`BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`).
  - Watch for: repeated thumbnail generation when selection changes quickly; ensure cache keying is stable (`cachedThumbPath`).

#### Entities Home list/grid
- UI is driven by **state snapshots** (`rows: [EntitiesHomeRow]`) loaded by `EntitiesHomeLoader.shared.loadSnapshot(...)` (`BrainMesh/Mainscreen/EntitiesHomeView.swift`).
- Hotspot reasons to watch:
  - Frequent search updates: `.task(id: taskToken)` cancels prior tasks (good), but still creates a lot of tasks while typing (debounce is implemented via `Task.sleep`).
  - Grid/list rows likely load images async; ensure image decode stays off-main (pattern exists via `NodeAsyncPreviewImageView` in `NodeDetailShared+Core.swift`).

#### Node detail screens (Entity/Attribute)
- Shared hero + image preview: `NodeHeroCard` and `NodeAsyncPreviewImageView` (`BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`).
  - Hotspot reason: if preview image resolution/decoding happens on main, it can block scrolling. Current pattern uses async resolution into `resolvedImage` state (verify call-sites remain async).
- Markdown editor: `MarkdownTextView` (`BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift`).
  - Hotspot reason: UIKit text view updates can be chatty; if you push too many SwiftUI state updates per keystroke, you’ll see dropped frames.
- Media section: gallery thumbs + attachments list (`BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`).
  - Hotspot reason: thumbnail generation and attachment preview file access; keep limited to visible tiles and use local cache (see `AttachmentStore`).

### 2.2 Sync / storage
- Container: `ModelContainer` with `cloudKitDatabase: .automatic` (`BrainMesh/BrainMeshApp.swift`).
  - **UNKNOWN:** whether the app uses only the private database or also shared/public DB via SwiftData’s automatic mapping (the code uses `.automatic`; verify in runtime/CloudKit dashboard).
- Push background mode: `remote-notification` (`BrainMesh/Info.plist`).
  - Implication: CloudKit pushes can wake the app; ensure hydration/cleanup work is bounded and not triggered excessively on background wakes.
- Attachments:
  - `MetaAttachment.fileData` is `@Attribute(.externalStorage)` (`BrainMesh/Attachments/MetaAttachment.swift`).
  - Primary risk: any query that forces **in-memory filtering** may pull large blobs from disk/iCloud. The code explicitly warns against OR predicates and optional tricks, and adds migration helpers (`BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).
- Images:
  - Images are stored as small JPEG `Data` (`imageData`) + optional disk cache path (`imagePath`) on entities/attributes (`BrainMesh/Models.swift`).
  - Disk cache is maintained in `ImageStore` (`BrainMesh/ImageStore.swift`) and hydrated in background (`BrainMesh/ImageHydrator.swift`).
- Bootstrap/migration:
  - `GraphBootstrap.swift` ensures graphs exist and runs legacy migrations. If this runs on main at launch, it can affect time-to-interactive (inspect call-site in `AppRootView` / `BrainMeshApp`).

### 2.3 Concurrency
- Preferred pattern used widely: **actor loader** + `Task.detached(.utility)` + background `ModelContext` + value snapshot DTOs.
  - Examples: `EntitiesHomeLoader` (`BrainMesh/Mainscreen/EntitiesHomeLoader.swift`), `GraphStatsLoader` (`BrainMesh/Stats/GraphStatsLoader.swift`), `GraphCanvasDataLoader` (`BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`), `MediaAllLoader` (`BrainMesh/Attachments/MediaAllLoader.swift`).
- Dedupe/in-flight tracking:
  - `NodeRenameService` keeps `inFlight` tasks keyed by node id (`BrainMesh/Mainscreen/LinkCleanup.swift`).
  - Risk: task dictionaries must be cleaned on completion; otherwise, memory grows. (The pattern likely removes tasks; verify in code during refactor.)
- Sendability:
  - Some snapshot structs are `@unchecked Sendable` (e.g. `GraphStatsSnapshot` in `BrainMesh/Stats/GraphStatsLoader.swift`).
  - Risk: accidental non-thread-safe members in snapshots. Keep DTOs value-only (String/Int/UUID/Date) and avoid UIKit/CoreGraphics types unless carefully isolated.

## 3) Refactor map (concrete, file-level)

### 3.1 Split candidates (high leverage)
1. **`BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift`** (629 lines)
   - Split suggestion (extensions or separate types):
     - `MarkdownTextView.swift` (public SwiftUI wrapper + bindings)
     - `MarkdownTextView+UIKit.swift` (UITextViewRepresentable + Coordinator)
     - `MarkdownTextView+AccessoryBar.swift` (toolbar, undo/redo, formatting actions)
     - `MarkdownTextView+LinkPrompt.swift` (nicer link UI prompt)
     - `MarkdownTextView+Preview.swift` (syntax-clean preview formatter)
   - Why: isolates UIKit complexity, reduces compile ripple, enables targeted testing of editor behavior.

2. **`BrainMesh/Mainscreen/EntitiesHomeView.swift`** (625 lines)
   - Split suggestion:
     - `EntitiesHomeView.swift` (host, state, `.task` orchestration)
     - `EntitiesHomeView+Toolbar.swift`
     - `EntitiesHomeView+EmptyStates.swift`
     - `EntitiesHomeView+List.swift` / `EntitiesHomeView+Grid.swift`
     - `EntitiesHomeView+Routing.swift` (Route views like `EntityDetailRouteView`)

3. **`BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`** (532 lines)
   - Split suggestion:
     - `GraphCanvasRendering+Edges.swift`
     - `GraphCanvasRendering+Nodes.swift`
     - `GraphCanvasRendering+Labels.swift`
     - `GraphCanvasRendering+SelectionOverlay.swift` (thumbnail bubble, notes)

4. **`BrainMesh/Mainscreen/LinkCleanup.swift`** (contains both cleanup + `NodeRenameService` actor)
   - Split suggestion:
     - `LinkCleanup.swift` (pure functions)
     - `NodeRenameService.swift` (actor + background context)

### 3.2 Storage/query safety refactors
- Create a small set of **query builders** to enforce graph scoping and avoid optional/OR pitfalls:
  - `FetchDescriptors+GraphScope.swift` (helpers for MetaEntity/MetaAttribute/MetaLink/MetaAttachment)
  - Adopt in: `GraphCanvasDataLoader.swift`, `GraphStatsService/*.swift`, `MediaAllLoader.swift`, `LinkCleanup.swift`.
- Centralize migration triggers so the app reaches a "no legacy graphID" steady state faster:
  - Active graph: migrate attachments with `graphID == nil` early (`AttachmentGraphIDMigration`), so list views never need fallback predicates.

### 3.3 Performance refactors (GraphCanvas-first)
- Reduce per-tick SwiftUI invalidation:
  - Move physics state (`positions`, `velocities`) into a reference type (`@StateObject` engine) and expose read-only snapshots to Canvas.
  - Batch updates (e.g. publish only every 2–3 ticks while dragging is idle) and keep the Canvas drawing using the engine’s internal state.
- Algorithmic: introduce a spatial grid for collision/repulsion to avoid full O(n²) at higher node counts.

## 4) Cache / index ideas
- **Adjacency cache for links**: keep a per-graph adjacency map `{NodeKey: [NeighborKey]}` built off-main when graph changes; this makes neighborhood/focus queries faster and avoids predicate gymnastics with set membership. Touchpoints: `GraphCanvasDataLoader.swift`, `NodeConnectionsLoader.swift`.
- **Denormalized counts** (optional): store link count per node in a small SwiftData table or compute & cache in `EntitiesHomeLoader` with TTL. (You already have a link-count option; this would make sort-by-link-count cheaper.)
- **Cache invalidation rules**:
  - Current approach: loaders expose `invalidateCache(for:)` (e.g. `EntitiesHomeLoader`). Standardize a single invalidation event bus (optional).

## 5) Risks & edge cases
- **Data duplication**: stats view dedupes graphs by `UUID` (`GraphStatsView.uniqueGraphs`). This suggests duplicates can exist in store; root cause should be understood to avoid repeated cleanup work.
- **Rename consistency**: `MetaLink` stores `sourceLabel/targetLabel`; any rename path must trigger relabeling (`NodeRenameService` in `LinkCleanup.swift`). Missing this yields stale UI.
- **Lock + system pickers**: transient `.background` during FaceID inside pickers can break flows; mitigated via `SystemModalCoordinator` (`BrainMesh/Support/SystemModalCoordinator.swift`). Ensure all picker presentations call `beginSystemModal/endSystemModal` consistently. **UNKNOWN** whether every picker flow is wrapped today.
- **ExternalStorage blobs**: accidental in-memory filtering will force-load large `fileData`. Keep the strict AND predicate rule; avoid `Set.contains` inside SwiftData predicates for attachments where possible.
- **CloudKit schema evolution**: SwiftData migrations are mostly automatic, but large changes to `@Model` fields can still break sync. **UNKNOWN** whether schema versioning/testing against an existing iCloud container is part of the workflow.

## 6) Observability / debuggability
- Logging: `BMObservability.swift` provides `BMLog`/`BMDuration` helpers (os.Logger).
- Recommendation: add **signposts** around:
  - Canvas load + expand (`GraphCanvasDataLoader.load...`).
  - Entities home snapshot load (`EntitiesHomeLoader.loadSnapshot`).
  - Stats snapshot load (`GraphStatsLoader.loadSnapshot`).
  - Hydration loops (`AttachmentHydrator`, `ImageHydrator`).
- Repro harness ideas:
  - Add a debug-only "Generate 200 nodes / 1000 links" action to test GraphCanvas scaling.
  - Add a debug-only "Attach 200 images" action (using bundled fixtures) to stress media.

## 7) Open Questions (UNKNOWN)
1. **UNKNOWN:** Verify which CloudKit database(s) SwiftData uses at runtime with `cloudKitDatabase: .automatic` (private vs shared/public) and document the result.
2. **UNKNOWN:** Confirm that every system picker presentation increments/decrements `SystemModalCoordinator` (not all call-sites were audited in this scan).
3. **UNKNOWN:** Define/verify a workflow for testing SwiftData + CloudKit schema evolution against an existing CloudKit container.

## 8) First 3 Refactors I would do (P0)

### P0.1 — Markdown editor split + UX polish
- **Ziel:** Editor stabiler machen (UIKit/SwiftUI boundary isolieren), Compile-Zeit senken, und Features wie Undo/Redo + nicer Link-Prompt + clean preview leichter umsetzen.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift` → split in 4–5 Dateien (siehe Refactor Map 3.1).
- **Risiko:** Mittel (UIKit-Interop kann regressionsanfällig sein, aber rein strukturell möglich).
- **Erwarteter Nutzen:** Hoch (größter Single-File-Hotspot; schnellere Iteration an Notes/Editor-UX, weniger fragile keyboard/accessory Bugs).

### P0.2 — GraphCanvas physics/state isolation
- **Ziel:** CPU/Battery reduzieren und Canvas flüssiger machen bei 100+ Nodes, indem per-tick State-Updates und O(n²) Work besser kontrolliert werden.
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- **Risiko:** Mittel–hoch (Timing/gestures/selection sind empfindlich).
- **Erwarteter Nutzen:** Sehr hoch (das ist dein deutlichster Laufzeit-Hotspot; wirkt sofort auf „Premium“-Feeling).

### P0.3 — Query builder + legacy graphID steady state
- **Ziel:** Performance-Fußangeln eliminieren: keine OR/optional-Tricks in SwiftData-Predicates, keine accidental in-memory filtering bei attachments; weniger duplicated query logic.
- **Betroffene Dateien:**
  - Neu: `BrainMesh/Storage/FetchDescriptors+GraphScope.swift` (oder ähnlich) **(neuer Ordner optional)**
  - Update: `BrainMesh/Attachments/MediaAllLoader.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/Stats/GraphStatsService/*`, `BrainMesh/Mainscreen/LinkCleanup.swift`.
  - Update/Migration: `BrainMesh/GraphBootstrap.swift`, `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.
- **Risiko:** Niedrig–mittel (hauptsächlich Refactor; Verhalten sollte gleich bleiben).
- **Erwarteter Nutzen:** Hoch (stabilere Performance + weniger "mystery slowdowns" auf Geräten mit vielen Medien).