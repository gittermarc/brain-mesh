# PROJECT_CONTEXT.md

## TL;DR

BrainMesh ist eine SwiftUI-iOS/iPadOS-App für graphbasiertes Wissens- und Entitätenmanagement. Die App modelliert mehrere Graphen mit Entitäten, Attributen, Links, Detailfeldern, Bildern und Anhängen. Mindestziel ist iOS 26.0, konfiguriert in `BrainMesh.xcodeproj/project.pbxproj`. Persistenz läuft über SwiftData mit CloudKit (`ModelConfiguration(schema:cloudKitDatabase: .automatic)`) in `BrainMesh/BrainMeshApp.swift`; Release-Builds fallen bei CloudKit-Containerfehlern auf lokalen SwiftData-Speicher zurück.

## Scan Snapshot

- Produktions-Swift: 487 Dateien, 62.970 Zeilen unter `BrainMesh/`.
- Größte Module nach Zeilen: `Mainscreen`, `GraphCanvas`, `GraphTransfer`, `Stats`, `Settings`, `Attachments`.
- Entry Point: `BrainMesh/BrainMeshApp.swift`.
- Root UI: `BrainMesh/ContentView.swift`, eingebettet in `BrainMesh/AppRoot/AppRootView.swift`.
- SwiftData-Modelle im App-Schema: `MetaGraph`, `MetaEntity`, `MetaAttribute`, `MetaLink`, `MetaAttachment`, `MetaDetailFieldDefinition`, `MetaDetailFieldValue`, `MetaDetailsTemplate`.

## Key Concepts / Domänenbegriffe

- **Graph**: Workspace/Container für Daten. Modell: `BrainMesh/Models/MetaGraph.swift`.
- **Active Graph**: aktuell ausgewählter Graph, gespeichert per `@AppStorage(BMAppStorageKeys.activeGraphID)`, genutzt in `EntitiesHomeView`, `GraphCanvasScreen`, `AppRootView`.
- **Entity**: Hauptknoten im Wissensgraph. Modell: `BrainMesh/Models/MetaEntity.swift`.
- **Attribute**: Kindknoten einer Entity, mit optionalen Details, Medien und Links. Modell: `BrainMesh/Models/MetaAttribute.swift`.
- **Link**: gerichtete Verbindung zwischen Entity/Attribute-Knoten. Modell: `BrainMesh/Models/MetaLink.swift`; Endpunkte sind skalare IDs plus `NodeKind`, keine SwiftData-Relationship.
- **Detail Field Definition**: frei definierbares Schemafeld pro Entity. Modell: `MetaDetailFieldDefinition` in `BrainMesh/Models/DetailsModels.swift`.
- **Detail Field Value**: typisierter Wert eines Detailfeldes an einem Attribute. Modell: `MetaDetailFieldValue` in `BrainMesh/Models/DetailsModels.swift`.
- **Attachment**: Datei, Video oder Galerie-Bild an Entity/Attribute. Modell: `BrainMesh/Attachments/MetaAttachment.swift`.
- **Header Image**: kleines CloudKit-freundliches Bild direkt auf `MetaEntity.imageData` oder `MetaAttribute.imageData` plus lokaler Cache `imagePath`.
- **Gallery Image**: Attachment mit `AttachmentContentKind.galleryImage`, nicht für Graph-Rendering gedacht.
- **Folded Search**: normalisierte Suche über `BMSearch.fold` in `BrainMesh/Models/BMSearch.swift`; gespeicherte Felder wie `nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`.
- **Graph Lock**: optionaler Schutz mit Biometrie und/oder Passwort über Security-Dateien in `BrainMesh/Security/` und Lock-Felder an Graph/Entity/Attribute.
- **Graph Transfer**: Export/Import für `.bmgraph` und `.bmbackup`, implementiert unter `BrainMesh/GraphTransfer/`.
- **Command Center**: globale Suche/Aktionen, UI unter `BrainMesh/Search/CommandCenter/`; `BrainMeshSearchService` orchestriert quellspezifische Candidate Provider unter `BrainMesh/Search/Candidates/`.
- **GraphScope / Read Repositories**: `BrainMesh/DataAccess/` stellt eine nicht-optionale Graph-Grenze, zentrale Fetch-Descriptor-Factories und value-only DTO-Repositories für Graph-Snapshots, Node-Lookups und direkte Nachbarschaften bereit.
- **GraphMutationEventBus / GraphMutationCommitter**: actor-sicherer Multicast-Bus plus einzige Save-then-Publish-Grenze unter `BrainMesh/DataAccess/Mutations/`. Main-Actor-UI-Pfade und caller-isolierte GraphTransfer-Kontexte verwenden dieselbe Committer-Implementierung. Basis- und zusammengesetzte Mutationen, Graph-Lifecycle, Dedupe, Bootstrap-/Migrations-Reparaturen sowie Import/Replace publizieren ausschließlich technische graph-scoped Post-Commit-Batches. `GraphMutationCacheInvalidationCoordinator` invalidiert die vorhandenen Home- und Stats-Caches zentral und container-idempotent.

