# ARCHITECTURE_NOTES — BrainMesh

> Fokus: Sync/Storage/Model → Entry Points/Navigation → große Views/Services → Konventionen/Workflows.  
> Alles, was nicht aus dem Repo ableitbar war, ist als **UNKNOWN** markiert und in „Open Questions“ gesammelt.

## Key Files (Orientierung)
- `BrainMeshApp.swift` — App entrypoint / SwiftData container creation + CloudKit config
- `AppRootView.swift` — Startup orchestration, auto-lock, system-modal handling
- `Models.swift` — SwiftData models (Graph/Entity/Attribute/Link)
- `Attachments/MetaAttachment.swift` — SwiftData model for attachments
- `ImageStore.swift` — Disk + memory cache for JPEGs
- `ImageHydrator.swift` — Hydration of cached JPEG files
- `GraphBootstrap.swift` — Legacy graphID migration + ensure default graph
- `Attachments/AttachmentHydrator.swift` — On-demand externalStorage blob materialization (throttled)
- `Attachments/MediaAllLoader.swift` — Off-main list loading for 'Alle' media screen
- `Attachments/AttachmentThumbnailStore.swift` — Thumbnail generation (QuickLook/ImageIO) + throttling
- `GraphCanvas/GraphCanvasScreen+Loading.swift` — Graph data fetch + caches (nodes/edges/labels/icons/images)
- `GraphCanvas/GraphCanvasView+Physics.swift` — 30 FPS physics simulation (O(n^2) pair loop)
- `GraphCanvas/GraphCanvasView+Rendering.swift` — Rendering layer + thumbnail decode pipeline
- `GraphStatsService.swift` — Graph stats aggregation via fetchCount

