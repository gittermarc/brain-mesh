# BrainMesh — PROJECT_CONTEXT

_Last updated: 2026-02-18 (auto-generated from repository state in BrainMesh.zip)_

## TL;DR
BrainMesh ist eine iOS/iPadOS-App (SwiftUI) zum Verwalten eines persönlichen Wissens-Graphen: **Graph → Entitäten → Attribute → Links**, plus **Medien/Anhänge**, **Graph-Canvas** und **Stats**. Persistenz/Sync läuft über **SwiftData mit CloudKit (private DB, automatic)**. Mindest-iOS: **26.0** (Deployment Target aus `BrainMesh.xcodeproj/project.pbxproj`).

## Key Concepts (Domänenbegriffe)
- **Graph / Workspace** (`MetaGraph`): Ein „Arbeitsraum“; der User kann zwischen Graphen wechseln (Graph-Picker). Optional pro Graph Schutz via Biometrie/Passwort.
- **Entität** (`MetaEntity`): Primäre Knotenart (z.B. „Projekt“, „Person“, „Thema“).
- **Attribut** (`MetaAttribute`): Knotenart, die optional einem Owner (`MetaEntity`) zugeordnet ist; Anzeige-Label kann „Entität · Attribut“ sein.
- **Link** (`MetaLink`): Kante zwischen zwei Knoten (Entity/Attribute), speichert IDs + denormalisierte Labels (`sourceLabel`, `targetLabel`) + optional Note.
- **Attachment** (`MetaAttachment`): Datei/Video/Gallery-Image an Entity/Attribute (Owner über `ownerKindRaw + ownerID`), bytes in `fileData` (external storage), lokal gecacht.
- **NodeKind / NodeKey / NodeRef**: Value-Typen, die Knoten eindeutig referenzieren (wichtig für Canvas/Navigation ohne SwiftData-Objekte über Threads zu reichen).
- **Hydration**: Hintergrund-Jobs, die aus SwiftData synchronisierte Bytes/Metadaten in lokale Cache-Dateien überführen (Images/Attachments), um UI-I/O zu entkoppeln.

## Architecture Map (Layer + Verantwortlichkeiten + Abhängigkeiten)
**UI (SwiftUI Views)**
- Tabs + Navigation: `BrainMesh/ContentView.swift`
- Root/Bootstrapping/Overlays (Onboarding, Unlock): `BrainMesh/AppRootView.swift`
- Feature-Module: `BrainMesh/Mainscreen/*`, `BrainMesh/GraphCanvas/*`, `BrainMesh/Stats/*`, `BrainMesh/Attachments/*`, `BrainMesh/PhotoGallery/*`, `BrainMesh/Settings/*`, `BrainMesh/Onboarding/*`, `BrainMesh/GraphPicker/*`, `BrainMesh/Icons/*`, `BrainMesh/Security/*`

**Loaders / Services (Performance & Entkopplung)**
- Off-main Snapshot-Loader (Actors + value-only DTOs):  
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`  
  - `BrainMesh/Mainscreen/NodePickerLoader.swift`  
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`  
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`  
  - `BrainMesh/Stats/GraphStatsLoader.swift`  
  - `BrainMesh/Attachments/MediaAllLoader.swift`
- Cache/Hydration:
  - Images: `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`
  - Attachments: `BrainMesh/Attachments/AttachmentStore.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`, `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

**Model / Storage**
- SwiftData Models:
  - `BrainMesh/Models.swift`: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`
  - `BrainMesh/Attachments/MetaAttachment.swift`: `MetaAttachment`
- Boot/Migration:
  - `BrainMesh/GraphBootstrap.swift`: Graph anlegen + `graphID` Legacy-Migration (Entities/Attributes/Links)
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`: on-demand Migration für Attachments (pro Owner)
- Active graph state (UserDefaults/AppStorage):
  - `BrainMesh/GraphSession.swift` (ObservableObject)
  - `@AppStorage("BMActiveGraphID")` in mehreren Views

