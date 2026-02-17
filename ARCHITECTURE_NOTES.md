# ARCHITECTURE_NOTES — BrainMesh (Details)

> Stand: 2026-02-17  
> Fokus: Performance-/Wartbarkeits-Hebel, Tradeoffs, Hotspots, konkrete Refactor-Cuts.  
> Regel: Unklares = **UNKNOWN** und am Ende unter „Open Questions“.

## Big Files List (Top 15 nach Zeilen)
| LOC | Pfad |
|---|---|
| 726 | BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift |
| 626 | BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift |
| 532 | BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift |
| 425 | BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift |
| 408 | BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift |
| 359 | BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift |
| 348 | BrainMesh/GraphCanvas/GraphCanvasScreen.swift |
| 325 | BrainMesh/Mainscreen/BulkLinkView.swift |
| 319 | BrainMesh/Onboarding/OnboardingSheetView.swift |
| 311 | BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift |
| 309 | BrainMesh/PhotoGallery/PhotoGallerySection.swift |
| 307 | BrainMesh/Mainscreen/EntitiesHomeView.swift |
| 305 | BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift |
| 297 | BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift |
| 282 | BrainMesh/GraphStatsView.swift |

**Warum riskant?**
- Große SwiftUI-Dateien erhöhen Compile-Zeiten und machen Review/Refactor schwer (viele Responsibilities).
- Große „+Sheets/+Media/+Rendering“ Dateien sind Hotspots für Regressions (State/Bindings/Navigation, viele `.task`/`sheet`/`alert`).

## Hot Path Analyse

### 1) Rendering / Scrolling (SwiftUI)
#### Graph Canvas: 30 FPS + Canvas Rendering
Betroffene Dateien:
- `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView.swift`

Warum Hotspot:
- **Timer-getriebene Simulation auf Main RunLoop**: `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, ...)` in `GraphCanvasView+Physics.swift` → `stepSimulation()` läuft regelmäßig.
- **O(n²) Pair-Loop**: Repulsion + Collision iterieren über Node-Paare (`for i in 0..<simNodes.count` / `for j in (i+1)..<...`) → bei `maxNodes`=140 (State in `GraphCanvasScreen.swift`) ~9.7k Paare pro Tick (30 FPS).
- **Hohe Invalidations**: `positions`/`velocities` sind `@Binding` Dictionaries; Updates pro Tick invalidieren den View (Canvas redraw).  
  Mitigation: Idle/Sleep stoppt Timer nach ~3s Stabilität (`physicsIdleTicks`).

Konkrete Risiken:
- Main-thread contention (UI events + physics + draw) → Stutter, Energy Impact.
- Dictionary-heavy Access (`positions[key]`, `vel[...]`) im inner loop → viele Hash lookups.

Bereits vorhandene Mitigations:
- „Sleep when idle“ in `GraphCanvasView+Physics.swift`.
- Spotlight Physik: `physicsRelevant` begrenzt Simulationsmenge (Selection+Neighbors) in `GraphCanvasView+Physics.swift`.
- Render caches: `labelCache`, `imagePathCache`, `iconSymbolCache` werden beim Load gebaut (`GraphCanvasScreen+Loading.swift`).

Refactor-Ideen (konkret):
- Physik-Arrays statt Dictionary im Tick (Index-basierte Buffers) **wenn** `nodes` stabile Reihenfolge hat. Risiko: medium (Mapping/Mutation).
- Tick auf `CADisplayLink` + adaptive FPS (z.B. 15 FPS bei idle) **wenn** nötig. Risiko: medium.
- Micro-opt: `simNodes` einmal in `[NodeKey]` + `pos/vel` in lokale Arrays; nur am Ende zurückschreiben. Risiko: medium.

#### Medien-/Galerie-Grids: viele Thumbnails, viele Tasks
Betroffene Dateien:
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`
- `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`
- `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

Warum Hotspot:
- **Viele Grid-Items** → viele SwiftUI `.task`-Starts pro Tile (Thumbnail load/generation).
- **Externes Thumbnailing** (QuickLook/AVFoundation) ist teuer, muss strikt throttled werden.

Bereits vorhandene Mitigations:
- `AttachmentThumbnailStore`:
  - Memory `NSCache` + Disk Cache (`thumb_v2_<id>.jpg`)
  - Downscaling via ImageIO (garantiert kleine Bitmaps)
  - Concurrency limit: `AsyncLimiter(maxConcurrent: 3)` (Generierung)  
    Datei: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- Attachment-/Media „Alle“-Screen lädt über Actor `MediaAllLoader` (Background ModelContext) → verhindert Freeze beim Push.
  Datei: `BrainMesh/Attachments/MediaAllLoader.swift`

