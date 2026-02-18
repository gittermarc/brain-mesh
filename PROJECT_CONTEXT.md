# BrainMesh — PROJECT_CONTEXT

_Last scan: 2026-02-18 (Europe/Berlin)_

## TL;DR

BrainMesh ist eine iOS/iPadOS-App (iPhone+iPad) fuer ein persoenliches Knowledge-Graph-Notebook: Nutzer verwalten **Graphen** (Workspaces), darin **Entitaeten** und **Attribute** (Knoten) und **Links** (Kanten) sowie **Notizen**, **Bilder** und **Anhaenge**. Persistenz via **SwiftData**; Sync via **SwiftData + CloudKit (cloudKitDatabase: .automatic)**. Minimum Deployment Target: **iOS 26.0** (aus `BrainMesh.xcodeproj/project.pbxproj`, `IPHONEOS_DEPLOYMENT_TARGET`).

---

## Key Concepts / Domaenenbegriffe

- **Graph**: Workspace/Scope. Viele Screens sind "graph-sensitiv" ueber `graphID`.
  - Modell: `MetaGraph` in `BrainMesh/Models.swift`
  - Aktiver Graph: `@AppStorage("BMActiveGraphID")` (z.B. `BrainMesh/GraphSession.swift`, `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`)
- **Node**: Oberbegriff fuer **Entitaet** oder **Attribut** (enum `NodeKind`).
  - Viele Flows arbeiten mit `NodeRef` / `NodeRefKey` (z.B. `BrainMesh/Mainscreen/NodePickerView.swift`, `BrainMesh/Mainscreen/NodeMultiPickerView.swift`, `BrainMesh/Mainscreen/NodeDetailShared/NodeDestinationView.swift`)
- **Entitaet** (`MetaEntity`): "Hauptknoten" mit Name, Icon, Notizen, optional Header-Bild.
- **Attribut** (`MetaAttribute`): Knoten, der einer Entitaet "gehoert" (`owner`) und eigenen Inhalt/Notizen/Bilder haben kann.
- **Link** (`MetaLink`): gerichtete Verbindung zwischen Nodes (Quelle/Ziel, optional Note).
- **Attachment / Medium** (`MetaAttachment`): Dateien, Videos oder Gallery-Bilder, die an einen Owner (Entity/Attribute) haengen.
  - Inhaltstyp via `AttachmentContentKind` (z.B. `BrainMesh/Attachments/MetaAttachment.swift`)
- **Local Cache vs Sync Storage**
  - Sync Storage: `imageData`/`fileData` (SwiftData, `.externalStorage`) -> CloudKit syncbar.
  - Local Cache: Application Support Ordner (Images/Attachments) -> nur lokal; deterministische Filenamen.

---

## Architecture Map (Layer/Module + Verantwortlichkeiten + Abhaengigkeiten)

**UI (SwiftUI Views)**
- Feature-orientierte Views unter `BrainMesh/Mainscreen`, `BrainMesh/GraphCanvas`, `BrainMesh/Stats`, `BrainMesh/Settings`, `BrainMesh/Onboarding`, `BrainMesh/Security`, `BrainMesh/PhotoGallery`, `BrainMesh/Attachments`.
- Navigation primaer via `TabView` + `NavigationStack`.
- UI greift i.d.R. **nicht** direkt im Render-Pfad auf SwiftData zu; stattdessen:
  - Off-main Loader + Snapshot DTO (z.B. `EntitiesHomeLoader`, `NodePickerLoader`, `NodeConnectionsLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`).

