# BrainMesh — ARCHITECTURE_NOTES.md

## Big Files List (Top 15 nach Zeilen)
> Quelle: Zeilenzählung aller `*.swift` unter `BrainMesh/BrainMesh/BrainMesh/`.

| # | Datei | Zeilen | Zweck (kurz) | Warum riskant |
|---:|---|---:|---|---|
| 1 | `Mainscreen/Details/DetailsSchemaBuilderView.swift` | 725 | UI zum Konfigurieren des Details‑Schemas pro Entität (Felder anlegen, sortieren, pinnen, Templates). | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 2 | `Mainscreen/NodeDetailShared/MarkdownTextView.swift` | 661 | UIKit‑basierter Markdown Editor/Viewer (UIViewRepresentable) inkl. Accessory/Commands; zentral im Notes‑Flow. | UIKit Bridge + InputAccessory + Selection/Undo; MainThread‑sensitiv, schwierig zu debuggen. |
| 3 | `Mainscreen/EntitiesHomeView.swift` | 625 | Tab “Entitäten”: Suche, Sortierung, Graph Picker, List/Grid, Navigation zu Entity Detail, Delete/Actions. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 4 | `GraphCanvas/GraphCanvasView+Rendering.swift` | 532 | Canvas‑Rendering: Node/Edge Drawing, Labels, Selection UI; wird pro Tick/Interaction invalidiert. | Render‑Hotpath; häufige Invalidations + komplexes Drawing → Performance/Jank‑Risiko. |
| 5 | `Models.swift` | 515 | SwiftData Modelle + Domain enums/helpers (BMSearch, NodeKind) + Details Schema/Value. | Schema‑Änderungen wirken auf Migration/CloudKit; Fehler hier sind high impact. |
| 6 | `Mainscreen/EntityDetail/EntityAttributesAllListModel.swift` | 510 | State/Derived Data für “Alle Attribute” Liste (Search/Sort/Grouping), vermutlich inkl. SwiftData Fetch/Predicate. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 7 | `Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | 478 | Core UI für Node Detail (Entity/Attribute): Header, Notes, Actions, verschiedene Subsections. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 8 | `Mainscreen/EntityDetail/EntityDetailView+AttributesSection.swift` | 460 | Attributes‑Sektion in Entity Detail: Preview, “Alle” Flow, Sort/Filter, Add Attribute. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 9 | `Settings/Appearance/AppearanceModels.swift` | 430 | Theming/Display‑Settings Modelle (Presets, Density, Farben) + viele Options. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 10 | `GraphCanvas/GraphCanvasDataLoader.swift` | 411 | Actor: lädt Graph‑Snapshot (Nodes/Edges/Neighborhood), computes Lens/Spotlight; heavy fetch/compute off‑main. | Background‑Fetch/Compute; Cancel/Debounce/Thread‑Safety muss korrekt sein, sonst Battery/Leaks/Stalls. |
| 11 | `Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 410 | “Bilder verwalten” UI: Gallery/Import/Deletion; triggert Image hydration/IO. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 12 | `Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | 394 | Connections UI: Links anzeigen/erstellen/“Alle”; nutzt NodeConnectionsLoader. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 13 | `Mainscreen/EntitiesHomeLoader.swift` | 362 | Actor: liefert EntitiesHome Snapshot (Rows + Counts), implements debounce/caching. | Background‑Fetch/Compute; Cancel/Debounce/Thread‑Safety muss korrekt sein, sonst Battery/Leaks/Stalls. |
| 14 | `Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 362 | Media Gallery Sektion in Node Detail (Fotos/Videos/Anhänge), inkl. Navigation zu “Alle”. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |
| 15 | `Stats/StatsComponents/StatsComponents+Cards.swift` | 361 | Stats UI Cards/Layouts; viele View‑Builder und Formatierung. | Große Compile Unit + hoher Merge‑Konflikt‑ und Regression‑Surface; Änderungen invalidieren viele Views/Logik gleichzeitig. |


---

## Hot Path Analyse