## Architecture Map

### App Shell

- `BrainMesh/BrainMeshApp.swift`
  - erstellt das SwiftData-Schema und den `ModelContainer`.
  - konfiguriert CloudKit oder lokalen Fallback.
  - erzeugt App-weite EnvironmentObjects: Appearance, Display, Onboarding, Graph Lock, Pro, Tabs, Jump, Command Center, Recent Nodes, EntitiesHome Routing.
  - ruft `AppLoadersConfigurator.configureAllLoaders(with:)` auf.
- `BrainMesh/AppRoot/AppRootView.swift`
  - hostet `ContentView`.
  - steuert Startup, Onboarding, Graph Lock, ScenePhase und Image-Hydration.
- `BrainMesh/ContentView.swift`
  - Root `TabView` mit vier Tabs: Entitäten, Graph, Stats, Einstellungen.
  - hostet Command-Center-Sheets.

### Domain / Persistence

- `BrainMesh/Models/`
  - Core SwiftData-Modelle ohne große UI-Abhängigkeiten.
  - Search-Folding und `NodeKind`.
- `BrainMesh/Attachments/MetaAttachment.swift`
  - Attachment-Modell liegt im Attachments-Modul, ist aber Teil des SwiftData-Schemas.
- `BrainMesh/Bootstrap/`
  - Default-Graph, Legacy-GraphID-Migration, Folded-Notes-Backfill.
- `BrainMesh/DataAccess/`
  - `GraphScope`, graph-scoped `FetchDescriptor`-Factories, `GraphReadRepository`, `NodeRepository` und ausschließlich value-only, `Sendable` Read-DTOs.
  - `Mutations/` enthält den zentralen `GraphMutationEventBus`, den einzigen `GraphMutationCommitter` für Save-then-Publish, value-only Batch-Factories, technische Mutation-Referenzen, atomare `GraphMutationBatch`-Werte ohne Nutzdaten sowie den zentralen Cache-Invalidation-Coordinator.

### Storage / Sync / Caches

- `BrainMesh/Settings/SyncRuntime.swift`
  - Runtime-Status für CloudKit vs. lokal, plus iCloud-Konto-Status.
- `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`
  - lokaler Header-Image-Cache und Rehydration aus `imageData`.
- `BrainMesh/Attachments/AttachmentStore.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`
  - lokaler Attachment-Cache, Preview-URL-Materialisierung und Hintergrund-Hydration.
- `BrainMesh/GraphTransfer/`
  - Export/Import/Backup und Transfer-Limits. Interne Import-Checkpoint-Saves bleiben eventfrei; erst der erfolgreiche Abschluss publiziert einen Import- beziehungsweise Replace-Batch. Fehler und Cancellation bereinigen persistierte Teilgraphen, bevor lokale Cache-Dateien entfernt werden.

### Feature UI

- `BrainMesh/Mainscreen/`
  - Entitätenliste, Entity/Attribute-Details, Node-Details-Shared-Komponenten, Bulk-Link, Details-Schema.
- `BrainMesh/GraphCanvas/`
  - Graph-Rendering, Physics, Lens, Inspector, Focus, View Presets, GraphCanvas-Loader.
- `BrainMesh/Stats/`
  - Stats-Dashboard, Counts, Media, Trends, Health.
- `BrainMesh/Settings/`
  - Einstellungen, Sync & Wartung, Appearance, Display, Import.
- `BrainMesh/Search/`
  - globaler Search-Orchestrator, quellspezifische Candidate Provider, Ranking und Command Center.
- `BrainMesh/GraphPicker/`
  - Graph-Auswahl, Graph-Lifecycle, Graph-Deletion.
- `BrainMesh/PhotoGallery/`
  - Galerie-Browser/Viewer für Header- und Gallery-Bilder.
- `BrainMesh/Pro/`
  - StoreKit/Pro-Zustand, Paywall, Limits.

### Background Loaders / Services