**Domain / Data (SwiftData Models)**
- Zentrales Schema in `BrainMesh/Models.swift` und `BrainMesh/Attachments/MetaAttachment.swift`.
- Graph-Scoping ueber `graphID` Felder (optional) und Migration von Legacy (`graphID == nil`) via `BrainMesh/GraphBootstrap.swift` und `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.

**Services / Loaders (Concurrency)**
- Actor-basierte Loader, die `ModelContext` in `Task.detached` nutzen und DTOs zurueckgeben:
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
  - `BrainMesh/Mainscreen/NodePickerLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Attachments/MediaAllLoader.swift`
- Caches/Stores (local-only):
  - `BrainMesh/ImageStore.swift` (NSCache + Disk, In-flight Dedup)
  - `BrainMesh/Attachments/AttachmentStore.swift` (Disk cache)
  - `BrainMesh/Attachments/AttachmentThumbnailStore.swift` (Thumbnailing + Concurrency Limit)
  - `BrainMesh/Attachments/AttachmentVideoDurationStore.swift` (AVAsset duration cache)

**App-Shell / Coordination**
- App Entry: `BrainMesh/BrainMeshApp.swift` (`@main`)
  - baut `ModelContainer` (CloudKit .automatic mit Local-only Fallback)
  - konfiguriert Loader/Stores (`configure(container:)` auf shared actors)
- Root Orchestration: `BrainMesh/AppRootView.swift`
  - bootstrap (Default-Graph, Legacy-Migration, Hydration)
  - Auto-Lock/Unlock Triggering via `GraphLockCoordinator`
  - System-Modal Guard via `Support/SystemModalCoordinator.swift` (Photos/FaceID edge cases)
- Session: `BrainMesh/GraphSession.swift` (aktiver Graph als ObservableObject)

---

## Folder Map (Ordner -> Zweck)

- `BrainMesh/Appearance/` — Themes, DisplaySettings, Appearance-Store, UI-Preview (`AppearanceStore`, `DisplaySettingsView`)
- `BrainMesh/Attachments/` — Attachment Model, Import, Cache, Thumbnailing, All-Media Loader
- `BrainMesh/GraphCanvas/` — Graph Canvas Screen, View (Physics/Rendering), DataLoader, Inspector, Expand/Lens
- `BrainMesh/GraphPicker/` — Graph-Liste, Row UI, Rename/Delete/Dedupe Services
- `BrainMesh/Icons/` — Icon Picker + Search Index fuer SF Symbols
- `BrainMesh/Images/` — Gemeinsame Image-Import Pipeline (Decode + JPEG-Prep)
- `BrainMesh/ImportProgress/` — ImportProgressState + UI Card fuer Upload/Import Feedback
- `BrainMesh/Mainscreen/` — Entitaeten/Attribute Home, Detail-Screens, Pickers, Bulk-Linking
  - `Mainscreen/EntityDetail/`, `Mainscreen/AttributeDetail/`, `Mainscreen/NodeDetailShared/`
- `BrainMesh/Observability/` — Micro-Logging + Timing (`BMObservability.swift`)
- `BrainMesh/Onboarding/` — Onboarding Coordinator + UI (inkl. deprecated file `Onboarding/Untitled.swift`)
- `BrainMesh/PhotoGallery/` — Gallery/Viewer UI (browsing, sections)
- `BrainMesh/Security/` — Graph Lock Coordinator, Crypto, UI Sheets
- `BrainMesh/Settings/` — Settings Screens + About section
- `BrainMesh/Stats/` — Stats Loader + Service + View Components
- `BrainMesh/Support/` — kleine Koordinatoren/Helfer (z.B. SystemModalCoordinator)

---

## Data Model Map (Entities, Relationships, wichtige Felder)

### `MetaGraph` (`BrainMesh/Models.swift`)
- Keys: `id: UUID`, `name: String`, `createdAt: Date`
- Locking: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Derived: `isProtected` (true wenn Biometrics oder Passwort konfiguriert)

### `MetaEntity` (`BrainMesh/Models.swift`)
- Scoping: `graphID: UUID?`
- Search: `nameFolded` (wird bei `name` updates gesetzt)
- Visual: `iconSymbolName`, `imageData: Data?` (`.externalStorage`), `imagePath: String?` (deterministischer Cache-Key)
- Text: `notes: String`
- Relationships:
  - `attributesList: [MetaAttribute]` (`@Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner)`)

### `MetaAttribute` (`BrainMesh/Models.swift`)
- Owner: `owner: MetaEntity?` (inverse zu `attributesList`)
- Scoping: `graphID: UUID?` (Legacy-Migration orientiert sich am Owner)
- Search: `nameFolded`, `searchLabelFolded` (Owner+Name)
- Content: `contentKindRaw`, `textValue`, `isLink`, `sortOrder`, `highlightIsOn` + Highlight-Felder
- Visual: `iconSymbolName`, `imageData: Data?` (`.externalStorage`), `imagePath: String?`

### `MetaLink` (`BrainMesh/Models.swift`)
- Scoping: `graphID: UUID?`
- Direction: `sourceKindRaw/sourceID/sourceLabel`, `targetKindRaw/targetID/targetLabel`
- Optional Note: `note: String?`

### `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
- Scoping: `graphID: UUID?`
- Ownership: `ownerKindRaw`, `ownerID`
- Type: `contentKindRaw` (file/video/galleryImage)
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Payload: `fileData: Data?` (`.externalStorage`)
- Local Cache pointer: `localPath: String?`
- Derived helpers: `contentKind`, `isVideo`, `isGalleryImage`

