# BrainMesh — ARCHITECTURE_NOTES

> Fokus dieser Notizen: **Sync/Storage/Model** → **Entry Points + Navigation** → **Wartbarkeit/Performance** → **Konventionen/Workflows**.  
> Alles, was nicht eindeutig aus dem Code/Repo ableitbar ist, ist als **UNKNOWN** markiert und unten gesammelt.

## Big Files List (Top 15 nach Zeilen)
- `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` — **653** LOC
- `GraphCanvas/GraphCanvasView+Rendering.swift` — **532** LOC
- `GraphCanvas/GraphCanvasScreen+Loading.swift` — **425** LOC
- `Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` — **359** LOC
- `GraphCanvas/GraphCanvasScreen.swift` — **348** LOC
- `Mainscreen/BulkLinkView.swift` — **325** LOC
- `PhotoGallery/PhotoGallerySection.swift` — **321** LOC
- `Onboarding/OnboardingSheetView.swift` — **319** LOC
- `Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` — **311** LOC
- `Mainscreen/EntitiesHomeView.swift` — **307** LOC
- `Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` — **305** LOC
- `PhotoGallery/PhotoGalleryBrowserView.swift` — **297** LOC
- `PhotoGallery/PhotoGalleryViewerView.swift` — **297** LOC
- `GraphStatsView.swift` — **282** LOC
- `Models.swift` — **277** LOC

Warum riskant (generisch):
- Große SwiftUI-Dateien erhöhen Compile-Time, erschweren Review und begünstigen “ein File hat alles”-Abhängigkeiten.
- Große Render/Load-Dateien sind oft Hot Paths (CPU/RAM), weil dort viel pro Frame oder pro Load passiert.

### Kurze Einordnung pro Big File
- `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` — Media UI (Preview + “Alle” Paging + Viewer/Preview Sheets) + Attachment/Gallery Handling.
- `GraphCanvas/GraphCanvasView+Rendering.swift` — pro-frame Rendering (Canvas/GraphicsContext) für Nodes/Edges/Labels/Notes.
- `GraphCanvas/GraphCanvasScreen+Loading.swift` — Graph Load Pipeline (SwiftData fetch + BFS + Caches).
- `Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` — Shared UI building blocks (Hero, Toolbelt, async image loader).
- `GraphCanvas/GraphCanvasScreen.swift` — Screen state + routing + toolbars/sheets für den Graphen.
- `Mainscreen/BulkLinkView.swift` — UI/Flow zum massenhaften Verlinken.
- `PhotoGallery/PhotoGallerySection.swift` — Media Section Komposition für Detail Views (Galerie UI, Import/Actions).
- `Onboarding/OnboardingSheetView.swift` — Onboarding Screen+Flow.
- `Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` — Connections Section (outgoing/incoming links, segments, actions).
- `Mainscreen/EntitiesHomeView.swift` — Entities List + Search/Fetch + Sheets.
- `Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` — Highlights/Jump Links/Counts.
- `PhotoGallery/PhotoGalleryBrowserView.swift` — Gallery Browser UI (Grid/Navigation).
- `PhotoGallery/PhotoGalleryViewerView.swift` — Fullscreen Viewer (Paging/Zoom).
- `GraphStatsView.swift` — Stats UI + Wiring zu `GraphStatsService`.
- `Models.swift` — SwiftData Models (Graph/Entity/Attribute/Link) + Search folding.

## Hot Path Analyse

### 1) Rendering / Scrolling

#### Graph Canvas Rendering (per frame)
- Dateien:
  - `GraphCanvas/GraphCanvasView+Rendering.swift`
  - `GraphCanvas/GraphCanvasView.swift`
- Gründe / Risiken:
  - **Per-frame loops über `drawEdges` und `nodes`** → CPU-bound bei vielen Nodes/Edges.
  - **Text drawing (Labels/Notes)** ist teuer (CoreText). In `GraphCanvasView+Rendering.swift` werden Labels/Notes abhängig vom Zoom (`zoomAlphas()`) und Selection gefiltert → gut, aber immer noch Hot Path.
  - **Frame caches** (`FrameCache`) bauen Dictionaries für screen points/label offsets pro Frame → reduziert Lookups im Render‑Loop, aber allokationssensitiv.
