# ARCHITECTURE_NOTES.md

## Big Files List (Top 15 nach Zeilen)
> Quelle: `find BrainMesh -name "*.swift"` + line count in diesem ZIP.

 1. `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **499** Zeilen
 2. `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **474** Zeilen
 3. `GraphCanvas/GraphCanvasDataLoader.swift` — **442** Zeilen
 4. `Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410** Zeilen
 5. `Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **404** Zeilen
 6. `Mainscreen/Details/NodeDetailsValuesCard.swift` — **388** Zeilen
 7. `Mainscreen/BulkLinkView.swift` — **367** Zeilen
 8. `Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362** Zeilen
 9. `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift` — **359** Zeilen
10. `Icons/AllSFSymbolsPickerView.swift` — **357** Zeilen
11. `PhotoGallery/PhotoGallerySection.swift` — **344** Zeilen
12. `Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — **341** Zeilen
13. `Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **331** Zeilen
14. `Attachments/AttachmentImportPipeline.swift` — **326** Zeilen
15. `PhotoGallery/PhotoGalleryBrowserView.swift` — **318** Zeilen

### Warum riskant? (Heuristik)
- Hohe Zeilenzahl korreliert in SwiftUI häufig mit: zu viel State in einem View, viele Responsibilities, schwerere Re-Renders, Debuggability-Probleme.
- In diesem Projekt sind viele große Files bereits „halb-splitted“ (z.B. GraphCanvas), aber einige Hotspots bleiben (Loaders/Search, Detail Screens).

## Hot Path Analyse

### Rendering / Scrolling
#### Graph Canvas Rendering
- **`GraphCanvas/GraphCanvasView/GraphCanvasView.swift`**: Rendering über `Canvas { renderCanvas(...) }` + gestengetriebene Updates.
  - Hotspot-Grund: `positions`/`velocities` ändern sich pro Tick → viele SwiftUI invalidations (Canvas re-render).
- **`GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`**: 30 FPS `Timer` + O(n²) Repulsion Pair-Loop (`for i in 0..<simNodes.count` + `for j in i+1..<...`).
  - Hotspot-Grund: CPU-lastige Simulation; wächst quadratisch mit Node-Anzahl. Mit „Spotlight“ wird `simNodes` reduziert, aber Global-Graph kann trotzdem teuer sein.
- **Mitigation bereits vorhanden**:
  - Simulation Gate `simulationAllowed` + Sleep-Mechanik (stoppt Timer nach Idle).
  - `GraphCanvasScreen` cached derived state (`drawEdgesCache`, `lensCache`, `physicsRelevantCache`) um per-frame Work zu reduzieren.

#### Entities Home Lists
- **`Mainscreen/EntitiesHome/EntitiesHomeView.swift`**: UI rendert große Listen (List + LazyVStack) und nutzt `.task(id: taskToken)` zum Reload.
- **`Mainscreen/EntitiesHome/EntitiesHomeList.swift`**: Card-Mode nutzt `ScrollView` + `LazyVStack` (gut für Performance), List-Mode nutzt `List` (UITableView/UICollectionView intern).
- Hotspot-Grund: häufige Reloads beim Tippen + Sortieren + Counts; mitigiert durch Debounce + Loader off-main.

#### Detail Screens / Media
- **`Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`** und **`Mainscreen/NodeDetailShared/NodeImagesManageView.swift`**: potentielle Scrolling-Hotspots (Thumbnails, Attachments, File Previews).
  - Grund: Bild-/Attachment-Hydration + Thumbnailing kann in Zellen auftreten → Risiko von I/O im Scroll-Pfad.
- **`PhotoGallery/PhotoGallerySection.swift`**: `@Query` für Gallery Images + `.task` Migration beim Erscheinen.
  - Grund: Migration/Fetch im UI-Lifecycle; wenn groß, kann es UI stören (auch wenn SwiftData intern optimiert).

### Sync / Storage
- **`BrainMeshApp.swift`**: erstellt CloudKit-ModelContainer und setzt `SyncRuntime` Mode; in DEBUG `fatalError` bei CloudKit init failure, in Release fallback auf local-only.
- **`GraphBootstrap.swift`**: Migration/Backfill im `@MainActor` Startup (`AppRootView.bootstrapGraphing()`).
  - Hotspot-Grund: mögliche Fetches über alle Entities/Attributes/Links bei Legacy- oder Backfill-Bedarf. Guarded über „fetchLimit = 1“ Checks, aber der eigentliche Migration-Pass kann groß werden.
- **`Attachments/MetaAttachment.swift`**: `fileData` als `.externalStorage` (SwiftData verwaltet Asset-like Storage).
  - Risiko/Tradeoff: große Datenmengen können CloudKit quota/latency beeinflussen; Preview-Caching nötig.

### Concurrency
#### Patterns im Projekt
- Viele Loader/Hydrators sind `actor` und erstellen **eigene** kurzlebige `ModelContext` Instanzen off-main (z.B. `EntitiesHomeLoader`, `GraphCanvasDataLoader`).
- UI bekommt value-only Snapshots; Navigation/Mutations passieren im MainActor `ModelContext`.

#### Risiken/Hotspots
- **`Task.detached`** taucht mehrfach auf (z.B. `Stats/GraphStatsLoader.swift`, `ImageHydrator.swift`, `Attachments/AttachmentHydrator.swift`, `Support/AppLoadersConfigurator.swift`, `Mainscreen/LinkCleanup.swift`).
  - Grund: Detached Tasks erben keine Cancellation von UI-Lifetimes → Gefahr von „work after user left screen“, unnötige CPU/I/O, stale results.
- **Stale-Result Handling**: GraphCanvas hat ein Token-System (`GraphCanvasScreen.swift` → `currentLoadToken`) + `loadTask` Cancellation. Das Pattern ist in Stats/Hydrators nicht durchgängig sichtbar.
- **Sendability**: `AnyModelContainer` + `@unchecked Sendable` Snapshots sind pragmatisch, aber erfordern Disziplin (kein `@Model` im Snapshot).

## Refactor Map

### Konkrete Splits (View → Subviews / Extensions)
- `Mainscreen/EntitiesHome/EntitiesHomeView.swift` (~404 Zeilen)
  - Split-Idee: `EntitiesHomeView+State.swift` (State/Bindings), `EntitiesHomeView+Toolbar.swift` (Toolbar/Sheets), `EntitiesHomeView+EmptyStates.swift` (Empty/Error), `EntitiesHomeView+Reload.swift` (reload/taskToken).
- `Mainscreen/EntityDetail/EntityDetailView.swift` (~317 Zeilen)
  - Split-Idee: „Header“, „Highlights Row“, „Connections Section“, „Attachments/Gallery“, „Details Schema/Values“ als eigene Subviews.
- `Mainscreen/BulkLinkView.swift` (~367 Zeilen)
  - Split-Idee: Wizard Steps (Pick Source/Targets, Options, Review/Commit) in einzelne Views, Loader/Validation getrennt.
- `Icons/AllSFSymbolsPickerView.swift` (~357 Zeilen)
  - Split-Idee: Search + Paging + Grid in eigene Subviews/Models; langfristig vordefinierte curated symbol sets.

### Cache-/Index-Ideen
- **EntitiesHome Link-Note Search** (`Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`)
  - Problem: Bei Link-Note Treffer werden endpoints per-ID einzeln gefetched (loop über `entityIDs`/`attributeIDs`).
  - Idee: Batch Fetch in Chunks (z.B. 50 IDs) und dann in-memory join. Wenn `#Predicate` `contains` bei UUID arrays „unreliable“ ist, kann man chunked fetch via mehrere OR-Prädikate bauen (Tradeoff: Predicate size).