---

## Sync/Storage

### SwiftData + CloudKit
- Container Setup: `BrainMesh/BrainMeshApp.swift`
  - `Schema([MetaGraph, MetaEntity, MetaAttribute, MetaLink, MetaAttachment])`
  - `ModelConfiguration(cloudKitDatabase: .automatic)`
  - Fallback: bei Container-Erstellung-Fehler -> lokal (`ModelConfiguration()`) und `cloudEnabled = false` (nur Release-Pfad)
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - iCloud container: `iCloud.de.marcfechner.BrainMesh`
  - CloudKit: `com.apple.developer.icloud-services = CloudKit`
  - Push: `aps-environment` gesetzt (Debug)

### External Storage Felder (CloudKit-Druck)
- `MetaEntity.imageData`, `MetaAttribute.imageData`, `MetaAttachment.fileData` sind `.externalStorage`.
  - Ziel: nicht jedes Listing triggert das Laden der Blob-Payload.
  - Pattern: Listen arbeiten mit DTOs ohne `fileData` (`BrainMesh/Attachments/MediaAllLoader.swift`).

### Local Caches (Application Support)
- Images: `BrainMesh/ImageStore.swift` -> `Application Support/BrainMeshImages`
  - Memory NSCache + Disk I/O off-main (`loadUIImageAsync`, `saveJPEGAsync`)
  - Deterministischer Name: `<stableID>.jpg` (z.B. `BrainMesh/NotesAndPhotoSection.swift`)
- Attachments: `BrainMesh/Attachments/AttachmentStore.swift` -> `Application Support/BrainMeshAttachments`
  - Lokaler File-Cache fuer Preview/Thumbnailing
  - `localPath` wird oft auf deterministische Namen normalisiert (`AttachmentStore.makeLocalFilename`)
- Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
  - Disk-Thumb Cache + Concurrency Limiter

### Migration / Hydration
- Legacy `graphID == nil` Migration:
  - Core Models: `BrainMesh/GraphBootstrap.swift` (Entities/Attributes/Links)
  - Attachments: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (owner-scoped)
- Hydration:
  - Attachments: `BrainMesh/Attachments/AttachmentHydrator.swift` (detached, disk cache, optional model save)
  - Images: `BrainMesh/ImageHydrator.swift` (laeuft auf MainActor, schreibt disk cache via `ImageStore.saveJPEGAsync`)

### Offline-Verhalten
- **KNOWN**: SwiftData speichert lokal; CloudKit synct "wenn moeglich".
- **UNKNOWN**: explizite Offline-UX (z.B. Sync-Status UI, Konflikt-Handling) ueber SwiftData hinaus.

---

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)

### Entry + Root Flow
- `BrainMesh/BrainMeshApp.swift` -> `AppRootView`
- `BrainMesh/AppRootView.swift`:
  - bootstrapped Default Graph + Migration + Hydration
  - zeigt `GraphUnlockView` als `.sheet` wenn `graphLock.activeRequest != nil`
  - auto-lock bei App Background (mit System-Modal Guard)

### Tab Navigation
- `BrainMesh/ContentView.swift`
  - `TabView`:
    1. **Entitaeten**: `EntitiesHomeView` (NavigationStack)
    2. **Graph**: `GraphCanvasScreen` (NavigationStack)
    3. **Stats**: `GraphStatsView` (NavigationStack)
  - Global Sheet: Settings (`SettingsView`) via Toolbar

