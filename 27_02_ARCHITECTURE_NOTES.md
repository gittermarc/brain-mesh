# ARCHITECTURE_NOTES — BrainMesh

## Big Files List (Top 15 nach Zeilen)
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **499 Zeilen**
  - Zweck: Background loader: EntitiesHome snapshot + counts cache + search
  - Risiko: Hält Cache + mehrere Fetches; falsche Cache-Invalidation kann stale counts verursachen; actor → cancellation/priority
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **411 Zeilen**
  - Zweck: Background loader: GraphCanvas nodes/edges snapshot (BFS neighborhood/global)
  - Risiko: Kann viel Daten traversieren (maxNodes/maxLinks); Detached Task + ModelContext; muss cancellation sauber halten
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 Zeilen**
  - Zweck: UI: Manage images/media for nodes (gallery/attachments actions)
  - Risiko: Viele Zustände/Sheets; Risiko für View-Invalidations + schwer testbar; Kandidat für Subview-Split
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **388 Zeilen**
  - Zweck: UI: EntitiesHome list/grid, search, sort, sheets; loads via EntitiesHomeLoader
  - Risiko: Komplexer State; viele .task/onChange; Risiko für reload loops / cancellation issues
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388 Zeilen**
  - Zweck: UI: Render/Editing of Details values per attribute
  - Risiko: Dynamic forms + bindings; potentielle Performance bei vielen Feldern/Values; Kandidat für Subview-Split
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **375 Zeilen**
  - Zweck: UI Screen host for GraphCanvas (state, overlays, loaders, navigation)
  - Risiko: Viele @State, koordinierte tasks; hohes invalidation potential; muss Renderpfad clean halten
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **367 Zeilen**
  - Zweck: UI: Bulk link creation flow (duplicate detection, preview, commit)
  - Risiko: Mehrstufiger Flow; correctness risk bei dedupe; viele states
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362 Zeilen**
  - Zweck: UI: Shared node detail section for media gallery
  - Risiko: UI + loader interactions; heavy lists/scroll
- `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **357 Zeilen**
  - Zweck: UI: SF Symbols picker (large list/search)
  - Risiko: Kann sehr viele Rows rendern; Memory/scroll performance
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **344 Zeilen**
  - Zweck: UI: Photo gallery section component
  - Risiko: Scroll/thumbnail rendering; image decode/caching
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — **341 Zeilen**
  - Zweck: UI: 'Alle Verbindungen' screen (potentially large link list)
  - Risiko: Large list; needs pagination/loader; risk of main-thread work
- `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **331 Zeilen**
  - Zweck: UI: Markdown editing accessory / helpers
  - Risiko: Text editing; state churn; keyboard/scroll issues
- `BrainMesh/Attachments/AttachmentImportPipeline.swift` — **326 Zeilen**
  - Zweck: Service: file/video/gallery import + size/compression policy
  - Risiko: I/O heavy; security-scoped URLs; needs strict background usage; edge cases for large files
- `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` — **318 Zeilen**
  - Zweck: UI: Fullscreen photo browser/viewer
  - Risiko: Memory; prefetch; gesture state
- `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` — **317 Zeilen**
  - Zweck: UI: Stats dashboard
  - Risiko: Many cards + loads; if not careful triggers repeated loads; heavy computed layout

## Hot Path Analyse

### Rendering / Scrolling (SwiftUI + Graph)
**GraphCanvas Physik (30 FPS Timer + O(n²) Pair Loops)**
- Datei: BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift
- Gründe (Hotspot):
  - `Timer.scheduledTimer(withTimeInterval: 1/30)` tickt dauerhaft solange `simulationAllowed` true ist.
  - Pair-Loop für Repulsion/Collision: `for i in 0..<simNodes.count` + inner `for j in (i+1)..<simNodes.count` ⇒ worst-case **O(n²)**.
  - Pro Tick werden `positions`/`velocities` als Dictionaries kopiert (`var pos = positions`, `var vel = velocities`) und am Ende wieder in `@State` geschrieben ⇒ viele Re-Renders + Dictionary-Overhead.
