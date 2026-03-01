# PROJECT_CONTEXT

## TL;DR
BrainMesh ist eine iOS‑App (SwiftUI + SwiftData) zum Verwalten von mehreren „Graphen“ (Workspaces) mit **Entitäten**, **Attributen** und **Links**. Persistenz läuft über SwiftData; Sync ist über CloudKit aktiviert (`cloudKitDatabase: .automatic`) mit Release‑Fallback auf lokalen Storage. Deployment Target: **iOS 26.0** (`BrainMesh.xcodeproj/project.pbxproj`).

## Key Concepts / Domänenbegriffe
- **Graph (Workspace)**: Oberste Einheit für thematisch getrennte Datenräume (`MetaGraph`, `BrainMesh/Models/MetaGraph.swift`).
- **Active Graph**: Aktiver Workspace wird als UUID‑String in `@AppStorage(BMAppStorageKeys.activeGraphID)` gehalten (z.B. `BrainMesh/AppRootView.swift`, `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`, `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`).
- **Entität (NodeKind.entity)**: Knoten‑Typ für Konzepte/Objekte (`MetaEntity`, `BrainMesh/Models/MetaEntity.swift`).
- **Attribut (NodeKind.attribute)**: Knoten‑Typ innerhalb einer Entität; Ownership über `MetaAttribute.owner` (`BrainMesh/Models/MetaAttribute.swift`).
- **Link**: Kante zwischen Nodes; gespeichert als IDs + Labels, plus optionaler Note (`MetaLink`, `BrainMesh/Models/MetaLink.swift`).
- **NodeKey**: Value‑Key (Kind + UUID) als stabile Referenz im Graph/Selection/Jump‑Handling (Definition in `BrainMesh/GraphCanvas/*` — konkrete Datei: **UNKNOWN** ohne gezielte Suche nach `struct NodeKey`).
- **Details‑Schema**: frei definierbare Felder pro Entität (`MetaDetailFieldDefinition`) + Werte pro Attribut (`MetaDetailFieldValue`) in `BrainMesh/Models/DetailsModels.swift`.
- **Attachments**: Dateien/Medien an Entity/Attribute (Owner wird als `(ownerKindRaw, ownerID)` gespeichert, nicht als Relationship) in `BrainMesh/Attachments/MetaAttachment.swift`.
- **Local Cache / Hydration**: Synced Bytes (z.B. `imageData`, `fileData`) werden in deterministische Dateien in Application Support gespiegelt (`ImageStore.swift`, `AttachmentStore.swift`), gebaut durch Hydratoren (`ImageHydrator.swift`, `AttachmentHydrator.swift`).
- **Graph‑Schutz (Security)**: optionaler Schutz per Biometrie (LocalAuthentication) und/oder eigenem Passwort pro Graph (UI/Koordinatoren in `BrainMesh/Security/*`, Felder in `MetaGraph`/`MetaEntity`/`MetaAttribute`).
- **Pro**: StoreKit2‑Abo‑Entitlements + Feature‑Gating (`BrainMesh/Pro/*`; IDs via Info.plist Keys).
- **Graph Transfer (.bmgraph)**: Export/Import eines Graphen als JSON‑Envelope‑Datei; UTI: `de.marcfechner.brainmesh.graph` (`BrainMesh/Support/UTType+BrainMesh.swift`, `BrainMesh/Info.plist`).

## Architecture Map
- **App Entry / Composition Root**
  - `BrainMesh/BrainMeshApp.swift` (`@main`): erstellt `ModelContainer`, setzt `.modelContainer(...)`, injiziert EnvironmentObjects.
- **Root Navigation**
  - `BrainMesh/AppRootView.swift`: Startup‑Pipeline (Bootstrap + Lock + Hydration + Onboarding) + ScenePhase Handling (Debounce bei Background‑Lock).
  - `BrainMesh/ContentView.swift`: `TabView` als Root‑Navigation (Entities / Graph / Stats / Settings).
  - `BrainMesh/RootTabRouter.swift`: programmatische Tab‑Navigation.
