# BrainMesh — ARCHITECTURE_NOTES

> Stand: 2026-02-17
> Fokus: SwiftData/CloudKit Sync + Hot Paths + Wartbarkeit/Performance.

---

## Big Files List (Top 15 nach Zeilen)

> Quelle: `wc -l` über `BrainMesh/**/*.swift`.

| Lines | Path | Zweck (kurz) | Warum riskant |
|---:|---|---|---|
| 694 | `BrainMesh/Stats/GraphStatsService.swift` | Stats Queries + Aggregationen + Trends | Viele Fetches/Counts; schwer testbar; hoher Änderungsdruck. |
| 689 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift` | Sheet/Alert Routing für Detailseiten | SwiftUI-Sheet-State ist fragil; Compile-Time/Type-check Hotspot; leicht Regressionen. |
| 580 | `BrainMesh/Stats/StatsComponents.swift` | Wiederverwendbare Stats UI Komponenten | Große UI-Bibliothek im selben File → Compile-Time; schwierige Ownership/Style-Drift. |
| 532 | `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` | Canvas Rendering | Render Hot Path; teure Path/Canvas ops; invalidation sensitivity. |
| 411 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | Off-main fetch + BFS Neighborhood | Predicate translation Risiken; BFS/Limit Logik komplex; concurrency boundaries. |
| 407 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | „Alle“-Media Manager UI | Paging/thumbnail hydration; viele states; navigation + sheet interactions. |
| 394 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | Connections Card + „Alle“ Navigation | Hot Path auf jeder Detailseite; risk: stuttering / heavy state changes. |
| 360 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | Gallery Grid + Browser Routing | Layout/scroll perf; thumbnail/caching; sheet races. |
| 359 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | Detail shared core components | Viele Abhängigkeiten; wächst schnell; schwierige Reuse-Grenzen. |
| 348 | `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` | Screen Host, state, toolbars | Viele state/overlays; concurrency tasks + routing. |
| 342 | `BrainMesh/PhotoGallery/PhotoGallerySection.swift` | Gallery preview section | Grid + selection + navigation; häufig im Renderpfad. |
| 325 | `BrainMesh/Mainscreen/BulkLinkView.swift` | Bulk linking | Große Picker + save loops; kann lange laufen; cancellation wichtig. |
| 319 | `BrainMesh/Onboarding/OnboardingSheetView.swift` | Onboarding UI | Viele Layouts + state; nicht kritisch für runtime, aber compile-time. |
| 316 | `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` | Gallery browser | Similar: Grid/scroll + selection states. |
| 305 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` | Highlights row (media/links/notes) | Wird oft invalidiert; darf keine DB work im body machen. |

---

## Hot Path Analyse

### 1) Rendering / Scrolling (SwiftUI)

#### Graph Canvas
- **Physics Tick**: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
  - 30 FPS Timer (`Timer.publish(..., on: .main, in: .common)` + `.onReceive`) → MainActor Druck.
  - Repulsion ist grundsätzlich **O(n²)** (Pair loop); im File gibt es Optimierungen (nur `j > i`, Rest-Thresholds, early-outs), aber bei großen Graphen bleibt das der dominante CPU-Faktor.
  - Risk: sobald `nodes.count` groß ist, kann selbst eine leichte Erhöhung der Konstanten (mehr Forces, mehr Constraints) sofort wieder „Very High Energy Impact“ ergeben.

- **Rendering**: `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`
  - Canvas/Path-Erzeugung pro Frame; abhängig von `positions`, `camera`, `edgesForDisplay`.
  - Hotspot-Grund: *expensive computations im Renderpfad* (Path building, text layout, symbol rendering).

#### Medien-Gitter
- **Gallery Grid / Thumbnails**
  - `BrainMesh/PhotoGallery/PhotoGallerySection.swift`, `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - Risiko: viele `Image`/`AsyncImage`-ähnliche Loads + invalidations.
  - Im Projekt existieren dedizierte Caches für Attachments (`AttachmentHydrator`, `AttachmentThumbnailStore`) → gut.

#### Detailseiten (Entity/Attribute)
- **Connections**
  - Default previews kommen aus `@Query` (outgoing/incoming), aber „Alle“ lädt off-main via `NodeConnectionsLoader`.
  - Files: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`, `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`.

