# PROJECT_CONTEXT.md — BrainMesh (Start Here)

## TL;DR
**BrainMesh** ist eine iOS/iPadOS-App (Deployment Target **iOS 26.0**, siehe `BrainMesh.xcodeproj/project.pbxproj`) zum Aufbau eines persönlichen Knowledge-Graphs: Graph → Entitäten → Attribute, plus Verknüpfungen, frei definierbare Detail-Felder und Medien/Datei-Anhänge. Persistenz läuft über **SwiftData** mit optionalem **CloudKit**-Sync (Fallback auf lokal-only in Release bei Init-Fehlern, siehe `BrainMesh/BrainMeshApp.swift`).

## Key Concepts (Domänenbegriffe)
- **Graph (`MetaGraph`)**: Workspace/Container. Der „aktive Graph“ wird global über `@AppStorage(BMAppStorageKeys.activeGraphID)` geführt (z.B. `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`).
- **Entität (`MetaEntity`)**: Knoten-Typ im Graph (z.B. „Buch“, „Projekt“). Hat Attribute, Notizen, optional Bild/Icon. (`BrainMesh/Models.swift`)
- **Attribut (`MetaAttribute`)**: Knoten-Typ, gehört optional zu einer Entität (Owner), hat Notizen, optional Bild/Icon. (`BrainMesh/Models.swift`)
- **Link (`MetaLink`)**: Verknüpfung zwischen Nodes (Entity↔Entity, plus Labels/Notiz). (`BrainMesh/Models.swift`)
- **Details-Schema (`MetaDetailFieldDefinition`)**: Pro Entität definierbare Custom-Felder (Typ, Unit, Options, Pinning). (`BrainMesh/Models.swift`)
- **Details-Werte (`MetaDetailFieldValue`)**: Pro Attribut gespeicherte Werte für die definierten Felder. (`BrainMesh/Models.swift`)
- **Attachment (`MetaAttachment`)**: Datei/Video/Galerie-Bild an Entity oder Attribut; Owner wird als `(ownerKindRaw, ownerID)` gespeichert (keine Relationship-Makros). (`BrainMesh/Attachments/MetaAttachment.swift`)
- **Hydration**: Background-Jobs, die lokal gecachte Dateien (Bilder/Attachments) aus SwiftData-Bytes erzeugen, ohne die UI zu blockieren (z.B. `BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`).
- **Graph Lock**: Optionaler Zugriffsschutz pro Graph (Biometrie/Passwort). (`BrainMesh/Security/*`, plus Felder in `MetaGraph`, `MetaEntity`, `MetaAttribute` in `BrainMesh/Models.swift`)

## Architecture Map (Layer/Module → Verantwortung → Abhängigkeiten)
- **UI (SwiftUI)**
  - Root: `BrainMesh/BrainMeshApp.swift` → `BrainMesh/AppRootView.swift` → `BrainMesh/ContentView.swift`
  - Feature-Screens: `BrainMesh/Mainscreen/*`, `BrainMesh/GraphCanvas/*`, `BrainMesh/Stats/*`, `BrainMesh/Settings/*`
  - Abhängigkeiten: EnvironmentObjects (Appearance/Display/Onboarding/Security), Loader-Snapshots, SwiftData `@Query` für einfache Listen
- **State Stores / Coordinators**
  - `AppearanceStore` (`BrainMesh/Settings/Appearance/AppearanceStore.swift`)
  - `DisplaySettingsStore` (`BrainMesh/Settings/Display/DisplaySettingsStore.swift`)
  - `OnboardingCoordinator` (`BrainMesh/Onboarding/OnboardingCoordinator.swift`)
  - `GraphLockCoordinator` (`BrainMesh/Security/GraphLockCoordinator.swift`)
  - `SystemModalCoordinator` (`BrainMesh/Support/SystemModalCoordinator.swift`)
  - Abhängigkeiten: `UserDefaults`/`@AppStorage`, SwiftUI Environment