- **Feature Areas** (jeweils: UI + Loader/Service + Sub‑Flows)
  - Entities: `BrainMesh/Mainscreen/EntitiesHome/*` + Detail Screens in `BrainMesh/Mainscreen/EntityDetail/*` und `BrainMesh/Mainscreen/AttributeDetail/*`.
  - GraphCanvas: `BrainMesh/GraphCanvas/*` (Canvas‑Rendering, Gestures, Physics, Jump‑Handling, Inspector, Overlays).
  - Stats: `BrainMesh/Stats/*` (Dashboard‑UI + `GraphStatsLoader` + `GraphStatsService/*`).
  - Settings: `BrainMesh/Settings/*` (Appearance/Display, Sync & Wartung, Import prefs, Pro/Transfer Tiles).
- **Shared Infrastructure**
  - SwiftData Models: `BrainMesh/Models/*` + `BrainMesh/Attachments/MetaAttachment.swift`.
  - Background Loaders/Hydrators: `BrainMesh/Support/AppLoadersConfigurator.swift` registriert und konfiguriert Actor‑Loader off‑main.
  - Utilities: `BrainMesh/Support/*` (AppStorage Keys, AsyncLimiter, UTType helpers, SystemModalCoordinator, DetailsCompletion).
  - Observability: `BrainMesh/Observability/BMObservability.swift` (Logger + Timing).

## Folder Map
- `Assets.xcassets/` — App Icons / Assets (0 Swift-Datei(en))
- `Attachments/` — Attachment Model/Import/Hydration + Disk-Cache (20 Swift-Datei(en))
  - Key file: `BrainMesh/Attachments/MetaAttachment.swift`
  - Key file: `BrainMesh/Attachments/AttachmentStore.swift`
  - Key file: `BrainMesh/Attachments/AttachmentHydrator.swift`
  - Key file: `BrainMesh/Attachments/MediaAllLoader.swift`
  - Key file: `BrainMesh/Attachments/AttachmentsSection.swift`
- `GraphCanvas/` — Graph Canvas Rendering (Canvas), Physics, DataLoader, Overlays (23 Swift-Datei(en))
  - Key file: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - Key file: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift`
  - Key file: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - Key file: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Overlays.swift`
- `GraphPicker/` — Graph-Auswahl & Graph-CRUD (List UI + Services) (6 Swift-Datei(en))
  - Key file: `BrainMesh/GraphPickerSheet.swift`
  - Key file: `BrainMesh/GraphPicker/GraphPickerListView.swift`
  - Key file: `BrainMesh/GraphPicker/GraphDeletionService.swift`
  - Key file: `BrainMesh/GraphPicker/GraphDedupeService.swift`
- `GraphTransfer/` — Graph Export/Import (.bmgraph) + UI (9 Swift-Datei(en))
  - Key file: `BrainMesh/GraphTransfer/GraphTransferView.swift`
  - Key file: `BrainMesh/GraphTransfer/GraphTransferService.swift`
- `Icons/` — SF Symbols Picker + Icon-UX (6 Swift-Datei(en))
  - Key file: `BrainMesh/Icons/AllSFSymbolsPickerView.swift`
- `Images/` — Image Import Pipeline(s) (1 Swift-Datei(en))
- `ImportProgress/` — UI/State für Import-Fortschritt (2 Swift-Datei(en))
  - Key file: `BrainMesh/ImportProgress/ImportProgressState.swift`
  - Key file: `BrainMesh/ImportProgress/ImportProgressCard.swift`
- `Mainscreen/` — Entities/Attributes Home + Detail + Create + Link flows (115 Swift-Datei(en))
  - Key file: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - Key file: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - Key file: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - Key file: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Key file: `BrainMesh/Mainscreen/AddEntityView.swift`
  - Key file: `BrainMesh/Mainscreen/AddAttributeView.swift`
  - Key file: `BrainMesh/Mainscreen/BulkLinkView.swift`
- `Models/` — SwiftData Models (ohne Attachments) (9 Swift-Datei(en))
  - Key file: `BrainMesh/Models/MetaGraph.swift`
  - Key file: `BrainMesh/Models/MetaEntity.swift`
  - Key file: `BrainMesh/Models/MetaAttribute.swift`
  - Key file: `BrainMesh/Models/MetaLink.swift`
  - Key file: `BrainMesh/Models/DetailsModels.swift`
- `Observability/` — Logging/Timing Helpers (1 Swift-Datei(en))
  - Key file: `BrainMesh/Observability/BMObservability.swift`
