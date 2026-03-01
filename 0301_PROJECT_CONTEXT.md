# PROJECT_CONTEXT.md

## TL;DR
BrainMesh ist eine **iOS‑App (iPhone/iPad)** zum Modellieren von Wissen als **Graph**: Du legst **Entitäten** an, gibst ihnen **Attribute**, verknüpfst alles über **Links**, hängst **Anhänge/Medien** dran und kannst mehrere **Graphen (Workspaces)** verwalten. Persistenz läuft über **SwiftData**, mit **CloudKit (Private DB) Sync** sofern iCloud/Entitlements passen. Deployment Target: **iOS 26.0** (`BrainMesh.xcodeproj/project.pbxproj`).

## Key Concepts / Domänenbegriffe
- **Graph**: eigenständiger Workspace / Wissensdatenbank (`MetaGraph`, `BrainMesh/Models/MetaGraph.swift`).
- **Entität**: Knoten-Typ 1 (z.B. Person, Projekt, Idee) (`MetaEntity`, `BrainMesh/Models/MetaEntity.swift`).
- **Attribut**: Knoten-Typ 2 (gehört zu einer Entität) (`MetaAttribute`, `BrainMesh/Models/MetaAttribute.swift`).
- **Link**: Kante zwischen zwei Nodes (Entity↔Entity oder Attribute↔…); speichert IDs + Labels + optional Notiz (`MetaLink`, `BrainMesh/Models/MetaLink.swift`).
- **Details Schema**: pro Entität definierbare Felder (z.B. Datum, Zahl, Auswahl), die Attribute‑Werte bekommen (`MetaDetailFieldDefinition`/`MetaDetailFieldValue`, `BrainMesh/Models/DetailsModels.swift`).
- **Attachment**: Datei/Video/Gallery‑Image, hängt an Entity/Attribute, bytes via externalStorage (`MetaAttachment`, `BrainMesh/Attachments/MetaAttachment.swift`).
- **Active Graph**: aktuell gewählter Workspace, gespeichert in `@AppStorage(BMAppStorageKeys.activeGraphID)` (`BrainMesh/Support/BMAppStorageKeys.swift`).
- **Pro**: Abo‑basierte Freischaltung (u.a. mehr Graphen, Graph‑Schutz) (`BrainMesh/Pro/*`).

## Architecture Map (Layer/Module + Verantwortlichkeiten + Abhängigkeiten)
**1) App/Composition (SwiftUI Scene + DI via EnvironmentObjects)**
- `BrainMesh/BrainMeshApp.swift`
  - baut SwiftData Schema + `ModelContainer` (CloudKit `.automatic`, Release-Fallback local-only)
  - injectet Stores/Coordinators via `.environmentObject(...)`
  - startet Loader/Hydrator-Konfiguration (`BrainMesh/Support/AppLoadersConfigurator.swift`)

**2) Persistence/Model (SwiftData @Model + Search-Indices)**
- SwiftData Models in `BrainMesh/Models/*` + `BrainMesh/Attachments/MetaAttachment.swift`
- Such-Indices als gespeicherte “folded” Strings (`BMSearch.fold`) in Models (`BrainMesh/Models/BMSearch.swift`)

**3) Background Loaders/Hydrators (Actors + Snapshot DTOs)**
- Pattern: Actor erstellt **eigenen** `ModelContext` aus `AnyModelContainer`, liefert **Value‑Snapshots** an UI.
  - `AnyModelContainer` Wrapper: `BrainMesh/Support/AnyModelContainer.swift`
  - Loader-Konfiguration zentral: `BrainMesh/Support/AppLoadersConfigurator.swift`
- Beispiele:
  - Entities Home Snapshot: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
  - Graph Canvas Snapshot: `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`
  - Stats Snapshot: `BrainMesh/Stats/GraphStatsLoader.swift`
  - Hydration/Cache: `BrainMesh/ImageHydrator.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`

