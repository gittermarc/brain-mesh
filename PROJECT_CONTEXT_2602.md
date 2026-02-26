# PROJECT_CONTEXT.md — BrainMesh (Start Here)

## TL;DR
BrainMesh ist eine SwiftUI iOS-App (Target iOS 26.0), die Wissens-„Graphen“ verwaltet: Entities enthalten Attributes, zwischen Nodes können Links bestehen (mit optionaler Notiz), und es gibt Attachments/Media. Persistenz läuft über SwiftData; Sync ist via CloudKit vorgesehen (ModelConfiguration `cloudKitDatabase: .automatic`), mit Release-Fallback auf local-only Storage.

## Key Concepts / Domänenbegriffe
- **Graph**: Workspace/Scope. Aktiver Graph wird in `UserDefaults` gespeichert und scopt Daten über `graphID`.
- **Entity**: Top-level Objekt im Graph, kann Notes, Icon und Main Photo haben.
- **Attribute**: Unterobjekt einer Entity, ebenfalls mit Notes/Icon/Main Photo.
- **Link**: Beziehung zwischen zwei Nodes (Entity/Attribute), optional mit `note`.
- **Details Schema**: Frei konfigurierbare Felder pro Entity (`MetaDetailFieldDefinition`), Werte liegen pro Attribute (`MetaDetailFieldValue`).
- **Attachment**: Datei/Video/Gallery-Image, an Entity/Attribute gebunden (Owner als `(ownerKindRaw, ownerID)`).
- **Graph Lock**: optionaler Zugriffsschutz pro Graph (Biometrics und/oder Passwort).

## Architecture Map (Layer/Module)
- **UI Layer (SwiftUI)**
  - Tab Root: `BrainMesh/ContentView.swift`
  - Feature UIs: `BrainMesh/Mainscreen/*`, `BrainMesh/GraphCanvas/*`, `BrainMesh/Stats/*`, `BrainMesh/Settings/*`, `BrainMesh/Onboarding/*`
- **Coordinators / State Stores (MainActor)**
  - Appearance & Display: `BrainMesh/Settings/Appearance/AppearanceStore.swift`, `BrainMesh/Settings/Display/DisplaySettingsStore.swift`
  - Onboarding: `BrainMesh/Onboarding/OnboardingCoordinator.swift`
  - Graph Lock: `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`
  - System Modals: `BrainMesh/Support/SystemModalCoordinator.swift`
- **Data Model (SwiftData)**
  - Core Models: `BrainMesh/Models/*`
  - Attachments Model: `BrainMesh/Attachments/MetaAttachment.swift`
- **Background Data Access (Actors + Snapshots)**
  - Config: `BrainMesh/Support/AppLoadersConfigurator.swift`
  - Loader/Hydrator Actors: `GraphCanvasDataLoader`, `GraphStatsLoader`, `EntitiesHomeLoader`, `AttachmentHydrator`, `ImageHydrator`, …
- **Utilities**
  - AppStorage Keys: `BrainMesh/Support/BMAppStorageKeys.swift`
  - Logging/Timing: `BrainMesh/Observability/BMObservability.swift`

## Folder Map
- `Assets.xcassets/` — **UNKNOWN** (Zweck nicht eindeutig ohne tieferes UI-Trace)
- `Attachments/` — Attachment Feature (MetaAttachment Model, Import/Compression, Hydration/Cache, UI Sections).
- `GraphCanvas/` — Graph-Ansicht (Canvas Rendering, Physics, DataLoader, MiniMap, Screen orchestration).
- `GraphPicker/` — Graph selection / management UI + services.
- `Icons/` — SF Symbols / Icon Picker UI.
- `Images/` — Static images/resources (non-code).
- `ImportProgress/` — Import progress UI/logic (bulk imports).
- `Mainscreen/` — Haupt-UI für Entities/Attributes/Links + Detail-Screens (EntityDetail, AttributeDetail, NodeDetailShared, Bulk-Linking, Pickers).
- `Models/` — SwiftData Models + Search/Enums.
- `Observability/` — Logging/Timing Helpers (os.Logger, durations).
- `Onboarding/` — Onboarding Flows + Coordinator/Progress.
- `PhotoGallery/` — Foto-/Gallery-Flows (Viewer, Browser, Actions).
- `Security/` — Graph Lock (FaceID/Passcode) + Security Sheets/Views + Crypto.
- `Settings/` — Settings Hub + Sections (Appearance, Display, Import, Sync & Wartung, Help/Info/About).
- `Stats/` — Stats Tab (Loader + Service-Layer + UI Components).
- `Support/` — App-weite Utilities (AppStorage keys, loader configuration, AsyncLimiter, SystemModalCoordinator, AnyModelContainer).

