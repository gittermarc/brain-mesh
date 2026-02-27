# PROJECT_CONTEXT — BrainMesh (Start Here)

## TL;DR
BrainMesh ist eine iOS-App (Deployment Target: iOS 26.0) für ein **graph-basiertes Wissens-/Notizsystem**: Nutzer erstellen **Graphen (Workspaces)**, darin **Entitäten**, dazu **Attribute**, verknüpfen sie über **Links**, hängen **Anhänge/Medien** an und visualisieren/verwalten alles im **GraphCanvas**. Einstieg/Root: BrainMesh/BrainMeshApp.swift, Tabs: BrainMesh/ContentView.swift.

## Key Concepts / Domänenbegriffe
- **Graph (MetaGraph)**: Workspace/Scope für Daten + optionaler Zugriffsschutz. Model: BrainMesh/Models/MetaGraph.swift.
- **Entität (MetaEntity)**: “Knoten-Typ 1” im Graphen (Name, Notes, optional Icon/Bild). Model: BrainMesh/Models/MetaEntity.swift.
- **Attribut (MetaAttribute)**: “Knoten-Typ 2” (gehört optional zu einer Entität; ebenfalls Notes/Icon/Bild). Model: BrainMesh/Models/MetaAttribute.swift.
- **Link (MetaLink)**: gerichtete Kante zwischen zwei Nodes (Entity/Attribute) mit optionaler Notiz. Model: BrainMesh/Models/MetaLink.swift.
- **Attachments (MetaAttachment)**: Datei/Video/Gallery-Image an Entity/Attribute; Bytes als externalStorage, lokale Cache-Datei optional. Model: BrainMesh/Attachments/MetaAttachment.swift.
- **Details (Schema + Werte)**:
  - **MetaDetailFieldDefinition** = definierte Felder pro Entität (z.B. “Autor”, “Datum”), inkl. Pinning.
  - **MetaDetailFieldValue** = Werte pro Attribut + Feld. Models: BrainMesh/Models/DetailsModels.swift.
  - **MetaDetailsTemplate** = vom Nutzer gespeicherte “Sets” (JSON-Feldliste) pro Graph. Model: BrainMesh/Models/MetaDetailsTemplate.swift.
- **GraphCanvas**: Visualisierung/Interaktion (Nodes/Edges, Zoom/Pan, Physik). Screen: BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift.
- **Graph Lock**: Zugriffsschutz pro Graph (Biometrie/Passwort). Koordinator wird in BrainMesh/BrainMeshApp.swift als EnvironmentObject gesetzt; UI-Host: BrainMesh/AppRootView.swift.
- **Folded Search Indices**: normalisierte Suchfelder (nameFolded, notesFolded, noteFolded) zur schnellen, diakritik-/case-insensitiven Suche. Helper: BrainMesh/Models/BMSearch.swift.

## Architecture Map (Layer/Module + Verantwortlichkeiten + Abhängigkeiten)
**1) App Bootstrap / Composition Root**
- App-Entry + SwiftData Container Setup: BrainMesh/BrainMeshApp.swift
  - Schema enthält Models (MetaGraph/Entity/Attribute/Link/Attachment/Details/Template).
  - Erstellt `ModelContainer` mit CloudKit (`cloudKitDatabase: .automatic`) und konfiguriert Loader/Hydrators via BrainMesh/Support/AppLoadersConfigurator.swift.
- Root-Lifecycle + systemweite Sheets: BrainMesh/AppRootView.swift
  - Startup (Graph bootstrap, Lock enforcement, Image hydration), Onboarding-Sheet, GraphUnlock fullScreenCover.
- Tabs / Navigation: BrainMesh/ContentView.swift (TabView + Settings in NavigationStack).

