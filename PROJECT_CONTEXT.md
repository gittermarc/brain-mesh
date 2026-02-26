# BrainMesh — PROJECT_CONTEXT
_Generated: 2026-02-26_
## TL;DR
- **App:** BrainMesh — graph-basierter Wissens-/Notiz-Organizer.
- **Plattform:** iOS
- **Minimum:** iOS **26.0** (`BrainMesh.xcodeproj/project.pbxproj`: `IPHONEOS_DEPLOYMENT_TARGET = 26.0`).
- **Persistenz/Sync:** SwiftData + CloudKit private DB (`cloudKitDatabase: .automatic`) mit Release-Fallback auf local-only (`BrainMesh/BrainMeshApp.swift`).
## Key Concepts / Domänenbegriffe
- **Graph (MetaGraph):** Workspace/„Datenbank“ innerhalb der App. Aktiv via `@AppStorage(BMAppStorageKeys.activeGraphID)` (z.B. `BrainMesh/AppRootView.swift`).
- **NodeKind:** Node-Typen (Entity/Attribute) werden häufig als Enum + `id` geroutet (z.B. `BrainMesh/Mainscreen/NodeDetailShared/*`).
- **Entity (MetaEntity):** Knoten „Entität“ (Name, Notes, Icon, Cover/Images, Detail-Felder).
- **Attribute (MetaAttribute):** Knoten „Attribut“ (Name, Notes, Icon, Cover/Images, Detail-Werte). Kann Owner-Entity haben.
- **Link (MetaLink):** Kante zwischen Nodes (Source/Target, jeweils Kind + UUID).
- **Details Schema:** Frei definierbare Felder (`MetaDetailFieldDefinition`) + Werte (`MetaDetailFieldValue`) für Nodes.
- **Attachment:** Medien/Dateien (`MetaAttachment`) als File/Video/GalleryImage.
- **Search Folding:** `BMSearch.fold(...)` + `nameFolded` Felder zur robusten Suche.
- **Graph Lock:** Schutz von Graphen/Nodes via Biometrie und/oder Passwort (`BrainMesh/Security/*`).
- **Snapshot Loader:** Off-main Datenaufbereitung in value-only DTOs (keine `@Model` über Threads).
## Architecture Map
Layer/Module + Verantwortlichkeiten + Abhängigkeiten (Textform):

- **App (Composition Root)**
  - `BrainMesh/BrainMeshApp.swift`
    - Konfiguriert `Schema([...])` und `ModelContainer`.
    - Versucht CloudKit-Config (`ModelConfiguration(... cloudKitDatabase: .automatic)`).
    - Im Release-Fall: Fallback local-only bei CloudKit-Init-Fehler.
    - Startet `SyncRuntime.shared.refreshAccountStatus()` in `Task.detached`.
    - Konfiguriert loader/hydrator via `AppLoadersConfigurator` (**siehe Open Questions**, nicht vollständig inspiziert).
  - `BrainMesh/AppRootView.swift`
    - Startup Sequence (bootstrap graph, lock enforce, auto image hydration, onboarding).
    - ScenePhase Handling (Background lock Task, Throttling).
- **Domain Model (SwiftData)**
  - `BrainMesh/Models/MetaGraph.swift`
  - `BrainMesh/Models/MetaEntity.swift`
  - `BrainMesh/Models/MetaAttribute.swift`
  - `BrainMesh/Models/MetaLink.swift`
  - `BrainMesh/Models/DetailsModels.swift`
  - `BrainMesh/Attachments/MetaAttachment.swift`
  - Abhängig von: Foundation + SwiftData. Keine UI-Abhängigkeiten.
- **Data Access / Loading**
  - Off-main Snapshot Loader:
    - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
    - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
    - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
    - `BrainMesh/Security/GraphUnlock/GraphUnlockSnapshotLoader.swift`
  - Prinzip: Background `ModelContext` erzeugen, fetch/aggregate, value-only return, UI resolved IDs im main context.
- **UI (SwiftUI Screens)**
  - Root Tabs: `BrainMesh/ContentView.swift`
  - Home/Details: `BrainMesh/Mainscreen/*`
  - Graph Canvas: `BrainMesh/GraphCanvas/*`
  - Stats: `BrainMesh/Stats/*`
  - Settings: `BrainMesh/Settings/*`
  - Onboarding: `BrainMesh/Onboarding/*`