- Zentrale Konfiguration: `BrainMesh/Support/AppLoadersConfigurator.swift` mit genau einer laufenden Konfiguration, idempotenter Wiederholung für denselben Container und awaitbarer `waitUntilReady()`-Barriere.
- `AppRootView+Startup.swift` wartet vor dem ersten serviceabhängigen Startup-Schritt auf diese Readiness-Barriere.
- Gemeinsames Pattern: Actor speichert `AnyModelContainer`, erzeugt eigenen `ModelContext`, setzt oft `autosaveEnabled = false`, liefert value-only DTOs zurück.
- Beispiele:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Search/BrainMeshSearchService.swift` mit value-only Candidate Providern unter `BrainMesh/Search/Candidates/`
  - `BrainMesh/DataAccess/GraphReadRepository.swift` für vollständige graph-scoped Source-Snapshots
  - `BrainMesh/DataAccess/NodeRepository.swift` für graph-scoped Node-Lookups und direkte Nachbarschaften
  - `BrainMesh/DataAccess/Mutations/GraphMutationEventBus.swift` und `GraphMutationCommitter.swift` für actor-sichere Multicast-Ereignisse und die einzige Save-then-Publish-Grenze; produktiv angebunden sind lokale Basis-/Composite-Mutationen, Graph-Lifecycle, Dedupe, Bootstrap-/Migrations-Reparaturen sowie Struktur-/Vollbackup-Import und Replace
  - `BrainMesh/Mainscreen/Deletion/GraphNodeDeletionService.swift` für graph-scoped Einzel-/Batch-Löschungen von Entities und Attributen mit deterministischem Link-, Detail-, Attachment- und Dateicache-Cleanup nach genau einem erfolgreichen Commit
  - `BrainMesh/Mainscreen/LinkCleanup.swift` mit `NodeRenameService`, der Node-Änderung und alle tatsächlichen Link-Relabels im selben `ModelContext` vorbereitet und gemeinsam committed
  - `BrainMesh/Attachments/AttachmentMutationService.swift` für Attachment-Create/Update/Delete mit Save-gebundenen lokalen Datei-Seiteneffekten
  - `BrainMesh/DataAccess/Mutations/GraphMutationCacheInvalidationCoordinator.swift` für genau eine unbounded Subscription, die `EntitiesHomeLoader` und `GraphStatsLoader` graph-scoped invalidiert

### Support / Observability

- `BrainMesh/Support/AnyModelContainer.swift`: `@unchecked Sendable` Wrapper für `ModelContainer`.
- `BrainMesh/Support/AsyncLimiter.swift`: kleiner Actor-Semaphore für Hydration/Thumbnails.
- `BrainMesh/Observability/BMObservability.swift`: `BMLog` Kategorien `load`, `expand`, `physics`, `mutation-events` plus `BMDuration`.

## Folder Map

| Ordner | Zweck | Auffälligkeit |
|---|---:|---|
| `BrainMesh/Mainscreen/` | Home, Entity/Attribute-Details, Node-Shared, Details, Bulk-Link | größtes Modul, viele UI-Flows und SwiftData-Interaktionen |
| `BrainMesh/GraphCanvas/` | Graph Canvas, Physics, Rendering, Inspector, Loader | wichtigster Render-Hot-Path |
| `BrainMesh/GraphTransfer/` | `.bmgraph` und `.bmbackup` Import/Export | Datenintegrität, große DTOs, FileDocument/Activity |
| `BrainMesh/Stats/` | Stats, Graph Health, Media/Trend/Structure Snapshots | viele aggregierende Fetches |
| `BrainMesh/Settings/` | Settings, Sync, Appearance, Display, Guide | Sync-Diagnose und große Guide-View |
| `BrainMesh/Attachments/` | Attachment-Modell, Store, Hydrator, Import, Thumbnails | CloudKit-Assets, lokale Cache-Dateien, 25-MB-Limit |
| `BrainMesh/Search/` | Search-Orchestrator, Candidate Provider, Ranking, Command Center | Provider-Grenze ist vorhanden; Links, Detailwerte und Attachments werden weiterhin graphweit gescannt |
| `BrainMesh/DataAccess/` | Graph-scoped Fetch-Factories, Read-Repositories, value-only DTOs und Mutation-Infrastruktur | nicht-optionaler `GraphScope`; actor-sicherer Event-Bus; zentraler Main-Actor-Committer; keine SwiftData-Modelle, Attachment-Binärdaten oder Nutzdaten über Actor-Grenzen |
| `BrainMesh/PhotoGallery/` | Galerie-Browser/Viewer/Section | `@Query` über Attachment-Galeriebilder |
| `BrainMesh/GraphPicker/` | Graph-Auswahl, Löschen, Sheet | Graph-Lifecycle und Pro-Limit |
| `BrainMesh/Security/` | Graph-Lock, Unlock, Crypto | Zugriffsschutz, ScenePhase-Interaktion |
| `BrainMesh/Onboarding/` | Onboarding-Koordinator und UI | AppRoot-gesteuert |
| `BrainMesh/Models/` | SwiftData Core Models | Model- und Sync-Kern |
| `BrainMesh/AppRoot/` | Root Lifecycle, Startup, Onboarding, ScenePhase | Startup-Hotspot für Migration/Hydration |
| `BrainMesh/Bootstrap/` | Default-Graph, Legacy-Migration, Backfill | Daten-Reparatur beim Start |
| `BrainMesh/Support/` | Shared Utilities und Loader-Konfiguration | Concurrency-Infrastruktur |
| `BrainMesh/Observability/` | Logging und Timing | bisher minimal |

## Data Model Map

### `MetaGraph` — `BrainMesh/Models/MetaGraph.swift`

- Felder: `id`, `createdAt`, `name`, `nameFolded`.
- Lock-Felder: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`.
- Computed: `isPasswordConfigured`, `isProtected`.
- Keine Relationship zu Entities; Graph-Zugehörigkeit läuft über skalare `graphID`-Felder in anderen Modellen.

