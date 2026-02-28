# PROJECT_CONTEXT.md — BrainMesh

## TL;DR
BrainMesh is an iOS-only SwiftUI app (deployment target **iOS 26.0**) for managing “graphs” of knowledge: **Entities** (nodes), **Attributes** (nodes attached to entities), and **Links** (edges between nodes). Persistence is **SwiftData** backed by **CloudKit** (private DB via `.automatic`) with a **local-only fallback** in Release builds. Entry point: `BrainMesh/BrainMeshApp.swift`.

## Key Concepts / Domänenbegriffe
- **Graph**: Workspace/Container für Daten. Modell: `Models/MetaGraph.swift`.
- **Entity (Entität)**: Primäre Nodes. Modell: `Models/MetaEntity.swift`.
- **Attribute (Attribut)**: Secondary Nodes, gehören zu einer Entity. Modell: `Models/MetaAttribute.swift` (Owner: `MetaEntity`).
- **Link (Verbindung)**: Kante zwischen Nodes (aktuell v.a. Entity–Entity). Modell: `Models/MetaLink.swift` (speichert `sourceID/targetID` + Labels, keine SwiftData-Relationships).
- **Details-Felder**: Frei definierbare Feld-Schemata pro Entity (`MetaDetailFieldDefinition`) und Werte pro Attribute (`MetaDetailFieldValue`). Datei: `Models/DetailsModels.swift`.
- **Attachments**: Dateien/Videos/Gallery-Images, hängen an Entity/Attribute über `(ownerKindRaw, ownerID)`. Datei: `Attachments/MetaAttachment.swift`.
- **Active Graph**: aktuell ausgewählter Graph, gespeichert via `@AppStorage(BMAppStorageKeys.activeGraphID)`. Keys: `Support/BMAppStorageKeys.swift`.
- **Graph Lock**: optionaler Zugriffsschutz (Biometrie/Passwort) pro Graph. Core: `Security/GraphLock/*`.

## Architecture Map (Layer / Module / Verantwortlichkeiten)
**App & Composition**
- `BrainMesh/BrainMeshApp.swift`
  - Erstellt `ModelContainer` (SwiftData Schema + CloudKit config)
  - Registriert globale Stores via `.environmentObject(...)`
  - Startet Loader-Konfiguration: `Support/AppLoadersConfigurator.swift`

**Persistence / Sync**
- SwiftData Models
  - Graph/Entity/Attribute/Link: `Models/*`
  - Details: `Models/DetailsModels.swift`, `Models/MetaDetailsTemplate.swift`
  - Attachments: `Attachments/MetaAttachment.swift`
- CloudKit Runtime Status (UI/Debug):
  - `Settings/SyncRuntime.swift` (iCloud accountStatus + “cloudKit vs localOnly” Flag)

