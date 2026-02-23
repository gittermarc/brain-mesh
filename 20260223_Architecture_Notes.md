# BrainMesh — ARCHITECTURE_NOTES

Diese Notizen sind absichtlich „engineering‑first“: Risiken, Hotspots, konkrete Hebel.

---

## 0) Architektur‑Schnappschuss

### Persistenz + Sync
- **SwiftData** ist die einzige Persistenzschicht.
- **CloudKit‑Sync** ist rein über SwiftData konfiguriert (kein eigener CKRecord‑Code):
  - `BrainMesh/BrainMeshApp.swift`: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`.
  - `Settings/SyncRuntime.swift` ist nur Diagnostik (iCloud account status), nicht Sync‑Implementation.

**Tradeoff:**
- + Weniger eigener Sync‑Code, weniger Fehlerquellen.
- − Weniger Kontrolle über Konfliktauflösung, Change‑Tracking, Debugging; bei Problemen muss man SwiftData/CloudKit intern „von außen“ diagnostizieren.

### Data Access Pattern (Performance)
- Starkes Pattern: **Heavy fetches off‑main** über Loader‑Actors + Snapshot DTOs.
  - Zentral verdrahtet in `Support/AppLoadersConfigurator.swift`.
  - Loader bauen einen Hintergrund‑`ModelContext` aus `AnyModelContainer`.

**Tradeoff:**
- + UI bleibt reaktiv, keine SwiftData‑Fetches im Render‑Pfad.
- − Mehr Komplexität (DTOs, Cache‑Invalidation, Cancellation, dedupe).

### Graph Canvas
- Graph ist der „Hot Path“:
  - Rendering über `Canvas` + custom draw pipeline (`GraphCanvasView+Rendering.swift`).
  - Physics über 30 FPS `Timer` (`GraphCanvasView+Physics.swift`) mit O(n²) pair‑Loop (Repulsion/Collision) → mitigiert durch Spotlight.

---

## 1) Big Files List (Top 15 nach Zeilen)
Quelle: `wc -l` über `BrainMesh/*.swift`.

| Rank | Lines | Pfad | Zweck | Warum riskant |
|---:|---:|---|---|---|
| 1 | 630 | `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift` | ViewModel/Model für „Alle Attribute“ inkl. Sort/Grouping/Pins | Hohe Änderungsfrequenz + viele Verantwortlichkeiten (Fetch/Cache/Sort/Grouping/UI‑State). |
| 2 | 532 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | Canvas‑Rendering (Nodes/Edges/Labels/Notes/Overlays) | Per‑Frame Arbeit; schwer zu profilieren/ändern ohne Regressionen. |
| 3 | 515 | `BrainMesh/Models.swift` | SwiftData Models (Graph/Entity/Attribute/Link/Details) | „God model file“: Merge‑Konflikte, Compile‑Churn, Migration‑Risiko. |
| 4 | 510 | `BrainMesh/Mainscreen/Details/DetailsValueEditorSheet.swift` | Details‑Editor (alle Typen) + Completion | Viele UI‑Branches + State + Async Tasks → Bug‑Surface hoch. |
| 5 | 504 | `BrainMesh/Onboarding/OnboardingSheetView.swift` | Onboarding Flow + UI | Viel UI in einem File; Änderungen können UX regressions verursachen. |
| 6 | 491 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | Shared Detail‑UI Kern | „Shared“ Files sammeln gern alles → schwer testbar. |
| 7 | 469 | `BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaFieldsList.swift` | Details‑Schema Editor (Felder definieren, pinning, Typen) | Komplexe UI + Mutationen am Schema (Migration‑Risiko). |
| 8 | 411 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | Graph Snapshot Loader + BFS Neighborhood | Algorithmik + SwiftData Predicates + Limits → Perf + Correctness risk. |
| 9 | 409 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | Bilder verwalten (Gallery) | Kombiniert UI + Hydration/Loading; potenziell heavy. |
|10 | 401 | `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` | Attribut Detail Screen | Viele Subsections; invalidations/scroll performance risk. |
|11 | 397 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` | Entities Home Loader (Search + Counts Caches) | Performance‑kritisch bei großen Daten; Cache‑Invalidation. |
|12 | 394 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | Connections UI + Loading | Potenziell viele Links; Paging/Load risk. |
|13 | 388 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` | Entities Home Screen | Viele UI states + debounce + sheets; regressions bei Navigation. |
|14 | 388 | `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` | Anzeige der Detail‑Werte | „Card“ wird häufig gerendert; risk bei Fetch/Format im body. |
|15 | 362 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | Media Gallery (Paging + UI) | I/O + Large UI; Cancellation/Memory risk. |

**Meta‑Risiko:** Diese Files sind zugleich „Hotspot + groß“ → wenn du Refactors schneidest, hier anfangen (kleine, behavior‑identische Splits).

---

## 2) Hot Path Analyse

### 2.1 Rendering / Scrolling

#### A) Graph Canvas Rendering
- **Pfad:** `BrainMesh/GraphCanvas/GraphCanvasView.swift` + `GraphCanvasView+Rendering.swift`.
- **Warum Hot:**
  - `Canvas { context in renderCanvas(...) }` läuft bei vielen State‑Änderungen (positions/velocities tick). `GraphCanvasView+Physics.swift` mutiert `positions/velocities` bis 30 FPS.
  - Rendering‑File ist groß (532 LOC), typischerweise viele Draw‑Passes.
- **Konkrete Risiken:**
  - **Exzessive View invalidation:** jeder Physics tick invalidiert den Canvas.
  - **Per‑Frame allocations:** wenn Render‑Pfad Arrays/Strings neu baut (z. B. Labels, layout calculations) → GC/ARC overhead.
  - **Disk I/O im Render:** wurde bereits aktiv vermieden; Thumbnail cache ist explizit `@State cachedThumb` und `ImageStore.loadUIImageAsync` ist der empfohlene Weg (`ImageStore.swift` Kommentar).

**Was bereits gut ist:**
- `GraphCanvasScreen.swift` hält Render‑Caches (`labelCache`, `imagePathCache`, `iconSymbolCache`) und precomputet derived state (`drawEdgesCache`, `lensCache`, `physicsRelevantCache`).
- Selection Thumbnail wird gecached (`GraphCanvasView.swift`: `cachedThumbPath/cachedThumb`).

**Konkrete Hebel:**
- Render‑Pipeline weiter „data‑driven“ machen:
  - Precompute `RenderableNode`/`RenderableEdge` structs bei Änderungen von `nodes/edges/labelCache/...` (nicht pro Frame).
  - Im Physics tick nur positions updaten.

#### B) Graph Canvas Physics
- **Pfad:** `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`.
- **Warum Hot:**
  - Pair‑loop für repulsion/collision: `for i in 0..<simNodes.count { for j in i+1..<... }` → **O(n²)**.
  - Timer 30 FPS: `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)`.
- **Mitigation im Code:**
  - **Spotlight Physik:** `physicsRelevant` begrenzt simNodes auf selection+neighbors.
  - **Idle/Sleep:** stoppt Timer nach ~3s wenn Geschwindigkeit niedrig.
  - Observability: `BMLog.physics` avg/max (rolling 60 ticks).

**Risiko‑Grenzen:**
- Bei globaler Ansicht (keine selection) sind `simNodes = nodes` → O(n²) kann CPU‑heavy werden.
- `maxNodes` default 140 (`GraphCanvasScreen.swift`), aber User kann es im Inspector ändern.

#### C) EntitiesHome Scrolling
- **Pfad:** `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` + `EntitiesHomeList.swift` / `EntitiesHomeGrid.swift`.
- **Warum Hot:**
  - Searchable + debounce + off‑main Loader. Bei schnellem Tippen viele Task‑Abbrüche.
  - Grid/List Varianten; Cards nutzen `ScrollView + LazyVStack`.
- **Was bereits gut ist:**
  - Keine `@Query`‑Liste für Entities; stattdessen `EntitiesHomeLoader.shared.loadSnapshot(...)` (off‑main).
  - TTL Cache für attribute/link counts (`EntitiesHomeLoader.swift`).

**Risiko:**
- Cache‑Staleness (TTL 8s) ist ein UX‑Tradeoff. Wenn du mutierst (Add/Delete) musst du invalidieren (wird teilweise gemacht: `EntitiesHomeView` invalidiert Cache beim Schließen von AddEntity).

### 2.2 Sync / Storage

#### A) Container Init & Fallback
- **Pfad:** `BrainMesh/BrainMeshApp.swift`.
- **Risk:**
  - Debug: `fatalError` bei CloudKit Init‑Fehler.
  - Release: silent fallback local‑only → kann „Sync kaputt“ wirken.
  - Der Modus wird über `SyncRuntime.storageMode` surfaced.

**Hotspot‑Grund:** nicht CPU‑Hotspot, aber **Produktions‑Risk** (Daten landen lokal ohne Sync).

#### B) External Storage Attachments
- **Pfad:** `BrainMesh/Attachments/MetaAttachment.swift` (`@Attribute(.externalStorage) var fileData`).
- **Risk:**
  - Beim Anzeigen kann das Lesen von `fileData` CloudKit fetch triggern.
  - Deshalb wird im Loader/Row bewusst nur metadata geladen; fileData wird erst beim Öffnen/hydraten gelesen.

#### C) Local Cache + Hydration
- **Bilder:** `ImageStore.swift` + `ImageHydrator.swift`.
- **Anhänge:** `AttachmentStore.swift` + `AttachmentHydrator.swift`.

**Hotspot‑Gründe:**
- Cache‑miss stampedes (viele Zellen gleichzeitig) → mitigiert durch AsyncLimiter und inFlight dedupe.
- Disk usage / cleanup flows (Settings Maintenance).

### 2.3 Concurrency

#### Pattern: Actor Loader + Task.detached + ModelContext
- **Pfadbeispiele:**
  - `GraphCanvasDataLoader.loadSnapshot(...)` (`GraphCanvas/GraphCanvasDataLoader.swift`).
  - `GraphStatsLoader` (`Stats/GraphStatsLoader.swift`).
  - `EntitiesHomeLoader` (`Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`).
- **Positiv:**
  - UI bleibt auf MainActor; SwiftData fetches laufen off‑main.
  - Snapshot DTOs verhindern „@Model über Thread“.
- **Risiken:**
  - **Cancellation‑Leaks:** wenn Loops selten `Task.checkCancellation()` machen (GraphCanvasDataLoader macht teils checks, EntitiesHomeLoader macht checks, aber ist nicht überall garantiert).
  - **Detached tasks lifetime:** `Task.detached` läuft unabhängig von parent task; wenn man nicht checkt/cancelt, arbeitet es weiter.
  - **MainActor contention:** GraphCanvas Physics Timer + UI state updates laufen auf MainActor.

---

## 3) Refactor Map

### 3.1 Konkrete Splits (Datei → neue Dateien)

#### A) `Models.swift` (515 LOC)
**Ziel:** Compile‑Churn runter, Merge‑Konflikte runter, besseres „findability“.

Vorschlag:
- `BrainMesh/Models/MetaGraph.swift`
- `BrainMesh/Models/MetaEntity.swift`
- `BrainMesh/Models/MetaAttribute.swift`
- `BrainMesh/Models/MetaLink.swift`
- `BrainMesh/Models/DetailsModels.swift` (DetailFieldDefinition/Value + DetailFieldType)
- `BrainMesh/Models/BMSearch.swift` (fold helper) + `NodeKind.swift`

Risiko: **Low** (behavior‑identisch, nur File‑Move/Split).  
Achtung: `Schema([...])` in `BrainMeshApp` muss weiterhin alle `@Model` Typen importieren.

#### B) `GraphCanvasView+Rendering.swift` (532 LOC)
**Ziel:** Render‑Pipeline klarer, besser messbar.

Vorschlag (Extensions):
- `GraphCanvas/Rendering/GraphCanvasRendering+Edges.swift`
- `GraphCanvas/Rendering/GraphCanvasRendering+Nodes.swift`
- `GraphCanvas/Rendering/GraphCanvasRendering+Labels.swift`
- `GraphCanvas/Rendering/GraphCanvasRendering+Notes.swift`
- `GraphCanvas/Rendering/GraphCanvasRendering+Debug.swift` (falls vorhanden)

Risiko: **Low‑Medium** (Refactor kann visuelle Regressionen bringen, aber behavior bleibt gleich).

#### C) `DetailsValueEditorSheet.swift` (510 LOC)
**Ziel:** UI‑Branches entknoten; Completion‑Mechanik isolieren.

Vorschlag:
- `Mainscreen/Details/Editor/DetailsValueEditorSheet.swift` (Routing + Save/Delete)
- `Mainscreen/Details/Editor/DetailsValueEditor+SingleLine.swift`
- `Mainscreen/Details/Editor/DetailsValueEditor+MultiLine.swift`
- `Mainscreen/Details/Editor/DetailsValueEditor+Numbers.swift`
- `Mainscreen/Details/Editor/DetailsValueEditor+DateToggleChoice.swift`
- Completion:
  - `Support/DetailsCompletion/*` ist schon da; ggf. `DetailsValueEditorCompletionCoordinator.swift` ergänzen.

Risiko: **Low** (UI‑Split, kaum Logikänderung).

#### D) `EntityAttributesAllListModel.swift` (630 LOC)
**Ziel:** Wartbarkeit + gezielte Perf‑Optimierungen ohne große Architektur.

Vorschlag:
- `.../EntityAttributesAllListModel.swift` (public API + state)
- `.../EntityAttributesAllListModel+Caching.swift` (pinned lookup, media sets, invalidation)
- `.../EntityAttributesAllListModel+Grouping.swift` (makeGroups + headers)
- `.../EntityAttributesAllListModel+Sorting.swift`

Risiko: **Low‑Medium** (viel Code bewegt, aber behavior gleich).

### 3.2 Cache-/Index‑Ideen (konkret)

#### A) GraphCanvas: Precomputed render items
- **Problem:** Rendering hängt an `positions` (per frame), aber vieles ist „static“: labels, icon paths, notes mapping.
- **Idee:**
  - Build `RenderNodeInfo` map: `NodeKey → (label, iconSymbol, imagePath, kind, baseRadius, ...)` wenn `nodes/labelCache/iconSymbolCache/imagePathCache` ändern.
  - Build `RenderEdgeInfo` array: `[(aKey,bKey,type,isDimmed,isHighlighted,...)]` wenn `drawEdgesCache/lensCache` ändern.
  - Canvas tick nutzt nur `positions` und liest die precomputed info.
- **Invalidation keys:**
  - Nodes/Edges mutation, lens settings, showAllLinksForSelection.

#### B) EntitiesHomeLoader: Cache invalidation hooks
- TTL Cache ist gut; zusätzlich helfen klare invalidations:
  - Bei Entity Add/Delete/Rename: `EntitiesHomeLoader.invalidateCache(for:)`.
  - Bei Link Add/Delete: invalidate linkCountsCache.

#### C) Details Completion Index
- Der Index wird im Sheet warm geladen (`DetailsValueEditorSheet.warmUpCompletionIndexIfNeeded`).
- **Hebel:** Index‑Load im Hintergrund, sobald aktive graphID gesetzt wird (z. B. in `AppRootView.bootstrapGraphing()`), um ersten Editor‑Open zu beschleunigen.

### 3.3 Vereinheitlichungen (Patterns, Services, DI)

#### A) „Loader“ Interface
Viele Loader haben das gleiche Muster:
- `configure(container:)`
- `loadSnapshot(...)`

Ein sehr kleiner, optionaler Schritt:
- Protokoll `ModelContainerConfigurable` + `SnapshotLoader` (nur für Code‑Lesbarkeit).

#### B) Logger
- Ein Teil nutzt `BMLog.*`, ein Teil erstellt `Logger(subsystem:..., category:...)`.
- Hebel: konsequent `BMLog` verwenden oder `BMLog.make(category:)` anbieten.

---

## 4) Risiken & Edge Cases

### 4.1 Datenverlust / Migration
- **GraphID optional** (MetaEntity/MetaAttribute/MetaLink/MetaAttachment):
  - Migration existiert (`GraphBootstrap`, `AttachmentGraphIDMigration`).
  - Risiko: neue Queries filtern nach `graphID == gid` → legacy records (nil) werden unsichtbar, wenn Migration nicht läuft.

### 4.2 Offline + Multi‑Device
- Offline wird von SwiftData gehandhabt (**UNKNOWN**: konkrete UX für Konflikte/merge).
- Risiko: parallel edits → „last write wins“ oder merges? → muss ggf. über UI/Logging sichtbar gemacht werden.

### 4.3 Security / Lock
- Graph Lock ist implementiert über `GraphLockCoordinator` + `GraphUnlockView`.
- `AppRootView` debounced background lock, um System‑Picker nicht zu zerlegen.
- **Model‑Risiko:** `MetaEntity` und `MetaAttribute` enthalten ebenfalls Lock‑Felder (`Models.swift`), die aber nicht sichtbar verwendet werden (siehe grep). → möglicher Ballast.

### 4.4 Attachments/Media
- `MetaAttachment.fileData` ist external storage → kann on‑demand geladen werden.
- Hydrator/Store schützen vor stampedes, aber:
  - Große Dateien können Memory pressure verursachen (Data im RAM beim Schreiben).
  - Cleanup flows müssen robust sein (Settings maintenance).

---

## 5) Observability / Debuggability

### Was existiert
- `Observability/BMObservability.swift`:
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics`
  - `BMDuration` für timing.
- Physics Logging: `GraphCanvasView+Physics.swift` loggt avg/max ms.

### Konkrete Verbesserungen
- Loader timing:
  - In `GraphCanvasDataLoader.loadSnapshot` und `GraphStatsLoader.loadDashboardSnapshot` mit `BMDuration` messen und `BMLog.load` loggen (nicht nur `Logger(category:...)`).
- Cancellation logging:
  - Wenn `CancellationError`, bewusst nicht als „Fehler“ loggen, aber counts/metrics sammeln.
- Repro‑Checklists:
  - GraphCanvas perf: nodes=140, links=800, selection toggles, zoom/pan stress.
  - Attachment cache: cache clear, dann gallery scroll.

---

## 6) Open Questions (alles UNKNOWN)
- CloudKit DB/Scope: `cloudKitDatabase: .automatic` — garantiert private DB? (**UNKNOWN**)
- Release/TestFlight: Entitlements `aps-environment = development` — muss das getrennt werden? (**UNKNOWN**)
- Konfliktauflösung bei SwiftData CloudKit: sichtbar machen? (**UNKNOWN**)
- Sind Node‑Locks (Entity/Attribute) geplant oder Altlast? (**UNKNOWN**)
- Welche maximalen Datenmengen sind Ziel (Nodes/Links/Attachments)? (**UNKNOWN**)

---

## 7) First 3 Refactors I would do (P0)

### P0.1 — Models.swift splitten (behavior‑identisch)
- **Ziel:** Weniger Merge‑Konflikte + klarere Ownership pro Model + schnelleres Arbeiten.
- **Betroffene Dateien:**
  - `BrainMesh/Models.swift` → neue Files unter `BrainMesh/Models/*` (siehe Refactor Map 3.1A)
  - `BrainMesh/BrainMeshApp.swift` (nur Imports/Schema bleibt, aber ggf. keine Änderung nötig)
- **Risiko:** Low
- **Erwarteter Nutzen:** High für Wartbarkeit, Medium für Compile‑Zeiten.

### P0.2 — GraphCanvas Rendering in Passes aufteilen
- **Ziel:** Render‑Pfad besser messbar/änderbar; Regressionen leichter isolieren.
- **Betroffene Dateien:**
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - ggf. neue Files unter `BrainMesh/GraphCanvas/Rendering/*`
- **Risiko:** Low‑Medium (visuelle Regressionen möglich)
- **Erwarteter Nutzen:** High für Wartbarkeit + Perf‑Tuning.

### P0.3 — DetailsValueEditorSheet modularisieren
- **Ziel:** Feature‑Entwicklung an Details (Completion/Chips/Typing) ohne „monolithisches Sheet“.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/Details/DetailsValueEditorSheet.swift`
  - `BrainMesh/Support/DetailsCompletion/*` (ggf. neue kleine Coordinator‑Helper)
- **Risiko:** Low
- **Erwarteter Nutzen:** Medium‑High (weniger Bugs, schnellere Iteration).
