# ARCHITECTURE_NOTES

## Scope & Reading Guide
- Fokus dieser Notizen (Priorität):
  1) Sync/Storage/Model (SwiftData/CloudKit)
  2) Entry Points + Navigation
  3) Große Views/Services (Wartbarkeit/Performance)
  4) Konventionen + typische Workflows
- Alle Aussagen sind auf konkrete Dateien im ZIP rückführbar. Alles Unklare ist als **UNKNOWN** markiert (siehe „Open Questions“).

## Key Architecture Decisions (as seen in code)
- **SwiftData + CloudKit** als Default Storage (`BrainMesh/BrainMeshApp.swift` → `ModelConfiguration(..., cloudKitDatabase: .automatic)`).
- **Value‑Snapshots statt @Model über Concurrency**: Loader/Services geben DTOs zurück (z.B. `EntitiesHomeRow`, `GraphCanvasSnapshot`, `GraphStatsSnapshot`).
- **Feature‑Loader als Actors**: `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `ImageHydrator`, `AttachmentHydrator` sind `actor`s; erhalten Container über `configure(container:)` und erzeugen eigene `ModelContext`s.
- **Composition Root**: `BrainMesh/Support/AppLoadersConfigurator.swift` konfiguriert Loader/Hydratoren „fire-and-forget“ in einem `Task.detached`.
- **UI Splitting via Extensions**: große Hosts werden in `+*.swift` gesplittet; State‑Properties sind daher oft nicht `private` (z.B. `GraphCanvasScreen`, `GraphStatsView`).

## Entry Points + Navigation (Technical)
- App Entry: `BrainMesh/BrainMeshApp.swift` (`@main`).
- Root Orchestration: `BrainMesh/AppRootView.swift` (Startup + Onboarding sheet + Unlock fullScreenCover).
- Root Tabs: `BrainMesh/ContentView.swift` (`TabView(selection:)`).
- Programmatic routing: `BrainMesh/RootTabRouter.swift` (`@Published selection`).
- Cross-screen jump into Graph tab: `BrainMesh/GraphJumpCoordinator.swift` (pending jump payload) + consumption in `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`.

## Big Files List (Top 15 by lines)
> Quelle: LOC‑Zählung der `.swift` Dateien im ZIP (Zeilenumbrüche).

- `BrainMesh/GraphTransfer/GraphTransferView.swift` — **908 LOC** — struct GraphTransferView
  - BrainMesh; UI for exporting and importing graphs as .bmgraph files.
  - Risk: sehr groß (Wartbarkeit/Compile-Zeit), I/O + Datenmapping (Export/Import)
- `BrainMesh/GraphTransfer/GraphTransferService.swift` — **644 LOC** — struct ExportOptions
  - BrainMesh; Actor-based service for graph export/import.; (Skeleton only in PR GT1)
  - Risk: sehr groß (Wartbarkeit/Compile-Zeit), I/O + Datenmapping (Export/Import)
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **500 LOC** — struct EntitiesHomeRow
  - BrainMesh; P0.1: Load Entities Home data off the UI thread.; Goal: Avoid blocking the main thread with SwiftData fetches when typing/searching
  - Risk: groß (Split-Kandidat), Home scroll/search hot path
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **475 LOC** — struct GraphCanvasScreen
  - BrainMesh; NOTE: Must not be `private` because several view helpers live in separate extension files.; NOTE: Must not be `private` because jump handling touches helpers in separate extension files.
  - Risk: groß (Split-Kandidat), hot path (Rendering/Physics/Loading)
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **443 LOC** — struct GraphCanvasSnapshot
  - BrainMesh; P0.1: Load GraphCanvas data off the UI thread.; Goal: Avoid blocking the main thread with SwiftData fetches when opening/switching graphs.
  - Risk: groß (Split-Kandidat), hot path (Rendering/Physics/Loading)
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 LOC** — struct NodeImagesManageView
  - BrainMesh; Gallery management (list-style) for Entity/Attribute detail screens.; This replaces the heavy unified "Alle" media view.
  - Risk: groß (Split-Kandidat), heavy UI (Media/Connections)
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **405 LOC** — struct EntitiesHomeView
  - BrainMesh
  - Risk: groß (Split-Kandidat), Home scroll/search hot path
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **389 LOC** — struct NodeDetailsValuesCard
  - BrainMesh; Phase 1: Details (frei konfigurierbare Felder)
  - Risk: Risiko: **UNKNOWN**
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **368 LOC** — struct BulkLinkView
  - BrainMesh
  - Risk: Risiko: **UNKNOWN**
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **363 LOC** — struct NodeGalleryThumbGrid
  - BrainMesh; Adaptive columns so tiles keep a stable, modern look.; 
  - Risk: heavy UI (Media/Connections)
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift` — **360 LOC** — UNKNOWN
  - BrainMesh; MARK: - Overlays
  - Risk: hot path (Rendering/Physics/Loading)
