# ARCHITECTURE_NOTES.md — BrainMesh

> Fokus: technische Architektur, Tradeoffs, Hotspots, Refactor‑Hebel.  
> Pfade sind relativ zum Target‑Ordner **`BrainMesh/`**.

---

## Big Files List (Top 15 nach Zeilen)

| # | Datei | Zeilen |
|---:|---|---:|
| 1 | `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift` | 725 |
| 2 | `BrainMesh/Mainscreen/EntityDetail/EntityDetailView+AttributesSection.swift` | 670 |
| 3 | `BrainMesh/Mainscreen/NodeDetailShared/MarkdownTextView.swift` | 661 |
| 4 | `BrainMesh/Mainscreen/EntityDetail/EntityAttributesAllListModel.swift` | 586 |
| 5 | `BrainMesh/Settings/Appearance/DisplaySettingsView.swift` | 533 |
| 6 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | 532 |
| 7 | `BrainMesh/Models.swift` | 515 |
| 8 | `BrainMesh/Onboarding/OnboardingSheetView.swift` | 504 |
| 9 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | 491 |
| 10 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | 411 |
| 11 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 410 |
| 12 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | 394 |
| 13 | `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` | 388 |
| 14 | `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` | 386 |
| 15 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` | 384 |

### Warum diese Dateien riskant sind (kurz)
- Große SwiftUI‑Screens erhöhen **Incremental‑Compile‑Zeit**, Merge‑Konflikt‑Risiko und erschweren Performance‑Analyse.
- Große „Model/Loader/Builder“ Dateien werden oft zu **Dumping Grounds** (Query‑Boilerplate, Formatierung, UI‑State, Business Rules vermischt).

---

## Hot Path Analyse

### 1) Rendering / Scrolling

#### Graph Canvas: per‑frame Rendering + Physics
- Datei: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`  
  **Grund:** pro Frame Loops über `drawEdges` + `nodes` (GraphicsContext drawing). Jeder Physics‑Tick ändert `positions/velocities` → viele View invalidations.
- Datei: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (und Extensions)  
  **Grund:** sehr viel `@State` (nodes/edges/positions/velocities + selection/lens/caches). Risiko von „exzessive View invalidation“ bei häufigen State‑Änderungen.

Mitigation, die bereits existiert:
- Render‑Caches (`drawEdgesCache`, `lensCache`, `physicsRelevantCache`) werden **nicht im `body`** berechnet, sondern via `recomputeDerivedState()` in `@MainActor`.  
  Datei: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
- Frame Cache / label offset cache / outgoing note prefilter im Rendering.  
  Datei: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`

Open Risks / Beobachtungen:
- **UNKNOWN:** Ob die Physics‑Tick‑Rate adaptiv ist (z.B. DisplayLink vs Timer) und ob sie bei Background/low power sauber pausiert.
- Bei sehr großen Graphen ist `maxNodes`/`maxLinks` ein UI‑Knob (State) – aber ob der Loader *wirklich* dadurch begrenzt wird, ist abhängig von `GraphCanvasDataLoader`‑Implementierung. **UNKNOWN** (siehe unten).

#### Entities Home: Search Typing + Count‑Berechnung
- Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`  
  **Grund:** `.task(id: taskToken)` triggert Reload bei Graph/Suche/Flag‑Changes (Debounce 250ms). UI ist zwar nicht blockiert, aber Reload‑Frequenz kann hoch sein.
- Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`  
  **Grund:** (optional) Berechnung von Attribute‑Counts und Link‑Counts kann große Fetches verursachen; es gibt TTL‑Caches (8s), aber bei großen Datenmengen bleibt es teuer.

Mitigation, die bereits existiert:
- Loader arbeitet **off-main** via `Task.detached(priority: .utility)` + value‑only Snapshot DTOs (`EntitiesHomeRow`).  
  Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Counts Cache (TTL) wird bei aktiver Suche genutzt (für „typing“ flüssig).  
  Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`

Konkreter Hotspot‑Grund:
- „heavy sort / counts“: Sortoptionen `attributesMost/linksMost` benötigen Counts, selbst wenn UI sie nicht anzeigt.  
  Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` (`taskToken` + `EntitiesHomeSortOption.needs*Counts`)

#### Node Detail Screens: große Scroll‑Compositions
- Datei: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` (+ `EntityDetailView+AttributesSection.swift`)  
  **Grund:** viele Sections, mehrere Sheets, `@Query` für `outgoingLinks`/`incomingLinks`, Media Preview reload in `.onAppear`.
