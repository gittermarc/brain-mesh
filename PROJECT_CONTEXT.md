# PROJECT_CONTEXT

> Stand: 2026-02-18 (basierend auf Repository-Inhalt im ZIP)

## TL;DR
BrainMesh ist eine SwiftUI-App (Minimum **iOS 26.0**) zum Erstellen und Erkunden von Wissens-Graphen. Persistenz & Sync laufen über **SwiftData + CloudKit (private DB, `.automatic`)** (siehe `BrainMesh/BrainMeshApp.swift`). Die Kernobjekte sind Graphen, Entitäten, Attribute, Links und Anhänge; der Graph kann optional per Face ID/Passwort gesperrt werden.

## Key Concepts / Domänenbegriffe
- **Graph**: Workspace/Scope für Daten (Multi-Graph), optional geschützt. Modell: `BrainMesh/Models.swift` (`MetaGraph`).
- **Entität**: “Knoten” (z.B. Person/Projekt), gehört zu einem Graph (`graphID`). Modell: `BrainMesh/Models.swift` (`MetaEntity`).
- **Attribut**: Unterobjekt einer Entität (1:n), ebenfalls graph-scoped. Modell: `BrainMesh/Models.swift` (`MetaAttribute`, `MetaEntity.attributes`).
- **Link**: Kante zwischen zwei Nodes (Entität/Attribut), graph-scoped. Modell: `BrainMesh/Models.swift` (`MetaLink`, `NodeKind`).
- **Attachment**: Datei/Video/Galeriebild, hängt an Entität oder Attribut (Owner via `(ownerKindRaw, ownerID)` statt Relationship). Modell: `BrainMesh/Attachments/MetaAttachment.swift` (`MetaAttachment`, `AttachmentContentKind`).
- **Graph Scope / activeGraphID**: Aktiver Graph wird via `@AppStorage("BMActiveGraphID")` gehalten (z.B. `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`).
- **Hydration**: Hintergrundarbeit, die aus synchronisierten Bytes lokale Cache-Files erzeugt (z.B. Bild-/Attachment-Cache), um UI/Preview schnell zu machen. Siehe `BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`.
- **Lens / WorkMode**: Canvas-Filter/Interaktionsmodus (Explore/Edit etc.). Siehe `BrainMesh/GraphCanvas/GraphCanvasScreen.swift` und `BrainMesh/GraphCanvas/GraphCanvasTypes.swift`.

## Architecture Map
**UI (SwiftUI Views)**
- Root Tabs: `BrainMesh/ContentView.swift` (Tabs: Entitäten / Graph / Stats / Einstellungen)
- App orchestration (Startup, scenePhase, auto-hydration, auto-lock): `BrainMesh/AppRootView.swift`
- Home/Detail/Flows: `BrainMesh/Mainscreen/*`
- Graph Canvas: `BrainMesh/GraphCanvas/*`
- Stats: `BrainMesh/Stats/*`
- Settings: `BrainMesh/Settings/SettingsView.swift`
- Graph management: `BrainMesh/GraphPickerSheet.swift` + `BrainMesh/GraphPicker/*`
- Onboarding: `BrainMesh/Onboarding/*`