## Big Files List (Top 15 nach Zeilen)
| # | Datei | Zeilen | Grober Zweck | Warum riskant |
|---:|---|---:|---|---|
| 1 | `GraphStatsView.swift` | 1152 | Stats-Tab UI (Dashboards/Listen/Charts für Graph(en)). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken |
| 2 | `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` | 726 | Shared Media-Sektion für Entity/Attribute-Details (Gallery + Attachments + Navigation). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken; mehrere `Task`/`Task.detached` → Cancellation/Lifetime komplex |
| 3 | `GraphStatsService.swift` | 695 | Zähl-/Aggregations-Service via `fetchCount` (GraphCounts, Rankings, Trends). | viele SwiftData `fetch`/`fetchCount` → potenziell I/O/DB-Druck; viele `#Predicate` → Compiler/Predicate-Übersetzung empfindlich |
| 4 | `Mainscreen/NodeDetailShared/NodeDetailShared+SheetsSupport.swift` | 689 | Shared Sheet-State + Präsentationslogik (Preview, Picker, Manage-Flows). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken; mehrere `Task`/`Task.detached` → Cancellation/Lifetime komplex |
| 5 | `GraphCanvas/GraphCanvasView+Rendering.swift` | 532 | Canvas-Rendering (Node-Layer, Labels, Thumbs, Caches). | manuelle Threads/Queues → Synchronisation & Main-Thread-Risiko; pro-Frame Arbeit → Skaliert direkt mit Node/Edge-Anzahl |
| 6 | `GraphCanvas/GraphCanvasScreen+Loading.swift` | 425 | Graph-Daten laden (SwiftData fetch → GraphNode/GraphEdge, Label/Image/Icon-Caches). | viele SwiftData `fetch`/`fetchCount` → potenziell I/O/DB-Druck; viele `#Predicate` → Compiler/Predicate-Übersetzung empfindlich |
| 7 | `Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 408 | ‘Bilder verwalten’ Screen inkl. Paging/Loader (galleryImage Attachments). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken; mehrere `Task`/`Task.detached` → Cancellation/Lifetime komplex |
| 8 | `Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift` | 359 | Shared Detail-Bausteine (Header/Hero, Async Image Loader). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken; mehrere `Task`/`Task.detached` → Cancellation/Lifetime komplex |
| 9 | `GraphCanvas/GraphCanvasScreen.swift` | 348 | Graph-Tab Host (State, Toolbar, Sheet/Overlay Routing). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken |
| 10 | `PhotoGallery/PhotoGallerySection.swift` | 342 | Shared Galerie-Sektion in Details (Grid Preview, Navigation). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken |
| 11 | `Mainscreen/BulkLinkView.swift` | 325 | Bulk-Linking UI (mehrere Nodes verbinden, Dedupe/Validation). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken |
| 12 | `Onboarding/OnboardingSheetView.swift` | 319 | Onboarding Sheet Host (Step Navigation, Progress). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken; mehrere `Task`/`Task.detached` → Cancellation/Lifetime komplex |
| 13 | `PhotoGallery/PhotoGalleryBrowserView.swift` | 316 | Galerie Vollansicht (Grid/Paging, Viewer Navigation). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken |
| 14 | `Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` | 311 | Shared Connections-Sektion (Links, Queries, UI). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken |
| 15 | `Mainscreen/EntitiesHomeView.swift` | 307 | Entitäten-Tab Root (Graph-scoped List + Search + Sheets). | Große SwiftUI-View → Compile-Time + Invalidations schwer zu überblicken; viele SwiftData `fetch`/`fetchCount` → potenziell I/O/DB-Druck |

## Hot Path Analyse
### Rendering / Scrolling
- **GraphCanvas Simulation (CPU)**
  - `GraphCanvas/GraphCanvasView+Physics.swift`
    - Timer: `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` → 30 FPS.
    - Kernschleife: repulsion + collisions in einem Pair-Loop `for i in 0..<simNodes.count { for j in (i+1)..<simNodes.count { ... } }` → **O(n²)** in `simNodes`.
    - Mitigation vorhanden: Spotlight-Relevanzfilter `physicsRelevant` reduziert `simNodes`; Sleep-Mechanik stoppt Timer nach ~3s Idle.
    - Risiko: bei großen Graphen (viele Nodes sichtbar) steigen CPU + Battery; jede State-Änderung triggert SwiftUI invalidations.
- **GraphCanvas Rendering (Main/UI Druck)**
  - `GraphCanvas/GraphCanvasView+Rendering.swift`
    - Viel pro-frame Arbeit (Positions/Label Offsets/Caches; siehe Kommentar „Rendering perf: per-frame screen cache …“).
    - Thumbnail-Pipeline: synchrones `ImageStore.loadUIImage(path:)` läuft zwar auf `DispatchQueue.global`, aber jede Thumbnail-Generation kann trotzdem I/O + Decode verursachen.
    - Risiko: bei vielen Nodes mit Bildern → decode storm + Memory; erkennbar in Grid/Canvas Jank.
- **Detail Screens Media/Thumbnails**
  - `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` (Gallery + Attachments) und `Attachments/AttachmentThumbnailStore.swift`
    - Positive: `AttachmentThumbnailStore` drosselt Generationsjobs (`AsyncLimiter maxConcurrent: 3`) und deduped pro `attachmentID`.
    - Risiko: wenn call-sites zu viele Thumbnails gleichzeitig anfordern (z.B. sehr große Grids), dauert „time-to-first-thumbnail“; priorisierung ist **UNKNOWN** (kein explizites LRU/priority system).

### Sync / Storage / Model
- **SwiftData CloudKit (indirekt)**
  - CloudKit wird nicht direkt via `import CloudKit` benutzt; Sync läuft über SwiftData-Konfiguration in `BrainMeshApp.swift`.
  - `ModelConfiguration(... cloudKitDatabase: .automatic)` → genaue DB-Wahl/Zone-Strategie ist **UNKNOWN** (SwiftData intern).
- **Startup Migration (graphID)**
  - `GraphBootstrap.swift`: `hasLegacyRecords` (fetchLimit=1) + `migrateLegacyRecordsIfNeeded` schreibt fehlende `graphID` nach.
  - Risiko: auf sehr großen Stores kann `migrateLegacyRecordsIfNeeded` trotzdem spürbar werden, weil es volle fetches pro Modell macht (Entities/Attributes/Links).
- **Attachment graphID Migration**
  - `Attachments/AttachmentGraphIDMigration.swift` existiert explizit, um OR-Predicates zu vermeiden, die SwiftData zu in-memory filtering zwingen könnten (sehr kritisch bei `@Attribute(.externalStorage)` in `MetaAttachment.fileData`).
- **Image Cache Hydration**
  - `ImageHydrator.swift` ist `@MainActor` und fetcht alle Entities/Attributes mit `imageData != nil`, schreibt dann fehlende JPEGs auf Disk.
  - Disk-Schreibarbeit passiert via `ImageStore.saveJPEGAsync` (detached), aber das initiale fetch + Iteration ist MainActor-gebunden.

### Concurrency / Task-Lifetimes
- **Off-main Loader Pattern (gut)**
  - `Attachments/MediaAllLoader.swift`: nutzt `Task.detached(priority: .utility)` + eigenen `ModelContext` (`autosaveEnabled = false`).
  - `Attachments/AttachmentHydrator.swift`: Actor + global Throttle (`AsyncLimiter`) + `inFlight` Dedupe.
- **MainActor Heavy Work (kritisch)**
  - `GraphCanvas/GraphCanvasScreen+Loading.swift` ist in `@MainActor func loadGraph(...)` eingebettet und macht `modelContext.fetch(...)` (5x im File).
    - Abbruch: `loadGraph` checkt `Task.isCancelled` vor/nach dem Load, aber `loadGlobal()/loadNeighborhood(...)` sind synchron → Cancellation greift erst danach.
  - Ergebnis: bei großen Graphen kann ein Tap/Graph-Wechsel UI blocken („Freeze vor Push“/„High CPU“) – wenn Fetch/Mapping nicht schnell genug ist.
- **System Modal vs. App Lifecycle**
  - `Support/SystemModalCoordinator.swift` existiert explizit, weil iOS während FaceID-Prompts aus Pickern kurz `.background` melden kann.
  - `AppRootView.swift` nutzt das, um Auto-Lock zu verzögern – wenn ein Picker nicht korrekt begin/end signalisiert, ist Verhalten **fragil**.

## Refactor Map
### Konkrete Splits (low risk)
- `GraphStatsView.swift` → in Section-Subviews/Extensions aufteilen:
  - `GraphStatsView+Header.swift` (Graph Picker + Zeitraum/Scope UI)
  - `GraphStatsView+CountsCards.swift` (Counters-Kacheln)
  - `GraphStatsView+Charts.swift` (falls vorhanden)
  - `GraphStatsView+Rankings.swift`
  - Nutzen: Compile-Time runter, Änderungen lokaler; Verhalten unverändert.
- `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift` → aufteilen:
  - `NodeDetailShared+MediaGallery.swift`
  - `NodeDetailShared+MediaAttachments.swift`
  - `NodeDetailShared+MediaNavigation.swift` ("Bilder verwalten"/"Anhänge verwalten" Flows)
  - Nutzen: weniger Querschnitt; bessere Testbarkeit.

### Loader / Cache Refactors (medium risk, großer Effekt)
- **GraphCanvas Data Loading off-main**
  - Ziel: SwiftData fetch + Mapping aus `GraphCanvas/GraphCanvasScreen+Loading.swift` aus dem MainActor holen.
  - Vorschlag:
    - Neues `actor GraphCanvasDataLoader` (Pattern wie `Attachments/MediaAllLoader.swift`), konfiguriert mit `AnyModelContainer` (existiert bereits in `Attachments/AttachmentHydrator.swift`).
    - `GraphCanvasScreen` ruft `await loader.loadGlobal(graphID:...)` / `loadNeighborhood(...)` und setzt dann nur noch State am MainActor.
  - Risiko: Thread-Safety (ModelContext Nutzung strikt in background Task); UI-State Updates müssen sauber auf MainActor passieren.

### Cache-/Index-Ideen
- **Image presence counting**: `GraphStatsService.swift` zählt über `imageData != nil` (gut, store-translatable).
- **Search**: bereits `nameFolded`/`searchLabelFolded` persistiert → sicherstellen, dass alle Create/Edit Flows diese Felder updaten (Stellen: `Models.swift`, Create Views in `Mainscreen/AddEntityView.swift`, `Mainscreen/AddAttributeView.swift`).
- **Attachment lists**: `MediaAllLoader` nutzt AND-only predicates und optional `AttachmentGraphIDMigration` → dieses Pattern überall anwenden, wo Attachments in großen Mengen geladen werden.

### Vereinheitlichungen (Patterns/DI)
- `AnyModelContainer` liegt aktuell in `Attachments/AttachmentHydrator.swift` (Querschnitt) → nach `Support/` oder `Storage/` verschieben, damit Loader (GraphCanvas/Stats) es ebenfalls nutzen können.
- Einheitliches „Loader“-Pattern:
  - Konfiguration einmalig im App-Startup (`BrainMeshApp.swift`) und dann nur async APIs in Views.
  - Dedupe + Throttle als Standard (siehe `AttachmentHydrator`/`AttachmentThumbnailStore`).

## Risiken & Edge Cases
### Risiken & Edge Cases
- **CloudKit Record Pressure**
  - `MetaEntity.imageData` / `MetaAttribute.imageData` und `MetaAttachment.fileData` sind große Blobs.
  - Mitigation sichtbar: `Images/ImageImportPipeline.swift` komprimiert JPEGs explizit auf Zielgröße (~280 KB).
  - Trotzdem: CloudKit Limits/Quota/Latency → **UNKNOWN** wie oft Uploads throttlen/retryen (SwiftData intern).
- **External Storage Blobs + Filtering**
  - `MetaAttachment.fileData` ist `@Attribute(.externalStorage)` (`Attachments/MetaAttachment.swift`).
  - In-memory filtering wäre fatal; daher existiert `AttachmentGraphIDMigration` + „AND-only predicates“ Kommentare in `MediaAllLoader.swift`.
- **Auto-Lock vs System Modals (Hidden Album FaceID)**
  - Wenn während eines Pickers kurz `.background` gemeldet wird und Auto-Lock zuschlägt, dismissen system modals oft ihren UI-Stack.
  - `Support/SystemModalCoordinator.swift` + `AppRootView.swift` versuchen das zu verhindern. Call-sites müssen konsistent sein.
- **Cancellation-Lücken**
  - `GraphCanvasScreen.scheduleLoadGraph` cancelt den vorherigen `loadTask`, aber wenn der aktuelle Load synchron in fetch/mapping hängt, wirkt Cancel erst danach.
- **Daten-Migrationen**
  - `GraphBootstrap.migrateLegacyRecordsIfNeeded` + `AttachmentGraphIDMigration` schreiben in bestehende Stores → Risiko bei Bug: falsche `graphID` Zuordnung.
  - Mitigation: Migrations sind scoped/AND-only; aber es fehlt eine explizite Versionierung → **UNKNOWN**.

## Observability / Debuggability
### Observability / Debuggability
- `Observability/BMObservability.swift`: `BMLog.load`, `BMLog.expand`, `BMLog.physics` + `BMDuration()`.
- GraphCanvas Physics loggt Rolling Window (alle 60 Ticks) in `GraphCanvas/GraphCanvasView+Physics.swift` → nutzbar um CPU Peaks zu korrelieren.
- Empfehlung: in `GraphCanvas/GraphCanvasScreen+Loading.swift` beim Start/Ende des Loads + Node/Edge Counts loggen (Pattern bereits angedeutet via `BMLog.load`).

## Open Questions
### Open Questions (alles **UNKNOWN**)
- Wie genau verhält sich SwiftData/CloudKit bei Konflikten (Merge-Policy, last-writer wins, field-level merge)?
- Gibt es ein explizites CloudKit Schema-/Migration-Management außerhalb des Repos (CloudKit Dashboard)?
- Gibt es einen definierten Daten-Export/Backup-Mechanismus? (keine Hinweise im Code gefunden)
- Welche Performance-Ziele gelten für große Graphen (z.B. 1k/5k/10k Nodes)?
- Welche iOS-Versionen/Devices zeigen das System-Modal `.background` Verhalten am stärksten? (Dokumentations-/Repro-Checkliste fehlt)

## First 3 Refactors I would do (P0)

### P0.1 — GraphCanvas Data Loading off-main
- **Ziel**: Kein SwiftData fetch + Mapping mehr auf dem MainActor beim Graph-Wechsel/Expand.
- **Betroffene Dateien**: `GraphCanvas/GraphCanvasScreen+Loading.swift`, `GraphCanvas/GraphCanvasScreen.swift`; neu: `GraphCanvas/GraphCanvasDataLoader.swift` (actor).
- **Risiko**: Medium (Threading/ModelContext Correctness, Race Conditions bei schnellen Graph-Wechseln).
- **Erwarteter Nutzen**: Deutlich weniger UI-Freeze, bessere Responsiveness bei großen Graphen.

### P0.2 — GraphStatsView in Sections splitten
- **Ziel**: Große View in wartbare Einheiten; compile-time stabilisieren; klare Verantwortlichkeiten.
- **Betroffene Dateien**: `GraphStatsView.swift` (Split in mehrere Files).
- **Risiko**: Low (reiner UI-Split, Verhalten sollte gleich bleiben).
- **Erwarteter Nutzen**: Schnellere Iteration, weniger Merge-Konflikte, weniger „type-check expression“ Probleme.

### P0.3 — NodeDetailShared Media entknoten
- **Ziel**: Media-Flows (Gallery/Attachments/Manage) isolieren, damit Picker/Lock/Preview Änderungen keinen großen Blast-Radius haben.
- **Betroffene Dateien**: `Mainscreen/NodeDetailShared/NodeDetailShared+Media.swift`, `Mainscreen/NodeDetailShared/NodeImagesManageView.swift`, ggf. `Attachments/*`.
- **Risiko**: Low–Medium (viele Sheets/State Übergaben; Gefahr, dass Binding/Sheet-Identities brechen).
- **Erwarteter Nutzen**: Robustere Media-UX (inkl. Hidden Album), weniger regressions, bessere Testbarkeit.