**Security**
- Graph Lock/Unlock + Crypto:
  - `BrainMesh/Security/GraphLockCoordinator.swift`
  - `BrainMesh/Security/GraphLockCrypto.swift`
  - `BrainMesh/Security/GraphUnlockView.swift`, `GraphSecuritySheet.swift`, `GraphSetPasswordView.swift`

**Observability / Support**
- Logging/Timing: `BrainMesh/Observability/BMObservability.swift`
- System Modal Tracking (Picker vs Auto-Lock): `BrainMesh/Support/SystemModalCoordinator.swift`

_Abhängigkeiten (grob): UI → Loaders/Services → SwiftData (`ModelContainer/ModelContext`) + Stores; Security/Support hängen an UI + SwiftData._

## Folder Map (Ordner → Zweck)
Top-Level unter `BrainMesh/`:
- `Appearance/`: Theme/Display-Settings (Tint, Scheme, Presets) + UI für Anzeigeoptionen.
- `Attachments/`: Attachment-Model, Import, Caching (Disk), Hydration, Thumbnails, Preview (QuickLook/Video).
- `GraphCanvas/`: Interaktiver Canvas (Rendering, Physics, Gestures, Overlays, Data Loading).
- `GraphPicker/`: List UI + Flows für Graph auswählen/umbenennen/löschen/dupe cleanup.
- `Icons/`: Icon-Auswahl (kuratierte Liste + Recents + „Alle SF Symbols…“).
- `Images/`: Import-Pipeline für Bilder.
- `ImportProgress/`: UI/State für laufende Import-Progressanzeigen.
- `Mainscreen/`: Entities/Home, Detail-Screens, Link/Bulk-Flows, Picker, gemeinsame Detail-Komponenten.
- `Observability/`: Micro-Logging + Timing-Helfer.
- `Onboarding/`: Onboarding Coordinator + Sheet/Steps + Progress-Berechnung.
- `PhotoGallery/`: Gallery UI (Grid/Browser/Viewer) für zusätzliche Bilder.
- `Security/`: Lock/Unlock/Passwort/FaceID pro Graph.
- `Settings/`: Settings UI + Wartung (Image Cache rebuild, Attachment Cache clear) + About.
- `Stats/`: Stats Tab + Services + Komponenten (Cards/Charts/KPIs).
- `Support/`: Kleine App-weite Koordinatoren (z.B. SystemModalCoordinator).

## Data Model Map (Entities, Relationships, wichtige Felder)
### `MetaGraph` (`BrainMesh/Models.swift`)
- `id: UUID`, `createdAt: Date`
- `name`, `nameFolded` (für Suche, via `BMSearch.fold`)
- Lock: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Derived: `isProtected`, `isPasswordConfigured`

### `MetaEntity` (`BrainMesh/Models.swift`)
- `id: UUID`
- `graphID: UUID?` (**Optional** für Legacy-Migration; Zielzustand: nicht-nil in aktiven Graphen)
- `name`, `nameFolded`, `notes`
- Media: `imageData: Data?` (CloudKit-sync), `imagePath: String?` (lokaler Cache filename)
- UI: `iconSymbolName: String?`
- Lock-Felder analog zu `MetaGraph` (Biometrie/Passwort)
- Relationship:
  - `attributes: [MetaAttribute]?` mit `@Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner)`
- Convenience: `attributesList` (de-dupe by id)

### `MetaAttribute` (`BrainMesh/Models.swift`)
- `id: UUID`, `graphID: UUID?`
- `name`, `nameFolded`, `notes`
- `owner: MetaEntity?` (kein Macro hier; Owner setzt ggf. `graphID`)
- `searchLabelFolded` (aus `displayName`)
- Media/UI: `imageData`, `imagePath`, `iconSymbolName`
- Lock-Felder analog zu `MetaGraph`

### `MetaLink` (`BrainMesh/Models.swift`)
- `id`, `createdAt`, `note`
- `graphID: UUID?`
- Denormalisierte Labels: `sourceLabel`, `targetLabel`
- Endpunkte: `sourceKindRaw`, `sourceID`, `targetKindRaw`, `targetID`
- Derived: `sourceKind`, `targetKind`

