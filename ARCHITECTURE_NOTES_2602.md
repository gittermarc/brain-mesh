# ARCHITECTURE_NOTES.md — BrainMesh

## Scope / Reading Guide
Diese Notizen fokussieren auf (1) Sync/Storage/Model (SwiftData/CloudKit), (2) Entry Points + Navigation, (3) große Views/Services (Wartbarkeit/Performance), (4) Konventionen/Workflows. Aussagen sind auf Basis dieses ZIP-Standes; alles nicht belegbare ist als **UNKNOWN** markiert.

---

## Big Files List (Top 15 nach Zeilen)

> Basis: Swift-Dateien im App-Target (`BrainMesh/BrainMesh/…`). Andere Filetypen wurden nicht gerankt.

| # | Datei | Zeilen | Zweck | Warum riskant |
|---:|---|---:|---|---|
| 1 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | 411 | Off-main Snapshot Loader für Graph Canvas (Entities/Links fetch + BFS hops + caches). | Komplexe Query-Logik + mehrere Fetches; Performance/Cancel/Memory sensitiver Codepfad beim Öffnen/Switching. |
| 2 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 410 | Gallery Management Screen (paginated list, set main photo, delete, viewer). | UI + Pagination + MediaAllLoader Integration; viele State-Transitions, Fehler-/Edge-Handling. |
| 3 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` | 388 | Home Tab Orchestrator (search, sort, grid/list, toolbars, sheets). | Viele UI States + Navigation/Sheets; leicht für Regressions bei Änderungen in Toolbar/Navigation. |
| 4 | `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` | 388 | Details Card (render schema fields + values, edit/configure). | Expensive computations im Renderpfad (map/filter + value lookup); Risiko für Scroll/Jank bei vielen Feldern. |
| 5 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` | 379 | Off-main Loader für EntitiesHome (rows + counts caches). | Cache/TTL + mehrere Fetch-Strategien; Korrektheit vs Performance Tradeoffs. |
| 6 | `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` | 375 | Graph Tab Screen Orchestrator (loading state, inspector, overlays, commands). | Zentraler Navigations-/State-Knoten; Änderungen können Graph UX und Performance beeinflussen. |
| 7 | `BrainMesh/Mainscreen/BulkLinkView.swift` | 367 | Bulk-Link Flow UI (select targets, duplicate detection, create links). | Viele Kombinatorik-States; hohe Fehlergefahr bei Änderungen an Duplicate-Detection/Confirmation. |
| 8 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 362 | Media/Gallery Section für Entity/Attribute Detail. | Kann viele Items rendern; potenziell teure Thumbnail/Preview Work; Interaktion mit Hydrators. |
| 9 | `BrainMesh/Icons/AllSFSymbolsPickerView.swift` | 357 | SF Symbols Picker (search/filter über große Symbol-Liste). | Große Datenmenge in SwiftUI List; Filter/Sort im Renderpfad kann teuer werden. |
| 10 | `BrainMesh/PhotoGallery/PhotoGallerySection.swift` | 344 | Photo Gallery UI Section (viewer, pickers, actions). | System modals + asset loading + navigation; edge cases (FaceID Hidden album) relevant. |
| 11 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` | 341 | Connections 'Alle' View (große Link-Listen + actions). | Viele Zeilen/Features; Gefahr für Main-thread jank bei großen Link-Mengen ohne Loader. |
| 12 | `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` | 331 | Markdown editing accessory UI (toolbar, actions). | UIKit bridge/Responder chain empfindlich; Regression-Risiko bei Keyboard/Focus. |
| 13 | `BrainMesh/Attachments/AttachmentImportPipeline.swift` | 326 | Import Pipeline für Attachments (UTTypes, file IO, optional video compression). | Potentiell große Dateien; Memory/IO/Concurrency; braucht Cancellation/Progress. |
| 14 | `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` | 318 | Full-screen Browser für Gallery Items. | Viele Images/Thumbnails; scroll performance; viewer state. |
| 15 | `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` | 317 | Stats Tab UI (dashboard + breakdown). | Viele derived values + charts; hängt an Loader/Services; Gefahr für layout thrash. |

---

## Hot Path Analyse

### Rendering / Scrolling

#### GraphCanvas: Physics Tick (O(n²) pro Frame)
- Pfad: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Konkreter Grund:
  - `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` → 30 FPS Tick auf dem Main RunLoop.
  - Repulsion + Collision im Pair-Loop: `for i in 0..<simNodes.count` + innerer `for j in (i + 1)..<simNodes.count` → **O(n²)**.
  - State Updates pro Tick (`positions = pos`, `velocities = vel`) → hohe View-Invalidation/Redraw-Frequenz.
- Mitigations, die bereits existieren:
  - `simulationAllowed` Gate + stop auf disappear (siehe `GraphCanvasView.swift`)
  - Spotlight/Relevant-Set (`physicsRelevant`) reduziert SimNodes.
  - Sleep-Mechanik (`physicsIdleTicks` / `physicsIsSleeping`) → vorhanden (Details in File).

#### GraphCanvas: Rendering Cache Build (O(n+m) pro Frame)
- Pfad: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift`
- Konkreter Grund:
  - `buildFrameCache(...)` läuft pro Canvas-Render und iteriert:
    - über `nodes` (ScreenPoint + label offset)
    - über `drawEdges` (defensive endpoint fill + label offset)
  - Zusätzlich optional: `prepareOutgoingNotes(...)` iteriert über `directedEdgeNotes` (bei Selection + showNotes).