**Background Loaders (off-main)**
- Zentrales Setup: `Support/AppLoadersConfigurator.swift` (`Task.detached` → configure actors)
- Loader/Services (Actors; value-only DTOs, kein @Model über Concurrency-Grenzen):
  - Entities Home: `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - Graph Canvas: `GraphCanvas/GraphCanvasDataLoader.swift`
  - Stats: `Stats/GraphStatsLoader.swift`
  - Media/Attachments: `Attachments/*Loader.swift`, `Attachments/AttachmentHydrator.swift`
  - Node pickers / bulk operations: `Mainscreen/NodePickerLoader.swift`, `Mainscreen/BulkLinkLoader.swift`, `Mainscreen/LinkCleanup.swift`

**UI**
- Root: `AppRootView.swift` → `ContentView.swift` (Tabs)
- Tabs:
  - Entities: `Mainscreen/EntitiesHome/EntitiesHomeView.swift` (NavigationStack inside)
  - Graph: `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ extensions)
  - Stats: `Stats/GraphStatsView.swift`
  - Settings: `Settings/SettingsView.swift` (+ extracted sections)

**Cross-Screen Navigation / Routing**
- Root tabs: `RootTabRouter.swift`
- Jump into Graph selection/centering: `GraphJumpCoordinator.swift` (consumed in `GraphCanvasScreen+Loading.swift`)

**Observability**
- `Observability/BMObservability.swift` (os.Logger categories + tiny timing helper)

## Folder Map (Ordner → Zweck)
- `(root)`:
  - `BrainMeshApp.swift` (App entry + SwiftData container)
  - `AppRootView.swift` (startup orchestration, onboarding, lock enforcement)
  - `ContentView.swift` (TabView)
  - `GraphSession.swift` / `RootTabRouter.swift` / `GraphJumpCoordinator.swift` (app-wide state/routing)
- `Models/`:
  - SwiftData @Model types: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`
  - Details schema/value models: `DetailsModels.swift`
  - Saved “Details Templates”: `MetaDetailsTemplate.swift`
  - Search helper: `BMSearch.swift`
- `Mainscreen/`:
  - Entities Home + Detail Screens (Entity/Attribute)
  - Create flows: `AddEntityView.swift`, `AddAttributeView.swift`, `AddLinkView.swift`
  - Shared detail components: `NodeDetailShared/*`
  - Bulk link flow: `BulkLinkView.swift` (+ loader/snapshot)
  - Node picker infra: `NodePickerView.swift`, `NodePickerLoader.swift`
- `GraphCanvas/`:
  - Graph canvas screen + inspector + overlays: `GraphCanvasScreen/*`
  - Rendering + gestures + physics: `GraphCanvasView/*`
  - Data load snapshot: `GraphCanvasDataLoader.swift`
  - Mini map: `MiniMapView.swift`
- `Stats/`:
  - Stats dashboard & components + loader: `GraphStatsView.swift`, `GraphStatsLoader.swift`, etc.
- `Settings/`:
  - Settings hub + sections
  - Appearance (theme/tint/graph colors): `Settings/Appearance/*`
  - Display settings (per-screen toggles + presets): `Settings/Display/*`
  - Sync & Maintenance: `SyncMaintenanceView.swift`, `SyncRuntime.swift`
  - Import preferences: `ImportSettingsView.swift`, `VideoImportPreferences.swift`, `ImageGalleryImportPreferences.swift`
- `Security/`:
  - Graph Lock coordinator + crypto + unlock UI: `Security/GraphLock/*`, `Security/GraphUnlock/*`
  - Security settings UI: `Security/GraphSecuritySheet.swift`, `Security/GraphSetPasswordView.swift`
- `Attachments/`:
  - Attachment model: `MetaAttachment.swift`
  - Import pipeline: `AttachmentImportPipeline.swift`
  - Cache/hydration: `AttachmentHydrator.swift`, `AttachmentStore.swift`, `AttachmentThumbnailStore.swift`
  - Media screens loaders: `MediaAllLoader.swift`, etc.
- `Onboarding/`:
  - Coordinator + sheet UI + progress model: `Onboarding/*`
- `PhotoGallery/`:
  - Gallery UI sections and viewer: `PhotoGallery/*`
- `Pro/`:
  - StoreKit2 entitlement manager + paywall/center: `Pro/ProEntitlementStore.swift`, `Pro/ProPaywallView.swift`, `Pro/ProCenterView.swift`
- `Support/`:
  - Shared helpers: `AnyModelContainer.swift`, `AppLoadersConfigurator.swift`, `AsyncLimiter.swift`, AppStorage keys, Details completion helpers, etc.
- `Icons/`:
  - SF Symbols picker & support UI: `Icons/AllSFSymbolsPickerView.swift`, etc.

## Data Model Map (Entities, Relationships, wichtige Felder)
### MetaGraph (`Models/MetaGraph.swift`)
- `id: UUID`
- `createdAt: Date`
- `name`, `nameFolded`
- **Lock fields**: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Derived: `isProtected`, `isPasswordConfigured`

### MetaEntity (`Models/MetaEntity.swift`)
- Scalars: `id`, `createdAt`, `graphID: UUID?`, `name/nameFolded`, `notes/notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
- Relationships:
  - `attributes: [MetaAttribute]?` (`@Relationship(.cascade, inverse: \MetaAttribute.owner)`)
  - `detailFields: [MetaDetailFieldDefinition]?` (`@Relationship(.cascade, inverse: \MetaDetailFieldDefinition.owner)`)
- Convenience:
  - `attributesList` (de-dupe by id)
  - `detailFieldsList` (sorted by `sortIndex`)

### MetaAttribute (`Models/MetaAttribute.swift`)
- Scalars: `id`, `graphID: UUID?`, `name/nameFolded`, `notes/notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
- Owner:
  - `owner: MetaEntity?` (plain property; inverse defined on entity side)
  - `searchLabelFolded` (computed from “Entity · Attribute” display name)
- Relationships:
  - `detailValues: [MetaDetailFieldValue]?` (`@Relationship(.cascade, inverse: \MetaDetailFieldValue.attribute)`)

### MetaLink (`Models/MetaLink.swift`)
- `id`, `createdAt`, `graphID`
- Source/target: `sourceKindRaw`, `sourceID`, `targetKindRaw`, `targetID`
- Denormalized labels: `sourceLabel`, `targetLabel`
- Optional note + stored search index: `note`, `noteFolded`

### Details Schema/Values (`Models/DetailsModels.swift`)
- `MetaDetailFieldDefinition` (schema for an entity’s attributes)
  - `owner: MetaEntity?` relationship (`originalName: "entity"`)
  - `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Scalar mirrors: `entityID`, `graphID`
- `MetaDetailFieldValue` (typed value for an attribute)
  - `attribute: MetaAttribute?` (plain property)
  - Scalar mirrors: `attributeID`, `fieldID`, `graphID`
  - Typed slots: `stringValue/intValue/doubleValue/dateValue/boolValue`

### Details Templates (`Models/MetaDetailsTemplate.swift`)
- User-saved schema templates (“Meine Sets”)
- `fieldsJSON` stores array of `FieldDef` (Codable)

### Attachments (`Attachments/MetaAttachment.swift`)
- Owner by id/kind: `ownerKindRaw`, `ownerID` (no SwiftData relationship)
- `contentKindRaw` (file/video/galleryImage)
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Data: `fileData` is `@Attribute(.externalStorage)` (CloudKit asset style)
- Local cache: `localPath`

## Sync / Storage
- SwiftData schema setup: `BrainMesh/BrainMeshApp.swift`
  - `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - Release fallback: local-only `ModelConfiguration(schema: schema)` when CloudKit init fails.
- CloudKit container identifier:
  - Entitlements: `BrainMesh/BrainMesh.entitlements` → `iCloud.de.marcfechner.BrainMesh`
  - Runtime check UI: `Settings/SyncRuntime.swift` (`CKContainer.accountStatus()`)
- Lightweight data migrations/backfills on startup:
  - `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)` sets missing `graphID` (entities/attributes/links)
  - `GraphBootstrap.backfillFoldedNotesIfNeeded(...)` fills `notesFolded`/`noteFolded`
  - File: `GraphBootstrap.swift`, executed in `AppRootView.bootstrapGraphing()`
- Local caches:
  - Images: `ImageStore.swift` (Application Support/BrainMeshImages + NSCache)
  - Attachments: `Attachments/AttachmentStore.swift` + related (Application Support/BrainMeshAttachments) (**cache maintenance UI** in `Settings/SyncMaintenanceView.swift`)
- Offline behavior:
  - **KNOWN**: SwiftData stores locally and syncs via CloudKit when available.
  - **UNKNOWN**: explicit user-facing conflict handling or merge policy beyond SwiftData defaults.

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `AppRootView.swift`
  - Startup: ensure default graph + data backfills
  - Enforces lock (`GraphLockCoordinator`) using `fullScreenCover`
  - Presents onboarding (`OnboardingSheetView`) via `.sheet`
- `ContentView.swift`
  - `TabView` tabs: Entities, Graph, Stats, Settings

### Entities Tab
- `Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `NavigationStack` with search + list/grid
  - Add flows: `AddEntityView.swift`, etc.
  - Push to entity detail (`Mainscreen/EntityDetail/EntityDetailView.swift`)
- Entity detail:
  - `Mainscreen/EntityDetail/*`
  - Links via `@Query` built in `Mainscreen/NodeLinksQueryBuilder.swift`
  - Media/gallery via `Mainscreen/NodeDetailShared/*` and `PhotoGallery/*`
- Attribute detail:
  - `Mainscreen/AttributeDetail/*`
  - Details values card: `Mainscreen/Details/NodeDetailsValuesCard.swift`

### Graph Tab
- `GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ extensions)
  - Graph picker sheet: `GraphPickerSheet.swift`
  - Inspector sheet: `GraphCanvasScreen+Inspector.swift`
  - Jump consumption: `GraphCanvasScreen+Loading.swift` (reads `GraphJumpCoordinator`)

### Stats Tab
- `Stats/GraphStatsView.swift`
  - Loads via `Stats/GraphStatsLoader.swift` (actor) and commits snapshots

### Settings Tab
- `Settings/SettingsView.swift` (+ extracted sections)
  - Appearance + Display settings
  - Pro tile + paywall/center (`Settings/SettingsView+ProTile.swift`, `Pro/*`)
  - Sync & Maintenance (`Settings/SyncMaintenanceView.swift`)

## Build & Configuration
- Xcode project: `BrainMesh/BrainMesh.xcodeproj`
- Targets (from `project.pbxproj`):
  - `BrainMesh` (app)
  - `BrainMeshTests`, `BrainMeshUITests`
- Deployment target: `IPHONEOS_DEPLOYMENT_TARGET = iOS 26.0` (from `project.pbxproj`)
- Bundle IDs:
  - App: `de.marcfechner.BrainMesh` (from `project.pbxproj`)
- Entitlements:
  - `BrainMesh/BrainMesh.entitlements` (CloudKit iCloud container + aps-environment)
- Info.plist:
  - `UIBackgroundModes = remote-notification` (CloudKit push)
  - `NSFaceIDUsageDescription` (Graph unlock)
  - Pro product id overrides: `BM_PRO_SUBSCRIPTION_ID_01`, `BM_PRO_SUBSCRIPTION_ID_02` (default “01”/“02”)
- StoreKit testing:
  - `BrainMesh Pro.storekit` exists for local StoreKit configuration testing in Xcode.

## Conventions (Naming, Patterns, Do / Don’t)
- **No @Model across concurrency boundaries**:
  - Loaders return DTO snapshots (`EntitiesHomeRow`, `GraphCanvasSnapshot`, `GraphStatsSnapshot`, …).
  - Pattern documented in `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` and `GraphCanvas/GraphCanvasDataLoader.swift`.
- **SwiftData relationship macros**:
  - Inverses are intentionally defined on one side only (see comments in `Models/MetaEntity.swift` and `Models/MetaAttribute.swift`) to avoid macro circularity.
- **Stored search indices**:
  - `nameFolded`, `notesFolded`, `noteFolded`, `searchLabelFolded` maintained via `didSet` or bootstrap backfill (`GraphBootstrap.swift`).
- **Graph scoping**:
  - Most models have optional `graphID` for soft migration; use `GraphBootstrap` to backfill.
- **Avoid toolbar overflow issues**:
  - Graph screen keeps toolbar minimal (see comment in `GraphCanvasScreen.swift`).

## How to work on this project (Setup Steps + wo anfangen)
### Setup
1. Open `BrainMesh/BrainMesh.xcodeproj` in Xcode.
2. Ensure Signing/Capabilities include iCloud + CloudKit and the container id matches:
   - `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`, `Settings/SyncRuntime.swift`).
3. Run on a device signed into iCloud to test sync (CloudKit `.automatic`).
4. Optional: StoreKit local test
   - Configure the run scheme to use `BrainMesh Pro.storekit` for local paywall testing.

### Where to start (new dev)
- App lifecycle + storage: `BrainMeshApp.swift`, `AppRootView.swift`
- Data model: `Models/*` + `Attachments/MetaAttachment.swift`
- Graph canvas: `GraphCanvas/GraphCanvasScreen/*` + `GraphCanvas/GraphCanvasView/*`
- Entities flow: `Mainscreen/EntitiesHome/*`, `Mainscreen/EntityDetail/*`, `Mainscreen/AttributeDetail/*`
- Settings system: `Settings/SettingsView.swift` + `Settings/Display/*` + `Settings/Appearance/*`


### Typical workflows (Kurzrezepte)
- **Neues SwiftData-Model hinzufügen**
  1. `@Model`-Typ in `Models/` (oder passendem Feature-Ordner wie `Attachments/`) anlegen.
  2. In `BrainMeshApp.init()` in die `Schema([...])` Liste aufnehmen (`BrainMeshApp.swift`).
  3. Falls der Typ `graphID` braucht: optionales Feld + Backfill im Startup ergänzen (`GraphBootstrap.swift`).
  4. Bei Suchfeldern: `*Folded` Index anlegen + `didSet` Pflege + Backfill (siehe `MetaEntity.swift`, `GraphBootstrap.swift`).

- **Neuen “off-main” Loader bauen**
  1. Actor in Feature-Ordner anlegen (Beispiele: `GraphCanvasDataLoader.swift`, `EntitiesHomeLoader.swift`).
  2. `AnyModelContainer` speichern + pro call einen frischen `ModelContext` bauen.
  3. DTO-Snapshot zurückgeben (keine `@Model` Instanzen).
  4. In `Support/AppLoadersConfigurator.swift` registrieren.

- **Neue Settings-Option**
  1. Persistente Keys: `Support/BMAppStorageKeys.swift` oder in `DisplaySettingsStore`/`AppearanceStore`.
  2. UI in `Settings/SettingsView+*.swift` ergänzen.
  3. Wenn per Screen Override: Model in `Settings/Display/*DisplaySettings.swift` + Migration/Defaults in `Settings/Display/DisplaySettingsStore.swift`.

- **“Jump into Graph” aus einem Detail-Screen**
  1. `GraphJumpCoordinator.requestJump(...)` aufrufen (`GraphJumpCoordinator.swift`).
  2. Root Tab umschalten via `RootTabRouter.openGraph()` (`RootTabRouter.swift`).
  3. GraphCanvas konsumiert Jump nach Load (`GraphCanvasScreen+Loading.swift`).

## Quick Wins (max 10, konkret)
1. Add **fetch limits / lazy loading** for link lists in detail screens if users can have “hundreds of links” (risk hotspot: `Mainscreen/EntityDetail/EntityDetailView.swift` uses `@Query var outgoingLinks/incomingLinks`).
2. Ensure **cancellation propagation** in all loaders is consistent (most already call `Task.checkCancellation()`; verify for attachment/media loaders).
3. Reduce Graph canvas main-thread load by lowering physics work when zoomed out (physics tick: `GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`).
4. Make “counts” caches invalidation more deterministic after edits (EntitiesHome counts TTL cache: `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`).
5. Consolidate duplicated “lock” fields in `MetaEntity`/`MetaAttribute` if truly unused (usage appears only on `MetaGraph` via `GraphLockCoordinator.swift`) — **migration risk**.
6. Replace ad-hoc `Task.detached` disk work in views with shared helper (e.g., cache size computation in `Settings/SyncMaintenanceView.swift`) to keep task lifetimes controllable.
7. Add a lightweight “sync debug” log toggle using `BMLog` categories (`Observability/BMObservability.swift`) to reproduce user issues.
8. Standardize “value snapshot” naming (`*Snapshot`, `*Row`) and add a short doc comment in each loader for consistency.
9. Add “Open Questions” as TODOs in code where needed (e.g., merge/conflict UX for CloudKit).
10. Split the largest UI files into subviews/extensions earlier to reduce merge conflicts (`EntitiesHomeView.swift`, `GraphCanvasScreen.swift`).

---
## Open Questions (UNKNOWN)
- **UNKNOWN**: Any custom SwiftData migration strategy beyond `GraphBootstrap.swift` (schema evolution, model versioning).
- **UNKNOWN**: CloudKit conflict resolution/merge behavior expectations (UI/UX + testing strategy).
- **UNKNOWN**: Whether links between attributes are supported in UI (model allows NodeKind on links; GraphCanvas loader currently filters entity–entity for global load).
- **UNKNOWN**: Maximum expected attachment/image sizes and whether CloudKit record size constraints are ever hit in practice (images are `Data?` without `.externalStorage` on entity/attribute models).
