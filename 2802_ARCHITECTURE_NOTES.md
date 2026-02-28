# ARCHITECTURE_NOTES.md — BrainMesh

> Stand: Analyse des ZIP-Inhalts am 2026-02-28. Aussagen sind anhand konkreter Dateien belegt; Unklares steht als **UNKNOWN** in „Open Questions“.

## 1) Big Files List (Top 15 nach Zeilen)
- `BrainMesh/GraphTransfer/GraphTransferView.swift` — **871 Zeilen**
  - Zweck: UI for exporting and importing graphs as .bmgraph files.
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/GraphTransfer/GraphTransferService.swift` — **635 Zeilen**
  - Zweck: Actor-based service for graph export/import.
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh.xcodeproj/project.pbxproj` — **600 Zeilen**
  - Zweck: Xcode Projekt-Konfiguration (Targets, Build Settings, File References).
  - Risiko: Sehr konfliktanfällig bei parallelen Änderungen (Xcode reorders/rewrites).
- `BrainMesh/Icons/IconCatalogData.json` — **527 Zeilen**
  - Zweck: Icon-Datenkatalog (vermutlich Export/Index für SF Symbols Picker).
  - Risiko: Große statische Resource → Merge-Konflikte + App Size; Update-Prozess sollte klar sein.
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **499 Zeilen**
  - Zweck: P0.1: Load Entities Home data off the UI thread.
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **474 Zeilen**
  - Zweck: NOTE: Must not be `private` because several view helpers live in separate extension files.
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **442 Zeilen**
  - Zweck: P0.1: Load GraphCanvas data off the UI thread.
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 Zeilen**
  - Zweck: Gallery management (list-style) for Entity/Attribute detail screens.
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **404 Zeilen**
  - Zweck: Defines EntitiesHomeView, EntityDetailRouteView, EntitiesHomeSortOption
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388 Zeilen**
  - Zweck: Phase 1: Details (frei konfigurierbare Felder)
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **367 Zeilen**
  - Zweck: Defines BulkLinkView, BulkLinkCompletion
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362 Zeilen**
  - Zweck: / Adaptive columns so tiles keep a stable, modern look.
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift` — **359 Zeilen**
  - Zweck: Defines types
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **357 Zeilen**
  - Zweck: Defines AllSFSymbolsPickerView, AllSFSymbolsPickerViewModel
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **344 Zeilen**
  - Zweck: / Detail-only photo gallery for entities/attributes.
  - Risiko: Großes File (Wartbarkeit/Review/Conflict-Risiko).

## 2) Architecture Deep Dive

### 2.1 Sync/Storage/Model (SwiftData + CloudKit)
#### Container-Aufbau (Source of Truth)
- `BrainMesh/BrainMeshApp.swift`
  - Baut `Schema([...])` aus:
    - `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`,
      `MetaDetailFieldDefinition`, `MetaDetailFieldValue`, `MetaDetailsTemplate`
  - Erstellt `ModelContainer` mit CloudKit:
    - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - `DEBUG`: `fatalError` bei Container-Init Fehler (kein Fallback)
  - `Release`: Fallback auf lokalen Container (kein Sync) + `SyncRuntime.shared.setStorageMode(.localOnly)`

Kurzer Code-Kontext (gekürzt, <10 Zeilen) aus `BrainMesh/BrainMeshApp.swift`:
```swift
let schema = Schema([ MetaGraph.self, MetaEntity.self, ... ])
let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
sharedModelContainer = try ModelContainer(for: schema, configurations: [cloudConfig])
```

#### Entitlements / Capabilities
- `BrainMesh/BrainMesh.entitlements`
  - `com.apple.developer.icloud-services = CloudKit`
  - `com.apple.developer.icloud-container-identifiers = ["iCloud.de.marcfechner.BrainMesh"]`
  - `aps-environment = development` (Build-Config-abhängig; Distribution üblicherweise anders)

#### Runtime-Diagnose / UX
- `BrainMesh/Settings/SyncRuntime.swift`
  - `SyncRuntime.containerIdentifier = "iCloud.de.marcfechner.BrainMesh"`
  - `refreshAccountStatus()` ruft `CKContainer(...).accountStatus()` ab (UI-Feedback in Settings).
- `BrainMesh/Settings/SyncMaintenanceView.swift` + `SettingsView+SyncSection.swift`
  - Zeigt StorageMode + iCloud Status
  - DEBUG-only: Container-ID wird angezeigt (`#if DEBUG`)