- **Media / Import**
  - Attachments: `BrainMesh/Attachments/AttachmentImportPipeline.swift`
  - Images: `BrainMesh/Images/ImageImportPipeline.swift`, `BrainMesh/ImageStore.swift`
  - Galleries: `BrainMesh/PhotoGallery/*`, `BrainMesh/Mainscreen/NodeDetailShared/*MediaGallery*`
- **Security**
  - Lock/Unlock: `BrainMesh/Security/GraphLock/*`, `BrainMesh/Security/GraphUnlock/*`.
  - Coordinator: `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`.
- **Observability**
  - `BrainMesh/Observability/BMObservability.swift` (`os.Logger` + mini timing).
## Folder Map
- `BrainMesh/Attachments/` — Attachment-Model + Import/Handling (Files/Videos/Gallery Images).
- `BrainMesh/GraphCanvas/` — Canvas-Visualisierung, Gestures, Physics, Loader/Snapshots, MiniMap.
- `BrainMesh/GraphPicker/` — UI zum Wechseln/Anlegen von Graph-Workspaces.
- `BrainMesh/Icons/` — SF Symbols Picker & Icon UI.
- `BrainMesh/Images/` — Image Store/Import/Hydration-Utilities.
- `BrainMesh/ImportProgress/` — UI/State für Import-Fortschritt (Media, Files).
- `BrainMesh/Mainscreen/` — Home/Entity/Attribute Detail, Bulk Linking, Shared Detail Components.
- `BrainMesh/Models/` — SwiftData @Model Entities + Details Schema/Values.
- `BrainMesh/Observability/` — Logger + Timing Helpers.
- `BrainMesh/Onboarding/` — Onboarding Coordinator + Views/Hints.
- `BrainMesh/PhotoGallery/` — Gallery UI/Browser/Actions.
- `BrainMesh/Security/` — Graph/Node Locking (Biometrics/Passcode) + Unlock UI.
- `BrainMesh/Settings/` — Settings Screens + Sync/Diagnostics + Appearance/Display Settings.
- `BrainMesh/Stats/` — Stats Screen(s), Aggregations/Charts.
- `BrainMesh/Support/` — Kleine Utilities/Hilfsviews.

## Data Model Map
### Overview
- Schema wird in `BrainMesh/BrainMeshApp.swift` registriert:
  - `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`.