### Rendering / Scrolling

#### 1) Graph Canvas (Rendering + Simulation)
Betroffene Dateien:
- Rendering: `GraphCanvas/GraphCanvasView+Rendering.swift`
- Simulation: `GraphCanvas/GraphCanvasView+Physics.swift`
- Data loading: `GraphCanvas/GraphCanvasDataLoader.swift`
- Screen glue: `GraphCanvas/GraphCanvasScreen.swift`

Warum Hotspot:
- **30 FPS Timer auf dem Main Thread**: `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, ...)` in `GraphCanvasView+Physics.swift` ruft `stepSimulation()` auf.
- `stepSimulation()` enthält **O(n²) Pair‑Loop** für Repulsion/Collisions (`for i in 0..<simNodes.count` + inner loop `j`).
- Jede Tick‑Iteration schreibt in `positions`/`velocities` (State) → SwiftUI invalidiert Rendering‑Pfad.

Mitigations, die bereits drin sind:
- **Sleep/Idle**: Timer stoppt nach “settled layout” (`idleTicksNeeded` ~3s).
- **Spotlight**: optional nur relevante Nodes simulieren (`physicsRelevant` / `physicsEdges`).

Konkrete Risiken:
- Große Graphen + Explore Mode: CPU‑Spikes, Input‑Lag, Batterie.
- MainActor contention: gleichzeitig Sheets/Inspector/UI‑Updates.

#### 2) Entities Home (Search + List/Grid)
Betroffene Dateien:
- `Mainscreen/EntitiesHomeView.swift`
- `Mainscreen/EntitiesHomeLoader.swift`

Warum Hotspot (potenziell):
- Typing → `.task(id: taskToken)` + Debounce; Reload kann häufig laufen.
- Loader liefert Snapshot off‑main (gut), **aber** Counts‑Berechnung fetcht komplette Tabellen:
  - `computeAttributeCounts(...)` fetcht alle `MetaAttribute` eines Graphs und zählt in memory.
  - `computeLinkCounts(...)` fetcht alle `MetaLink` eines Graphs.
  - Beides in `Mainscreen/EntitiesHomeLoader.swift`.

Konkreter Grund:
- “heavy sort/aggregation” + “full table scan” pro Graph bei Count‑Features oder Sort‑Optionen.

#### 3) Notes / Markdown Editor
Betroffene Dateien:
- `Mainscreen/NodeDetailShared/MarkdownTextView.swift`
- `Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
- `NotesAndPhotoSection.swift`

Warum Hotspot:
- UIKit ↔ SwiftUI Bridge, Editor‑State, InputAccessory/Undo/Redo.
- Jede Text‑Änderung kann SwiftUI invalidieren, wenn Binding/State nicht sauber getrennt ist.
- Risiko von “MainActor contention” bei gleichzeitigen Save/Hydration‑Tasks.

#### 4) Media Management (Bilder/Anhänge/Thumbnails)
Betroffene Dateien:
- `Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
- `Attachments/AttachmentThumbnailStore.swift`
- `Attachments/AttachmentHydrator.swift`
- `ImageHydrator.swift`, `ImageStore.swift`

Warum Hotspot:
- Thumbnails + Disk I/O + ggf. Video‑Meta (Duration/Preview) sind teuer.
- Wenn UI “Alle Medien” viele Items lädt, besteht Risiko von:
  - “unbounded Task fan‑out”
  - “Disk thrash” (viele kleine Reads/Writes)
  - “MainActor contention” wenn irgendwas versehentlich sync im `body` passiert

---

### Sync / Storage

Betroffene Dateien:
- Container: `BrainMeshApp.swift`
- Sync status: `Settings/SyncRuntime.swift`
- Migration/Repair: `GraphBootstrap.swift`, `Attachments/AttachmentGraphIDMigration.swift`
- Media: `Images/ImageImportPipeline.swift`, `ImageHydrator.swift`, `Attachments/*`