- **Background Loader/Hydrator Actors (SwiftData off-main)**
  - Zentral konfiguriert via `AppLoadersConfigurator.configureAllLoaders(...)` (`BrainMesh/Support/AppLoadersConfigurator.swift`)
  - Pattern: `actor` hält `AnyModelContainer`, erstellt eigenen `ModelContext` im `Task.detached`, liefert **Value-Snapshots** (DTOs) statt `@Model` über Thread-Grenzen (z.B. `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`)
- **Persistence / Sync**
  - SwiftData `ModelContainer` mit Schema in `BrainMesh/BrainMeshApp.swift`
  - CloudKit-Config: `ModelConfiguration(schema:..., cloudKitDatabase: .automatic)` (Intent: iCloud Sync)
  - Runtime-Diagnose: `BrainMesh/Settings/SyncRuntime.swift` (AccountStatus, StorageMode)
- **Domain Model (SwiftData @Model)**
  - `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue` in `BrainMesh/Models.swift`
  - `MetaAttachment` in `BrainMesh/Attachments/MetaAttachment.swift`
- **Support / Utilities**
  - Keys: `BrainMesh/Support/BMAppStorageKeys.swift`
  - Throttling: `BrainMesh/Support/AsyncLimiter.swift`
  - Logging: `BrainMesh/Observability/BMObservability.swift`

## Folder Map (Ordner → Zweck)
- `BrainMesh/GraphCanvas/` — Canvas-Rendering + Physik-Simulation + Graph-Loading (Snapshots, Lens, MiniMap).
- `BrainMesh/Mainscreen/` — „klassische“ Screens: Entities Home, Entity/Attribute Detail, Details-Editor, Node-Picker, Link-Flows.
  - `Mainscreen/EntitiesHome/` — Home Tab (Liste/Grid, Suche, Sortierung, Loader).
  - `Mainscreen/EntityDetail/` & `Mainscreen/AttributeDetail/` — Detailseiten.
  - `Mainscreen/NodeDetailShared/` — shared UI/Loader für Detailseiten (Media, Links, Manage Views).
  - `Mainscreen/Details/` — Custom-Fields (Schema/Editor/Values).
- `BrainMesh/Attachments/` — Attachment Model + Import/Cache/Hydration + Thumbnails + Media-All Screen Loader.
- `BrainMesh/Images/` — Bildimport/Kompression/Decode (`ImageImportPipeline.swift`).
- `BrainMesh/PhotoGallery/` — Gallery UI (Viewer, Import, Actions).
- `BrainMesh/Settings/` — Settings Root + Sections; Unterordner `Appearance/`, `Display/`.
- `BrainMesh/Security/` — Graph Lock, Passwort, Unlock UI.
- `BrainMesh/Support/` — kleine, wiederverwendbare Helper (Keys, Limiter, Loader-Config).
- `BrainMesh/Observability/` — Micro-Logging/Timing.

## Data Model Map (Entities, Relationships, wichtige Felder)
**SwiftData Models (7):**
1. `MetaGraph` (`BrainMesh/Models.swift`)
   - `id`, `createdAt`, `name`, `nameFolded`
   - Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
2. `MetaEntity` (`BrainMesh/Models.swift`)
   - Scope: `graphID: UUID?`
   - `name`, `nameFolded`, `createdAt`, `notes`, `iconSymbolName`
   - Photo: `imageData: Data?` (sync), `imagePath: String?` (lokaler Cache)
   - Relationships:
     - `attributes: [MetaAttribute]?` (cascade, inverse: `MetaAttribute.owner`)
     - `detailFields: [MetaDetailFieldDefinition]?` (cascade, inverse: `MetaDetailFieldDefinition.owner`)
3. `MetaAttribute` (`BrainMesh/Models.swift`)
   - Scope: `graphID: UUID?`, Owner: `owner: MetaEntity?` (ohne Relationship-Macro)
   - `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`
   - `searchLabelFolded` (denormalisiert für Suche)
   - Relationship:
     - `detailValues: [MetaDetailFieldValue]?` (cascade, inverse: `MetaDetailFieldValue.attribute`)
4. `MetaLink` (`BrainMesh/Models.swift`)
   - Scope: `graphID: UUID?`
   - `sourceKindRaw`, `sourceID`, `sourceLabel`
   - `targetKindRaw`, `targetID`, `targetLabel`
   - `note` (optional)