## SwiftData Models (Persistenz)

**Schema wird im App-Init registriert:** `BrainMesh/BrainMeshApp.swift`

### `MetaGraph` — Graph/Workspace
Pfad: `BrainMesh/Models/MetaGraph.swift`
- `id: UUID`
- `createdAt: Date`
- `name: String`, `nameFolded: String` (folded search)
- Security/Lock-Flags + Passwort-Hash/Salt:
  - `lockBiometricsEnabled: Bool`
  - `lockPasswordEnabled: Bool`
  - `passwordSaltB64: String?`, `passwordHashB64: String?`, `passwordIterations: Int`

### `MetaEntity` — Entity
Pfad: `BrainMesh/Models/MetaEntity.swift`
- `id: UUID`, `createdAt: Date`
- `graphID: UUID?` (Graph-Scope; optional für sanfte Migration)
- `name: String`, `nameFolded: String`
- `notes: String`
- `iconSymbolName: String?`
- Bild:
  - `imageData: Data?` (CloudKit-sync)
  - `imagePath: String?` (lokaler Disk-Cache; Dateiname)
- Beziehungen:
  - `attributes: [MetaAttribute]?` (Cascade; inverse: `MetaAttribute.owner`)
  - `detailFields: [MetaDetailFieldDefinition]?` (Cascade; inverse: `MetaDetailFieldDefinition.owner`)
- Convenience:
  - `attributesList` / `detailFieldsList` (de-dupe by `id`, sort by `sortIndex`)

### `MetaAttribute` — Attribute
Pfad: `BrainMesh/Models/MetaAttribute.swift`
- `id: UUID`
- `graphID: UUID?`
- `name: String`, `nameFolded: String`
- `notes: String`
- `iconSymbolName: String?`
- Bild:
  - `imageData: Data?`
  - `imagePath: String?`
- Owner (keine Relationship-Macro inverse hier, um Macro-Zirkularität zu vermeiden):
  - `owner: MetaEntity?`
- Detail-Werte:
  - `detailValues: [MetaDetailFieldValue]?` (Cascade; inverse: `MetaDetailFieldValue.attribute`)
- Suchlabel:
  - `searchLabelFolded: String` (kombiniert Entity + Attribute)

### `MetaLink` — Link zwischen Nodes
Pfad: `BrainMesh/Models/MetaLink.swift`
- `id: UUID`, `createdAt: Date`, `note: String?`
- `graphID: UUID?`
- Denormalisierte Labels (für schnelles Rendering):
  - `sourceLabel: String`, `targetLabel: String`
- Referenzen als Scalars:
  - `sourceKindRaw: Int`, `sourceID: UUID`
  - `targetKindRaw: Int`, `targetID: UUID`
- `sourceKind` / `targetKind` computed via `NodeKind`

### `MetaAttachment` — Attachments (Files / Videos / Gallery Images)
Pfad: `BrainMesh/Attachments/MetaAttachment.swift`
- `id: UUID`, `createdAt: Date`
- `graphID: UUID?`
- Owner als Scalars (bewusst ohne Relationship):
  - `ownerKindRaw: Int`, `ownerID: UUID`
- Content Kind:
  - `contentKindRaw: Int` (`AttachmentContentKind`: file/video/galleryImage)
- Metadata:
  - `title`, `originalFilename`, `contentTypeIdentifier` (UTType id), `fileExtension`, `byteCount`