#### Multi-Graph Scoping (graphID statt Relationships)
- `MetaGraph` hat **keine** Relationships zu Entities/Links; stattdessen:
  - `MetaEntity.graphID`, `MetaAttribute.graphID`, `MetaLink.graphID`, `MetaAttachment.graphID` (optional für Migration)
- Konsequenz:
  - Queries müssen konsequent `graphID == activeGraphID` enthalten, sonst vermischen sich Graphen.

#### Soft-Migration / Backfill
- `BrainMesh/GraphBootstrap.swift` (auf MainActor)
  - `ensureAtLeastOneGraph(...)`
  - `migrateLegacyRecordsIfNeeded(defaultGraphID: ...)` → setzt `graphID`, wenn `nil`
  - `backfillFoldedNotesIfNeeded(...)` → füllt `notesFolded` / `noteFolded`
- Aufrufstelle:
  - `BrainMesh/AppRootView.swift` → `bootstrapGraphing()` (wird im Startup ausgeführt)

#### External Storage (Attachments)
- `BrainMesh/Attachments/MetaAttachment.swift`
  - `@Attribute(.externalStorage) var fileData: Data?`
  - Risiko bei Queries: OR-Predicates können SwiftData zwingen, in-memory zu filtern (fatal bei blobs).
- Gegenmaßnahme:
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
    - Migriert `graphID` für „legacy attachments“ pro Owner → erlaubt „saubere“ AND-Predicates.

### 2.2 Entry Points + Navigation
#### App Start / Boot
- `BrainMesh/BrainMeshApp.swift`
  - EnvironmentObjects: `AppearanceStore`, `DisplaySettingsStore`, `OnboardingCoordinator`, `GraphLockCoordinator`, `SystemModalCoordinator`, `ProEntitlementStore`, `RootTabRouter`, `GraphJumpCoordinator`
  - `.modelContainer(sharedModelContainer)`
- `BrainMesh/AppRootView.swift`
  - `ContentView()` + App-level startup tasks
  - ScenePhase handling (Locking, Hydration throttling, Onboarding Auto-Show)

#### Root Tabs
- `BrainMesh/ContentView.swift`
  - `TabView` mit 4 Tabs:
    - `EntitiesHomeView`
    - `GraphCanvasScreen`
    - `GraphStatsView`
    - `SettingsView` (in `NavigationStack`)

#### Graph selection
- `BrainMesh/GraphPickerSheet.swift`
  - Sheet, listet Graphen (`@Query` on `MetaGraph`)
  - Add/Rename/Delete + Security entry
  - Pro-Gating: Free-Limit `ProLimits.freeGraphLimit` (`BrainMesh/Pro/ProFeature.swift`)

#### Cross-tab jump (Detail → Graph)
- `BrainMesh/GraphJumpCoordinator.swift`
  - Speichert pending jump (`GraphJump`)
- Consumer:
  - `GraphCanvasScreen` staged/consumes jump nach Load (`GraphCanvasScreen+Loading.swift` + Helpers)

### 2.3 Große Views/Services (Wartbarkeit/Performance) — was auffällt
#### GraphCanvas (UI + Physics + Data)
- UI Host: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ Extensions)
  - Hält viele `@State`-Caches (labelCache/imagePathCache/iconSymbolCache/drawEdgesCache/lensCache/physicsRelevantCache …)
  - Lädt Daten via Snapshot (`GraphCanvasDataLoader`) und commitet state „in einem Rutsch“ (`GraphCanvasScreen+Loading.swift`)
  - Stale-result guard: `currentLoadToken` (verhindert „Geister-Loads“)
