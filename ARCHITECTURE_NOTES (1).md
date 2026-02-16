# BrainMesh — ARCHITECTURE_NOTES

Last generated: 2026-02-16 (Europe/Berlin)

## Big Files List (Top 15 Dateien nach Zeilen)
| Lines | File | Purpose | Why it’s risky |
| --- | --- | --- | --- |
| 533 | BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift | GraphCanvas: per-frame render loop (edges/nodes/labels/thumbnails) | Hot path: executed every frame; allocations/lookup cost scales with nodes+edges. |
| 426 | BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift | GraphCanvas: SwiftData load (global + neighborhood) + caches | Load path: fetch + filtering; cancellation correctness; impacts perceived performance. |
| 349 | BrainMesh/GraphCanvas/GraphCanvasScreen.swift | GraphCanvas root screen: state, controls, lens, physics wiring | Large state surface; easy to introduce invalidations or I/O in view updates. |
| 331 | BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift | Shared media card + 'All media' screen for entity/attribute | Potential unbounded grids/lists; thumbnail work + memory pressure. |
| 326 | BrainMesh/Mainscreen/BulkLinkView.swift | Bulk linking UI (multi-select + link creation) | High UI+data coupling; can trigger many writes / heavy fetch if not bounded. |
| 320 | BrainMesh/Onboarding/OnboardingSheetView.swift | Onboarding sheet (multi-step UI) | Large UI file; low runtime risk but slows compile / iteration. |
| 315 | BrainMesh/PhotoGallery/PhotoGallerySection.swift | Photo gallery section embedded in details | Thumbnails + SwiftData queries; can cause scroll jank if not lazy. |
| 312 | BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift | Shared connections UI (links/related nodes) | Can expand to large lists; graph-scoped fetches and sorting. |
| 308 | BrainMesh/Mainscreen/EntitiesHomeView.swift | Entities home list (search + graph picker + delete) | Central navigation; search triggers multiple fetches and in-memory sort. |
| 298 | BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift | Shared highlight components (chips/rows) for details | Mostly UI; risk: computed props or sync image loading in body. |
| 298 | BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift | Full-screen gallery viewer | Paging + media decoding; memory pressure if preloading too much. |
| 290 | BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift | Gallery browser / grid | Large grid; requires careful laziness and thumbnail caching. |
| 283 | BrainMesh/GraphStatsView.swift | Graph statistics screen | Potential full-scan computations over SwiftData; watch for heavy grouping/sorts on main thread. |
| 278 | BrainMesh/Models.swift | SwiftData models: MetaGraph/Entity/Attribute/Link + search helpers | Schema changes are high impact (migration + CloudKit). |
| 273 | BrainMesh/Appearance/AppearanceModels.swift | Appearance models (themes, presets) | Low runtime risk; can bloat compile; ensure stable defaults. |

## Hot Path Analyse

