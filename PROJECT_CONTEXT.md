# PROJECT_CONTEXT.md

## TL;DR
- App: **BrainMesh** (iOS / iPadOS, SwiftUI)
- Mindest-iOS: **26.0** (aus `BrainMesh.xcodeproj/project.pbxproj`)
- Persistence/Sync: **SwiftData** mit **CloudKit** (Private DB, `.automatic`) + Release-Fallback auf local-only

## Key Concepts / Domänenbegriffe
- **Graph (MetaGraph)**: Workspace / Wissensdatenbank. Mehrere Graphen möglich. Optionaler Zugriffsschutz (Biometrie/Passwort).
- **Entität (MetaEntity)**: „Ding“ im Graph (z.B. Person, Buch, Projekt). Hat Name, Notizen, optional Icon & Headerbild.
- **Attribut (MetaAttribute)**: gehört optional zu einer Entität (owner). Kann ebenfalls Notizen, Icon & Bild besitzen.
- **Link (MetaLink)**: Kante zwischen zwei Nodes (Entity/Attribute), speichert Source/Target IDs + Kind, Labels (denormalisiert) und optional `note`.
- **Details Schema**: Entität definiert frei konfigurierbare Felder (`MetaDetailFieldDefinition`); Attribute speichern Werte als `MetaDetailFieldValue`.
- **Attachments (MetaAttachment)**: Datei/Video/Galerie-Bilder, an Entity/Attribute „angehängt“ über `(ownerKindRaw, ownerID)`, Bytes in `.externalStorage`.
- **Folded Search**: case-/diacritic-insensitive Suchindizes (`nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`) via `BMSearch.fold(...)`.

## Architecture Map
Text-Map der wichtigsten Schichten/Module (Pfeil = Abhängigkeit):
- **App**: `BrainMeshApp.swift` → erstellt SwiftData `ModelContainer` (CloudKit), konfiguriert Loader (`Support/AppLoadersConfigurator.swift`) → `AppRootView.swift`
- **Root UI**: `AppRootView.swift` → `ContentView.swift` (TabView) → Feature-Screens (Entities / Graph / Stats / Settings)
- **Data Model**: `Models/*` + `Attachments/MetaAttachment.swift` (SwiftData `@Model`)
- **Sync/Storage Runtime**: `BrainMeshApp.swift` + `Settings/SyncRuntime.swift` + `GraphBootstrap.swift` (Migration/Backfills)
- **Background Loaders (Actors)**: z.B. `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`, `GraphCanvas/GraphCanvasDataLoader.swift`, `Stats/GraphStatsLoader.swift` → liefern Snapshot-DTOs (value-only) an UI
- **Caches/Stores**: `ImageStore.swift`, `Attachments/AttachmentStore.swift`, `ImageHydrator.swift`, `Attachments/AttachmentHydrator.swift`
- **Security/Pro**: `Security/*` (Graph Lock/Unlock), `Pro/*` (StoreKit Entitlements + Paywall)