5. `MetaDetailFieldDefinition` (`BrainMesh/Models.swift`)
   - Scope: `graphID: UUID?`, Scalars: `entityID`
   - `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
   - Relationship: `owner: MetaEntity?` (nullify, originalName "entity")
6. `MetaDetailFieldValue` (`BrainMesh/Models.swift`)
   - Scope: `graphID: UUID?`, Scalars: `attributeID`, `fieldID`
   - typed values: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
   - Owner: `attribute: MetaAttribute?` (ohne Relationship-Macro)
7. `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
   - Scope: `graphID: UUID?`
   - Owner: `ownerKindRaw`, `ownerID`
   - Kind: `contentKindRaw` (`file`, `video`, `galleryImage`)
   - Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
   - Data: `@Attribute(.externalStorage) fileData`
   - Cache: `localPath`

**Graph Scoping (Multi-Graph):**
- `graphID` ist bei vielen Modellen optional (Legacy-Migration). Bootstrap migriert fehlende IDs in Default-Graph (`BrainMesh/GraphBootstrap.swift`).

## Sync / Storage
- **SwiftData Schema + Container**
  - Schema wird explizit in `BrainMesh/BrainMeshApp.swift` gebaut (Liste der Modelklassen).
  - CloudKit-Init via `ModelConfiguration(..., cloudKitDatabase: .automatic)`. Bei Fehler:
    - DEBUG: `fatalError(...)`
    - RELEASE: Fallback zu lokal-only `ModelConfiguration(schema: schema)` (siehe `BrainMesh/BrainMeshApp.swift`)
- **iCloud/CloudKit Runtime Diagnostics**
  - `SyncRuntime` nutzt `CKContainer(identifier: "iCloud.de.marcfechner.BrainMesh")` und `accountStatus()` (`BrainMesh/Settings/SyncRuntime.swift`)
- **Entitlements / Info.plist**
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh.entitlements`)
  - iCloud Services: `CloudKit` (`BrainMesh/BrainMesh.entitlements`)
  - `UIBackgroundModes` enthält `remote-notification` (`BrainMesh/Info.plist`)
  - FaceID Usage: `NSFaceIDUsageDescription` (`BrainMesh/Info.plist`)
- **Local Caches**
  - Bilder: `Application Support/BrainMeshImages` + `NSCache` (`BrainMesh/ImageStore.swift`)
  - Attachments: `Application Support/BrainMeshAttachments` (siehe `BrainMesh/Attachments/AttachmentStore.swift` + `AttachmentHydrator`)
- **Hydration**
  - `ImageHydrator` (actor): schreibt deterministische JPEGs aus `imageData` und setzt `imagePath` (`BrainMesh/ImageHydrator.swift`)
  - `AttachmentHydrator` (actor): de-duped + throttled write of cached attachment files (`BrainMesh/Attachments/AttachmentHydrator.swift`)
- **Offline-Verhalten**
  - Framework-Standard: SwiftData arbeitet lokal; CloudKit synct asynchron, sobald Account+Netz verfügbar sind. Projektspezifische Offline-UX: **UNKNOWN** (keine expliziten Retry/Conflict-UI-Flows gefunden).

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMeshApp` (`BrainMesh/BrainMeshApp.swift`)
  - setzt `modelContainer`
  - registriert EnvironmentObjects
- `AppRootView` (`BrainMesh/AppRootView.swift`)
  - Startup-Pipeline: `GraphBootstrap`, Lock-Enforcement, ImageAutoHydration
  - Debounced Background-Lock, um System-Picker (Photos Hidden Album) nicht abzuschießen
- `ContentView` (`BrainMesh/ContentView.swift`) — Root `TabView`
  1) **Entitäten**: `EntitiesHomeView`
  2) **Graph**: `GraphCanvasScreen`
  3) **Stats**: `GraphStatsView`
  4) **Einstellungen**: `SettingsView` (in `NavigationStack`)