### `MetaEntity` — `BrainMesh/Models/MetaEntity.swift`

- Felder: `id`, `createdAt`, optionales `graphID`, `name`, `nameFolded`, `notes`, `notesFolded`, `iconSymbolName`, `imageData`, `imagePath`.
- Lock-Felder wie `MetaGraph`.
- Relationships:
  - `attributes`: cascade, inverse `MetaAttribute.owner`.
  - `detailFields`: cascade, inverse `MetaDetailFieldDefinition.owner`.
- Convenience:
  - `attributesList` de-dupliziert nach `id`.
  - `detailFieldsList` de-dupliziert und sortiert nach `sortIndex`.
  - `addAttribute` setzt `attr.graphID` und `attr.owner`.
  - `addDetailField` setzt `field.graphID`, `field.owner`, `field.entityID`.

### `MetaAttribute` — `BrainMesh/Models/MetaAttribute.swift`

- Felder: `id`, optionales `graphID`, `name`, `nameFolded`, `notes`, `notesFolded`, `iconSymbolName`, `imageData`, `imagePath`, `searchLabelFolded`.
- Owner: `owner: MetaEntity?`; bewusst ohne inverse auf dieser Seite, um Macro-Zirkularität zu vermeiden.
- Relationship:
  - `detailValues`: cascade, inverse `MetaDetailFieldValue.attribute`.
- `displayName` kombiniert Entity-Name und Attribute-Name.
- `searchLabelFolded` wird bei Name-/Owner-Änderung neu berechnet.

### `MetaLink` — `BrainMesh/Models/MetaLink.swift`

- Felder: `id`, `createdAt`, optionales `graphID`, `note`, `noteFolded`.
- Endpunkte: `sourceKindRaw`, `sourceID`, `sourceLabel`, `targetKindRaw`, `targetID`, `targetLabel`.
- Keine SwiftData-Relationships zu Entity/Attribute.
- Denormalisierte Labels werden bei Rename über `NodeRenameService` in `BrainMesh/Mainscreen/LinkCleanup.swift` im selben `ModelContext`, Save und Mutation-Batch wie die Node-Änderung aktualisiert. Entity-Rename berücksichtigt außerdem die vom Owner-Namen abhängigen sichtbaren Labels seiner Attribute.

### `MetaAttachment` — `BrainMesh/Attachments/MetaAttachment.swift`

- Felder: `id`, `createdAt`, optionales `graphID`, `ownerKindRaw`, `ownerID`, `contentKindRaw`, `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`, `localPath`.
- Daten: `@Attribute(.externalStorage) var fileData: Data?`.
- Keine Relationships; Ownership ist skalar über `ownerKindRaw + ownerID`.
- `AttachmentContentKind`: `file`, `video`, `galleryImage`.
- Fachliche Create-/Update-/Delete-Operationen laufen über `AttachmentMutationService`; vorbereitete neue Cache-Dateien werden bei Save-Fehler bereinigt, bestehende Cache-Dateien erst nach erfolgreichem Commit entfernt. Reine Rehydration eines rekonstruierbaren Preview-Caches verändert das Modell nicht und publiziert kein Event.

### `MetaDetailFieldDefinition` — `BrainMesh/Models/DetailsModels.swift`

- Felder: `id`, optionales `graphID`, `entityID`, `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`.
- Relationship: `owner: MetaEntity?` mit `@Relationship(deleteRule: .nullify, originalName: "entity")`.
- Typen: Text, Mehrzeilig, Int, Double, Date, Toggle, Single Choice.
- Choice-Optionen liegen JSON-kodiert in `optionsJSON`.

### `MetaDetailFieldValue` — `BrainMesh/Models/DetailsModels.swift`

- Felder: `id`, optionales `graphID`, `attributeID`, `fieldID`.
- Typisierte Werte: `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`.
- Relationship: `attribute: MetaAttribute?`.
- `clearTypedValues()` löscht alle typisierten Slots.

