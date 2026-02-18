# BrainMesh — ARCHITECTURE_NOTES

_Last scan: 2026-02-18 (Europe/Berlin)_

Meta:
- Swift files: **159**
- Total Swift LOC (approx, raw line count): **22479**
- Minimum iOS: **26.0** (`BrainMesh.xcodeproj/project.pbxproj`)

---

## Big Files List (Top 15 nach Zeilen)

> Pfad + Zeilen. "Riskant" heisst hier: hohe kognitive Last, mehr Merge-Konflikte, mehr Wahrscheinlichkeit fuer perf/regression Bugs oder Compile-Time Probleme.

1. `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` — **532** Zeilen
2. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift` — **489** Zeilen
3. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **411** Zeilen
4. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **408** Zeilen
5. `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift` — **408** Zeilen
6. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` — **394** Zeilen
7. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **360** Zeilen
8. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` — **359** Zeilen
9. `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` — **348** Zeilen
10. `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **342** Zeilen
11. `BrainMesh/Mainscreen/BulkLinkView.swift` — **325** Zeilen
12. `BrainMesh/Onboarding/OnboardingSheetView.swift` — **319** Zeilen
13. `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` — **316** Zeilen
14. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` — **305** Zeilen
15. `BrainMesh/Mainscreen/EntitiesHomeView.swift` — **299** Zeilen

### Warum diese Dateien riskant sind (kurzer Zweck + konkretes Risiko)

1. `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
   - Zweck: Canvas Drawing (Edges, Labels, Selection Overlay) pro Frame.
   - Risiko: Hot-Path. Jeder unnötige Allocate/Sort/Loop kostet sofort FPS. SwiftUI invalidation kann hier schnell eskalieren.

2. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift`
   - Zweck: "Anhaenge verwalten" Sheet (Paging, Import, Preview, Delete).
   - Risiko: Viele Responsibilities in einer Datei; viele `@State`/Bindings; hoher Regression-Radius.

3. `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
   - Zweck: Off-main Snapshot Load fuer Canvas (Nodes/Edges + Caches).
   - Risiko: Predicate-Translatability + BFS/Filter-Logik; potentielle Memory-Spikes bei grossen Graphen; Concurrency correctness.

4. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
   - Zweck: Manage View fuer Medien/Bilder an Nodes (Listen, Import, Bulk Actions).
   - Risiko: UI + Data + Media Preview in einem; viele State-Pfade (Paging, Selection, Delete).

5. `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift`
   - Zweck: Stats UI Cards (Layout, Charts, Subcomponents).
   - Risiko: Compile-Time / Type-checking; schwer testbar; "simple UI change" kann grosse Diff verursachen.

6. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`
   - Zweck: Connections UI (Preview list + "Alle" sheet) und Loader orchestration.
   - Risiko: Viele conditional branches (NodeKind, Empty/Non-empty states). Performance: große Link-Listen.

7. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
   - Zweck: Medien/Gallery Section in Detailseiten.
   - Risiko: Scrolling/Thumbnail tasks; Disk/Preview I/O; viele states fuer import/progress.

8. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
   - Zweck: Shared Detail Host (Sections zusammensetzen; common state).
   - Risiko: "God file" fuer Detail; jede Erweiterung verlaengert compile time und macht Nebenwirkungen wahrscheinlicher.

9. `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
   - Zweck: Tab-Screen fuer Canvas (State machine + sheets + derived state).
   - Risiko: Viele `onChange`, viele State-Interaktionen; Bugs werden oft als "random" wahrgenommen.

10. `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
    - Zweck: Gallery Grid/Section (Thumbnails, taps -> Browser).
    - Risiko: Rendering + async thumbnail loads; kann schnell viele concurrent tasks starten.

11. `BrainMesh/Mainscreen/BulkLinkView.swift`
    - Zweck: Bulk-Linking UI (Multi-select + create).
    - Risiko: Datenintegritaet (Duplicate links), Performance (viele Nodes), UX state complexity.

12. `BrainMesh/Onboarding/OnboardingSheetView.swift`
    - Zweck: Onboarding flow (pages, actions).
    - Risiko: Weniger perf-kritisch, aber "entry/exit" flows sind regressions-anfällig.

13. `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`
    - Zweck: Vollbild Browser (Paging, gestures).
    - Risiko: Memory (UIImage); gesture conflicts; heavy view tree.

14. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift`
    - Zweck: Highlight UI + editing.
    - Risiko: Viele states/bindings; invalidation bei Editing.