- Datei: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`  
  **Grund:** analoges Muster; riskant bei „Media + Connections“ (große Link‑Sets).

Mitigation, die bereits existiert:
- Media Preview/Counts wird als `NodeMediaPreview` geladen (fetch-limited, nicht „alles laden“).  
  Hinweis im Code: `EntityDetailView` („P0.2: Media preview + counts“).

---

### 2) Sync / Storage

#### SwiftData + CloudKit Container Init + Fallback
- Datei: `BrainMesh/BrainMeshApp.swift`  
  **Grund:** CloudKit init entscheidet über StorageMode; in DEBUG `fatalError` (klarer Fail), in RELEASE Fallback auf local‑only (riskant, wenn User Sync erwartet).
- Datei: `BrainMesh/Settings/SyncRuntime.swift`  
  **Grund:** Diagnostik ist bewusst „best effort“ (AccountStatus ≠ Sync‑Garantie). Erwartungsmanagement wichtig.

#### External Storage (Attachments) + Disk Materialization
- Datei: `BrainMesh/Attachments/MetaAttachment.swift`  
  **Grund:** `fileData` ist `@Attribute(.externalStorage)` → kann große Datenmengen bedeuten, die on-demand geladen werden.
- Datei: `BrainMesh/Attachments/AttachmentHydrator.swift`  
  **Grund:** Fetch `fileData` + Disk write, throttled (AsyncLimiter maxConcurrent:2). Bei vielen Attachments können „cache miss stampedes“ auftreten, wenn nicht gedrosselt.
- Datei: `BrainMesh/Attachments/AttachmentStore.swift`  
  **Grund:** `ensurePreviewURL` mutiert `localPath` (SwiftData write) – muss im UI‑Pfad kontrolliert bleiben.

#### Images: Cloud data → deterministic disk cache
- Datei: `BrainMesh/ImageHydrator.swift`  
  **Grund:** scannt Entities/Attributes mit `imageData != nil` und schreibt JPEG cache files.  
  Auto‑Run: in `AppRootView` max 1×/24h (`BMImageHydratorLastAutoRun`) + per‑launch guard.  
  Datei: `BrainMesh/AppRootView.swift`
- Datei: `BrainMesh/ImageStore.swift`  
  **Grund:** synchronous `loadUIImage(path:)` existiert; falscher Einsatz in `body` wäre sofortiger UI‑Stall.

Migration/Legacy:
- Datei: `BrainMesh/GraphBootstrap.swift`  
  **Grund:** `graphID == nil` wird einmalig migriert. Potenzielles Edge‑Case Risiko: wenn Geräte parallel Daten schreiben, bevor Migration auf allen Devices gelaufen ist. **UNKNOWN:** Ob dafür zusätzliche Guards existieren.

---

### 3) Concurrency / Task Lifetimes / MainActor Contention

Projektweite Rahmenbedingung:
- Build Setting: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Project file).  
  Folge: alles ist „main isolated“, außer explizit `nonisolated`/Actors/Sendable types.

Kritische Stellen:
- `AnyModelContainer` ist `@unchecked Sendable` Wrapper für `ModelContainer`.  
  Datei: `BrainMesh/Attachments/AttachmentHydrator.swift`  
  **Grund:** bewusst unsafe, aber notwendig für Loader/Hydrator Konfiguration.  
  Risiko: Container falsch genutzt (mutating writes off-main) → Data races / SwiftData asserts.
- „Detached Task‑Sprawl“: viele `Task.detached` in `BrainMeshApp.init()` (Loader configure) und in Loaders/Hydrators (background fetch).  
  Dateien: `BrainMesh/BrainMeshApp.swift`, diverse `*Loader.swift`  
  Risiko: unbounded work wenn Callsites nicht sauber cancellen/dedupe’n.
- Dedupe‑Patterns:
  - AttachmentHydrator `inFlight[UUID: Task]`  
    Datei: `BrainMesh/Attachments/AttachmentHydrator.swift`
  - NodeRenameService `inFlight` (Rename relabeling)  
    Datei: `BrainMesh/Mainscreen/LinkCleanup.swift`
  - ImageStore `InFlightLoader` für disk reads  
    Datei: `BrainMesh/ImageStore.swift`

Positive Pattern:
- Value‑only snapshots verhindern das „@Model über Actor Grenze“ Problem.  
  Beispiel: `EntitiesHomeRow`/`EntitiesHomeSnapshot` (Sendable)  
  Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`

---

## Refactor Map

### A) Konkrete Splits (Datei → neue Dateien)

#### 1) `BrainMesh/Models.swift` (515 Zeilen)
Ziel: Macro‑Compile Hotspot reduzieren + bessere Orientierung.
- `BrainMesh/Models/MetaGraph.swift`
- `BrainMesh/Models/MetaEntity.swift`
- `BrainMesh/Models/MetaAttribute.swift`
- `BrainMesh/Models/MetaLink.swift`
- `BrainMesh/Models/MetaDetailFieldDefinition.swift`
- `BrainMesh/Models/MetaDetailFieldValue.swift`
- `BrainMesh/Models/BMSearch.swift` (fold helper)
- `BrainMesh/Models/NodeKind.swift`