- `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **358 LOC** — struct AllSFSymbolsPickerView
  - BrainMesh
  - Risk: large static data / memory risk
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — **345 LOC** — struct PhotoGallerySection
  - BrainMesh; Detail-only photo gallery for entities/attributes.; 
  - Risk: Risiko: **UNKNOWN**
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — **342 LOC** — struct NodeConnectionsAllView
  - BrainMesh; Full connections list (with delete) backed by the snapshot loader.
  - Risk: heavy UI (Media/Connections)
- `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **332 LOC** — final class MarkdownAccessoryView
  - BrainMesh; One-line formatting toolbar used as UITextView.inputAccessoryView.
  - Risk: heavy UI (Media/Connections)

## Hot Path Analyse

### Rendering / Scrolling
- **Graph Canvas per-frame Work**
  - Dateien: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift` + (Physics/Camera/Gestures Splits laut Kommentar in der Datei).
  - Grund: `GraphCanvasView` hält einen `@State var timer: Timer?` und zeichnet via `Canvas { ... }` — potentiell 30 FPS‑Workload (Kommentar: „pause the 30 FPS timer“).
  - Risiko: hohe Re‑Render‑Frequenz bei großen `positions/velocities` Dictionaries (`@Binding var positions`, `@Binding var velocities`).
  - Bereits vorhandene Gegenmaßnahmen:
    - Simulation Gate von außen: `simulationAllowed` (gesetzt in `GraphCanvasScreen.swift`).
    - Sleep/Idle Mechanik: `physicsIdleTicks` / `physicsIsSleeping` in `GraphCanvasView.swift`.

- **GraphCanvasScreen State Explosion**
  - Datei: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (475 LOC) + Extensions (z.B. `GraphCanvasScreen+Overlays.swift` 360 LOC).
  - Grund: Viele `@State` (Nodes/Edges/Positions/Caches/Selection/Sheets) können häufig invalidieren; kombinierbar mit Physics Tick.
  - Positiv: explizite Render‑Caches (`labelCache`, `imagePathCache`, `iconSymbolCache`, `drawEdgesCache`, `lensCache`, `physicsRelevantCache`) werden als State gehalten, um Arbeit aus `body` herauszuziehen.

- **EntitiesHome List + Search**
  - Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` (405 LOC).
  - Grund: List/Grid + Search triggert Reloads; UI hält `rows/isLoading/loadError` und nutzt `.task(id: taskToken)` (Token enthält Search + Flags).
  - Gegenmaßnahme: `EntitiesHomeLoader` lädt off‑main und cached counts für kurze Zeit (`countsCacheTTLSeconds = 8` in `EntitiesHomeLoader.swift`).

- **Node Detail Shared Media/Connections**
  - Kandidaten: `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` (410 LOC), `NodeDetailShared+MediaGallery.swift` (363 LOC), `NodeDetailShared+Connections.AllView.swift` (342 LOC).
  - Gründe:
    - Media/Attachments können viele Items beinhalten (Disk I/O, Thumbnails, Fetches).
    - Connections/Links können sehr groß werden → N+1 Risiko, heavy sorting/filtering, UI virtualization wichtig.
  - Konkrete Loader existieren: `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift` (Konfiguration über `AppLoadersConfigurator`).

### Sync / Storage
- **CloudKit Default + Release Fallback**
  - Datei: `BrainMesh/BrainMeshApp.swift`.
  - Verhalten:
    - Default: CloudKit enabled (`cloudKitDatabase: .automatic`).
    - DEBUG: Container‑Fehler = `fatalError(...)` (kein lokaler Fallback).
    - non‑DEBUG: lokaler Fallback + `SyncRuntime.storageMode = .localOnly`.
  - Risiko: Unterschiedliches Verhalten zwischen Debug und TestFlight/Release kann Sync‑Bugs maskieren bzw. erst spät zeigen.