### 1) Rendering / Scrolling (SwiftUI invalidations, Draw loops, expensive work)
- **GraphCanvas per-frame Rendering** — `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
-   - Wird pro Frame ausgeführt: Schleifen über `drawEdges` und `nodes` in `renderCanvas(...)` (Path allocation + stroke/fill).
-   - Skalierung: O(edges + nodes) pro Frame; bei Zoom/Interactions kann die UI bei Cache-Miss janken.
-   - Konkreter Hotspot: synchrones Bild-Laden via `ImageStore.loadUIImage(path:)` im Rendering-Codepfad (z.B. around line ~360).
-   - Bereits gute Maßnahmen im Code: `FrameCache` (screenPoints + labelOffsets) wird pro Frame einmal vorbereitet; Directed notes werden vorgefiltert (`prepareOutgoingNotes`).
- **GraphCanvas selection fullscreen image** — `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
-   - Öffnet Fullscreen Photo; lädt `UIImage` synchron aus Disk (`ImageStore.loadUIImage`) bevor Sheet angezeigt wird (line ~175).
-   - Wenn der Cache nicht warm ist oder File I/O langsam ist: UI-Delay beim Tap.
- **Node detail hero images** — `BrainMesh/Mainscreen/NodeDetailHeaderCard.swift` + `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
-   - `previewImage` computed property nutzt `ImageStore.loadUIImage` synchron.
-   - SwiftUI kann computed props häufig reevaluieren (State changes, environment changes). Disk-I/O in diesem Pfad kann Scrollen/Interaction ruckeln lassen.
- **Media 'All' screen** — `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` (`NodeMediaAllView`)
-   - Gallery Grid ist lazy (`LazyVGrid`).
-   - Attachment list ist nicht lazy (ScrollView + VStack + ForEach(attachments)) → Risiko: unbounded view creation + thumbnail requests; kann Freeze/Watchdog auslösen.
- **Entities home search** — `BrainMesh/Mainscreen/EntitiesHomeView.swift`
-   - Search = 2 separate SwiftData fetches (Entities by `nameFolded.contains`, Attributes by `searchLabelFolded.contains`) + in-memory merge + sort.
-   - Bei vielen Entities/Attributes kann die Kombi aus `contains` + `unique.values.sorted` spürbar werden.
- **PhotoGallery** — `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` + `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift`
-   - Typischer Memory-Hotspot: Bild-Decoding + prefetch; Stabilität hängt stark von Thumbnail caching (AttachmentThumbnailStore) und lazy grids ab.

### 2) Sync / Storage (CloudKit, fetch strategies, caching, background triggers)
- **SwiftData + CloudKit activation** — `BrainMesh/BrainMeshApp.swift`
-   - Container init: DEBUG fatalError bei Failure; RELEASE fallback auf local-only Configuration.
-   - `cloudKitDatabase: .automatic` ist aktiv; welche CloudKit-DB genau genutzt wird ist im Code nicht spezifiziert → **UNKNOWN** (check Apple docs/runtime).
- **Entitlements + Background** — `BrainMesh/BrainMesh.entitlements`, `BrainMesh/Info.plist`
-   - CloudKit + remote notifications sind enabled; das ermöglicht background wake über Push/CloudKit.
-   - `aps-environment` aktuell `development` → Release build muss `production` sein.
- **Graph scoping / legacy** — `BrainMesh/GraphBootstrap.swift`
-   - `graphID` ist optional bei MetaEntity/MetaAttribute/MetaLink. Legacy records werden beim Startup optional einem Default-Graph zugewiesen (`migrateLegacyRecordsIfNeeded`).
-   - Queries inkludieren häufig auch `graphID == nil` (legacy). Das verhindert „verschwundene Daten“, erhöht aber Query-Result-Size.
- **Image caching** — `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`, `BrainMesh/SettingsView.swift`
-   - Design: SwiftData `imageData` (sync) + Disk-JPEG (fast UI load).
-   - Risiko: Cache drift (DB updated, disk missing/old). Countermeasure: incremental hydration + force rebuild via Settings.
- **Attachments** — `BrainMesh/Attachments/*`
-   - `fileData` externalStorage ist gut gegen große DB-Records, aber Zugriff kann I/O-lastig sein.
-   - Local cache + thumbnail cache reduzieren repeated decoding.
-   - Cleanup ist manuell (owner references sind IDs).

### 3) Concurrency (MainActor, Task lifetimes, cancellation, thread safety)
- **Startup tasks** — `BrainMesh/AppRootView.swift`
-   - `.task` startet Bootstrapping; `.onChange(scenePhase)` triggert lock enforcement + optional prewarm/hydration.
-   - Potenzial: doppelte Tasks, wenn scenePhase schnell wechselt. Es gibt Guard/flags (`startupHasRun`).
- **Graph load cancellation** — `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift`
-   - Cancel checks (`Task.isCancelled`) sind vorhanden; `scheduleLoadGraph` (in Extensions) sollte alte Tasks canceln → **UNKNOWN** bis Code verifiziert (siehe GraphCanvasScreen+Helpers).
- **Thumbnails actor** — `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
-   - Actor schützt state; in-flight dedupe reduziert Task-storms.
- **MainActor contention candidates**
-   - Delete flows, rebuild caches und große sorts sollten möglichst nicht lange den MainActor blockieren.

## SwiftData Query Inventory (wo wird gefetched, wofür, welche Risiken)

### GraphCanvas Loading
- `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift`
-   - `loadGlobal()`: FetchDescriptor<MetaEntity> mit sortBy name + fetchLimit = maxNodes; FetchDescriptor<MetaLink> mit fetchLimit = maxLinks; filter by graphID + kind.
-   - `loadNeighborhood(...)`: BFS/neighbor fetches (Details in Datei); Risiko: multiple fetch rounds bei hohen hops.
-   - Gute Praxis: Build render caches (label/image/icon) im Load-Step, nicht im Render-Step.

### Entities Home
- `BrainMesh/Mainscreen/EntitiesHomeView.swift`
-   - Empty search: fetch all entities for active graph (plus legacy nil).
-   - Search: 2 fetches (entities by `nameFolded.contains`, attributes by `searchLabelFolded.contains`) + resolve owners.
-   - Risiko: `contains` kann teuer sein, insbesondere ohne geeignete Index-Unterstützung (SwiftData indexing ist **UNKNOWN**).

### Media / Attachments / Gallery
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`
-   - Gallery: `PhotoGalleryQueryBuilder.galleryImagesQuery(...)` (Query<MetaAttachment>).
-   - Attachments: `Query(filter: ..., sort: createdAt desc)` ohne limit.
-   - Risiko: unbounded `attachments` list → UI/Mem.
- `BrainMesh/PhotoGallery/PhotoGalleryQuery.swift`
-   - Zentralisiert Predicates (gut gegen Drift).
- `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
-   - Thumbnails werden async generiert/cached; UI sollte trotzdem lazy sein um nicht zu viele Requests zu feuern.

### Stats
- `BrainMesh/GraphStatsView.swift` + `BrainMesh/GraphStatsService.swift`
-   - Stats rechnen typischerweise Aggregationen über Entities/Links/Attributes. Prüfen, ob dies im body/onscreen synchron passiert (risk).
-   - Ohne Sampling/caching kann Stats view bei großen Datenmengen spürbar werden.

## Refactor Map (konkrete Splits, Cache-Ideen, Vereinheitlichungen)

### A) Konkrete Splits (low risk zuerst)
- **Node detail shared**
-   - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` ist UI + Routing + Query init in einer Datei.
-   - Split-Vorschlag (kein Behavior change):
-     - `NodeMediaCard.swift` (Karte auf Detail-Screen)
-     - `NodeMediaAllView.swift` (All-Screen: Lazy list/grid)
-     - `NodeMediaAllView+Sheets.swift` (viewer/preview/video sheets)
-     - `NodeGalleryThumb*` files (UI-only).
- **EntitiesHomeView**
-   - Split in `EntitiesHomeView+Fetch.swift` (fetchEntities), `EntitiesHomeView+Deletion.swift` (delete & cleanup), `EntitiesHomeView+Sheets.swift` (sheet state).
- **GraphStatsView**
-   - Split computed aggregations in `GraphStatsView+Computed.swift` und UI cards in `GraphStatsView+Cards.swift`.

### B) Cache-/Index-Ideen (was cachen, Keys, Invalidations)
- **Async cached image view** (P0 candidate):
-   - Ein kleiner `CachedImageView` der `imagePath` + `imageData` akzeptiert, intern async disk-load macht (ImageStore.loadUIImageAsync) und ein NSCache nutzt.
-   - Reuse in `NodeDetailHeaderCard` und `NodeHeroCard`.
- **Attachment list paging**:
-   - UI: `LazyVStack` plus „Load more“; Daten: manuell fetchen via FetchDescriptor mit `fetchLimit`/`fetchOffset` → fetchOffset Support in SwiftData ist **UNKNOWN** (verifizieren).
- **GraphCanvas images**:
-   - Memory cache `NodeKey → UIImage` (thumb) + `imagePathCache` already exists.
-   - Prefetch on selection change (GraphCanvasScreen) statt im draw loop.

### C) Vereinheitlichungen (Patterns/Services/DI)
- **Graph scope helper**:
-   - Zentraler Helper, damit das legacy-include Muster nicht divergiert (reduziert Bugs).
- **Deletion service**:
-   - `NodeDeletionService.deleteEntity(...)` / `deleteAttribute(...)`: kapselt link deletes + attachment cleanup + model deletes + save.
-   - Heavy I/O (FileManager.remove) in actor/detached task; modelContext ops bleiben auf MainActor/SwiftData thread.
- **Query builders**:
-   - PhotoGalleryQueryBuilder existiert bereits; analog für Links/Connections (EntityDetail/AttributeDetail) wäre sinnvoll.

## Risiken & Edge Cases (Datenverlust, Offline, Multi-Device, Locks)
- **Migration risk**:
-   - Keine `SchemaMigrationPlan` gefunden. Änderungen an @Model Feldern/Types können lokale Stores oder CloudKit mirroring brechen.
-   - GraphBootstrap migriert nur `graphID` legacy; nicht allgemeine Schema evolution.
- **Orphaned data risk**:
-   - MetaLink und MetaAttachment hängen an IDs, nicht an Relationships → ohne Cleanup bleiben Orphans.
-   - EntitiesHomeView macht Cleanup beim Delete; gleiche Disziplin braucht man in allen Delete-Pfaden.
- **Large binary sync risk**:
-   - `imageData` + `fileData` können große Payloads erzeugen; CloudKit hat Limits und kann Sync verlangsamen.
-   - Gegenmaßnahme: resizing/compression beim Import (prüfen wo das passiert → **UNKNOWN**).
- **Offline**:
-   - User kann lokal arbeiten; Sync Konflikte/merge sind möglich. Policy im Code nicht dokumentiert.
- **Locks**:
-   - Passwort-Hash/Salt im Model → wenn Sync aktiv: Lock-Konfiguration sync’t über CloudKit. Ob das gewünscht ist, ist Produktentscheidung → **UNKNOWN**.

## Observability / Debuggability
- `BrainMesh/Observability/BMObservability.swift` definiert Logger: `BMLog.load`, `BMLog.expand`, `BMLog.physics` + `BMDuration`.
- Empfohlen:
-   - Logge counts (nodes/edges) + durations in GraphCanvas load.
-   - Logge thumbnail cache hits/misses (AttachmentThumbnailStore).
-   - Optional: Build-time toggles für verbose logging (Feature flag) → **UNKNOWN** ob vorhanden.

## Repro / Test Checklist (Performance + Correctness)
- GraphCanvas
-   - Test global load (kein focus) und neighborhood load (focusEntity gesetzt).
-   - Edge notes: nur bei selection + nah zoom (alphas.showNotes) sichtbar; check correctness.
-   - Zoom/Pan stress test (maxNodes/maxLinks hoch).
- Media
-   - Entity mit 100+ gallery images + 100+ attachments öffnen → `Medien > Alle` sollte nicht freezen.
-   - Attachment preview: PDF, image, video; Thumbnail generation und caching.
- Sync
-   - 2 Geräte: Änderungen an Entity name/image/attachments; prüfen ob `imagePath` hydration korrekt nachzieht.
- Security
-   - Graph Lock: enable biometrics/password, App background/foreground → unlock overlay muss erscheinen.

## Open Questions (alles als **UNKNOWN** markiert)
- Welche CloudKit DB nutzt SwiftData bei `cloudKitDatabase: .automatic` in diesem Setup genau (private/shared)?
- Wie verhält sich SwiftData bei Merge-Konflikten (policy), und gibt es Anforderungen für deterministische conflict resolution?
- Unterstützt SwiftData `fetchOffset`/paging zuverlässig für große Attachment-Listen?
- Werden importierte Images vor Speicherung in `imageData` komprimiert/resized? (relevante Codepfade nicht eindeutig gefunden).
- Soll Lock-Konfiguration (Passwort-Hash) über CloudKit syncen oder nur lokal (Keychain)?

## First 3 Refactors I would do (P0)

### P0.1 — Remove synchronous disk I/O from SwiftUI render paths
- **Ziel**: `ImageStore.loadUIImage(path:)` nicht mehr aus computed props in `body`/render loops aufrufen.
- **Betroffene Dateien**:
-   - BrainMesh/Mainscreen/NodeDetailHeaderCard.swift
-   - BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift
-   - BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift (thumbnail path)
-   - BrainMesh/GraphCanvas/GraphCanvasScreen.swift (fullscreen image load)
- **Risiko**: niedrig (UI-only); Risiko = kurze Placeholder-Phase oder race conditions bei state updates.
- **Erwarteter Nutzen**: weniger UI jank, stabilere FPS, weniger Main-thread stalls.

### P0.2 — Make Media 'All' screen lazy + bounded
- **Ziel**: `NodeMediaAllView` skalierbar machen (viele Attachments).
- **Betroffene Dateien**:
-   - BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift
-   - BrainMesh/Attachments/AttachmentCardRow.swift (falls Row thumbnails synchron/expensive sind)
- **Risiko**: mittel (UI & navigation).
- **Erwarteter Nutzen**: verhindert Freeze/RAM spikes, smoother scroll.

### P0.3 — Centralize deletion & cleanup and move heavy work off-main
- **Ziel**: Konsistente Cleanup-Logik (Links + Attachments + lokale Files) und keine langen Main-thread blocks beim Delete.
- **Betroffene Dateien**:
-   - BrainMesh/Mainscreen/EntitiesHomeView.swift
-   - BrainMesh/Attachments/AttachmentCleanup.swift
-   - BrainMesh/GraphPicker/GraphDeletionService.swift (Graph delete kann ähnliche Cleanup Patterns brauchen)
- **Risiko**: mittel (Datenintegrität).
- **Erwarteter Nutzen**: weniger regressions, weniger orphaned attachments, bessere UX beim Delete.