**Domain Model (SwiftData)**
- Schema + Container: `BrainMesh/BrainMeshApp.swift` (Schema: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`)
- Models: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`

**Data Access / Background Loaders (off-main Snapshots)**
- Pattern: actor + background `ModelContext` via `AnyModelContainer`, Rückgabe als value-only DTO.
- Beispiele:
  - `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - `BrainMesh/Mainscreen/NodePickerLoader.swift`
  - `BrainMesh/Attachments/MediaAllLoader.swift`

**Caching & Filesystem**
- Images: `BrainMesh/ImageStore.swift` (Memory + Disk: Application Support / `BrainMeshImages`)
- Attachments: `BrainMesh/Attachments/AttachmentStore.swift` (Application Support / `BrainMeshAttachments`)
- Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift` (NSCache + Disk + QuickLook/AV/ImageIO)

**Security & Coordinators**
- Graph Lock (Face ID / Passwort): `BrainMesh/Security/*` (z.B. `GraphLockCoordinator.swift`, `GraphUnlockView.swift`)
- System modal tracking: `BrainMesh/Support/SystemModalCoordinator.swift` (Picker/FaceID Edge Case)
- Appearance: `BrainMesh/Appearance/*`

**Observability**
- `BrainMesh/Observability/BMObservability.swift` (Logger + simple Timing helper)

## Folder Map
- `BrainMesh/Appearance/` — UI-Appearance/Theme Models + Store (AppStorage/EnvironmentObject)
- `BrainMesh/Attachments/` — Anhänge: Modell (MetaAttachment), Cache, Hydration, Thumbnails, Preview/Import
- `BrainMesh/GraphCanvas/` — Interaktiver Graph (Canvas), Physics/Rendering, DataLoader/Snapshots
- `BrainMesh/GraphPicker/` — Graph-Auswahl/Management (Rename/Delete/Dedupe Services, Rows)
- `BrainMesh/Icons/` — Icon Picker (kuratierte SF Symbols, Recents, All Symbols Picker)
- `BrainMesh/Images/` — Bild-Import/Decode-Pipeline
- `BrainMesh/ImportProgress/` — UI für Import-Progress/Status (z.B. bei Attachments/Media)
- `BrainMesh/Mainscreen/` — Home + Detail-Screens (Entities/Attributes), Links, Bulk-Aktionen, NodeDetailShared
- `BrainMesh/Observability/` — Micro-Logging/Timing Helpers (os.Logger, Duration)
- `BrainMesh/Onboarding/` — Onboarding Coordinator + Sheet + Steps/Progress
- `BrainMesh/PhotoGallery/` — Detail-only Galerie (MetaAttachment.contentKind == .galleryImage), Browser/Viewer
- `BrainMesh/Security/` — Graph Lock (Biometrie/Passwort), Crypto, Unlock/SetPassword Sheets
- `BrainMesh/Settings/` — Settings UI (Wartung, Appearance, Onboarding Trigger, Cache-Tools)
- `BrainMesh/Stats/` — Stats Tab: Loader + Service + UI Komponenten (KPI/Charts/Trends)
- `BrainMesh/Support/` — App-weite kleine Helper/Coordinators (z.B. SystemModalCoordinator)

## Data Model Map (SwiftData)
> Quelle: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`

### `MetaGraph` (`BrainMesh/Models.swift`)
- Felder: `id`, `createdAt`, `name`, `nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Derived: `isProtected`, `isPasswordConfigured`

### `MetaEntity` (`BrainMesh/Models.swift`)
- Felder: `id`, `graphID` (optional, Migration), `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`
- Relationship: `attributes: [MetaAttribute]?` mit `@Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner)` (Inverse wird nur hier angegeben)
- Convenience: `attributesList` (de-dupe nach `id`), `addAttribute/removeAttribute`
- **Hinweis:** `lock*`-Felder existieren auch auf `MetaEntity`, scheinen aber aktuell **nicht** im UI verwendet zu werden → **UNKNOWN/evtl. geplant** (siehe “Open Questions”).

### `MetaAttribute` (`BrainMesh/Models.swift`)
- Felder: `id`, `graphID`, `name`, `nameFolded`, `notes`, `iconSymbolName`, `imageData`, `imagePath`, `searchLabelFolded`
- Owner: `owner: MetaEntity?` **ohne** `@Relationship` Macro (Kommentar: “KEIN inverse hier, sonst Macro-Zirkularität”)

### `MetaLink` (`BrainMesh/Models.swift`)
- Felder: `id`, `createdAt`, `note`, `graphID`
- Source/Target: `sourceKindRaw/sourceID/sourceLabel`, `targetKindRaw/targetID/targetLabel`
- Derived: `sourceKind`, `targetKind` (via `NodeKind`)

### `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
- Felder: `id`, `createdAt`, `graphID`
- Owner (ohne Relationship): `ownerKindRaw`, `ownerID`
- Inhalt: `contentKindRaw` (`file` / `video` / `galleryImage`)
- Metadaten: `title`, `originalFilename`, `contentTypeIdentifier` (UTType), `fileExtension`, `byteCount`
- Bytes: `fileData` mit `@Attribute(.externalStorage)` (SwiftData external storage; CloudKit “asset style”)
- Lokaler Cache: `localPath` (Application Support)

## Sync/Storage
> Fakten aus `BrainMesh/BrainMeshApp.swift`, `BrainMesh/BrainMesh.entitlements`, `BrainMesh/Info.plist`

- Persistenz: SwiftData `ModelContainer` mit Schema (siehe oben).
- Cloud Sync: `ModelConfiguration(schema: ..., cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`.
- Fallback: In **Release** wird bei CloudKit-Init-Fehler auf lokale Konfiguration ohne CloudKit zurückgefallen (siehe `#if DEBUG`-Block in `BrainMesh/BrainMeshApp.swift`).
- iCloud Container: `iCloud.de.marcfechner.BrainMesh` (siehe `BrainMesh/BrainMesh.entitlements`).
- Background Mode: `remote-notification` (siehe `BrainMesh/Info.plist`) → typischerweise für CloudKit-Push/SwiftData Sync, **keine** eigene Push-Implementierung im Code gefunden.
- Attachments: `MetaAttachment.fileData` ist external storage; lokale Cache-Files werden über `AttachmentHydrator` & `AttachmentStore` erzeugt/verwaltet.
- Images: Hauptbilder werden als `imageData` im Model gehalten und über `ImageHydrator` in Disk-Cache (`ImageStore`) “hydratisiert”.

### Migration / Legacy
- Graph scoping migration für alte Records ohne `graphID`:
  - `BrainMesh/GraphBootstrap.swift` (Entities/Attributes/Links → Default-Graph)
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (Attachments: owner-scoped Migration ohne OR-Predicate)
- App-Startup ruft `GraphBootstrap` auf: `BrainMesh/AppRootView.swift` (`bootstrapGraphing()`).

## UI Map (Screens, Navigation, wichtige Sheets)
### Root Navigation
- TabView: `BrainMesh/ContentView.swift`
  - **Entitäten**: `BrainMesh/Mainscreen/EntitiesHomeView.swift`
  - **Graph**: `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
  - **Stats**: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - **Einstellungen**: `BrainMesh/Settings/SettingsView.swift` (in `NavigationStack`)

### Wichtige Flows (Auswahl)
- Graph wechseln / verwalten: `BrainMesh/GraphPickerSheet.swift` (+ UI in `BrainMesh/GraphPicker/*`)
- Entität hinzufügen: Sheet `AddEntityView` (öffnet aus `EntitiesHomeView`)
- Detailansichten:
  - Entität: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - Attribut: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Shared Komponenten: `BrainMesh/Mainscreen/NodeDetailShared/*`
- Links:
  - Link hinzufügen: `BrainMesh/Mainscreen/AddLinkView.swift`
  - Bulk-Link: `BrainMesh/Mainscreen/BulkLinkView.swift`
  - Query-Building: `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`
- Anhänge / Medien:
  - Attachments Section: `BrainMesh/Attachments/AttachmentsSection*.swift`
  - Thumbnail/Preview: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`, `AttachmentPreviewSheet.swift`
  - Photo gallery (detail-only): `BrainMesh/PhotoGallery/*`

### Security UX
- Graph unlock / set password / security sheet: `BrainMesh/Security/*`
- AppRoot scenePhase + auto-lock debounce: `BrainMesh/AppRootView.swift`
- System picker edge-case handling: `BrainMesh/Support/SystemModalCoordinator.swift`

## Build & Configuration
- Xcode project: `BrainMesh/BrainMesh.xcodeproj`
- Targets (pbxproj): App + Unit Tests + UI Tests (`BrainMesh`, `BrainMeshTests`, `BrainMeshUITests`)
- Minimum iOS: **iOS 26.0** (Build Setting `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in `BrainMesh.xcodeproj/project.pbxproj`)
- Bundle ID: **de.marcfechner.BrainMesh** (pbxproj)
- Entitlements: `BrainMesh/BrainMesh.entitlements` (iCloud container + CloudKit + APS env)
- Info.plist: `BrainMesh/Info.plist` (FaceID usage + background remote-notification)
- SPM Dependencies: **keine** `Package.resolved` gefunden; pbxproj enthält keine `repositoryURL` → vermutlich keine externen Packages.

## Conventions (Naming, Patterns, Do/Don't)
### SwiftData / Queries
- **Do:** Store-translatable Predicates bevorzugen, OR vermeiden (siehe `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`, `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`).
- **Do:** Graph-scope konsequent als `graphID == gid` ausdrücken, statt `(graphID == nil || graphID == gid)`, wo Migration existiert.
- **Don't:** `@Model` Instanzen über Concurrency-Grenzen schicken. Stattdessen DTO/Snapshots (siehe `EntitiesHomeLoader.swift` Kommentar).

### Concurrency / Loader Pattern
- **Do:** actor-Loader mit `configure(container:)` in `BrainMesh/BrainMeshApp.swift` (detached, priority `.utility`), dann in Views `.task { await loader.load... }`.
- **Do:** Throttling bei teurer I/O-Arbeit (`AsyncLimiter` in `BrainMesh/Attachments/AttachmentThumbnailStore.swift`).

### UI Files
- Große Views werden in `+*.swift` Partial-Files gesplittet (z.B. `GraphCanvasScreen+*.swift`, `GraphStatsView+*.swift`, `AttachmentsSection+*.swift`).

## How to work on this project (Setup + Einstieg)
### Setup Checklist
- [ ] `BrainMesh/BrainMesh.xcodeproj` öffnen
- [ ] iOS Simulator/Device mit **iOS 26.0+** auswählen
- [ ] (Für Cloud Sync) iCloud in Xcode Signing & Capabilities aktiv, Container `iCloud.de.marcfechner.BrainMesh` muss existieren
- [ ] Build & Run
- [ ] Erster Start: AppRoot führt Graph-Bootstrap + Migration aus (`BrainMesh/AppRootView.swift`)

### Wo anfangen (für neue Devs)
- Datenmodell verstehen: `BrainMesh/Models.swift`, `BrainMesh/Attachments/MetaAttachment.swift`
- Root Navigation: `BrainMesh/ContentView.swift`, `BrainMesh/AppRootView.swift`
- Hot UI: `BrainMesh/Mainscreen/EntitiesHomeView.swift`, `BrainMesh/GraphCanvas/GraphCanvasScreen.swift`
- Loader Pattern anschauen: `BrainMesh/Mainscreen/EntitiesHomeLoader.swift`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`

## Quick Wins (max. 10, konkret)
1. **AsyncLimiter aus `AttachmentThumbnailStore.swift` extrahieren** nach `BrainMesh/Support/AsyncLimiter.swift` und überall importieren (nutzen: `ImageHydrator.swift`, `AttachmentHydrator.swift`, `AttachmentThumbnailStore.swift`). Vorteil: weniger “Utility in Random File”.
2. **Unbenutzten Code markieren/entfernen:** `BrainMesh/GraphSession.swift` scheint aktuell unreferenziert → entweder nutzen (z.B. als reactive activeGraph source) oder löschen.
3. **Lock-Felder auf Entity/Attribute evaluieren:** `MetaEntity.lock*` / `MetaAttribute.lock*` existieren, UI nutzt aber Graph-Lock (`BrainMesh/Security/*`). Entscheiden: implementieren oder entfernen (sonst Migrations-/Sync-Ballast).
4. **GraphBootstrap @MainActor Entlastung**: `GraphBootstrap.migrateLegacyRecordsIfNeeded` kann bei vielen Legacy-Records dauern. Option: in Hintergrund-Kontext (actor) + progress, UI nur “once” triggern.
5. **Konsequente DTO-Grenzen**: prüfen, ob irgendwo noch `@Model` aus Loader-Actor in UI gelangt (z.B. neue Features). Regel: nur IDs/DTOs.
6. **Thumbnail Disk Cache Cleanup Policy**: ergänzen: `AttachmentThumbnailStore` Disk-Cache (Settings) getrennt von AttachmentCache löschen.
7. **`imageData` Größenbudget enforce**: sicherstellen, dass alle Importpfade über `Images/ImageImportPipeline.swift` laufen (CloudKit pressure).
8. **Centralize file-system folder names**: `ImageStore.folderName`, `AttachmentStore.folderName` als Konstanten in `Support/StoragePaths.swift` (reduziert Drift).
9. **Logging Gate**: `BMLog` Kategorien erweitern (z.B. `thumb`, `hydrator`) und Debug/Release Policy vereinheitlichen.
10. **Tests für Migration**: 1–2 Unit Tests für `GraphBootstrap` / `AttachmentGraphIDMigration` (Target `BrainMeshTests`).

## Open Questions (UNKNOWNs)
- **Entity/Attribute Locking:** Lock-Felder auf `MetaEntity`/`MetaAttribute` wirken aktuell ungenutzt im UI (**UNKNOWN** ob geplant).
- **Collaboration/Sharing:** Keine direkte CloudKit Share/Collab-Implementierung im Code gefunden; Sync läuft über SwiftData CloudKit private DB (**UNKNOWN** ob später geplant).
- **Secrets Handling:** Keine `.xcconfig`/Secrets-Datei gefunden (**UNKNOWN**, ob es versteckt/extern gelöst ist).