Wichtige Punkte:
- SwiftData Container wird mit `ModelConfiguration(... cloudKitDatabase: .automatic)` erstellt (`BrainMeshApp.swift`).
- **DEBUG: kein Fallback** → CloudKit muss korrekt signiert/konfiguriert sein, sonst App startet nicht.
- Medien‑Design reduziert CloudKit‑Pressure:
  - Hauptbild: `ImageImportPipeline.prepareJPEGForCloudKit(...)` Ziel ~280 KB.
  - Gallery: Ziel ~2.2 MB.
  - Attachments: `@Attribute(.externalStorage)` in `MetaAttachment.fileData` (asset‑ähnlich).

Risiken / Edge Cases:
- **Record size pressure** (trotz Kompression), insbesondere wenn `imageData` für viele Nodes gesetzt ist.
- **Duale Wahrheit**: `imageData` synced, `imagePath` cache. Crash/Fail beim Disk write ist toleriert (“CloudKit sync still works via imageData”), aber:
  - Cache kann stale sein → Hydrator muss konsistent bleiben.
- **Graph scoping**: `graphID` ist optional (Migration). Queries müssen robust sein (GraphBootstrap versucht zu patchen).

---

### Concurrency

Betroffene Dateien (Auswahl):
- Loader Actors: `GraphCanvasDataLoader.swift`, `EntitiesHomeLoader.swift`, `GraphStatsLoader.swift`, `NodePickerLoader.swift`, `NodeConnectionsLoader.swift`
- Hydrators: `ImageHydrator.swift`, `Attachments/AttachmentHydrator.swift`
- Main thread: `GraphCanvasView+Physics.swift` (Timer)
- App init: `BrainMeshApp.swift` (`Task.detached` für Configure)

Hotspots / Gründe:
- **Default Actor Isolation: MainActor** (Project setting; siehe `project.pbxproj`) erhöht die Gefahr, dass Utility APIs “unabsichtlich” main‑isolated sind. Du arbeitest dagegen bereits mit `nonisolated` und `Sendable` Value Types (z.B. `GraphCanvas/GraphCanvasTypes.swift`, `ImageStore.swift`, `Attachments/AttachmentStore.swift`).
- **Task lifetimes**:
  - Loader/Hydrator verwenden Background‑ModelContexts und Caches; Cancellation muss konsequent sein (z.B. “typing reload”).
  - `Task.detached` im App init ist nicht cancellable, aber hier nur Setup/Configure (ok). Dennoch: wenn Setup später “mehr” macht, wird das riskant.

Konkrete Stellen zum Review:
- “unbounded Task”: jede List‑Row triggert Hydration/Thumbnail? → prüfen in `NodeImagesManageView.swift`, `AttachmentThumbnailStore.swift`.
- “MainActor contention”: GraphCanvas Timer + gleichzeitige Sheets + Save operations.

---

## Refactor Map

### Konkrete Splits (Datei → neue Dateien)

#### A) `Mainscreen/NodeDetailShared/MarkdownTextView.swift` (661 Zeilen)
Ziel: UIKit‑Bridge + Command‑Logik + Styling trennen.

Vorschlag:
- `Mainscreen/NodeDetailShared/MarkdownTextView.swift` → nur `SwiftUI View` Wrapper API
- NEW: `Mainscreen/NodeDetailShared/MarkdownTextView/MarkdownTextView+Representable.swift`
- NEW: `Mainscreen/NodeDetailShared/MarkdownTextView/MarkdownTextView+Coordinator.swift`
- NEW: `Mainscreen/NodeDetailShared/MarkdownTextView/MarkdownCommands.swift` (Undo/Redo, Link prompt, formatting)
- NEW: `Mainscreen/NodeDetailShared/MarkdownTextView/MarkdownPreviewSanitizer.swift` (Preview ohne `**/#` etc.)

Risk:
- Niedrig–mittel (UITextView details). Regression‑Risiko v.a. bei InputAccessory und Cursor/Selection.

Expected Win:
- Bessere Compile‑Times, klarere Ownership, schnellere Debugbarkeit.