**2) Storage / Sync**
- SwiftData Models (mit CloudKit): BrainMesh/Models/MetaGraph.swift, BrainMesh/Models/MetaEntity.swift, BrainMesh/Models/MetaAttribute.swift, BrainMesh/Models/MetaLink.swift, BrainMesh/Attachments/MetaAttachment.swift, BrainMesh/Models/DetailsModels.swift, BrainMesh/Models/MetaDetailsTemplate.swift.
- CloudKit Runtime Status (UI sichtbar in Settings): BrainMesh/Settings/SyncRuntime.swift.
- Migration/Backfill Utilities:
  - Graph-scope Migration für Legacy Records (graphID == nil): BrainMesh/GraphBootstrap.swift.
  - Attachment graphID Migration (vermeidet OR-Prädikate mit externalStorage): BrainMesh/Attachments/AttachmentGraphIDMigration.swift.

**3) Background Loader/Hydrator Layer (off-main)**
Ziel: keine SwiftData-Fetches/Traversal im Renderpfad; stattdessen actor + Snapshot DTO.
- Zentrale Registrierung/Konfiguration: BrainMesh/Support/AppLoadersConfigurator.swift + Container Wrapper: BrainMesh/Support/AnyModelContainer.swift.
- Beispiele:
  - Entities Home Snapshot: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift → UI: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift.
  - GraphCanvas Snapshot (Nodes/Edges/LabelCaches): BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift → UI: BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift.
  - Stats Snapshot: BrainMesh/Stats/GraphStatsLoader.swift → UI: BrainMesh/Stats/GraphStatsView/GraphStatsView.swift.
  - Image Cache Hydration: BrainMesh/ImageHydrator.swift + Local Store: BrainMesh/ImageStore.swift.
  - Attachment Cache/Import: BrainMesh/Attachments/AttachmentStore.swift + BrainMesh/Attachments/AttachmentImportPipeline.swift.

**4) UI Layer (SwiftUI)**
- Mainscreen: `BrainMesh/Mainscreen/...` (Home, Detail Screens, Bulk-Linking, Shared Node Detail Components).
- GraphCanvas: `BrainMesh/GraphCanvas/...` (Canvas Screen + View + Simulation/Rendering).
- Stats: `BrainMesh/Stats/...` (Dashboard + Services/Loaders).
- Settings: `BrainMesh/Settings/...` (Hub + Unterseiten für Appearance/Display/Import/Sync/Help).
- Onboarding: `BrainMesh/Onboarding/...` (Sheets/Progress).

**5) Cross-cutting**
- Logging/Timing: BrainMesh/Observability/BMObservability.swift (os.Logger Kategorien + BMDuration).
- “No SwiftData models across actors”: wird in Snapshots/Loader-Kommentaren explizit eingehalten (z.B. BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift, BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift).

## Folder Map (Ordner → Zweck)
- `BrainMesh/Models/` → SwiftData `@Model` Klassen + Such-Helper (`BMSearch`).
- `BrainMesh/Mainscreen/` → Haupt-UI: Home, Entity/Attribute Detail, Shared Node-Detail Bausteine, BulkLink Flow.
- `BrainMesh/GraphCanvas/` → Graph Visualisierung: Screen, View, Rendering, Physik, DataLoader.
- `BrainMesh/Attachments/` → Attachments Models, Cache Store, Import Pipeline, Hydrators/Loader.
- `BrainMesh/PhotoGallery/` → Gallery UI/Viewer für zusätzliche Bilder (nicht GraphCanvas).
- `BrainMesh/Stats/` → Stats UI + `GraphStatsService` + Loader/Snapshots.
- `BrainMesh/Settings/` → Settings Hub + Unterseiten (Appearance/Display/Import/Sync/Help).
- `BrainMesh/Security/` → Graph Lock/Unlock, Passwort/biometrische Flows.
- `BrainMesh/Support/` → kleine Infrastruktur (Container Wrapper, Loader Configurator, Indizes/Utilities).
- `BrainMesh/Observability/` → Logging/Timing Helpers.
- `BrainMesh/Onboarding/` → Onboarding coordinator + Sheets.

## Data Model Map (Entities, Relationships, wichtige Felder)
> Scope-Konzept: fast alle Models haben optionales `graphID: UUID?` für Multi-Graph und sanfte Migration (Legacy: `nil`).