Risiko:
- Mittel: SwiftData Macros reagieren empfindlich auf Relationship‑Definitionen; aber die Models sind bereits sauber „one-side inverse“ definiert.

#### 2) `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift` (725 Zeilen)
Ziel: UI + Validation + Persistence entkoppeln.
- `.../DetailsSchemaBuilderView.swift` (Host)
- `.../DetailsSchemaBuilderList.swift` (Liste/Selection)
- `.../DetailsSchemaFieldEditor.swift` (Editor sheet / inline editor)
- `.../DetailsSchemaValidation.swift` (Name uniqueness, pin limits, options parsing)
- `.../DetailsSchemaCommands.swift` (create/update/delete operations, save handling)

Risiko:
- Niedrig–Mittel (hauptsächlich SwiftUI State wiring).

#### 3) `BrainMesh/Settings/Appearance/DisplaySettingsView.swift` (533 Zeilen)
Ziel: schnellere Iteration an Display Settings ohne Merge‑Hölle.
- `DisplaySettingsView.swift` (Host)
- `DisplaySettingsSection+EntitiesHome.swift`
- `DisplaySettingsSection+EntityDetail.swift`
- `DisplaySettingsSection+GraphCanvas.swift`
- `DisplaySettingsSection+Stats.swift`
- `DisplaySettingsSection+Misc.swift`

Risiko:
- Niedrig.