**4) UI (SwiftUI Views, Flows, Navigation)**
- Root/Navigation: `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`
- Feature-Screens: `BrainMesh/Mainscreen/*`, `BrainMesh/GraphCanvas/*`, `BrainMesh/Stats/*`, `BrainMesh/Settings/*`, `BrainMesh/GraphPicker/*`, `BrainMesh/GraphTransfer/*`

**5) Services/Utilities**
- Stats “domain service”: `BrainMesh/Stats/GraphStatsService/*`
- Export/Import: `BrainMesh/GraphTransfer/GraphTransferService/*`
- Security: `BrainMesh/Security/*`
- Observability: `BrainMesh/Observability/BMObservability.swift` (OSLog Kategorien + Timer helper)

Abhängigkeiten (grob):
- UI → Stores/Coordinators/Loaders → SwiftData Models
- Hydrators/Loaders → `AnyModelContainer` → SwiftData `ModelContainer`
- UI darf SwiftData Models halten (im Main `ModelContext`), aber Loader geben **keine @Model Instanzen** an UI zurück (Value‑DTOs).

## Folder Map (Ordner → Zweck)
- `BrainMesh/Models/` — SwiftData Models + Search Helpers (z.B. `MetaEntity`, `BMSearch`).
- `BrainMesh/Mainscreen/` — “Entitäten” Tab: Home, Create, Detail, Shared Detail-Komponenten.
- `BrainMesh/GraphCanvas/` — “Graph” Tab: Canvas Rendering + Screen-Logik + DataLoader.
- `BrainMesh/Stats/` — “Stats” Tab: Loader + Service + UI Components.
- `BrainMesh/Settings/` — Settings Hub + Sections (Sync, Appearance, Display, Import, Maintenance).
- `BrainMesh/Attachments/` — Datei/Video/Gallery‑Image Attachments: Import, Preview, Cache/Hydration.
- `BrainMesh/PhotoGallery/` — Gallery UI (zusätzliche Bilder in Details).
- `BrainMesh/GraphPicker/` — Graph Auswahl/Management (rename, delete, dedupe).
- `BrainMesh/GraphTransfer/` — Export/Import Flows (bmgraph).
- `BrainMesh/Security/` — Graph Lock/Unlock + Security Sheet (Biometrics/Passwort).
- `BrainMesh/Onboarding/` — Onboarding Sheet + Progress.
- `BrainMesh/Support/` — Shared Helpers (AppStorage Keys, Coordinators, throttling, loaders config).
- `BrainMesh/Observability/` — Logging/Timing Helpers.
- `BrainMesh/Icons/` — SF Symbols picker + Icon Katalogdaten.

## Data Model Map (Entities, Relationships, wichtige Felder)
### SwiftData Schema (Quelle)
- Schema wird in `BrainMesh/BrainMeshApp.swift` gebaut:
  - `MetaGraph`
  - `MetaEntity`
  - `MetaAttribute`
  - `MetaLink`
  - `MetaAttachment`
  - `MetaDetailFieldDefinition`
  - `MetaDetailFieldValue`
  - `MetaDetailsTemplate`