### Entitaeten Tab
- Home: `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - Data: `EntitiesHomeLoader` Snapshot (off-main)
  - Flows:
    - Add Entity: `.sheet` -> `AddEntityView`
    - Graph Picker: `.sheet` -> `GraphPickerSheet`
    - Search: `searchText` / `scope` (Entity vs Attribute)

### Entity / Attribute Detail
- Entity: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- Attribute: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- Shared building blocks in `BrainMesh/Mainscreen/NodeDetailShared/`:
  - Header/Card UI, Notes&Photo, Highlights, Connections, Media Gallery, Attachments-Management Sheet, etc.
  - Connections "Alle": `NodeConnectionsAllView` laedt Snapshot via `NodeConnectionsLoader` (off-main)

### Graph Tab (Canvas)
- `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + Extensions
  - Graph Picker sheet, Focus Picker sheet, Inspector sheet
  - Entity/Attribute detail sheets (item-based)
  - Canvas View: `GraphCanvasView` mit Physics/Rendering Extensions
  - Data Loading off-main: `GraphCanvasDataLoader.loadSnapshot(...)`

### Stats Tab
- `BrainMesh/Stats/GraphStatsView/*` (modular)
  - Data Loading off-main: `GraphStatsLoader.loadSnapshot(...)`
  - Services: `BrainMesh/Stats/GraphStatsService/*` (count/media/structure/trends)