#### 4) Graph Canvas: „State Machine“ aus View ziehen
Dateien:
- `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
- `BrainMesh/GraphCanvas/*` Extensions

Ziel:
- View wird „dumm“, ein `GraphCanvasViewModel` hält:
  - load pipeline (cancel/dedupe)
  - physics tick lifecycle (start/stop)
  - derived caches recompute scheduling
- Erwartung: weniger view invalidation + besser testbar.

Risiko:
- Mittel (viel UI‑State, careful threading nötig).

---

### B) Cache-/Index-Ideen

#### EntitiesHome: Counts / Links
- Aktuell: TTL cache im Loader (8s) + optionales include flags.
- Idee: per Graph persistentes „Counts Snapshot“ (z.B. in-memory + invalidation events), statt häufige Recompute bei Typing.
  - Invalidation Trigger: create/delete Attribute/Link, rename Entity, graph switch.
  - Dateien: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`, `BrainMesh/Mainscreen/LinkCleanup.swift`, create/delete flows.

Risiko:
- Niedrig–Mittel (Staleness/Invalidation correctness).

#### GraphCanvas: adjacency + BFS
- Aktuell: Loader macht (vermutlich) Fetch + Neighborhood BFS.  
  Datei: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- Idee: Loader gibt zusätzlich „adjacency map“ zurück, die UI (Lens/Spotlight) wiederverwenden kann, statt in `LensContext.build` jedes Mal `adj` aus edges zu bauen.  
  Datei: `BrainMesh/GraphCanvas/GraphCanvasTypes.swift` (`LensContext.build`)  
  **Tradeoff:** Memory vs CPU.

**UNKNOWN:** Ob `LensContext.build` aktuell häufig genug läuft, dass das relevant ist (es wird gecached; Trigger‑Frequenz hängt von selection/lens toggles ab).

---

### C) Vereinheitlichungen (Patterns, Services, DI)

- „Loader Config“ Pattern (Container injection) ist konsistent, aber verteilt:  
  `BrainMesh/BrainMeshApp.swift` enthält viele `Task.detached { await X.shared.configure(container: ...) }`.
  - Idee: `LoaderRegistry.configureAll(container:)` als Single Call, um App init zu kürzen.
  - Dateien: `BrainMesh/BrainMeshApp.swift` + neuer `BrainMesh/Support/LoaderRegistry.swift`.
- AppStorage keys: teilweise Strings inline (`"BMActiveGraphID"`, `"BMOnboardingHidden"`, …), teilweise `BMAppStorageKeys`.  
  - Idee: Keys zentralisieren + migrationsafe defaults.
  - Dateien: `BrainMesh/BMAppStorageKeys.swift` (existiert) + callsites.

---

## Risiken & Edge Cases

### Datenverlust / Konsistenz
- Denormalisierte Link Labels (`MetaLink.sourceLabel/targetLabel`) müssen bei Rename konsistent bleiben.  
  Service: `NodeRenameService` (`BrainMesh/Mainscreen/LinkCleanup.swift`)  
  Risiko: Rename‑Flow, der Service nicht aufruft → stale labels.
- Attachments: `localPath` ist nur Cache; darf nicht als „Source of Truth“ missverstanden werden.  
  Datei: `BrainMesh/Attachments/AttachmentStore.swift`

### Migration / Legacy
- `graphID` ist optional und wird migriert.  
  Datei: `BrainMesh/GraphBootstrap.swift`  
  Risiko: Mischzustände (ein Device migriert, anderes noch nicht) → Fetches müssen `nil` korrekt behandeln (einige Loader tun das bereits).

### Offline / Multi-Device
- SwiftData+CloudKit: Konflikte/merges sind systemmanaged.  
  **UNKNOWN:** Ob die App irgendwo explizit Konflikt‑Handling oder „last write wins“ UX macht.

### Security / Lock UX
- Auto‑lock debounce ist bewusst komplex wegen Photos Hidden Album FaceID prompt.  
  Datei: `BrainMesh/AppRootView.swift`, Coordinator: `BrainMesh/Support/SystemModalCoordinator.swift`  
  Risiko: state machine bugs (lock zu früh/zu spät).

---

## Observability / Debuggability

- `os.Logger` Kategorien:
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics`  
    Datei: `BrainMesh/Observability/BMObservability.swift`
- Loaders nutzen teils eigene Logger (`Logger(subsystem: "BrainMesh", category: "...")`).  
  Verbesserung: konsistente Kategorien + durations in Hotspot‑Flows.

Praktische Repro‑Checkliste (manuell):
- Graph Canvas:
  - [ ] Graph mit > 500 Links öffnen → FPS, Pan/Zoom responsiveness
  - [ ] Spotlight (Selection) toggeln → CPU spikes?
- Entities Home:
  - [ ] Suche tippen (10–20 chars) in großem Graph → UI bleibt flüssig?
  - [ ] Counts on/off + Sort by counts → Loader‑Duration
- Media:
  - [ ] Attachment heavy graph → Scroll Media list → Thumbnail throttling ok?

---

## Open Questions (alle UNKNOWNs gesammelt)

- GraphCanvas:
  - Wird die Physics tick rate adaptive/pauseable gemanaged? **UNKNOWN**
  - Begrenzen `maxNodes/maxLinks` den Loader wirklich oder nur Rendering? **UNKNOWN**
- Import/Media:
  - Nutzen alle Import flows `ImportProgress` UI oder gibt es stille Abbrüche? **UNKNOWN**
- Sync:
  - Gibt es eine definierte Migration/Versioning Strategie für SwiftData Schema Changes? **UNKNOWN**
  - Gibt es jemals CloudKit sharing/collab? (im Code nicht sichtbar) **UNKNOWN**
- Performance:
  - Gibt es ein „perf mode“ Logging/metrics toggle (DEBUG)? (aktuell nein) **UNKNOWN**

---

## First 3 Refactors I would do (P0)

### P0.1 — `Models.swift` entknoten (Compile + Macro‑Risiken reduzieren)
- **Ziel:** kleinere Compile Units, weniger Merge‑Konflikte, klarere Ownership von Relationships.
- **Betroffene Dateien:**  
  - `BrainMesh/Models.swift`  
  - `BrainMesh/BrainMeshApp.swift` (Schema‑Liste bleibt, ggf. in `BMModelSchema.swift` auslagern)
- **Risiko:** Mittel (SwiftData Macros/Relationship wiring; Tests/Smoke‑Run nötig)
- **Erwarteter Nutzen:** spürbar bessere Orientierung + weniger „alles in einer Datei“ Änderungen; meist auch bessere Incremental‑Compiles.

### P0.2 — GraphCanvas: View‑State in ViewModel bündeln (Stabilität + Perf)
- **Ziel:** UI invalidation reduzieren, klarere Load/Physics Lifecycle control (cancel/dedupe), bessere Testbarkeit.
- **Betroffene Dateien:**  
  - `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`  
  - `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`  
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- **Risiko:** Mittel–Hoch (viele State‑Abhängigkeiten; Regression in Gestures/Selection möglich)
- **Erwarteter Nutzen:** weniger „state explosion“ im View, klarere Grenzen für MainActor work, weniger Heisenbugs beim schnellen Graph‑Switching.

### P0.3 — Details Schema Builder split + Validation isolieren (Wartbarkeit)
- **Ziel:** `DetailsSchemaBuilderView` in überschaubare Einheiten splitten; Validation/Commands isolieren.
- **Betroffene Dateien:**  
  - `BrainMesh/Mainscreen/Details/DetailsSchemaBuilderView.swift`  
  - neue Files im selben Ordner (siehe Refactor Map A.2)
- **Risiko:** Niedrig–Mittel (SwiftUI wiring)
- **Erwarteter Nutzen:** schnelleres Arbeiten an Custom Fields, weniger regressions in der UI‑Logik, weniger Compile‑Zeit.