- Renderer/Physik: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift` (+ Extensions)
  - `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)` (`GraphCanvasView+Physics.swift`)
  - Per Tick: `positions/velocities` Updates → hohe Invalidations-Frequenz
  - Mitigation sichtbar:
    - Canvas Rendering (UIKit/SwiftUI Canvas) statt vieler subviews
    - „physicsRelevant“ Set (Spotlight Physik) + Idle/Sleep Mechanik (`GraphCanvasView.swift`)
- Loader: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - Background `ModelContext`, `Task.checkCancellation()` Checks
  - Global vs Neighborhood Loader; `fetchLimit` für Entities und Links (`maxNodes`, `maxLinks`)

#### Entities Home (Search + Counts)
- UI: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `.task(id: taskToken)` + `Task.sleep` Debounce (250ms)
  - State: `rows`, `isLoading`, `loadError`
- Loader: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` (actor)
  - DTO: `EntitiesHomeRow`
  - Cache: Attribute counts + Link counts (graph-scoped TTL ~8s) → reduziert repeated full scans beim Tippen.

#### Detail Screens (Entity/Attribute)
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- Auffällig:
  - Links werden über `@Query` gebaut (`NodeLinksQueryBuilder`) **ohne** fetchLimit
  - Bei vielen Links eines Nodes kann das:
    - große Resultsets in Memory ziehen
    - View invalidations bei Live-Updates erhöhen
- Gegenpattern existiert bereits im Projekt: `NodeConnectionsLoader` (wird in `AppLoadersConfigurator` konfiguriert) → spricht dafür, Links perspektivisch „on-demand“ zu laden.

#### Attachments/Media
- Storage:
  - Bytes in SwiftData external storage (`MetaAttachment.fileData`)
  - Lokale Cachefiles: `AttachmentStore` (AppSupport/BrainMeshAttachments)
- Hydration:
  - `AttachmentHydrator` (actor) → fetch fileData off-main + write to cache, throttled (`AsyncLimiter`)
  - `ImageHydrator` (actor) → ensures deterministic cached JPEG, throttled
- UI:
  - `PhotoGallerySection` verwendet `@Query` via `PhotoGalleryQueryBuilder.galleryImagesQuery(...)` und triggert migration in `.task` (`BrainMesh/PhotoGallery/PhotoGallerySection.swift`)

## 3) Hot Path Analyse

### 3.1 Rendering / Scrolling
#### GraphCanvas: Physik-Ticks → SwiftUI invalidation pressure
- Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
- Konkreter Grund:
  - 30 FPS Timer + mutierende Dictionaries (`positions`, `velocities`) → viele Re-Renders.
- Bereits vorhandene Gegenmaßnahmen:
  - Render über `Canvas` (nicht viele `View`-Nodes)
  - Derived render state wird gecached (`drawEdgesCache`, `lensCache`), explizit kommentiert („Previously computed inside body“).

#### Entities Home: Search reload cadence + List/Grid
- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- Konkreter Grund:
  - `.task(id:)` triggered bei `activeGraphID/searchText/flags` → Debounce sleep + reload.
  - Loader macht SwiftData fetch + optional full counts scans (mit TTL Cache mitigiert).
- Risiko:
  - Bei sehr vielen Entities/Attributes trotz TTL noch „burst“ work bei toggle changes.

