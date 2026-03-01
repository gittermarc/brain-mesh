# PROJECT_CONTEXT (Start Here)

## TL;DR
BrainMesh ist eine iOS-App (Deployment Target **iOS 26.0**) für persönliche Wissens-Graphen. Daten werden in **SwiftData** gespeichert und per **CloudKit (Private DB)** synchronisiert. Storage/Synchronisation wird in `BrainMesh/BrainMeshApp.swift` konfiguriert; in Release-Builds gibt es einen Local-only-Fallback, wenn CloudKit-Init fehlschlägt.

## Key Concepts / Domänenbegriffe
- **Graph / Workspace**: thematischer Container für Daten (`MetaGraph` in `BrainMesh/Models/MetaGraph.swift`). Die meisten Records sind über ein optionales `graphID` (Migration-freundlich) gescoped.
- **Entity (Entität)**: Top-Level-Knoten (`MetaEntity` in `BrainMesh/Models/MetaEntity.swift`). Eine Entity besitzt **Attribute** und **Detail-Feld-Definitionen**.
- **Attribute**: Knoten unter einer Entity (`MetaAttribute` in `BrainMesh/Models/MetaAttribute.swift`), inkl. Notes/Icon/Bild und **Detail-Feld-Werten**.
- **Link**: Kante zwischen Nodes (Entity↔Entity, Entity↔Attribute, Attribute↔Attribute), als Raw-IDs + Labels gespeichert (`MetaLink` in `BrainMesh/Models/MetaLink.swift`).
- **Details (Schema + Werte)**:
  - **Definitionen** liegen auf der Entity (`MetaDetailFieldDefinition` in `BrainMesh/Models/DetailsModels.swift`).
  - **Werte** liegen auf dem Attribut (`MetaDetailFieldValue` in `BrainMesh/Models/DetailsModels.swift`).
  - **Templates** sind vom User gespeicherte Sets (`MetaDetailsTemplate` in `BrainMesh/Models/MetaDetailsTemplate.swift`).
- **Attachments (Anhänge)**: Dateien/Videos/Galeriebilder als `MetaAttachment` (`BrainMesh/Attachments/MetaAttachment.swift`) mit `fileData` als `@Attribute(.externalStorage)`.
- **GraphCanvas**: Canvas-basierte Graph-Ansicht mit Physik-Simulation (`BrainMesh/GraphCanvas/...`), Datenload off-main via Actor (`BrainMesh/GraphCanvas/GraphCanvasDataLoader/...`).

