# ARCHITECTURE_NOTES.md

## Scope & Method
- Source basis: das gelieferte ZIP (keine externen Annahmen).
- Fokuspriorität (wie angefragt): 1) Sync/Storage/Model → 2) Entry Points + Navigation → 3) große Views/Services → 4) Konventionen/Workflows.

## 1) Sync / Storage / Model (Deep Dive)

### SwiftData + CloudKit Setup
- `BrainMesh/BrainMeshApp.swift`
  - Schema: `Schema([MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment, MetaDetailFieldDefinition, MetaDetailFieldValue, MetaDetailsTemplate])`.
  - CloudKit: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`.
  - Fallback:
    - DEBUG: `fatalError(...)` bei Container‑Init‑Fehler (kein Fallback).
    - Release: fallback auf local-only `ModelConfiguration(schema: schema)` + `SyncRuntime.shared.setStorageMode(.localOnly)`.

### Sync Status Oberfläche
- `BrainMesh/Settings/SyncRuntime.swift`
  - zeigt `storageMode` + iCloud accountStatus (`CKContainer(identifier: "iCloud.de.marcfechner.BrainMesh").accountStatus()`).
- `BrainMesh/Settings/SettingsView+SyncSection.swift`
  - In DEBUG wird der Container‑Identifier zusätzlich angezeigt.
  - Footer enthält Hinweis zu Debug (Development environment) vs Release/TestFlight (typisch Production).

### Datenmodell: Struktur & Denormalisierung
- Models
  - `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`): Workspace + optionaler Zugriffsschutz (Biometrics/Password Hash+Salt).
  - `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`): `graphID`, `attributes` (cascade), `detailFields` (cascade), `nameFolded`, `notesFolded`.
  - `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`): owner (`MetaEntity?`), `detailValues` (cascade), `searchLabelFolded` (owner + name).
  - `MetaLink` (`BrainMesh/Models/MetaLink.swift`): scalar endpoints, denormalized labels (`sourceLabel/targetLabel`), `noteFolded`.
  - `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`): owner via `(ownerKindRaw, ownerID)`, `fileData` via `.externalStorage`.
- Denormalisierung / Indizes
  - Ziel: schnelle Suche/Rendering ohne aufwändige Normalisierung/FETCH im UI.
  - Mechanik: `didSet` updatet folded fields (`nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`).
  - Backfill: `GraphBootstrap.backfillFoldedNotesIfNeeded(...)` (`BrainMesh/GraphBootstrap.swift`).
- Denormalized Link Labels
  - Links speichern Labels für schnellen UI‑Render (Connections).
  - Rename‑Support: `LinkCleanup.relabelLinks(...)` + `NodeRenameService` (`BrainMesh/Mainscreen/LinkCleanup.swift`).

### Graph Scoping + Migration
- Multi‑Graph wird durch `graphID` auf Records modelliert (UUID?).
- Bootstrap (`BrainMesh/GraphBootstrap.swift`):
  - `ensureAtLeastOneGraph(...)`: erstellt Default Graph, wenn keiner existiert.
  - `migrateLegacyRecordsIfNeeded(...)`: setzt `graphID` auf Entities/Attributes/Links, wenn nil.
  - `hasLegacyRecords(...)` nutzt `fetchLimit=1` als cheap guard.
- Attachments: `AttachmentGraphIDMigration` (`BrainMesh/Attachments/AttachmentGraphIDMigration.swift`)
  - Motivation: OR‑Predicates können SwiftData in in‑memory filtering zwingen; für `.externalStorage` wäre das extrem teuer.

### Image/Media Storage Strategy
- Hauptbilder (Entity/Attribute): werden als `imageData` synchronisiert + als JPEG lokal gecached (`imagePath`).
  - Kompression/Resizing: `ImageImportPipeline.prepareJPEGForCloudKit(...)` (`BrainMesh/Images/ImageImportPipeline.swift`) zielt auf ~280 KB.
  - Cache: `ImageStore` (`BrainMesh/ImageStore.swift`) + Hydrator (`BrainMesh/ImageHydrator.swift`).
- Gallery Images: über `MetaAttachment` mit `contentKind = .galleryImage` (siehe `AttachmentContentKind` in `MetaAttachment.swift`) → `.externalStorage` + Disk cache.
- Videos: Video‑Import/Kompression: `BrainMesh/Attachments/VideoCompression.swift` + Import Settings (`BrainMesh/Settings/Import/*`).

## 2) Entry Points + Navigation (Map)

### App Entry
- `@main` App: `BrainMesh/BrainMeshApp.swift`
- Root View: `BrainMesh/AppRootView.swift`
  - wraps `ContentView()` und kümmert sich um:
    - scenePhase changes + debounce background lock (verhindert Picker‑Abbrüche).
    - Onboarding auto show (nur wenn keine Daten).
    - ImageHydrator auto run (max 1×/24h, via `BMImageHydratorLastAutoRun`).
    - Graph lock gating via `GraphLockCoordinator`.

### Root Tabs (`BrainMesh/ContentView.swift`)
- `EntitiesHomeView` (Entitäten)
- `GraphCanvasScreen` (Graph)
- `GraphStatsView` (Stats)
- `SettingsView` (Einstellungen) – eingebettet in `NavigationStack`

### Wichtige Navigation Flows
- Graph Picker (Sheet) ist ein zentraler Entry Point (Home + Graph): `BrainMesh/GraphPickerSheet.swift` → UI in `BrainMesh/GraphPicker/*`.
- Entity/Attribute Details:
  - Home list → `EntityDetailRouteView(entityID:)` (`EntitiesHomeView.swift`) → `EntityDetailView` (`BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`).
  - Graph selection chip → Sheet `EntityDetailView` / `AttributeDetailView` (`GraphCanvasScreen.swift`).
- Cross-screen jump (Detail → Graph):
  - Request: `GraphJumpCoordinator.requestJump(...)` (`BrainMesh/GraphJumpCoordinator.swift`).
  - Consume: `GraphCanvasScreen` staged selection/centering (siehe `GraphCanvasScreen.swift` + helpers).
- Pro/paywall:
  - `ProEntitlementStore` (`BrainMesh/Pro/ProEntitlementStore.swift`) injected in App.
  - GraphPicker gates more graphs (`ProLimits.freeGraphLimit` in `BrainMesh/Pro/ProFeature.swift`).

## 3) Große Views / Services (Wartbarkeit & Performance)

### Big Files List (Top 15 nach Zeilen)
| # | Datei | Zeilen | Grober Zweck | Warum riskant |
|---:|---|---:|---|---|
| 1 | `BrainMesh/GraphTransfer/GraphTransferService.swift` | 644 | Graph Export/Import (.bmgraph), DTO mapping, file I/O, batch inserts. | Format+I/O+DB‑Writes in einer Datei; schwer zu testen/ändern ohne Side-Effects. |
| 2 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` | 500 | Background search + counts cache + snapshot building. | Search correctness + performance; N+1 risk; viele Predicates. |
| 3 | `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` | 475 | Graph tab state machine, overlays, sheets, selection. | Viele States + frequent invalidations (physics). |
| 4 | `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` | 443 | Heavy SwiftData fetch + neighborhood BFS. | Algorithmic scaling; must be cancellation safe. |
| 5 | `BrainMesh/Icons/AllSFSymbolsPickerView.swift` | 430 | SF Symbols catalog/picker. | Large list; easy to introduce performance regressions. |
| 6 | `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` | 428 | Transfer UI state machine. | Progress phases + error handling; UI can get stuck. |
| 7 | `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` | 410 | Gallery management. | Media I/O + caching/hydration race conditions. |
| 8 | `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` | 405 | Home UI + debounce search. | Core UX; many dependencies. |
| 9 | `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` | 389 | Dynamic details values editor. | Many field types; data corruption potential if bindings wrong. |
| 10 | `BrainMesh/Mainscreen/BulkLinkView.swift` | 368 | Bulk link creation. | Performance/correctness with large sets. |
| 11 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` | 363 | Media gallery in details. | Scroll perf w/ thumbnails. |
| 12 | `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift` | 360 | Overlays/minimap/action chip. | Frequent invalidations. |
| 13 | `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` | 346 | Entity detail screen. | Large UI; can become god-view. |
| 14 | `BrainMesh/PhotoGallery/PhotoGallerySection.swift` | 345 | Photo gallery section. | Memory/thumbnail perf. |
| 15 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` | 342 | All connections list. | Large list; delete correctness. |

### Hot Path Analyse (konkret, mit Gründen)
#### GraphCanvas (Render + Physics)
- Physics Tick on main thread (30 FPS): `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - Grund: Pair‑Loop O(n²) (repulsion+collision) + springs + integration pro tick; state updates invalidieren UI.
- Per-frame render caches: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift`
  - Grund: Dictionary/loop building pro frame (O(n+e)), plus optional outgoing notes.
- Screen state churn: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - Grund: viele `.onChange` Observers + `@State` collections; physics ticks trigger many re-renders.
#### EntitiesHome (Search)
- Debounced task reload: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - Grund: `.task(id: taskToken)` → debounce 250ms → loader call; gut für UX, aber viele triggers (graph change, flags).
- N+1 link note resolve: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - Grund: endpoint IDs werden pro ID einzeln gefetched; besonders teuer bei vielen Link‑Notiz matches.
#### Stats
- Attachment bytes summation: `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - Grund: `context.fetch(MetaAttachment...)` und summiert `byteCount` in Swift; bei vielen Attachments kann das dominieren.
#### Startup
- Migration/backfill im Startup auf MainActor: `BrainMesh/AppRootView.swift` → `GraphBootstrap`
  - Grund: `migrateLegacyRecordsIfNeeded`/`backfillFoldedNotesIfNeeded` können full fetches + loops + save auslösen.

## 4) Refactor / Optimierungshebel (konkret)

### Refactor Map: Splits
- `BrainMesh/GraphTransfer/GraphTransferService.swift` → aufteilen:
  - `GraphTransferService+Export.swift`
  - `GraphTransferService+Import.swift`
  - `GraphTransferService+Validation.swift`
  - `GraphTransferFileIO.swift`
  - `GraphTransferDTOs.swift`
  - Nutzen: bessere Testbarkeit; klarere ownership; weniger merge conflicts.
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` → aufteilen:
  - `EntitiesHomeSearch.swift` (Entities/Attributes/Links matching)
  - `EntitiesHomeCountsCache.swift` (TTL cache + compute)
  - Nutzen: Performance‑Tuning ohne „alles anfassen“.

### Performance Map: 3 schnelle Hebel
1) **EntitiesHome Link‑Notiz Batch Resolve**
   - Ersetze per‑ID fetch loops durch batch queries (chunked OR predicates).
   - Files: `EntitiesHomeLoader.swift`.
2) **GraphCanvas Physics: spatial hashing/cutoff**
   - Begrenze Pair‑Vergleiche auf nahe Nachbarn; collisions + repulsion entkoppeln.
   - Files: `GraphCanvasView+Physics.swift`.
3) **Startup Migration off-main**
   - `GraphBootstrap` work in background `ModelContext` + minimal main-thread orchestration.
   - Files: `AppRootView.swift`, `GraphBootstrap.swift`.

### Cache-/Index Ideen (mittel)
- Stats attachment bytes: cached per graph (invalidated on add/remove) → vermeidet full fetch in Stats.
- EntitiesHome counts: aktuell TTL 8s; alternative wäre „incremental maintained counts“ (denormalized count fields) – hoher correctness‑Aufwand + Migration.

## Risiken & Edge Cases
- CloudKit Dev vs Prod: Footer Text in `BrainMesh/Settings/SettingsView+SyncSection.swift` warnt bereits; wichtig für Support/Debug.
- Release fallback local-only: `BrainMeshApp.swift` kann Sync still deaktivieren; UI zeigt zwar Status, aber User‑Verwirrung möglich.
- Denormalized link labels: rename muss relabeln; Service existiert (`NodeRenameService` in `LinkCleanup.swift`).
- Attachment predicates: OR/optional patterns vermeiden (siehe `AttachmentGraphIDMigration.swift`).
- Pro gating: Graph limit free = 3 (`BrainMesh/Pro/ProFeature.swift`); überall, wo Graph creation möglich ist, muss das greifen (GraphPicker plus ggf. weitere Entry Points).

## Observability / Debuggability
- Logging helpers: `BrainMesh/Observability/BMObservability.swift` (`BMLog`, `BMDuration`).
- Physics telemetry: `BMLog.physics` wird in `GraphCanvasView+Physics.swift` periodisch geloggt.
- Sync debugging: `SyncMaintenanceView` + `SyncRuntime` (`BrainMesh/Settings/*`).
- Debug‑Tip: beim Report „Sync kaputt“ zuerst `storageMode` und `iCloudAccountStatusText` checken (Settings → Sync & Wartung).

## Open Questions (UNKNOWN)
1) **Graph‑Security Felder in Entity/Attribute**: in `MetaEntity.swift`/`MetaAttribute.swift` vorhanden, aber im UI/Coordinator nur Graph‑Lock verwendet. Legacy oder geplant?
2) **Entitlements**: `BrainMesh/BrainMesh.entitlements` enthält `aps-environment = development`. Wird das pro Build‑Config überschrieben?
3) **SwiftData Predicate Translation**: Kommentar in `EntitiesHomeLoader` sagt, dass `UUIDArray.contains(e.id)` nicht zuverlässig ist. Gilt das in iOS 26 Toolchain weiterhin?
4) **CloudKit conflict handling**: Kein explizites Conflict‑UI/Resolution gefunden. Wird Default SwiftData/CloudKit genutzt?

## First 3 Refactors I would do (P0)

### P0.1 — EntitiesHome Search: Link‑Notiz Matches ohne N+1
- **Ziel**: Search‑Latenz stabil halten (auch bei vielen Link‑Notizen).
- **Betroffene Dateien**: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- **Risiko**: Mittel (Predicate translation + correctness).
- **Erwarteter Nutzen**: deutlich weniger fetch calls; schnelleres Tippen/Filtering; bessere Battery.

### P0.2 — GraphCanvas Physics: O(n²) entschärfen
- **Ziel**: flüssige Interaktion bei höheren Node‑Counts.
- **Betroffene Dateien**: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- **Risiko**: Mittel (Layout verändert sich; mehr Code).
- **Erwarteter Nutzen**: weniger main-thread CPU pro tick; weniger dropped frames.

### P0.3 — Startup migrations off-main
- **Ziel**: Kaltstart ohne Hänger bei großen Bestandsdaten.
- **Betroffene Dateien**: `BrainMesh/AppRootView.swift`, `BrainMesh/GraphBootstrap.swift`
- **Risiko**: Niedrig–Mittel (Reihenfolge/Idempotenz).
- **Erwarteter Nutzen**: smoother cold start; weniger MainActor contention.