### Media / Attachments
- Inline Media/Gallery Section: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` + `BrainMesh/PhotoGallery/*`
- "Anhaenge verwalten" Sheet: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift`
  - Paging + Import + Preview (Datei/Video)
  - List DTOs via `MediaAllLoader`

### Security
- Graph Security UI: `BrainMesh/Security/GraphSecuritySheet.swift`
- Unlock UI: `BrainMesh/Security/GraphUnlockView.swift`
- Coordinator: `BrainMesh/Security/GraphLockCoordinator.swift`

---

## Build & Configuration

### Targets
- Xcode Project: `BrainMesh/BrainMesh.xcodeproj`
- Targets in `project.pbxproj`:
  - App: `BrainMesh`
  - Unit Tests: `BrainMeshTests`
  - UI Tests: `BrainMeshUITests`

### Minimum OS / Devices
- Deployment Target: iOS 26.0 (`IPHONEOS_DEPLOYMENT_TARGET`)
- Device Family: iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)

### Capabilities / Entitlements
- `BrainMesh/BrainMesh.entitlements`
  - iCloud + CloudKit container: `iCloud.de.marcfechner.BrainMesh`
  - Push notifications entitlement: `aps-environment` (Debug)
- `BrainMesh/Info.plist`
  - FaceID usage description (`NSFaceIDUsageDescription`)
  - Background mode: `remote-notification` (CloudKit push sync)

### Dependencies
- SPM: **UNKNOWN** (keine eindeutigen Swift Package References im `project.pbxproj` gefunden; falls lokal eingebunden: **UNKNOWN**)

### Secrets-Handling
- **UNKNOWN**: eigene Secrets (.xcconfig, build-time injection) nicht gefunden.

---

## Conventions (Naming, Patterns, Do/Don’t)

### Patterns, die im Projekt bereits konsequent sind
- **Off-main Fetch + Snapshot DTO**
  - UI ruft in einer `.task`-Closure `await loader.load...` und committed state in einem Rutsch.
  - DTOs sind `Sendable` oder value-only; SwiftData `@Model` wird nicht ueber Actor-Grenzen gereicht.
  - Beispiele: `EntitiesHomeLoader`, `NodePickerLoader`, `NodeConnectionsLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`.
- **Store-translatable Predicates**
  - Vermeide `OR` auf optionals (z.B. `(graphID == gid || graphID == nil)`), weil SwiftData sonst in-memory filtern kann.
  - Stattdessen: Legacy vorher migrieren (z.B. `AttachmentGraphIDMigration`).
- **Deterministische Cache Keys**
  - Bilder: `<stableID>.jpg` (`NotesAndPhotoSection.swift`)
  - Attachments: `<attachmentID>.<ext>` (`AttachmentStore.swift`)
- **No disk I/O in `body`**
  - `ImageStore.loadUIImageAsync` statt synchroner reads im Renderpfad.
  - Thumbnails via `AttachmentThumbnailStore`/`PhotoGallery`.

### Do / Don’t (konkret)
- DO: grosse Listen/Picker immer ueber Loader + DTO laden.
- DO: `.task(id:)` nutzen, damit alte Loads sauber gecancelt werden.
- DO: `Task.checkCancellation()` in langen Loops (siehe `GraphStatsLoader`).
- DON’T: `ModelContext.fetch` in SwiftUI `body` oder in tight scroll callbacks.
- DON’T: `#Predicate` mit optionalen String-Vergleichen in "komplizierten" Ausdruecken (siehe Kommentar in `Stats/GraphStatsService/GraphStatsService.swift`).
- DON’T: `fileData` in Listen/Picker-Layern anfassen (ExternalStorage kann teuer werden).

---

## How to work on this project (Setup Steps + wo anfangen)

### Setup (neue Devs)
1. Xcode oeffnen: `BrainMesh/BrainMesh.xcodeproj`
2. Scheme: `BrainMesh`
3. Simulator/Device: iOS 26.0+ (iPhone oder iPad)
4. iCloud/CloudKit: Capabilities sind aktiv; fuer echte Sync-Tests muss ein iCloud Account im Geraet/Simulator angemeldet sein (**UNKNOWN**: spezifische CloudKit Environment-Settings/Container-Setup ausserhalb des Projekts).

### Wo anfangen (Orientierung)
- App Shell / Boot: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`
- Datenmodell: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- Graph Canvas: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + `GraphCanvasView+Physics.swift` / `GraphCanvasView+Rendering.swift`
- Home/Detail: `BrainMesh/Mainscreen/EntitiesHomeView.swift`, `BrainMesh/Mainscreen/EntityDetail/*`, `BrainMesh/Mainscreen/NodeDetailShared/*`
- Stats: `BrainMesh/Stats/GraphStatsView/*`, `BrainMesh/Stats/GraphStatsService/*`

### Typischer Workflow: neues Feature
- UI in passendem Feature-Ordner anlegen.
- Wenn SwiftData-Fetch noetig:
  - neuen `actor ...Loader` anlegen (DTO-Snapshot zurueckgeben)
  - `configure(container:)` in `BrainMeshApp.swift` hinzufuegen
  - UI: in `.task`-Closure `await loader.load...` aufrufen und State committen
- Fuer Media/Blob:
  - DTO ohne `Data` nutzen
  - Disk-cache ueber `ImageStore`/`AttachmentStore` materialisieren

---

## Quick Wins (max 10, konkret, umsetzbar)

1. **`Onboarding/Untitled.swift` entfernen** (deprecated-only file)  
   Pfad: `BrainMesh/Onboarding/Untitled.swift`
2. **`ImageHydrator` off-main machen** (Fetch + loop currently MainActor)  
   Pfad: `BrainMesh/ImageHydrator.swift`  
   Pattern wie `AttachmentHydrator` (actor + detached context).
3. **GraphID-Optionalitaet reduzieren (planbar)**  
   Viele Predicates muessen `graphID == nil` beruecksichtigen (z.B. Stats).  
   **UNKNOWN** ob du `graphID` langfristig non-optional machen willst (Migration/Schema-Version).
4. **Attachment-Manage Sheet modularisieren** (Lesbarkeit/Wartbarkeit)  
   Pfad: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Sheets.Attachments.swift`
5. **Konsolidierung "System Modal" Markierung**  
   Pattern in `NotesAndPhotoSection.swift` und Video/Attachment pickers vereinheitlichen (Helper in `Support/`).
6. **BulkLinkView: off-main Vorberechnungen pruefen**  
   Pfad: `BrainMesh/Mainscreen/BulkLinkView.swift`  
   (z.B. `existingOutgoingTargets` Setup) -> sicherstellen, dass keine grossen fetches im Main flow haengen.
7. **GraphCanvas Physics: "relevant set" noch aggressiver nutzen**  
   Pfade: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`, `GraphCanvasScreen.swift`  
   Spotlight reduziert already; ggf. zusaetzlich spatial bucketing (groessere Aenderung, aber klarer Hotspot).
8. **ThumbnailStore: Disk-Cache-Policy dokumentieren und invalidieren**  
   Pfad: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
9. **Stats: perGraph Dictionary Key Typ vereinheitlichen**  
   `GraphStatsSnapshot.perGraph: [UUID?: GraphCounts]` ist ungewoehnlich.  
   Alternative: `[UUID: GraphCounts] + legacyCounts separat` (rein strukturell).
10. **Open Questions aus den Docs in Issues uebertragen**  
   (siehe `ARCHITECTURE_NOTES.md` "Open Questions").