**Check**: In den großen Cards sollte *kein* `modelContext.fetch` im `body` sein. Die meisten DB-Arbeiten passieren in `.task`/Loadern (z.B. `EntitiesHomeView`, `GraphCanvasScreen+Loading`, `GraphStatsView+Loading`).

### 2) Sync / Storage (SwiftData/CloudKit)

#### External Storage und "versehentliche Voll-Loads"
- `MetaEntity.imageData`, `MetaAttribute.imageData`: `@Attribute(.externalStorage)` in `BrainMesh/Models.swift`.
- `MetaAttachment.fileData`: `@Attribute(.externalStorage)` in `BrainMesh/Attachments/MetaAttachment.swift`.

**Hotspot-Grund:** Wenn eine Query oder ein Mapping zu früh `imageData`/`fileData` berührt, kann SwiftData große Blobs laden → Memory + IO + Sync-Pressure.

Mitigation im Projekt:
- Media "Alle" Loader mapped bewusst nur Metadaten (kein `fileData`): `BrainMesh/Attachments/MediaAllLoader.swift`.
- Progressive Cache-Hydration holt `fileData` nur bei Bedarf (throttled + deduped): `BrainMesh/Attachments/AttachmentHydrator.swift`.

#### Predicate Translation / in-memory filtering
- Explizit adressiert bei Attachments:
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` erklärt, dass OR-Predicates bei `externalStorage` gefährlich sind.
  - `BrainMesh/Attachments/MediaAllLoader.swift` hält Predicates AND-only und migriert legacy `graphID == nil` pro Owner.

- Noch vorhandene OR/Contains Patterns, die potentiell in-memory filtering triggern können:
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift` (`gid == nil || e.graphID == gid || e.graphID == nil`).
  - `BrainMesh/Mainscreen/NodePickerLoader.swift` (gleiches Muster).
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
    - Global load: `e.graphID == gid || e.graphID == nil`, `l.graphID == gid || l.graphID == nil`.
    - Neighborhood BFS: `frontierIDs.contains(l.sourceID) || frontierIDs.contains(l.targetID)`.

**Status:** Ob `contains`/OR hier store-translatable ist, ist **UNKNOWN** und sollte mit Instruments (SwiftData SQL Logging / Time Profiler) geprüft werden.

### 3) Concurrency

#### Off-main Loaders
- Pattern: actor + `Task.detached(priority: .utility)` + eigener `ModelContext`, Rückgabe als DTO/Snapshot.
- Konfiguration zentral: `BrainMesh/BrainMeshApp.swift` (mehrere `Task.detached { await X.shared.configure(...) }`).

**Risiken:**
- Snapshot Typen sind oft `@unchecked Sendable` (z.B. `GraphCanvasSnapshot`, `GraphStatsSnapshot`).
  - Vorteil: schnell integrierbar.
  - Risiko: falls Snapshot später referenz-typen enthält → Data races möglich.

#### Task lifetime / cancellation
- Loader loops prüfen teilweise Cancellation (`Task.checkCancellation`, `Task.isCancelled`).
  - Beispiel: `GraphStatsLoader.loadSnapshot(...)` (`BrainMesh/Stats/GraphStatsLoader.swift`).
  - BFS loop in `GraphCanvasDataLoader` prüft `Task.isCancelled`.

#### MainActor contention / Locks
- Auto-Lock bei Background wird **debounced** und respektiert Systemmodals:
  - `BrainMesh/AppRootView.swift` + `BrainMesh/Support/SystemModalCoordinator.swift`.
- Das ist explizit als Fix für Photos Hidden Album + FaceID Flaps kommentiert.

---

## Refactor Map

### A) Konkrete Splits (Wartbarkeit + Compile-Time)

1) `BrainMesh/Stats/GraphStatsService.swift` → Split in Services/Extensions
- Vorschlag:
  - `GraphStatsService+Counts.swift`
  - `GraphStatsService+Media.swift`
  - `GraphStatsService+Structure.swift`
  - `GraphStatsService+Trends.swift`
- Nutzen:
  - geringeres Risiko beim Ändern einzelner Stats
  - besseres Test-Splitting (Mock context / fixture data)