- `Onboarding/` — Onboarding Coordinator + Views (12 Swift-Datei(en))
  - Key file: `BrainMesh/Onboarding/OnboardingCoordinator.swift`
  - Key file: `BrainMesh/Onboarding/OnboardingSheetView.swift`
- `PhotoGallery/` — Galerie (zusätzliche Bilder/Videos) + Viewer (9 Swift-Datei(en))
  - Key file: `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
  - Key file: `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift`
- `Pro/` — StoreKit2 Entitlements + Paywall + Pro Center (4 Swift-Datei(en))
  - Key file: `BrainMesh/Pro/ProEntitlementStore.swift`
  - Key file: `BrainMesh/Pro/ProCenterView.swift`
  - Key file: `BrainMesh/Pro/ProPaywallView.swift`
- `Security/` — Graph-Schutz (Biometrie/Passwort) + Unlock UI (13 Swift-Datei(en))
  - Key file: `BrainMesh/Security/GraphSecuritySheet.swift`
  - Key file: `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`
  - Key file: `BrainMesh/Security/GraphUnlock/GraphUnlockView.swift`
- `Settings/` — Settings UI + Appearance/Display Settings + Sync/Wartung (44 Swift-Datei(en))
  - Key file: `BrainMesh/Settings/SettingsView.swift`
  - Key file: `BrainMesh/Settings/SyncMaintenanceView.swift`
  - Key file: `BrainMesh/Settings/SyncRuntime.swift`
  - Key file: `BrainMesh/Settings/Appearance/AppearanceStore.swift`
  - Key file: `BrainMesh/Settings/Display/DisplaySettingsStore.swift`
- `Stats/` — Stats UI + Loader + Services + Components (22 Swift-Datei(en))
  - Key file: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - Key file: `BrainMesh/Stats/GraphStatsLoader.swift`
  - Key file: `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift`
- `Support/` — Shared Helpers (AppStorage keys, AnyModelContainer, AsyncLimiter, UTType, SystemModalCoordinator, ...) (11 Swift-Datei(en))
  - Key file: `BrainMesh/Support/AppLoadersConfigurator.swift`
  - Key file: `BrainMesh/Support/AnyModelContainer.swift`
  - Key file: `BrainMesh/Support/BMAppStorageKeys.swift`
  - Key file: `BrainMesh/Support/AsyncLimiter.swift`
  - Key file: `BrainMesh/Support/UTType+BrainMesh.swift`
  - Key file: `BrainMesh/Support/SystemModalCoordinator.swift`

## Data Model Map
### Schema (siehe `BrainMesh/BrainMeshApp.swift`)
Die App registriert folgendes SwiftData‑Schema (Reihenfolge aus Code):
- `MetaGraph`
- `MetaEntity`
- `MetaAttribute`
- `MetaLink`
- `MetaAttachment`
- `MetaDetailFieldDefinition`
- `MetaDetailFieldValue`
- `MetaDetailsTemplate`

### Modelle & Relationships (Kurzform)
- `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`)
  - Name + Search Index: `name` / `nameFolded`.
  - Security: Biometrie + Passwort‑Hash/Salt/Iterations.
- `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`)
  - Graph‑Scope: `graphID: UUID?`.
  - Search: `nameFolded`, `notesFolded` werden im `didSet` gepflegt.
  - Medien: `imageData` (synced), `imagePath` (lokaler Cache‑Filename).
  - Relationships:
    - `attributes` (cascade) → `MetaAttribute.owner`
    - `detailFields` (cascade) → `MetaDetailFieldDefinition.owner`
- `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`)
  - Owner ist ein optionales Feld `owner: MetaEntity?` (keine Relationship‑Macro‑Inverse in der Datei, Kommentar: Macro-Zirkularität).
  - Relationships:
    - `detailValues` (cascade) → `MetaDetailFieldValue.attribute`
  - Search: `searchLabelFolded` wird aus `displayName` abgeleitet (Owner + Name).
- `MetaLink` (`BrainMesh/Models/MetaLink.swift`)
  - Endpoint Modell: `(sourceKindRaw, sourceID)` und `(targetKindRaw, targetID)` plus Labels.
  - Search: `noteFolded` via `didSet` von `note`.
- `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
  - Owner Modell: `(ownerKindRaw, ownerID)`; Content Kind via `AttachmentContentKind`.
  - Payload: `fileData` ist `@Attribute(.externalStorage)`.