### MetaGraph (Workspace)
- Datei: `BrainMesh/Models/MetaGraph.swift`
- Felder (Auszug):
  - Identität/Meta: `id: UUID`, `createdAt: Date`, `name: String`, `nameFolded: String`
  - Lock: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64?`, `passwordHashB64?`, `passwordIterations`, `isPasswordConfigured`, `isProtected`

### MetaEntity (Node: Entity)
- Datei: `BrainMesh/Models/MetaEntity.swift`
- Felder:
  - Scope: `graphID: UUID?` (optional; Kommentare: „für Migration“)
  - Meta: `id`, `createdAt`
  - Content: `name`, `nameFolded`, `notes`
  - Icon/Cover: `iconSymbolName?`, `imageData?`, `imagePath?`
  - Lock: wie `MetaGraph`
- Beziehungen:
  - `attributes: [MetaAttribute]?` (Owner-Beziehung)
  - `detailFields: [MetaDetailFieldDefinition]?` (Schema pro Entity)

### MetaAttribute (Node: Attribute)
- Datei: `BrainMesh/Models/MetaAttribute.swift`
- Felder ähnlich Entity + zusätzlich:
  - `owner: MetaEntity?`
  - `detailValues: [MetaDetailFieldValue]?`
  - `searchLabelFolded: String` (kombinierter Suchstring; wird bei name/notes/owner recomputed)

### MetaLink (Edge)
- Datei: `BrainMesh/Models/MetaLink.swift`
- Felder:
  - `graphID: UUID?`
  - Source: `sourceKindRaw`, `sourceID`, `sourceLabel`
  - Target: `targetKindRaw`, `targetID`, `targetLabel`
  - `note?`, `createdAt`

### Details Schema / Values
- Datei: `BrainMesh/Models/DetailsModels.swift`
- `DetailFieldType`: `singleLineText`, `multiLineText`, `numberInt`, `numberDouble`, `date`, `toggle`, `singleChoice`.
- `MetaDetailFieldDefinition`:
  - Scope: `graphID?`, `entityID`
  - `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`
  - Optional: `unit?`, `optionsJSON?` (für `singleChoice`)
- `MetaDetailFieldValue`:
  - Scope: `graphID?`, `attributeID`, `fieldID`
  - Typed slots: `stringValue?`, `intValue?`, `doubleValue?`, `dateValue?`, `boolValue?`

### MetaAttachment
- Datei: `BrainMesh/Attachments/MetaAttachment.swift`
- Scope/Owner:
  - `graphID?`
  - `ownerKindRaw`, `ownerID` (Entity/Attribute)
- Content:
  - `contentKindRaw` (File/Video/GalleryImage)
  - `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`
  - `byteCount`, `fileData?`, `localPath?`

## Sync / Storage
### SwiftData + CloudKit
- Konfiguration: `BrainMesh/BrainMeshApp.swift`
  - CloudKit: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - Local: `ModelConfiguration(schema: schema)`
- Release-Fallback Verhalten:
  - Wenn CloudKit-Init fehlschlägt: Fallback local-only, `SyncRuntime.shared.setStorageMode(.localOnly)`.
  - DEBUG: Fallback ist **deaktiviert** (fatalError), damit Signing/Entitlements nicht still „kaputt gehen“.
- iCloud Diagnose:
  - `BrainMesh/Settings/SyncRuntime.swift` checkt `CKContainer.default().accountStatus()`.
  - UI: `BrainMesh/Settings/SettingsView+SyncSection.swift` (zeigt StorageMode + AccountStatus).
- Entitlements:
  - `BrainMesh/BrainMesh.entitlements` enthält iCloud container `iCloud.de.marcfechner.BrainMesh` + CloudKit.
- Background:
  - `BrainMesh/Info.plist`: `UIBackgroundModes` enthält `remote-notification`.
### Graph Bootstrap / Migration
- Startup: `BrainMesh/AppRootView.swift` ruft `bootstrapGraphing()`.
- `GraphBootstrap.ensureAtLeastOneGraph(using:)` erstellt Default-Graph, falls keiner existiert (`BrainMesh/GraphBootstrap.swift`).
- `GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID:using:)` schiebt Records ohne `graphID` in den Default-Graph.
- „Legacy Records Check“ nutzt `fetchLimit = 1` (cheap), siehe `GraphBootstrap.hasLegacyRecords(using:)`.
### Offline / Konflikte
- Offline-Verhalten: **UNKNOWN** (keine explizite UX/Conflict-Policy im Code gefunden; SwiftData/CloudKit übernimmt Standard-Verhalten).
- Konflikte/Resolution: **UNKNOWN** (kein explizites Merge UI/Policy gefunden).

## Entry Points + Navigation
### App Entry
- `@main` in `BrainMesh/BrainMeshApp.swift`.
- Shared Environment Objects (App-scoped):
  - `AppearanceStore`, `DisplaySettingsStore`
  - `OnboardingCoordinator`
  - `GraphLockCoordinator`
  - `SystemModalCoordinator` (**Datei nicht gefunden**, aber Objekt wird in `BrainMeshApp` instanziert) → **UNKNOWN**.
### Startup Sequence
- `BrainMesh/AppRootView.swift`:
  - `runStartupIfNeeded()`:
    1) `bootstrapGraphing()`
    2) `enforceLockIfNeeded()`
    3) `autoHydrateImagesIfDue()` (max 1x/24h; `ImageHydrator.shared.hydrateIncremental(runOncePerLaunch: true)`)
    4) `enforceLockIfNeeded()` (nochmal, nach hydration)
    5) `maybePresentOnboardingIfNeeded()`
### Root Tabs
- Datei: `BrainMesh/ContentView.swift`
  - Tab 1: **Entitäten** → `EntitiesHomeView()`
  - Tab 2: **Graph** → `GraphCanvasScreen()`
  - Tab 3: **Stats** → `GraphStatsView()`
  - Tab 4: **Einstellungen** → `NavigationStack { SettingsView(showDoneButton: false) }`
### Entities Home — wichtigste Flows
- Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
- Datenquellen:
  - `@Query` Graph-Liste: `@Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)]) var graphs`.
  - Row-Data: über `EntitiesHomeLoader` (value-only Snapshots) — siehe `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`.
- Sheets/Navigation (aus States ableitbar):
  - `showGraphPicker` → Graph Picker UI (siehe `BrainMesh/GraphPickerSheet.swift`).
  - `showAddEntity` → Add Entity Sheet (**konkreter View-Pfad**: **UNKNOWN**).
### Graph Canvas — wichtigste Flows
- Root: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (split in viele `GraphCanvasScreen+*.swift`).
- Loader: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` baut `GraphCanvasSnapshot` off-main.
- Rendering: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift` + `+DrawNodes/+DrawEdges/+Gestures/+Physics/+Camera`.
- MiniMap: `BrainMesh/GraphCanvas/MiniMapView.swift`.
### Node Details (Entity / Attribute)
- Entity Detail: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- Attribute Detail: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- Shared: `BrainMesh/Mainscreen/NodeDetailShared/*`
  - Media Gallery: `NodeDetailShared+MediaGallery.swift`
  - Connections Loader: `NodeConnectionsLoader.swift`
  - Destination Routing: `NodeDetailShared+Connections/NodeDetailShared+Connections.Destination.swift`
### Security Flows
- Coordinator: `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`
  - hält `activeRequest` und merkt sich `unlockedGraphIDs`.
  - `enforceActiveGraphLockIfNeeded(using:)` wird von `AppRootView` getriggert.
- Unlock UI:
  - `BrainMesh/Security/GraphUnlock/GraphUnlockView.swift` + hero/background/effects.
  - Snapshot: `GraphUnlockSnapshot.swift` + Loader `GraphUnlockSnapshotLoader.swift`.
- Password/Crypto:
  - `BrainMesh/Security/GraphLock/GraphLockCrypto.swift` (Hashing/Salt/Iterations).
  - `BrainMesh/Security/GraphSetPasswordView.swift`.
### Settings
- Root: `BrainMesh/Settings/SettingsView.swift`
- Sync Section: `BrainMesh/Settings/SettingsView+SyncSection.swift`
- Appearance: `BrainMesh/AppearanceStore.swift`
- Display settings: `BrainMesh/DisplaySettingsStore.swift`

## Große Views/Services (Wartbarkeit/Performance)
### Loader/Service Inventory (relevante Files)
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — Graph Snapshot build off-main.
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — Home list snapshot build off-main.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift` — Links/Connections snapshot.
- `BrainMesh/ImageStore.swift` — Image Cache/Load/Save (223 lines; potentiell RAM/IO hotspot).
- `BrainMesh/Attachments/AttachmentImportPipeline.swift` — Import orchestration.
- `BrainMesh/Images/ImageImportPipeline.swift` — Image picking/compression/persist.
- `BrainMesh/Observability/BMObservability.swift` — logging/timing.
### Known Hotspots (konkrete Gründe)
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.Destination.swift`
  - Grund: Fetch im `body` (render path) → potentiell wiederholte DB hits.
- `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - Grund: 30Hz Timer tick; `stepSimulation()` auf Main RunLoop → Jank/Battery bei großen Graphen.

## Build & Configuration
- Xcode: `BrainMesh/BrainMesh.xcodeproj`
- Deployment: iOS 26.0
- Capabilities:
  - iCloud/CloudKit via `BrainMesh/BrainMesh.entitlements`
  - APS environment: development (im Entitlement; Release/prod env **UNKNOWN**)
- Info.plist: `BrainMesh/Info.plist`
  - FaceID usage description vorhanden.
  - Background mode remote-notification.
- SPM: keine externen Packages gefunden.
- Secrets Handling: **UNKNOWN** (keine `.xcconfig`, keine Keychain wrapper sichtbar im Quick Scan).

## Conventions
- Dateisplitting: `Foo+Bar.swift` statt Monster-Datei.
- Value-only Snapshots für off-main; UI navigiert via IDs.
- `@MainActor` Coordinator pattern (z.B. `GraphLockCoordinator`).
- Logging mit `BMLog` Kategorien; Timing via `BMStopwatch`.

## How to work on this project
### Setup Steps
- Open `BrainMesh/BrainMesh.xcodeproj`.
- Prüfe Signing/Entitlements für iCloud Container.
- Start App → Settings → Sync: StorageMode & iCloud AccountStatus prüfen.
- Für GraphCanvas Performance Tests: großen Graph importieren/erstellen (falls vorhanden) und FPS/CPU beobachten.
### Typical workflow: neues Feature hinzufügen
1. Entscheide: gehört es in **Model**, **Loader**, **UI** oder **Pipeline**?
2. Wenn Datenzugriff nötig:
   - Implementiere Loader der ein value-only Snapshot erzeugt.
   - UI resolved `@Model` Instanzen im Main-Context nur für Detail-Views.
3. UI:
   - Neue Subviews als eigene Files, möglichst ohne heavy computations im `body`.
4. Observability:
   - Für teure Pfade `BMLog.load` + `BMStopwatch` adden.

## Quick Wins (max 10)
1. Eliminate fetch-in-body in NodeDestinationView (Destination Routing).
2. Budget GraphCanvas physics tick (adaptive tick rate / early-out / stop in background).
3. Harden Attachment pipeline cancellation + memory usage (avoid large Data retention).
4. Centralize graphID scoping (shared predicate helpers).
5. Throttle search reloads (debounce) in EntitiesHomeView.
6. Make ImageHydrator policy explicit (what gets hydrated, when, and why).
7. Add debug screen: show activeGraphID, nodes/edges counts, storageMode, accountStatus.
8. Guard unbounded Tasks in views with `.task(id:)` and cancellation on disappear.
9. Normalize “Folded Search” usage (ensure all searchable text updates folded variants).
10. Document local-only fallback UX (clear warning + remediation steps).

## Open Questions (UNKNOWN)
- `SystemModalCoordinator` existiert als `@StateObject` in `BrainMeshApp`, Datei nicht im ZIP gefunden → fehlt im Upload oder generiert?.
- Stats compute: snapshot caching / invalidation Strategie?
- Add Entity/Attribute Editor Views: Pfade/Dateien?
- Attachment limits/policies (CloudKit record size, local storage)?
- Export/Import/Sharing roadmap?

## Test Checklist (Smoke)

- **Cold Launch**

  - App startet ohne Crash.

  - In Settings → Sync: StorageMode wird sinnvoll angezeigt (CloudKit vs local-only).

- **Graph Bootstrap**

  - Bei frischer Installation wird mindestens ein Graph angelegt (`GraphBootstrap.ensureAtLeastOneGraph`).

  - `activeGraphID` wird gesetzt (AppStorage) und bleibt stabil nach Relaunch.

- **Graph Lock**

  - Protected Graph sperrt beim App-Start bzw. beim Background→Foreground (je nach Policy).

  - Biometrie Fail/Cancel zeigt sinnvolles Error Banner (`Security/GraphUnlock/*`).

- **Entities Home**

  - Graph wechseln: Liste update korrekt, keine UI Hänger.

  - Search tippen: keine spürbaren Lags (Loader off-main).

- **Entity/Attribute Detail**

  - Navigation via Connections: Destination löst korrekt auf (siehe NodeDestinationView).

  - Details-Felder hinzufügen/ändern, pinned fields erscheinen in Cards.

- **Graph Canvas**

  - Graph laden: Snapshot baut, UI reagiert.

  - Pinch/Pan/Select fühlt sich stabil an; Simulation stoppt wenn View weg ist.

- **Attachments / Gallery**

  - Image import: Thumbnail/Cover erscheint; App bleibt responsiv.

  - File/video import: ByteCount stimmt; lokale Pfade funktionieren nach Relaunch.


## Troubleshooting (typische Fehlerbilder)

- **„Sync wirkt kaputt“ / Daten fehlen auf 2. Gerät**

  - Prüfe Settings → Sync: StorageMode = local-only? Dann CloudKit init vermutlich fehlgeschlagen.

  - Prüfe iCloud accountStatus in derselben Sektion.

- **GraphCanvas ruckelt**

  - Verdacht: Physics tick auf Main (30Hz). Test: Simulation stoppen/idle mode.

- **Navigation zu Entity/Attribute zeigt „nicht gefunden“**

  - Prüfe ob `graphID` scoping/predicate korrekt ist (Legacy migration vs activeGraph).

- **Attachments verschwinden**

  - Prüfe ob `localPath` im Sandbox gültig ist und ob Dateien beim Cleanup entfernt werden (**UNKNOWN**, wo Cleanup stattfindet).