## Architecture Map (Layer/Module + Verantwortlichkeiten)
**UI (SwiftUI)**
- App Entry + Root Shell: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRootView.swift`, `BrainMesh/ContentView.swift`
- Feature-UI: `BrainMesh/Mainscreen/`, `BrainMesh/GraphCanvas/`, `BrainMesh/Stats/`, `BrainMesh/Settings/`, `BrainMesh/GraphTransfer/`, `BrainMesh/Pro/`, `BrainMesh/Security/`, `BrainMesh/Onboarding/`

**Loaders / Services (SwiftData off-main)**
- Zentrale Konfiguration: `BrainMesh/Support/AppLoadersConfigurator.swift` (verkabelt `ModelContainer` in verschiedene Loader-Actors).
- Beispiele:
  - Entities Home: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader.swift`
  - GraphCanvas Snapshot: `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift` (+ Extensions)
  - Stats: `BrainMesh/Stats/GraphStatsLoader.swift`
  - Connections: `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
  - Node Picker: `BrainMesh/Mainscreen/NodePickerLoader.swift`
  - Bulk Link: `BrainMesh/Mainscreen/BulkLinkLoader.swift`

**Storage / Sync / Caches**
- SwiftData Models: `BrainMesh/Models/*` und `BrainMesh/Attachments/MetaAttachment.swift`
- CloudKit Setup + Fallback: `BrainMesh/BrainMeshApp.swift`
- iCloud Account-Status in UI: `BrainMesh/Settings/SyncRuntime.swift`
- Lokale Caches:
  - Main Images: `BrainMesh/ImageStore.swift` + Hydration: `BrainMesh/ImageHydrator.swift`
  - Attachments Cache + Hydration: `BrainMesh/Attachments/AttachmentStore.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`
  - Thumbnails: `BrainMesh/Attachments/AttachmentThumbnailStore.swift`

**Support / Observability**
- AppStorage Keys: `BrainMesh/Support/BMAppStorageKeys.swift`
- Throttling: `BrainMesh/Support/AsyncLimiter.swift`
- Logging/Timing: `BrainMesh/Observability/BMObservability.swift`
- System-Modal Coordination: `BrainMesh/Support/SystemModalCoordinator.swift` (verhindert Picker-/FaceID-Unterbrechungen)

## Folder Map (Ordner → Zweck)
- `BrainMesh/Models/` — SwiftData Models + Search-Folding Helper.
- `BrainMesh/Mainscreen/` — “Entitäten”-Tab + Detail-Screens, Links, Details UI, Node Picker, Bulk Link.
- `BrainMesh/GraphCanvas/` — GraphCanvas UI (Canvas Rendering, Gestures, Physik) + DataLoader.
- `BrainMesh/Stats/` — Stats Tab (UI + Loader + Aggregation Service).
- `BrainMesh/Attachments/` — Datei-/Video-Anhänge (Import, Cache, Preview).
- `BrainMesh/PhotoGallery/` — Galerie-Bilder (MetaAttachment mit `contentKind == .galleryImage`).
- `BrainMesh/GraphTransfer/` — Export/Import Format + Service + UI.
- `BrainMesh/GraphPicker/` — Graph Liste / Rename / Delete / Dedupe.
- `BrainMesh/Settings/` — Settings UI inkl. Appearance/Display/Sync/Maintenance.
- `BrainMesh/Pro/` — StoreKit2 Entitlement Store + Paywall/Pro Center.
- `BrainMesh/Security/` — Graph Lock/Unlock (Biometrie/Passwort) + Auto-Lock.
- `BrainMesh/Onboarding/` — Onboarding Coordinator + Sheets/Steps.
- `BrainMesh/Support/` — Shared Utilities (Keys, Container-Erasure, Limiter, etc.)
- `BrainMesh/Observability/` — Lightweight Logging.
- `BrainMesh/Icons/` — Icon Picker (SF Symbols + Recents).

## Data Model Map (Entities, Relationships, wichtige Felder)
**MetaGraph** (`BrainMesh/Models/MetaGraph.swift`)
- Felder: `id`, `createdAt`, `name`, `nameFolded`
- Optional Security: Biometrics + Passwort (Hash/Salt/Iterations)
- Relationships: keine (Graph wird per ID referenziert)

**MetaEntity** (`BrainMesh/Models/MetaEntity.swift`)
- Felder: `id`, `createdAt`, `graphID`, `name/nameFolded`, `notes/notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
- Relationships:
  - `attributes` (cascade), inverse: `MetaAttribute.owner`
  - `detailFields` (cascade), inverse: `MetaDetailFieldDefinition.owner`

**MetaAttribute** (`BrainMesh/Models/MetaAttribute.swift`)
- Felder: `id`, `graphID`, `name/nameFolded`, `notes/notesFolded`, `iconSymbolName`, `imageData`, `imagePath`
- Relationship: `owner: MetaEntity?` (inverse ist nur auf Entity-Seite definiert)
- Relationships:
  - `detailValues` (cascade), inverse: `MetaDetailFieldValue.attribute`
- Derived/Search: `searchLabelFolded` aus `owner.name + attribute.name`

**MetaLink** (`BrainMesh/Models/MetaLink.swift`)
- Felder: `id`, `createdAt`, `graphID`
- Endpunkte (ohne Relationship-Macros): `sourceKindRaw/sourceID/sourceLabel`, `targetKindRaw/targetID/targetLabel`
- Optional: `note`, `noteFolded`

**MetaAttachment** (`BrainMesh/Attachments/MetaAttachment.swift`)
- Felder: `id`, `createdAt`, `graphID`, `ownerKindRaw/ownerID`, `contentKindRaw`
- Metadata: `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
- Payload: `fileData` (external storage), optional `localPath` (Cache in Application Support)

**MetaDetailFieldDefinition** (`BrainMesh/Models/DetailsModels.swift`)
- Schema pro Entity: `entityID`, `name/nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, optional `unit`, optional `optionsJSON`
- Relationship: `owner: MetaEntity?` (nullify, `originalName: "entity"`)

**MetaDetailFieldValue** (`BrainMesh/Models/DetailsModels.swift`)
- Werte pro Attribute: `attributeID`, `fieldID`, typed storage (`string/int/double/date/bool`)
- Relationship: `attribute: MetaAttribute?`

**MetaDetailsTemplate** (`BrainMesh/Models/MetaDetailsTemplate.swift`)
- Felder: `id`, `createdAt`, `graphID`, `name/nameFolded`, `fieldsJSON` (encoded FieldDef array)

## Sync/Storage (SwiftData/CloudKit, Caches, Migration, Offline)
- **SwiftData Schema** wird in `BrainMesh/BrainMeshApp.swift` gebaut und enthält:
  `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`, `MetaDetailsTemplate`.
- **CloudKit**
  - Aktiviert via `ModelConfiguration(... cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`.
  - Container ID kommt aus `BrainMesh/BrainMesh.entitlements` und ist im Code als `SyncRuntime.containerIdentifier` gespiegelt (`BrainMesh/Settings/SyncRuntime.swift`).
  - Release-Fallback: wenn CloudKit-Container nicht erstellt werden kann, wird `ModelConfiguration(schema:)` ohne CloudKit genutzt (siehe `BrainMesh/BrainMeshApp.swift`).
- **Lokale Caches (Application Support)**
  - Node-Main-Images: deterministische JPEGs via `ImageStore` (`BrainMesh/ImageStore.swift`); Backfill/Repair via `ImageHydrator` (`BrainMesh/ImageHydrator.swift`).
  - Attachments: `MetaAttachment.fileData` wird extern gespeichert; für Preview/Open gibt es lokale Cache-Files (`BrainMesh/Attachments/AttachmentStore.swift`), hydratisiert über `AttachmentHydrator` (`BrainMesh/Attachments/AttachmentHydrator.swift`).
- **Migration/Backfills**
  - Graph-Scoping Backfill (`graphID`) + Notes Search Index Backfill (`notesFolded` / `noteFolded`) laufen im Startup in `BrainMesh/GraphBootstrap.swift` (getriggert aus `BrainMesh/AppRootView.swift`).

**UNKNOWN**
- Langfristige Migrations-Strategie über SwiftData Auto-Migration + die Backfills in `BrainMesh/GraphBootstrap.swift` hinaus.

## UI Map (Hauptscreens + Navigation + wichtige Sheets/Flows)
Root Tabs (`BrainMesh/ContentView.swift`):
1. **Entitäten** → `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
   - Navigation zu Details:
     - Entity: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
     - Attribute: `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
   - Flows: Add Entity/Attribute/Link, Node Picker (`BrainMesh/Mainscreen/NodePickerView.swift`), Bulk Link (`BrainMesh/Mainscreen/BulkLinkView.swift`)
2. **Graph** → `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` (+ Partials)
   - Canvas: `BrainMesh/GraphCanvas/GraphCanvasView/*`
   - DataLoader: `BrainMesh/GraphCanvas/GraphCanvasDataLoader/*`
3. **Stats** → `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` (+ Partials)
4. **Einstellungen** → `BrainMesh/Settings/SettingsView.swift` (+ Section-Partials)

Global/Shared Präsentationen:
- Onboarding Sheet: `BrainMesh/Onboarding/OnboardingSheetView.swift` (presented in `BrainMesh/AppRootView.swift`)
- Graph Unlock Fullscreen: `BrainMesh/Security/GraphUnlock/GraphUnlockView.swift` via `GraphLockCoordinator` (`BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`)
- Graph Picker Sheet: `BrainMesh/GraphPickerSheet.swift`
- Import/Export UI: `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferView.swift`

## Build & Configuration (Targets, Info.plist, Entitlements, SPM, Secrets)
- Xcode Projekt: `BrainMesh.xcodeproj`
- Deployment Target: **26.0** (`IPHONEOS_DEPLOYMENT_TARGET = 26.0;` in `BrainMesh.xcodeproj/project.pbxproj`)
- Entitlements: `BrainMesh/BrainMesh.entitlements` (CloudKit Container, aps-environment)
- SwiftPM Dependencies: keine gefunden (keine `XCRemoteSwiftPackageReference` Einträge in `BrainMesh.xcodeproj/project.pbxproj`)
- Tests:
  - `BrainMeshTests/GraphTransferRoundtripTests.swift` nutzt das Swift `Testing` Framework + in-memory SwiftData.

**UNKNOWN**
- `INFOPLIST_FILE` referenziert `BrainMesh/Info.plist`, die Datei fehlt im ZIP. Xcode könnte sie generieren (`GENERATE_INFOPLIST_FILE = YES` in `BrainMesh.xcodeproj/project.pbxproj`). Prüfen, wo Info.plist Keys (z.B. Pro Product IDs) tatsächlich gepflegt werden.

## Conventions (Naming, Patterns, Do/Don’t)
- **Keine SwiftData-Fetches im Render-Pfad** (Navigation/Typing/Scrolling):
  - Stattdessen: Loader-Actor mit eigenem `ModelContext` (siehe `BrainMesh/Support/AppLoadersConfigurator.swift` + `EntitiesHomeLoader`, `GraphCanvasDataLoader`, `GraphStatsLoader`).
- **Mechanische Splits**: `TypeName+Concern.swift` (z.B. `GraphCanvasScreen+DerivedState.swift`).
- **Search-Indexing**:
  - `BMSearch.fold(...)` (`BrainMesh/Models/BMSearch.swift`)
  - Persistierte Indizes: `nameFolded`, `notesFolded`, `noteFolded`
- **Image/Attachment Caching**
  - `ImageStore.loadUIImage(path:)` nicht aus `body` verwenden (Warnhinweis in `BrainMesh/ImageStore.swift`).
  - Async de-dupe Loader nutzen (`ImageStore.loadUIImageAsync`, `AttachmentHydrator.ensureFileURL`).

## How to work on this project (Setup + Einstieg)
1. `BrainMesh.xcodeproj` öffnen.
2. Signing + iCloud Capability müssen zu `BrainMesh/BrainMesh.entitlements` passen (Container: `iCloud.de.marcfechner.BrainMesh`).
3. App einmal starten:
   - Settings → Sync prüfen (UI nutzt `BrainMesh/Settings/SyncRuntime.swift`).
4. Tests ausführen (Target **BrainMeshTests**).
5. Für neue Features mit Datenload:
   - Loader-Actor anlegen und in `BrainMesh/Support/AppLoadersConfigurator.swift` konfigurieren.

## Quick Wins (max 10, konkret umsetzbar)
1. `.DS_Store` aus dem Repo entfernen (z.B. `BrainMesh/Settings/.DS_Store`, `BrainMesh/Mainscreen/.DS_Store`).
2. Info.plist Handling klarziehen (Keys für Pro IDs werden via `BrainMesh/Pro/ProEntitlementStore.swift` gelesen; Quelle aktuell **UNKNOWN**).
3. Task-Cancellation/Stale-Guards standardisieren (z.B. Search Debounce in `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` und `BrainMesh/Icons/AllSFSymbolsPickerView.swift`).
4. `@Query`-Listen auf unbounded Loads prüfen (`BrainMesh/PhotoGallery/PhotoGallerySection.swift`, `BrainMesh/Attachments/AttachmentsSection.swift`).
5. Logging schaltbar machen (BMLog existiert in `BrainMesh/Observability/BMObservability.swift`, aber kein globaler “Verbose”-Toggle).
6. “Preview”-Collections konsequent bounded halten (Intent ist dokumentiert in `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`).
7. Derived-Work in SwiftUI views entkoppeln (z.B. `rows` Mapping in `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard.swift`).
8. Graph-Scoping Regeln (`graphID`) an einer Stelle dokumentieren + helper APIs.
9. CloudKit-Fallback sichtbarer machen (Release fällt still auf local-only zurück; Settings zeigt es, aber UX könnte “einmalig” warnen).
10. Deprecated Platzhalter-Files aufräumen (`BrainMesh/Models/Models.swift`, `BrainMesh/Onboarding/Untitled.swift`).

## Open Questions (UNKNOWNs collected)
- Info.plist: Wird bewusst generiert? Wo liegen die produktiven Keys? (**UNKNOWN**)
- Migration: Gibt es mehr als Auto-Migration + Backfills (`BrainMesh/GraphBootstrap.swift`)? (**UNKNOWN**)
- Collaboration/Sharing: Gibt es geplante CloudKit Shared DB Flows? In diesem ZIP nicht sichtbar (**UNKNOWN**).
