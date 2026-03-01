# PROJECT_CONTEXT.md

## TL;DR
BrainMesh ist eine iOS‑App (SwiftUI) zum Erfassen von Wissen als **Graph** aus Entitäten, Attributen und Links. Persistenz läuft über **SwiftData** mit **CloudKit (Private DB)**; Deployment‑Target: **iOS 26.0**. Einstiegspunkte: `BrainMesh/BrainMeshApp.swift` → `BrainMesh/AppRootView.swift` → `BrainMesh/ContentView.swift`.

## Key Concepts / Domänenbegriffe
- **Graph (Workspace)** (`MetaGraph`): eigenständige Wissensdatenbank. Aktiver Graph via `@AppStorage(BMAppStorageKeys.activeGraphID)` (Key: `BMActiveGraphID`).
- **Entität** (`MetaEntity`): Oberkategorie/Container (z.B. „Person“). Hat Attribute, Details‑Schema, Notizen, Icon, optional ein Hauptbild.
- **Attribut** (`MetaAttribute`): gehört zu genau einer Entität (`owner`). Hat Notizen, Icon/Hauptbild, Details‑Werte (typed).
- **Link** (`MetaLink`): Verbindung zwischen Nodes (Entity/Attribute) über scalar IDs. Link‑Notiz optional; UI nutzt gerichtete Notizen via `DirectedEdgeKey`.
- **Details**: frei definierbare Felder pro Entität (`MetaDetailFieldDefinition`) + Werte pro Attribut (`MetaDetailFieldValue`).
- **Attachments**: Dateien/Videos/Gallery‑Images (`MetaAttachment`) hängen an Entity/Attribute über `ownerKindRaw + ownerID`; `fileData` ist `.externalStorage`.
- **Graph‑Scoping**: nahezu alle Records haben `graphID` (UUID?) zur Trennung mehrerer Graphen; Legacy Migration in `GraphBootstrap`.
- **Folded Search**: Suche arbeitet mit normalisierten Strings (`BMSearch.fold`) + gespeicherten Indizes (`nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`).

## Architecture Map (Layers + Abhängigkeiten)
- **App/Composition Layer**
  - `BrainMesh/BrainMeshApp.swift`
    - baut `Schema([...])` + `ModelContainer`
    - CloudKit: `ModelConfiguration(..., cloudKitDatabase: .automatic)`
    - setzt `SyncRuntime.shared.storageMode` + startet `SyncRuntime.refreshAccountStatus()`
    - konfiguriert Loader/Hydratoren off‑main (`AppLoadersConfigurator.configureAllLoaders(...)`).
  - `BrainMesh/AppRootView.swift`
    - ScenePhase Handling: debounce background lock, foreground tasks (ImageHydrator, Lock, Onboarding).
    - präsentiert App‑weite Sheets/Covers (Onboarding, GraphUnlock).
- **Presentation Layer (SwiftUI)**
  - Root Tabs: `BrainMesh/ContentView.swift` (`TabView`)
  - Home/Details/Create: `BrainMesh/Mainscreen/*`
  - Graph: `BrainMesh/GraphCanvas/*` (Canvas Rendering + Physics + Inspector)
  - Stats: `BrainMesh/Stats/*`
  - Settings: `BrainMesh/Settings/*`
- **State/Coordination Layer**
  - `AppearanceStore` (`BrainMesh/Settings/Appearance/AppearanceStore.swift`): App‑Tint, ColorScheme, Graph‑Farben etc (UserDefaults JSON).
  - `DisplaySettingsStore` (`BrainMesh/Settings/Display/DisplaySettingsStore.swift`): Presets + screen‑spezifische Overrides (UserDefaults JSON).
  - `GraphLockCoordinator` (`BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`): Lock/Unlock Status + Requests.
  - `SystemModalCoordinator` (`BrainMesh/Support/SystemModalCoordinator.swift`): verhindert disruptive Work während system pickers offen sind.
  - `RootTabRouter` (`BrainMesh/RootTabRouter.swift`): programmatic tab switches.
  - `GraphJumpCoordinator` (`BrainMesh/GraphJumpCoordinator.swift`): cross‑screen Jump in GraphCanvas.