### Graph / Workspace
- `MetaGraph` (`BrainMesh/Models/MetaGraph.swift`)
  - `id: UUID`, `createdAt: Date`, `name`, `nameFolded`
  - Security: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`

### Entity
- `MetaEntity` (`BrainMesh/Models/MetaEntity.swift`)
  - Scope: `graphID: UUID?` (optional für Migration/Legacy)
  - UI: `iconSymbolName`, `imageData` (synced), `imagePath` (lokaler Cache)
  - Text: `name/nameFolded`, `notes/notesFolded`
  - Relationships:
    - `attributes` (`@Relationship(deleteRule: .cascade, inverse: \MetaAttribute.owner)`)
    - `detailFields` (`@Relationship(deleteRule: .cascade, inverse: \MetaDetailFieldDefinition.owner)`)

### Attribute
- `MetaAttribute` (`BrainMesh/Models/MetaAttribute.swift`)
  - Scope: `graphID: UUID?`
  - Owner: `owner: MetaEntity?` (keine inverse hier; inverse ist auf Entity-Seite)
  - UI: `iconSymbolName`, `imageData`, `imagePath`
  - Text: `name/nameFolded`, `notes/notesFolded`, `searchLabelFolded` (Entity · Attribute)
  - Relationship:
    - `detailValues` (`@Relationship(deleteRule: .cascade, inverse: \MetaDetailFieldValue.attribute)`)

### Link
- `MetaLink` (`BrainMesh/Models/MetaLink.swift`)
  - Keine SwiftData Relationships (IDs + Labels stattdessen; “macro cycles” vermeiden)
  - Scope: `graphID: UUID?`
  - Endpoints: `sourceKindRaw/sourceID/sourceLabel`, `targetKindRaw/targetID/targetLabel`
  - Note: `note` + `noteFolded` (Suchindex)

### Details Schema + Werte
- `MetaDetailFieldDefinition` (`BrainMesh/Models/DetailsModels.swift`)
  - `owner: MetaEntity?` (`@Relationship(deleteRule: .nullify, originalName: "entity")`)
  - `entityID` (scalar), `graphID`, `name/nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
- `MetaDetailFieldValue` (`BrainMesh/Models/DetailsModels.swift`)
  - `attribute: MetaAttribute?` (inverse kommt von Attribute.detailValues)
  - Scalars: `attributeID`, `fieldID`, `graphID`
  - Typed storage: `stringValue/intValue/doubleValue/dateValue/boolValue`

### Templates
- `MetaDetailsTemplate` (`BrainMesh/Models/MetaDetailsTemplate.swift`)
  - `graphID`, `name/nameFolded`, `fieldsJSON` (JSON Array)

### Attachments
- `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`)
  - Scope: `graphID`
  - Owner: `ownerKindRaw + ownerID` (keine Relationships)
  - Payload: `@Attribute(.externalStorage) fileData`
  - Cache: `localPath` (AppSupport/BrainMeshAttachments), Metadaten (UTType, filename, size, kind)

## Sync/Storage
### SwiftData + CloudKit
- `BrainMesh/BrainMeshApp.swift`
  - `ModelConfiguration(schema: ..., cloudKitDatabase: .automatic)` → CloudKit Private DB
  - DEBUG: CloudKit‑Init Failure → `fatalError(...)`
  - Release: CloudKit‑Init Failure → Fallback auf `ModelConfiguration(schema: schema)` (local-only) + `SyncRuntime.shared.setStorageMode(.localOnly)`

### iCloud Container / Entitlements / Background
- Entitlements: `BrainMesh/BrainMesh.entitlements`
  - `com.apple.developer.icloud-container-identifiers`: `iCloud.de.marcfechner.BrainMesh`
  - `com.apple.developer.icloud-services`: `CloudKit`
  - `aps-environment`: `development` (**Achtung**: Release/Production Handling ist **UNKNOWN** ohne CI/Build-Config Setup)
- Runtime Anzeige + AccountStatus:
  - `SyncRuntime.containerIdentifier` und `refreshAccountStatus()` in `BrainMesh/Settings/SyncRuntime.swift`
- `Info.plist`: `UIBackgroundModes = remote-notification` (`BrainMesh/Info.plist`)

### Lokale Caches (nicht SwiftData)
- Bilder:
  - Disk cache: `Application Support/BrainMeshImages` (`BrainMesh/ImageStore.swift`)
  - Hydration: `BrainMesh/ImageHydrator.swift` schreibt deterministische `"<id>.jpg"` Dateien und setzt `imagePath`
- Attachments:
  - Disk cache: `Application Support/BrainMeshAttachments` (via `AttachmentStore`, siehe `BrainMesh/Attachments/AttachmentHydrator.swift` und `BrainMesh/Attachments/AttachmentStore.swift`)
  - `MetaAttachment.fileData` ist externalStorage (CloudKit‑freundlicher)