### `MetaDetailsTemplate` — `BrainMesh/Models/MetaDetailsTemplate.swift`

- Felder: `id`, `createdAt`, optionales `graphID`, `name`, `nameFolded`, `fieldsJSON`.
- `fieldsJSON` ist JSON für gespeicherte Detail-Schema-Sets.
- Das Erstellen publiziert ein nutzdatenfreies `detailTemplateCreated`-Event. Graph-Löschung entfernt Templates desselben Graphen; der Legacy-Bootstrap weist Templates ohne `graphID` dem Default-Graphen zu.

## Sync / Storage

### SwiftData + CloudKit

- `BrainMesh/BrainMeshApp.swift` baut explizit ein `Schema` mit allen Modellen.
- CloudKit-Konfiguration: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)`.
- Erfolgsfall: `SyncRuntime.shared.setStorageMode(.cloudKit)`.
- Debug-Fehlerfall: `fatalError` bei CloudKit-Containerfehler.
- Release-Fehlerfall: Fallback auf `ModelConfiguration(schema:)` ohne CloudKit und `storageMode = .localOnly`.
- Entitlement: `BrainMesh/BrainMesh.entitlements` mit `iCloud.de.marcfechner.BrainMesh` und CloudKit-Service.
- `UIBackgroundModes` enthält `remote-notification` in `BrainMesh/Info.plist`.

### Runtime-Diagnose

- `BrainMesh/Settings/SyncRuntime.swift` prüft `CKContainer.accountStatus()`.
- `SyncMaintenanceView` zeigt Speicherstatus, iCloud-Konto, Cache-Größen und Cache-Wartung.
- Statusprüfung garantiert laut Code-Kommentar nicht, dass Sync selbst erfolgreich arbeitet.

### Offline / Fallback

- Lokaler Speicher bleibt verfügbar, wenn Release-CloudKit-Initialisierung fehlschlägt.
- **UNKNOWN**: Es wurde keine explizite Migration von einem lokalen Fallback-Store zurück in einen CloudKit-Store gefunden.
- **UNKNOWN**: Custom Conflict-Resolution für SwiftData/CloudKit wurde nicht gefunden; Verhalten kommt vermutlich von SwiftData/CloudKit automatic.

### Caches

- Header Images:
  - CloudKit-synchronisierte Bytes: `MetaEntity.imageData`, `MetaAttribute.imageData`.
  - Lokaler Cache: `BrainMesh/ImageStore.swift`, Ordner `BrainMeshImages`, `NSCache` mit `countLimit = 120`.
  - Rehydration: `BrainMesh/ImageHydrator.swift`, `AsyncLimiter(maxConcurrent: 1)`, maximal einmal pro 24h automatisch in `AppRootView+Startup.swift`.
- Attachments:
  - Synchronisierte Bytes: `MetaAttachment.fileData` mit `.externalStorage`.
  - Lokaler Cache: `BrainMesh/Attachments/AttachmentStore.swift`, Ordner `BrainMeshAttachments`.
  - Hydration: `BrainMesh/Attachments/AttachmentHydrator.swift`, `AsyncLimiter(maxConcurrent: 2)`.
  - Import-Limit: `25 * 1024 * 1024` in `AttachmentsSection` und Detail-Views.
- Galerie-Images:
  - Werden über `AttachmentImportPipeline` normalisiert und als `galleryImage` gespeichert.
- Main Header Image Pipeline:
  - `BrainMesh/Images/ImageImportPipeline.swift` zielt auf ca. 280 KB bei max. 1400 px für CloudKit-freundliche Header-Bilder.
- Derived Caches:
  - `EntitiesHomeLoader.invalidateCaches(forGraphID:)` entfernt nur Attribute-/Link-Counts des mutierten Graphen.
  - `GraphStatsLoader` entfernt nur graphbezogene Counts und das betroffene Total-Aggregat. Dashboard-Snapshots werden bewusst global verworfen, weil jeder Snapshot das graphübergreifende Total enthält.
  - `EntitiesHomeCockpitLoader` und `BrainMeshSearchService` halten im aktuellen Stand keinen langlebigen Cache; deshalb existiert für sie kein nutzloser No-op-Subscriber.

### Migration / Repair

- `BrainMesh/Bootstrap/GraphBootstrap+Repair.swift`
  - stellt sicher, dass mindestens ein Graph existiert und publiziert dessen `graphCreated`-Batch erst nach erfolgreichem Save.
  - migriert Legacy-Records einschließlich `MetaDetailsTemplate` mit `graphID == nil` in graph-scoped Repair-Batches.
- `BrainMesh/Bootstrap/GraphBootstrap+Backfill.swift`
  - backfillt folded Notes Indices nach vollständig validiertem Preflight und publiziert graphweise `integrityRepair`-Batches.
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - repariert owner-lokal fehlende Attachment-Graph-IDs und publiziert nach erfolgreichem Save einen `integrityRepair`-Batch.
- Kein `SchemaMigrationPlan`, `VersionedSchema` oder `MigrationStage` wurde im Scan gefunden.

## UI Map

### Root

- `BrainMesh/BrainMeshApp.swift` → `WindowGroup` → `AppRootView()`.
- `BrainMesh/AppRoot/AppRootView.swift`
  - `.task { await runStartupIfNeeded() }`.
  - `.sheet` für Onboarding.
  - `.fullScreenCover` für `GraphUnlockView`.
  - ScenePhase-Lock-Handling in `AppRootView+ScenePhase.swift`.

### Tabs — `BrainMesh/ContentView.swift`

- `RootTab.entities`: `EntitiesHomeView()`.
- `RootTab.graph`: `GraphCanvasScreen()`.
- `RootTab.stats`: `GraphStatsView()`.
- `RootTab.settings`: `NavigationStack { SettingsView(showDoneButton: false) }`.
- Command Center:
  - `.sheet(isPresented: $commandCenter.isPresented)` → `CommandCenterView`.
  - `.sheet(item: $commandCenter.destination)` → `CommandCenterDestinationSheet`.

### Entities Home

- Hauptdateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Body.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader.swift`
- Navigation:
  - Root `NavigationStack`.
  - `.searchable(text: $searchText, prompt: "Entität, Attribut, Notiz suchen")`.
  - Sheets: Display Options, Add Entity, Graph Picker.
  - Detail Route: `EntityDetailRouteView` in `EntitiesHomeRoutes.swift`.