- `MetaDetailFieldDefinition` (`BrainMesh/Models/DetailsModels.swift`)
  - Schema/Definition pro Entity; `entityID` wird als Scalar gehalten (Query‑Stabilität).
- `MetaDetailFieldValue` (`BrainMesh/Models/DetailsModels.swift`)
  - Werte pro Attribute+Field; typed storage (String/Int/Double/Date/Bool).
- `MetaDetailsTemplate` (`BrainMesh/Models/MetaDetailsTemplate.swift`)
  - User-saved Templates; Felder als JSON im String (`fieldsJSON`).

### Enums/Helper für Model‑Semantik
- `NodeKind` (`BrainMesh/Models/NodeKind.swift`) — `.entity` / `.attribute`.
- `DetailFieldType` (`BrainMesh/Models/DetailsModels.swift`) — Typen für Details‑Schema.
- `AttachmentContentKind` (`BrainMesh/Attachments/MetaAttachment.swift`) — file/video/galleryImage.
- `BMSearch` (`BrainMesh/Models/BMSearch.swift`) — Folding/Normalisierung für Suche.

## Sync/Storage
### Container Setup
- `BrainMesh/BrainMeshApp.swift`:
  - erstellt `Schema([...])` und versucht `ModelContainer(for: schema, configurations: [cloudConfig])`.
  - `cloudConfig` ist `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)` (Kommentar: „CloudKit / iCloud Sync (private DB)“).
  - In DEBUG: bei Fehler `fatalError(...)` (kein Fallback).
  - In non-DEBUG: Fallback auf lokalen `ModelConfiguration(schema: schema)` und Setzen von `SyncRuntime.storageMode = .localOnly`.

### CloudKit / Entitlements
- `BrainMesh/BrainMesh.entitlements`:
  - iCloud Container ID: `iCloud.de.marcfechner.BrainMesh`.
  - iCloud Service: `CloudKit`.
  - `aps-environment = development` (relevant für Push‑Umgebung; App nutzt in Code keine Push APIs direkt — siehe Open Questions).
- `BrainMesh/Settings/SyncRuntime.swift`:
  - `CKContainer(identifier: Self.containerIdentifier)` + `accountStatus()` für UI‑Anzeige.
- `BrainMesh/Settings/SettingsView+SyncSection.swift`: zeigt Status/Container in DEBUG (`#if DEBUG`).

### Local Cache / Hydration
- Bilder:
  - `BrainMesh/ImageStore.swift`: NSCache + Disk (Application Support/BrainMeshImages).
  - `BrainMesh/ImageHydrator.swift`: scannt SwiftData (Records mit `imageData != nil`) und schreibt deterministische JPEGs; optional `forceRebuild()`.
- Attachments:
  - `BrainMesh/Attachments/AttachmentStore.swift`: Disk Cache (Application Support/BrainMeshAttachments).
  - `BrainMesh/Attachments/AttachmentHydrator.swift`: (analog) baut lokale Dateien aus `MetaAttachment.fileData`/Imports.

### Migration / Backfill
- Multi‑Graph Einführung (graphID): `BrainMesh/GraphBootstrap.swift`
  - `ensureAtLeastOneGraph`
  - `migrateLegacyRecordsIfNeeded(defaultGraphID:using:)` (setzt fehlende `graphID`s).
  - `backfillFoldedNotesIfNeeded(using:)` (setzt `notesFolded`/`noteFolded`).
- Attachments GraphID Migration: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (Details im Code).

### Offline Verhalten
- SwiftData/CloudKit kümmert sich um lokale Persistenz; explizite Offline‑UX/Conflict Handling ist im Code nicht klar als eigenständige Schicht sichtbar ⇒ **UNKNOWN**.

## UI Map (Screens + Navigation)
### Root Tabs (`BrainMesh/ContentView.swift`)
- Tab 0: **Entitäten** → `EntitiesHomeView()` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`).
- Tab 1: **Graph** → `GraphCanvasScreen()` (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`).
- Tab 2: **Stats** → `GraphStatsView()` (`BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`).
- Tab 3: **Einstellungen** → `NavigationStack { SettingsView(showDoneButton: false) }` (`BrainMesh/Settings/SettingsView.swift`).