- Mitigations im Code (observed):
  - `FrameCache` + selektionsbasierte Note‑Filterung (`PreparedOutgoingNote`) (`GraphCanvas/GraphCanvasView+Rendering.swift`)
  - Zoom‑basierte Alpha Gates (`zoomAlphas()`) (`GraphCanvas/GraphCanvasView+Rendering.swift`)

#### Graph Physics Tick (O(n²) im worst case)
- Datei: `GraphCanvas/GraphCanvasView+Physics.swift`
- Gründe / Risiken:
  - **Repulsion/Collision Pair Loop**: `for i in 0..<simNodes.count` + `for j in (i+1)..<simNodes.count` → O(n²) (`GraphCanvas/GraphCanvasView+Physics.swift`).
  - Bei `maxNodes` hoch + bei häufigen ticks → CPU-Spikes möglich.
- Mitigations im Code (observed):
  - i<j “compute once” + symmetrische Kräfte (`GraphCanvas/GraphCanvasView+Physics.swift`)
  - “Spotlight Physik”: `physicsRelevant` begrenzt simNodes (`GraphCanvas/GraphCanvasView+Physics.swift`)

#### Graph Load (SwiftData fetch + BFS)
- Dateien:
  - `GraphCanvas/GraphCanvasScreen+Loading.swift`
  - `GraphCanvas/GraphCanvasScreen.swift` (State `maxNodes=140`, `maxLinks=800`)
- Gründe / Risiken:
  - **Große Fetches am MainActor** (SwiftData `ModelContext` wird im UI Kontext genutzt) können UI blocken.
  - BFS Neighborhood Load baut Frontier Sets und macht Hop‑Fetches über `MetaLink` (`GraphCanvas/GraphCanvasScreen+Loading.swift`).
  - Filter + `unique()` auf Edges → potentiell teuer je nach Datenmenge.
- Mitigations im Code (observed):
  - `fetchLimit` für Entities/Links (`loadGlobal`, `loadNeighborhood`) (`GraphCanvas/GraphCanvasScreen+Loading.swift`)
  - “Commit result in one go” → verhindert Teil‑Overwrites bei cancelled loads (`GraphCanvas/GraphCanvasScreen+Loading.swift`)
  - Render caches (`labelCache`, `imagePathCache`, `iconSymbolCache`) werden beim Load einmalig gebaut (**kein SwiftData Fetch im Render‑Pfad**) (`GraphCanvas/GraphCanvasScreen+Loading.swift`)

#### Detail-Views Media (Listen/Grid)
- Datei: `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`
- Gründe / Risiken:
  - **Viele Zellen mit `.task/.onAppear`** (Gallery thumbs, Attachment rows) → kann “stampede” erzeugen, wenn viele Items gleichzeitig sichtbar werden.
  - **Thumbnail generation + file hydration** kann IO/CPU heavy sein (QuickLook/Video thumbnails).
  - “Alle” View (`NodeMediaAllView`) lädt paged, aber beim schnellen Scrollen können viele `loadMore*` Trigger feuern.
- Mitigations im Code (observed):
  - Paging via `fetchLimit/fetchOffset` + `fetchCount` (keine Voll-@Query) (`NodeMediaAllView` in `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`)
  - Hydration off-main via `AttachmentHydrator` + `AsyncLimiter` (`Attachments/AttachmentHydrator.swift`, `Attachments/AttachmentThumbnailStore.swift`)
  - Preview counts/limited fetch: `NodeMediaPreviewLoader` (`Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`)

### 2) Sync / Storage

#### SwiftData CloudKit Container + Fallback
- Datei: `BrainMeshApp.swift`
- Gründe / Risiken:
  - DEBUG `fatalError` bei CloudKit Container Fehler → Debug Builds “hart” (gut zum Finden, schlecht für Smoke tests ohne iCloud).
  - RELEASE fallback auf local-only → Daten/Sync Verhalten unterscheidet sich nach Build‑Konfiguration (`BrainMeshApp.swift`).