### Migration / Legacy
- Multi‑Graph Migration:
  - `GraphBootstrap.migrateLegacyRecordsIfNeeded(...)` setzt fehlendes `graphID` (Entities/Attributes/Links) (`BrainMesh/GraphBootstrap.swift`)
- Search index backfill:
  - `GraphBootstrap.backfillFoldedNotesIfNeeded(...)` setzt fehlende `notesFolded/noteFolded` (`BrainMesh/GraphBootstrap.swift`)
- Attachments GraphID Migration:
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` (**Details hier: siehe Datei; bei weiterem Audit ggf. erweitern**)

### Offline-Verhalten
- SwiftData+CloudKit speichert lokal und sync’t später — konkrete Konflikt-/Merge-Policy ist **UNKNOWN** (keine explizite Policy-Konfiguration im Projekt gefunden).

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
### Root
- `BrainMesh/AppRootView.swift`
  - hostet `ContentView()` (Tabs)
  - Onboarding `.sheet` (`OnboardingSheetView`)
  - Graph Unlock `.fullScreenCover(item:)` (`GraphUnlockView`)
  - Startup: `GraphBootstrap.ensureAtLeastOneGraph`, Lock enforcement, Auto‑Image hydration
- `BrainMesh/ContentView.swift` — `TabView`:
  - Tab 1: `EntitiesHomeView()` (mit eigener `NavigationStack` in der View)
  - Tab 2: `GraphCanvasScreen()`
  - Tab 3: `GraphStatsView()`
  - Tab 4: `SettingsView` innerhalb `NavigationStack`

### Entities (Tab)
- Home/List: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - list rows kommen aus `EntitiesHomeLoader` (Snapshot) statt @Query heavy lists
  - Sheets: `AddEntityView`, `GraphPickerSheet`, Display sheet
- Detail:
  - Entity: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - Attribute: `BrainMesh/Mainscreen/AttributeDetail/*`
  - Shared components: `BrainMesh/Mainscreen/NodeDetailShared/*`

### Graph (Tab)
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ Extensions)
  - data load via `GraphCanvasDataLoader` (`BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift`)
  - rendering via `GraphCanvasView` (`BrainMesh/GraphCanvas/GraphCanvasView/*`)
  - Jump handling über `GraphJumpCoordinator` (`BrainMesh/GraphJumpCoordinator.swift`)

### Stats (Tab)
- `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` (+ Extensions)
  - background load: `GraphStatsLoader` (`BrainMesh/Stats/GraphStatsLoader.swift`)
  - compute: `GraphStatsService` (`BrainMesh/Stats/GraphStatsService/*`)

### Settings (Tab)
- `BrainMesh/Settings/SettingsView.swift` (+ Section Extensions)
  - Appearance: `BrainMesh/Settings/Appearance/*` + `AppearanceStore`
  - Display: `BrainMesh/Settings/Display/*` + `DisplaySettingsStore` (Presets + Overrides)
  - Sync/Maintenance: `BrainMesh/Settings/SyncRuntime.swift`, `SettingsView+MaintenanceSection.swift`, etc.
  - Import settings: `BrainMesh/Settings/ImportSettingsView.swift`

### Graph Management / Security / Pro
- Graph Picker Sheet: `BrainMesh/GraphPickerSheet.swift` + `BrainMesh/GraphPicker/*`
  - Pro gating: `ProLimits.freeGraphLimit` in `BrainMesh/Pro/ProFeature.swift`
- Graph Security UI: `BrainMesh/Security/GraphSecuritySheet.swift` + lock/unlock flow in `BrainMesh/Security/*`
- Pro Paywall: `BrainMesh/Pro/ProPaywallView.swift`, `BrainMesh/Pro/ProCenterView.swift`, StoreKit: `BrainMesh/Pro/ProEntitlementStore.swift`

### Export/Import
- UI: `BrainMesh/GraphTransfer/GraphTransferView/*`
- Service: `BrainMesh/GraphTransfer/GraphTransferService/*`
- File type:
  - UTType in `BrainMesh/Info.plist` → `de.marcfechner.brainmesh.graph`, Extension `.bmgraph`

## Build & Configuration
- Xcode Project: `BrainMesh.xcodeproj/project.pbxproj`
  - Deployment target: `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
  - Default actor isolation: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  - Bundle IDs:
    - App: `de.marcfechner.BrainMesh`
    - Tests: `de.marcfechner.BrainMeshTests`, `de.marcfechner.BrainMeshUITests`
  - Entitlements: `CODE_SIGN_ENTITLEMENTS = BrainMesh/BrainMesh.entitlements`
- `BrainMesh/Info.plist`
  - Pro Produkt‑IDs overridable: `BM_PRO_SUBSCRIPTION_ID_01`, `BM_PRO_SUBSCRIPTION_ID_02` (default “01”/“02”)
  - `NSFaceIDUsageDescription` (Graph‑Unlock)
  - Background mode remote notification
- StoreKit Test config: `BrainMesh/BrainMesh Pro.storekit` (für Xcode StoreKit Configuration; Release-Verhalten **UNKNOWN** ohne Build‑Phasen/Flags)

SPM / externe Dependencies:
- Keine `Package.resolved` / keine `XCRemoteSwiftPackageReference` gefunden → **UNKNOWN** ob absichtlich “no deps” oder via anderer Mechanik.

Secrets-Handling:
- Keine `.xcconfig`/Secrets‑Dateien im Archiv gefunden → **UNKNOWN** ob es externe Secrets gibt. (Im aktuellen Tree sind keine API Keys erkennbar.)

## Conventions (Naming, Patterns, Do/Don’t)
- **Kein SwiftData fetch im Render-Pfad**:
  - Graph Canvas cached Labels/Images (`labelCache/imagePathCache/iconSymbolCache`) in `GraphCanvasScreen.swift`
  - `ImageStore` warnt explizit: `loadUIImage(path:)` nicht aus `body` aufrufen (`BrainMesh/ImageStore.swift`)
- **Background work über Actors + Snapshot DTOs**:
  - z.B. `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`
  - UI commit in einem Rutsch (stale-result guard) z.B. `GraphCanvasScreen+Loading.swift`
- **Search indices speichern**:
  - `nameFolded/notesFolded/noteFolded/searchLabelFolded` + `BMSearch.fold` (Models + `BrainMesh/Models/BMSearch.swift`)
- **Centralize UserDefaults keys**:
  - `BMAppStorageKeys` statt string literals (`BrainMesh/Support/BMAppStorageKeys.swift`)
- **Default Actor Isolation: MainActor**:
  - Services/Loaders, die off-main laufen sollen, explizit `nonisolated`/Actor/Task.detached nutzen (siehe `GraphStatsService`, `GraphStatsLoader`).

## How to work on this project (Setup Steps + wo anfangen)
### Lokal bauen
1. `BrainMesh.xcodeproj` in Xcode öffnen.
2. Signing/Team setzen für Target `BrainMesh` (**not in repo; per-Dev Setup**).
3. iCloud/CloudKit Capability aktivieren und Container `iCloud.de.marcfechner.BrainMesh` sicherstellen (`BrainMesh/BrainMesh.entitlements` + `SyncRuntime.containerIdentifier`).
4. Für Pro/Paywall lokal: optional Xcode StoreKit Configuration `BrainMesh/BrainMesh Pro.storekit` auswählen.
5. Run auf iOS 26 Simulator/Device.

### Wo anfangen bei einem neuen Feature
- UI‑Feature im jeweiligen Tab:
  - Entities: `BrainMesh/Mainscreen/*`
  - Graph: `BrainMesh/GraphCanvas/*`
  - Stats: `BrainMesh/Stats/*`
  - Settings: `BrainMesh/Settings/*`
- Brauchst du “heavy data”?
  - erst überlegen: **Loader Actor + Snapshot** statt direkt `@Query`/`fetch` im View.
  - Loader konfigurieren in `BrainMesh/Support/AppLoadersConfigurator.swift`
- Modelländerungen:
  - SwiftData Models in `BrainMesh/Models/*` (oder `Attachments/MetaAttachment.swift`)
  - Achtung: CloudKit Schema Migration (automatisch) kann riskant sein → siehe Architektur Notes.

## Quick Wins (max. 10, konkret, umsetzbar)
1. **Graph expand off-main**: `GraphCanvasScreen+Expand.swift` macht `modelContext.fetch` auf MainActor → expand Snapshot in `GraphCanvasDataLoader` verlagern.
2. **EntitiesHome Link‑Note Search optimieren**: In `EntitiesHomeLoader.fetchEntities(...)` werden Link‑Endpoint Entities/Attributes teils per‑ID einzeln gefetcht (N+1) → batch/chunk fetch oder “placeholder rows”.
3. **Task.detached Review**: Hydrators (`ImageHydrator.swift`, `AttachmentHydrator.swift`, `GraphStatsLoader.swift`) nutzen `Task.detached` → prüfen, wo cancellation inheritance wichtig ist.
4. **Cancellation Checks in Hydrators**: `ImageHydrator.hydrate(...)` iteriert ohne `Task.checkCancellation()` → bei großen Libraries evtl. unnötige Arbeit.
5. **Loader Metrics**: `BMLog.load/expand/physics` nutzen, um ms + node/link counts systematisch zu loggen (GraphCanvas already does; EntitiesHome/Stats ggf. ergänzen).
6. **@unchecked Sendable minimieren**: Snapshot DTOs / ViewModels (`GraphCanvasSnapshot`, `GraphTransferViewModel`) prüfen und wo möglich `Sendable` korrekt machen.
7. **Cache TTL Tuning**: EntitiesHome counts cache TTL ist 8s (`EntitiesHomeLoader.swift`) — ggf. profilieren, ob zu kurz/lang bei großen Datensätzen.
8. **CloudKit Fallback Sichtbarkeit**: `SyncRuntime.storageMode` wird gesetzt, aber UI/UX der Konsequenzen (read‑only? warnings?) ist **UNKNOWN** → ggf. deutlicher machen.
9. **Entitlements aps-environment**: aktuell `development` (`BrainMesh.entitlements`) — Release/Production Setup prüfen, damit Push/CK korrekt.
10. **Project hygiene**: `Models.swift` ist leerer “shim” (`BrainMesh/Models/Models.swift`) — ok, aber bei neuen Devs im Setup erwähnen (done).

## Big Files / Hot Files (Quick Glance)
(Full analysis + Refactor Map siehe `ARCHITECTURE_NOTES.md`.)

Top 10 Swift files nach Zeilen:
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift` — **499 LoC**
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` — **474 LoC**
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader.swift` — **442 LoC**
- `BrainMesh/Icons/AllSFSymbolsPickerView.swift` — **429 LoC**
- `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` — **427 LoC**
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — **410 LoC**
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` — **404 LoC**
- `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift` — **388 LoC**
- `BrainMesh/Mainscreen/BulkLinkView.swift` — **367 LoC**
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362 LoC**

## Typical Workflows (sehr kurz)
- **Neue Entität anlegen**: `EntitiesHomeView` → Sheet `AddEntityView` (`BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`).
- **Attribut hinzufügen**: in Entity Detail (siehe `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`) → Attribut‑Create Flow (`BrainMesh/Mainscreen/NodeCreate/*`).
- **Link zwischen Nodes**: `AddLinkView` (`BrainMesh/Mainscreen/AddLinkView.swift`) + Bulk Linking (`BrainMesh/Mainscreen/BulkLinkView.swift`).
- **Graph wechseln / verwalten**: Graph Picker Sheet (`BrainMesh/GraphPickerSheet.swift`).
- **Export/Import**: GraphTransfer UI (`BrainMesh/GraphTransfer/GraphTransferView/*`) → Service (`BrainMesh/GraphTransfer/GraphTransferService/*`).