- Mitigations, die bereits existieren:
  - `reserveCapacity` + deterministische label offsets (keine random allocations)
  - Prefilter für outgoing notes (nur wenn selection + zoom erlaubt)

#### Details: Value Lookup in Renderpfad (O(fields * values))
- Pfade:
  - UI: `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
  - Formatting: `BrainMesh/Mainscreen/Details/DetailsFormatting.swift`
- Konkreter Grund:
  - `NodeDetailsValuesCard.rows` mappt `owner.detailFieldsList` und ruft `DetailsFormatting.displayValue(for:on:)` pro Feld.
  - `DetailsFormatting.displayValue(for:on:)` sucht pro Feld per `attribute.detailValuesList.first(where:)` den passenden Value.
  - Bei vielen Feldern + vielen Werten ergibt das **O(fields * values)** pro Render-Invalidation.
- Mitigation im Code:
  - Es existiert bereits eine overload `displayValue(for:value:)` „mit pre-fetched value“ (Hinweis im Kommentar).
  - Der aktuelle Card-Code nutzt diese Optimierung noch nicht.

#### All SF Symbols Picker (große Liste)
- Pfad: `BrainMesh/Icons/AllSFSymbolsPickerView.swift`
- Konkreter Grund:
  - UI zeigt potentiell sehr große Listen (alle SF Symbols).
  - Filter/Sort während Search kann schnell teuer werden (insb. wenn es im body computed wird).
- **UNKNOWN**: Ob Symbol-Liste lazy geladen/cached wird (müsste man im File prüfen; hier nur über Dateigröße als Indikator).

#### EntitiesHome: Search + Row Snapshot + Counts
- Pfade:
  - UI: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - Loader: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Konkreter Grund:
  - Searchable Text + debounce → regelmäßige Snapshot Loads beim Tippen.
  - Loader hält graph-weite Counts-Caches (`countsCache`, `linkCountsCache`) mit kurzer TTL (8s).
  - Counts erfordern typischerweise breite Fetches (Attributes/Links) je Graph-Context.

### Sync / Storage

#### SwiftData CloudKit Boot (Cold Start)
- Pfad: `BrainMesh/BrainMeshApp.swift`
- Konkreter Grund:
  - `ModelContainer` init mit CloudKit kann (geräte-/netzabhängig) spürbar sein.
  - DEBUG: `fatalError` (kein Fallback) → harte Crash-Failure bei Signing/Entitlement Problemen.
  - Release: local-only Fallback → App startet, aber Sync fällt still aus (UI muss das erklären).

#### External Storage + Predicate-Fallen (Attachments)
- Pfade:
  - Model: `BrainMesh/Attachments/MetaAttachment.swift` (`@Attribute(.externalStorage) var fileData: Data?`)
  - Migration Guard: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- Konkreter Grund:
  - OR-Predicates wie „graphID ist nil ODER graphID ist gleich active“ können SwiftData zwingen, in-memory zu filtern.
  - Bei externalStorage Blobs bedeutet das potentiell: **viel Data wird geladen**, nur um anschließend wegzufiltern.
  - Das Migration-Utility existiert explizit, um Predicates als AND ausdrücken zu können.

#### Progressive Hydration (Attachments)
- Pfad: `BrainMesh/Attachments/AttachmentHydrator.swift`
- Konkreter Grund:
  - „fetch external data + disk write“ ist teuer; Hydrator throttled global (`AsyncLimiter(maxConcurrent: 2)`) und deduped per attachment id.
  - Hydration wird bewusst so designt, dass sie aus List-Cells heraus aufgerufen werden kann (visibility-driven).

### Concurrency

#### Loader Pattern: Actor + Task.detached + ModelContext
- Beispiele:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
- Konkrete Punkte:
  - Loader speichern `AnyModelContainer` (Sendable wrapper) und erzeugen short-lived `ModelContext` in detached tasks.
  - Cancellation ist teilweise berücksichtigt (`Task.isCancelled` in GraphCanvas BFS).
  - DTOs sind häufig `@unchecked Sendable` → Tradeoff: weniger Boilerplate, aber Sicherheit hängt an „value-only“ Disziplin.

#### Throttling / Dedupe Patterns
- `BrainMesh/Support/AsyncLimiter.swift` ist ein kleines Semaphore-Actor.
- `AttachmentHydrator` kopiert `container` lokal, weil `AsyncLimiter.withPermit` in limiter-Isolation läuft und nicht auf hydrator-state zugreifen darf (Kommentar im Code zeigt bewusstes Actor-Isolation Denken).

---

## Refactor Map (konkret)

### 1) Details-Values Index (Performance + Simplify)
**Ziel:** `O(fields * values)` in Details-Rendering eliminieren; UI deterministischer/leichter testbar.

- Betroffene Dateien:
  - `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
  - `BrainMesh/Mainscreen/Details/DetailsFormatting.swift`