- Konkrete Stelle:
  - Container Setup + DEBUG/RELEASE Branch (`BrainMeshApp.swift`)

#### Attachment Storage (External Storage + local cache)
- Dateien:
  - Model: `Attachments/MetaAttachment.swift` (`@Attribute(.externalStorage) var fileData: Data?`)
  - IO: `Attachments/AttachmentStore.swift`
  - Hydration: `Attachments/AttachmentHydrator.swift`
  - Thumbnails: `Attachments/AttachmentThumbnailStore.swift`
- Gründe / Risiken:
  - **fileData** kann sehr groß werden (Videos/Docs). External storage hilft, aber CloudKit/SwiftData Limits bleiben relevant.
  - `localPath` ist device-local → auf neuem Device fehlt Cache, Hydrator muss wiederherstellen.
  - Thumbnail generation kann teuer sein (QuickLook).
- Mitigations im Code (observed):
  - `AttachmentHydrator.shared.configure(container:)` im detached init (`BrainMeshApp.swift`) → Hydration kann in background `ModelContext` passieren.
  - `AsyncLimiter` begrenzt parallele Thumbnail/Hydration Tasks (`Attachments/AttachmentThumbnailStore.swift`, `Attachments/AttachmentHydrator.swift`).

#### Image Storage (CloudKit-sync bytes + local JPEG cache)
- Dateien:
  - Data model fields: `MetaEntity.imageData/imagePath`, `MetaAttribute.imageData/imagePath` (`Models.swift`)
  - IO: `ImageStore.swift`
  - Hydration: `ImageHydrator.swift`
  - Import: `Images/ImageImportPipeline.swift`, `NotesAndPhotoSection.swift`
- Gründe / Risiken:
  - `imageData` sync’t als Data (Record pressure). Import Pipeline komprimiert aktiv.
  - `ImageHydrator` scannt alle Records mit `imageData != nil` und läuft als `@MainActor` (kann contention erzeugen) (`ImageHydrator.swift`).
- Mitigations im Code (observed):
  - Auto-hydration max 1x/24h (`AppRootView.swift` + `ImageHydrator.swift`)
  - Decode off-main in `NodeAsyncPreviewImageView` (`Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`)

### 3) Concurrency / Task Lifetimes

#### Gute Patterns (observed)
- Cancellation-aware loads:
  - `GraphCanvasScreen` nutzt `loadTask`/`Task.isCancelled` checks und committed state atomar (`GraphCanvas/GraphCanvasScreen.swift`, `GraphCanvas/GraphCanvasScreen+Loading.swift`).
- Off-main decode/hydration:
  - `NodeAsyncPreviewImageView` decode via `Task.detached` + `MainActor.run` (`Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`).
  - `AttachmentHydrator` nutzt eigenen `ModelContext` aus `ModelContainer` in Task.detached (`Attachments/AttachmentHydrator.swift`).

#### Risiken / Edge Cases
- MainActor contention:
  - `ImageHydrator.hydrate(...)` ist `@MainActor` und iteriert potentiell viele Records (`ImageHydrator.swift`).
- “Burst” Task creation:
  - Media grids/lists können viele thumbnail/hydration tasks starten (`Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`), auch wenn `AsyncLimiter` die Parallelität begrenzt.

## Refactor Map (konkret)

### A) Konkrete Splits (low-risk modularization)
1. **NodeDetailShared+Media weiter aufteilen**
   - Quelle: `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`
   - Ziel-Dateien (Vorschlag):
     - `Mainscreen/NodeDetailShared/Media/NodeMediaSection.swift` (Preview cards + entry points)
     - `Mainscreen/NodeDetailShared/Media/NodeMediaAllView.swift` (Paging + list/grid)
     - `Mainscreen/NodeDetailShared/Media/NodeMediaAttachmentRow.swift`
     - `Mainscreen/NodeDetailShared/Media/NodeMediaGalleryThumbTile.swift`
     - `Mainscreen/NodeDetailShared/Media/NodeMediaSheets.swift` (QuickLook/Video)
   - Nutzen: kleinere Compile Units + leichteres Profiling pro Subbereich.