- Daten:
  - `fileData: Data?` mit `@Attribute(.externalStorage)` (CloudKit-Asset-ähnlich)
  - `localPath: String?` (lokaler Cache filename)

### Details (Schema + Werte)
Pfad: `BrainMesh/Models/DetailsModels.swift`
- `MetaDetailFieldDefinition` (Schema pro Entity):
  - `entityID: UUID` (Scalar)
  - `name`, `nameFolded`
  - `typeRaw: Int` (`DetailFieldType`)
  - `sortIndex: Int`, `isPinned: Bool`, `unit: String?`, `optionsJSON: String?`
  - `owner: MetaEntity?` (`@Relationship(deleteRule: .nullify, originalName: "entity")`)
- `MetaDetailFieldValue` (Werte pro Attribute):
  - `attributeID: UUID` (Scalar), `fieldID: UUID`
  - typed storage: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
  - `attribute: MetaAttribute?`


## Sync/Storage

### Storage Engine
- SwiftData mit CloudKit:
  - `BrainMesh/BrainMeshApp.swift` verwendet `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - Kommentar im Code deutet Ziel „Private DB“ an. Die genaue DB-Wahl hinter `.automatic` ist SwiftData-intern → **UNKNOWN** (aber i.d.R. private).

### Runtime Visibility (UI)
- `BrainMesh/Settings/SyncRuntime.swift`
  - `storageMode`: `.cloudKit` oder `.localOnly`
  - iCloud Account Status via `CKContainer.accountStatus()`
  - Container Identifier ist hardcoded und muss mit Entitlements übereinstimmen.

### Offline/Fehlerfälle
- Release-Fallback auf local-only Storage wenn CloudKit Container init fehlschlägt:
  - Vorteil: App startet auch bei Signing/Entitlement-Problemen.
  - Risiko: User merkt ggf. spät, dass **kein Sync** läuft (daher `SyncRuntime` UI).
- Hintergrund Remote Notifications aktiviert (`UIBackgroundModes`), was typisch für CK-Subscriptions ist.
  - Ob Subscriptions aktiv konfiguriert werden: **UNKNOWN** (kein entsprechender Code gefunden).

### Cache Layers
- Main Photos (Entity/Attribute):
  - `BrainMesh/ImageStore.swift` (Memory NSCache + Disk in Application Support / `BrainMeshImages`)
  - `BrainMesh/ImageHydrator.swift` (SwiftData fetch + cache write; off-main konfiguriert via `AppLoadersConfigurator`)
- Attachments:
  - `BrainMesh/Attachments/AttachmentStore.swift` (Disk cache in Application Support / `BrainMeshAttachments`)
  - `BrainMesh/Attachments/AttachmentHydrator.swift` (progressive hydration, throttled, deduped, off-main)
  - `MetaAttachment.fileData` ist `@Attribute(.externalStorage)` → vermeidet Record-Size Druck, aber:
    - Query-Predicates müssen store-translatable bleiben, sonst droht In-Memory Filtering (katastrophal bei Blobs).
    - Siehe `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (konkrete Abwehr gegen OR-Predicate-Fallen).

### Migration Strategy
- Es gibt keine explizite Schema-Versionierung im Repo (kein „ModelVersion“ o.ä.) → **UNKNOWN**
- Migrationen im Code:
  - Graph-Scope Migration für alte Records: `BrainMesh/GraphBootstrap.swift`
  - Attachment GraphID Migration (vermeidet OR-Predicates): `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`


## Entry Points & Navigation

### App Entry
- `BrainMesh/BrainMeshApp.swift`
  - Initialisiert `ModelContainer` mit `ModelConfiguration(..., cloudKitDatabase: .automatic)`
  - DEBUG: `fatalError` wenn CloudKit-Container nicht erstellt werden kann.
  - Release: Fallback auf local-only `ModelConfiguration(schema:)` (kein Sync).
  - `SyncRuntime.shared.refreshAccountStatus()` wird einmalig per `Task.detached` angestoßen.
  - `AppLoadersConfigurator.configureAllLoaders(with:)` konfiguriert Loader/Hydrators off-main.