#### Detail Screens: Unbounded @Query für Links
- Dateien:
  - `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- Konkreter Grund:
  - `@Query` ohne `fetchLimit` + Sort by `createdAt` → kann bei großen Linkmengen teuer werden und wirkt direkt in UI-Lifecycle.

### 3.2 Sync / Storage
- CloudKit init + Fallback:
  - `BrainMesh/BrainMeshApp.swift` (DEBUG fatal vs Release fallback)
  - Risiko:
    - Unterschiedliche Speichermodi je Build-Konfiguration → Daten „scheinen“ zu fehlen.
  - UI-Hinweis:
    - Footer in Settings Sync Section beschreibt Debug vs Release Umgebung (`SettingsView+SyncSection.swift`)

- Attachments externalStorage:
  - `MetaAttachment.fileData` + Predicates (migrations) (`AttachmentGraphIDMigration.swift`)
  - Konkreter Grund:
    - OR-Predicates → in-memory filtering → katastrophal für blobs.

### 3.3 Concurrency (MainActor, Task lifetimes, cancellation, thread safety)
- Positives Pattern (konsequent):
  - Loader als `actor` + eigener Background `ModelContext` (z.B. `EntitiesHomeLoader`, `GraphCanvasDataLoader`)
  - `Task.checkCancellation()` in Load-Pfaden (`GraphCanvasDataLoader`, `EntitiesHomeLoader`)
  - Stale-result guards in UI Host (`GraphCanvasScreen+Loading.swift`)
  - Verbot, @Model über Concurrency-Grenzen zu schieben (Docstring in `EntitiesHomeLoader.swift`)
- Auffällige Stellen (nicht per se falsch, aber watch-list):
  - `Task.detached` in App init (`BrainMeshApp.swift`: `refreshAccountStatus`), in Loader-Config (`AppLoadersConfigurator.swift`) und in manchen Services (`GraphStatsLoader`, `AttachmentGraphIDMigration`, `SyncMaintenanceView.refreshCacheSizes`)
  - Konkreter Grund:
    - Detached Tasks erben keine Cancellation/Actor-Kontexte → Work kann „weiterlaufen“, obwohl UI weg ist.

## 4) Refactor Map (konkret)

### 4.1 Konkrete Splits (Datei → neue Dateien)
> Ziel: kürzere Diff-Surfaces, weniger Merge-Konflikte, klarere Ownership.

- `BrainMesh/GraphTransfer/GraphTransferView.swift` (871)
  - Split-Vorschlag:
    - `GraphTransferView.swift` (nur host + routing)
    - `GraphTransferExportSection.swift`
    - `GraphTransferImportSection.swift`
    - `GraphTransferViewModel.swift` (aktuell im selben File)
  - Nutzen: UI-Komplexität entkoppelt; besser testbar.

- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` (404)
  - Split-Vorschlag:
    - `EntitiesHomeView.swift` (host)
    - `EntitiesHomeToolbar.swift` (menus, actions)
    - `EntitiesHomeState.swift` (taskToken, sort option mapping)
    - `EntitiesHomeErrorStateView.swift`
  - Nutzen: reduziert „God View“ Risiko; erleichtert zukünftige UX-Änderungen.

- `BrainMesh/Mainscreen/LinkCleanup.swift` (278, aber mischt Responsibilities)
  - Split-Vorschlag:
    - `LinkCleanup.swift` (deleteLinks, relabelLinks)
    - `NodeRenameService.swift` (actor)
  - Nutzen: klare Trennung „pure helpers“ vs „configured background service“.

### 4.2 Cache-/Index-Ideen (was cachen, Key-Strukturen, Invalidations)
- Links-Counts/Preview:
  - Problem: Detail-Views `@Query` lädt evtl. viele Links.
  - Idee:
    - Neuer Loader `NodeLinksPreviewLoader`:
      - `countOutgoing/countIncoming` + `latestN` Links (fetchLimit)
    - Key: `(graphID, kindRaw, nodeID, direction)`
    - Invalidations:
      - nach Link create/delete für nodeID
      - nach graph switch
- Attachment Thumbnails:
  - Es existiert `AttachmentThumbnailStore.swift` (lokaler Thumbnail Cache; Datei im `Attachments/` Ordner).
  - Idee:
    - Klar definierte TTL/MaxCount + invalidation bei Attachment delete
    - prefetch für visible IDs (Lazy list/ grid)
- EntitiesHome Counts Cache TTL:
  - Existiert bereits (`EntitiesHomeLoader.countsCacheTTLSeconds = 8`).
  - Hebel:
    - TTL dynamisch erhöhen bei schnellem Tippen (z.B. „while user is typing“ flag)
    - explizite invalidation bei Mutationen (create/delete/rename) statt nur TTL.

### 4.3 Vereinheitlichungen (Patterns, Services, DI)
- „Configured actor loader“ Pattern ist schon da, aber heterogen:
  - `AppLoadersConfigurator` konfiguriert viele Loader, aber nicht alle Services (z.B. `GraphTransferService` wird im Screen konfiguriert).
- Vereinheitlichung:
  - Alles, was `AnyModelContainer` braucht, in `AppLoadersConfigurator` konfigurieren (inkl. `GraphTransferService`), damit:
    - keine „vergessen“-Fehler
    - ein Ort fürs Debugging.

## 5) Risiken & Edge Cases
- **CloudKit init failure → local fallback** (Release):
  - Risiko: „Daten verschwunden“ zwischen Debug/TestFlight, wenn man nicht auf denselben StorageMode schaut.
  - Mitigation: `SyncRuntime.storageMode` sichtbar machen (existiert).