2) `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift` → Sheet-Routing entkoppeln
- Vorschlag:
  - „Sheet State“ in `NodeDetailSheetState.swift` (struct + enums)
  - „Actions“ in `NodeDetailSheetActions.swift` (pure functions)
  - UI Binding Layer bleibt in View.
- Nutzen:
  - weniger SwiftUI type-check complexity
  - weniger „blank sheet race“ risk

3) `BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift` → Render Helpers extrahieren
- Vorschlag:
  - `GraphCanvasRenderPrimitives.swift` (Path building)
  - `GraphCanvasLabelLayout.swift` (Text measurement/placement)
- Nutzen:
  - klarere Perf-Tuning Hooks

### B) Graph Scope / Legacy cleanup (Performance + Simplification)

Ziel: **kein** `graphID == nil` in laufenden Predicates, außer beim echten "all graphs" Modus.

- Aktuell:
  - Viele Queries tragen legacy `|| x.graphID == nil` mit.
  - Attachments haben bereits eine gezielte Migration (gut): `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.

- Vorschlag:
  - Einmalige Background-Migration beim App-Start:
    - `GraphBootstrap.ensureDefaultGraphAndAssignMissingGraphIDs(in:)` (`BrainMesh/GraphBootstrap.swift`) erweitern:
      - Entitäten, Attribute, Links, Attachments: alle `graphID == nil` → DefaultGraphID.
  - Danach: Predicates vereinfachen:
    - `EntitiesHomeLoader`, `NodePickerLoader`, `GraphCanvasDataLoader`, `NodeLinksQueryBuilder`.

**Risiko:** moderat (Daten-Scope ändert sich, aber deterministisch).

### C) BFS / Neighborhood Loading robust machen

Problem: `frontierIDs.contains(...)` in `#Predicate` könnte in-memory filtering triggern.

Optionen:
1. **Zweiphasig**
   - Phase 1: fetch Links pro graph/kind mit engem Limit (AND-only) → in-memory adjacency.
   - Phase 2: BFS rein in-memory.
   - Datei: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`.

2. **Materialisierte Adjazenz** (**größerer Eingriff**)
   - zusätzliche SwiftData Tabelle „Adjacency“ oder „EdgeIndex“ (denormalisiert) → schnelle neighbor queries.
   - Risiko: Migration + Consistency.

---

## Cache-/Index-Ideen

1) **Per-Graph Stats Cache**
- Speichere letzten Stats Snapshot pro Graph in SwiftData/Defaults, UI zeigt sofort cached values.
- Invalidations:
  - beim Insert/Delete von Entity/Attribute/Link/Attachment.
- Betroffene Dateien:
  - `BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/Stats/GraphStatsService.swift`.

2) **Degree Cache für Hubs**
- Für „Top-Hubs“ / Dichte-Trends könnte ein kleines „degree counter“ pro Node gepflegt werden.
- Heute: vermutlich counts via fetches; OK für kleine DB, aber skaliert schlecht.

3) **Thumbnail warm-up**
- Für die „Alle“-Screens könnte beim Öffnen eine Batch-Anfrage an `AttachmentThumbnailStore` erfolgen (limitiert), statt nur „onAppear pro Zelle“.
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`, `BrainMesh/Attachments/AttachmentThumbnailStore.swift`.

---

## Vereinheitlichungen (Patterns, Services, DI)

- **Ein Loader-Protocol**
  - z.B. `protocol ConfigurableLoader { func configure(container: AnyModelContainer) }`.
  - Vorteil: `BrainMeshApp` DI Block wird homogener.

- **Graph Scope Helper**
  - eine zentrale Funktion pro Model:
    - `PredicateFactory.entity(in graphID: UUID?)` etc.
  - reduziert Copy/Paste Predicates.

- **Delete Semantics**
  - heute: Links/Attachments werden teilweise manuell entfernt (z.B. `EntitiesHomeView.deleteEntities`, `AttachmentCleanup`).
  - Vereinheitlichen: „DeleteNodeService“ (löscht Node + Links + Attachments in einer Transaktion).

---

## Risiken & Edge Cases

- **Datenverlust / Scope Drift**
  - Migration von `graphID == nil` kann Verhalten verändern (legacy Inhalte werden eindeutig einem Graph zugeordnet).
  - Deshalb: vor Migration einmal "backup" Export (**UNKNOWN** ob Export/Import im Projekt existiert).

