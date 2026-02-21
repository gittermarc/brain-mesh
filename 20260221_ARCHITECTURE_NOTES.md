# ARCHITECTURE_NOTES.md — BrainMesh

> Stand: 2026-02-21 (Analyse aus dem ZIP-Stand im Repo).  
> Ziel: Hotspots/Risiken sichtbar machen und konkrete, umsetzbare Refactor-Hebel ableiten.

## 0) Kurzüberblick: Was ist hier „architektonisch wichtig“?
- **SwiftData + CloudKit** ist der Kern: Container/Schema-Init, Graph-Scoping (`graphID`), Migrationen, und „off-main“ Fetch-Strategien bestimmen Stabilität + UX. (`BrainMesh/BrainMeshApp.swift`, `BrainMesh/Models.swift`, `BrainMesh/GraphBootstrap.swift`)
- Das Projekt nutzt bewusst mehrere **actor-basierte Loader/Hydrators** mit `Task.detached` und eigener `ModelContext`, um UI-Thread-Stalls zu vermeiden. Zentrale Konfiguration: `BrainMesh/Support/AppLoadersConfigurator.swift`.
- Die Performance-Kante ist (a) **GraphCanvas Rendering/Physics** und (b) **List-/Detail-Screens mit vielen Records/Medien**.

---

## 1) Big Files List (Top 15 nach Zeilen)

| # | Pfad | Zeilen |
|---:|---|---:|
| 1 | `Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` | 630 |
| 2 | `GraphCanvas/GraphCanvasView+Rendering.swift` | 532 |
| 3 | `Models.swift` | 515 |
| 4 | `Mainscreen/Details/DetailsValueEditorSheet.swift` | 510 |
| 5 | `Onboarding/OnboardingSheetView.swift` | 504 |
| 6 | `Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | 491 |
| 7 | `Mainscreen/Details/DetailsSchema/DetailsSchemaFieldsList.swift` | 469 |
| 8 | `GraphCanvas/GraphCanvasDataLoader.swift` | 411 |
| 9 | `Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 410 |
| 10 | `Mainscreen/AttributeDetail/AttributeDetailView.swift` | 401 |
| 11 | `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` | 397 |
| 12 | `Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | 394 |
| 13 | `Mainscreen/EntitiesHome/EntitiesHomeView.swift` | 388 |
| 14 | `Mainscreen/Details/NodeDetailsValuesCard.swift` | 388 |
| 15 | `Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 362 |

### Warum diese Dateien riskant sind (typische Failure-Modes)
- **Compile-Time / Rebuild-Churn**: Große SwiftUI-Views + viele generische Builder/Closures → langsame Incremental Builds.
- **UI Invalidations**: Wenn in großen Views viel abgeleitete State-Berechnung in `body` passiert, invalidiert SwiftUI gern zu breit.
- **MainActor Contention**: Große „Model“-Klassen/Views, die (re-)builden, sortieren, strings zusammenbauen, etc. auf Main.
- **Memory Pressure**: Details-Editor + Media-Views + GraphCanvas können schnell viele `UIImage`/`Data`/`@Model` Instanzen anfassen.

---

## 2) Hot Path Analyse