### MetaGraph
- Datei: BrainMesh/Models/MetaGraph.swift
- Felder: `id`, `createdAt`, `name/nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### MetaEntity
- Datei: BrainMesh/Models/MetaEntity.swift
- Felder: `id`, `createdAt`, `graphID`, `name/nameFolded`, `notes/notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
- Beziehungen:
  - `attributes` (cascade) → `MetaAttribute.owner` (inverse nur auf Entity-Seite definiert)
  - `detailFields` (cascade) → `MetaDetailFieldDefinition.owner`

### MetaAttribute
- Datei: BrainMesh/Models/MetaAttribute.swift
- Felder: `id`, `graphID`, `name/nameFolded`, `notes/notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
- Beziehung:
  - `owner: MetaEntity?` (ohne inverse, um Macro-Zirkularität zu vermeiden)
  - `detailValues` (cascade) → `MetaDetailFieldValue.attribute`
- Denormalisiert: `searchLabelFolded` (kombiniert Entity+Attribut DisplayName)

### MetaLink
- Datei: BrainMesh/Models/MetaLink.swift
- Felder: `id`, `createdAt`, `graphID`
- Endpunkte: `sourceKindRaw/sourceID/sourceLabel`, `targetKindRaw/targetID/targetLabel`
- Notiz: `note` + Index `noteFolded`

### MetaAttachment
- Datei: BrainMesh/Attachments/MetaAttachment.swift
- Felder: `id`, `createdAt`, `graphID`
- Owner als Scalars: `ownerKindRaw` + `ownerID` (bewusst ohne Relationship macros)
- Typ: `contentKindRaw` (file/video/galleryImage)
- Bytes: `fileData` als `@Attribute(.externalStorage)`
- Lokal: `localPath` (Application Support Cache)

### Details: MetaDetailFieldDefinition / MetaDetailFieldValue
- Datei: BrainMesh/Models/DetailsModels.swift
- MetaDetailFieldDefinition:
  - Scalars: `entityID`, `graphID`, `name/nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Beziehung: `owner: MetaEntity?` (nullify)
- MetaDetailFieldValue:
  - Scalars: `attributeID`, `fieldID`, `graphID`
  - Typed Values: `stringValue/intValue/doubleValue/dateValue/boolValue`
  - Beziehung: `attribute: MetaAttribute?`

### MetaDetailsTemplate (Saved Sets)
- Datei: BrainMesh/Models/MetaDetailsTemplate.swift
- Felder: `id`, `createdAt`, `graphID`, `name/nameFolded`, `fieldsJSON` (Array von FieldDef)

## Sync/Storage (SwiftData + CloudKit + Caches + Migration + Offline)
- Container Setup: BrainMesh/BrainMeshApp.swift
  - CloudKit aktiv: `ModelConfiguration(..., cloudKitDatabase: .automatic)`
  - Release-Fallback: bei CloudKit-Init-Fehlern wird in Release auf local-only umgeschaltet (siehe `#else` Block).
- iCloud/CloudKit Status:
  - Container-ID: `iCloud.de.marcfechner.BrainMesh` (muss zu Entitlements passen): BrainMesh/BrainMesh.entitlements + BrainMesh/Settings/SyncRuntime.swift.
  - App prüft Account-Status async beim Launch: BrainMesh/BrainMeshApp.swift.
- Hintergrund:
  - `UIBackgroundModes` enthält `remote-notification` (CloudKit push): BrainMesh/Info.plist.
- Lokale Caches (Application Support):
  - Bilder: `BrainMeshImages` via BrainMesh/ImageStore.swift, Hydration via BrainMesh/ImageHydrator.swift.
  - Attachments: `BrainMeshAttachments` via BrainMesh/Attachments/AttachmentStore.swift (lokale Kopien/Preview).
- Migration/Backfill:
  - Graph-scope Migration (Legacy `graphID == nil`): BrainMesh/GraphBootstrap.swift.
  - Backfill für `notesFolded`/`noteFolded`: BrainMesh/GraphBootstrap.swift.
  - Attachments graphID Migration, um store-translatable Predicates ohne OR zu behalten (wichtig wegen externalStorage): BrainMesh/Attachments/AttachmentGraphIDMigration.swift.