### Root View
- `BrainMesh/AppRootView.swift`
  - Root ist `ContentView()` mit globalem `.tint(...)` + `.preferredColorScheme(...)`.
  - ScenePhase Handling: Auto-Lock wird beim echten Backgrounding mit Debounce + „System Modal Grace“ ausgelöst.
  - `OnboardingSheetView` per `.sheet(...)`.
  - `GraphUnlockView` per `.fullScreenCover(item: $graphLock.activeRequest)`.

### Tabs
- `BrainMesh/ContentView.swift`
  - Tab 1: `EntitiesHomeView()`
  - Tab 2: `GraphCanvasScreen()`
  - Tab 3: `GraphStatsView()`
  - Tab 4: `SettingsView(showDoneButton: false)` in eigenem `NavigationStack`.

### Active Graph
- Persistenz über `@AppStorage(BMAppStorageKeys.activeGraphID)` (String UUID)
  - `BrainMesh/Support/BMAppStorageKeys.swift`
  - `BrainMesh/GraphSession.swift` hält ein @Published Spiegelbild (MainActor) auf UserDefaults-Änderungen.

### On Launch Bootstrapping / Migration
- `BrainMesh/GraphBootstrap.swift`
  - `ensureAtLeastOneGraph(...)` erzeugt Default-Graph falls none.
  - `migrateLegacyRecordsIfNeeded(...)` setzt `graphID` für alte Entities/Attributes/Links, wenn `graphID == nil`.


## UI Map (Hauptscreens + wichtige Flows)

### Tab: Entitäten
- Entry: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - Search + Sort, Grid/List Layout
  - Add Entity Sheet: `BrainMesh/Mainscreen/AddEntityView.swift`
  - Graph Picker: `BrainMesh/GraphPickerSheet.swift` + `BrainMesh/GraphPicker/*`
  - View Options Sheet: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeViewOptionsSheet.swift`
- Entity Detail:
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` (+ Extensions)
  - Attribute Sections: `BrainMesh/Mainscreen/EntityDetail/EntityAttributes/*`
  - Detail Schema Builder/Editor: `BrainMesh/Mainscreen/Details/*` (z.B. `NodeDetailsValuesCard.swift`, `DetailsSchema/*`)
- Attribute Detail:
  - `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift` (+ Extensions)
