# PROJECT_CONTEXT.md

> Generated: 2026-03-01  
> Repo artifact: `BrainMesh.xcodeproj` (iOS 26.0 deployment target)

## TL;DR
BrainMesh ist eine **iOS/iPadOS-App (iOS 26.0+)** für ein persönliches Wissensnetz als **Graph**: du legst **Graphen (Workspaces)** an, erstellst **Entitäten**, hängst **Attribute** dran und verknüpfst Knoten über **Links**. Persistenz & Sync laufen über **SwiftData + CloudKit** (iCloud Private DB) mit lokalen Caches für Bilder/Anhänge.

Primäre Entry Points: `BrainMesh/BrainMeshApp.swift` → `BrainMesh/AppRootView.swift` → `BrainMesh/ContentView.swift`.

## Key Concepts / Domänenbegriffe
- **Graph / Workspace** (`MetaGraph`): getrennte Wissensdatenbanken, um Themen sauber zu trennen.
- **Entität** (`MetaEntity`): “Ding”/Konzept, z.B. Person/Projekt/Ort.
- **Attribut** (`MetaAttribute`): konkrete Ausprägung/Instanz unter einer Entität (z.B. *Person · Marc*).
- **Link / Verbindung** (`MetaLink`): Kante zwischen zwei Knoten (Entity↔Entity oder Attribute↔Attribute; technisch frei über `sourceKindRaw/targetKindRaw` + IDs).
- **Details-Felder** (`MetaDetailFieldDefinition` + `MetaDetailFieldValue`): frei definierbare Felder pro Entität (Schema) und Werte pro Attribut (typed storage: String/Int/Double/Date/Bool).
- **Anhänge** (`MetaAttachment`): Dateien/Videos/Galeriebilder, die an Entity/Attribute “hängen” (Owner via `(ownerKindRaw, ownerID)` statt SwiftData Relationship).
- **Graph Canvas**: Visualisierung/Interaktion mit dem Graphen inkl. Physics-Simulation (`BrainMesh/GraphCanvas/...`).
- **Graph Transfer**: Export/Import von Graphen als `.bmgraph` (JSON) (`BrainMesh/GraphTransfer/...`).
- **Graph Lock / Schutz**: optionaler Zugriffsschutz (Face ID/Touch ID + optional eigenes Passwort) pro Graph (`BrainMesh/Security/...`).
- **Pro**: StoreKit2-Abo schaltet u.a. “mehr Graphen” + “Graph-Schutz” frei (`BrainMesh/Pro/...`).

## Architecture Map (Layer/Module → Verantwortlichkeiten → Abhängigkeiten)
- **App Shell / Bootstrap**
  - `BrainMesh/BrainMeshApp.swift`: erstellt `ModelContainer` (SwiftData) mit `cloudKitDatabase: .automatic`, setzt `SyncRuntime` StorageMode, konfiguriert Loader/Hydrators über `AppLoadersConfigurator`.
  - `BrainMesh/AppRootView.swift`: Startup-Orchestration (Bootstrap Graph, Lock Enforcement, Onboarding, Auto-Hydrate) + ScenePhase Handling + Lock debounce.
  - Abhängigkeiten: SwiftUI, SwiftData, CloudKit (indirekt), AppStorage.

- **Domain Model (SwiftData @Model)**
  - `BrainMesh/Models/*.swift` + `BrainMesh/Attachments/MetaAttachment.swift`: zentrale Entities.
  - Abhängigkeiten: SwiftData; viele Modelle haben *denormalisierte Suchfelder* (`nameFolded`, `notesFolded`, `noteFolded`).

- **Data Access / Background Loaders (Actors)**
  - Loader/Hydrators sind Actors, bekommen `ModelContainer` über `AnyModelContainer` und erstellen eigene `ModelContext` Instanzen.
  - Einstieg: `BrainMesh/Support/AppLoadersConfigurator.swift`
  - Beispiele:
    - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
    - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
    - `BrainMesh/Stats/GraphStatsLoader.swift`
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
    - `BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`
  - Abhängigkeiten: SwiftData, Task.detached (off-main), DTO-Snapshots (value-only).

- **Feature Services**
  - `BrainMesh/GraphTransfer/GraphTransferService/*`: Export/Import/Validate/FileIO für `.bmgraph`.
  - `BrainMesh/Stats/GraphStatsService/*`: Berechnung von Counts/Breakdowns (wird über `GraphStatsLoader` off-main gefahren).