- Datenpfad:
  - `@Query` nur für Graph-Liste.
  - Entity-Zeilen kommen aus `EntitiesHomeLoader` als DTOs.

### Entity / Attribute Details

- Entity:
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - Sheets/Routing: `EntityDetailView+Sheets.swift`.
  - Rename/Delete: `EntityDetailView+Actions.swift`.
- Attribute:
  - `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - Sheets/Routing: `AttributeDetailView+Sheets.swift`.
- Shared Detail Components:
  - `BrainMesh/Mainscreen/NodeDetailShared/`.
- Link Preview:
  - `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift` nutzt `fetchCount` und `fetchLimit` statt unbounded `@Query`.

### Graph Canvas

- Host:
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - Body/Screens: `GraphCanvasScreen+Body.swift`.
- Render/Physics:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Loader:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift`
  - `GraphCanvasDataLoader+Global.swift`
  - `GraphCanvasDataLoader+Neighborhood.swift`
- Navigation:
  - Root `NavigationStack`.
  - Sheets: Graph Picker, Focus Picker, Inspector, Entity/Attribute detail, Detail Value Editor, Details Focus Editor.
  - Cross-tab jump: `BrainMesh/GraphJumpCoordinator.swift`.

### Stats

- `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`.
- Loader: `BrainMesh/Stats/GraphStatsLoader.swift`.
- Service: `BrainMesh/Stats/GraphStatsService/`.
- Health: `BrainMesh/Stats/GraphHealth/`.

### Settings / Sync / Pro / Transfer

- Settings root: `BrainMesh/Settings/SettingsView.swift`.
- Sync UI: `BrainMesh/Settings/SyncMaintenanceView.swift`, `SettingsView+SyncSection.swift`.
- Guide: `BrainMesh/Settings/BrainMeshGuideView.swift`.
- Pro: `BrainMesh/Pro/ProCenterView.swift`, `ProEntitlementStore.swift`, `ProFeature.swift`.
- Transfer: `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferView.swift`.

## Build & Configuration

- Xcode Project: `BrainMesh.xcodeproj`.
- Shared Scheme: `BrainMesh.xcodeproj/xcshareddata/xcschemes/BrainMesh.xcscheme`.
- Targets: `BrainMesh`, `BrainMeshTests`, `BrainMeshUITests`.
- Deployment Target: iOS 26.0.
- Device Family: iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).
- Bundle ID: `de.marcfechner.BrainMesh`.
- Version: `MARKETING_VERSION = 1.07`, `CURRENT_PROJECT_VERSION = 1`.
- Swift setting im Projekt: `SWIFT_VERSION = 5.0`.
- Xcode project object version: 77, `CreatedOnToolsVersion = 26.0`, `LastUpgradeCheck = 2600`.
- Frameworks: explizit `StoreKit.framework`.
- SPM: keine `XCRemoteSwiftPackageReference`, kein `Package.resolved`, kein `Package.swift` im Scan gefunden.
- `.xcconfig`: keine Dateien im Scan gefunden.
- Info.plist:
  - Pro-Produkte: `de.marcfechner.brainmesh.pro.monthly`, `de.marcfechner.brainmesh.pro.yearly`.
  - Exported UTIs: `.bmgraph`, `.bmbackup`.
  - Background: `remote-notification`.