### `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
- `id`, `createdAt`, `graphID: UUID?`
- Owner: `ownerKindRaw`, `ownerID`
- Typ: `contentKindRaw` (`AttachmentContentKind`: file/video/galleryImage)
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Bytes: `@Attribute(.externalStorage) fileData: Data?`
- Lokaler Cache: `localPath: String?`

## Sync / Storage
### SwiftData + CloudKit
- ModelContainer wird in `BrainMesh/BrainMeshApp.swift` mit `ModelConfiguration(schema:..., cloudKitDatabase: .automatic)` initialisiert.
- Entitlements: `BrainMesh/BrainMesh.entitlements`  
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`  
  - iCloud Service: `CloudKit`  
  - `aps-environment`: `development`
- Info.plist: `BrainMesh/Info.plist`  
  - `UIBackgroundModes = ["remote-notification"]` (CloudKit Push/Sync)  
  - `NSFaceIDUsageDescription` gesetzt

### Lokale Caches (Application Support)
- **Images**: `BrainMesh/ImageStore.swift` → `Application Support/BrainMeshImages`  
  - Memory cache (NSCache) + Disk cache
- **Attachments**: `BrainMesh/Attachments/AttachmentStore.swift` → `Application Support/BrainMeshAttachments`  
  - Disk cache für Files; Thumbnails: `AttachmentThumbnailStore` (thumb_<id>.jpg)
- **Hydration**:
  - `AttachmentHydrator` & `ImageHydrator` werden in `BrainMesh/BrainMeshApp.swift` via `Task.detached` konfiguriert (Container injiziert) und laufen off-main.
  - Auto-Trigger: `AppRootView.autoHydrateImagesIfDue()` (max 1× / 24h, AppStorage timestamp).

### Migration / Legacy
- Graph scope Migration (Entities/Attributes/Links): `BrainMesh/GraphBootstrap.swift` (läuft im Startup: `AppRootView.bootstrapGraphing()`).
- Attachment scope Migration (nur bei Bedarf): `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (wird von Loader/Actions aufgerufen).

### Offline-Verhalten (implizit durch SwiftData)
- SwiftData ist lokal persistent; CloudKit-Sync ist opportunistisch.
- **UNKNOWN**: spezielle Offline-UI (z.B. Sync-Status) oder manuelle Retry-Mechanik (keine dedizierte Sync-UI im Code gefunden).

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root Navigation
- `TabView` in `BrainMesh/ContentView.swift`:
  1) **Entitäten** → `EntitiesHomeView()`
  2) **Graph** → `GraphCanvasScreen()`
  3) **Stats** → `GraphStatsView()`
  4) **Einstellungen** → `SettingsView(showDoneButton: false)` im `NavigationStack`

### Global Overlays / Startup
- `BrainMesh/AppRootView.swift`:
  - Startup: Graph bootstrap + Lock enforcement + (optionale) Image hydration + Onboarding Auto-Show
  - Onboarding: `.sheet` → `OnboardingSheetView()`
  - Graph unlock: `.fullScreenCover(item:)` → `GraphUnlockView(request:)`
  - ScenePhase Handling + debounce Auto-Lock (in Kombination mit `SystemModalCoordinator`)