- Konkreter Cut:
  - Neu: `BrainMesh/Mainscreen/Details/DetailValuesIndex.swift`
    - baut `Dictionary<UUID, MetaDetailFieldValue>` für ein Attribut (key = `fieldID`)
    - optional: liefert bereits formatierte Strings als `[UUID: String]`
  - `NodeDetailsValuesCard` nutzt `displayValue(for:value:)` (pre-fetched) statt `displayValue(for:on:)`.
- Risiko: niedrig (rein read-only Darstellung; keine Persistenzänderungen).
- Nutzen: spürbar bei vielen Detail-Feldern + Scroll/Edits; weniger Invalidation cost.

### 2) GraphCanvas Physics Scaling
**Ziel:** GraphCanvas bei großen Graphen stabil flüssig halten (Battery + CPU).

- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - (optional) `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift` (Scheduler/Gates)
- Konkrete Optionen:
  1) **Spatial Hash / Grid Buckets**: nur Paare im lokalen Umfeld für Collision/Repulsion prüfen (reduziert Pair Checks massiv).
  2) **Hard Cap SimNodes**: bei `nodes.count > N` automatisch `physicsRelevant` auf subset (Selection neighborhood, pinned, viewport).
  3) **Adaptive Tick Rate**: bei hoher Node-Zahl → 15 FPS, bei idle → sleep schneller.
- Risiko: mittel (Layout-Verhalten ändert sich; Nutzer merkt „anderes“ Physikgefühl).
- Nutzen: großer Performance-Hebel; weniger MainActor contention.