- **CloudKit Limits**
  - Große `externalStorage` Blobs (Attachments/Images) könnten CloudKit Record Limits berühren.
  - Max Attachment Bytes ist im UI als 25MB gesetzt (`BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`), aber CloudKit Limit Details sind **UNKNOWN**.

- **Kein Cascade Delete**
  - MetaAttachment ist nicht per Relationship verbunden → Owner delete muss Cleanup machen.
  - Siehe `BrainMesh/Attachments/AttachmentCleanup.swift` und Delete-Flows in Home/Detail.

- **Lock vs System Picker**
  - ScenePhase kann während FaceID-Prompts flappen; das wird in `BrainMesh/AppRootView.swift` explizit behandelt.
  - Regression-Risiko hoch, wenn man Lock-Mechanik ändert.

---

## Observability / Debuggability

### Bestehende Tools
- `BMLog` Kategorien + `BMDuration`: `BrainMesh/Observability/BMObservability.swift`.

### Empfohlene Messpunkte
- **Loader Durations**
  - EntitiesHome: around `EntitiesHomeLoader.loadSnapshot`.
  - GraphCanvas: around `GraphCanvasDataLoader.loadSnapshot` + Render first frame.
  - Stats: around `GraphStatsLoader.loadSnapshot`.

- **SwiftData Query Translation**
  - Profiling mit Instruments + ggf. SwiftData debug logging (OS env) (**UNKNOWN** welche Logs du aktiv nutzt).

### Repro Checklists
- GraphCanvas perf:
  - Graph mit 500/1000 Nodes laden → zoomen, pan, 30s laufen lassen.
  - CPU/Energy beobachten, insbesondere in `GraphCanvasView+Physics.swift`.

- Attachments:
  - „Alle“ öffnen bei 0/200/2000 attachments.
  - Prüfen ob `fileData` lazy bleibt (Memory spike = Hinweis auf Voll-load).

---

## Open Questions (alles was nicht gesichert ist)

- SwiftData/CloudKit Conflict Resolution / Merge Policy: **UNKNOWN** (nicht konfiguriert; SwiftData intern).
- SwiftData Predicate Translation Status für:
  - OR über optional graphID (`x.graphID == gid || x.graphID == nil`): **UNKNOWN**.
  - `frontierIDs.contains(...)` in `#Predicate`: **UNKNOWN**.
- Export/Import/Backup Mechanismus: **UNKNOWN** (im ZIP kein offensichtlicher Export-Flow gefunden).
- CloudKit Record/Asset Limits, die hier relevant werden: **UNKNOWN**.

---

## First 3 Refactors I would do (P0)

### P0.1 — Graph Scope „Legacy nil“ eliminieren
- **Ziel**: Weg von OR-Predicates und "nil-legacy" überall; dadurch weniger in-memory filtering Risiko + einfachere Queries.
- **Betroffene Dateien**:
  - Migration: `BrainMesh/GraphBootstrap.swift` (erweitern)
  - Queries/Loader: `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`, `BrainMesh/Mainscreen/NodePickerLoader.swift`, `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- **Risiko**: Mittel (Scope-Änderung für legacy Daten; braucht klare DefaultGraph Semantik).
- **Erwarteter Nutzen**: Spürbarer Performance-Boost bei großen DBs + weniger SwiftData Überraschungen.

### P0.2 — GraphCanvas Neighborhood Loading absichern
- **Ziel**: Keine store-untranslatable `contains` Predicates; BFS planbar und skalierbar.
- **Betroffene Dateien**:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
- **Risiko**: Mittel (mehr Code, aber gut testbar über deterministische Snapshots).
- **Erwarteter Nutzen**: Stabilere Ladezeiten (keine Random-Spikes), weniger Memory.

### P0.3 — NodeDetail Sheets & Stats Service splitten (Wartbarkeit)
- **Ziel**: Compile-Time runter, klarere Zuständigkeiten, weniger SwiftUI Sheet-Races.
- **Betroffene Dateien**:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift`
  - `BrainMesh/Stats/GraphStatsService.swift`
- **Risiko**: Niedrig bis Mittel (hauptsächlich mechanisches Splitten, wenig Logikänderung).
- **Erwarteter Nutzen**: Schnellere Iteration, weniger "compiler is unable to type-check" Situationen, weniger Regressionen.