### Entitäten-Tab
- `EntitiesHomeView` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`)
  - `NavigationStack`, `searchable`, view options sheet, add-entity sheet, graph picker sheet
  - Daten werden über `EntitiesHomeLoader.loadSnapshot(...)` geladen (off-main) (`.../EntitiesHomeLoader.swift`)
  - Navigation: Row → `EntityDetailView` via `EntityDetailRouteView` (resolves model by ID)

### Entity/Attribute Detail
- `EntityDetailView` (`BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`)
- `AttributeDetailView` (`BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`)
- Shared Sections/Helpers:
  - `Mainscreen/NodeDetailShared/*` (Media, Links, Manage Views)
- Details:
  - `DetailsValueEditorSheet` (`BrainMesh/Mainscreen/Details/DetailsValueEditorSheet.swift`)
  - Schema Builder/Lists in `Mainscreen/Details/DetailsSchema/*`

### Graph-Tab
- `GraphCanvasScreen` (`BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + `GraphCanvasScreen+*.swift`)
  - GraphPicker Sheet, Inspector Sheet, NodePicker Sheet
  - Detail-Sheets: `EntityDetailView` / `AttributeDetailView` in `NavigationStack`
  - Daten: `GraphCanvasDataLoader.loadSnapshot(...)` (actor + detached context) (`BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`)
- `GraphCanvasView` (`BrainMesh/GraphCanvas/GraphCanvasView.swift` + `...+Rendering.swift`, `...+Physics.swift`, ...)
  - Canvas Rendering + 30 FPS Physik via `Timer` (siehe `GraphCanvasView+Physics.swift`)

### Stats-Tab
- `GraphStatsView` (`BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`)
  - Loader: `GraphStatsLoader` (`BrainMesh/Stats/GraphStatsLoader.swift`) — off-main snapshot loading

### Settings-Tab
- `SettingsView` (`BrainMesh/Settings/SettingsView.swift`)
  - Sections in `SettingsView+*.swift` (Sync, Maintenance, Appearance, Display, etc.)
  - Maintenance: ImageCache rebuild, Attachment cache clear, etc.

## Build & Configuration
- Xcode-Projekt: `BrainMesh.xcodeproj`
- Targets: `BrainMesh`, `BrainMeshTests`, `BrainMeshUITests` (siehe Bundle IDs in `BrainMesh.xcodeproj/project.pbxproj`)
- Deployment Target: `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (`BrainMesh.xcodeproj/project.pbxproj`)
- Swift Version Setting: `SWIFT_VERSION = 5.0` (`BrainMesh.xcodeproj/project.pbxproj`)
- Info.plist: `BrainMesh/Info.plist` (minimal; s.o.)
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit, aps-environment)
- SPM: Kein `Package.resolved`/`Package.swift` gefunden und keine `XCRemoteSwiftPackageReference` Einträge in `BrainMesh.xcodeproj/project.pbxproj` → keine SPM-Packages im Repo-Stand.
- .xcconfig: **Keine** `.xcconfig` Dateien gefunden → Secrets-Handling über `.xcconfig`: **UNKNOWN** (aktuell nicht vorhanden).

## Conventions (Naming, Patterns, Do/Don’t)
- **Keine `@Model` Instanzen über Concurrency-Grenzen** schicken: Loader liefern DTOs (z.B. `EntitiesHomeRow`, `GraphCanvasSnapshot`).
- **SwiftData-Fetches off-main**: für große Listen/Graph/Stats per actor-loader + `Task.detached` (`Support/AppLoadersConfigurator.swift`).
- **AppStorage Keys zentral**: nur `BMAppStorageKeys.*` verwenden (`Support/BMAppStorageKeys.swift`).
- **Search**: Folded Strings (`nameFolded`, `searchLabelFolded`) + `BMSearch.fold(...)` (`Models.swift`).
- **CloudKit Record Druck reduzieren**: JPEG-Kompression für `imageData` (`Images/ImageImportPipeline.swift`), Attachments `externalStorage` (`Attachments/MetaAttachment.swift`).
- **SwiftUI Performance**: keine Disk-I/O in `body` (`ImageStore.loadUIImage(path:)` warnt explizit, `ImageStore.swift`).

## How to work on this project (Setup + wo anfangen)
1. Öffne `BrainMesh.xcodeproj` in einer Xcode-Version, die iOS 26 Targets unterstützt.
2. Prüfe Signing + iCloud Capability:
   - Entitlements: `iCloud.de.marcfechner.BrainMesh` (`BrainMesh.entitlements`)
   - Bei CloudKit-Problemen: Settings → Sync Sektion zeigt Runtime-Status (`Settings/SyncRuntime.swift`, `SettingsView+SyncSection.swift`)
3. Run in Debug auf einem Gerät mit iCloud Login, wenn Sync getestet werden soll.
4. Startpunkte fürs Verständnis:
   - Root/Startup: `BrainMeshApp.swift`, `AppRootView.swift`
   - Data Model: `Models.swift`, `Attachments/MetaAttachment.swift`
   - Loader-Konfiguration: `Support/AppLoadersConfigurator.swift`
5. Feature-Dev Flow (typisch):
   - Model ändern/neu hinzufügen → **Schema-Liste** in `BrainMeshApp.swift` anpassen
   - ggf. Legacy-Migration in `GraphBootstrap.swift` ergänzen
   - UI + Loader anpassen; für schwere Fetches: neues `actor`-Loader-Pattern wie `EntitiesHomeLoader` kopieren

## Quick Wins (max 10, konkret)
- [ ] **Audit: Fetches auf MainActor**: Stellen wie `NodeMediaPreviewLoader.load(...)` sind `@MainActor` und machen `fetchCount` + `fetch` (`Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`). Prüfen, ob Call-Sites das nur in `.task`/onAppear tun (nicht in `body`).
- [ ] **Crash-Verhalten in DEBUG**: CloudKit Container Init nutzt `fatalError` in DEBUG (`BrainMeshApp.swift`). Wenn häufig Signing-Fehler auftreten: optional lokales Fallback auch in DEBUG (Dev-Option).
- [ ] **APS environment**: `aps-environment` ist in Entitlements auf `development` gesetzt (`BrainMesh.entitlements`). Für Release/TestFlight prüfen: Build-Setting/Entitlements Handling.
- [ ] **AppStorage Konsistenz**: Suchen nach String-Literals in `@AppStorage("...")` (sollte `BMAppStorageKeys.*` sein).
- [ ] **GraphCanvas Node Caps**: Default `maxNodes=140`, `maxLinks=800` (`GraphCanvasScreen.swift`). Für große Graphen UX-Optionen/Warnings überlegen.
- [ ] **Attachment & Image Cache Monitoring**: Settings zeigt Cache Sizes (`SettingsView.swift`). Optional: logging der Hydration-Dauer (`ImageHydrator`, `AttachmentHydrator`).
- [ ] **Unit Tests auf Daten-Migration**: `GraphBootstrap.migrateLegacyRecordsIfNeeded` hat Logik, aber keine Tests (`GraphBootstrap.swift`). Small tests hinzufügen.
- [ ] **Search Normalization**: `nameFolded` wird via `didSet` gepflegt. Prüfen, ob alle Inits `nameFolded` initial setzen (bei `MetaEntity`/`MetaAttribute` ja) (`Models.swift`).
- [ ] **Link Label Denormalization**: Wenn Entities/Attributes umbenannt werden, müssen Link-Labels aktualisiert werden (Service vorhanden: `NodeRenameService` via `AppLoadersConfigurator`). Prüfen, dass alle Rename-Flows den Service triggern (**UNKNOWN**, Call-Sites nicht vollständig auditiert).
- [ ] **Observability**: `BMLog` existiert (load/expand/physics). Optional: signposts für Loader Laufzeiten (Graph/Stats/Home) ergänzen.

## Open Questions (UNKNOWN)
- **SPM/Dependencies**: keine `Package.resolved` gefunden; falls Packages über Workspace außerhalb Repo kommen: **UNKNOWN**.
- **Offline/Conflict UX**: keine expliziten Konflikt- oder Merge-UI-Flows gefunden (SwiftData/CloudKit Default-Verhalten vorausgesetzt): **UNKNOWN**.
- **Push/CloudKit Subscriptions**: `remote-notification` ist gesetzt, aber keine `CKSubscription`/`CKShare` Nutzung gefunden: **UNKNOWN**, ob geplant.
- **Secrets Handling**: keine `.xcconfig` im Repo; falls extern verwaltet: **UNKNOWN**.