- **Data/Services Layer (Actors)**
  - Grundprinzip: UI arbeitet mit IDs + value‑Snapshots; Loader/Services verwenden Background‑`ModelContext` (aus `AnyModelContainer`).
  - Konfiguration: `BrainMesh/Support/AppLoadersConfigurator.swift` → `AnyModelContainer` an Loader übergeben.
  - Wichtige Loader/Services (Auszug):
    - Graph: `GraphCanvasDataLoader` (`BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`)
    - Home: `EntitiesHomeLoader` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`)
    - Stats: `GraphStatsLoader` (`BrainMesh/Stats/GraphStatsLoader.swift`) + `GraphStatsService` (`BrainMesh/Stats/GraphStatsService/*`)
    - Node pickers / bulk link / connections: `NodePickerLoader`, `BulkLinkLoader`, `NodeConnectionsLoader` (siehe `AppLoadersConfigurator`).
    - Media/Cache: `AttachmentHydrator`, `ImageHydrator`, `MediaAllLoader`.
    - Transfer: `GraphTransferService` (`BrainMesh/GraphTransfer/GraphTransferService.swift`).
- **Local Cache Layer**
  - `ImageStore` (`BrainMesh/ImageStore.swift`): NSCache + Disk (AppSupport/BrainMeshImages); async load de‑dupe via `InFlightLoader`.
  - Attachments: `MetaAttachment.localPath` + Hydrator/Thumbnail store (`BrainMesh/Attachments/*`).

## Folder Map (Ordner → Zweck)
- `BrainMesh/Assets.xcassets/` (0 Swift files): Asset catalog (AppIcon, colors).
- `BrainMesh/Attachments/` (20 Swift files): File/Video/Gallery-Attachments (SwiftData MetaAttachment + cache/hydration + UI sections).
- `BrainMesh/GraphCanvas/` (23 Swift files): Graph visualisation (canvas rendering + physics) + data loader + inspector/overlays.
- `BrainMesh/GraphPicker/` (6 Swift files): Graph management (list/rename/delete/dedupe) used via GraphPickerSheet.
- `BrainMesh/GraphTransfer/` (13 Swift files): Export/Import of graphs (.bmgraph) + service + UI.
- `BrainMesh/Icons/` (6 Swift files): SF Symbols picker + icon-related UI helpers.
- `BrainMesh/Images/` (1 Swift files): Image import pipeline (gallery images).
- `BrainMesh/ImportProgress/` (2 Swift files): Progress UI for long-running imports.
- `BrainMesh/Mainscreen/` (115 Swift files): Entities home + entity/attribute details + create flows + bulk link + shared detail components.
- `BrainMesh/Models/` (9 Swift files): SwiftData @Model types + search helpers + node kind definitions.
- `BrainMesh/Observability/` (1 Swift files): os.Logger categories + cheap timing helpers.
- `BrainMesh/Onboarding/` (12 Swift files): Onboarding coordinator + sheets + mini explainer.
- `BrainMesh/PhotoGallery/` (9 Swift files): Gallery UI + import controller/actions.
- `BrainMesh/Pro/` (4 Swift files): StoreKit2 entitlement store + paywall UI + pro center.
- `BrainMesh/Security/` (13 Swift files): Graph lock (FaceID/passcode/password) + security sheets + unlock UI.
- `BrainMesh/Settings/` (44 Swift files): Settings hub + appearance/display/sync/import settings + maintenance.
- `BrainMesh/Stats/` (22 Swift files): Stats dashboard + loader/service + reusable components.
- `BrainMesh/Support/` (11 Swift files): Shared utilities (AnyModelContainer, AsyncLimiter, AppStorage keys, SystemModalCoordinator, UTType).

## Data Model Map (SwiftData Models + Relationships)
### Schema
Definiert in `BrainMesh/BrainMeshApp.swift`:
- `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`)
- `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`)
- `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`)
- `MetaLink` (`BrainMesh/Models/MetaLink.swift`)
- `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
- `MetaDetailFieldDefinition`, `MetaDetailFieldValue` (`BrainMesh/Models/DetailsModels.swift`)
- `MetaDetailsTemplate` (`BrainMesh/Models/MetaDetailsTemplate.swift`)

### Relationships / Key Fields (Kurz)
- `MetaEntity.attributes` (cascade, inverse: `MetaAttribute.owner`) + `MetaEntity.detailFields` (cascade, inverse: `MetaDetailFieldDefinition.owner`).
- `MetaAttribute.detailValues` (cascade, inverse: `MetaDetailFieldValue.attribute`).
- `MetaLink`: keine Relationships, nur IDs + `NodeKind` Raw Values.
- `MetaAttachment`: keine Relationships, Owner via `(ownerKindRaw, ownerID)`; Daten via `.externalStorage`.
- Search Indizes: `nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded` werden via `didSet` gepflegt.

### Graph‑Scoping (Multi‑Graph)
- `graphID: UUID?` auf Entities/Attributes/Links/Attachments/Details.
- Bootstrap/Migration:
  - Default Graph: `GraphBootstrap.ensureAtLeastOneGraph(...)` (`BrainMesh/GraphBootstrap.swift`).
  - Legacy Records (graphID == nil) → Default Graph: `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)`.
  - Backfill `notesFolded` / `noteFolded`: `GraphBootstrap.backfillFoldedNotesIfNeeded(...)`.
  - Attachments: `AttachmentGraphIDMigration` migriert owner‑scoped legacy attachments (`BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).

## Sync/Storage
- `BrainMesh/BrainMeshApp.swift` erstellt `ModelContainer` mit CloudKit (`cloudKitDatabase: .automatic`).
- `SyncRuntime` (`BrainMesh/Settings/SyncRuntime.swift`) surfaced:
  - `storageMode`: `.cloudKit` vs `.localOnly` (Release‑Fallback).
  - iCloud Account Status via `CKContainer(...).accountStatus()`.
- Settings UI: `SyncMaintenanceView` + `SettingsView+SyncSection.swift`.
- Background Mode: `remote-notification` in `BrainMesh/Info.plist`.
- **UNKNOWN**:
  - Ob CloudKit Debug/Production Environments pro Build‑Config/Entitlements automatisch umgestellt werden (Entitlements file enthält `aps-environment = development`).
  - Ob es app‑seitige Retry/Conflict‑UI gibt (außer Account‑Status Anzeige).

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root Tabs (`BrainMesh/ContentView.swift`)
- **Entitäten** → `EntitiesHomeView` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`)
  - List/Grid Subviews: `EntitiesHomeList`, `EntitiesHomeGrid` (im selben Ordner).
  - Search: `.task(id: taskToken)` mit debounce → `EntitiesHomeLoader.loadSnapshot(...)`.
  - Toolbar: `EntitiesHomeToolbar` (iPad Portrait Workaround, siehe `preferExpandedToolbarActions`).
  - Sheets: Add Entity (`AddEntityView`), Graph Picker (`GraphPickerSheet`), Display Options (`EntitiesHomeDisplaySheet`).
  - Navigation: Entity row navigiert über `EntityDetailRouteView(entityID:)` (Query by ID) → `EntityDetailView`.
- **Graph** → `GraphCanvasScreen` (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` + Extensions)
  - Data: `GraphCanvasDataLoader.loadSnapshot(...)` → commit to state (`nodes/edges/caches`).
  - Physics: 30 FPS Timer in `GraphCanvasView+Physics.swift` (gated via `simulationAllowed`).
  - Selection Action Chip + Details Peek (`GraphCanvasScreen+DetailsPeek.swift`).
  - Sheets: Graph Picker, Focus Picker (`NodePickerView`), Inspector, Entity/Attribute Detail, Details Value Editor.
  - Cross‑screen Jump: listens to `GraphJumpCoordinator.pendingJump` and stages selection/centering.
- **Stats** → `GraphStatsView` (`BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` + Extensions)
  - Data: `GraphStatsLoader` liefert Dashboard Snapshot + lazy per‑graph counts.
- **Einstellungen** → `SettingsView` (`BrainMesh/Settings/SettingsView.swift`)
  - Hub Tiles (Bento Grid): Pro, Darstellung, Graph Transfer, Import, Sync & Wartung, Hilfe & Support.
  - Import Settings als Sheet: `ImportSettingsView` (`BrainMesh/Settings/Import/*`).

### App‑weite Modals (`BrainMesh/AppRootView.swift`)
- Onboarding (`OnboardingCoordinator`): `.sheet(isPresented:)` → `OnboardingSheetView`.
- Graph Unlock (`GraphLockCoordinator`): `.fullScreenCover(item:)` → `GraphUnlockView`.

## Build & Configuration
- Xcode project: `BrainMesh.xcodeproj`
- Bundle IDs (pbxproj):
  - App: `de.marcfechner.BrainMesh`
  - Tests: `de.marcfechner.BrainMeshTests`
  - UI Tests: `de.marcfechner.BrainMeshUITests`
- Deployment target: iOS 26.0
- SwiftData/CloudKit Entitlements: `BrainMesh/BrainMesh.entitlements`
- Info.plist (`BrainMesh/Info.plist`):
  - `UIBackgroundModes = remote-notification`
  - `NSFaceIDUsageDescription`
  - `UTExportedTypeDeclarations` für `de.marcfechner.brainmesh.graph` (`.bmgraph`).
  - `BM_PRO_SUBSCRIPTION_ID_01/02` (Default IDs: `01`/`02`).
- StoreKit Configuration (Xcode): `BrainMesh/BrainMesh Pro.storekit`.
- Tests nutzen Apple `Testing` framework (`import Testing`) (`BrainMeshTests/GraphTransferRoundtripTests.swift`).

## Conventions / Patterns
- **IDs statt Models über Grenzen**: Loader liefern Snapshots; UI resolved via main `modelContext` (z.B. `EntityDetailRouteView`).
- **Cancellation**: In Loops `Task.checkCancellation()` (z.B. `GraphCanvasDataLoader`, `EntitiesHomeLoader`, `GraphTransferService`).
- **Stale‑Result Guards**: GraphCanvas nutzt `loadTask` + `currentLoadToken` um overlapping loads zu vermeiden (`GraphCanvasScreen.swift`).
- **Predicate‑Design**: bei `.externalStorage` (Attachments) OR‑Predicates vermeiden → sonst Gefahr in‑memory filtering (siehe Kommentar in `AttachmentGraphIDMigration.swift`).
- **Split Large Files**: `+Foo.swift` Extensions für Views/Services (GraphCanvas, Stats).

## How to work on this project (typische Workflows)
### Neues UI Feature (SwiftUI)
- [ ] Screen/Subview unter passendem Ordner anlegen (z.B. `BrainMesh/Mainscreen/...`).
- [ ] Navigation wählen: `NavigationLink`, `.sheet`, `.fullScreenCover` – konsistent mit bestehenden Flows (siehe `EntitiesHomeView`, `GraphCanvasScreen`, `SettingsView`).
- [ ] Wenn Daten > trivial: Loader/Actor nutzen statt `modelContext.fetch` im View (vgl. `EntitiesHomeLoader`).

### Neuer SwiftData Field / neues Model
- [ ] `@Model` in `BrainMesh/Models/*` (oder passendem Modul) anlegen/anpassen.
- [ ] Schema‑Liste in `BrainMesh/BrainMeshApp.swift` aktualisieren.
- [ ] Graph‑Scoping prüfen: braucht das neue Model `graphID`?
- [ ] Backfills/Migration ggf. in `GraphBootstrap` ergänzen (wenn neue Indizes/Felder).

### Neuer Background Loader/Service
- [ ] Actor mit `configure(container: AnyModelContainer)` (Pattern siehe `GraphCanvasDataLoader`, `EntitiesHomeLoader`).
- [ ] value‑only Snapshot DTOs definieren (Sendable).
- [ ] In `AppLoadersConfigurator.configureAllLoaders(...)` registrieren.
- [ ] UI: `.task(id:)` + debounce/cancellation je nach Use‑Case.

## Quick Wins (max 10, konkret)
1) Repo hygiene: `__MACOSX/*` + `.DS_Store` entfernen/ignorieren (liegen im ZIP).
2) Entitlements prüfen: `BrainMesh/BrainMesh.entitlements` enthält `aps-environment = development` → Release/TestFlight Setup verifizieren. **UNKNOWN** ob per Build‑Config überschrieben.
3) EntitiesHome Search: Link‑Notiz‑Matches lösen IDs aktuell via Schleifen‑Fetch (`EntitiesHomeLoader.swift`); Batch‑Fetch/Chunking würde UI‑Latenz reduzieren.
4) Graph‑Security Felder in `MetaEntity`/`MetaAttribute` sind im UI nicht referenziert (nur `MetaGraph`); Entscheidung: entfernen oder aktiv nutzen.
5) `.storekit` im Projekt: sicherstellen, dass es in Release nicht ungewollt aktiv ist (Scheme‑Setting).
6) Add minimal logging toggles: BMLog Kategorien existieren (`BrainMesh/Observability/BMObservability.swift`), aber nicht überall genutzt.
7) Tests ausbauen: aktuell v.a. GraphTransfer Roundtrip; Hot paths (Search/GraphCanvas Loader) haben keine Tests. **Optional**: Snapshot shape tests mit in‑memory SwiftData.