### 3) GraphCanvasDataLoader: Adjacency Cache / Fewer Fetches
**Ziel:** beim Wechseln von Fokus/Selection nicht pro Hop erneut Link-Fetches aus SwiftData machen.

- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - (optional) `BrainMesh/Mainscreen/LinkCleanup.swift` (Invalidation Hooks nach Link-Änderungen)
- Konkreter Vorschlag:
  - In `GraphCanvasDataLoader` einen graph-scoped Cache: `adjacency: [UUID: [UUID]]` + `linksByNode`.
  - Aufbau per **einmaligem** Fetch der relevanten Links (z.B. entity-entity links für Graph).
  - BFS läuft dann rein in-memory.
  - Invalidierung:
    - simpel: TTL (z.B. 2–5s) oder link-count watermark.
    - besser: explizit beim Link-Create/Delete via Service call (falls zentraler Link-Service existiert → **UNKNOWN**).
- Risiko: mittel (Cache invalidation correctness, memory footprint).
- Nutzen: schnellere Graph-Interaktion, weniger SwiftData load spikes.

### 4) AttachmentImportPipeline Splits (Wartbarkeit + Cancellation)
**Ziel:** Import/Compression Pfad testbarer machen, Memory/IO besser kontrollieren.

- Betroffene Dateien:
  - `BrainMesh/Attachments/AttachmentImportPipeline.swift`
  - `BrainMesh/Attachments/VideoCompression.swift`
  - `BrainMesh/Settings/VideoImportPreferences.swift`, `BrainMesh/Settings/ImageGalleryImportPreferences.swift` (wenn Preferences Einfluss haben)
- Konkreter Cut:
  - `AttachmentImportPipeline+UTType.swift` (type detection, metadata)
  - `AttachmentImportPipeline+Copy.swift` (file copy, temp urls)
  - `AttachmentImportPipeline+Compression.swift` (video/image compression)
  - Zentrales Cancellation token / progress reporting (z.B. `AsyncStream`), wenn UI Fortschritt zeigen soll.
- Risiko: niedrig bis mittel (Import-Fehlerfälle; Filesystem).
- Nutzen: geringere Fehlerquote, bessere Debriefbarkeit.

---

## Cache-/Index-Ideen