2. **GraphCanvas Rendering in “Edges/Nodes/Text” schneiden**
   - Quelle: `GraphCanvas/GraphCanvasView+Rendering.swift`
   - Ziel-Dateien:
     - `GraphCanvas/Rendering/GraphCanvasRendering+Edges.swift`
     - `GraphCanvas/Rendering/GraphCanvasRendering+Nodes.swift`
     - `GraphCanvas/Rendering/GraphCanvasRendering+LabelsAndNotes.swift`
   - Nutzen: klare Verantwortlichkeiten, leichteres Performance‑Tuning.

3. **Graph Load Pipeline als Service kapseln**
   - Quelle: `GraphCanvas/GraphCanvasScreen+Loading.swift`
   - Ziel:
     - `GraphCanvas/GraphLoadService.swift` (pure functions + return `GraphLoadResult`)
   - Nutzen: Testbarkeit + Entkopplung von SwiftUI State.

### B) Cache-/Index-Ideen (konkret)
- **Attachment File URL Cache (per device)**
  - Heute: `AttachmentStore.ensurePreviewURL(for:)` + Hydrator schreibt Dateien (device-local). (`Attachments/AttachmentStore.swift`, `Attachments/AttachmentHydrator.swift`)
  - Idee: in-memory LRU mapping `attachmentID -> localURL` + invalidation bei delete/cleanup (`AttachmentCleanup.swift`).
- **Thumbnail cache invalidation**
  - Heute: `AttachmentThumbnailStore.deleteCachedThumbnail(attachmentID:)` wird bei cleanup genutzt (`Attachments/AttachmentCleanup.swift`).
  - Idee: zusätzlich invalidieren bei `updatedAt`/content hash (**UNKNOWN**: es gibt kein `updatedAt` Feld im Model).
- **GraphCanvas Path caching**
  - Heute: pro frame werden Paths neu gebaut (`GraphCanvas/GraphCanvasView+Rendering.swift`).
  - Idee: Cache per edge list signature + scale bucket (tradeoff: memory vs CPU). Nur sinnvoll, wenn edges stabil und frame time dominiert.

### C) Vereinheitlichungen (Patterns/DI)
- **Graph scope predicate helper**:
  - Wiederholt in `EntitiesHomeView.swift`, `GraphCanvasScreen+Loading.swift`, `NodeMediaPreviewLoader.swift`, `NodeDetailShared+Media.swift`.
  - Idee: helper `GraphScopePredicate.make(gid:)` oder kleine wrapper functions je Model.
- **Einheitliches “Delete with cleanup”**
  - Graph deletion macht Image + Attachment cleanup (`GraphPicker/GraphDeletionService.swift`).
  - Entity/Attribute deletion sollte denselben Cleanup Pfad nutzen (prüfen: **UNKNOWN** ob überall vorhanden).

## Risiken & Edge Cases (konkret)

### Datenverlust / Migration
- Legacy Scope `graphID == nil`:
  - Migration wird in `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)` ausgeführt (`GraphBootstrap.swift`).
  - Risiko: wenn Migration nicht läuft (z.B. Startup skipped) bleiben Records “global” und tauchen evtl. in falschen Graphen auf.
- Duplicate MetaGraph records:
  - GraphDeletionService löscht alle MetaGraph Datensätze mit gleicher UUID (`GraphPicker/GraphDeletionService.swift`).
  - Risiko: Root Cause der Duplikate ist **UNKNOWN**; Deduper existiert (`GraphPicker/GraphDedupeService.swift`).

### CloudKit / Record Limits
- Main photo bytes:
  - Komprimierung in `Images/ImageImportPipeline.swift` (target ~280 KB) → gut.
- Attachments:
  - `maxBytes = 25 MB` in `EntityDetailView.swift` (Kommentar: Limit attachments/videos). Enforcement ist im Snapshot **PARTIALLY UNKNOWN** (wo genau geprüft wird, hängt von Import-Flows in `Attachments/*` ab).

### Offline / Multi-device
- device-local caches (`imagePath`, `localPath`) sind nicht synchronisiert → Hydrators müssen nachziehen:
  - Images: `ImageHydrator.ensureCachedJPEGExists(...)` (`ImageHydrator.swift`)
  - Attachments: `AttachmentHydrator.ensureFileURL(...)` (`Attachments/AttachmentHydrator.swift`)