Konkrete Risiken:
- Thumbnails können trotzdem „burst“en (viele Tasks starten, obwohl Store limitiert) → Task overhead + Memory churn.
- Grid Layout Probleme/Overlaps sind UI-seitig möglich (abhängig vom Grid/Aspect-Ratio); Ursache muss in den jeweiligen Tile-Views gesucht werden (**UNKNOWN** ohne UI-Screenshot).

### 2) Sync / Storage (SwiftData / CloudKit / Caches)
#### SwiftData Container + CloudKit
Betroffene Dateien:
- `BrainMesh/BrainMeshApp.swift`
- `BrainMesh/BrainMesh.entitlements`
- `BrainMesh/Info.plist`

Was sicher ist:
- SwiftData `ModelContainer` wird mit `cloudKitDatabase: .automatic` gebaut (`BrainMeshApp.swift`).
- Entitlements enthalten CloudKit Container `iCloud.com.marcfechner.BrainMesh`.

Warum Hotspot:
- **DEBUG init fatal**: In `BrainMesh/BrainMeshApp.swift` führt ein Container-Fehler in DEBUG zu `fatalError(...)`.  
  Das kann Dev-Flows blockieren (Simulator ohne iCloud, Entitlements mismatch, CloudKit env issues).

**UNKNOWN**
- CloudKit Schema/Record Types/Zone-Strategie (kein `import CloudKit` Code; SwiftData abstrahiert).
- Konfliktauflösung/merge policy (SwiftData Standard; nicht explizit im Code).

#### Bilder: sync bytes + lokaler Cache (Hydration)
Betroffene Dateien:
- `BrainMesh/NotesAndPhotoSection.swift`
- `BrainMesh/ImageHydrator.swift`
- `BrainMesh/ImageStore.swift`
- `BrainMesh/Images/ImageImportPipeline.swift`
- `BrainMesh/AppRootView.swift`

Warum Hotspot:
- `ImageHydrator.hydrateIncremental` fetch’t alle Records mit `imageData != nil` im `ModelContext` (`ImageHydrator.swift`).  
  Der Fetch läuft synchron (auch wenn danach async Disk writes), und wird in `AppRootView` bei `.active` getriggert (throttled auf 24h).
- `NotesAndPhotoSection` macht beim Import:
  - ImageIO decode + resize + JPEG komprimieren in `Task.detached` (gut)
  - Speichern in SwiftData + Disk cache

Tradeoff:
- `imageData` als Sync-Quelle ist robust, aber CloudKit Record Pressure (daher starke Kompression in `ImageImportPipeline.prepareJPEGForCloudKit`).

Refactor-Ideen:
- Hydration in Background ModelContext (wie `MediaAllLoader`), main context nur „didChange“ committen. Risiko: medium (Konflikte/Save).