- **Details Values Index** (siehe Refactor #1): map `fieldID -> value` pro Attribute.
- **GraphCanvas Adjacency** (siehe Refactor #3): `nodeID -> neighborIDs` + optional edge metadata.
- **Link Counts / Entity Counts**: existiert schon in `EntitiesHomeLoader` als graph-weite TTL cache; könnte ergänzt werden um Invalidations nach Mutationen.
- **Disk Cache Housekeeping**:
  - Images: `BrainMesh/ImageStore.swift` (Application Support / BrainMeshImages)
  - Attachments: `BrainMesh/Attachments/AttachmentStore.swift` (Application Support / BrainMeshAttachments)
  - Idee: maintenance pass „delete files without matching SwiftData record“ (nur wenn record list fetch cheap ist; ansonsten incremental).

---

## Vereinheitlichungen (Patterns / DI / Services)

- Loader/Hydrator Pattern ist bereits konsistent:
  - `configure(container:)` in `AppLoadersConfigurator`
  - `loadSnapshot` / `ensure...` APIs
- Potenzielle Vereinheitlichungen:
  - Ein gemeinsames `LoaderCancellationBag` Pattern für Views (statt ad-hoc Task vars) → reduziert stale updates.
  - Zentraler „Links Service“ (Create/Delete/Rename hooks) um Cache invalidation an einer Stelle zu bündeln → **UNKNOWN** ob es bereits einen zentralen Service gibt (teilweise in `LinkCleanup` / `NodeRenameService`).

---

## Risiken & Edge Cases

### Datenverlust / Konsistenz
- Release Fallback auf local-only Storage bei CloudKit init failure:
  - Risiko: User arbeitet lokal weiter, erwartet Sync, merkt es später.
  - Mitigation: `SyncRuntime` UI sichtbar machen (bereits vorhanden).

### Migration / Schema Changes
- Keine explizite Model-Versionierung im Repo → **UNKNOWN** wie produktive Migrationen gehandhabt werden.
- GraphID Migration existiert (Entities/Attributes/Links + Attachments), aber:
  - Weitere zukünftige Felder benötigen definierte Strategie (z.B. defaults wie `MetaGraph.createdAt = .distantPast` um „Neuheit“ zu vermeiden).

### Offline / Multi-Device
- SwiftData + CloudKit: Konfliktauflösung und Merge-Policy sind SwiftData-intern → **UNKNOWN**.
- Denormalisierte Link Labels:
  - `MetaLink.sourceLabel/targetLabel` müssen nach Rename aktualisiert werden.
  - `NodeRenameService` macht das, aber bei Multi-Device Rename/Conflict: **UNKNOWN** (keine expliziten conflict handlers).

### Large Blobs
- `MetaAttachment.fileData` externalStorage:
  - IO-Spikes bei Preview/Share/Export.
  - `AttachmentHydrator` reduziert Stampedes, aber große Files sind per se teuer.

### System Modals / FaceID
- Es gibt gezielte Guards um „Photos Hidden album“ FaceID Edge Case:
  - `BrainMesh/Support/SystemModalCoordinator.swift`
  - Debounced background lock in `BrainMesh/AppRootView.swift`

---

## Observability / Debuggability

- `BrainMesh/Observability/BMObservability.swift`
  - `BMLog.load/expand/physics` als zentrale Logger
  - `BMDuration` für Timing
- Viele Loader nutzen zusätzlich eigene `Logger(subsystem: "BrainMesh", category: "...")`.
- Vorschläge:
  - Einheitliche Kategorien (z.B. `load.graphcanvas`, `load.entityhome`, `hydrate.attachments`) statt ad-hoc.
  - Optional: `os_signpost` für Cold Start / Loader durations (requires Instruments workflow).

---

## Open Questions (alles, was **UNKNOWN** ist)

1) **CloudKit Details**: nutzt SwiftData automatisch private DB / Custom Zones / Subscriptions? (ModelConfiguration `.automatic` versteckt Details)
2) **Schema Versioning**: Gibt es irgendwo im Projekt einen Plan für Model-Migrationen im App Store? (keine Version Files gefunden)
3) **Collaboration/Sharing**: Gibt es CKShare/Shared DB Support? (kein Code dafür gefunden)
4) **Analytics/Crash Reporting**: Wird irgendetwas genutzt? (kein SDK/Config gefunden)
5) **SPM Dependencies**: Lokal evtl. vorhanden, aber nicht im Repo. (pbxproj hat keine Remote package refs)
6) **Performance Budgets**: Zielwerte für GraphCanvas Nodes/Edges? (keine hard limits außer maxNodes/maxLinks in Loader)

---

## First 3 Refactors I would do (P0)

### P0.1 — Details Values Index
- Ziel: Details Rendering von O(fields*values) auf O(fields+values) bringen; Scroll/Edits entjanken.
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`
  - `BrainMesh/Mainscreen/Details/DetailsFormatting.swift`
  - neu: `BrainMesh/Mainscreen/Details/DetailValuesIndex.swift`
- Risiko: niedrig
- Erwarteter Nutzen: mittel bis hoch (je nach Anzahl Felder/Werte); weniger UI invalidation cost.

### P0.2 — GraphCanvas Physics Scaling Guardrails
- Ziel: Große Graphen ohne CPU-Spikes; weniger MainActor contention; bessere Battery.
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - optional: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift`
- Risiko: mittel
- Erwarteter Nutzen: hoch (Hot Path, O(n²) Reduktion).

### P0.3 — GraphCanvasDataLoader Adjacency Cache
- Ziel: Weniger SwiftData Fetches bei Fokus-/Selection-Wechseln; schnellere Graph Interaktion.
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - optional: Services/Hooks für Cache invalidation (**UNKNOWN** wo am besten)
- Risiko: mittel
- Erwarteter Nutzen: mittel bis hoch (abhängig von hop usage und DB Größe).