### Entitäten / Details
- Home: `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - Graph wechseln: `GraphPickerSheet` (`BrainMesh/GraphPickerSheet.swift`)
  - Add Entity: `AddEntityView` (`BrainMesh/Mainscreen/AddEntityView.swift`)
- Entity/Attribute Details: `BrainMesh/Mainscreen/EntityDetail/*`, `BrainMesh/Mainscreen/AttributeDetail/*`
  - Shared components: `BrainMesh/Mainscreen/NodeDetailShared/*`
  - Links: AddLink/BulkLink: `AddLinkView.swift`, `BulkLinkView.swift`, `NodeAddLinkSheet.swift`, `NodeBulkLinkSheet.swift`
  - Media: Gallery + Attachments + Preview (siehe `NodeDetailShared+Media*`)

### Graph Canvas
- Screen: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` (+ `GraphCanvasScreen+*.swift`)
- View/Simulation/Rendering: `GraphCanvasView.swift` (+ `GraphCanvasView+Camera/Gestures/Physics/Rendering.swift`)
- Data loading off-main: `GraphCanvasDataLoader.swift`

### Stats
- Screen: `BrainMesh/Stats/GraphStatsView/*`
- Data: `GraphStatsLoader.swift` + `GraphStatsService/*`
- UI components: `Stats/StatsComponents/*`

## Build & Configuration
- Xcode project: `BrainMesh.xcodeproj`
- Deployment Target: iOS 26.0
- Device family: iPhone+iPad (`TARGETED_DEVICE_FAMILY = "1,2"` in pbxproj)
- Entitlements/Capabilities:
  - iCloud/CloudKit: `BrainMesh/BrainMesh.entitlements`
  - Push environment: `development` (DEBUG/Development)
  - Background mode: remote-notification (`BrainMesh/Info.plist`)
- Dependencies:
  - SwiftUI, SwiftData, Combine, os.Logger, UIKit, LocalAuthentication, QuickLook/AVFoundation (für Attachments/Thumbnails)
  - SPM Packages: **keine** in `project.pbxproj` gefunden

## Conventions (Naming, Patterns, Do/Don’t)
- Suche: `BMSearch.fold` + *Folded*-Felder (`nameFolded`, `searchLabelFolded`) statt „on-the-fly“ Folding in Hot Paths.
- Graph Scoping:
  - Bei `activeGraphID != nil`: bevorzugt strikt `x.graphID == gid` (keine OR-Predicates).
  - Legacy-Migration existiert (`GraphBootstrap`, `AttachmentGraphIDMigration`).
- Concurrency:
  - **Nie** SwiftData `@Model` Instanzen über Thread/Actor-Grenzen reichen.
  - Pattern: Actor-Loader → value-only DTO/Snapshot → UI navigiert über IDs und löst Model im Main-Context auf.
- Caches:
  - Keine sync Disk-I/O in `body`.
  - Thumbnails/Images: dedupe + limiter (`AsyncLimiter`).

## How to work on this project (Setup + wo anfangen)
### Setup (lokal)
1) Öffnen: `BrainMesh.xcodeproj` in Xcode 26.
2) iCloud testen: auf Device/Simulator mit iCloud-Account; Capability „iCloud/CloudKit“ muss aktiv sein (Entitlements vorhanden).
3) Build/Run: iOS 26.0 Simulator oder Device.
4) Für Lock-Features: FaceID/TouchID im Simulator/Device aktivieren; `NSFaceIDUsageDescription` ist gesetzt.

### Einstiegspunkte (für neue Devs)
- App/Container: `BrainMesh/BrainMeshApp.swift`
- Startup/Overlays: `BrainMesh/AppRootView.swift`
- Domänenmodell: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- Hauptnavigation: `BrainMesh/ContentView.swift`
- Feature: Entities/Home: `BrainMesh/Mainscreen/EntitiesHomeView.swift`
- Heavy Feature: Graph Canvas: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` + `GraphCanvasView+Physics/Rendering.swift`

### Typischer Workflow: neues Feature hinzufügen (Checkliste)
- [ ] Betroffene Domain identifizieren (Graph/Entity/Attribute/Link/Attachment).
- [ ] Modelländerung (falls nötig): `Models.swift` oder `MetaAttachment.swift` anpassen (+ folded/search Felder konsistent halten).
- [ ] Performance-sensitiver Screen? → Loader-Pattern nutzen (actor + snapshot DTO).
- [ ] UI Hook: in passendem Feature-Ordner (z.B. `Mainscreen/...`, `GraphCanvas/...`) neue View/Subview ablegen.
- [ ] Cache-I/O: über `ImageStore` / `AttachmentStore` / `AttachmentThumbnailStore` (async, dedupe).
- [ ] Logging: `BMLog.*` nutzen, wenn Hot Path/Loader erweitert wird.

## Quick Wins (max 10, konkret & umsetzbar)
1) **Fetch im SwiftUI-Renderpfad entfernen**: `NodeLinkDetailRouter` macht `modelContext.fetch(...)` direkt in `body` → in `.task` laden oder `@Query` nutzen.  
   Pfad: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift` (ca. Zeilen 340–370).
2) **GraphCanvasDataLoader: FetchLimit vs Filter-Reihenfolge prüfen**: Links werden mit `fetchLimit=maxLinks` geladen und danach in-memory auf `nodeIDs` gefiltert → kann relevante Links wegschneiden.  
   Pfad: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` (loadGlobal, `filteredLinks` nach fetchLimit).
3) **Entity/Attribute Bilddaten als externalStorage erwägen**: `MetaEntity.imageData` / `MetaAttribute.imageData` sind nicht mit `@Attribute(.externalStorage)` markiert → CloudKit Record Size Pressure möglich.  
   Pfad: `BrainMesh/Models.swift`.
4) **Attachment GraphID Migration zentralisieren**: `GraphBootstrap` migriert Entities/Attributes/Links, Attachments sind on-demand → optional: Startup-Pass nur für `fetchLimit=1` + ggf. Hintergrund-Repair.  
   Pfad: `BrainMesh/GraphBootstrap.swift`, `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`.
5) **Timer-Lifecycle im Canvas hart absichern**: Simulation läuft über `Timer.scheduledTimer` (30fps). Sicherstellen, dass `stopSimulation()` zuverlässig in `onDisappear`/ScenePhase passiert, um Background-Ticks zu vermeiden.  
   Pfad: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`, `GraphCanvasView.swift` (**UNKNOWN**, ob bereits überall sauber gestoppt).
6) **`@unchecked Sendable` Snapshots minimieren**: Snapshot DTOs sind pragmatisch, aber riskant, wenn später Reference-Typen hineinrutschen. Lightweight Audit + Kommentare/Tests.  
   Pfade: `GraphCanvasDataLoader.swift`, `GraphStatsLoader.swift`, `EntitiesHomeLoader.swift`, `NodeConnectionsLoader.swift`.
7) **Link-Label Denormalisierung konsistent halten**: Rename-Flow muss Links updaten (Service existiert). Sicherstellen, dass alle Rename-Einstiege `NodeRenameService` nutzen.  
   Pfad: `BrainMesh/BrainMeshApp.swift` (configure), `BrainMesh/Mainscreen/LinkCleanup.swift` + Rename UI (**UNKNOWN**, vollständige Coverage).
8) **Thumbnails: RequestSize/Scale Standardisieren**: Viele Aufrufer können unterschiedliche Größen anfragen → kann Cache hit rate drücken.  
   Pfad: `BrainMesh/Attachments/AttachmentThumbnailStore.swift` + UI-Aufrufer.
9) **Stats: große Karten weiter splitten, wenn Editing zunimmt**: `StatsComponents+Cards.swift` ist groß; bei Feature-Wachstum weiter in thematische Cards splitten.  
   Pfad: `BrainMesh/Stats/StatsComponents/StatsComponents+Cards.swift`.
10) **Tests anreichern (Smoke)**: `BrainMeshTests.swift` ist leer → mind. 2–3 Tests für Fold/Search + GraphBootstrap Migration (legacy graphID).  
    Pfade: `BrainMeshTests/BrainMeshTests.swift`, `BrainMesh/GraphBootstrap.swift`, `BrainMesh/Models.swift`.


## UI Flows (wichtige Sheets/Routes, wo der Code sitzt)
### Graph-Verwaltung
- Picker Sheet Host: `BrainMesh/GraphPickerSheet.swift` (State + Routing)
- List/Rows: `BrainMesh/GraphPicker/GraphPickerListView.swift`, `GraphPickerRow.swift`
- Rename: `BrainMesh/GraphPicker/GraphPickerRenameSheet.swift`
- Delete Flow: `BrainMesh/GraphPicker/GraphPickerDeleteFlow.swift`
- Services:
  - Dupe Cleanup: `BrainMesh/GraphPicker/GraphDedupeService.swift`
  - Deletion: `BrainMesh/GraphPicker/GraphDeletionService.swift`

### Node-Details (Shared)
- Core UI Bausteine (Hero, Pills, Headers): `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Core.swift`
- Abschnitt-Highlights / KPI-Zeilen: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift`
- Connections Preview + „Alle“-Screen: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections.swift`  
  - Off-main Loader für „Alle“: `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
- Medien (Fotos/Anhänge):
  - Gallery Grid: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
  - Attachments: `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaAttachments.swift`
  - Attachments Manage Sheet (Import/Actions/Loading split): `BrainMesh/Mainscreen/NodeDetailShared/NodeAttachmentsManageView+*.swift`
  - Media Preview Loader: `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift` (inkl. AttachmentGraphIDMigration)

### Link-Workflows
- Add Link: `BrainMesh/Mainscreen/AddLinkView.swift`, Sheet: `BrainMesh/Mainscreen/NodeAddLinkSheet.swift`
- Bulk Link: `BrainMesh/Mainscreen/BulkLinkView.swift`, Sheet: `BrainMesh/Mainscreen/NodeBulkLinkSheet.swift`
- Cleanup/Relabel: `BrainMesh/Mainscreen/LinkCleanup.swift` (+ `NodeRenameService` in `BrainMesh/BrainMeshApp.swift` konfiguriert)

## Invariants / Datenregeln (wichtig für Refactors)
- **Graph scoping**: Wenn `BMActiveGraphID` gesetzt ist, sollen neue/aktualisierte Records nach Möglichkeit `graphID == activeGraphID` haben.
- **Legacy graphID**: `graphID == nil` ist „Altbestand“; Migration existiert.
- **Links**:
  - Endpunkte sind IDs + KindRaw (`sourceKindRaw/targetKindRaw`) — kein Relationship.
  - Labels sind denormalisiert → Rename muss Link-Labels aktualisieren.
- **Attachments**:
  - Owner ist `(ownerKindRaw, ownerID)`; graphID ist zur Query-Optimierung da.
  - File bytes liegen in `fileData` (external storage), lokaler Cache ist nur eine Optimierung.

## Troubleshooting / Debug Runbook (kurz, technisch)
- „UI hängt beim Öffnen eines Screens“:
  - Prüfen: gibt es `modelContext.fetch` im Renderpfad (`body`) oder in `.onAppear` ohne Dedupe?
  - Logs: `BMLog.load`, `BMLog.physics` (`BrainMesh/Observability/BMObservability.swift`)
- „Attachment Grid zieht CPU hoch“:
  - Prüfen: `AttachmentThumbnailStore` limiter (`maxConcurrent`) + RequestSize konsistent.
  - Prüfen: ob `AttachmentHydrator.ensureFileURL(...)` in vielen Zellen gleichzeitig getriggert wird (Dedupe via `inFlight` vorhanden).
- „Graph Canvas frisst Akku“:
  - Timer-Lifecycle und „sleep“ (`physicsIsSleeping`) prüfen. Pfad: `BrainMesh/GraphCanvas/GraphCanvasView+Physics.swift`
- „Daten wirken ‚weg‘ nach Graph-Wechsel“:
  - Prüfen: `activeGraphIDString` (AppStorage) + scoping predicates in Loader/Queries.
  - Prüfen: ob noch legacy `graphID == nil` Records existieren (`GraphBootstrap.hasLegacyRecords`).

## Open Questions (PROJECT_CONTEXT)
Alle Punkte hier sind bewusst als **UNKNOWN** markiert (nicht eindeutig aus dem Code ableitbar):
- **UNKNOWN**: Gibt es ein bewusstes Daten-Limit/Policy für `imageData` Größen (JPEG-Compression/Resizing beim Import)?
- **UNKNOWN**: Gibt es bewusst deaktivierte CloudKit Features (z.B. Share/Collab), oder ist Private-DB-only die Zielarchitektur?
- **UNKNOWN**: Gibt es ein Monitoring/Debug UI für Sync-Status (dezent in Settings o.ä.)?
- **UNKNOWN**: Gibt es Migrationspläne über `graphID` hinaus (Schema changes), oder ist graphID die einzige Legacy-Schicht?
