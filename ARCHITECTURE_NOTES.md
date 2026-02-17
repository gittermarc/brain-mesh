# BrainMesh — ARCHITECTURE_NOTES (Details)

Schwerpunkt: Sync/Storage/Model → Entry Points & Navigation → große Views/Services → Konventionen/Workflows.

---

## Big Files List (Top 15 Dateien nach Zeilen)
Zeilenzahlen sind approximiert und stammen aus dem aktuellen Repository-Snapshot.

- **694** — `BrainMesh/Stats/GraphStatsService.swift`
  - Zweck: Stats-Backend: Counts, Media-Breakdown, Struktur + Trends-Snapshots
  - Warum riskant: Viele SwiftData `fetchCount`/`fetch` Aufrufe; wenn häufig getriggert, teuer. Predicate-Komplexität + wiederholte Queries. Risiko von ungewolltem In-Memory-Fallback, falls Predicates nicht sauber übersetzen.
- **689** — `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift`
  - Zweck: Sheets + Workflows für Anhänge (Import, Liste, Öffnen, Löschen)
  - Warum riskant: Große Mischdatei: UI + Import-Orchestrierung + Previews + Alerts. Höheres Regressionsrisiko und Compile-Time Hotspot.
- **580** — `BrainMesh/Stats/StatsComponents.swift`
  - Zweck: Shared Stats UI Bausteine (Cards, KPI, Mini-Charts)
  - Warum riskant: Custom Chart/Layout in Scroll-Kontext; potenziell teures Path/Layout, wenn oft/mit großen Arrays gefüttert.
- **532** — `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - Zweck: Canvas Rendering Pipeline (Edges/Nodes/Labels/Thumbs) + Frame-Cache Aufbau
  - Warum riskant: Läuft im Renderpfad; Allokationen und per-frame Work skalieren mit Nodes+Edges. Primärer Hot Path für Interaktions-Jank.
- **411** — `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - Zweck: Off-main Loader: SwiftData Fetch + Nachbarschafts-BFS + Mapping zu GraphNode/GraphEdge
  - Warum riskant: `contains()` in Predicates (Übersetzung **UNKNOWN**), plus Traversal. Cancellation/Limits müssen sauber sein, sonst CPU-Spikes.
- **408** — `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - Zweck: „Bilder verwalten“: alle Bilder eines Nodes browsen/selektieren
  - Warum riskant: Risiko für Memory, falls Decoding nicht thumbnail-basiert/lazy ist. Viele Items → viele Thumbnail-Loads.
- **360** — `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - Zweck: Media-Galerie-Sektion (Preview Grid + Navigation) auf Node-Details
  - Warum riskant: Grid in Scroll; viele Thumbnails. Jede synchrone Decode/FETCH im body wäre sofort spürbar.
- **359** — `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
  - Zweck: Shared Core UI für Node-Details (Hero/Header/Layout-Basis)
  - Warum riskant: Zentraler Shared Baustein: Änderungen wirken auf Entity + Attribute Detail. Hohe Blast-Radius Gefahr.
- **348** — `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - Zweck: Graph-Tab Host: State, Navigation, Sheets; delegiert Arbeit an Extensions/Loader
  - Warum riskant: Große State-Fläche; falsche State-Änderungen können exzessive Invalidations auslösen. Viele Sheet-Flows müssen konsistent bleiben.
- **342** — `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - Zweck: Reusable Foto-Galerie-Sektion (Preview Grid + Navigation)
  - Warum riskant: Grid-Sizing/Spacing muss robust sein; sonst Overlaps/Unsauberkeiten. Thumbnail-Loading in Listen-Kontext kann janken.
- **325** — `BrainMesh/Mainscreen/BulkLinkView.swift`
  - Zweck: Bulk-Link UI (viele Links in einem Rutsch anlegen/bearbeiten)
  - Warum riskant: Kann N×M Operationen triggern (abhängig von Selektion). Braucht Batching + Cancellation, sonst UI-Stalls.
- **319** — `BrainMesh/Onboarding/OnboardingSheetView.swift`
  - Zweck: Onboarding Multi-Step Sheet
  - Warum riskant: Große View mit viel State/Logik. Wartbarkeit + Compile-Time Hotspot.
- **316** — `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`
  - Zweck: Galerie-Browser für viele Bilder
  - Warum riskant: Viele Items im Grid/List; Memory-Risiko bei aggressivem Decoding ohne Cache/Limit.
- **311** — `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
  - Zweck: Connections/Links-Sektion (Shared) in Node-Details
  - Warum riskant: Links-Darstellung + Queries; teuer, wenn Derived State im Renderpfad ständig neu berechnet wird.
