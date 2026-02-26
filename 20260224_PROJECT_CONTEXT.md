# PROJECT_CONTEXT.md

## TL;DR
BrainMesh ist eine SwiftUI‑iOS‑App (Deployment Target: iOS 26.0) für persönliche Wissensgraphen: **Graphen** enthalten **Entitäten** (Nodes), deren **Attribute** (Sub-Nodes), **Links** (Kanten) sowie **Details** (frei definierbare Felder + Werte) und **Anhänge** (Dateien/Video/Galerie‑Bilder). Persistenz läuft über **SwiftData** mit **CloudKit Private DB** (Fallback auf lokal-only nur in Release). Einstieg: `BrainMesh/BrainMesh/BrainMeshApp.swift` → `AppRootView` → `ContentView` (Tabs).

---

## Key Concepts / Domänenbegriffe
- **Graph (Workspace)**: Datenscope/Arbeitsbereich. Modell: `MetaGraph` (`BrainMesh/BrainMesh/Models/MetaGraph.swift`).
- **Active Graph**: aktuell ausgewählter Graph per `@AppStorage(BMAppStorageKeys.activeGraphID)` (z.B. `BrainMesh/BrainMesh/AppRootView.swift`, `.../GraphCanvas/GraphCanvasScreen.swift`, `.../Mainscreen/EntitiesHome/EntitiesHomeView.swift`).
- **Graph Scope (`graphID`)**: fast alle Records tragen `graphID: UUID?` zur Multi‑Graph‑Trennung + sanfter Migration (z.B. `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, Details‑Modelle).
- **Entität**: Primärer Node. Modell: `MetaEntity` (`BrainMesh/BrainMesh/Models/MetaEntity.swift`).
- **Attribut**: Sub‑Node einer Entität (Relationship via `owner`). Modell: `MetaAttribute` (`BrainMesh/BrainMesh/Models/MetaAttribute.swift`).
- **Link**: Kante zwischen Nodes (Entity/Attribute) als reine Scalar‑Referenzen (kind+id) + Labels. Modell: `MetaLink` (`BrainMesh/BrainMesh/Models/MetaLink.swift`).
- **Details**:
  - **Field Definition (Schema)** pro Entität: `MetaDetailFieldDefinition` (`BrainMesh/BrainMesh/Models/DetailsModels.swift`).
  - **Field Value** pro Attribut: `MetaDetailFieldValue` (`BrainMesh/BrainMesh/Models/DetailsModels.swift`).
  - **Pinned Fields**: bis zu 3 Felder als Chips/Sortierung in Listen (z.B. `.../Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift`).
- **Attachments**: Dateien/Video/Galerie‑Bilder; owner wird als `(ownerKindRaw, ownerID)` gespeichert, `fileData` ist `.externalStorage` (siehe `BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`).
- **Hydration**: Background‑Pipelines schreiben lokale Caches (Image/Attachment) und aktualisieren `imagePath`/`localPath` (z.B. `BrainMesh/BrainMesh/ImageHydrator.swift`, `BrainMesh/BrainMesh/Attachments/AttachmentHydrator.swift`).
- **Loader/Snapshots**: UI bekommt value‑DTOs statt `@Model` über Concurrency‑Grenzen (Pattern in `.../Support/AppLoadersConfigurator.swift`).
- **Graph Lock**: optional Biometrie/Passwort pro Graph/Node; Koordination via `GraphLockCoordinator` (`BrainMesh/BrainMesh/Security/...`).

---

## Architecture Map
Textuelle Layer‑Map (von oben nach unten):

1) **UI (SwiftUI Screens & Components)**
   - Root Tabs: `BrainMesh/BrainMesh/ContentView.swift`
   - Root Coordinator: `BrainMesh/BrainMesh/AppRootView.swift`
   - Hauptbereiche: `BrainMesh/BrainMesh/Mainscreen/*`, `BrainMesh/BrainMesh/GraphCanvas/*`, `BrainMesh/BrainMesh/Stats/*`, `BrainMesh/BrainMesh/Settings/*`

2) **UI‑State / Stores (ObservableObject)**
   - Appearance: `BrainMesh/BrainMesh/Settings/Appearance/AppearanceStore.swift`
   - Display Settings: `BrainMesh/BrainMesh/Settings/Display/DisplaySettingsStore.swift`
   - Onboarding: `BrainMesh/BrainMesh/Onboarding/OnboardingCoordinator.swift` (**UNKNOWN**: nicht in Quick-Scan geöffnet, siehe „Open Questions“)
   - Graph Lock + System Modal State: `BrainMesh/BrainMesh/Security/GraphLockCoordinator.swift`, `BrainMesh/BrainMesh/Support/SystemModalCoordinator.swift` (**UNKNOWN**: Pfad/Implementierung prüfen)

3) **Background Loader / Service Layer (off-main, Snapshot-DTOs)**
   - Zentraler Setup: `BrainMesh/BrainMesh/Support/AppLoadersConfigurator.swift`
   - Beispiele:
     - `GraphCanvasDataLoader` (`BrainMesh/BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`)
     - `GraphStatsLoader` + `GraphStatsService` (`BrainMesh/BrainMesh/Stats/*`)
     - `EntitiesHomeLoader` (`BrainMesh/BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`)
     - `NodePickerLoader`, `NodeConnectionsLoader`, `NodeRenameService` (siehe `AppLoadersConfigurator`)

4) **Persistence / Sync (SwiftData + CloudKit)**
   - Container + Schema + CloudKit Config: `BrainMesh/BrainMesh/BrainMeshApp.swift`
   - Sync‑Status UI: `BrainMesh/BrainMesh/Settings/SyncRuntime.swift`
   - Graph‑ID‑Migration: `BrainMesh/BrainMesh/GraphBootstrap.swift`, `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`

5) **Domain Models (@Model)**
   - `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink` (Ordner `BrainMesh/BrainMesh/Models/*`)
   - `MetaAttachment` (Ordner `BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`)
   - Details Schema/Werte (Ordner `BrainMesh/BrainMesh/Models/DetailsModels.swift`)

Abhängigkeitsrichtung (vereinfachte Regel):
UI → Stores/Loader → SwiftData/ModelContext → @Model

---

## Folder Map
- `BrainMesh/BrainMesh/Models/`  
  SwiftData `@Model`‑Typen + Hilfsmodelle (Search folding, enums).
- `BrainMesh/BrainMesh/Mainscreen/`  
  „Entitäten“-Tab: Listen, Detail‑Screens, Shared Detail‑Bausteine.
- `BrainMesh/BrainMesh/GraphCanvas/`  
  Graph‑Tab: Canvas‑Screen, Rendering, Physik, Data Loader, Inspector.
- `BrainMesh/BrainMesh/Stats/`  
  Stats‑Tab: UI (`GraphStatsView`) + Loader/Service (`GraphStatsLoader`, `GraphStatsService*`).
- `BrainMesh/BrainMesh/Attachments/`  
  Attachment‑Model, Import‑Pipeline, Stores (Cache/Thumbnails), Hydrator, UI‑Komponenten.
- `BrainMesh/BrainMesh/Settings/`  
  Settings‑Hub + Unterbereiche (Appearance/Display, Sync/Maintenance, Import‑Prefs).
- `BrainMesh/BrainMesh/Security/`  
  Graph Lock / Unlock Flows (Biometrie/Passwort), Crypto‑Utilities.
- `BrainMesh/BrainMesh/Support/`  
  Querschnitt: Loader‑Konfiguration, Utilities (Limiter, Coordinator‑Helper etc.).
- `BrainMesh/BrainMesh/Onboarding/`  
  Onboarding‑Flow (Sheet, Mini‑Explainer, Coordinator).
- `BrainMesh/BrainMesh/PhotoGallery/`, `BrainMesh/BrainMesh/Images/`, `BrainMesh/BrainMesh/Icons/`  
  Medien-/Icon‑UI (Picker, Galerie, Präsentation).

---

## Data Model Map
### MetaGraph (`BrainMesh/BrainMesh/Models/MetaGraph.swift`)
- Felder: `id`, `createdAt`, `name`, `nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### MetaEntity (`BrainMesh/BrainMesh/Models/MetaEntity.swift`)
- Felder: `id`, `createdAt`, `graphID`, `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`
- Relationships:
  - `attributes: [MetaAttribute]?` (cascade, inverse `MetaAttribute.owner`)
  - `detailFields: [MetaDetailFieldDefinition]?` (cascade, inverse `MetaDetailFieldDefinition.owner`)
- Convenience: `attributesList` und `detailFieldsList` de‑dupen und sortieren.

### MetaAttribute (`BrainMesh/BrainMesh/Models/MetaAttribute.swift`)
- Felder: `id`, `graphID`, `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`
- Owner: `owner: MetaEntity?` (keine Relationship‑Macro auf dieser Seite, um Zirkularität zu vermeiden)
- Details:
  - `detailValues: [MetaDetailFieldValue]?` (cascade, inverse `MetaDetailFieldValue.attribute`)
- Search: `searchLabelFolded` als denormalisierter Search‑Index.

### MetaLink (`BrainMesh/BrainMesh/Models/MetaLink.swift`)
- Felder: `id`, `createdAt`, `note`, `graphID`
- Endpunkte (Scalar):
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`

### MetaAttachment (`BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`)
- Felder: `id`, `createdAt`, `graphID`
- Owner (Scalar): `ownerKindRaw`, `ownerID`
- Typ: `contentKindRaw` (`file`, `video`, `galleryImage`)
- Metadaten: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Daten: `fileData: Data?` mit `@Attribute(.externalStorage)`
- Local cache: `localPath: String?`

### MetaDetailFieldDefinition (`BrainMesh/BrainMesh/Models/DetailsModels.swift`)
- Felder: `id`, `graphID`, `entityID`, `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
- Relationship: `owner: MetaEntity?` (nullify; originalName „entity“)

### MetaDetailFieldValue (`BrainMesh/BrainMesh/Models/DetailsModels.swift`)
- Felder: `id`, `graphID`, `attributeID`, `fieldID`
- Typed values: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
- Relationship: `attribute: MetaAttribute?` (keine Macro‑Inverse auf dieser Seite)

---

## Sync / Storage
### SwiftData + CloudKit
- Container Setup: `BrainMesh/BrainMesh/BrainMeshApp.swift`
  - `Schema([...])` enthält: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`
  - CloudKit aktiviert via `ModelConfiguration(..., cloudKitDatabase: .automatic)`
  - **Debug**: CloudKit‑Init Fehler ⇒ `fatalError` (kein Fallback)  
    **Release**: Fallback auf lokale `ModelConfiguration(schema:)` + `SyncRuntime.storageMode = .localOnly`
- iCloud Container ID: `iCloud.de.marcfechner.BrainMesh` (`BrainMesh/BrainMesh/Settings/SyncRuntime.swift`)
- Account Status Probe: `SyncRuntime.refreshAccountStatus()` on launch (`BrainMesh/BrainMesh/BrainMeshApp.swift`)

### Graph Scope / Migration
- Default Graph sicherstellen + Legacy‑Migration (`graphID == nil` → defaultGraphID):
  - `BrainMesh/BrainMesh/GraphBootstrap.swift` (Entities/Attributes/Links)
- Attachments Graph‑ID Migration (wichtig wegen `.externalStorage`):
  - `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - Motivation laut Kommentar: OR‑Predicates zwingen sonst in-memory filtering.

### Local Caches / Offline
- Header‑Bilder (Entity/Attribute):
  - Disk: `Application Support/BrainMeshImages` (`BrainMesh/BrainMesh/ImageStore.swift`)
  - Hydration: `BrainMesh/BrainMesh/ImageHydrator.swift` (detached, throttled)
- Attachments:
  - Disk: `Application Support/BrainMeshAttachments` (`BrainMesh/BrainMesh/Attachments/AttachmentStore.swift`)
  - Thumbnails: `.../Attachments/AttachmentThumbnailStore.swift`
  - Hydration: `.../Attachments/AttachmentHydrator.swift`
- Offline‑Verhalten: SwiftData lokal + späterer Sync via CloudKit. Konfliktstrategie ist **UNKNOWN** (SwiftData/CloudKit default).

---

## UI Map (Screens, Navigation, Flows)
### Root
- `BrainMesh/BrainMesh/ContentView.swift`  
  `TabView` mit:
  1. **Entitäten**: `EntitiesHomeView`
  2. **Graph**: `GraphCanvasScreen`
  3. **Stats**: `GraphStatsView`
  4. **Einstellungen**: `NavigationStack { SettingsView(showDoneButton: false) }`

### AppRoot / Global Sheets
- `BrainMesh/BrainMesh/AppRootView.swift`
  - Startup Tasks: `bootstrapGraphing()`, `autoHydrateImagesIfDue()`, `enforceLockIfNeeded()`, `maybePresentOnboardingIfNeeded()`
  - Onboarding: `.sheet(isPresented: $onboarding.isPresented) { OnboardingSheetView() }`
  - Graph Lock: `.fullScreenCover(item: $graphLock.activeRequest) { GraphUnlockView(request: ...) }`
  - ScenePhase Handling: Debounced background lock, um iOS‑Picker/FaceID‑Flows nicht zu killen.

### Entitäten (Tab 1)
- `BrainMesh/BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - NavigationStack + Search + Toolbar
  - Sheets:
    - `AddEntityView()` (neu)
    - `EntitiesHomeDisplaySheet` (Darstellung)
    - `GraphPickerSheet` (Graph wechseln)
  - Data source: `EntitiesHomeLoader.shared.loadSnapshot(...)` (off-main)

- Entity Detail:
  - Route helper: `EntityDetailRouteView` (in `EntitiesHomeView.swift`)
  - Detail: `BrainMesh/BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` (**UNKNOWN**: Datei existiert, aber nicht in diesem Scan geöffnet)
  - Attribute „All List“ Snapshot Model:  
    `BrainMesh/BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift`

- Attribute Detail:
  - `BrainMesh/BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`

- Shared Detail Components:
  - `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/*` (Hero, Media Gallery, Connections, Markdown accessory, etc.)

### Graph Canvas (Tab 2)
- `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - NavigationStack + minimal Toolbar (Graph Picker + Inspector)
  - Sheets:
    - `GraphPickerSheet`
    - Focus Node Picker: `NodePickerView(kind: .entity) { ... }`
    - Inspector: `inspectorSheet`
    - Detail Sheets: `EntityDetailView(entity:)`, `AttributeDetailView(attribute:)` (über `selectedEntity/selectedAttribute`)
  - Daten: `GraphCanvasDataLoader.shared.loadSnapshot(...)` (off-main)
  - Rendering/Physik: `GraphCanvasView` + Splits (u.a. `GraphCanvasView+Rendering.swift`)

### Stats (Tab 3)
- UI: `BrainMesh/BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
- Loader/Service: `BrainMesh/BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/BrainMesh/Stats/GraphStatsService/*`

### Settings (Tab 4)
- Hub: `BrainMesh/BrainMesh/Settings/SettingsView.swift` + Section‑Splits (`SettingsView+*.swift`)
- Sync Status: `BrainMesh/BrainMesh/Settings/SyncRuntime.swift`
- Appearance: `BrainMesh/BrainMesh/Settings/Appearance/*`
- Display: `BrainMesh/BrainMesh/Settings/Display/*`
- Import: `BrainMesh/BrainMesh/Settings/ImportSettingsView.swift` + `ImageGalleryImportPreferences.swift`

---

## Build & Configuration
- Xcode Project: `BrainMesh/BrainMesh.xcodeproj`
- Deployment Target: `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (`BrainMesh/BrainMesh.xcodeproj/project.pbxproj`)
- Entitlements: `BrainMesh/BrainMesh/BrainMesh.entitlements`
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`
  - iCloud Service: `CloudKit`
  - `aps-environment` (development)
- Info.plist: `BrainMesh/BrainMesh/Info.plist`
  - `UIBackgroundModes: remote-notification`
  - `NSFaceIDUsageDescription` für Graph Lock
- Swift Packages: keine `packageProductDependencies` im App‑Target (Arrays sind leer im `project.pbxproj`).

Secrets Handling:
- Keine offensichtlichen API Keys / Secrets im Repo‑Root gefunden. Falls vorhanden: **UNKNOWN**.

---

## Conventions (Naming, Patterns, Do/Don’t)
### Do
- **Keine SwiftData `@Model` über Concurrency‑Grenzen** tragen.  
  Pattern: Background `ModelContext` → Snapshot DTO → UI commit (z.B. `GraphCanvasDataLoader`, `GraphStatsLoader`, `EntitiesHomeLoader`).
- Bei `.externalStorage` (Attachments) **OR‑Predicates vermeiden**, sonst droht in-memory filtering.  
  Siehe `BrainMesh/BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.
- Heavy Work **nicht im SwiftUI `body`**: lieber Caches + `@State`/`@StateObject` und Debounce.
- Predicates stabil halten: keine captured model properties in `#Predicate` (siehe Kommentar in `EntityAttributesAllListModel+Lookups.swift`).

### Don’t
- Kein synchrones Disk‑IO in `body` (`ImageStore.loadUIImage(path:)` warnt explizit; siehe `BrainMesh/BrainMesh/ImageStore.swift`).
- Keine unbounded background loops ohne Cancellation‑Checks (bei eigenen Tasks immer `Task.checkCancellation()` / `Task.isCancelled`).

---

## How to work on this project
### Setup Steps
- `BrainMesh.xcodeproj` öffnen.
- Signing: iCloud/CloudKit Capability aktiv + Container `iCloud.de.marcfechner.BrainMesh` muss passen (`BrainMesh/BrainMesh/BrainMesh.entitlements`).
- Bei Debug‑Builds: CloudKit‑Fehler crashen absichtlich (`BrainMesh/BrainMesh/BrainMeshApp.swift`).
- Für realistische Sync‑Tests:
  - iCloud auf Device aktiv + App installiert auf mindestens 2 Geräten (oder Simulator+Device).
  - Settings → Sync prüfen: `SyncRuntime` (iCloud Account Status + StorageMode).

### Wo anfangen für neue Devs?
- App‑Entry + Storage: `BrainMesh/BrainMesh/BrainMeshApp.swift`
- Root Navigation + Global Sheets: `BrainMesh/BrainMesh/AppRootView.swift`
- Models: `BrainMesh/BrainMesh/Models/*`, `BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`
- Heavy paths: `BrainMesh/BrainMesh/Support/AppLoadersConfigurator.swift` (zeigt, welche Loader existieren).

### Wie fügt man ein Feature hinzu (Workflow)
- [ ] Neues persistentes Konzept?
  - [ ] Neues `@Model` in `BrainMesh/BrainMesh/Models/` oder passendem Modul.
  - [ ] **Schema** in `BrainMesh/BrainMesh/BrainMeshApp.swift` ergänzen.
  - [ ] `graphID` Scoping + Migration bewerten.
- [ ] Heavy Fetch/Compute?
  - [ ] Loader‑Pattern (Actor + Snapshot DTO) statt `@Query` + ad-hoc compute.
  - [ ] In `BrainMesh/BrainMesh/Support/AppLoadersConfigurator.swift` konfigurieren.
- [ ] UI Flow integrieren
  - [ ] Tab/Screen wählen (siehe „UI Map“).
  - [ ] Navigation (Sheet/Stack) + Coordinator‑State (falls global).
- [ ] Tests/Checks
  - [ ] Multi‑Device Sync Smoke Test (falls Daten betroffen)
  - [ ] Performance Smoke (Graph Tab öffnen, Entities Home search tippen, Stats öffnen)

---

## Quick Wins (max. 10, konkret)
1) **ActiveGraph Single Source of Truth**: Doppelte „Active Graph“‑State (AppStorage vs `GraphSession.shared`) konsolidieren.  
   Files: `BrainMesh/BrainMesh/GraphSession.swift`, `BrainMesh/BrainMesh/AppRootView.swift`, `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasScreen.swift`, `BrainMesh/BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`.
2) **Pinned Values Lookup**: `fetchPinnedValuesLookup` macht pro pinned field ein Fetch. Prüfen, ob ein Single‑Fetch via `fieldIDs.contains(v.fieldID)` möglich ist (reduziert DB‑Hits).  
   File: `BrainMesh/BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel+Lookups.swift`. (**UNKNOWN**: SwiftData‑Predicate‑Support für `contains` auf `[UUID]` in diesem Kontext.)
3) **Stats Attachment Bytes**: `GraphStatsService+Counts` lädt Attachments, um `byteCount` zu summieren. Bei vielen Attachments: ggf. caching oder alternative Summierung.  
   File: `BrainMesh/BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`. (**UNKNOWN**: Aggregation/partial fetch in SwiftData hier.)
4) **OnboardingSheetView splitten** (Compile‑Time, Merge‑Konflikte): 504 Zeilen → Sections/Components.  
   File: `BrainMesh/BrainMesh/Onboarding/OnboardingSheetView.swift`.
5) **NodeImagesManageView splitten** (Picker‑Edgecases isolieren).  
   File: `BrainMesh/BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`.
6) **GraphCanvas Rendering Profiling**: `renderCanvas` iteriert pro Frame über Knoten/Kanten; Prüfen ob zusätzliche Budgets / Culling sinnvoll sind.  
   File: `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasView+Rendering.swift`.
7) **Details GraphID Migration**: prüfen ob `MetaDetailFieldDefinition/Value` Legacy‑Records ohne `graphID` existieren und eine Migration nötig ist.  
   File: `BrainMesh/BrainMesh/Models/DetailsModels.swift`. (**UNKNOWN**: Legacy‑Datenlage.)
8) **Picker-Sensitivity Pattern**: `AppRootView` blockt Foreground‑Work bei System‑Modal. Pattern ggf. auch in Medien‑Flows anwenden.  
   File: `BrainMesh/BrainMesh/AppRootView.swift`. (**UNKNOWN**: weitere betroffene Flows.)
9) **Logging Konvention**: `os.Logger` Kategorien standardisieren + optional Debug‑Toggle.  
   Files: `BrainMesh/BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`, `BrainMesh/BrainMesh/Stats/GraphStatsLoader.swift`, `BrainMesh/BrainMesh/Observability/BMObservability.swift`.
10) **Big File #1 (EntityAttributesAllListModel)**: weitere Splits (Sort, Row building, Cache struct) → weniger Risiko beim Weiterentwickeln.  
   File: `BrainMesh/BrainMesh/Mainscreen/EntityDetail/EntityAttributes/EntityAttributesAllListModel.swift`.

---

## Open Questions (UNKNOWN)
- Wo liegt `OnboardingCoordinator.swift` und wie sieht dessen Persistenz/State‑Machine genau aus? (In `BrainMeshApp.swift` als `@StateObject` genutzt.)
- Gibt es einen zentralen DI/Service‑Locator neben `AppLoadersConfigurator`? (Viele `.shared` Singletons.)
- Nutzt ihr bewusst `UIBackgroundModes: remote-notification` nur für SwiftData/CloudKit, oder existiert eigene Push‑Handling‑Logik? (Im Scan keine `didReceiveRemoteNotification` / UNUserNotificationCenter‑Nutzung gefunden.)
- Welche Konflikt-/Merge‑Strategie ist für Multi‑Device Sync gewünscht (CloudKit default vs custom)?
- Gibt es Datenmigrationen jenseits GraphID‑Migration (z.B. Details, Attachments local cache cleanup)?