### 2.1 Rendering / Scrolling (SwiftUI)
#### GraphCanvas: per-frame Rendering + Physik
- **Rendering Hotspot**
  - Datei: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` (532 Zeilen)
  - Grund: per Canvas-Frame werden Nodes/Edges iteriert, Path aufgebaut, Labels/Notizen/Thumbs gerendert.
  - Positive: Es gibt einen **FrameCache** (`screenPoints`, `labelOffsets`, `outgoingNotesByTarget`) und Zoom-Alpha-Gating, um Work zu reduzieren.
- **Physik Hotspot**
  - Datei: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - Grund: `Timer` mit 30 FPS (`Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)`) + O(n²) Pair-Loop für Repulsion/Collision.
  - Mitigation im Code:
    - Spotlight-Physik (nur relevante Nodes) via `physicsRelevant` (`GraphCanvasView.swift`, `GraphCanvasView+Physics.swift`)
    - Idle/Sleep Mechanik (timer stoppen, wenn Layout „settled“) (`GraphCanvasView.swift`, `GraphCanvasView+Physics.swift`)
- **UI invalidation risk**
  - Datei: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - Grund: sehr viele `@State` Variablen; Änderungen an `positions/velocities` triggern re-renders; Countermeasure: caching von derived state (`drawEdgesCache`, `lensCache`, `physicsRelevantCache`).

#### Entities Home: Suche/Reload
- Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
- Grund: `searchable` + `.task(id: taskToken)` führt bei Tipp-Events zu Reloads.
- Mitigation: `debounceNanos` + Loader-Pattern statt Fetch im Renderpfad; sofortige Sort-Anwendung ohne Reload (`.onChange(of: entitiesHomeSortRaw)`).

#### Detailseiten: Medien + Attachments
- Datei: `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`
- Grund: `fetchCount` + `fetch` für Gallery/Attachment Preview. Das ist **@MainActor**.
- Bewertung:
  - Positiv: `fetchLimit` wird genutzt (Preview); Predicates sind bewusst „store-translatable“ (kein OR).
  - Risiko: Wenn Call-Sites das unabsichtlich häufig triggern (z.B. bei jedem State Change), kann das Scroll/Interaction stören.
  - Call-Sites: `EntityDetailView+MediaSection.swift`, `AttributeDetailView+MediaSection.swift` (beide verwenden den Loader).

### 2.2 Sync / Storage (SwiftData + CloudKit)
#### Container/Schema & Fallback
- Datei: `BrainMesh/BrainMeshApp.swift`
- Grund: Startup ist Gatekeeper:
  - Schema wird hart kodiert (Model-Liste muss bei neuen `@Model` angepasst werden).
  - CloudKit Init: DEBUG fatal, RELEASE fallback local-only.
- Risiken:
  - **Signing/Entitlements Drift** → CloudKit init fail (Release fallback versteckt Probleme als „kein Sync“).
  - **Schema drift**: neuer `@Model` nicht im Schema → runtime errors / missing persistence.

#### Graph scoping & Legacy Migration
- Dateien: `BrainMesh/Models.swift`, `BrainMesh/GraphBootstrap.swift`
- Grund:
  - `graphID` ist optional für „gentle migration“.
  - Bootstrap migriert `graphID == nil` Records in Default-Graph.
- Risiken:
  - Queries müssen häufig 2 Pfade haben (mit/ohne graphID), sonst braucht man OR-Predicates (die SwiftData/Store ggf. nicht optimiert).
  - Das Projekt arbeitet aktiv dagegen: z.B. Attachment-Migration in `AttachmentGraphIDMigration` (aufgerufen in `NodeMediaPreviewLoader.load`).

#### External Storage (Attachments)
- Datei: `BrainMesh/Attachments/MetaAttachment.swift`
- Grund: `@Attribute(.externalStorage) fileData` senkt Record Size Druck und ist CloudKit-freundlicher.
- Risiko: Beim Zugriff kann SwiftData die externen Bytes nachladen → deshalb gibt es `AttachmentHydrator` als Cache-Schicht.

### 2.3 Concurrency / Task Lifetimes
#### Loader-/Hydrator-Pattern
- Zentrale Konfiguration: `BrainMesh/Support/AppLoadersConfigurator.swift`
- Pattern:
  - `actor` hält `AnyModelContainer`
  - `Task.detached` erstellt `ModelContext` und führt Fetch/Compute off-main aus
  - Rückgabe als Value-Snapshot (DTO), UI resolved per ID im Main `ModelContext`
- Beispiele:
  - `EntitiesHomeLoader` (`Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`)
  - `GraphCanvasDataLoader` (`GraphCanvas/GraphCanvasDataLoader.swift`)
  - `GraphStatsLoader` (`Stats/GraphStatsLoader.swift`)
- Typische Risiken:
  - Cancellation nicht konsequent → überlappende Loads, wasted work
  - Snapshot-Typen müssen wirklich value-only sein (keine `@Model`, keine `UIImage`)
  - Thread safety: `ModelContext` darf nicht über Threads hinweg geteilt werden (wird hier korrekt per Task neu erstellt)

#### Throttling / Stampede Prevention
- Datei: `BrainMesh/Support/AsyncLimiter.swift`
- Hydrators nutzen Limiter:
  - `ImageHydrator`: `maxConcurrent: 1` (`BrainMesh/ImageHydrator.swift`)
  - `AttachmentHydrator`: `maxConcurrent: 2` + `inFlight` de-dupe (`BrainMesh/Attachments/AttachmentHydrator.swift`)
- Nutzen: verhindert UI-Jank beim Öffnen großer Screens (viele Zellen → viele „ensure cached file“ calls).

---

## 3) Refactor Map (konkret, dateibasiert)

### 3.1 Splits (Wartbarkeit + Compile-Time)
> Ziel: kleinere Responsibility Units, weniger Rebuild-Churn, klarere Ownership.

- `BrainMesh/Mainscreen/Details/DetailsValueEditorSheet.swift` (510)
  - Split-Idee:
    - `DetailsValueEditorSheet.swift` (Host: Navigation, Save/Delete wiring)
    - `DetailsValueEditor+FieldType.swift` (Editor-UI je `DetailFieldType`)
    - `DetailsValueEditor+Completion.swift` (Completion Index + Tasks)
  - Grund: das File mischt Form-Layout, typed parsing/validation, completion, persistence.

- `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` (630)
  - Split-Idee:
    - `EntityAttributesAllListModel.swift` (API + Published outputs)
    - `EntityAttributesAllListModel+Cache.swift` (Cache struct + invalidation)
    - `EntityAttributesAllListModel+Pinned.swift` (Pinned fields/chips/menu options)
    - `EntityAttributesAllListModel+FilteringSorting.swift` (search + sort selection)
  - Grund: File enthält mehrere orthogonale Concerns, ist gleichzeitig „state machine“ und „row builder“.

- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` (491) und `...+Connections.swift` (394)
  - Split-Idee: je Section ein eigenes Subview + Actions in separate helper.
  - Grund: Detailseiten sind naturgemäß „Oktopus“; Splits reduzieren Merge-Konflikte und Recompile.