- **Startup Migration/Backfill auf MainActor**
  - Datei: `BrainMesh/AppRootView.swift` ruft `bootstrapGraphing()` auf.
  - Implementierung: `BrainMesh/GraphBootstrap.swift` (annotated `@MainActor`).
  - Gründe für Hotspot:
    - `migrateLegacyRecordsIfNeeded` kann potenziell viele Records anfassen (Fetch ohne fetchLimit, dann Schleifen + Save).
    - `backfillFoldedNotesIfNeeded` ebenfalls.
  - Gegenmaßnahme im Code: Vorchecks nutzen `fetchLimit = 1` (`hasLegacyRecords`, `hasFoldedNotesBackfillNeeded`) um die teure Migration nur bei Bedarf zu starten.

- **External Storage for Attachments**
  - Datei: `BrainMesh/Attachments/MetaAttachment.swift` verwendet `@Attribute(.externalStorage)` für `fileData`.
  - Positiv: reduziert Druck auf CloudKit Record‑Size für große Files; lokalen Cache gibt es zusätzlich (`AttachmentStore`).

- **Disk Cache Rebuild in Settings**
  - Datei: `BrainMesh/Settings/SyncMaintenanceView.swift` → `refreshCacheSizes()` nutzt `Task.detached` + ByteCountFormatter und dann `MainActor.run` (UI update).

### Concurrency / Task Lifetimes
- **Task.detached Inventory** (potenziell: keine Cancellation Inheritance)
  - Files mit `Task.detached` (Auswahl; vollständige Liste siehe unten):
    - `BrainMesh/BrainMeshApp.swift`
    - `BrainMesh/ImageStore.swift`
    - `BrainMesh/NotesAndPhotoSection.swift`
    - `BrainMesh/ImageHydrator.swift`
    - `BrainMesh/Settings/SyncMaintenanceView.swift`
    - `BrainMesh/Mainscreen/BulkLinkLoader.swift`
    - `BrainMesh/Mainscreen/LinkCleanup.swift`
    - `BrainMesh/Mainscreen/NodePickerLoader.swift`
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeAttachmentsManageView+Import.swift`
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core/NodeDetailShared+Core.Hero.swift`
    - `BrainMesh/Mainscreen/NodeCreate/NodeCreateDraft.swift`
    - `BrainMesh/PhotoGallery/PhotoGalleryImportController.swift`
    - `BrainMesh/PhotoGallery/PhotoGalleryActions.swift`
    - `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift`
    - `BrainMesh/Support/AppLoadersConfigurator.swift`
    - `BrainMesh/Support/DetailsCompletion/DetailsCompletionIndex.swift`
    - `BrainMesh/Icons/AllSFSymbolsPickerView.swift`
    - `BrainMesh/Attachments/AttachmentHydrator.swift`
    - `BrainMesh/Attachments/AttachmentsSection+Import.swift`
    - `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
    - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
    - `BrainMesh/Attachments/MediaAllLoader.swift`
    - `BrainMesh/Stats/GraphStatsLoader.swift`
  - Warum relevant:
    - `Task.detached` erbt keine Parent‑Cancellation / Priorität automatisch.
    - Späte Ergebnisse können UI‑State überschreiben, wenn kein Token/Stale‑Guard vorhanden ist.
  - Positivbeispiele:
    - `GraphCanvasScreen` hält `loadTask` + `currentLoadToken` (Stale‑Result Guard) in `GraphCanvasScreen.swift`.
    - `GraphStatsView` hält ähnliche Tokens (`currentLoadToken`, `currentPerGraphLoadToken`) in `GraphStatsView.swift`.

- **@unchecked Sendable**
  - `AnyModelContainer` ist `@unchecked Sendable` (`BrainMesh/Support/AnyModelContainer.swift`).
  - `GraphCanvasSnapshot`/`EntitiesHomeSnapshot` sind teils `@unchecked Sendable`.
  - Risiko: Typ‑Safety liegt beim Autor; wichtig ist, dass die Snapshots nur Value‑Typen enthalten (bei `GraphCanvasSnapshot` ist das als Kommentar notiert).

- **MainActor contention**
  - Viele Coordinator/Stores sind `@MainActor` (z.B. `SyncRuntime`, `ProEntitlementStore`, `GraphSession`).
  - Das ist oft korrekt für UI‑State, kann aber Bottlenecks erzeugen, wenn dort schwere Arbeit stattfindet (im Scan: keine klaren „heavy“ Operationen in diesen Stores außer StoreKit iteration; trotzdem Monitoring empfohlen).

## Refactor Map
### Konkrete Splits (low risk, file-size driven)
- `BrainMesh/GraphTransfer/GraphTransferView.swift` (908 LOC)
  - Split-Vorschlag:
    - `GraphTransferView+Export.swift` (Export UI + Options)
    - `GraphTransferView+Import.swift` (Import UI + Preview/Confirm)
    - `GraphTransferView+Components.swift` (Cards/Rows/Reusable UI)
  - Grund: View beinhaltet typischerweise mehrere Flows (export/import/preview/progress) und wird sonst schwer testbar.
- `BrainMesh/GraphTransfer/GraphTransferService.swift` (644 LOC)
  - Split-Vorschlag:
    - `GraphTransferService+Export.swift` (Fetch → DTO → Encode → File write)
    - `GraphTransferService+Import.swift` (Decode → validation → insert/remap)
    - `GraphTransferDTOs.swift` (DTO types + format versioning)
  - Grund: klare Trennung von Format/DTO, Export, Import erleichtert evolvierendes Format und Tests.
- `BrainMesh/Mainscreen/LinkCleanup.swift`
  - In dieser Datei steckt auch `NodeRenameService` (gefunden via Symbolsuche).
  - Split-Vorschlag: `NodeRenameService.swift` (actor/service) vs. Cleanup/Helpers.

### Vereinheitlichungen (Patterns)
- **Loader Base Pattern**
  - Viele Loader implementieren dieselben Schritte: container check, `ModelContext`, cancellation checkpoints, DTO mapping.
  - Vorschlag: kleines internes Protokoll/Helper (z.B. `LoaderBase.makeContext(container:)`) um Boilerplate zu reduzieren und Regeln (autosaveEnabled=false, cancellation) zu erzwingen.
- **Stale-Result Guard Standardisieren**
  - `GraphCanvasScreen` und `GraphStatsView` haben Token Guards; andere detached tasks (Hydrators) nicht.
  - Vorschlag: `LoadToken` helper + `guard token == currentToken else { return }` Pattern für alle UI-relevanten Loads.

## Cache-/Index-Ideen
- **EntitiesHome Counts Cache**
  - Ist vorhanden (TTL=8s) in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`.
  - Hebel: invalidation an allen Mutationspfaden sicherstellen (`invalidateCache(for:)`). Mutations‑Audit im Scan nicht vollständig ⇒ **UNKNOWN**, ob vollständig verdrahtet.