#### Attachments: externalStorage + Cache + Hydration
Betroffene Dateien:
- `BrainMesh/Attachments/MetaAttachment.swift`
- `BrainMesh/Attachments/AttachmentHydrator.swift`
- `BrainMesh/Attachments/AttachmentStore.swift`
- `BrainMesh/Attachments/MediaAllLoader.swift`
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`

Warum Hotspot:
- `fileData` ist externalStorage → bei unglücklichen Predicates kann SwiftData in-memory filtern und dabei große blobs anfassen.
- Das Projekt adressiert das explizit:
  - `AttachmentGraphIDMigration` migriert legacy `graphID == nil`, um OR-Predicates zu vermeiden.
  - `MediaAllLoader` nutzt Background ModelContext (kein UI-blocking fetch).

Risiken/Edge Cases:
- Cache-Dateien können verwaisen (App gelöscht/Cache cleared) → Hydrator muss „repair“en (sieht so aus, ist implementiert).
- Große Dateien: `NodeAttachmentsManageView` limitiert `maxBytes` auf 25MB (`NodeDetailShared+SheetsSupport.swift`).

### 3) Concurrency (Tasks, Cancellation, Actor boundaries)
#### Background ModelContext pattern (gutes Beispiel)
Betroffene Dateien:
- `BrainMesh/Attachments/MediaAllLoader.swift`
- `BrainMesh/Attachments/AttachmentHydrator.swift`

Positiv:
- `AnyModelContainer` wird in `BrainMeshApp` per `Task.detached` in Actors konfiguriert.
- Background work läuft in `Task.detached(priority: .utility)` und baut einen **eigenen** `ModelContext(container.container)`.
- Throttling + in-flight dedupe verhindert stampedes (`inFlight` dict + `AsyncLimiter`).

Risiken:
- Actor-Isolation: Container muss vor Nutzung gesetzt sein; ohne Configure ist Verhalten **UNKNOWN**. (Code nutzt `guard let container` → returns early in manchen Pfaden; siehe `AttachmentHydrator.swift` / `MediaAllLoader.swift`.)
- Cancellation: UI-seitige Tasks (Tiles) verlassen sich auf SwiftUI cancellation; in Actors laufen detached Tasks ggf. weiter (bewusst), was ok ist, aber Energy Impact beeinflussen kann.

#### MainActor-heavy Services
Betroffene Dateien:
- `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift` (Laden + Fetches)
- `BrainMesh/GraphStatsService.swift` (komplett `@MainActor`)

Warum Hotspot:
- Mehrere synchrone `ModelContext.fetch(...)` / `fetchCount(...)` auf MainActor → kann UI blockieren.

## Refactor Map (konkrete Splits / Caches / Vereinheitlichungen)

### A) Konkrete Splits (Datei → neue Dateien)
1) `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` (726 LOC)
- Vorschlag:
  - `NodeMediaSection.swift` (Preview Grid + Header + Buttons)
  - `NodeMediaAllView.swift` (die „Alle Medien“ Screen)
  - `NodeMediaThumbGrid.swift` (LazyVGrid + Layout)
  - `NodeMediaTiles.swift` (PhotoGallerySquareTile / AttachmentTile)
- Ziel: Compile-Time runter, Responsibilities trennen, UI-Bugs einfacher lokalisieren.
- Risiko: low (nur UI-Split, keine Logikänderung).

2) `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift` (626 LOC)
- Vorschlag:
  - `NodeAttachmentsManageView.swift` (List + paging)
  - `NodeAttachmentsImport.swift` (fileImporter/video picker flows)
  - `NodeAttachmentsPreview.swift` (openAttachment + preview sheet)
- Risiko: low-medium (Sheet/Alert wiring; testen: Import, Preview, Delete).

3) `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (532 LOC)
- Vorschlag:
  - `GraphCanvasRendering+Edges.swift`
  - `GraphCanvasRendering+Nodes.swift`
  - `GraphCanvasRendering+Labels.swift`
  - `GraphCanvasRendering+Cache.swift` (Frame cache types + helpers)
- Risiko: low (mechanischer Split), Nutzen: Reviewbarkeit + gezielte Optimierung.

### B) Cache-/Index-Ideen
1) Graph adjacency cache beim Load
- Ausgang: `GraphCanvasScreen+Loading.swift` baut `edges` + `directedEdgeNotes`, und UI rechnet `edgesForDisplay()` + Lens.
- Idee: beim Load zusätzlich `neighborsByNode: [NodeKey: [NodeKey]]` generieren (aus `edges`), Lens BFS wird schneller.
- Risiko: low (zusätzlicher Cache), Nutzen: weniger pro-selection CPU.

2) Attachment bytes / counters
- Ausgang: `GraphStatsService.totalAttachmentBytes()` fetch’t alle Attachments und summiert `byteCount`.
- Idee: persistenter Counter pro Graph (z.B. in `MetaGraph`), aktualisiert bei Import/Delete.
- Risiko: medium (Konsistenz, Migration), Nutzen: Stats werden O(1).

### C) Vereinheitlichungen (Patterns, Services, DI)
1) Active Graph State
- Ausgang: `GraphSession.shared` beobachtet UserDefaults (`BrainMesh/GraphSession.swift`), gleichzeitig überall `@AppStorage("BMActiveGraphID")`.
- Vorschlag: **eine** Quelle:
  - Entweder `@AppStorage` überall und `GraphSession` entfernen,
  - oder `GraphSession` als single source of truth und UI bindet daran.
- Risiko: low, Nutzen: weniger „zwei Wahrheiten“ Bugs.

2) Background Fetch Pattern konsistent machen
- `MediaAllLoader` ist Vorbild: Container rein, Background ModelContext, result zurück.
- Vorschlag: gleiches Pattern für:
  - Graph loading (`GraphCanvasScreen+Loading.swift`)
  - Stats counts (`GraphStatsService.swift`)
- Risiko: medium (ModelContext-Semantik), Nutzen: UI bleibt responsiv.

