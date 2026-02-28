# PROJECT_CONTEXT.md — BrainMesh

## TL;DR
BrainMesh ist eine iOS-App (iPhone/iPad) zum Erstellen von **Graphen** aus **Entitäten** und **Attributen** mit **Links**, Notizen, Bildern und Anhängen. Persistenz via **SwiftData**, Sync über **CloudKit** (wenn verfügbar). Mindest-iOS: **26.0** (Xcode Target: `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in `BrainMesh.xcodeproj/project.pbxproj`).

## Key Concepts / Domänenbegriffe
- **Graph / Workspace**: logischer Arbeitsbereich. Modell: `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`).
- **Entität**: „Ding“/Knoten-Typ A. Modell: `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`).
- **Attribut**: „Eigenschaft“/Knoten-Typ B (gehört zu einer Entität). Modell: `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`).
- **Link**: Kante zwischen zwei Knoten (Entity↔Entity oder (je nach UI) auch Attribute). Modell: `MetaLink` (`BrainMesh/Models/MetaLink.swift`).
- **Details-Felder**: frei konfigurierbare Felder je Entität (Schema) + Werte je Attribut. Modelle: `MetaDetailFieldDefinition`, `MetaDetailFieldValue` (`BrainMesh/Models/DetailsModels.swift`).
- **Anhänge**: Dateien/Videos/Galeriebilder an Entity/Attribute. Modell: `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`).
- **Graph-Schutz**: optionaler Zugriffsschutz pro Graph (Systemschutz + optional eigenes Passwort). Koordinator: `GraphLockCoordinator` (`BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`).
- **Pro**: StoreKit2 Subscriptions + Feature-Gating (mehr Graphen, Graph-Schutz). `ProEntitlementStore` (`BrainMesh/Pro/ProEntitlementStore.swift`).

## Architecture Map (Layer/Module → Verantwortlichkeiten → Abhängigkeiten)
- **UI (SwiftUI)**
  - Root/Navigation: `BrainMeshApp.swift` → `AppRootView.swift` → `ContentView.swift` (Tabs) (`BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`)
  - Feature-Screens: `Mainscreen/*`, `GraphCanvas/*`, `Stats/*`, `Settings/*`, `GraphTransfer/*`, `GraphPicker/*`
  - **Abhängigkeiten:** `ModelContext` (SwiftData) + EnvironmentObjects (Stores/Coordinators)
- **Coordinators / Stores (State & Routing)**
  - Appearance: `AppearanceStore` (`BrainMesh/Settings/Appearance/AppearanceStore.swift`)
  - Display Presets/Overrides: `DisplaySettingsStore` (`BrainMesh/Settings/Display/DisplaySettingsStore.swift`)
  - Tabs: `RootTabRouter` (`BrainMesh/RootTabRouter.swift`)
  - Cross-screen Jump: `GraphJumpCoordinator` (`BrainMesh/GraphJumpCoordinator.swift`)
  - Graph Lock: `GraphLockCoordinator` (`BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`)
  - System modal guard: `SystemModalCoordinator` (`BrainMesh/Support/SystemModalCoordinator.swift`)
- **Loaders / Services (off-main Datenzugriff, DTO-Snapshots)**
  - Konfiguration zentral: `AppLoadersConfigurator.configureAllLoaders(...)` (`BrainMesh/Support/AppLoadersConfigurator.swift`)
  - Beispiele: `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`, `AttachmentHydrator`, `ImageHydrator` …
  - **Abhängigkeiten:** `AnyModelContainer` → `ModelContext` (Background) → SwiftData Models
- **Model (SwiftData @Model)**
  - `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`, `MetaDetailsTemplate`
- **Storage/Sync**
  - `ModelContainer` wird in `BrainMeshApp.init()` erstellt (Schema + `ModelConfiguration(... cloudKitDatabase: .automatic)`) (`BrainMesh/BrainMeshApp.swift`)
  - Runtime-Status/Diagnose: `SyncRuntime` (`BrainMesh/Settings/SyncRuntime.swift`)
  - Caches: `ImageStore` (`BrainMesh/ImageStore.swift`), `AttachmentStore` (`BrainMesh/Attachments/AttachmentStore.swift`)

## Folder Map (Ordner → Zweck)
- `BrainMesh/` (App-Target Root)
  - `Models/` — SwiftData @Model-Typen + Search-Helpers
  - `Mainscreen/` — Entitäten/Attribute UI (Home, Details, Create, Pickers, Bulk Link)
  - `GraphCanvas/` — Canvas-Rendering, Physik, GraphScreen + DataLoader
  - `Stats/` — Stats UI + StatsLoader/Service
  - `Settings/` — Settings Hub + Unterseiten (Sync/Wartung, Anzeige, Import, Hilfe)
  - `GraphPicker/` + `GraphPickerSheet.swift` — Graph-Auswahl, Add/Rename/Delete, Security entry
  - `GraphTransfer/` — Export/Import `.bmgraph` + Service
  - `Attachments/` — Attachment-Model, Import-Pipeline, Preview, Cache/Hydration, Video tools
  - `PhotoGallery/` — Detail-Galerie (zusätzliche Bilder als Attachments)
  - `Security/` — Unlock/Lock/Security UI + Crypto
  - `Pro/` — StoreKit2 Entitlements, Paywall/Manage UI, Feature Limits
  - `Support/` — kleine Infrastruktur (AppStorage Keys, AsyncLimiter, AnyModelContainer, UTType)
  - `Observability/` — os.Logger Wrapper + Timing (`BrainMesh/Observability/BMObservability.swift`)
  - `Icons/` — SF-Symbol Picker + Icon Data (`BrainMesh/Icons/*`)
- `BrainMeshTests/`, `BrainMeshUITests/` — minimale Test-Targets
- `BrainMesh.xcodeproj/` — Xcode Projektdateien

## Data Model Map (Entities, Relationships, wichtige Felder)
### MetaGraph (`BrainMesh/Models/MetaGraph.swift`)
- `id: UUID`, `createdAt: Date`, `name` + `nameFolded`
- Graph-Schutz: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### MetaEntity (`BrainMesh/Models/MetaEntity.swift`)
- `id`, `createdAt`, `graphID`
- `name` + `nameFolded`, `notes` + `notesFolded`
- Media: `imageData: Data?`, `imagePath: String?`, `iconSymbolName: String?`
- **Relationships**
  - `attributes: [MetaAttribute]` (inverse `MetaAttribute.owner`, deleteRule `.cascade`)
  - `detailFields: [MetaDetailFieldDefinition]` (inverse `MetaDetailFieldDefinition.owner`, deleteRule `.cascade`)

### MetaAttribute (`BrainMesh/Models/MetaAttribute.swift`)
- `id`, `graphID`
- `name` + `nameFolded`, `notes` + `notesFolded`
- `owner: MetaEntity?` (kein inverse hier; wird über `MetaEntity.attributes` geführt)
- Media: `imageData`, `imagePath`, `iconSymbolName`
- Details: `detailValues: [MetaDetailFieldValue]` (inverse `MetaDetailFieldValue.attribute`, deleteRule `.cascade`)
- Search: `searchLabelFolded` (kombiniert Entity+Attribut via `displayName`)

### MetaLink (`BrainMesh/Models/MetaLink.swift`)
- `id`, `createdAt`, `graphID`
- Knoten-Referenzen (keine Relationships): `sourceKindRaw/sourceID`, `targetKindRaw/targetID`
- Denormalisierte Labels: `sourceLabel`, `targetLabel` (aktualisiert via `LinkCleanup.relabelLinks` + `NodeRenameService` in `BrainMesh/Mainscreen/LinkCleanup.swift`)
- Notiz: `note` + `noteFolded`

### MetaAttachment (`BrainMesh/Attachments/MetaAttachment.swift`)
- `id`, `createdAt`, `graphID`
- Owner: `ownerKindRaw`, `ownerID` (keine Relationship-Macros)
- Typ: `contentKindRaw` (`file`, `video`, `galleryImage`)
- Bytes: `@Attribute(.externalStorage) fileData: Data?` + lokaler Cachepfad `localPath`

### Details Models (`BrainMesh/Models/DetailsModels.swift`)
- `MetaDetailFieldDefinition` (Schema pro Entität): `owner: MetaEntity?` + `entityID`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
- `MetaDetailFieldValue` (Werte pro Attribut): `attribute: MetaAttribute?` + `attributeID`, `fieldID`, typed values (`stringValue/intValue/doubleValue/dateValue/boolValue`)

### MetaDetailsTemplate (`BrainMesh/Models/MetaDetailsTemplate.swift`)
- Templates für Details-Sets: `fieldsJSON` (JSON-Array), `graphID`, `name` + `nameFolded`

## Sync/Storage
- **SwiftData Container**
  - Schema in `BrainMesh/BrainMeshApp.swift` (Liste der @Model-Typen).
  - CloudKit-Konfiguration: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)` (`BrainMesh/BrainMeshApp.swift`).
  - Release-Fallback: Wenn CloudKit init fehlschlägt → lokaler Container (nur in non-DEBUG). (`BrainMesh/BrainMeshApp.swift`)
- **iCloud Runtime/Diagnose**
  - Container-ID: `"iCloud.de.marcfechner.BrainMesh"` (`BrainMesh/Settings/SyncRuntime.swift`, `BrainMesh/BrainMesh.entitlements`)
  - Settings UI: `SyncMaintenanceView` + `SettingsView+SyncSection.swift`
- **Migration/Backfill (app-intern, keine „echte“ Schema-Migration)**
  - Graph bootstrap + legacy graphID backfill + notesFolded backfill: `GraphBootstrap` (`BrainMesh/GraphBootstrap.swift`) wird in `AppRootView.bootstrapGraphing()` ausgeführt (`BrainMesh/AppRootView.swift`).
  - Attachments graphID backfill (um OR-Predicates zu vermeiden): `AttachmentGraphIDMigration` (`BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).
- **Caches**
  - Bilder: `ImageStore` (NSCache + Disk in Application Support) + `ImageHydrator` (`BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`).
  - Attachments: `AttachmentStore` (Disk cache) + `AttachmentHydrator` (`BrainMesh/Attachments/AttachmentStore.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`).

## UI Map (Hauptscreens + Navigation + wichtige Flows)
### Root
- `BrainMeshApp` → `AppRootView` → `ContentView` (`TabView`)
  - Tab **Entitäten**: `EntitiesHomeView()` (`BrainMesh/ContentView.swift`)
  - Tab **Graph**: `GraphCanvasScreen()` (`BrainMesh/ContentView.swift`)
  - Tab **Stats**: `GraphStatsView()` (`BrainMesh/ContentView.swift`)
  - Tab **Einstellungen**: `SettingsView(showDoneButton: false)` in `NavigationStack` (`BrainMesh/ContentView.swift`)

### Wichtige Flows
- **Graph wählen/verwalten**: `GraphPickerSheet` (Sheet), z.B. von EntitiesHome/GraphCanvas (`BrainMesh/GraphPickerSheet.swift`)
- **Entity Detail**: NavigationLink → `EntityDetailRouteView(entityID:)` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeList.swift`) → `EntityDetailView` (`BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`)
- **Attribute Detail**: analog `AttributeDetailView` (`BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`)
- **Graph Canvas**: `GraphCanvasScreen` lädt Snapshot via `GraphCanvasDataLoader` (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Loading.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`)
- **Bulk Link**: `BulkLinkView` (`BrainMesh/Mainscreen/BulkLinkView.swift`)
- **Attachments/Media**
  - Detail-Galerie: `PhotoGallerySection` (`BrainMesh/PhotoGallery/PhotoGallerySection.swift`)
  - Dateien/Videos: `AttachmentsSection` (`BrainMesh/Attachments/AttachmentsSection.swift`)
- **Export/Import**: Settings tile → `GraphTransferView` (`BrainMesh/Settings/SettingsView+GraphTransferTile.swift`, `BrainMesh/GraphTransfer/GraphTransferView.swift`)
- **Graph-Schutz**: aus GraphPicker → `GraphSecuritySheet` (`BrainMesh/Security/GraphSecuritySheet.swift`)
- **Pro**: Settings tile → `ProCenterView` und ggf. `ProPaywallView` (`BrainMesh/Pro/ProCenterView.swift`, `BrainMesh/Pro/ProPaywallView.swift`)

## Build & Configuration
- Targets: `BrainMesh, BrainMeshTests, BrainMeshUITests` (`BrainMesh.xcodeproj/project.pbxproj`)
- Bundle Identifiers:
  - App: `de.marcfechner.BrainMesh` (`BrainMesh.xcodeproj/project.pbxproj`)
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`
  - iCloud Services: CloudKit
  - `aps-environment = development` (Distribution baut typischerweise anders; hier nur als Projektstand sichtbar)
- Info.plist: `BrainMesh/Info.plist`
  - `UIBackgroundModes = remote-notification` (CloudKit Push)
  - `NSFaceIDUsageDescription` (Graph-Schutz)
  - Pro IDs: `BM_PRO_SUBSCRIPTION_ID_01`, `BM_PRO_SUBSCRIPTION_ID_02`
  - UTType Export: `UTExportedTypeDeclarations` für `.bmgraph`
- StoreKit Config (Dev/Test): `BrainMesh/BrainMesh Pro.storekit` (wird über Scheme verwendet, nicht automatisch im Release aktiv)

## Conventions (Naming, Patterns, Do/Don’t)
- **Keine SwiftData-Model-Objekte über Actor/Task-Grenzen schieben.** Stattdessen DTO-Snapshots (`EntitiesHomeRow`, `GraphCanvasSnapshot`, …). Beispiel: `EntitiesHomeLoader.swift`, `GraphCanvasDataLoader.swift`.
- **Kein Fetch im Renderpfad** (SwiftUI `body` / Canvas draw). Stattdessen:
  - Precompute-Caches in `@State` und aktualisiere sie bei „realen“ Events (Selection change, data load).
  - Beispiel: `GraphCanvasScreen` Render-Caches (`drawEdgesCache`, `lensCache`) (`BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`).
- **Loader-Konfiguration zentral** in `AppLoadersConfigurator` (ein Ort, ein Pattern) (`BrainMesh/Support/AppLoadersConfigurator.swift`).
- **AppStorage Keys zentral**: `BMAppStorageKeys` (`BrainMesh/Support/BMAppStorageKeys.swift`).
- **File Splits via Extensions** bei großen Views/Services (z.B. `GraphCanvasScreen+*.swift`, `GraphCanvasView+*.swift`).

## How to work on this project (Setup + wo anfangen)
### Setup Steps (Dev-Maschine)
- Öffnen: `BrainMesh.xcodeproj`
- Signing/Capabilities prüfen:
  - iCloud Capability + CloudKit Container `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`)
  - (TestFlight/Release) korrekte Team/Bundle-ID
- Run:
  - Start im Simulator/Device (iOS 26.0+)
  - Für StoreKit Tests: Scheme → StoreKit Configuration auf `BrainMesh/BrainMesh Pro.storekit` setzen (**nur** Dev)

### Wo anfangen (neue Devs)
- Root/Boot: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`
- Datenmodell: `BrainMesh/Models/*` (+ `BrainMesh/Attachments/MetaAttachment.swift`)
- Hot features:
  - Entities Home: `BrainMesh/Mainscreen/EntitiesHome/*`
  - Graph: `BrainMesh/GraphCanvas/*`
  - Stats: `BrainMesh/Stats/*`
  - Settings: `BrainMesh/Settings/*`

## Hot Path Bereiche + größte Dateien (kurz)
### Hot Path (warum)
- Graph-Rendering/Physik: 30 FPS Timer + State-Updates (`GraphCanvasView+Physics.swift`) → viele SwiftUI invalidations; mitigiert via Caches in `GraphCanvasScreen` (`BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`, `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`).
- Link-Queries im Detail: `@Query` für Links ohne Fetch-Limit (`EntityDetailView`, `AttributeDetailView`) → kann bei sehr vielen Links teuer werden (`BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`, `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`, `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`).
- Attachments mit `externalStorage`: falsche Prädikate (OR) können in-memory filtering triggern → darum `AttachmentGraphIDMigration` (`BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).

### Größte Swift-Dateien (Top 10 nach Zeilen)
- `BrainMesh/GraphTransfer/GraphTransferView.swift` — 871 Zeilen
- `BrainMesh/GraphTransfer/GraphTransferService.swift` — 635 Zeilen
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — 499 Zeilen
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — 474 Zeilen
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — 442 Zeilen
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — 410 Zeilen
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — 404 Zeilen
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — 388 Zeilen
- `BrainMesh/Mainscreen/BulkLinkView.swift` — 367 Zeilen
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — 362 Zeilen

## Quick Wins (max 10, konkret)
1. Link-Queries in Detail-Screens „preview-first“ machen (fetchLimit/Loader) und „Alle Verbindungen“ on-demand laden (`EntityDetailView.swift`, `AttributeDetailView.swift`).
2. `GraphTransferView.swift` in Subviews + eigenes ViewModel-File splitten (871 Zeilen → besser wartbar).
3. `GraphStatsLoader` um Cancellation/Stale-Guard ergänzen (analog `GraphCanvasScreen+Loading.swift`), damit schnelle Tab-Wechsel keine teuren Background-Fetches „durchlaufen“ lassen.
4. `LinkCleanup.swift` trennen: `LinkCleanup` vs. `NodeRenameService` in eigene Files (aktuell Mischfile).
5. Einheitliches Logging für Loader-Dauern (BMLog + BMDuration) in `EntitiesHomeLoader`/`GraphStatsLoader` auf denselben Pattern-Standard bringen (`Observability/BMObservability.swift`).
6. Konsequent `Task.detached` vermeiden, wenn Structured Concurrency möglich ist (z.B. `SyncMaintenanceView.refreshCacheSizes()`), um Cancel/ScenePhase leichter zu handhaben.
7. JSON Icon Catalog (`Icons/IconCatalogData.json`) als build-time resource behandeln: klare Owner/Update-Story dokumentieren (Merge-Konflikte reduzieren).
8. `project.pbxproj` Änderungen minimieren (Formatter/Sort) — Merge-Risiko; dokumentieren, welche Xcode-Version genutzt wird (**UNKNOWN**, siehe Open Questions).
9. Konsolidieren von „System Modal“-Grace Pattern: überall Photos/File picker → begin/end sauber in einem Helper.
10. An UI-Hotspots (Graph/EntitiesHome) gezielt `EquatableView` / `@StateObject` Stabilisierung prüfen (**UNKNOWN** ob bereits nötig; erst messen).

## Open Questions (**UNKNOWN**)
- Gibt es eine definierte Xcode-Version/Toolchain-Policy im Team (wichtig wegen `project.pbxproj` Diffs)?
- Ist `.automatic` CloudKit DB bewusst gewählt (private vs. shared) oder soll es explizit `.private` sein?
- Gibt es Performance-Benchmarks (z.B. „ab X Nodes/Links ist Graph zäh“), um Refactors zu priorisieren?