- **UI (SwiftUI)**
  - Root Tabs: `BrainMesh/ContentView.swift`
  - Feature Screens: `BrainMesh/Mainscreen/...`, `BrainMesh/GraphCanvas/...`, `BrainMesh/Stats/...`, `BrainMesh/Settings/...`
  - Pattern: größere Views sind in `+*.swift` Extensions gesplittet (z.B. GraphCanvas, Stats).

- **Cross-cutting**
  - **Settings & Persisted Preferences**: `BrainMesh/Settings/*`, `BrainMesh/Support/BMAppStorageKeys.swift`
  - **Observability**: `BrainMesh/Observability/BMObservability.swift`
  - **Security**: `BrainMesh/Security/*`
  - **Pro / StoreKit2**: `BrainMesh/Pro/*`

## Folder Map (Ordner → Zweck)
Top-Level unter `BrainMesh/`:
- `Attachments/` — Attachment Models + Cache/Hydration + Preview/Thumbs (z.B. `Attachments/AttachmentStore.swift`, `Attachments/AttachmentHydrator.swift`).
- `GraphCanvas/` — GraphCanvasScreen + GraphCanvasView + Rendering/Gestures/Physics + Loader (`GraphCanvas/GraphCanvasDataLoader.swift`).
- `GraphPicker/` — UI-Teile für Graph-Auswahl/Management (Liste, Cards, Security Sheet). Host: `GraphPickerSheet.swift`.
- `GraphTransfer/` — Export/Import UI + Service + Format (`GraphTransfer/GraphTransferService/*`, `GraphTransfer/GraphTransferView/*`).
- `Icons/` — SF Symbols Picker (`Icons/AllSFSymbolsPickerView.swift`) + Hilfen.
- `ImportProgress/` — UI/State für Import-Fortschritt.
- `Mainscreen/` — Hauptfeature-Screens: EntitiesHome, EntityDetail, AttributeDetail, NodeDetailShared, Details, BulkLink etc.
- `Models/` — SwiftData Modelle (ohne Attachments).
- `Observability/` — Logger/Kleinst-Timer.
- `Onboarding/` — Onboarding Sheet + Progress Calculation.
- `PhotoGallery/` — GalleryImages (MetaAttachment.galleryImage) + Picker/Viewer/Browser.
- `Pro/` — StoreKit2 Entitlements, Paywall, Pro Center.
- `Security/` — GraphLock/Unlock + Crypto.
- `Settings/` — Settings Hub + Appearance/Display/Sync Maintenance + Import Settings.
- `Stats/` — Stats Screen + Loader + Service + Components.
- `Support/` — Shared Helpers (AppStorage Keys, UTType, Modals, Dedupe, Configurator, etc.).

## Data Model Map (Entities, Relationships, wichtige Felder)
### MetaGraph (`BrainMesh/Models/MetaGraph.swift`)
- Felder: `id`, `createdAt`, `name`, `nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### MetaEntity (`BrainMesh/Models/MetaEntity.swift`)
- Felder: `id`, `createdAt`, `graphID`, `name/nameFolded`, `notes/notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
- Relationships:
  - `attributes` (cascade) inverse: `MetaAttribute.owner`
  - `detailFields` (cascade) inverse: `MetaDetailFieldDefinition.owner`