### Security
- Graph unlock ist in-memory:
  - `GraphLockCoordinator.unlockedGraphIDs` wird bei background lockAll gelöscht (`AppRootView.swift`).
  - Passwort Hash+Salt liegen im SwiftData Model (`Models.swift`) → threat model **UNKNOWN** (kein Keychain usage im Snapshot).

## Observability / Debuggability
- Logging + Timing: `Observability/BMObservability.swift`
  - `BMLog.load` wird im Graph load genutzt (`GraphCanvas/GraphCanvasScreen+Loading.swift`).
- Repro Tipps:
  - Performance Canvas: Erhöhe temporär `maxNodes/maxLinks` (`GraphCanvas/GraphCanvasScreen.swift`) und messe frame time (Instrument “Time Profiler”).
  - Media “Alle” Stress: großer Attachment‑Set pro Entity/Attribute → prüfe Task creation + limiter behavior (`Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`, `Attachments/AttachmentHydrator.swift`).

## Open Questions (**UNKNOWN** gesammelt)
- Deployment Target / Mindest‑iOS: **UNKNOWN** (keine Projektdateien im ZIP).
- Bundle Identifier / Versioning: **UNKNOWN** (Info.plist nutzt vermutlich Build Settings placeholders; im parsed plist keine Werte).
- SPM/Dependencies: **UNKNOWN** (kein `Package.resolved`/`Package.swift` im ZIP).
- CloudKit Environment: nur `aps-environment=development` sichtbar (`BrainMesh.entitlements`) → Produktion/Release‑Setup **UNKNOWN**.
- Datenmigrationsstrategie über `graphID` hinaus (Schema Migration): **UNKNOWN**.
- Tests/CI/Performance Benchmarks: **UNKNOWN**.

## First 3 Refactors I would do (P0)

### P0.1 — Media Layer weiter entknoten (NodeDetailShared+Media)
- Ziel: `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` in klar getrennte Subviews + kleine Loader/Helpers schneiden, ohne Verhalten zu ändern.
- Betroffene Dateien:
  - `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`
  - ggf. `Attachments/AttachmentHydrator.swift`, `Attachments/AttachmentThumbnailStore.swift` (nur falls Schnitt API braucht)
- Risiko: **Low–Medium** (viel UI, aber Task/Snapshot‑State muss stabil bleiben).
- Erwarteter Nutzen:
  - bessere Wartbarkeit + zielgerichtetes Profiling (Thumbnail/Hydration/Preview getrennt),
  - weniger Merge‑Konflikte und kleinere Compile Units.

### P0.2 — ImageHydrator “chunked” + background ModelContext
- Ziel: Hydration soll bei vielen Records keine MainActor spikes erzeugen.
- Betroffene Dateien:
  - `ImageHydrator.swift`
  - evtl. `BrainMeshApp.swift` (ModelContainer weiterreichen) / `AppRootView.swift` (call site)
- Risiko: **Medium** (SwiftData Threading: neuer `ModelContext` pro Task; sorgfältig mit cancellation/save).
- Erwarteter Nutzen:
  - weniger UI stalls beim Foreground,
  - planbarere IO (z.B. 50 Records pro chunk, yield zwischen chunks).

### P0.3 — Graph Load Service extrahieren + optionale Background-Preload
- Ziel: `GraphCanvasScreen+Loading.swift` in einen Service, der reine Daten (nodes/edges/caches) liefert, damit UI State schlank bleibt.
- Betroffene Dateien:
  - `GraphCanvas/GraphCanvasScreen+Loading.swift`
  - `GraphCanvas/GraphCanvasScreen.swift`
  - neues File: `GraphCanvas/GraphLoadService.swift`
- Risiko: **Low–Medium** (Refactor, aber Verhalten soll identisch bleiben; größte Gefahr: state wiring/cancellation).
- Erwarteter Nutzen:
  - bessere Testbarkeit (Loader kann mit mock ModelContext geprüft werden),
  - leichteres Performance‑Tuning (Loader isoliert).