- Bereits vorhandene Mitigation:
  - Visibility Gate + Sleep/Idle Stop: `simulationAllowed` + “sleep when idle” Mechanik.

**GraphCanvas Rendering (per-frame Cache-Aufbau)**
- Datei: BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift
- Gründe (Hotspot):
  - `buildFrameCache(...)` baut pro Frame Dictionaries (`screenPoints`, `labelOffsets`, optional outgoing notes map) und iteriert über `nodes` + `drawEdges`.
  - Selection/Zoom beeinflusst zusätzliche Work (Note-Rendering erst ab Zoom/Selection).
- Bereits vorhandene Mitigation:
  - FrameCache + deterministic label offsets; outgoing notes werden vorgefiltert (selection-only).

**GraphCanvas Screen Host (State-Churn)**
- Datei: BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift
- Gründe (Hotspot):
  - Sehr viele `@State` Felder (Nodes/Edges, caches, selection, sheets) → hohes Invalidation-Potential.
  - `positions/velocities` ändern häufig, wodurch Screen-Host-Body oft neu berechnet wird, obwohl eigentlich nur Canvas zeichnen müsste.

**Large Lists**
- SF Symbols Picker:
  - Datei: BrainMesh/Icons/AllSFSymbolsPickerView.swift
  - Risiko: sehr große Item-Zahl → Scroll/Memory; braucht Lazy-Container + filtering off-main (**UNKNOWN**: wie groß das Symbols-Set zur Laufzeit ist, da es vom OS abhängt).
- Connections “All”:
  - Datei: BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift
  - Risiko: potentiell Hunderte Links; ohne Pagination/Loader kann @Query/Filter UI blocken (es existiert aber `NodeConnectionsLoader`, siehe BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift).

### Sync / Storage (SwiftData + CloudKit)
**ModelContainer Setup + Release Fallback**
- Datei: BrainMesh/BrainMeshApp.swift
- Gründe (Hotspot/Risiko):
  - CloudKit Container Init kann fehlschlagen (Entitlements/Signing/iCloud). In Release: Fallback auf local-only → “Sync wirkt kaputt” ohne klares Signal.
  - App refresht Account Status async beim Launch (Task.detached) → gut, aber **keine** aktive “Sync health” Telemetrie vorhanden (nur AccountStatus), siehe BrainMesh/Settings/SyncRuntime.swift.

**External Storage + Predicate-Translatability (Attachments)**
- Dateien: BrainMesh/Attachments/MetaAttachment.swift, BrainMesh/Attachments/AttachmentGraphIDMigration.swift
- Gründe (Hotspot/Risiko):
  - `MetaAttachment.fileData` nutzt `@Attribute(.externalStorage)` → große Blobs.
  - OR-Prädikate (z.B. `graphID == nil || graphID == gid`) können SwiftData in memory filtering zwingen; bei Blobs ist das “katastrophal” (Kommentar in BrainMesh/Attachments/AttachmentGraphIDMigration.swift).
  - Darum existiert die Migration, die `graphID == nil` Records in den aktuellen Graph schiebt.

**Image Storage (synced bytes + local cache)**
- Dateien: BrainMesh/Models/MetaEntity.swift, BrainMesh/Models/MetaAttribute.swift, BrainMesh/ImageStore.swift, BrainMesh/ImageHydrator.swift
- Design:
  - `imageData` synced via SwiftData/CloudKit (klein gehalten).
  - `imagePath` ist lokaler Cache Pointer (Application Support).
  - Hydrator scannt background-context und schreibt deterministische JPEGs (id.jpg).

### Concurrency (MainActor, Task lifetimes, cancellation)
**Actor Loader Pattern**
- Registrierung: BrainMesh/Support/AppLoadersConfigurator.swift
- Typischer Ablauf:
  - Loader actor hält `AnyModelContainer` (Sendable wrapper).
  - UI triggert `loadSnapshot(...)`, Loader erstellt background `ModelContext`, führt Fetches in `Task.detached`.
  - Ergebnis ist DTO Snapshot (value-only) → UI commit in einem Rutsch.