#### B) `Mainscreen/Details/DetailsSchemaBuilderView.swift` (725 Zeilen)
Ziel: UI‑Sektionen und Actions entkoppeln.

Vorschlag:
- NEW: `Mainscreen/Details/DetailsSchemaBuilder/DetailsSchemaTemplatesSection.swift`
- NEW: `Mainscreen/Details/DetailsSchemaBuilder/DetailsSchemaFieldsSection.swift`
- NEW: `Mainscreen/Details/DetailsSchemaBuilder/DetailsSchemaActions.swift` (move/delete/applyTemplate)

Risk:
- Niedrig. Funktionale Änderungen vermeiden; reines View‑Split.

#### C) `Mainscreen/EntitiesHomeView.swift` (625 Zeilen)
Ziel: Home‑Screen modularisieren; Route/ViewModel sauber separieren.

Vorschlag:
- `EntitiesHomeView.swift` bleibt “Shell”
- Move out:
  - `EntitiesHome/EntitiesHomeToolbar.swift`
  - `EntitiesHome/EntitiesHomeList.swift` + `EntitiesHome/EntitiesHomeGrid.swift`
  - `EntitiesHome/EntityDetailRouteView.swift` (aktuell nested struct)
  - `EntitiesHome/EntitiesHomeDeleteActions.swift`

Risk:
- Niedrig. Hauptgewinn: Wartbarkeit + weniger Merge‑Konflikte.

---

### Cache-/Index-Ideen

#### 1) Denormalisierte Counts für EntitiesHome
Problem:
- `EntitiesHomeLoader` macht Full‑Table‑Scans für Attribute/Links Counts.

Optionen:
- (A) **Neue SwiftData Entity** `MetaEntityCounts` (graphID + entityID + attrCount + linkCount + updatedAt).
- (B) **Felder direkt auf `MetaEntity`**: `attributeCount`, `linkCount` (aber Migration).
- (C) “Eventual” Cache: nur für Sort/Display berechnen und persistent in UserDefaults keyed by graphID (niedrigerer Correctness‑Anspruch).

Invalidation:
- Bei Create/Delete von Attribute/Link; zentral über Service (z.B. `LinkCleanup.swift` / `NodeRenameService` Schnittstelle erweitern).

#### 2) GraphCanvas spatial partitioning
Problem:
- O(n²) Pair‑Loop (Repulsion/Collision).

Option:
- Grid‑based binning / simple spatial hash → Kollisionschecks nur innerhalb Nachbar‑Bins.

Risk:
- Mittel–hoch (Algorithmus), aber klar messbarer Perf‑Gewinn.

---

### Vereinheitlichungen (Patterns, Services, DI)
- **Container Injection** ist heute manuell in `BrainMeshApp.init()` (viele `Task.detached { loader.configure(container:) }`).
  - Option: zentrale `AppServices`/`Bootstrapper` Struktur, die alles konfiguriert und leichter testbar macht.
- **Loader Snapshot Pattern** ist gut; konsequent dokumentieren:
  - “No SwiftData Models across actor boundary”
  - “Snapshots are Sendable”
- **@AppStorage Keys**: zentrale `enum BMKeys`/`struct DefaultsKeys` würde Tippfehler verhindern und ermöglicht Audit.

---

## Risiken & Edge Cases
- **Schema‑Änderungen (SwiftData/CloudKit)**: Felder entfernen/umbenennen in `Models.swift` ist High Risk (Migration + CloudKit schema evolution).
- **Graph Security UX**: `AppRootView.swift` implementiert debounced background lock, um Photos Hidden Album FaceID nicht zu zerstören (Picker‑Guard via `SystemModalCoordinator`). Änderungen hier können “picker dismissed” Bugs reaktivieren.
- **Dual storage (synced bytes + disk cache)**: Wenn Cache gelöscht wird, muss Hydration zuverlässig wiederherstellen (Settings Maintenance).
- **Multi-device drift**: Denormalisierte Labels/Counts müssen deterministisch nachgezogen werden (Rename + Link updates).