- **307** — `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - Zweck: Home-Tab: Listen, Suche, Graph-Scoping, Navigation
  - Warum riskant: SwiftData Fetches laufen aktuell auf MainActor; wächst die DB, drohen UI-Stalls. Predicates nutzen OR mit `graphID == nil` Pattern.

---

## Hot Path Analyse

### Rendering / Scrolling

#### 1) Graph Canvas: Rendering-Pfad
- **Dateien**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView.swift`
- **Warum Hot Path**
  - Pro-Frame Arbeit: Aufbau `frameCache` + Iteration über Edges/Nodes (skaliert grob ~O(N + E)).
  - Hohe Invalidation-Gefahr: Änderungen an `positions`, Selection, Kamera, Overlays triggern Re-Draws.
  - Thumbnail-Loading: Decode läuft auf globaler Queue, aber Ergebnis landet in `@State` (`thumbnailImages`) → kann zusätzliche Invalidations auslösen.
- **Konkrete Risiken**
  - Große Graphen: CPU-bound durch Schleifen + Label/Text-Layout.
  - Ungebundene Thumbnail-Decodes können Memory-Spikes erzeugen (schnelles Pan/Zoom).

#### 2) Graph Canvas: Physik-Pfad (Main-Thread Simulation)
- **Datei**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- **Warum Hot Path**
  - Timer-basierte 30 FPS Simulation mit **Pair-Loop Repulsion/Collision** → Worst Case ~O(N²).
  - Läuft über `Timer.scheduledTimer` auf dem Main RunLoop → konkurriert direkt mit Input/Rendering.
- **Konkrete Risiken**
  - Jank unter Last: Gestures + Physik + Draw contend um Main Thread.
  - Große Graphen: selbst mit Spotlight können Worst-Case-Fälle teuer werden.

#### 3) Node Media Grids (Detailseiten + Galerie)
- **Dateien**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`
- **Warum Hot Path**
  - Viele Thumbnails in Scroll Views (LazyVGrid/List) → Layout + Decode.
  - Kritisch, falls irgendwo implizit SwiftData-Fetches oder Sync-Decode im `body` passieren.
- **Konkrete Risiken**
  - Memory Pressure, wenn Full-Res statt Preview/Thumb decodiert wird.
  - Scroll-Hitches bei synchroner Bildarbeit.

### Sync / Storage

#### 1) SwiftData + CloudKit automatic
- **Dateien**
  - `BrainMesh/BrainMeshApp.swift` (ModelContainer Setup)
  - `BrainMesh/BrainMesh.entitlements` (CloudKit Container)
- **Beobachtbares Verhalten**
  - CloudKit aktiv via `ModelConfiguration(schema:..., cloudKitDatabase: .automatic)`.
  - Release-Fallback zu lokal-only Container ist vorhanden (non-DEBUG Pfad).
- **Risiken / Tradeoffs**
  - Sync-Konfliktstrategie ist nicht explizit im Code modelliert (**UNKNOWN**).
  - Diagnostik für Sync-Probleme ist minimal (hauptsächlich Xcode/iCloud Logs; **UNKNOWN** ob Analytics vorhanden).

#### 2) `.externalStorage` + Predicate-Fallen (Attachments)
- **Dateien**
  - `BrainMesh/Attachments/MetaAttachment.swift` (`fileData` als `@Attribute(.externalStorage)`)
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (konkrete Warnung + Migration)
  - `BrainMesh/Attachments/MediaAllLoader.swift` (Fetch ohne `fileData`)
- **Warum kritisch**
  - Im Projekt ist das zentrale Risiko bereits dokumentiert: OR-Predicates (z.B. `graphID == gid || graphID == nil`) können In-Memory-Fallback auslösen und dadurch **`fileData` materialisieren**.
- **Was schon gut ist**
  - `MediaAllLoader` arbeitet mit „lightweight“ Items und vermeidet `fileData`.
  - Attachment `graphID` Migration existiert als Performance-Guard.
- **Rest-Risiko**
  - Viele Queries bei Entities/Attributes/Links verwenden weiterhin `graphID == gid || graphID == nil` Patterns:
    - Beispiele: `BrainMesh/Mainscreen/EntitiesHomeView.swift`, `BrainMesh/Mainscreen/NodePickerView.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`.
  - Bei Entities/Attributes/Links ist das weniger gefährlich als bei Attachments, aber kann trotzdem:
    - Query-Komplexität erhöhen
    - In-Memory-Fallback begünstigen (**UNKNOWN**, Profiling nötig)

#### 3) Disk Caches & Hydration
- **Images**
  - `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`
  - Trigger in `BrainMesh/AppRootView.swift` (max. 1× pro 24h).
- **Attachments**
  - `BrainMesh/Attachments/AttachmentStore.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`
  - Hydration mit Concurrency-Limiter, UI nutzt meist „lightweight“ Items.
- **Risiken**
  - ImageHydrator ist `@MainActor`: bei wachsender Datenmenge können Foreground-Transitions schwerer werden.
  - Cache-Invalidation ist heuristisch (Paths + „exists“), Stale-Cache Edge Cases möglich (**UNKNOWN**, ob bekannt).

### Concurrency

#### Actor + detached Tasks (Loader/Hydrator Pattern)
- **Dateien**
  - `BrainMesh/Attachments/MediaAllLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