15. `BrainMesh/Mainscreen/EntitiesHomeView.swift`
    - Zweck: Entities/Attributes Home (Search, scope, list).
    - Risiko: Hot path in normal usage; muss smooth bleiben. Positiv: nutzt bereits `EntitiesHomeLoader` Snapshot (off-main).

---

## Hot Path Analyse

### Rendering / Scrolling

#### Graph Canvas Rendering (FPS-kritisch)
- Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- Konkrete Hotspot-Gruende:
  - **Timer-driven 30 FPS Simulation** (`GraphCanvasView.startSimulation()` in `GraphCanvasView+Physics.swift`): Jede Tick-Iteration kann CPU-Budget sprengen.
  - **O(n^2) repulsion loop** in `GraphCanvasView+Physics.swift` (pairwise repulsion zwischen `simNodes`): skaliert schlecht, wenn `physicsRelevant` nicht klein ist.
  - **Per-frame Canvas loops** in `GraphCanvasView+Rendering.swift` (Edges + Nodes + Labels): O(E + V) pro Frame; Path building/geometry ist teuer.
  - **View invalidation**: Viele `@State` Updates (positions/velocities) invalidieren grosse Teile des Canvas; aktuell wird viel ueber Canvas und Caches abgefedert, aber das bleibt ein sensibler Bereich.
- Was schon gut ist (im Code sichtbar):
  - **PhysicsRelevant Set** (Spotlight Physik) in `GraphCanvasView.swift` reduziert `simNodes`.
  - **Sleep/Idle** Mechanik (`physicsIsSleeping`) spart CPU, wenn Layout settled.
  - **FrameCache** in `GraphCanvasView+Rendering.swift` vermeidet repeated transforms und label measurements.
  - **Cancellable load** in `GraphCanvasScreen.scheduleLoadGraph` verhindert stale commits (`GraphCanvasScreen.swift`).

#### Listen mit Thumbnails (I/O + Task fan-out)
- Dateien:
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift`
  - `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- Konkrete Hotspot-Gruende:
  - **Many small async tasks** pro Cell (thumbnail loads) -> Gefahr von unbounded concurrency.
  - **QuickLook/AV thumbnailing** kann heavy sein (CPU + Disk), auch wenn `AsyncLimiter` bremst.
  - **Disk cache misses**: beim schnellen Scrollen kann die Cache-Hit-Rate kurz einbrechen -> spuerbare Jank.
- Was schon gut ist:
  - `AttachmentThumbnailStore` hat **Inflight Dedup** + **AsyncLimiter** + Disk cache.
  - `MediaAllLoader` liefert DTOs ohne `fileData` und paginiert (FetchLimit, `startAfter`) -> gut fuer grosse Libraries.