### 3.2 Cache-/Index-Ideen (Performance)
- **EntitiesHome counts**: bereits TTL-cache (8s) für Attribute/Link Counts (`EntitiesHomeLoader.swift`).
  - Nächster Schritt: separate TTL je Graph + separate TTL je includeFlags (Counts vs Notes).
- **GraphCanvas**
  - Rendering: `FrameCache` existiert bereits (`GraphCanvasView+Rendering.swift`).
  - Potenzial: für große Graphen könnte ein Spatial Index (Grid) für Collision die Pair-Loop reduzieren. Aufwand: mittel/hoch.
- **Details Completion**
  - Index existiert (`Support/DetailsCompletion/*`).
  - Potenzial: Persistenten Cache pro Graph/Entity-Feld statt „warmUp“ pro Sheet-Open (Call-Sites prüfen).

### 3.3 Vereinheitlichungen (Patterns, DI, Debug)
- **ModelContext Factory**: Viele Loader erstellen `ModelContext(configuredContainer.container)` + `autosaveEnabled = false`.
  - Hebel: kleine Utility (z.B. `Support/ModelContextFactory.swift`) → weniger Boilerplate, weniger Fehler.
- **Logging**
  - Es gibt `BMLog` + `BMDuration` (`Observability/BMObservability.swift`), aber noch nicht konsequent überall.
  - Hebel: Loader-Laufzeiten signposten (Home/Graph/Stats) und Settings → „Diagnostics“ ausgeben.

---

## 4) Risiken & Edge Cases
- **CloudKit Init Fail in Debug**: `fatalError` blockiert Debug-Testing ohne korrektes Signing (`BrainMeshApp.swift`).
- **graphID == nil Legacy**: Doppelpfad-Queries bleiben fehleranfällig, solange alle Records nicht vollständig migriert sind (`GraphBootstrap.swift`, `AttachmentGraphIDMigration.swift`).
- **Media/Attachment Pressure**
  - Entity/Attribute `imageData` ist Data im Record (`Models.swift`) und wird via `ImageImportPipeline.prepareJPEGForCloudKit` klein gehalten (`Images/ImageImportPipeline.swift`).
  - Attachments nutzen `externalStorage`, aber Preview-Loads können dennoch I/O-trächtig sein.