- **GraphCanvasDataLoader** (`GraphCanvas/GraphCanvasDataLoader.swift`)
  - BFS Hop Queries nutzen `frontierIDs.contains(...)` im Predicate. Für große Frontiers könnte das langsam werden.
  - Idee: Begrenze Frontier-Größe (top-K by recency) oder verwende 2-step: fetch candidate links by graphID + kind + createdAt window und filter dann in-memory (Tradeoff: oversampling).
- **ImageStore/AttachmentStore**
  - InFlight dedupe existiert (ImageStore). Ähnliches Pattern bei Attachments ist bereits in `AttachmentHydrator` (`inFlight`).
  - Idee: Unified „DiskCache“ helper in `Support/` für Metrics, cleanup, file URL building.

### Vereinheitlichungen (Patterns/DI)
- Loader-Konfiguration: zentral in `Support/AppLoadersConfigurator.swift` (gut).
- Konsistenz-Idee: *alle* background Jobs (Stats, Hydrators, Rename) sollten Cancellation-aware sein und idealerweise keine detached tasks verwenden, wenn sie UI-gebunden sind.
- DI/Testing: Aktuell sind viele Singletons (`.shared`). Für Tests könnte man Protokolle/Factories in `Support/` einziehen. **UNKNOWN**, ob Tests ernsthaft genutzt werden (Test targets existieren, aber Inhalt im ZIP nicht analysiert).