#### Home / Pickers (frequent, muss instant sein)
- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHomeView.swift` + `EntitiesHomeLoader.swift`
  - `BrainMesh/Mainscreen/NodePickerView.swift` + `NodePickerLoader.swift`
- Konkrete Hotspot-Gruende:
  - Home & Pickers sind "oft genutzt" -> jede 50ms Blockade fuehlt sich schlimm an.
- Was schon gut ist:
  - Off-main Loader mit Snapshot DTO.
  - Counts werden in einem Batch gezählt (`EntitiesHomeLoader.fetchAttributeCountsByEntity`).

### Sync / Storage

#### SwiftData + CloudKit (automatisch)
- Dateien:
  - `BrainMesh/BrainMeshApp.swift` (ModelContainer config, CloudKit fallback)
  - `BrainMesh/BrainMesh.entitlements` (iCloud/CloudKit container)
  - `BrainMesh/Info.plist` (remote-notification)
- Risiken / Tradeoffs:
  - SwiftData + CloudKit ist "automatisch", aber Debugging von Konflikten/Sync-Latenzen ist schwer ohne eigene Observability.
  - Release fallback auf local-only bei Container-Error ist gut fuer Crashfreiheit, aber:
    - **UNKNOWN**: wie wird dem User dieser Zustand angezeigt? (kein klarer UI-hook im Code gefunden)

#### External Storage (Blob Payloads)
- Modelle:
  - `MetaEntity.imageData`, `MetaAttribute.imageData` (`BrainMesh/Models.swift`)
  - `MetaAttachment.fileData` (`BrainMesh/Attachments/MetaAttachment.swift`)
- Risiken:
  - Bloecke / grossen Data payloads koennen CloudKit Limits treffen; du hast bereits eine JPEG-Pipeline (`BrainMesh/Images/ImageImportPipeline.swift`), das ist ein bewusstes Gegenmittel.
  - Wenn eine View aus Versehen `fileData` in einer List Row anfässt, ist das sofort ein perf bug (zum Glueck: `MediaAllLoader` DTO vermeidet das).

#### Migration (graphID nil) und Cache-Hydration
- Dateien:
  - `BrainMesh/GraphBootstrap.swift`
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
- Konkrete Hotspot-Gruende:
  - Migration laeuft auf `@MainActor` (`GraphBootstrap.migrateLegacyRecordsIfNeeded`): bei vielen Records kann Launch spuerbar werden.
  - `ImageHydrator` laeuft ebenfalls `@MainActor` und macht `fetch` + loop + disk writes (disk writes sind async, fetch/iteration nicht).
- Was schon gut ist:
  - Migration ist guarded (Flag in `@AppStorage`).
  - Attachment Hydration ist actor/detached und concurrency-limited.

### Concurrency

#### Pattern: Actor Loader + detached ModelContext
- Beispiele:
  - `EntitiesHomeLoader`, `NodePickerLoader`, `NodeConnectionsLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `MediaAllLoader`
- Positiv:
  - Minimiert MainActor contention.
  - DTOs sind value-only; keine SwiftData Models ueber Threads.
- Konkrete Risiken:
  - `AnyModelContainer` ist `@unchecked Sendable` (`BrainMesh/BrainMeshApp.swift`).
    - Das ist bewusst, aber es heisst: Thread-safety muss durch Disziplin garantiert sein (nur `ModelContainer` wird geteilt, `ModelContext` pro Task neu).
  - `Task.detached` ist leicht "unbounded" zu starten. Der Code nutzt aber oft `.task(id:)` oder Inflight-Dedup (gut).
  - Cancellation: teilweise sehr sauber (`GraphCanvasScreen.loadTask?.cancel`, `GraphStatsLoader` checkCancellation). Trotzdem:
    - **UNKNOWN**: Gibt es flows, die detached tasks feuern ohne UI-lifetime binding (z.B. bulk thumbnailing)? -> profiling noetig.

---

## Refactor Map

### Konkrete Splits (Datei -> neue Dateien)

> Ziel: Ownership klarer, weniger Merge-Konflikte, geringere Compile-Time, kleinere "hot" diffs.

- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift`
  - -> `NodeAttachmentsManageSheet.swift` (Host + toolbar + paging state)
  - -> `NodeAttachmentsManageRow.swift` (Row UI + thumbnail request)
  - -> `NodeAttachmentsManageImport.swift` (import flows, progress integration)
  - -> `NodeAttachmentsManagePreview.swift` (QuickLook / video player sheet)

- `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift`
  - -> `StatsCardBase.swift` (Card shell)
  - -> `StatsKPIGrid.swift`
  - -> `StatsMiniCharts.swift` (Sparkline, density)
  - -> `StatsTopLists.swift` (Top nodes/media lists)

- `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - -> `GraphCanvasScreen+StateMachine.swift` (workMode, lens, selection, pinned)
  - -> `GraphCanvasScreen+Sheets.swift` (graph picker, focus picker, inspector)
  - -> `GraphCanvasScreen+SelectionPrefetch.swift` (prefetchSelectedFullImage, selection image cache)