- Entitlements:
  - `aps-environment = development` in der hochgeladenen Datei.
  - iCloud Container: `iCloud.de.marcfechner.BrainMesh`.
- Secrets Handling:
  - Produkt-IDs und Container-IDs liegen im Repo.
  - **UNKNOWN**: Release-Signing, CloudKit Production-Deployment und CI-Secrets sind im ZIP nicht belegt.

## Conventions

- Graph-Scoped Fetches immer mit `graphID` filtern, wenn ein aktiver Graph bekannt ist.
- `graphID == nil` ist Legacy- oder Migrationszustand, nicht als neue Normalform verwenden.
- Keine schweren SwiftData-Fetches, Sorts oder Disk-I/O im SwiftUI-`body`.
- Für große Reads Actor-Loader nutzen, DTOs zurückgeben, keine `@Model`-Objekte über Actor-Grenzen reichen.
- Background-Kontexte setzen in vielen Loadern `context.autosaveEnabled = false`.
- `Task.checkCancellation()` und stale-token-Guards bei reloadbaren Flows verwenden.
- Für Suche gespeicherte folded Indices pflegen: `nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`.
- `MetaLink` und `MetaAttachment` nutzen skalare Owner/Endpoint-IDs; Entity- und Attribute-Löschungen müssen deshalb über `GraphNodeDeletionService` laufen.
- Alle fachlichen lokalen Save-Grenzen verwenden ausschließlich `GraphMutationCommitter` beziehungsweise die darauf aufbauenden Services. Normale Single-Graph-Aktionen publizieren genau einen technischen Batch nach erfolgreichem Save; seltene atomare Multi-Graph-Wartung publiziert anschließend einen deterministisch nach Graph-ID geordneten Batch pro Graph und niemals einen Mixed-Graph-Batch.
- Lokale, aus synchronisierten Bytes rekonstruierbare Medien-Caches sind keine fachliche Graph-Mutation und dürfen keinen SwiftData-Save oder Mutation-Event erzwingen.
- Relationship-Konventionen beachten:
  - Inverse bei Entity-Seite definieren, nicht doppelt.
  - Relationship nicht `entity` nennen, siehe `MetaDetailFieldDefinition.owner`.
- Header-Bilder klein halten und über `ImageImportPipeline.prepareJPEGForCloudKit` vorbereiten.
- Attachments/Gallery-Medien nicht direkt aus SwiftUI-Views synchron laden; Hydrator/Store verwenden.
- Große Feature-Views sind bereits per Extensions geteilt; neue Logik möglichst in Subviews, Loader oder kleine Services auslagern.

## How to work on this project

### Setup Steps

1. Projekt in Xcode 26 öffnen: `BrainMesh.xcodeproj`.
2. Scheme `BrainMesh` auswählen.
3. Signing/Team/CloudKit-Container prüfen, besonders `BrainMesh/BrainMesh.entitlements`.
4. iCloud-Sync in Debug gegen CloudKit Development testen.
5. Vor Sync-Tests mehrere Geräte/Simulatoren auf gleiche Build-Konfiguration bringen, siehe Footer in `SettingsView+SyncSection.swift`.
6. Für Datenänderungen zuerst die Model- und Cleanup-Pfade lesen: `BrainMesh/Models/`, `BrainMesh/Mainscreen/Deletion/GraphNodeDeletionService.swift`, `BrainMesh/Attachments/MetaAttachment.swift`, `BrainMesh/Mainscreen/LinkCleanup.swift`, `BrainMesh/Attachments/AttachmentCleanup.swift`.

### Wo anfangen für neue Devs

- App-Lifecycle: `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRoot/AppRootView.swift`, `BrainMesh/ContentView.swift`.
- Datenmodell: `BrainMesh/Models/` und `BrainMesh/Attachments/MetaAttachment.swift`.
- Entitätenliste: `BrainMesh/Mainscreen/EntitiesHome/`.
- Detail-Screens: `BrainMesh/Mainscreen/EntityDetail/`, `BrainMesh/Mainscreen/AttributeDetail/`, `BrainMesh/Mainscreen/NodeDetailShared/`.
- Graph: `BrainMesh/GraphCanvas/GraphCanvasScreen/`, `BrainMesh/GraphCanvas/GraphCanvasView/`, `BrainMesh/GraphCanvas/GraphCanvasDataLoader/`.
- Sync-Diagnose: `BrainMesh/Settings/SyncRuntime.swift`, `BrainMesh/Settings/SyncMaintenanceView.swift`.