## Risiken & Edge Cases
- **CloudKit Fallback**: In Release wird bei CloudKit init failure local-only genutzt (`BrainMeshApp.swift`). Risiko: User erwartet Sync, sieht aber lokalen Store. UI zeigt StorageMode in Settings (gut).
- **Migration/Backfill Kosten**: `GraphBootstrap.migrateLegacyRecordsIfNeeded` und `.backfillFoldedNotesIfNeeded` können bei großen Datensätzen merklich sein (läuft im MainActor Startup).
- **Daten-Duplikate**: `GraphPickerSheet.swift` deduped Graphs (`GraphDedupeService.removeDuplicateGraphs`). Das deutet auf mögliche iCloud Merge/Sync Edge Cases hin.
- **Large Attachments**: `MetaAttachment.fileData` external storage + local cache; Risiko: Speicher/Quota, App Support wächst; klare „Clear Cache“ Flows nötig.
- **Graph Physics**: Für sehr große Graphen kann O(n²) Repulsion CPU/Battery belasten; capping/spotlight mindert, aber worst case bleibt.
- **Security UX vs System Modals**: `AppRootView.swift` debounced background lock, um Photos/Hidden album FaceID edge case zu vermeiden. Gute Defensive, aber komplex (testen!).

## Observability / Debuggability
- `Observability/BMObservability.swift`: Logger Kategorien (load/expand/physics) + `BMDuration` Timer.
- Graph Physics loggt Rolling Window (60 ticks) in `GraphCanvasView+Physics.swift` (`BMLog.physics.debug(...)`).
- Erweiterungsidee:
  - EntitiesHomeLoader/GraphCanvasDataLoader/GraphStatsService: debug-only timings + row/node counts loggen (ähnliche Rolling Windows, keine Log-Spam).
  - Repro Scripts: „Großer Graph“ Fixtures (Test-Daten Generator) **UNKNOWN** (nicht gefunden).

## Open Questions (UNKNOWN)
- Gibt es explizite Konfliktauflösung/merge policy für SwiftData/CloudKit? (Keine eigene Policy im Code gefunden.)
- Wie werden StoreKit Produkt-IDs in Release gesetzt? (`Info.plist` enthält Default "01"/"02".)
- Gibt es Performance Targets (z.B. max nodes/links) aus Product Requirements? (Knobs existieren in GraphCanvasScreen, aber „warum diese Werte“ ist nicht dokumentiert.)
- Werden Tests/UITests aktiv genutzt? (Targets existieren, Testquellcode wurde nicht ausgewertet.)
- Existiert ein Analytics/Crash Reporting Setup? (Nicht gefunden.)

## First 3 Refactors I would do (P0)

### P0.1 — Cancellation & Detached-Task Cleanup (Stats + Hydrators)
- **Ziel:** Background Work soll UI-Lifetimes respektieren (kein unnötiges Rechnen/I/O nach Tab-Wechsel), Cancellation sauber propagieren.
- **Betroffene Dateien:**
  - `Stats/GraphStatsLoader.swift`
  - `ImageHydrator.swift`
  - `Attachments/AttachmentHydrator.swift`
  - `Support/AppLoadersConfigurator.swift`
  - `Mainscreen/LinkCleanup.swift (NodeRenameService)`
- **Risiko:** Mittel: Concurrency-Refactor; Gefahr von Deadlocks/Regression, wenn man Actor-Isolation falsch anfasst.
- **Erwarteter Nutzen:** Weniger CPU/I/O im Hintergrund, bessere Responsiveness beim schnellen Wechsel, weniger „stale commits“.

### P0.2 — EntitiesHome Link-Note Search: Batch Resolve statt N+1
- **Ziel:** Bei Link-Note Treffern keine per-ID Fetch Schleifen, sondern batch/chunked fetch + join.
- **Betroffene Dateien:**
  - `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- **Risiko:** Niedrig–Mittel: Nur Search Path; erfordert sorgfältiges Predicate-Chunks + Tests für correctness.
- **Erwarteter Nutzen:** Spürbar schnellere Suche bei vielen Links + weniger SwiftData overhead.

### P0.3 — Graph Physics Scaling (große Graphen)
- **Ziel:** Physik-Simulation skalierbarer machen (O(n²) begrenzen), ohne UX einzubrechen.
- **Betroffene Dateien:**
  - `GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift (maxNodes/maxLinks knobs)`
- **Risiko:** Mittel–Hoch: Algorithmische Änderung kann Layout/Feel beeinflussen.
- **Erwarteter Nutzen:** Bessere Battery/CPU, weniger frame drops, robustere Performance bei großen Datenmengen.