- **Large graphs**
  - GraphCanvas: maxNodes/maxLinks caps (`GraphCanvasScreen.swift`) verhindern Worst-Case, aber:
    - Edge Case: Auswahl/Jump auf Node außerhalb cap → selection drop / nicht sichtbar (UI muss das kommunizieren, aktuell **UNKNOWN** wie gelöst).
- **Attachments blobs**
  - Falsche Predicates → in-memory filtering → UI stalls/Memory spikes.
  - Gegenmaßnahmen existieren (GraphID migration + hydrators).
- **Password/biometrics**
  - `GraphLockCoordinator` trackt unlockedGraphIDs in-memory.
  - Edge Case: App kill / cold start → alles wieder locked (erwartet).
  - Edge Case: System modal + FaceID prompt: `SystemModalCoordinator` existiert als Workaround.

## 6) Observability / Debuggability
- Logging:
  - `BrainMesh/Observability/BMObservability.swift` bietet `BMLog` Logger-Kategorien + `BMDuration`.
- Praktische Debug-Hooks, die schon vorhanden sind:
  - Graph load timing logs in `GraphCanvasScreen+Loading.swift` (BMLog.load + ms)
- Empfohlene Ergänzungen:
  - Einheitliche loader duration logs (EntitiesHomeLoader, GraphStatsLoader) mit denselben Feldern (graphID, counts, ms).
  - Optional: os_signpost (falls nötig) → aktuell **UNKNOWN** ob vorhanden/gewünscht.

## 7) Open Questions (**UNKNOWN**)
- Welche Xcode-Version ist „Source of Truth“ für dieses Repo (um `project.pbxproj` churn zu reduzieren)?
- Soll CloudKit DB explizit `.private` statt `.automatic` sein (Absicht vs. Zufall)?
- Gibt es definierte Lastfälle (Nodes/Links/Attachments), bei denen Performance „akzeptabel“ sein muss?
- Ist GraphTransfer (Export/Import) Feature „production-ready“ oder bewusst „skeleton“ (Kommentar in `GraphTransferService.swift`)?
- Gibt es eine geplante Collaboration/Sharing Roadmap (kein `CKShare` Code gefunden)?

## 8) First 3 Refactors I would do (P0)

### P0.1 — Link loading im Detail: Preview-first statt unbounded @Query
- **Ziel:** Detail-Screens bleiben schnell, auch wenn ein Node sehr viele Links hat.
- **Betroffene Dateien:**
  - `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - (neu) `BrainMesh/Mainscreen/NodeLinksPreviewLoader.swift` (oder unter `Mainscreen/NodeDetailShared/`)
- **Risiko:** Mittel (UI/UX Änderungen; muss sauber testen, dass „Alle Links“ weiterhin vollständig ist).
- **Erwarteter Nutzen:** Weniger SwiftData Arbeit im Renderpfad, bessere Scroll-Responsiveness bei großen Graphen.

### P0.2 — GraphTransferView splitten (ViewModel/Subviews extrahieren)
- **Ziel:** Wartbarkeit erhöhen, kleinere Diffs, klarere Responsibilities.
- **Betroffene Dateien:**
  - `BrainMesh/GraphTransfer/GraphTransferView.swift`
  - (neu) `GraphTransferViewModel.swift`, `GraphTransferExportSection.swift`, `GraphTransferImportSection.swift`
- **Risiko:** Niedrig–Mittel (UI-Refactor, funktional gleich).
- **Erwarteter Nutzen:** Schnellere Reviews, weniger Bug-Risiko bei zukünftigen Import/Export Erweiterungen.

### P0.3 — Cancellation/Stale-Guards für Stats-Loading (analog GraphCanvas)
- **Ziel:** Verhindern, dass Stats-Loads weiterlaufen, wenn User schnell Tabs/Graphen wechselt.
- **Betroffene Dateien:**
  - `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
- **Risiko:** Niedrig (rein intern; API kann gleich bleiben).
- **Erwarteter Nutzen:** Weniger unnötige Background-Fetches; stabilere UI bei schnellen Interaktionen.