- **Details Completion Index**
  - Existiert: `BrainMesh/Support/DetailsCompletion/DetailsCompletionIndex.swift` (arbeitet mit `ModelContainer` und nutzt `Task.detached`).
  - Hebel: Index‑Invalidation/Incremental Updates statt full rebuild bei jeder Änderung (genaue Trigger: **UNKNOWN** ohne tieferen Audit).
- **GraphCanvas derived caches**
  - Bereits umgesetzt: `drawEdgesCache`, `lensCache`, `physicsRelevantCache` in `GraphCanvasScreen.swift`.
  - Hebel: klare Invalidationsstellen dokumentieren (wann wird welcher Cache neu berechnet) — reduziert Bugs bei zukünftigen Änderungen.
- **Attachment thumbnail caching**
  - Es gibt `BrainMesh/Attachments/AttachmentThumbnailStore.swift` (Task.detached usage vorhanden).
  - Hebel: unify thumbnail generation pipeline (ein Thread‑safe dedupe layer) falls mehrere UI‑Screens dieselben previews laden.

## Risiken & Edge Cases
- **Datenverlust / Partial Imports**
  - GraphTransfer Import/Remap kann Links überspringen, wenn Endpoints fehlen; Tests existieren (`BrainMeshTests/GraphTransferRoundtripTests.swift`).
  - Risiko: bei großen Imports ohne Progress/Cancel kann der User die App killen → teilweiser Insert State. (Mit SwiftData Transaction semantics: **UNKNOWN** ob hier atomare Saves genutzt werden; im Code ist autosave oft disabled, aber explicit save strategy im Import: **UNKNOWN** ohne tieferen Import-Audit).
- **Migration Kosten**
  - `GraphBootstrap` ist MainActor; bei vielen Records kann Startup Zeit steigen (trotz Vorchecks).
- **CloudKit Environment Confusion**
  - Settings Footer weist explizit auf Debug vs Release/TestFlight Unterschiede hin (`BrainMesh/Settings/SettingsView+SyncSection.swift`).
- **Record Size / Media**
  - Entity/Attribute Bilder werden in `imageData` gespeichert (synced) und zusätzlich disk‑cached.
  - Attachments sind externalStorage (synced) + disk cached; trotzdem potenziell große Datenmengen. Monitoring/limits sind **UNKNOWN**.
- **Multiple sources of truth für Active Graph**
  - App nutzt `@AppStorage(BMAppStorageKeys.activeGraphID)` an vielen Stellen.
  - Zusätzlich existiert `GraphSession.shared` (`BrainMesh/GraphSession.swift`), aber ohne Referenzen im Scan ⇒ Gefahr von inkonsistenten zukünftigen Änderungen, wenn jemand GraphSession reaktiviert.