- **Pattern**
  - `actor` hält `container: AnyModelContainer?`, gesetzt via `configure(...)`.
  - API arbeitet mit `Task.detached` + frischem `ModelContext` (`autosaveEnabled = false`).
- **Stärken**
  - Heavy SwiftData Work off-main → weniger UI-Blocker.
- **Konkrete Risiken**
  - Startup-Race: Loader-Aufruf vor `configure(...)`. `GraphStatsLoader` wirft explizit „not configured“ (`BrainMesh/Stats/GraphStatsLoader.swift`).
    - Mitigation: `GraphStatsView.startReload` macht `await Task.yield()`.
    - Aber nicht garantiert in allen Situationen (**UNKNOWN**, Häufigkeit).
  - Cancellation: nicht alle langen Phasen checken Cancellation gleich konsequent.

---

## Refactor Map

### A) Konkrete Splits (low risk / Compile-Time + Wartbarkeit)
1. `BrainMesh/Stats/GraphStatsService.swift`
   - Splits nach Concern:
     - `GraphStatsService+Counts.swift`
     - `GraphStatsService+Media.swift`
     - `GraphStatsService+Structure.swift`
     - `GraphStatsService+Trends.swift`
2. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift`
   - UI/Logic trennen:
     - `NodeAttachmentsManageView.swift` (UI)
     - `NodeAttachmentsManageViewModel.swift` (Pagination/Import/Delete/Open)
     - `AttachmentPreviewSheetState.swift` (DTO/State)
3. `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
   - Splits:
     - `GraphCanvasRenderingCache.swift`
     - `GraphCanvasDrawing.swift`
     - `GraphCanvasThumbnails.swift`

### B) Cache-/Index-Ideen (Performance-Hebel)
1. **Graph Scope Normalisierung**
   - Vorschlag: `graphID == nil` als Legacy behandeln und Entities/Attributes/Links in einen echten Graph migrieren (wie Attachments).
   - Effekt: weniger OR-Predicates, weniger Risiko für In-Memory-Fallback, klareres Modell.
2. **Stats Snapshot Caching**
   - Kurzer TTL Cache in `GraphStatsLoader` (z.B. 30–60s), invalidiert auf Mutationen.
3. **Canvas Expansion Caching**
   - Memoization von Nachbarschafts-Sets in `GraphCanvasDataLoader` für die Session.

### C) Vereinheitlichungen
- Zentraler Graph-Scope Helper: `BrainMesh/Support/GraphScope.swift` (pure helpers + ggf. predicate-builder).
- Optional: DI statt Singletons, falls Tests/Varianten wichtig werden (Start bei Loader/Hydrator).

