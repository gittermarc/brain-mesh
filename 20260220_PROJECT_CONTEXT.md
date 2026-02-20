# BrainMesh — PROJECT_CONTEXT.md

## TL;DR
BrainMesh ist eine SwiftUI‑App (iOS/iPadOS **26.0+**) für Wissensmanagement als **Graph**: Du legst **Graphen** (Workspaces) an, darin **Entitäten**, **Attribute**, **Links** zwischen Nodes sowie **Anhänge** (Dateien/Videos/Gallery‑Bilder). Persistenz läuft über **SwiftData** mit **CloudKit‑Sync** (ModelConfiguration `cloudKitDatabase: .automatic`) und lokalen Caches für Medien.

**Entry Points:** `BrainMesh/BrainMesh/BrainMesh/BrainMeshApp.swift`, `BrainMesh/BrainMesh/BrainMesh/AppRootView.swift`, `BrainMesh/BrainMesh/BrainMesh/ContentView.swift`.

---

## Key Concepts / Domänenbegriffe
- **MetaGraph**: Workspace/“Datenbank” (inkl. optionaler Sperre). `BrainMesh/BrainMesh/BrainMesh/Models.swift`
- **MetaEntity**: Oberkategorie (z.B. “Bücher”, “Personen”). Hat Attribute. `Models.swift`
- **MetaAttribute**: Eintrag/Instanz innerhalb einer Entität (z.B. “Dune” unter “Bücher”). `Models.swift`
- **MetaLink**: Kante zwischen zwei Nodes (Entity/Attribute). Labels werden **denormalisiert** gespeichert. `Models.swift`
- **MetaAttachment**: Datei/Video/Gallery‑Bild, referenziert über `(ownerKindRaw, ownerID)` statt Relationship‑Macro. `BrainMesh/BrainMesh/BrainMesh/Attachments/MetaAttachment.swift`
- **Details (Schema + Werte)**: Pro Entität definierbare Felder (`MetaDetailFieldDefinition`), pro Attribut Werte (`MetaDetailFieldValue`). `Models.swift`, UI: `Mainscreen/Details/*`
- **Hydration / Caches**:
  - **ImageStore**: Memory+Disk Cache in *Application Support/BrainMeshImages*. `BrainMesh/BrainMesh/BrainMesh/ImageStore.swift`
  - **ImageHydrator**: erstellt lokale Cache‑JPEGs aus `imageData` (SwiftData) im Hintergrund. `ImageHydrator.swift`
  - **AttachmentStore / AttachmentHydrator**: analog für Anhänge in *Application Support/BrainMeshAttachments*. `Attachments/AttachmentStore.swift`, `Attachments/AttachmentHydrator.swift`