## Folder Map
Top-Level Ordner in `BrainMesh/` (App Target):
- `Assets.xcassets/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Attachments/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `GraphCanvas/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `GraphPicker/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Icons/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Images/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `ImportProgress/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Mainscreen/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Models/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Observability/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Onboarding/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `PhotoGallery/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Pro/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Security/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Settings/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Stats/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)
- `Support/` → Zweck: **UNKNOWN** (siehe einzelne Dateien)

Konkret (aus Code ersichtlich):
- `Models/` → SwiftData-Modelle + Search Helpers (z.B. `Models/MetaEntity.swift`, `Models/BMSearch.swift`).
- `GraphCanvas/` → Graph Canvas UI + Loader + Types (z.B. `GraphCanvas/GraphCanvasView/*`, `GraphCanvas/GraphCanvasDataLoader.swift`).
- `Mainscreen/` → Entities/Attributes/Links UI, Create Flows, Pickers, Shared Detail Komponenten.
- `Stats/` → Stats UI + Service/Loader (`Stats/GraphStatsService/*`, `Stats/GraphStatsLoader.swift`).
- `Settings/` → Settings UI + Appearance/Display/Sync/Maintenance (`Settings/SettingsView.swift`).
- `Security/` → Graph Lock/Unlock + Security UI (`Security/GraphLock/*`, `Security/GraphUnlock/*`).
- `Pro/` → StoreKit / Entitlements / Paywall (`Pro/ProEntitlementStore.swift`, `Pro/ProPaywallView.swift`).
- `Attachments/` → Attachments Model, Import, Cache/Hydration, „Media“-Screens.
- `PhotoGallery/` → Detail-Galerie als Attachments `contentKind == .galleryImage` (z.B. `PhotoGallery/PhotoGallerySection.swift`).
- `Support/` → Utilities/Keys/Coordinators/Formatting/Small Services (z.B. `Support/BMAppStorageKeys.swift`, `Support/SystemModalCoordinator.swift`).
- `Observability/` → Logging/Timing (`Observability/BMObservability.swift`).
- `Icons/` → SF Symbols Picker UI (`Icons/IconPickerView.swift`).

## Data Model Map (SwiftData)
> Quelle: `BrainMeshApp.swift` Schema-Liste + jeweilige Model-Dateien in `Models/*` und `Attachments/*`.

### MetaGraph (`Models/MetaGraph.swift`)
- Fields: `id`, `createdAt`, `name`, `nameFolded`
- Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### MetaEntity (`Models/MetaEntity.swift`)
- Fields: `id`, `createdAt`, `graphID` (optional, Migration/Scope), `name`, `nameFolded`, `notes`, `notesFolded`
- Optional UI metadata: `iconSymbolName`, `imageData`, `imagePath`
- Relationships:
  - `attributes: [MetaAttribute]?` (cascade delete, inverse: `MetaAttribute.owner`)
  - `detailFields: [MetaDetailFieldDefinition]?` (cascade delete, inverse: `MetaDetailFieldDefinition.owner`)
- Convenience: `attributesList` / `detailFieldsList` dedup + sort (by `sortIndex`).

### MetaAttribute (`Models/MetaAttribute.swift`)
- Fields: `id`, `graphID`, `name`, `nameFolded`, `notes`, `notesFolded`, `searchLabelFolded`
- Optional UI metadata: `iconSymbolName`, `imageData`, `imagePath`
- Relationship: `owner: MetaEntity?` (set via inverse on Entity)
- Relationships: `detailValues: [MetaDetailFieldValue]?` (cascade delete, inverse: `MetaDetailFieldValue.attribute`)
- Derived: `displayName` = `"<entity> · <attribute>"` (falls owner gesetzt).

### MetaLink (`Models/MetaLink.swift`)
- Fields: `id`, `createdAt`, `graphID`
- Directed endpoints: `sourceKindRaw`, `sourceID`, `sourceLabel`, `targetKindRaw`, `targetID`, `targetLabel`
- Optional note: `note` + stored search index `noteFolded`

### Details Schema (`Models/DetailsModels.swift`)
- `MetaDetailFieldDefinition`: graph-scoped Field Definition pro Entity
  - Fields: `id`, `graphID`, `entityID`, `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - Relationship: `owner: MetaEntity?` (deleteRule: nullify, originalName: "entity")
- `MetaDetailFieldValue`: Wert pro Attribute+Field
  - Fields: `id`, `graphID`, `attributeID`, `fieldID`, typed values (`stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`)
  - Relationship: `attribute: MetaAttribute?` (inverse comes from `MetaAttribute.detailValues`)

### User Templates (`Models/MetaDetailsTemplate.swift`)
- Fields: `id`, `createdAt`, `graphID`, `name`, `nameFolded`, `fieldsJSON`
- `fieldsJSON` encodes `FieldDef { name, typeRaw, unit, options, isPinned }`

### Attachments (`Attachments/MetaAttachment.swift`)
- Fields: `id`, `createdAt`, `graphID`, `ownerKindRaw`, `ownerID`, `contentKindRaw`
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Storage: `fileData: Data?` marked as `@Attribute(.externalStorage)`
- Local cache: `localPath` (Application Support / BrainMeshAttachments)

## Sync/Storage
### SwiftData + CloudKit
- `BrainMeshApp.swift`: Schema + `ModelConfiguration(schema:..., cloudKitDatabase: .automatic)` → `ModelContainer` erstellt.
- Release-Fallback: wenn CloudKit init fehlschlägt, wird `ModelConfiguration(schema:...)` ohne CloudKit genutzt (local-only).
- `Settings/SyncRuntime.swift`: Oberfläche für „StorageMode“ (cloudKit vs local-only) + iCloud Account Status via `CKContainer.accountStatus()`.
- Entitlements: `BrainMesh/BrainMesh.entitlements` enthält iCloud Container + CloudKit Service + `aps-environment` (dev).
- Migration/Backfills: `GraphBootstrap.swift` verschiebt Legacy-Records ohne `graphID` in Default-Graph und backfilled `notesFolded`/`noteFolded`.

### Caches
- Bilder: `ImageStore.swift` (NSCache + Disk in Application Support / BrainMeshImages).
- Attachment cache: `Attachments/AttachmentStore.swift` (Disk in Application Support / BrainMeshAttachments).
- Hydration: `ImageHydrator.swift` + `Attachments/AttachmentHydrator.swift` erstellen/normalisieren Cache-Dateien nach Sync oder Cache-Miss.

### Offline-Verhalten
- **Systemverhalten**: SwiftData speichert lokal und synct über CloudKit, sobald verfügbar. App-spezifische Offline-Queues o.ä. sind im Code nicht ersichtlich. (kein eigenes Retry/Queue-System gefunden)

## UI Map (Hauptscreens + Navigation)
### Root Tabs (`ContentView.swift`)
- Tab 1: `EntitiesHomeView()`
- Tab 2: `GraphCanvasScreen()` (eigene `NavigationStack` im Screen)
- Tab 3: `GraphStatsView()` (Stats)
- Tab 4: `SettingsView(showDoneButton: false)` eingebettet in `NavigationStack`

### Global Modals (`AppRootView.swift`)
- Onboarding Sheet: `.sheet(isPresented: $onboarding.isPresented) { OnboardingSheetView() }`
- Graph Unlock Fullscreen: `.fullScreenCover(item: $graphLock.activeRequest) { GraphUnlockView(...) }`

### Entities
- `Mainscreen/EntitiesHome/EntitiesHomeView.swift`:
  - Searchable (Folded) + async reload via `EntitiesHomeLoader` (Snapshot)
  - Add Entity: `.sheet { AddEntityView() }`
  - Graph Picker: `.sheet { GraphPickerSheet() }`
  - Navigation to Entity detail: `EntitiesHomeList.swift` → `NavigationLink { EntityDetailRouteView(entityID:) }`
- Entity Detail: `Mainscreen/EntityDetail/EntityDetailView.swift` (großes File; nutzt NodeDetailShared Komponenten)

### Graph
- `GraphCanvas/GraphCanvasScreen/*`:
  - Loads graph snapshot via `GraphCanvasDataLoader` (off-main)
  - Canvas rendering + physics timer in `GraphCanvasView/*`
  - Inspector/Sheets/Peek Editing: siehe `GraphCanvasScreen+Inspector.swift`, `+DetailsPeek.swift`, `+Overlays.swift`
  - Cross-screen jump: `GraphJumpCoordinator` (request/consume) + `RootTabRouter` (tab switch)

### Stats
- `Stats/GraphStatsView/GraphStatsView.swift`: Dashboard + Sections (Header/KPI/Media/Structure/Trends)
- `Stats/GraphStatsLoader.swift`: Off-main snapshot via `GraphStatsService`

### Settings
- `Settings/SettingsView.swift` + Extensions: Appearance / Import / Sync / Maintenance / Help / Info / About
- Sync & Wartung Oberfläche nutzt `SyncRuntime` + Cache-Rebuild Aktionen (z.B. `ImageHydrator.forceRebuild()`)

## Build & Configuration
- Xcode-Projekt: `BrainMesh.xcodeproj`
- Info.plist: `BrainMesh/Info.plist` (u.a. `NSFaceIDUsageDescription`, `UIBackgroundModes` mit `remote-notification`, Pro-Product Keys)
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit Container + APS env)
- Dependencies: Keine Swift Package Dependencies in `project.pbxproj` (packageProductDependencies leer).
- Secrets Handling: **UNKNOWN** (keine `.xcconfig`/Secrets-Dateien im ZIP gefunden).

## Conventions
- SwiftData `@Model` nicht über Concurrency-Boundaries geben → Loader liefern value-only Snapshots (z.B. `EntitiesHomeRow`, `GraphCanvasSnapshot`).
- Große Views/Features oft in Partial-Files via `+Something.swift` gesplittet (z.B. `GraphCanvasScreen+Overlays.swift`, `GraphCanvasView+Physics.swift`).
- Search: immer über gespeicherte Folded-Felder (`nameFolded`, `notesFolded`, `noteFolded`) + `BMSearch.fold(...)` arbeiten.
- Programmatic Navigation/Tab switch über `RootTabRouter` + `GraphJumpCoordinator` (kein globaler NavigationState).

## How to work on this project
### Setup (lokal)
1. `BrainMesh.xcodeproj` öffnen (Xcode 26.x wegen iOS 26 Deployment Target).
2. Signing-Team setzen, Bundle ID prüfen (`de.marcfechner.BrainMesh`).
3. iCloud/CloudKit Capabilities aktivieren (muss zu `BrainMesh.entitlements` passen).
4. Run: erstes Launch erzeugt Default-Graph (`GraphBootstrap.ensureAtLeastOneGraph`).

### Wenn du ein neues SwiftData Model hinzufügst
- Model-Datei in `Models/` (oder Feature-Folder) anlegen, mit `@Model` annotieren.
- Schema-Liste in `BrainMeshApp.swift` ergänzen (sonst ist es nicht im Container).
- Migration/Backfill prüfen: wenn neue Felder „Index“-Charakter haben (folded), ggf. `GraphBootstrap` ergänzen.

### Wenn du einen neuen Background-Loader brauchst
- Actor anlegen (Pattern siehe `EntitiesHomeLoader`, `GraphCanvasDataLoader`).
- `Support/AppLoadersConfigurator.swift` erweitern, damit er den Loader konfiguriert (Container injiziert).
- UI: niemals `@Model` aus dem Loader zurückgeben; stattdessen Snapshot DTO (Sendable / @unchecked Sendable).

## Quick Wins (max 10)
1. **Link-Note Search N+1 reduzieren** in `Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` (Abschnitt „Resolve entity endpoints“/„Resolve attribute endpoints“): batch-fetch statt per-ID FetchDescriptor Schleife.
2. **Task.detached reduzieren / Cancellation vererben**: `Stats/GraphStatsLoader.swift`, `ImageHydrator.swift`, `Attachments/AttachmentHydrator.swift`, `Support/AppLoadersConfigurator.swift`, `Mainscreen/LinkCleanup.swift` (NodeRenameService).
3. **GraphCanvas Physik skalieren**: `GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift` (O(n²) Paarloop). Weiteres Capping/Spatial Hashing für große Graphen.
4. **GraphSession dead code prüfen**: `GraphSession.swift` wird im Projekt nicht referenziert (grep im ZIP zeigt keine usage) → entfernen falls wirklich ungenutzt.
5. **Search-Feld Backfills/Migration zentralisieren**: `GraphBootstrap.swift` deckt notesFolded/noteFolded ab; wenn weitere Indizes kommen, gleiche Pattern beibehalten.
6. **Index/Cache Invalidations standardisieren**: mehrere TTLs und per-screen caches (z.B. EntitiesHome counts TTL) dokumentieren & ggf. zentral in `Support/` kapseln.
7. **Pro-Produkt IDs**: `Info.plist` Defaults ("01"/"02") sind offensichtlich Platzhalter → in Release Builds per Build Setting/Config injizieren.
8. **Observability ausweiten**: `Observability/BMObservability.swift` existiert; Stats/Loader könnten in Debug den Fetch/Count Aufwand loggen (Rolling windows, ähnlich Physics).
9. **Attachment preview path normalization**: `AttachmentStore.ensurePreviewURL` mutiert `localPath` im MainActor; prüfen ob das im List/Scroll zu häufig triggert.
10. **Große Files splitten** (siehe Big Files List in ARCHITECTURE_NOTES.md) um Testbarkeit/Ownership zu verbessern.