---

## Observability / Debuggability
Vorhanden:
- `Observability/BMObservability.swift`:
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics`
  - `BMDuration` für günstige Timing‑Messungen
- GraphCanvas Physik loggt Rolling Window (60 ticks) in `GraphCanvasView+Physics.swift`.

Konkrete Verbesserungen (low-risk):
- Loader durations messen (Start/Ende) in:
  - `GraphCanvasDataLoader.load(...)`
  - `EntitiesHomeLoader.loadSnapshot(...)`
  - `GraphStatsLoader.loadSnapshot(...)`
- Ein “Debug Overlay” (nur DEBUG) im GraphCanvas: nodes/edges counts, avg physics ms (bereits geloggt).

Repro‑Tipps:
- “Jank” reproduzieren: großer Graph (200+ nodes), WorkMode Explore, Spotlight aus → FPS/CPU beobachten.
- “Search cost”: EntitiesHome Sort “Attribute count” + viele Attribute → Ladezeit messen.

---

## Open Questions (UNKNOWNs)
- **CloudKit DB semantics von `.automatic`**: verwendet SwiftData hier ausschließlich Private DB oder auch Shared? (Im Code kommentiert als “private”, aber keine explizite DB‑Wahl.)
- **Security Felder in `MetaEntity`/`MetaAttribute`**: Absicht (zukünftig per‑Node Lock) oder versehentliches Copy/Paste? (Aktuell ungenutzt; nur `MetaGraph` wird gelockt.)
- **Secrets / Config**: keine `.xcconfig`/Secrets Datei im Repo gefunden. Gibt es externe Config (CI, local)?  
- **Datenmigrationsstrategie**: außer `GraphBootstrap` + `AttachmentGraphIDMigration` keine Versioned migrations sichtbar. Ist das ausreichend für geplante Schema‑Änderungen?

---

## First 3 Refactors I would do (P0)

### P0.1 — MarkdownTextView splitten & UI‑State entkoppeln
- **Ziel:** Wartbarkeit + weniger MainThread‑Risiken im Notes‑Editor; Compile‑Zeit runter.
- **Betroffene Dateien:**  
  - `Mainscreen/NodeDetailShared/MarkdownTextView.swift`  
  - plus neue Unterdateien unter `Mainscreen/NodeDetailShared/MarkdownTextView/*`
- **Risiko:** niedrig–mittel (UITextView edge cases).
- **Erwarteter Nutzen:** schnelleres Iterieren am Editor, weniger Regressionen, bessere Testbarkeit von Preview‑Sanitizing/Commands.

### P0.2 — EntitiesHome counts von Full‑Table‑Scan weg
- **Ziel:** Sort “nach Anzahl Attribute/Links” und Badge‑Counts skalieren ohne Full‑Graph fetch.
- **Betroffene Dateien:**  
  - `Mainscreen/EntitiesHomeLoader.swift`  
  - ggf. `Models.swift` (wenn Counts persistiert werden) oder neues Model `MetaEntityCounts` (**NEW**, Pfad: `Mainscreen/EntitiesHome/MetaEntityCounts.swift`)
- **Risiko:** mittel (Correctness + Migration falls Felder/Model persistent).
- **Erwarteter Nutzen:** deutlich weniger CPU/Memory bei großen Graphen; Search/Sort fühlt sich sofort an.

### P0.3 — GraphCanvas Physik aus dem Main Thread entschärfen
- **Ziel:** Jank reduzieren bei großen Graphen.
- **Betroffene Dateien:**  
  - `GraphCanvas/GraphCanvasView+Physics.swift`  
  - `GraphCanvas/GraphCanvasView.swift` (State‑Plumbing)  
  - optional `Observability/BMObservability.swift` (Signposts)
- **Risiko:** mittel–hoch (Timing/Threading; deterministische UI Updates).
- **Erwarteter Nutzen:** spürbar flüssigere Interaktionen, weniger Batterie‑Drain, bessere Skalierung >200 Nodes.