---

## Risiken & Edge Cases
- Migrationen:
  - `BrainMesh/GraphBootstrap.swift` migriert Legacy Records in Default-Graph.
  - Risiko: Behavior-Change, falls `nil` als „global“ gedacht ist (**UNKNOWN**).
- Offline/Multi-Device:
  - Explizites Offline-UX nicht modelliert (**UNKNOWN**).
  - Caches (`imagePath`, `localPath`) sind device-local und dürfen nie als Source of Truth verstanden werden.
- Security + System Picker:
  - Workaround gegen Hidden-Album/FaceID Loop ist bewusst: `SystemModalCoordinator` + debounced Locking (`BrainMesh/AppRootView.swift`).
  - Jede neue Picker-Integration muss `beginSystemModal/endSystemModal` korrekt setzen.

---

## Observability / Debuggability
- Logging/Timing:
  - `BrainMesh/Observability/BMObservability.swift` (`BMLog`, `BMDuration`)
  - Physics Tick Logs: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- Repro-Checklisten:
  - Canvas-Jank: großer Graph, pan/zoom, Logs/CPU beobachten.
  - Media-Jank: viele Bilder an einem Node, `NodeImagesManageView` öffnen, Memory beobachten.
  - Stats-Slowness: mehrere Graphen + Anhänge, Stats öffnen/refreshen, CPU in detached tasks.

---

## Open Questions (UNKNOWN)
1. SwiftData Predicate Translation: Übersetzt `contains()` zuverlässig oder fällt es auf In-Memory zurück (z.B. in `GraphCanvasDataLoader`)?
2. CloudKit Konflikt-/Merge-Erwartungen: Welche Semantik soll gelten? Nichts explizit codiert.
3. Bedeutung von `graphID == nil`: reine Legacy oder bewusst „global“?
4. Loader-Configure Race: gibt es reale Fälle von „not configured“?
5. Cache-Invalidation: wann `imagePath/localPath` resetten vs. wiederverwenden?

---

## First 3 Refactors I would do (P0)

### P0.1 — Graph Scoping normalisieren (OR-Predicates reduzieren)
- **Ziel**
  - Legacy `graphID == nil` für Entities/Attributes/Links in einen konkreten Graph migrieren.
- **Betroffene Dateien**
  - `BrainMesh/GraphBootstrap.swift`
  - Query Call Sites:
    - `BrainMesh/Mainscreen/EntitiesHomeView.swift`
    - `BrainMesh/Mainscreen/NodePickerView.swift`
    - `BrainMesh/Mainscreen/NodeMultiPickerView.swift`
    - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
    - `BrainMesh/Stats/GraphStatsService.swift`
    - `BrainMesh/Onboarding/OnboardingProgress.swift`
- **Risiko**
  - Behavior-Change, falls `nil` als „global“ gedacht war (**UNKNOWN**).
- **Erwarteter Nutzen**
  - Einfachere Predicates, weniger ORs, geringeres In-Memory-Fallback-Risiko, klareres mental model.

### P0.2 — Home-Fetches off-main (Loader wie Stats/Canvas)
- **Ziel**
  - Main-Thread-Stalls beim Suchen/Filtern in `EntitiesHomeView` eliminieren.
- **Betroffene Dateien**
  - `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - Neu: `BrainMesh/Mainscreen/EntitiesHomeLoader.swift` (actor + detached context)
- **Risiko**
  - State-Synchronisation (Snapshot commit) muss sauber sein, sonst UI-Flicker.
- **Erwarteter Nutzen**
  - Spürbar smoother Scroll + Search bei wachsender DB.

### P0.3 — Canvas-Physik billiger machen (Main Thread entlasten)
- **Ziel**
  - Ähnliches „Feel“, aber weniger Main-Thread-Kosten bei großen Graphen.
- **Betroffene Dateien**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- **Risiko**
  - Layout-Dynamik ändert sich; UX testen (besonders Spotlight).
- **Erwarteter Nutzen**
  - Weniger Jank beim Pan/Zoom; bessere Skalierung.
  - Kandidat: Spatial Hash/Grid Bucketing statt Voll-O(N²) Repulsion/Collision pro Tick.