**Cancellation**
- Positiv:
  - EntitiesHomeLoader nutzt `Task.checkCancellation()` (mehrfach) → gut bei “typing/search” Pressure: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift.
  - GraphStatsLoader nutzt `Task.checkCancellation()` im per-graph loop: BrainMesh/Stats/GraphStatsLoader.swift.
- Risiko:
  - GraphCanvasDataLoader enthält keine sichtbaren Cancellation Checks während BFS/Traversal (kein `Task.checkCancellation()`), siehe BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift.
  - Wenn UI schnell zwischen Graphen/Fokus wechselt, kann unnötig Arbeit laufen und später “stale” Snapshots liefern (UI muss tokenisieren/ignore old results).

**Timer + ScenePhase**
- Physik nutzt `Timer.scheduledTimer` (RunLoop) → muss zuverlässig invalidiert werden.
  - Datei: BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift.
- AppRootView enthält bewusst debounced background lock, um System-Picker/FaceID-Flows nicht zu zerstören.
  - Datei: BrainMesh/AppRootView.swift (Kommentar erklärt den ScenePhase Edge Case).

## Refactor Map

### A) Konkrete Splits (Datei → neue Dateien)
1. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
   - Split Vorschlag:
     - `NodeImagesManageView+State.swift` (state + intent)
     - `NodeImagesManageView+Gallery.swift` (gallery UI)
     - `NodeImagesManageView+Attachments.swift` (file/video actions)
     - `NodeImagesManageView+Toolbar.swift`
   - Nutzen: weniger Merge-Konflikte, klarere Verantwortlichkeit, weniger “god view”.