### Entities (Home + Details)
- Home: `EntitiesHomeView`
  - lädt Rows über `EntitiesHomeLoader` (Value‑DTO) statt `@Query` über Entities; State: `rows/isLoading/loadError` (`EntitiesHomeView.swift`).
  - Loader: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` (Counts‑Cache TTL).
- Entity Details: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` + Extensions (`EntityDetailView+*.swift`).
- Attribute Details: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` + Extensions.
- Create Flows:
  - `BrainMesh/Mainscreen/AddEntityView.swift`
  - `BrainMesh/Mainscreen/AddAttributeView.swift`
  - Draft/Shared: `BrainMesh/Mainscreen/NodeCreate/*` (z.B. `NodeCreateDraft.swift`).
- Links:
  - Einzellink: `BrainMesh/Mainscreen/AddLinkView.swift`.
  - Bulk Link: `BrainMesh/Mainscreen/BulkLinkView.swift` + `BulkLinkLoader.swift`.

### Graph Canvas
- Host/State/Loading: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` + viele `GraphCanvasScreen+*.swift` Dateien (Overlays, Helpers, Loading, Inspector, ...).
- Rendering/Gestures/Physics: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift` (Canvas + `Timer?` für Physics Tick, gated via `simulationAllowed`).
- Data load (off-main): `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (actor; Snapshot DTO; BFS Neighborhood Loader).
- Jump Handling (cross-screen): `BrainMesh/GraphJumpCoordinator.swift` (pending jump) + Konsum in GraphCanvasScreen (Datei: `GraphCanvasScreen.swift`).

### Stats
- Host/UI Orchestration: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` (Splits in `GraphStatsView+*.swift`).
- Loader: `BrainMesh/Stats/GraphStatsLoader.swift` (actor; dashboard vs per-graph loads).
- Service: `BrainMesh/Stats/GraphStatsService/*` (Counts, Structure, Media, Trends).

### Settings
- Root: `BrainMesh/Settings/SettingsView.swift` (Bento/Grid‑artige Tiles; Section Extensions in `SettingsView+*.swift`).
- Sync & Wartung: `BrainMesh/Settings/SyncMaintenanceView.swift` (+ Sections).
- Appearance: `BrainMesh/Settings/Appearance/*` (Models + Store + Presets).
- Display Settings: `BrainMesh/Settings/Appearance/DisplaySettings/*` (Store + Sections).
- Pro: Tile `BrainMesh/Settings/SettingsView+ProTile.swift` → `BrainMesh/Pro/ProCenterView.swift`.
- Graph Transfer: Tile `BrainMesh/Settings/SettingsView+GraphTransferTile.swift` → `BrainMesh/GraphTransfer/GraphTransferView.swift`.

### Onboarding & Security
- Onboarding: `BrainMesh/Onboarding/OnboardingCoordinator.swift` + `OnboardingSheetView.swift`; Trigger in `BrainMesh/AppRootView.swift`.
- Graph Lock/Unlock: `BrainMesh/Security/GraphLock/*` + `BrainMesh/Security/GraphUnlock/*`; Präsentation über `AppRootView.fullScreenCover(item:)`.

## Build & Configuration
- **Deployment Target**: iOS 26.0 (`BrainMesh.xcodeproj/project.pbxproj`).
- **Targets**: `BrainMesh`, `BrainMeshTests`, `BrainMeshUITests` (Bundle IDs in `project.pbxproj`).
- **Bundle ID (App)**: `de.marcfechner.BrainMesh`.
- **Entitlements**: `BrainMesh/BrainMesh.entitlements` (CloudKit Container + iCloud services).
- **Info.plist**: `BrainMesh/Info.plist`
  - `UIBackgroundModes`: `remote-notification` (kein entsprechender AppDelegate/Notification‑Handler im Swift‑Code gefunden).
  - `NSFaceIDUsageDescription`: vorhanden (Security Flow).
  - StoreKit IDs: `BM_PRO_SUBSCRIPTION_ID_01`, `BM_PRO_SUBSCRIPTION_ID_02` (Default: "01"/"02"; konsumiert in `BrainMesh/Pro/ProEntitlementStore.swift`).
  - UTI Export (Graph Transfer): `de.marcfechner.brainmesh.graph`, Extension `.bmgraph` (auch in `BrainMesh/Support/UTType+BrainMesh.swift`).
- **Tests**:
  - Unit Tests enthalten Swift Testing (`import Testing`) in `BrainMeshTests/GraphTransferRoundtripTests.swift` (kein XCTest in dieser Datei).
- **Dependencies**:
  - Keine SPM‑Dependencies im ZIP (keine `Package.resolved`, keine `XCRemoteSwiftPackageReference` in `project.pbxproj`).
- **Secrets Handling**: **UNKNOWN** (keine `.xcconfig` im ZIP; keine offensichtlichen API keys).

## Conventions (Naming, Patterns, Do/Don’t)
### SwiftData + Concurrency
- **Keine @Model über Concurrency‑Grenzen**: Value‑Snapshots + IDs als Navigation‑Key (`EntitiesHomeLoader.swift` Kommentar + Implementierung).
- **Background Contexts**: Loader erstellen ihre eigenen `ModelContext(configuredContainer.container)` und setzen `autosaveEnabled = false` (z.B. `GraphCanvasDataLoader`, `EntitiesHomeLoader`).
- **Cancellation**: In langen Loops wird `Task.checkCancellation()` verwendet (z.B. `GraphCanvasDataLoader.loadNeighborhood`, `EntitiesHomeLoader.loadSnapshot`).

### UI Splits & State Visibility
- Große Views werden per Extensions in mehrere Dateien gesplittet. Konsequenz: viele State‑Properties sind absichtlich nicht `private` (z.B. `GraphCanvasScreen.swift`, `GraphStatsView.swift`).
- Sheets bevorzugt item-driven, um SwiftUI „blank sheet“ Races zu vermeiden (`GraphPickerSheet.swift`).

### Naming / Model Semantik
- Owner‑Property nicht `entity` nennen (Kommentar in `MetaAttribute.swift`: Konflikt mit Core Data).
- Denormalisierte Labels/Indices werden aktiv gepflegt (`nameFolded`, `notesFolded`, `noteFolded`, `searchLabelFolded`).

### Disk I/O
- `ImageStore.loadUIImage(path:)` ist synchron und explizit **nicht** für SwiftUI `body` gedacht (`BrainMesh/ImageStore.swift`).

## How to work on this project
### Setup (lokal)
- Öffne `BrainMesh.xcodeproj` (kein Workspace im ZIP).
- Run auf iOS 26 Simulator/Gerät.
- Für CloudKit: Capability/Signing korrekt; Container ID: `iCloud.de.marcfechner.BrainMesh` (Entitlements + `SyncRuntime`).
- Sync Debug: Settings → „Sync & Wartung“ (`BrainMesh/Settings/SyncMaintenanceView.swift`).

### Debugging Quick Checklist
- [ ] Active Graph korrekt? (`BMAppStorageKeys.activeGraphID`).
- [ ] Sync‑Status: `SyncRuntime.storageMode` (CloudKit vs localOnly).
- [ ] Lock‑Flow: `GraphLockCoordinator.activeRequest` gesetzt? (FullScreenCover in `AppRootView.swift`).
- [ ] GraphCanvas lädt? (`GraphCanvasScreen.isLoading/loadError`, Loader: `GraphCanvasDataLoader`).
- [ ] EntitiesHome Search stottert? (Loader TTL cache, `EntitiesHomeLoader.countsCacheTTLSeconds`).

### Wo anfangen (für neue Devs)
1. **Composition Root**: `BrainMesh/BrainMeshApp.swift` (Container + EnvironmentObjects).
2. **Startup**: `BrainMesh/AppRootView.swift` (Bootstrap/Hydration/Onboarding/Lock).
3. **Navigation**: `BrainMesh/ContentView.swift` + `RootTabRouter.swift`.
4. **Data Model**: `BrainMesh/Models/*` + `BrainMesh/Attachments/MetaAttachment.swift`.
5. **Performance Infrastructure**: `BrainMesh/Support/AppLoadersConfigurator.swift` + Loader‑Actors.

### Typischer Workflow: neues Feature (UI + Data)
- Neues SwiftData Model:
  - `@Model` Datei anlegen (meist `BrainMesh/Models/`).
  - Schema ergänzen: `BrainMesh/BrainMeshApp.swift` (Schema([...])).
  - Wenn Export/Import betroffen: `BrainMesh/GraphTransfer/GraphTransferService.swift` + Tests (z.B. `GraphTransferRoundtripTests.swift`) anpassen.
  - Migration/Backfill überlegen: `BrainMesh/GraphBootstrap.swift`.
- Neuer Background Loader/Service:
  - `actor` anlegen, `configure(container:)` implementieren (Input: `AnyModelContainer`).
  - `ModelContext` lokal instanziieren, `autosaveEnabled=false`.
  - In `BrainMesh/Support/AppLoadersConfigurator.swift` registrieren.
- Neuer Screen/Flow:
  - Tab hinzufügen: `BrainMesh/ContentView.swift`.
  - Settings Tile hinzufügen: `BrainMesh/Settings/SettingsView+*.swift` (pattern: Tile + Navigation).
  - Cross-tab jump: `RootTabRouter` + `GraphJumpCoordinator` nutzen.

## Quick Wins (max. 10)
- [ ] **Dead code prüfen**: `BrainMesh/GraphSession.swift` wird im Projekt nicht referenziert (keine Symbol‑Treffer im ZIP).
- [ ] **Task.detached auditieren**: mehrere Stellen nutzen `Task.detached` für Work, der eigentlich cancellable sein sollte (z.B. `BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/ImageHydrator.swift`, `BrainMesh/Support/AppLoadersConfigurator.swift`).
- [ ] **Remote notification background mode**: `UIBackgroundModes=remote-notification` in `BrainMesh/Info.plist`, aber keine Remote‑Notification Handler im Code ⇒ klären/entfernen falls unnötig.
- [ ] **Entitlements (aps-environment)**: `BrainMesh/BrainMesh.entitlements` setzt `aps-environment=development` ⇒ Release/TestFlight Setup prüfen.
- [ ] **Logger Konsolidierung**: `BMLog` existiert, aber viele Stellen nutzen eigene `Logger(subsystem: "BrainMesh", category: ...)` ⇒ optional vereinheitlichen.
- [ ] **GraphTransferService**: Export/Import iteriert über alle Records eines Graphen und mappt in DTOs (`BrainMesh/GraphTransfer/GraphTransferService.swift`) ⇒ cancellation + progress + memory‑Footprint prüfen.
- [ ] **Search indices**: Bulk‑Updates (z.B. Rename/Import) müssen `*Folded` Felder konsistent halten (`GraphBootstrap` deckt nur Backfill ab).
- [ ] **Counts Cache invalidation**: `EntitiesHomeLoader.invalidateCache(for:)` existiert ⇒ prüfen, ob bei Mutationen (Add/Delete) konsequent invalidiert wird (**UNKNOWN** ohne Mutations‑Audit).
- [ ] **GraphPicker Dedupe/Deletes**: `GraphPickerSheet` friert `displayedGraphs` ein, um UITableView inconsistency zu vermeiden ⇒ ähnliche Pattern evtl. in anderen Listen nötig.
- [ ] **Big file split**: `BrainMesh/GraphTransfer/GraphTransferView.swift` (908 LOC) in Subviews aufteilen (ARCHITECTURE_NOTES).

## Open Questions (UNKNOWNs)
- **Offline/Conflict UX**: Gibt es explizite Conflict‑Resolution oder Retry‑Mechanik über SwiftData/CloudKit hinaus? **UNKNOWN**.
- **Secrets/Build Variants**: Gibt es externe `.xcconfig`/CI‑Secrets außerhalb dieses ZIPs? **UNKNOWN**.
- **Push / remote-notification**: Warum ist `remote-notification` in `Info.plist` gesetzt, obwohl keine Handler/Subscriptions im Code sichtbar sind? **UNKNOWN**.
- **NodeKey Definition**: NodeKey wird in mehreren Files verwendet (z.B. `GraphJumpCoordinator.swift`), aber die konkrete Definitionsdatei wurde nicht explizit in diesem Scan extrahiert ⇒ **UNKNOWN** (lösbar durch gezielte Suche nach `struct NodeKey`).