- `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - -> `PhotoGalleryGrid.swift` (Grid + cell)
  - -> `PhotoGalleryCell.swift` (thumb loading + placeholders)
  - -> `PhotoGalleryRouting.swift` (open browser, selection binding)

### Cache-/Index-Ideen (konkret)

- Graph Canvas
  - Cache adjacency map fuer `edges` (Key -> [neighbors]) im Screen derived state statt jedes Mal neu filtern.
    - Files: `GraphCanvasScreen+Derived.swift`, `GraphCanvasScreen+Expand.swift`
  - Physics: spatial bucketing (grid) fuer repulsion/collision um O(n^2) zu reduzieren.
    - File: `GraphCanvasView+Physics.swift`

- Attachments/Thumbnails
  - Persistente "thumbnail versioning" bei Content replace:
    - invalidate thumb cache wenn `byteCount`/`updatedAt` sich aendert (**UNKNOWN**: es gibt aktuell kein `updatedAt` Feld am Attachment)
  - Memory cache size tuning (NSCache countLimit) fuer `AttachmentThumbnailStore` und `ImageStore`.

- Stats
  - Snapshot caching pro graphID + "dirty flags" (invalidate bei create/delete) statt immer full recompute.
    - Files: `Stats/GraphStatsLoader.swift`, `Stats/GraphStatsService/*`
  - Compute in batches (du machst das teilweise schon): vermeiden, pro graphID separate fetches zu machen.

### Vereinheitlichungen (Patterns, Services, DI)

- "Shared singletons" sind aktuell verbreitet (`...Loader.shared`, `GraphSession.shared`).
  - Vorteil: einfach.
  - Tradeoff: schwer testbar und lifetime nicht explizit.
  - Option:
    - zentraler `AppServices` Container als `@EnvironmentObject` (nur value references / actors).
    - Mindestens: eine Datei `Support/Services.swift` die alle shared dependencies zentral listet.

- Wiederkehrende Konzepte:
  - "System modal guard" (`Support/SystemModalCoordinator.swift`) wird in mehreren Media flows verwendet.
  - Empfehlung: einen kleinen Helper/Modifier bereitstellen, der system modal begin/end konsistent setzt.

---

## Risiken & Edge Cases

### Datenverlust / Migration
- graphID Migration (`GraphBootstrap.swift`, `AttachmentGraphIDMigration.swift`):
  - Risiko: falscher graphID bei Legacy Records, falls Owners fehlen oder Daten inkonsistent sind.
  - Mitigation im Code: Attachment migration faellt auf first graph zurueck, wenn owner missing (bewusst, aber sollte in Logs sichtbar sein).

### Offline / Multi-Device
- CloudKit sync ist "automatic".
- **UNKNOWN**: Konfliktstrategie, Merge rules, und ob User Hinweise bekommt.
- Local cache pointer fields:
  - `MetaEntity.imagePath`, `MetaAttribute.imagePath`, `MetaAttachment.localPath` sind persistiert und syncen mit.
  - Risiko: "path is local" kann auf neuem Device unsinnig sein.
  - Mitigation: du nutzt deterministische Namen und kannst local files hydratisieren, trotzdem bleibt das ein area to watch.

### Security / FaceID Interaktionen
- `AppRootView` nutzt `SystemModalCoordinator` um nicht zu relocken waehrend system modals (Photos/Hidden Album) offen sind.
  - Files: `AppRootView.swift`, `Support/SystemModalCoordinator.swift`, `NotesAndPhotoSection.swift`
- Risiko: wenn irgendwo `systemModal.begin()`/`end()` nicht symmetrisch ist, kann Auto-Lock aus dem Tritt kommen.

### Performance cliffs
- Canvas physics scaling (viele nodes) bleibt der groesste "cliff".
- Thumbnail generation fuer viele Videos kann ebenfalls heavy werden, obwohl limiter existiert.

---

## Observability / Debuggability

- `BrainMesh/Observability/BMObservability.swift`
  - `BMDuration` (ms measurement) + `BMLog` categories (load, etc.)
- Bereits gut:
  - Canvas loading logs in `GraphCanvasScreen+Loading.swift`
  - Loader "configured" debug logs (z.B. `NodePickerLoader`)
- Erweiterungen (konkret):
  - Ein "perf overlay" in Debug: FPS, physics tick ms, thumbnail queue length.
    - Daten sind teils schon da (`physicsTickCounter`, `physicsTickMaxNanos` in `GraphCanvasView.swift`)
  - Log points fuer CloudKit fallback (`BrainMeshApp.swift`) sichtbar im UI (Settings) statt nur internal state.

---

## Open Questions (UNKNOWN gesammelt)

1. **SPM / externe Dependencies**: keine klaren Package-References in `project.pbxproj` gefunden. Falls du lokale Packages nutzt: Welche, und warum?
2. **Secrets Handling**: keine `.xcconfig` / injection files gefunden. Gibt es APIs/Keys, die ausserhalb liegen?
3. **CloudKit Konflikt-Handling**: verlaesst du dich komplett auf SwiftData defaults, oder gibt es (geplant) Konflikt-UX?
4. **User-visible Sync Status**: `cloudEnabled` Flag existiert (`BrainMeshApp.swift`). Wird das irgendwo angezeigt? Falls nein: soll es?
5. **Per-Entity/Attribute Lock**: `MetaEntity` und `MetaAttribute` haben Lock-Felder (`Models.swift`), aber im UI wird primaer Graph-Lock benutzt (`Security/*`). Sind die Felder future work oder legacy?
6. **Persistierte Cache-Pfade**: Soll `imagePath`/`localPath` wirklich syncen (oder besser `@Transient`/computed)?
7. **GraphCanvasDataLoader Predicate-Translatability**: `contains` auf ID-Arrays in `#Predicate` kann je nach SwiftData Version unterschiedlich optimiert werden. Hast du Messungen/Profiling fuer grosse Graphen?

---

## First 3 Refactors I would do (P0)

### P0.1 — ImageHydrator off-main + incremental batching
- Ziel:
  - Launch/Graph-switch smoother machen, indem Image-Hydration nicht am MainActor "fetch-looped".
- Betroffene Dateien:
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/BrainMeshApp.swift` (optional: configure wie andere actors)
  - ggf. `BrainMesh/AppRootView.swift` (call site)
- Risiko: **niedrig-mittel**
  - Risiko sind Concurrency mistakes (ModelContext thread confinement). Pattern existiert bereits (AttachmentHydrator).
- Erwarteter Nutzen:
  - weniger UI stalls beim Start / nach Sync; bessere Battery, wenn viele images vorhanden sind.

### P0.2 — Node Attachments Manage Sheet split + klare Ownership
- Ziel:
  - Lesbarkeit/Wartbarkeit massiv verbessern; leichteres Iterieren (thumbnails, sorting, import UI).
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift`
  - ggf. `BrainMesh/Attachments/MediaAllLoader.swift` (API remains)
  - ggf. `BrainMesh/Attachments/AttachmentThumbnailStore.swift` (nur falls UI needs)
- Risiko: **niedrig**
  - Split-only kann mechanisch sein, Verhalten unveraendert.
- Erwarteter Nutzen:
  - weniger Merge-Konflikte, weniger "compiler unable to type-check", schnellere Feature-Entwicklung.

### P0.3 — GraphCanvas Physics: O(n^2) entschärfen (minimaler Schritt zuerst)
- Ziel:
  - CPU cliffs bei grossen Graphen reduzieren, ohne das gesamte Layout zu "neu erfinden".
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - ggf. `BrainMesh/GraphCanvas/GraphCanvasView.swift` (sleep/wake triggers)
- Risiko: **mittel**
  - Physik-Aenderungen koennen Layout-Gefuehl aendern; Bugs sind schwerer zu debuggen.
- Erwarteter Nutzen:
  - stabilere FPS und weniger Battery drain bei grossen Graphen (insb. wenn `physicsRelevant` nicht klein ist).
- Konkreter erster Schritt (klein, testbar):
  - Spatial bucketing fuer repulsion/collision (nur Nachbar-Zellen vergleichen) oder harte cap fuer `simNodes` wenn `physicsRelevant` nil.