2. `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
   - Split Vorschlag:
     - `NodeDetailsValuesCard+Row.swift` (one field row)
     - `NodeDetailsValuesCard+Formatters.swift` (value formatting)
     - `NodeDetailsValuesCard+Editing.swift` (edit triggers/sheets)
   - Nutzen: besser testbar; reduziert Render-Komplexität.

3. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
   - Split Vorschlag:
     - `GraphCanvasScreen+State.swift` (State structs)
     - `GraphCanvasScreen+Navigation.swift` (sheets/pickers)
     - `GraphCanvasScreen+Loading.swift` existiert bereits; weiter konsequent auslagern.
   - Nutzen: Fokus auf “composition”; weniger versehentliche Invalidation.

### B) Cache-/Index-Ideen (was cachen, Keys, Invalidations)
1. **GraphCanvas Simulation Storage**
   - Datei: BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift
   - Idee:
     - `positions/velocities` als Arrays (Index = node order) statt Dictionaries.
     - `NodeKey → Int` mapping einmal pro Snapshot/Nodes-Change bauen.
   - Invalidations: rebuild mapping bei `nodes` Update, nicht pro tick.

2. **GraphCanvas Repulsion Grid**
   - Datei: BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift
   - Idee:
     - Spatial hashing / grid bins: nur Nachbarn in umliegenden Zellen kollidieren/repellieren.
   - Nutzen: reduziert Pair-Loop von O(n²) in der Praxis dramatisch.

3. **EntitiesHome Counts Cache Policy**
   - Datei: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift
   - Idee:
     - Cache invalidation an domain events koppeln (Entity/Attribute/Link changes) statt nur “time-based”.
   - **UNKNOWN**: ob es bereits ein zentrales Event-System gibt; im Code nur Loader-internal Cache sichtbar.

4. **Search Indices**
   - Dateien: Models + BrainMesh/GraphBootstrap.swift
   - Idee:
     - Dev-only “index audit” um folded fields konsistent zu halten; wichtig bei Migrationen.

### C) Vereinheitlichungen (Patterns, Services, DI)
- `AppLoadersConfigurator` ist bereits das zentrale Pattern (gut). Nächster Schritt:
  - Ein kleines “Loader Protocol” + einheitliche `configure(container:)` Signatur, inklusive “not configured” Fehler.
  - Token-basierte UI-Loads: jeder Screen hält einen `loadGeneration`/`UUID` und ignoriert stale results.
- Repository Layer:
  - **UNKNOWN**: ob du bewusst auf Repositories verzichtest; aktuell dominiert das “Loader+Snapshot”-Pattern.

## Risiken & Edge Cases
- **CloudKit init fails → local-only** (Release-Fallback) kann zu “Daten fehlen auf Gerät 2” führen.
  - Dateien: BrainMesh/BrainMeshApp.swift, BrainMesh/Settings/SyncRuntime.swift.
- **ExternalStorage Blobs + in-memory filtering** (Attachments):
  - Dateien: BrainMesh/Attachments/AttachmentGraphIDMigration.swift, BrainMesh/Attachments/MetaAttachment.swift.
- **ScenePhase Background Glitches** bei System Pickern / FaceID:
  - Datei: BrainMesh/AppRootView.swift (Debounce + grace window).
- **Multi-device / Merge**:
  - **UNKNOWN**: conflict resolution strategy für gleichzeitige Edits an denselben Records (SwiftData CloudKit default).
- **Record size pressure**:
  - Bilder werden als `imageData` gesynct; Attachments als externalStorage. Grenzen müssen enforced werden (maxBytes wird in Detail Views als const genutzt, z.B. in BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift).

## Observability / Debuggability
- Minimal Logging + Timing:
  - Datei: BrainMesh/Observability/BMObservability.swift
  - Kategorien: `BMLog.load`, `BMLog.expand`, `BMLog.physics`.
- Physik loggt Rolling Window (60 Ticks) mit avg/max ms:
  - Datei: BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift.
- Settings zeigt Sync Mode + iCloud AccountStatus:
  - Dateien: BrainMesh/Settings/SyncRuntime.swift, BrainMesh/Settings/SyncMaintenanceView.swift.

## Open Questions (UNKNOWNs gesammelt)
- **SwiftData/CloudKit Konfliktlösung**: gibt es app-spezifische Regeln oder wird Standardverhalten akzeptiert? (**Keine** CKOperationen gefunden.)
- **Distribution/Release Entitlements**: `aps-environment` ist `development` in BrainMesh/BrainMesh.entitlements. Wie ist TestFlight/AppStore Signing geplant?
- **Package Dependencies**: im ZIP keine SPM-Refs gefunden. Gibt es private Packages außerhalb des Repos?
- **Pagination/Virtualisierung** für sehr große Listen (Links, SF Symbols): existiert teilweise Loader-seitig; ist UI-seitig überall korrekt “lazy”?

## First 3 Refactors I would do (P0)
### P0.1 — GraphCanvas Physik: Datenstruktur + Pair-Loop reduzieren
- Ziel: weniger CPU + weniger Re-Renders bei 30 FPS.
- Betroffene Dateien:
  - BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift
  - (optional) BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift (wenn FrameCache an neue Storage angepasst wird)
- Risiko: Mittel (ändert Kern-Interaktion/Feel); braucht visuelle Regression-Tests.
- Erwarteter Nutzen: spürbar flüssiger bei vielen Nodes; bessere Battery; weniger Thermal Throttling.

### P0.2 — GraphCanvasDataLoader: Cancellation + “stale snapshot” Schutz
- Ziel: unnötige Background Arbeit verhindern, bei schnellem Wechsel kein “falsches” Ergebnis committen.
- Betroffene Dateien:
  - BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift
  - BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift (token/generation check beim Apply)
- Risiko: Niedrig–Mittel (logisch klar; Hauptgefahr: edge cases bei Task cancellation).
- Erwarteter Nutzen: weniger Spikes beim Graph-Wechsel; robustere UX.

### P0.3 — Detail Screens: Links lazy-loaden / fetch-limit + “Alle”
- Ziel: Entity/Attribute Detail bei sehr vielen Links nicht blockieren.
- Betroffene Dateien:
  - BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift
  - BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift
  - (optional) BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift als backend für “Alle”
- Risiko: Mittel (kann UX/Sortierung verändern; muss korrekt mit GraphScope funktionieren).
- Erwarteter Nutzen: schnelleres Öffnen von Detail Screens; weniger SwiftData work im UI-Pfad.