## Observability / Debuggability
- `BrainMesh/Observability/BMObservability.swift`: `BMLog` Kategorien (load/expand/physics) + `BMDuration` (DispatchTime‑basiert).
- Einige Loader nutzen `os.Logger` direkt mit subsystem `"BrainMesh"` (z.B. `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`).
- Repro/Debug Tipps (pragmatisch):
  - GraphCanvas Performance: in `GraphCanvasScreen` maxNodes/maxLinks erhöhen und beobachten; Logs in `BMLog.physics` ergänzen (falls nötig).
  - Sync Debug: `SyncMaintenanceView` → „iCloud‑Status prüfen“ (ruft `SyncRuntime.refreshAccountStatus()`).
  - Import/Export: Unit Test `GraphTransferRoundtripTests` als Regression‑Suite nutzen.

## Open Questions (UNKNOWN)
- **NodeKey Definition**: wird breit verwendet (GraphCanvas, Jump, Link), aber Definitionsfile wurde in diesem Scan nicht explizit extrahiert. **UNKNOWN** (lösbar per gezielter Suche `struct NodeKey`).
- **Offline/Conflict Policy**: SwiftData/CloudKit default; keine explizite Conflict‑Policy Layer gesehen. **UNKNOWN**.
- **Import Atomicity**: Nutzt GraphTransfer Import einen atomaren Save/Transaction, oder kann ein Import teilweise committed werden? **UNKNOWN** ohne vollständiges Import-Code-Audit.
- **Warum `UIBackgroundModes=remote-notification`**: keine Handler/Subscriptions im Code gefunden. **UNKNOWN**.
- **Cache invalidation wiring**: bei welchen Mutationen werden Loader‑Caches invalidiert (EntitiesHome, DetailsCompletion, etc.)? **UNKNOWN** ohne Mutationspfad‑Audit.

## First 3 Refactors I would do (P0)
### P0.1 — Task.detached reduzieren + Cancellation/Token‑Guards standardisieren
- Ziel: weniger „ghost work“ und weniger späte UI‑State‑Updates; konsistente Cancellation‑Semantik.
- Betroffene Dateien (Startpunkt):
  - `BrainMesh/Stats/GraphStatsLoader.swift` (detached innerhalb Loader)
  - `BrainMesh/ImageHydrator.swift` + `BrainMesh/Attachments/AttachmentHydrator.swift` (detached Work ohne sichtbaren cancel/token guard)
  - `BrainMesh/Support/AppLoadersConfigurator.swift` (fire-and-forget detached Setup)
- Risiko: mittel (Concurrency Änderungen; kann Race‑Bugs aufdecken).
- Erwarteter Nutzen: spürbar weniger Hintergrundarbeit bei schnellen Navigationswechseln; stabilere UI bei Re-Loads; weniger Battery/CPU Peaks.

### P0.2 — GraphTransferView/Service split + Streaming/Progress vorbereiten
- Ziel: Wartbarkeit + geringerer Memory‑Peak bei großen Graphen; bessere UX durch Progress + Cancel.
- Betroffene Dateien:
  - `BrainMesh/GraphTransfer/GraphTransferView.swift`
  - `BrainMesh/GraphTransfer/GraphTransferService.swift`
  - Tests: `BrainMeshTests/GraphTransferRoundtripTests.swift` (Regression behalten/ausbauen)
- Risiko: niedrig bis mittel (viel UI‑Refactor, aber klare Abgrenzungen).
- Erwarteter Nutzen: geringere Compile-Zeit, leichteres Weiterentwickeln des File‑Formats, robustere Imports/Exports bei großen Datenmengen.

### P0.3 — Active Graph: Legacy/Dead Code aufräumen und Single Source of Truth erzwingen
- Ziel: verhindern, dass zwei konkurrierende Active‑Graph Mechaniken parallel existieren.
- Betroffene Dateien:
  - `BrainMesh/GraphSession.swift` (aktuell unreferenziert) → entfernen oder deutlich als deprecated markieren.
  - Alle Stellen mit `@AppStorage(BMAppStorageKeys.activeGraphID)` beibehalten als einzige Quelle.
- Risiko: niedrig (wenn wirklich ungenutzt; aktueller Scan findet keine Referenzen).
- Erwarteter Nutzen: weniger Verwirrung für neue Devs; weniger Risiko für subtile Bugs bei zukünftigen Refactors.