- Offline-Verhalten:
  - SwiftData arbeitet lokal; Sync erfolgt später via CloudKit. **UNKNOWN**: explizite Konfliktauflösungs-Policy (SwiftData/CloudKit Standardverhalten, keine app-spezifischen CKOperationen im Code gefunden).

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root Tabs
- Entitäten: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift
- Graph: BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift
- Stats: BrainMesh/Stats/GraphStatsView/GraphStatsView.swift
- Einstellungen: BrainMesh/Settings/SettingsView.swift (in NavigationStack, siehe BrainMesh/ContentView.swift)

### Entities Home → Detail Flows
- Home list/grid + Suche/Sortierung: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift (Daten via BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift)
- Entity Detail: BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift
  - Links via BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift (outgoing/incoming @Query)
  - BulkLink Sheet: BrainMesh/Mainscreen/BulkLinkView.swift
  - Details Schema Builder: BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaBuilderView.swift
  - Attachments/Media: `BrainMesh/Attachments/*` + `BrainMesh/PhotoGallery/*`

### GraphCanvas
- Screen/State/Overlays: BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift
- Rendering/Frame caches: BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift
- Physik/Simulation (30 FPS Timer): BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift
- Daten laden off-main: BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift

### Onboarding / Security
- Onboarding host (sheet): BrainMesh/AppRootView.swift → `BrainMesh/Onboarding/*`
- Graph Unlock host (fullScreenCover): BrainMesh/AppRootView.swift → `BrainMesh/Security/GraphUnlock/*`

### Settings
- Hub-Grid: BrainMesh/Settings/SettingsView.swift
- Sync & Wartung: BrainMesh/Settings/SyncMaintenanceView.swift (Cache sizes, rebuild triggers)
- Import (Compression): `BrainMesh/Settings/ImportSettingsView.swift`
- Help/Support: `BrainMesh/Settings/HelpSupportView.swift`

## Build & Configuration
- Xcode Projekt: `BrainMesh/BrainMesh.xcodeproj`
- Deployment Target: iOS 26.0 (aus project.pbxproj extrahiert)
- Entitlements:
  - iCloud Container + CloudKit Service: BrainMesh/BrainMesh.entitlements
  - APS environment: `development` (für Release/TestFlight vermutlich anzupassen) — **UNKNOWN**: finaler Signing/Distribution-Setup.
- Info.plist:
  - `UIBackgroundModes` = `remote-notification`
  - `NSFaceIDUsageDescription` gesetzt: BrainMesh/Info.plist
- SPM:
  - Keine Swift Package Dependencies im Repo gefunden (kein `Package.swift`, keine `repositoryURL` in pbxproj) — **UNKNOWN**: ob lokal/privat Packages außerhalb dieses ZIP genutzt werden.

## Conventions (Naming, Patterns, Do/Don’t)
### Patterns, die im Projekt klar etabliert sind
- **Loader + Snapshot DTO** statt SwiftData-Fetch im UI-Thread:
  - Beispiel: BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift, BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift, BrainMesh/Stats/GraphStatsLoader.swift.
- **Kein Cross-Actor-Sharing von `@Model` Objekten**:
  - Snapshots sind Value-only, UI navigiert via `id` und resolved Models im main `ModelContext`.
- **Graph-Scoping über `graphID`** + sanfte Migration aus Legacy (`nil`):
  - Migration/Backfill: BrainMesh/GraphBootstrap.swift.
- **Stored Search Indices** (folded strings) werden in `didSet` gepflegt:
  - z.B. `nameFolded/notesFolded/noteFolded` in Models.
- **SwiftUI File Splits**: große Screens werden über Extensions/Subviews in mehrere Dateien aufgeteilt (z.B. `GraphCanvasScreen+*.swift`, `GraphCanvasView+*.swift`).
- **Cache-Layer**: synced bytes (SwiftData) + lokaler Disk Cache (Application Support), mit Hydrators.

### Do
- Fetch/Traversal in actor/Loader, UI bekommt Snapshots (DTOs).
- Prädikate store-translatable halten (kein OR) bei externalStorage (siehe BrainMesh/Attachments/AttachmentGraphIDMigration.swift).
- Bei neuen Suchfeldern: folded index + Backfill in BrainMesh/GraphBootstrap.swift ergänzen.