- **GraphCanvas Scaling**
  - O(n²) Kollisionsloop wird bei `maxNodes` hart (trotz Caps). Default Caps sind gesetzt (`GraphCanvasScreen.swift`), aber große Graphen bleiben Performance-kritisch.
- **Security/Lock vs System Modals**
  - `AppRootView` debounced Background-Lock, um Photos-Picker-Edgecases zu vermeiden (`AppRootView.swift`).
  - Risiko: weitere System Modal Flows (DocumentPicker, etc.) könnten ähnliche Probleme haben; Koordinator existiert (`Support/SystemModalCoordinator.swift`).

---

## 5) Observability / Debuggability
- Vorhanden:
  - `BMLog` Kategorien: load/expand/physics (`Observability/BMObservability.swift`)
  - Timing helper `BMDuration`
  - Settings Sync Diagnostics: `SyncRuntime` (`Settings/SyncRuntime.swift`)
- Vorschläge (klein, high ROI):
  - Loader-Snapshots: Dauer + Result-Größen loggen (Entities count, edges count).
  - Hydrators: Anzahl der geschriebenen Files + Dauer (Image/Attachment).
  - GraphCanvas: FPS/avg tick time (teilweise vorhanden: Tick Counters in `GraphCanvasView.swift`).

---

## 6) Open Questions (UNKNOWN)
- **CloudKit Konflikt-/Merge-Strategien**: keine projektspezifische UI/Policy gefunden → **UNKNOWN** (bisher vermutlich Framework-Default).
- **SPM Dependencies**: keine `Package.resolved` im Repo → **UNKNOWN**, ob außerhalb des ZIP eingebunden.
- **Push/Subscriptions**: `remote-notification` gesetzt (`Info.plist`), aber keine `CKSubscription` gefunden → **UNKNOWN** (geplant oder legacy).
- **Test Coverage**: Tests Targets existieren (`BrainMeshTests`, `BrainMeshUITests`), aber Umfang/Value: **UNKNOWN** (nur Basistemplates gefunden).

---

## 7) First 3 Refactors I would do (P0)

### P0.1 — DetailsValueEditorSheet splitten
- **Ziel:** Wartbarkeit + weniger Recompile + klarere typed parsing/validation.
- **Betroffene Dateien:**  
  - `BrainMesh/Mainscreen/Details/DetailsValueEditorSheet.swift`  
  - plus neue Dateien (z.B. `DetailsValueEditor+FieldType.swift`, `...+Completion.swift`)
- **Risiko:** niedrig/mittel (UI-Refactor, aber Logik bleibt gleich; Risiko liegt in Focus/Task-Cancellation).
- **Erwarteter Nutzen:** schnellere Builds, weniger regressions bei Details-Feature-Iteration, einfacher testbar.

### P0.2 — EntityAttributesAllListModel in Partial-Files aufteilen + Cache klarziehen
- **Ziel:** Das Attribut-Listen-Model wartbar machen (und idealerweise „incremental rebuild“ strikt trennen von UI-State).
- **Betroffene Dateien:**  
  - `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift`  
  - neue: `...+Cache.swift`, `...+Pinned.swift`, `...+FilteringSorting.swift`
- **Risiko:** niedrig (struktureller Split, kein Behavior Change).
- **Erwarteter Nutzen:** weniger Merge-Konflikte, schnelleres Iterieren an Sort/Grouping/Pinned-Details.

### P0.3 — ModelContextFactory + einheitliche Loader-Boilerplate
- **Ziel:** Boilerplate reduzieren, konsistente Cancellation/Autosave-Policy, weniger Copy/Paste Bugs.
- **Betroffene Dateien:**  
  - neue Utility in `BrainMesh/Support/` (z.B. `ModelContextFactory.swift`)  
  - Loader: `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `NodeConnectionsLoader`, `NodePickerLoader`
- **Risiko:** niedrig (mechanischer Refactor), solange API minimal bleibt.
- **Erwarteter Nutzen:** weniger Fehler, klarer Standard für neue Loader, bessere Lesbarkeit.