### Feature hinzufügen — Checkliste

- Datenmodell:
  - Muss das Feature persistent sein?
  - Falls graph-scoped: `graphID` einplanen.
  - Falls suchbar: folded Index oder expliziten Search-Pfad ergänzen.
  - Falls Datei/Bytes: CloudKit-Bytebudget, lokale Cache-Datei und Cleanup definieren.
- Storage/Sync:
  - Entscheiden, ob Daten CloudKit-synchronisiert oder nur lokaler Cache sind.
  - Entity- und Attribute-Löschungen über `GraphNodeDeletionService` ausführen; Graph-Löschung behält ihren graphweiten Transaktionspfad.
  - Import/Export/Backup bei GraphTransfer prüfen.
- Loader:
  - Große Reads in Actor-Loader auslagern.
  - DTO statt SwiftData-Objekt zurückgeben.
  - `AppLoadersConfigurator` ergänzen, wenn ein App-weiter Loader Containerzugriff braucht.
- UI:
  - View-State klein halten.
  - Fetch/Sort/Disk-I/O nicht im `body`.
  - Reloads über `.task(id:)` mit Cancellation/Debounce.
- Navigation:
  - Tab-Wechsel über `RootTabRouter`.
  - Graph-Sprung über `GraphJumpCoordinator`.
  - Sheets möglichst zentral in `+Sheets` oder Coordinator-Dateien halten.
- Observability:
  - Für Hot Paths `BMLog`/`BMDuration` ergänzen.
  - Fehler nicht mit `try?` schlucken, wenn Diagnose wichtig ist.
- Tests:
  - In-Memory SwiftData-Testcontainer liegt in `BrainMeshTests/TestSupport/BrainMeshTestContainer.swift`.

## Quick Wins

1. `GraphCanvasDataLoader+Neighborhood.swift` `try? context.fetch` durch `do/catch` mit `BMLog.load` ersetzen, damit Fetch-Fehler nicht still zu leeren Graphen werden.
2. Bestehende Feature-Loader schrittweise auf die vorhandenen `GraphScopedFetches`, `GraphReadRepository` und `NodeRepository` migrieren, wenn dies ihren Hot Path vereinfacht.
3. Die Provider unter `BrainMesh/Search/Candidates/` später für Links, Detailwerte und Attachments indexieren oder vorfiltern; aktuell werden diese Tabellen weiterhin graphweit geladen und danach in Memory gerankt. `BrainMeshSearchService` besitzt derzeit keinen langlebigen Cache und braucht deshalb noch keinen Mutation-Subscriber.
4. `EntitiesHomeCockpitLoader.swift` Snapshot cachen oder inkrementell machen; aktuell lädt Cockpit Entity, Attribute, Links, DetailFields und Attachments graphweit und besitzt keinen langlebigen Derived-State, der invalidiert werden müsste.
5. `GraphCanvasView+Physics.swift` O(n²)-Pair-Loop durch Grid/Bucket-Approximation ersetzen, mindestens oberhalb von etwa 80 simulierten Nodes.
6. Readiness-Fehler im App-Root bei Bedarf zusätzlich als sichtbaren Recovery-Zustand darstellen; die awaitbare Konfigurationsbarriere ist vorhanden.
7. Große UI-Dateien splitten: `BrainMeshGuideView.swift`, `GraphTransferComponents.swift`, `GraphCanvasTypes.swift`, `GraphCanvasScreen+InspectorOverlay.swift`.
8. Sync-Debuggability erweitern: letzte Container-Initialisierung, Storage-Fallback-Grund, letzte Hydration und Cache-Fehler in `SyncMaintenanceView` anzeigen.

## Open Questions / UNKNOWN

- **UNKNOWN**: CloudKit Production-Deployment, Release-Signing und CI/CD sind im ZIP nicht belegbar.
- **UNKNOWN**: Ob lokale Fallback-Daten nach später erfolgreicher CloudKit-Initialisierung automatisch in den CloudKit-Store übernommen werden.
- **UNKNOWN**: Custom CloudKit-Merge- oder Conflict-Resolution wurde nicht gefunden.
- **UNKNOWN**: Konkrete maximale Produktdatenmengen für Graphen, Nodes und Attachments jenseits der UI-/Import-Limits.
- **UNKNOWN**: App-Store-Konfiguration für StoreKit-Produkte außerhalb der Info.plist-IDs.
- **UNKNOWN**: Exakte lokale Test-Destination für `xcodebuild`; Scheme ist vorhanden, aber kein Build wurde ausgeführt.