### Don’t
- `ImageStore.loadUIImage(path:)` im SwiftUI `body` aufrufen (explizit verboten in BrainMesh/ImageStore.swift).
- SwiftData Models über Actor-Grenzen reichen (Race/Crashes/Undefined Behavior).

## How to work on this project (Setup + wo anfangen)
### Setup (lokal)
1. `BrainMesh.xcodeproj` öffnen.
2. Signing prüfen:
   - Bundle ID & iCloud Container müssen zusammenpassen (`iCloud.de.marcfechner.BrainMesh`): BrainMesh/BrainMesh.entitlements, BrainMesh/Settings/SyncRuntime.swift.
3. iCloud auf Gerät/Simulator:
   - Für echten CloudKit Sync braucht ein Gerät (Simulator CloudKit kann eingeschränkt sein) — **UNKNOWN**: aktuelles Test-Setup.
4. Run:
   - Beim Start: Container Init + Account Status Refresh (Log in Konsole): BrainMesh/BrainMeshApp.swift.

### Einstiegspunkte für neue Features
- New Model: `BrainMesh/Models/*` (und Schema-Liste in BrainMesh/BrainMeshApp.swift erweitern).
- New Screen: in passenden Modulordner, Navigation meist über Tab (ContentView) oder NavigationLink/Sheets aus Detail Screens.
- New background fetch: actor Loader in `Support/` oder Feature-Ordner + Registrierung in BrainMesh/Support/AppLoadersConfigurator.swift.

### Debugging Leitplanken
- CloudKit-Status sichtbar: Settings → Sync & Wartung (UI, BrainMesh/Settings/SyncMaintenanceView.swift + BrainMesh/Settings/SyncRuntime.swift).
- Rendering/Physics: BMLog.physics (siehe BrainMesh/Observability/BMObservability.swift + Logging in GraphCanvas Physik).

## Quick Wins (max. 10, konkret)
1. **Physics Pair Loop weiter begrenzen** (z.B. spatial partitioning / Barnes-Hut / grid binning) in BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift.
2. **Dictionary→Array Hot Path**: Positions/Velocities in GraphCanvas für simNodes als Array-Backed Storage (Key→Index Map einmal bauen) in BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift.
3. **Links in Detail Screens lazy-loaden**: replace full `@Query` with fetch-limited preview + “Alle anzeigen” via Loader (Startpunkte: BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift, BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift).
4. **Unified cancellation tokens** für `.task(id:)` Loads in Screens, die loader-basierte Snapshots nutzen (Beispiel: EntitiesHome/Stats already do parts; audit in BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift, BrainMesh/Stats/GraphStatsView/GraphStatsView.swift, BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift).
5. **Zentrale Logging-Schalter** (feature flags) für BMLog-Kategorien, um Debug overhead zu kontrollieren (BMObservability: BrainMesh/Observability/BMObservability.swift).
6. **Attachment Cache metrics + cleanup** in Settings weiter ausbauen (Sizes sind schon da: BrainMesh/Settings/SyncMaintenanceView.swift); ergänzen: “Clear stale localPath references” — **UNKNOWN** ob nötig.
7. **Search Index Consistency Tests**: kleine Debug-Utility (dev-only) um `*Folded` Felder zu auditieren (Models + BrainMesh/GraphBootstrap.swift).
8. **Reduce view invalidations**: prüfen ob häufig wechselnde States (z.B. `positions/velocities`) nur in Canvas/View, nicht im Screen-Host gehalten werden müssen (GraphCanvasScreen: BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift).
9. **Split**: die 2–3 größten UI-Dateien weiter in Subviews (Top Kandidaten siehe Architecture Notes: z.B. EntitiesHomeView, NodeImagesManageView).
10. **Release-Sync fallback visibility**: in UI noch deutlicher machen, wenn CloudKit init failte (StorageMode lokal-only) (siehe BrainMesh/BrainMeshApp.swift, BrainMesh/Settings/SyncRuntime.swift).