- **Loader‑Pattern**: Heavy SwiftData‑Fetches/Sort/Compute laufen off‑main in Actors, liefern **Snapshots** (value types) an Views. Beispiele:
  - `GraphCanvas/GraphCanvasDataLoader.swift`
  - `Mainscreen/EntitiesHomeLoader.swift`
  - `Stats/GraphStatsLoader.swift`
  - `Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - `Mainscreen/NodePicker/NodePickerLoader.swift`

---

## Architecture Map (Layer/Module + Verantwortlichkeiten + Abhängigkeiten)

**UI (SwiftUI Views)**
- Tabs & Root: `ContentView.swift`
- Hauptscreens: `Mainscreen/*`, `GraphCanvas/*`, `Stats/*`, `Settings/*`
- Detail‑Flows: `Mainscreen/EntityDetail/*`, `Mainscreen/AttributeDetail/*`, `Mainscreen/NodeDetailShared/*`

**State / Coordination (EnvironmentObjects + @AppStorage)**
- Appearance/Theming: `Settings/Appearance/AppearanceStore.swift`, `Settings/Appearance/AppearanceModels.swift`
- Onboarding: `Onboarding/OnboardingCoordinator.swift`, `Onboarding/*`
- Graph Lock + Security: `Security/GraphLockCoordinator.swift`, `Security/GraphSecuritySheet.swift`
- System Picker Guard: `Support/SystemModalCoordinator.swift`

**Domain / Services / Loaders (meist Actors)**
- Heavy Queries/Derived Data: `*Loader.swift` (siehe oben)
- Medien‑Pipelines: `Images/ImageImportPipeline.swift`, `Attachments/AttachmentImportPipeline.swift`, `Attachments/VideoCompression.swift`
- Caches/Hydrator: `ImageStore.swift`, `ImageHydrator.swift`, `Attachments/AttachmentStore.swift`, `Attachments/AttachmentHydrator.swift`, `Attachments/AttachmentThumbnailStore.swift`

**Persistence (SwiftData)**
- Models: `Models.swift`, `Attachments/MetaAttachment.swift`
- Container Setup: `BrainMeshApp.swift` (Schema + `ModelContainer`)
- Migration/Repair helpers: `GraphBootstrap.swift`, `Attachments/AttachmentGraphIDMigration.swift`

**Cross‑cutting**
- Logging/Timing: `Observability/BMObservability.swift`

Abhängigkeiten (Textform):
- Views → (Loader/Hydrator/Stores) → SwiftData (ModelContext/ModelContainer) → CloudKit (über SwiftData)
- Views → AppearanceStore / GraphLockCoordinator / OnboardingCoordinator / SystemModalCoordinator
- Loader/Hydrator → `AnyModelContainer` wrapper (Sendable) → Background `ModelContext`

---

## Folder Map (Ordner → Zweck)
- `Attachments/` — Datei/Video/Gallery‑Anhänge: Import, Preview (QuickLook), Hydration, Thumbnails, Cache.
- `GraphCanvas/` — Graph‑Ansicht: Rendering (Canvas), Physik‑Simulation, DataLoader, Inspector.
- `GraphPicker/` — UI‑SubViews/Flows für Graph‑Auswahl/Verwaltung (genutzt von `GraphPickerSheet.swift`).
- `Icons/` — SF‑Symbol Picker & Icon UI.
- `Images/` — Image‑Import/Compression (`ImageImportPipeline.swift`).
- `ImportProgress/` — UI/State für Import‑Progress Cards.
- `Mainscreen/` — Haupt‑UI: Entities Home, Entity/Attribute Detail, NodeDetailShared, Details‑Schema UI.
- `Observability/` — Logger/Timing helper.
- `Onboarding/` — Onboarding UI + Coordinator + Progress‑Berechnung.
- `PhotoGallery/` — Vollbild‑Foto/Gallery UI (plus `FullscreenPhotoView.swift`).
- `Security/` — Graph‑Lock (Biometrie/Passwort), Unlock UI.
- `Settings/` — Settings root + Sections, Sync Status, Maintenance, Video Import Prefs.
- `Stats/` — Graph‑Statistiken, Cards, Loader.
- `Support/` — SystemModalCoordinator (Picker‑Guard).

---

## Data Model Map (Entities, Relationships, wichtige Felder)

### `MetaGraph` (`Models.swift`)
- Felder: `id`, `createdAt`, `name`, `nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`, computed `isProtected`

### `MetaEntity` (`Models.swift`)
- Scope: `graphID: UUID?` (optional für Migration)
- Felder: `id`, `createdAt`, `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`
- Relationships:
  - `attributes` (cascade) inverse `MetaAttribute.owner`
  - `detailFields` (cascade) inverse `MetaDetailFieldDefinition.owner`
- Denormalisierung: `name.didSet` aktualisiert `nameFolded` und ruft `recomputeSearchLabelFolded()` auf allen `attributesList` auf.
- **Auffälligkeit:** `MetaEntity` enthält ebenfalls Graph‑Security‑Felder wie `MetaGraph`, aber es gibt **keine** Call‑Sites, die Entity‑Security nutzen (Suche zeigt nur Zugriff über `MetaGraph`). -> siehe `ARCHITECTURE_NOTES.md` (Risiko/Refactor). 

### `MetaAttribute` (`Models.swift`)
- Scope: `graphID: UUID?`
- Felder: `id`, `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`
- Owner: `owner: MetaEntity?` (keine Relationship‑Macro; bewusst zur Macro‑Stabilität)
- Details: Relationship `detailValues` (cascade) inverse `MetaDetailFieldValue.attribute`
- Denormalisierung: `searchLabelFolded` über `displayName` (“Entity · Attribute”)
- **Auffälligkeit:** `MetaAttribute` enthält ebenfalls Graph‑Security‑Felder wie `MetaGraph`, aber es gibt **keine** Call‑Sites, die Attribute‑Security nutzen.

### `MetaLink` (`Models.swift`)
- Scope: `graphID: UUID?`
- Source/Target: `sourceKindRaw`, `sourceID`, `sourceLabel` sowie `targetKindRaw`, `targetID`, `targetLabel`
- `createdAt`, optional `note`
- **Design:** Keine Relationships; Labels denormalisiert → Rename muss Labels nachziehen (`Mainscreen/LinkCleanup.swift` / `NodeRenameService`).

### Details: `MetaDetailFieldDefinition` + `MetaDetailFieldValue` (`Models.swift`)
- Definition:
  - Felder: `entityID` (scalar), `name/nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Relationship: `owner: MetaEntity?` (`originalName: "entity"`)
- Value:
  - Felder: `attributeID`, `fieldID`, typed storage: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
  - Owner: `attribute: MetaAttribute?` (keine Relationship‑Macro)

### `MetaAttachment` (`Attachments/MetaAttachment.swift`)
- Scope: `graphID: UUID?`
- Owner: `ownerKindRaw` + `ownerID` (keine Relationship‑Macros)
- Content: `contentKindRaw` (`file` / `video` / `galleryImage`)
- Bytes: `fileData` ist `@Attribute(.externalStorage)` (SwiftData extern, CloudKit “asset‑style”)
- Local cache: `localPath` (Application Support)

---

## Sync/Storage
### SwiftData + CloudKit
- Setup: `BrainMesh/BrainMesh/BrainMesh/BrainMeshApp.swift`
  - Schema: `[MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment, MetaDetailFieldDefinition, MetaDetailFieldValue]`
  - Config: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`
  - **DEBUG‑Verhalten:** CloudKit‑Container‑Failure → `fatalError` (kein Fallback).  
  - **RELEASE‑Verhalten:** Fallback auf local‑only `ModelConfiguration(schema: schema)`.

### Medien: synced vs. cache
- **Entity/Attribute Hauptbild**:
  - Synced: `imageData` (JPEG, bewusst klein gehalten)
  - Cache: `imagePath` + Diskfile in `Application Support/BrainMeshImages` (`ImageStore.swift`)
  - Import/Kompression: `Images/ImageImportPipeline.swift`
    - `prepareJPEGForCloudKit`: Ziel ~**280 KB**
    - `prepareJPEGForGallery`: Ziel ~**2.2 MB**
- **Attachments**:
  - Synced: `MetaAttachment.fileData` als `externalStorage`
  - Cache: `localPath` + Diskfile in `Application Support/BrainMeshAttachments` (`AttachmentStore.swift`)
  - Hydration: `Attachments/AttachmentHydrator.swift` (fetches `fileData` off‑main, throttled via `AsyncLimiter`)

### Offline‑Verhalten
- Lokale SwiftData‑Persistenz ist immer vorhanden; Sync passiert “best effort”, abhängig von iCloud/Netz.  
- Account‑Status wird in `Settings/SyncRuntime.swift` per `CKContainer.accountStatus()` aktualisiert.

---

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)

### Root/Startup
- `AppRootView.swift`
  - Bootstrapping: `GraphBootstrap.ensureAtLeastOneGraph()` + `migrateLegacyRecordsIfNeeded()`
  - Auto‑Hydration Images (max 1x/24h): `ImageHydrator.shared.hydrateIncremental(...)`
  - Security: `GraphLockCoordinator.enforceActiveGraphLockIfNeeded(...)`
  - Onboarding Auto‑Sheet (nur wenn noch keine Daten): `OnboardingProgress.compute(...)`
  - Picker‑Guard: debounced auto‑lock wenn `.background` und `SystemModalCoordinator.isSystemModalPresented`

### Tabs (`ContentView.swift`)
- **Entitäten** → `Mainscreen/EntitiesHomeView.swift`
  - Navigation zu `EntityDetailView` (Route‑View in derselben Datei)
  - Sheets: `AddEntityView` (`Mainscreen/AddEntityView.swift`), `GraphPickerSheet` (`GraphPickerSheet.swift`)
- **Graph** → `GraphCanvas/GraphCanvasScreen.swift`
  - `NavigationStack` + Canvas UI + Inspector/Settings
  - Sheets: Node‑Detail (Entity/Attribute), Picker etc. (siehe `.sheet`/`.fullScreenCover` in Datei)
- **Stats** → `Stats/GraphStatsView/GraphStatsView.swift`
  - Lädt Snapshot via `Stats/GraphStatsLoader.swift`
- **Einstellungen** → `Settings/SettingsView.swift` + `SettingsView+*.swift` Sections
  - Sync Status: `SettingsView+SyncSection.swift` + `Settings/SyncRuntime.swift`
  - Maintenance: Cache clear, Hydrator rebuild etc.

---

## Build & Configuration
- Xcode Projekt: `BrainMesh/BrainMesh/BrainMesh.xcodeproj`
- Deployment Target: **iOS 26.0** (`IPHONEOS_DEPLOYMENT_TARGET = 26.0` in `project.pbxproj`)
- Bundle ID: `de.marcfechner.BrainMesh` (Tests: `de.marcfechner.BrainMeshTests`, UI‑Tests: `de.marcfechner.BrainMeshUITests`)
- Entitlements: `BrainMesh/BrainMesh/BrainMesh/BrainMesh.entitlements`
  - `com.apple.developer.icloud-services = CloudKit`
  - Container: `iCloud.de.marcfechner.BrainMesh`
  - APS Environment: `development`
- Info.plist: `BrainMesh/BrainMesh/BrainMesh/Info.plist`
  - Background mode: `remote-notification`
  - FaceID usage: `NSFaceIDUsageDescription` (Graph Lock)
- SPM: **keine** `Package.resolved` / keine `XCRemoteSwiftPackageReference` im Projekt gefunden.
- Secrets‑Handling: **UNKNOWN** (keine `.xcconfig`/Secrets‑Datei im Repo gefunden; evtl. nicht nötig).

---

## Conventions (Naming, Patterns, Do/Don’t)
- **Graph Scope first:** Neue Records möglichst immer mit `graphID = activeGraphID` anlegen (Migration‑tolerant, aber Performance/Correctness hängt daran).
- **Suche:** immer über gefaltete Strings (`BMSearch.fold`) + gespeicherte `*Folded` Felder.
- **SwiftData in UI vermeiden:** keine teuren Fetches/Sorts im `body`; stattdessen Loader‑Snapshots (siehe `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`).
- **Keine Model‑Objects über Actor‑Grenzen schleppen:** Snapshots/value types nutzen; wenn nötig `AnyModelContainer` + Background‑`ModelContext`.
- **Disk I/O niemals im Renderpfad:** `ImageStore.loadUIImage(path:)` ist sync → nur async Varianten (`loadUIImageAsync`) in UI verwenden.
- **Denormalisierung bewusst:** Link‑Labels (`MetaLink.sourceLabel/targetLabel`) und Attribute‑SearchLabel müssen bei Rename konsistent gehalten werden (`NodeRenameService`).

---

## How to work on this project (Setup Steps + wo anfangen)
### Setup (neuer Dev)
1. `BrainMesh.xcodeproj` öffnen.
2. Signing Team wählen + iCloud Capability aktivieren (CloudKit Container `iCloud.de.marcfechner.BrainMesh`), sonst **DEBUG‑Build startet nicht** (`fatalError` in `BrainMeshApp.init()`).
3. Auf Device/Simulator mit iOS 26 starten.
4. In Settings → Sync prüfen: `Settings/SyncRuntime.swift` (Account‑Status).

### Wo anfangen
- Navigation/Startup verstehen: `BrainMeshApp.swift` → `AppRootView.swift` → `ContentView.swift`
- Model & Scope: `Models.swift`, `Attachments/MetaAttachment.swift`, `GraphBootstrap.swift`
- Performance‑kritisch: `GraphCanvas/*`, `Mainscreen/NodeDetailShared/*`, Loader/Hydrator Actors.

### Feature hinzufügen (typischer Ablauf)
- Neues Domain‑Konzept:
  - Neue `@Model` Klasse anlegen → **Schema‑Liste** in `BrainMeshApp.swift` erweitern.
  - `graphID` und ggf. `*Folded`/Denormalisierungen festlegen.
  - Migration/Bootstrap falls nötig (`GraphBootstrap.swift`).
- Neue UI:
  - Screen in passendem Ordner (z.B. `Mainscreen/...`) + Entry in Tab/Navigation.
  - Heavy Data/Derived: neuen `*Loader` Actor anlegen, in `BrainMeshApp.init()` konfigurieren (Container inject).
- Medien:
  - Import immer über Pipeline (`Images/ImageImportPipeline.swift`, `Attachments/AttachmentImportPipeline.swift`).

---

## Quick Wins (max 10, konkret)
1. **Outer `NavigationStack` in `ContentView.swift` prüfen**: Tabs nutzen bereits eigene `NavigationStack`s (z.B. `EntitiesHomeView.swift`, `GraphCanvasScreen.swift`, `GraphStatsView.swift`). Entfernen/vereinheitlichen reduziert „nested stack“ Komplexität.
2. **Dead Code entfernen oder nutzen:** `GraphSession.swift` hat keine Referenzen im Projekt (suche liefert nur die Datei selbst).
3. **Model‑Bloat audit:** Security‑Felder in `MetaEntity`/`MetaAttribute` sind aktuell ungenutzt (nur `MetaGraph` wird gelockt). Entfernen ist Migration‑Risiko; zumindest klar dokumentieren/isolieren.
4. **EntitiesHome counts**: `EntitiesHomeLoader.computeAttributeCounts`/`computeLinkCounts` fetcht komplette Tabellen pro Graph (`Mainscreen/EntitiesHomeLoader.swift`). Für große Graphen: denormalisierte Counts oder separate Cache‑Modelle.
5. **GraphCanvas Physik**: `GraphCanvasView+Physics.swift` läuft 30 FPS auf Main Thread mit O(n²) Pair‑Loop → bei großen Graphen „jank“ möglich. (Mindestens: harte Node‑Cap für Simulation oder spatial partitioning.)
6. **Unit Tests für Pipelines**: `Images/ImageImportPipeline.swift` (Byte‑Targets), `BMSearch.fold` (Locale/Diacritics) – schnelle Tests mit hohem ROI.
7. **Logging konsolidieren**: `BMLog` Kategorien nutzen (bereits in `BMObservability.swift`), Hotspots (Loader durations) mit `BMDuration` messen.
8. **Cache clear UX**: Settings Maintenance (z.B. `SettingsView+MaintenanceSection.swift`) um klare „wie viel Speicher“‑Anzeige erweitern (ImageStore/AttachmentStore haben `cacheSizeBytes()`).
9. **Schema‑Änderungen sichern**: Checkliste im Repo: “Neue @Model? → Schema in `BrainMeshApp.swift` + ggf. Migration”.
10. **Renderpfad audit**: sicherstellen, dass sync‑APIs wie `ImageStore.loadUIImage(path:)` nicht direkt im `body` landen (Kommentare existieren; review‑Checklist).