### MetaAttribute (`BrainMesh/Models/MetaAttribute.swift`)
- Felder: `id`, `graphID`, `name/nameFolded`, `notes/notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
- Owner: `owner: MetaEntity?` (ohne Relationship-Macro auf dieser Seite, um Macro-Zirkularität zu vermeiden)
- Details: `detailValues` (cascade) inverse: `MetaDetailFieldValue.attribute`
- Suchindex: `searchLabelFolded` (kombiniert Entity + Attributname)

### MetaLink (`BrainMesh/Models/MetaLink.swift`)
- Felder: `id`, `createdAt`, `graphID`, `note/noteFolded`
- Endpoints (denormalisiert + IDs): `sourceKindRaw/sourceID/sourceLabel`, `targetKindRaw/targetID/targetLabel`
- Wichtig: Labels sind denormalisiert (Rename muss Link-Labels nachziehen; siehe `Support/AppLoadersConfigurator.swift` → `NodeRenameService.shared.configure(...)`).

### Details Schema + Values (`BrainMesh/Models/DetailsModels.swift`)
- `MetaDetailFieldDefinition`: `entityID`, `name/nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`, `owner`
- `MetaDetailFieldValue`: `attributeID`, `fieldID`, typed storage `stringValue/intValue/doubleValue/dateValue/boolValue`, `attribute`

### MetaDetailsTemplate (`BrainMesh/Models/MetaDetailsTemplate.swift`)
- Felder: `id`, `createdAt`, `graphID`, `name/nameFolded`, `fieldsJSON` (Array von FieldDef)

### MetaAttachment (`BrainMesh/Attachments/MetaAttachment.swift`)
- Owner: `(ownerKindRaw, ownerID)`; Graph-Scope: `graphID`
- Typ: `contentKindRaw` (`file`, `video`, `galleryImage`)
- Bytes: `fileData` mit `@Attribute(.externalStorage)` (SwiftData/CloudKit-friendly)
- Local cache: `localPath` (Application Support / `BrainMeshAttachments`)

## Sync/Storage
### SwiftData + CloudKit
- Container-Setup: `BrainMesh/BrainMeshApp.swift`
  - Schema ist **manuell** gelistet; neue `@Model` Klassen müssen hier ergänzt werden.
  - CloudKit: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - DEBUG: CloudKit-Init-Fehler führen zu `fatalError(...)` (kein Fallback).
  - RELEASE: Fallback auf local-only (`ModelConfiguration(schema: schema)`) und `SyncRuntime.shared.setStorageMode(.localOnly)`.

### iCloud Status Surface
- `BrainMesh/Settings/SyncRuntime.swift`: liest `CKContainer.accountStatus()` für `iCloud.de.marcfechner.BrainMesh`.

### Lokale Caches (nicht Teil des Syncs)
- Bilder: `BrainMesh/ImageStore.swift` → Application Support `/BrainMeshImages`
- Anhänge: `BrainMesh/Attachments/AttachmentStore.swift` → Application Support `/BrainMeshAttachments`
- Hydration:
  - `BrainMesh/ImageHydrator.swift`: setzt deterministische `imagePath = "<id>.jpg"` und schreibt Cache-Dateien (serialisiert via `AsyncLimiter`).
  - `BrainMesh/Attachments/AttachmentHydrator.swift`: materialisiert Preview-Files on-demand (global throttled, dedupe per attachment id).

### Migration / Backfill (app-intern, ohne SwiftData-Versioning)
- Graph-Scope Backfill: `BrainMesh/GraphBootstrap.swift` (setzt fehlende `graphID` auf Default-Graph).
- Notes Folded Backfill: `BrainMesh/GraphBootstrap.swift` (füllt `notesFolded` / `noteFolded`).
- Attachment graphID migration: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (vermeidet OR-Predicates bei externalStorage).

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMesh/ContentView.swift`: `TabView`
  - Tab “Entitäten”: `Mainscreen/EntitiesHome/EntitiesHomeView.swift` (eigener `NavigationStack`)
  - Tab “Graph”: `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ `GraphCanvasScreen+*.swift`)
  - Tab “Stats”: `Stats/GraphStatsView/GraphStatsView.swift` (eigener `NavigationStack`)
  - Tab “Einstellungen”: `Settings/SettingsView.swift` innerhalb `NavigationStack`

### Global modals / overlays
- Onboarding Sheet: `Onboarding/OnboardingSheetView.swift` (hosted by `AppRootView.swift`)
- Graph Unlock Fullscreen: `Security/GraphUnlock/GraphUnlockView.swift` (hosted by `AppRootView.swift`)

### Key Flows (Auswahl)
- Graph auswählen/verwalten: `GraphPickerSheet.swift` (Sheet; verwendet `GraphPicker/*`)
  - Wird u.a. aus `EntitiesHomeView.swift` und `GraphCanvasScreen+Body.swift` geöffnet.
- Entity/Attribute Details:
  - `Mainscreen/EntityDetail/EntityDetailView.swift`
  - `Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Typische Sheets: Add Attribute, Add Link/Bulk Link, Notes Editor, Media/Gallery Browser/Viewer, Attachments Manager.
- Export/Import:
  - `GraphTransfer/GraphTransferView/GraphTransferView.swift` (fileImporter/fileExporter)
  - Service: `GraphTransfer/GraphTransferService/*`
- Settings Hub:
  - `Settings/SettingsView.swift` Tiles → Display, GraphTransfer, ImportSettings, SyncMaintenance, HelpSupport.

## Build & Configuration
- Xcode project: `BrainMesh.xcodeproj`
- Deployment target: **iOS 26.0** (`BrainMesh.xcodeproj/project.pbxproj` → `IPHONEOS_DEPLOYMENT_TARGET = 26.0;`)
- Target device family: iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2";` im pbxproj)
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud container: `iCloud.de.marcfechner.BrainMesh`
  - iCloud service: CloudKit
  - `aps-environment` aktuell: `development` (für Release typischerweise `production`).
- Info.plist: `BrainMesh/Info.plist`
  - StoreKit IDs: `BM_PRO_SUBSCRIPTION_ID_01`, `BM_PRO_SUBSCRIPTION_ID_02`
  - FaceID usage: `NSFaceIDUsageDescription`
  - Background mode: `UIBackgroundModes = remote-notification` (CloudKit pushes)
  - UTType Export: `.bmgraph` (`UTExportedTypeDeclarations`)
- StoreKit Test Config: `BrainMesh/BrainMesh Pro.storekit` (für lokale Produkt-Simulation in Xcode)
- Test Targets:
  - `BrainMeshTests/GraphTransferRoundtripTests.swift` (Swift Testing: `import Testing`)
  - `BrainMeshUITests/` vorhanden (Inhalte **UNKNOWN** ohne weitere Inspection)

## Conventions (Naming, Patterns, Do/Don’t)
- **SwiftData Models**: `@Model final class …` liegen primär in `BrainMesh/Models/*` (+ Attachments separat).
  - Neue Models müssen in `BrainMesh/BrainMeshApp.swift` im `Schema([...])` ergänzt werden.
- **Graph scoping**: fast alle “Content”-Modelle haben `graphID: UUID?` (nil = legacy).
  - Queries bevorzugt als `AND` predicate (kein `OR`), besonders bei `MetaAttachment.fileData` (siehe `Attachments/AttachmentGraphIDMigration.swift`).
- **Keine @Model-Objekte über Concurrency-Grenzen**:
  - Loader liefern value-only DTOs (`EntitiesHomeRow`, `GraphCanvasSnapshot`, …).
- **Loader/Hydrator Pattern**:
  - `actor` + `configure(container: AnyModelContainer)` + `Task.detached` für Fetch/Disk I/O.
  - UI nutzt cancellation + stale-token guards (z.B. `GraphStatsView.swift`, `GraphCanvasScreen.swift`).
- **Split per Extensions**:
  - Große Views sind in `+*.swift` Files gesplittet.
  - Achtung: `private` ist file-scoped → shared state in gesplitteten Views ist absichtlich nicht `private` (z.B. `GraphTransferView.swift`, `GraphCanvasScreen.swift`).

## How to work on this project (Setup Steps + wo anfangen)
Checklist für neue Devs:
1. `BrainMesh.xcodeproj` öffnen.
2. Signing/Team setzen und iCloud Capability + Container prüfen (`BrainMesh/BrainMesh.entitlements`).
3. Run auf iOS 26 Simulator/Device.
4. iCloud Sync testen:
   - Settings → “Sync & Wartung” (`Settings/SyncMaintenanceView.swift`) und `SyncRuntime` Status checken.
5. Architektur verstehen über:
   - Entry Points: `BrainMeshApp.swift`, `AppRootView.swift`, `ContentView.swift`
   - Models: `Models/*` + `Attachments/MetaAttachment.swift`
   - Loader: `Support/AppLoadersConfigurator.swift` + größte Loader (`EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`)

## Quick Wins (max 10, konkret, umsetzbar)
1. **Pagination für “Alle Verbindungen”**: `Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift` liefert aktuell alle Links; UI/Loader könnten eine pageSize + “Load more” bekommen.
2. **EntitiesHomeLoader split**: `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` in `+Fetch`, `+Counts`, `+Cache` aufteilen (mechanisch, geringer Risiko).
3. **GraphCanvasDataLoader split**: `GraphCanvas/GraphCanvasDataLoader.swift` in `+Global` / `+Neighborhood` / `+Caches`.
4. **Centralize detached patterns**: wiederkehrende `Task.detached`-Blöcke in Loadern vereinheitlichen (cancellation, token guard, error mapping).
5. **Audit “fetchLimit”**: sicherstellen, dass alle “Preview”-Loads fetch-limited sind (z.B. Media/Links Previews in Detail Screens).
6. **Rename-Propagation Tests**: unit-test, dass `NodeRenameService` Link-Labels korrekt nachzieht (relevant für Sync-Konflikte).
7. **Attachment cache maintenance**: `Settings/SyncMaintenanceView.swift` (Cache clear/rebuild) um klare “what it does” Texte + guards ergänzen.
8. **GraphTransferViewModel split**: `GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` in Import/Export/Replace/Pro-Gating Teile.
9. **Remove dead global state (falls ungenutzt)**: `BrainMesh/GraphSession.swift` usage prüfen; wenn obsolet, entfernen (erst usage audit).
10. **Consistent logging**: `BMLog` Kategorien in den wichtigsten Loadern/Flows konsequent nutzen (GraphCanvas load, Import, Attachment hydration).

---

## App-wide State / EnvironmentObjects (global, injected in `BrainMesh/BrainMeshApp.swift`)
Injected in `WindowGroup`:
- `AppearanceStore` — Theme/Colors + per-screen appearance defaults (`BrainMesh/Settings/Appearance/*`).
- `DisplaySettingsStore` — per-screen display/toggles (z.B. Section order/collapse) (`BrainMesh/Settings/Display/*`).
- `OnboardingCoordinator` — steuert Onboarding Sheet (`BrainMesh/Onboarding/OnboardingCoordinator.swift`).
- `GraphLockCoordinator` — Lock/Unlock Requests + Unlock State (`BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`).
- `SystemModalCoordinator` — “system picker is open” Guard (Photos/Files) (`BrainMesh/Support/SystemModalCoordinator.swift`).
- `ProEntitlementStore` — StoreKit2 Entitlement/Products (`BrainMesh/Pro/ProEntitlementStore.swift`).
- `RootTabRouter` — Tab selection routing (`BrainMesh/RootTabRouter.swift`).
- `GraphJumpCoordinator` — cross-screen “jump to node” state (GraphCanvas ↔ Details) (`BrainMesh/GraphJumpCoordinator.swift`).

## Typical Workflows (wie fügt man ein Feature hinzu)
### 1) Neues SwiftData Model hinzufügen
Checklist:
- [ ] `@Model` Klasse anlegen (idealerweise unter `BrainMesh/Models/` oder passendem Feature-Ordner).
- [ ] **Schema ergänzen**: `BrainMesh/BrainMeshApp.swift` → `Schema([ ... NewModel.self ... ])`
- [ ] Graph-Scope entscheiden:
  - falls graph-spezifisch: `var graphID: UUID? = nil`
  - Migration/Backfill überlegen (siehe `BrainMesh/GraphBootstrap.swift` / `Attachments/AttachmentGraphIDMigration.swift`)
- [ ] Query-Strategie festlegen (store-translatable Predicates; kein OR bei heavy blobs).
- [ ] Falls UI diese Daten in Listen/Scroll-Pfaden nutzt: Loader-Actor + DTO in Betracht ziehen.

### 2) Neuer Screen / Navigation
- Root Tabs: `BrainMesh/ContentView.swift`
- Innerhalb eines Tabs:
  - bevorzugt `NavigationStack` als Host (z.B. `EntitiesHomeView.swift`, `GraphStatsView.swift`).
  - Sheets/FullScreenCovers möglichst **vom Screen-Host** aus präsentieren (siehe Kommentar in `PhotoGallery/PhotoGallerySection.swift`), nicht aus List rows.

### 3) Heavy data → Loader statt Fetch im Renderpfad
Pattern (Beispiele):
- EntitiesHome: `EntitiesHomeView.swift` orchestriert; `EntitiesHomeLoader.swift` liefert `EntitiesHomeSnapshot`.
- Stats: `GraphStatsView.swift` orchestriert; `GraphStatsLoader.swift` liefert `GraphStatsSnapshot`.
- GraphCanvas: `GraphCanvasScreen+Load.swift` orchestriert; `GraphCanvasDataLoader.swift` liefert `GraphCanvasSnapshot`.

Do/Don’t:
- ✅ Do: value-only DTOs über Actor-Grenzen, UI navigiert via IDs.
- ❌ Don’t: `@Query` ohne `fetchLimit` für große Mengen oder Beziehungen, besonders in ScrollViews.

### 4) Settings / UserDefaults Keys
- Neue persisted toggles über `BMAppStorageKeys` zentralisieren: `BrainMesh/Support/BMAppStorageKeys.swift`.
- UI: `Settings/SettingsView.swift` (Hub) + Detail-Screens in `Settings/*`.

## UI Map (detaillierter: Screens, Sheets, kritische States)
### Entities Tab (`Mainscreen/EntitiesHome/EntitiesHomeView.swift`)
- Root: `NavigationStack`
- Kernzustände:
  - `@AppStorage(BMAppStorageKeys.activeGraphID)` → Graph-Scope
  - `rows` + `loadTask` via `EntitiesHomeLoader.shared.loadSnapshot(...)`
  - `searchText` → debounced reload (Token: `taskToken`)
- Navigation:
  - Route helper: `EntityDetailRouteView` (in `EntitiesHomeView.swift`) lädt Entität per ID und hostet `EntityDetailView`.
- Sheets/Flows (Auszug, via `@State`):
  - GraphPicker (`GraphPickerSheet()`)
  - Add Entity (`showAddEntity`)
  - View Options (`showViewOptions`)

### Entity Detail (`Mainscreen/EntityDetail/EntityDetailView.swift`)
- `@Bindable var entity: MetaEntity`
- Render-Strategie:
  - Links preview + counts: fetch-limited, keine full-load `@Query` (siehe State `outgoingLinksPreview/incomingLinksPreview` + `reloadLinksPreview()`).
  - Media preview: `NodeMediaPreviewLoader` (wird onAppear getriggert; siehe `reloadMediaPreview()`).
- Kritische Flows:
  - Attachment import/preview (maxBytes Guard: `let maxBytes = 25 * 1024 * 1024`)
  - Gallery Browser/Viewer (Sheet-State: `galleryViewerRequest`)
  - Bulk link creation (Sheet-State: `showBulkLink`)

### Graph Tab (`GraphCanvas/GraphCanvasScreen/*` + `GraphCanvas/GraphCanvasView/*`)
- `GraphCanvasScreen.swift`: state container (nodes/edges/positions caches, selection, limits).
- `GraphCanvasView.swift`: Canvas rendering + gestures + 30 FPS timer in `GraphCanvasView+Physics.swift`.
- Navigation/Sheets:
  - GraphPicker (`GraphPickerSheet()`) u.a. in `GraphCanvasScreen+Body.swift`.
  - Inspector (`GraphCanvasScreen+Inspector.swift`) + Overlays (`GraphCanvasScreen+Overlays.swift`).

### Stats Tab (`Stats/GraphStatsView/GraphStatsView.swift`)
- Host: `NavigationStack` + `ScrollView` + Cards
- Loading:
  - `GraphStatsLoader.shared.loadDashboardSnapshot(...)` und optional `loadPerGraphCounts(...)`
  - cancellation + stale-token guards (`currentLoadToken`, `currentPerGraphLoadToken`)

### Settings Tab (`Settings/SettingsView.swift`)
- Hub Tiles:
  - Pro: navigiert zu `Pro/ProCenterView.swift` (und Paywall `ProPaywallView.swift`)
  - Display: `Settings/Display/*` (u.a. Presets/Overrides)
  - GraphTransfer: `GraphTransfer/GraphTransferView/GraphTransferView.swift`
  - Import Settings: `Settings/ImportSettingsView.swift` (Sheet)
  - Sync & Wartung: `Settings/SyncMaintenanceView.swift` (Cache + iCloud status)
  - Hilfe: `Settings/HelpSupportView.swift`

## Testing (was ist vorhanden, wo starten)
- Unit tests:
  - `BrainMeshTests/GraphTransferRoundtripTests.swift` (Swift Testing, `import Testing`)
- UI tests:
  - Ordner `BrainMeshUITests/` existiert → Inhalte/Abdeckung **UNKNOWN** ohne weitere Inspection.
- Praktische Smoke-Tests (manuell):
  - Export/Import Roundtrip (Settings → Export & Import)
  - Graph switch + lock/unlock (GraphPicker → Security)
  - EntitiesHome: schnell tippen/scrollen → keine UI-Lags, keine späten Updates
  - GraphCanvas: rein/raus navigieren → Physics stoppt (siehe `GraphCanvasView.swift` `.onDisappear { stopSimulation() }`)


## Open Questions (**UNKNOWN**)
- Gibt es bewusste Anforderungen an **SwiftData Schema Migration** (Model-Versioning/Custom Migration), oder wird ausschließlich “automatic” akzeptiert?
- Soll CloudKit in Release **hart fehlschlagen** (wie DEBUG) oder ist der local-only Fallback gewollt?
- Gibt es geplante **Collaboration/Sharing** Features (CloudKit Sharing)? (Im Code keine `CKShare` Nutzung gefunden.)