- Links:
  - Add Single Link: `BrainMesh/Mainscreen/AddLinkView.swift` / `NodeAddLinkSheet.swift`
  - Bulk Linking: `BrainMesh/Mainscreen/BulkLinkView.swift` (+ `BulkLinkLoader.swift` / `BulkLinkSnapshot.swift`)
  - Connections „Alle“: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/*`

### Tab: Graph
- Screen Orchestrator: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ Extensions)
- Canvas Rendering + Interaction:
  - `BrainMesh/GraphCanvas/GraphCanvasView/*`
  - Physics: `GraphCanvasView+Physics.swift`
  - Rendering Cache: `GraphCanvasView+Rendering.swift`
- Data loading off-main:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`

### Tab: Stats
- UI: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
- Loader (off-main): `BrainMesh/Stats/GraphStatsLoader.swift`
- Services: `BrainMesh/Stats/GraphStatsService/*`
- UI components: `BrainMesh/Stats/StatsComponents/*`

### Tab: Einstellungen
- Hub: `BrainMesh/Settings/SettingsView.swift`
- Sections:
  - Appearance: `SettingsView+AppearanceSection.swift`, `Settings/Appearance/*`
  - Display: `Settings/Display/*`
  - Import: `ImportSettingsView.swift`, `SettingsView+ImportSection.swift`
  - Sync & Wartung: `SettingsView+SyncSection.swift`, `SyncMaintenanceView.swift`
  - Hilfe/Info/Über: `HelpSupportView.swift`, `SettingsAboutSection.swift`

### Onboarding
- Coordinator: `BrainMesh/Onboarding/OnboardingCoordinator.swift`
- Sheet: `BrainMesh/Onboarding/OnboardingSheetView.swift`
- Progress: `BrainMesh/Onboarding/OnboardingProgress.swift`
- Auto-Presentation Gate: `BrainMesh/AppRootView.swift`

## Build & Configuration

### Xcode Targets
- `BrainMesh` (App)
- `BrainMeshTests`
- `BrainMeshUITests`  
Quelle: `BrainMesh/BrainMesh.xcodeproj/project.pbxproj`

### Deployment Target
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`  
Quelle: `BrainMesh/BrainMesh.xcodeproj/project.pbxproj`

### Info.plist
Pfad: `BrainMesh/Info.plist`
- `UIBackgroundModes`: `remote-notification` (Push/CK-Notifications)
- `NSFaceIDUsageDescription` (Graph-Lock / Unlock)

### Entitlements
Pfad: `BrainMesh/BrainMesh.entitlements`
- iCloud Container: `iCloud.de.marcfechner.BrainMesh`
- iCloud Service: `CloudKit`
- Push environment: `aps-environment = development`

### Swift Package Manager / Drittlibs
- Im `.pbxproj` sind keine `XCRemoteSwiftPackageReference` Einträge vorhanden.  
  => **Keine** SPM-Dependencies im Projektstand (Stand: dieses ZIP).  
  (Falls du lokal SPM-Packages hast, sind sie hier nicht eingecheckt → **UNKNOWN**)

### Secrets-Handling
- Keine `.xcconfig` Dateien im Repo gefunden.  
  => Secrets/Keys Handling: **UNKNOWN** (ggf. nicht vorhanden / nicht eingecheckt)


## Conventions (Do/Don't)

### File Struktur / Naming
- Große Views werden per Extensions/Teilviews aufgesplittet:
  - Pattern: `FooView+Section.swift` / `Foo+Feature.swift`  
    Beispiele:  
    - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift`  
    - `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView+*.swift`  
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+*.swift`
- „Loader“ Pattern:
  - `actor <Feature>Loader` + `configure(container:)` + `loadSnapshot(...) -> DTO`
  - DTOs sind value-only, häufig `@unchecked Sendable` (bewusst minimal, aber Tradeoff).
  - Beispiele:  
    - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`  
    - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`  
    - `BrainMesh/Stats/GraphStatsLoader.swift`

### Concurrency
- **Don't:** SwiftData `@Model` Instanzen über Actor/Task-Grenzen geben.
  - Stattdessen: IDs + Snapshot-DTOs (siehe `EntitiesHomeRow`, `GraphCanvasSnapshot`, `GraphStatsSnapshot`).
- **Do:** `Task` Cancellation respektieren in Loaders (z.B. BFS in GraphCanvasDataLoader prüft `Task.isCancelled`).
- **Do:** Throttling & Dedupe bei teuren Hydrations (siehe `AttachmentHydrator`, `ImageStore` inFlight).
- **Don't:** Schweres Disk-I/O synchron im SwiftUI `body` (wird in `ImageStore.swift` explizit gewarnt).

### SwiftData/Predicates
- **Do:** Predicates so formulieren, dass sie store-translatable bleiben (kein OR über `graphID == nil` wenn Blobs beteiligt sind).
  - Siehe Kommentar + Migration in `AttachmentGraphIDMigration.swift`.
- **Do:** `fetchLimit` für „Existence checks“/Guards (z.B. `GraphBootstrap.hasLegacyRecords(...)`).

### Denormalisierung
- `MetaLink` hält `sourceLabel` / `targetLabel` denormalisiert.
  - **Do:** Beim Rename die Link-Labels aktualisieren (siehe `NodeRenameService` in `BrainMesh/Mainscreen/LinkCleanup.swift`).


## How to work on this project (Setup + Einstieg)

### Setup (neuer Dev)
1) Xcode öffnen: `BrainMesh/BrainMesh.xcodeproj`
2) Team/Signing konfigurieren (App Target `BrainMesh`)
3) iCloud Capability aktivieren:
   - iCloud Container muss existieren: `iCloud.de.marcfechner.BrainMesh` (siehe Entitlements)
4) Push Notifications aktivieren (wegen `aps-environment` + `remote-notification`)
5) Run auf iOS 26 Simulator/Device

### Wo anfangen
- App-Lifecycle / Root Navigation: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`
- Datenmodelle: `BrainMesh/Models/*` + `BrainMesh/Attachments/MetaAttachment.swift`
- Sync/Runtime Status: `BrainMesh/Settings/SyncRuntime.swift`
- Loader/Hydrator Übersicht: `BrainMesh/Support/AppLoadersConfigurator.swift`

### Feature hinzufügen (typischer Flow)
1) (Optional) neues SwiftData Model:
   - Datei in `BrainMesh/Models/` oder Feature-Ordner anlegen
   - `Schema([...])` in `BrainMesh/BrainMeshApp.swift` erweitern
   - Falls `graphID` relevant: Migration/Bootstrap-Strategie mitdenken (siehe `GraphBootstrap`, `AttachmentGraphIDMigration`)
2) UI:
   - View(s) im passenden Feature-Ordner anlegen
   - Navigation: per `NavigationStack` im Feature oder via Sheets/FullScreenCovers am Root
3) Performance:
   - Wenn SwiftData-Fetches nicht trivial sind: Loader Actor + Snapshot einführen
   - Loader im `AppLoadersConfigurator.configureAllLoaders(with:)` registrieren
4) Caching/Hydration (wenn Bilder/Blobs):
   - Disk-Caches über `ImageStore` / `AttachmentStore`
   - Hydrator patterns beachten (throttle, dedupe, off-main)


## Quick Wins (max. 10)

1) **GraphCanvas Physics Guardrails:** harte Obergrenze für simulierende Nodes bei hoher Node-Zahl (z.B. Spotlight/Relevant-Set erzwingen).  
   Hotspot: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift` (O(n²) Pair-Loop).

2) **GraphCanvas Simulation Scheduler:** `Timer` → `CADisplayLink` oder frame-synced tick; Sleep aggressiver, wenn `maxSimSpeed` klein ist.  
   Hotspot: `GraphCanvasView+Physics.swift`.

3) **GraphCanvasDataLoader Adjacency Cache pro Graph:** einmalige Link-Fetch + adjacency-map statt hop-weiser Link-Fetches (reduziert Fetches bei hops>1).  
   Hotspot: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`.

4) **EntitiesHome counts cache TTL tuning + invalidation hooks** nach Create/Delete (statt nur TTL).  
   File: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`.

5) **AttachmentHydrator metrics/logging erweitern** (cache hit rate, hydration time) um regressions sichtbar zu machen.  
   File: `BrainMesh/Attachments/AttachmentHydrator.swift`, `BrainMesh/Observability/BMObservability.swift`.

6) **Link label denormalization: batch updates** (entity/attribute rename) mit fetchLimit/Chunking bei sehr vielen Links.  
   File: `BrainMesh/Mainscreen/LinkCleanup.swift` (`NodeRenameService`).

7) **Settings Hub UI tests**: simple UITest smoke (open each tile and back) um regressions in NavigationStack zu vermeiden.  
   Files: `BrainMesh/Settings/SettingsView.swift` + `SettingsView+*.swift`.

8) **Disk cache cleanup**: Hintergrund-Aufräumer für orphaned files (images/attachments) auf Basis vorhandener IDs.  
   Files: `BrainMesh/ImageStore.swift`, `BrainMesh/Attachments/AttachmentStore.swift`, plus neuer Maintenance Task.

9) **Avoid duplicated `.task` triggers** in heavy screens: ensure cancellation tokens exist (e.g. GraphCanvasScreen, Stats).  
   Files: `BrainMesh/GraphCanvas/GraphCanvasScreen/*`, `BrainMesh/Stats/GraphStatsView/*`.

10) **Standardize loader pattern** (configure/loadSnapshot/cancel) und dokumentieren; reduziert Bug-Fixes bei neuen Features.  
    Files: `BrainMesh/Support/AppLoadersConfigurator.swift` + Loader Actors.