## Risiken & Edge Cases (aus Code ablesbar)
- CloudKit / Container init:
  - DEBUG: kein Fallback (`fatalError`) → kann Dev blockieren (`BrainMesh/BrainMeshApp.swift`).
- Migration:
  - Graph scoping + Legacy `graphID == nil` muss „clean“ sein, sonst teure Predicates (siehe `GraphBootstrap.swift`, `AttachmentGraphIDMigration.swift`).
- Attachments:
  - externalStorage + in-memory filter ist kritisch (explizit kommentiert), daher OR-Predicates vermeiden.
- Datenverlust:
  - Delete von Attachments räumt Cache via `AttachmentCleanup.deleteCachedFiles` (siehe `NodeDetailShared+SheetsSupport.swift`).  
    Ob CloudKit delete/propagation sauber ist: **UNKNOWN** (SwiftData default).

## Observability / Debuggability
- Logging:
  - `BrainMesh/Observability/BMObservability.swift` definiert `BMLog` Kategorien + `BMDuration`.
  - Graph load logs: `GraphCanvasScreen+Loading.swift` (Timing + counts).
  - Attachment hydrator logs: `AttachmentHydrator.swift` (Logger category „AttachmentHydrator“).
- Repro Tips (praktisch):
  - Graph-Load Perf: in `GraphCanvasScreen` `maxNodes/maxLinks` hochdrehen und Logs beobachten.
  - Media Perf: viele Attachments + Gallery Images importieren, dann „Alle Medien“ öffnen (Paging + thumbnails).
  - CloudKit Edge: Simulator/Device ohne iCloud → DEBUG init wird sichtbar.

## Open Questions (UNKNOWNs)
1. CloudKit:
   - Gibt es ein explizites CloudKit Schema/Zone Setup oder reine SwiftData-Defaults?
   - Konfliktauflösung/merge policy relevant? (nicht im Code konfiguriert)
2. Test/CI:
   - Gibt es Test Targets oder CI Pipelines außerhalb des ZIP? (im Code keine Tests gefunden)
3. Offline/Recovery:
   - Welche UX ist gewollt bei Sync-Lags/Conflicts (z.B. duplicates, missing links)? (keine explizite UX im Code)
4. Gallery/Grid Layout:
   - Aktuelle UI-Probleme (Overlaps/Aspect Ratio) hängen an konkreten Tile Views/Layout-Constraints → ohne UI-Screenshot **UNKNOWN**.

## First 3 Refactors I would do (P0)
### P0.1 — Graph Loading off MainActor
- **Ziel:** Graph-Load (global/neighborhood) ohne UI-Blocker; Navigation + Interaktionen bleiben responsiv.
- **Betroffene Dateien:**  
  `BrainMesh/GraphCanvas/GraphCanvasScreen+Loading.swift`, `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`, ggf. neues `BrainMesh/GraphCanvas/GraphLoader.swift` (Actor/Service).
- **Risiko:** Medium. Background-`ModelContext` + State Commit muss sauber cancellable/ordered bleiben (ähnlich `loadTask` Pattern).
- **Erwarteter Nutzen:** weniger Stutter beim Wechseln/Reload, stabilere CPU/Energy bei großen Datenmengen.

### P0.2 — Stats Counting in Background + Bytes-Counter Strategie
- **Ziel:** `GraphStatsView` soll nie „hängen“, auch mit vielen Attachments.
- **Betroffene Dateien:**  
  `BrainMesh/GraphStatsService.swift`, `BrainMesh/GraphStatsView.swift`, optional `MetaGraph` (falls Counter-Felder eingeführt werden).
- **Risiko:** Medium. Persistente Counter erfordern Migration/Consistency; reine Background-Berechnung ist lower risk.
- **Erwarteter Nutzen:** spürbar smoother Stats Screen, weniger Main-thread work, bessere Skalierung.

### P0.3 — NodeDetailShared Media/Sheets in kleine Units splitten
- **Ziel:** Wartbarkeit/Compile-Time verbessern, UI-Bugs (Media Grid) isolierbar machen.
- **Betroffene Dateien:**  
  `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`,  
  `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift`,  
  `BrainMesh/PhotoGallery/*` (falls gemeinsame Tiles extrahiert werden).
- **Risiko:** Low. Mechanischer Split, Verhalten sollte gleich bleiben.
- **Erwarteter Nutzen:** schnellere Iteration, weniger „God files“, sauberere Verantwortlichkeiten.
