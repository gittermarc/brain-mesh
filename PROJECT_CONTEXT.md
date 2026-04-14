# PROJECT_CONTEXT.md

## TL;DR
BrainMesh ist eine iOS/iPadOS-App zum Aufbau und zur Pflege von wissensgraphartigen Sammlungen aus **Graphen**, **Entitäten**, **Attributen**, **Links**, **Detailfeldern** und **Medien**. Der Einstieg liegt in `BrainMesh/BrainMeshApp.swift`, die Persistenz läuft über **SwiftData** mit **CloudKit private database** als Standardpfad und einem **Release-Fallback auf lokal-only**, falls der CloudKit-Container nicht erstellt werden kann. Das aktuelle Deployment Target im Projekt ist **iOS 26.0**, Gerätefamilie **iPhone + iPad**.

## Key Concepts / Domänenbegriffe
- **Graph**
  - Eigenständiger Workspace / Wissensraum.
  - Technisch: `MetaGraph` in `BrainMesh/Models/MetaGraph.swift`.
  - Viele Datenobjekte tragen zusätzlich ein `graphID`, damit mehrere Graphen in derselben lokalen Datenbank getrennt bleiben.
- **Entität**
  - Primärer Wissensknoten wie Person, Ort, Thema, Projekt.
  - Technisch: `MetaEntity` in `BrainMesh/Models/MetaEntity.swift`.
- **Attribut**
  - Unterknoten einer Entität, z. B. Rolle, Datum, Status, Quelle.
  - Technisch: `MetaAttribute` in `BrainMesh/Models/MetaAttribute.swift`.
- **Link**
  - Verbindung zwischen zwei Knoten (Entität oder Attribut) mit optionaler Notiz.
  - Technisch: `MetaLink` in `BrainMesh/Models/MetaLink.swift`.
- **Detailfeld-Definition / Detailwert**
  - Frei definierbares Schema pro Entität und konkrete Werte pro Attribut.
  - Technisch: `MetaDetailFieldDefinition` / `MetaDetailFieldValue` in `BrainMesh/Models/DetailsModels.swift`.
- **Details-Template**
  - Wiederverwendbares Set aus Detailfeld-Definitionen.
  - Technisch: `MetaDetailsTemplate` in `BrainMesh/Models/MetaDetailsTemplate.swift`.
- **Attachment / Gallery Image / Video**
  - Datei- bzw. Medienobjekte, die an Entitäten oder Attribute gehängt werden.
  - Technisch: `MetaAttachment` in `BrainMesh/Attachments/MetaAttachment.swift`.
  - Wichtige Besonderheit: keine SwiftData-Relationship-Makros, sondern Owner über `(ownerKindRaw, ownerID)`.
- **Active Graph**
  - Der aktuell geöffnete Graph wird über `@AppStorage(BMAppStorageKeys.activeGraphID)` geführt.
- **Graph Lock**
  - Optionaler Zugriffsschutz pro Graph via Biometrie und/oder Passwort.
  - Modelle tragen entsprechende Lock-Felder; Orchestrierung in `BrainMesh/Security/GraphLock/*`.

## Architecture Map
### Layer / Module Map
- **App / Lifecycle**
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/AppRoot/*`
  - Verantwortung: SwiftData-Container, Environment-Objekte, Startup, Foreground/Background-Reaktion, Locking, Onboarding.
- **Domain Models**
  - `BrainMesh/Models/*`
  - Verantwortung: SwiftData-Modelle, Suchindices (`nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`), Details-Schema.
- **Feature UI**
  - `BrainMesh/Mainscreen/*`, `BrainMesh/GraphCanvas/*`, `BrainMesh/Stats/*`, `BrainMesh/Settings/*`, `BrainMesh/Onboarding/*`, `BrainMesh/Pro/*`, `BrainMesh/PhotoGallery/*`, `BrainMesh/GraphTransfer/*`
  - Verantwortung: Screens, Sheets, View-spezifische Orchestrierung.
- **Loader / Query / Background Helpers**
  - `BrainMesh/Support/AppLoadersConfigurator.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/*`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/*`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader+Query.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - Verantwortung: SwiftData-Fetches und teurere Berechnungen weg vom Renderpfad und möglichst off-main.
- **Storage / Media Pipelines**
  - `BrainMesh/Attachments/*`, `BrainMesh/Images/*`
  - Verantwortung: Import, Recompression, Disk-Caches, Hydration lokaler Dateien aus synchronisierten Daten.
- **Bootstrap / Repair**
  - `BrainMesh/Bootstrap/*`
  - Verantwortung: Default-Graph anlegen, Legacy-Daten in Graph scopes migrieren, Backfills für Suchfelder.
- **Security / Routing / Cross-screen Coordination**
  - `BrainMesh/RootTabRouter.swift`
  - `BrainMesh/GraphJumpCoordinator.swift`
  - `BrainMesh/Security/*`
  - Verantwortung: Root-Tab-Navigation, Graph-Jumps, Unlock-Flows.
- **Observability**
  - `BrainMesh/Observability/BMObservability.swift`
  - Verantwortung: leichtgewichtiges Logging (`load`, `expand`, `physics`) und Timing.

### Abhängigkeiten in Textform
- `BrainMeshApp` erstellt den SwiftData-Container und injiziert globale Stores / Koordinatoren.
- `AppRootView` orchestriert Startup und umschließt `ContentView`.
- `ContentView` stellt vier Root-Tabs bereit: Entitäten, Graph, Stats, Einstellungen.
- Feature-Screens lesen SwiftData direkt im UI nur für kleine, nahe Daten; größere Reads gehen über Loader-Actoren mit eigenen `ModelContext`-Instanzen.
- Medien-Import und Cache-Wiederherstellung laufen über Pipelines und Hydratoren außerhalb des direkten SwiftUI-Renderpfads.

## Folder Map
- `BrainMesh/AppRoot`
  - App-Startup, Scene-Phase-Reaktionen, Onboarding-/Lock-Orchestrierung.
- `BrainMesh/Attachments`
  - Attachment-Modell, Import-Pipeline, Cache-Store, Hydrator, Preview/Management.
- `BrainMesh/Bootstrap`
  - Default-Graph-Anlage, Legacy-Migration, Backfills.
- `BrainMesh/GraphCanvas`
  - Graph-Screen, DataLoader, Render-/Physics-Logik.
- `BrainMesh/GraphPicker`
  - UI-Teile für Graphwechsel, Rename, Delete.
- `BrainMesh/GraphTransfer`
  - `.bmgraph` Import/Export, DTOs, ViewModel, File I/O.
- `BrainMesh/Icons`
  - SF-Symbol-Auswahl und Hilfsviews.
- `BrainMesh/Images`
  - Bild-Dekodierung, JPEG-Normalisierung, lokaler Bild-Cache.
- `BrainMesh/ImportProgress`
  - Fortschrittsdarstellung für Imports.
- `BrainMesh/Mainscreen`
  - Haupt-Featurebereich für Entitäten, Attribute, Details, Bulk-Linking, Node-Detail-Shared-UI.
- `BrainMesh/Models`
  - SwiftData-Modelle und Such-/Typ-Helfer.
- `BrainMesh/Observability`
  - Logging und Timing.
- `BrainMesh/Onboarding`
  - Guided First-Run-Flows.
- `BrainMesh/PhotoGallery`
  - Gallery Browser / Viewer für zusätzliche Bilder.
- `BrainMesh/Pro`
  - StoreKit, Paywall, Entitlement-Status, Feature-Gating.
- `BrainMesh/Security`
  - Graph Lock, Unlock, Passwort/Biometrie-Logik.
- `BrainMesh/Settings`
  - Settings-Hub, Sync-Maintenance, Display/Appearance, Hilfe.
- `BrainMesh/Stats`
  - Stats-Dashboard, Loader, Service, Komponenten.
- `BrainMesh/Support`
  - AppStorage-Keys, Loader-Konfiguration, Hilfsbausteine.
- `BrainMeshTests`
  - Schwerpunkt auf Loadern, Search, Stats, Transfer, Media, Bootstrap.
- `BrainMeshUITests`
  - Basale UI- / Launch-Tests.

## Data Model Map
### `MetaGraph` — `BrainMesh/Models/MetaGraph.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `name`, `nameFolded`
  - `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Zweck:
  - Oberster Workspace.
  - Trägt Schutz-Einstellungen pro Graph.

### `MetaEntity` — `BrainMesh/Models/MetaEntity.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `name`, `nameFolded`, `notes`, `notesFolded`
  - `iconSymbolName`, `imageData`, `imagePath`
  - Lock-Felder analog zu `MetaGraph`
- Relationships:
  - `attributes` (`@Relationship`, cascade)
  - `detailFields` (`@Relationship`, cascade)
- Besonderheiten:
  - `name`-Änderung triggert Recompute der Attribut-Suchlabels.

### `MetaAttribute` — `BrainMesh/Models/MetaAttribute.swift`
- Wichtige Felder:
  - `id`, `graphID`
  - `name`, `nameFolded`, `notes`, `notesFolded`
  - `searchLabelFolded`
  - `iconSymbolName`, `imageData`, `imagePath`
  - Lock-Felder analog zu `MetaGraph`
- Relationships:
  - `owner: MetaEntity?`
  - `detailValues` (`@Relationship`, cascade)
- Besonderheiten:
  - `searchLabelFolded` basiert auf `displayName` (`Entity · Attribute`).

### `MetaLink` — `BrainMesh/Models/MetaLink.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`
  - `note`, `noteFolded`
- Zweck:
  - Gerichtete/gerichtet gespeicherte Verbindung zwischen zwei Knoten.

### `MetaDetailFieldDefinition` — `BrainMesh/Models/DetailsModels.swift`
- Wichtige Felder:
  - `id`, `graphID`, `entityID`
  - `name`, `nameFolded`, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
  - `owner: MetaEntity?`
- Zweck:
  - Schema pro Entität für attributbezogene Zusatzfelder.

### `MetaDetailFieldValue` — `BrainMesh/Models/DetailsModels.swift`
- Wichtige Felder:
  - `id`, `graphID`, `attributeID`, `fieldID`
  - `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
  - `attribute: MetaAttribute?`
- Zweck:
  - Getypte Werte pro Attribut und Felddefinition.

### `MetaDetailsTemplate` — `BrainMesh/Models/MetaDetailsTemplate.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`, `name`, `nameFolded`, `fieldsJSON`
- Zweck:
  - Wiederverwendbare Detailfeld-Sets.

### `MetaAttachment` — `BrainMesh/Attachments/MetaAttachment.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `ownerKindRaw`, `ownerID`
  - `contentKindRaw` (`file`, `video`, `galleryImage`)
  - `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
  - `fileData` (`@Attribute(.externalStorage)`)
  - `localPath`
- Besonderheiten:
  - Keine SwiftData-Beziehungen zu Ownern.
  - Owner wird bewusst als `(kind, id)` gespeichert.

### Wichtige Relationships auf einen Blick
- `MetaGraph` → keine direkten SwiftData-Relationships zu Child-Objekten; Abgrenzung läuft über `graphID`.
- `MetaEntity` → viele `MetaAttribute`, viele `MetaDetailFieldDefinition`.
- `MetaAttribute` → ein `owner: MetaEntity?`, viele `MetaDetailFieldValue`.
- `MetaLink` → referenziert Endpunkte nur per `NodeKind + UUID`.
- `MetaAttachment` → referenziert Owner nur per `NodeKind + UUID`.

## Sync / Storage
### Persistenz
- Primärer Persistenzpfad: `BrainMesh/BrainMeshApp.swift`
- Technologie: **SwiftData**.
- Schema enthält:
  - `MetaGraph`
  - `MetaEntity`
  - `MetaAttribute`
  - `MetaLink`
  - `MetaAttachment`
  - `MetaDetailFieldDefinition`
  - `MetaDetailFieldValue`
  - `MetaDetailsTemplate`

### Sync
- Standardmodus: `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`.
- `SyncRuntime.shared` in `BrainMesh/Settings/SyncRuntime.swift` spiegelt nur einen kleinen Runtime-Status:
  - `storageMode = cloudKit | localOnly`
  - iCloud-Account-Status via `CKContainer.accountStatus()`.
- Entitlements in `BrainMesh/BrainMesh.entitlements`:
  - iCloud-Container: `iCloud.de.marcfechner.BrainMesh`
  - Service: `CloudKit`
  - `aps-environment = development`

### Fallback-Verhalten
- **DEBUG**: CloudKit-Containerfehler führen in `BrainMesh/BrainMeshApp.swift` zu `fatalError`.
- **RELEASE**: Fallback auf lokalen SwiftData-Container ohne CloudKit.
- Nutzerseitig sichtbar über `SyncRuntime.storageMode` in `BrainMesh/Settings/SyncMaintenanceView.swift`.

### Lokale Caches / Hydration
- Bilder:
  - `BrainMesh/Images/ImageStore.swift`
  - `BrainMesh/ImageHydrator.swift`
  - Synchronisierte `imageData` werden in lokale Dateien (`imagePath`) gespiegelt.
- Attachments:
  - `BrainMesh/Attachments/AttachmentStore.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - `fileData` wird in lokale Cache-Dateien gespiegelt.
- Zweck:
  - Schnellere Medienanzeige.
  - Stabilere Dateiverwendung für Preview, Share und Viewer.

### Migration / Repair
- Startup-Bootstrap in `BrainMesh/AppRoot/AppRootView+Startup.swift` ruft:
  - `GraphBootstrap.ensureAtLeastOneGraph(using:)`
  - `GraphBootstrap.migrateLegacyRecordsIfNeeded(defaultGraphID:using:)`
  - `GraphBootstrap.backfillFoldedNotesIfNeeded(using:)`
- Attachment-/Gallery-Migrationen:
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryQuery.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryActions.swift`
- **UNKNOWN**:
  - Es wurde im gescannten Repo **kein expliziter `VersionedSchema` / `SchemaMigrationPlan`** gefunden.
  - Konfliktauflösungsstrategie über SwiftData/CloudKit-Defaults hinaus ist **UNKNOWN**.

### Offline-Verhalten
- Lokal gespeicherte Daten bleiben über SwiftData verfügbar.
- Sync wird implizit nachgeholt, wenn iCloud / Netzwerk wieder verfügbar sind.
- Release-Builds können komplett lokal-only laufen, wenn CloudKit beim Start nicht initialisiert.
- **UNKNOWN**:
  - Ob es zusätzliche Konflikt- oder Retry-Strategien außerhalb der SwiftData-Defaults gibt, ist unklar.

## UI Map
### Root Navigation
- Einstieg: `BrainMesh/AppRoot/AppRootView.swift`
- Root Tabs: `BrainMesh/ContentView.swift`
  - `EntitiesHomeView()`
  - `GraphCanvasScreen()`
  - `GraphStatsView()`
  - `SettingsView(showDoneButton: false)` in `NavigationStack`

### Wichtige Screens / Flows
- **Entitäten-Home** — `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
  - `NavigationStack`
  - Suche, Sortierung, Graph-Switch, Add-Entity, Anzeigeoptionen
  - navigiert zu `EntityDetailView`
- **Entity Detail** — `BrainMesh/Mainscreen/EntityDetail/*`
  - Attribute, Links, Details, Medien, Gallery, Attachments, Rename, Delete
- **Attribute Detail** — `BrainMesh/Mainscreen/AttributeDetail/*`
  - Links, Details-Werte, Medien, Gallery, Attachments, Rename, Delete
- **Graph Canvas** — `BrainMesh/GraphCanvas/GraphCanvasScreen/*`
  - Fokusmodus, Hops, Attribute an/aus, Inspector, Graph-Jumps, Physics-Layout
  - Sheets für Graph Picker, Focus Picker, Inspector, Entity/Attribute-Detail, Details-Value-Edit
- **Stats** — `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - Dashboard, Trends, Struktur, Medien, per-Graph Breakdown
- **Graph Picker** — `BrainMesh/GraphPickerSheet.swift`
  - Graph wechseln, anlegen, rename, delete, security, duplicate cleanup
- **Graph Transfer** — `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferView.swift`
  - Export / Import `.bmgraph`, Replace-Flows, Share, Pro-Limit-Handling
- **Photo Gallery** — `BrainMesh/PhotoGallery/*`
  - Browser + Viewer für zusätzliche Bilder
- **Onboarding** — `BrainMesh/Onboarding/*`
  - Guided Einstieg mit Schritten für Entität, Attribut, Link, Details
- **Settings** — `BrainMesh/Settings/SettingsView.swift`
  - Display, Graph Transfer, Import, Sync & Wartung, Hilfe & Support
- **Pro** — `BrainMesh/Pro/*`
  - Paywall, Entitlement-Status, Restore / Purchase
- **Security** — `BrainMesh/Security/*`
  - Graph Security Sheet, Unlock Fullscreen Flow

## Build & Configuration
### Targets
- Gefunden in `BrainMesh.xcodeproj/project.pbxproj`:
  - `BrainMesh`
  - `BrainMeshTests`
  - `BrainMeshUITests`

### Plattform / Deployment
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- `TARGETED_DEVICE_FAMILY = "1,2"` → iPhone + iPad

### Info.plist / Entitlements
- `BrainMesh/Info.plist`
  - Abo-IDs:
    - `BM_PRO_SUBSCRIPTION_ID_01 = de.marcfechner.brainmesh.pro.monthly`
    - `BM_PRO_SUBSCRIPTION_ID_02 = de.marcfechner.brainmesh.pro.yearly`
  - `UIBackgroundModes = remote-notification`
  - Exportierter UTType für `.bmgraph`
- `BrainMesh/BrainMesh.entitlements`
  - iCloud / CloudKit aktiviert
  - `aps-environment = development`

### StoreKit / Monetarisierung
- `BrainMesh/Pro/ProEntitlementStore.swift` liest Produkt-IDs aus `Info.plist`.
- StoreKit-Konfiguration vorhanden:
  - `BrainMesh/BrainMesh Pro.storekit`

### Swift Package Manager
- Im gescannten `BrainMesh.xcodeproj/project.pbxproj` wurden **keine SPM-Dependencies** gefunden.

### .xcconfig / Secrets
- Im gescannten Repo wurden **keine `.xcconfig`-Dateien** gefunden.
- Sichtbare konfigurierbare Werte liegen primär in `Info.plist`.
- **UNKNOWN**:
  - Ob CI / lokale Umgebungen außerhalb des Repos weitere Build-Konfigurationen injizieren, ist unklar.

### File-System-synced Groups
- Das Projekt verwendet Xcode-15-kompatible filesystem-synced groups im `.pbxproj`.
- Neue Dateien werden daher typischerweise über die Dateistruktur statt über manuelles Projektfile-Editing eingebunden.

## Conventions
### Naming / Struktur
- Große Views werden in Host-Datei + Feature-Erweiterungen gesplittet.
  - Beispiele:
    - `BrainMesh/GraphCanvas/GraphCanvasScreen/*`
    - `BrainMesh/Mainscreen/EntityDetail/*`
    - `BrainMesh/Mainscreen/AttributeDetail/*`
    - `BrainMesh/Mainscreen/NodeDetailShared/*`
- Loader und Query-Helfer liegen häufig nah am Feature.
- `BMAppStorageKeys` in `BrainMesh/Support/BMAppStorageKeys.swift` zentralisiert `@AppStorage`-Keys.

### Persistenz / Search / Performance
- Suchindices werden denormalisiert gespeichert:
  - `nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`
- Schwere Fetches sollen **nicht** im SwiftUI-Renderpfad laufen.
- Off-main-Snapshots werden bevorzugt über Loader-Actoren geladen.
- `@Model`-Objekte werden nicht absichtlich quer über Concurrency-Grenzen transportiert; stattdessen DTO-/Snapshot-Strukturen.
- Bei Medien-Predicates wird store-translatable Query-Logik bevorzugt, um In-Memory-Fallbacks zu vermeiden.

### Do / Don’t
- **Do**
  - Graph-scoped Daten immer sauber über `graphID` berücksichtigen.
  - Bei neuen Suchfeldern gleich Folded-Index + Backfill-Strategie mitdenken.
  - Schwere Arbeit in Loader / Service / Pipeline verschieben.
  - Für Images / Videos bestehende Importpipelines nutzen.
- **Don’t**
  - Keine großen SwiftData-Fetches in `body` oder pro Frame.
  - Keine neuen Medienpfade an `AttachmentStore` / `ImageStore` vorbei etablieren.
  - Keine OR-/Optional-Predicates einführen, die SwiftData zu In-Memory-Filterung zwingen könnten.
  - Keine neuen `@AppStorage`-Stringliteral-Keys verteilen; `BMAppStorageKeys` erweitern.

## How to work on this project
### Setup für neue Devs
- Projekt in Xcode öffnen.
- Signing / iCloud / CloudKit prüfen.
- Mit einem iCloud-fähigen Environment testen, wenn Sync relevant ist.
- Für reine lokale Entwicklung beachten:
  - DEBUG crasht absichtlich, wenn der CloudKit-Container nicht aufgebaut werden kann.
- StoreKit-Tests optional über `BrainMesh/BrainMesh Pro.storekit`.

### Wo anfangen
- App-Einstieg verstehen:
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/AppRoot/AppRootView.swift`
  - `BrainMesh/ContentView.swift`
- Datenmodell verstehen:
  - `BrainMesh/Models/*`
  - `BrainMesh/Attachments/MetaAttachment.swift`
- Hot Paths prüfen:
  - `BrainMesh/GraphCanvas/*`
  - `BrainMesh/Stats/*`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/*`

### Typischer Workflow für neue Features
- Modell ergänzen oder neues graph-scoped Objekt einführen.
- Falls suchbar: Folded-Index einplanen und Legacy-Backfill prüfen.
- UI-Host klein halten, komplexe Fetches über Loader / Snapshot lösen.
- Medienzugriff über bestehende Pipelines und Cache-Layer führen.
- Tests in `BrainMeshTests` ergänzen, möglichst nahe am betroffenen Loader / Service.

## Quick Wins
- [ ] Explizite Migrationsstrategie ergänzen (`VersionedSchema` / `MigrationPlan`), weil im gescannten Repo keine explizite Versionierung gefunden wurde.
- [ ] `GraphStatsService+Counts.swift` so umbauen, dass Attachment-Bytes nicht über Vollfetch aller `MetaAttachment` berechnet werden.
- [ ] `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift` auf räumliche Partitionierung prüfen; aktuell O(n²)-Pair-Loop.
- [ ] Graph-scoped Attachment-Predicate-Helfer zentralisieren; dieselbe Problemdomäne taucht in Media Preview, Gallery, Migration, Stats mehrfach auf.
- [ ] Startup-Repairs aus `AppRootView+Startup.swift` weiter entkoppeln und messbar machen.
- [ ] `BrainMesh/Settings/BrainMeshGuideView.swift` datengetrieben oder in kleinere Sektionen zerlegen; die Datei ist sehr groß und merge-anfällig.
- [ ] Klären, ob `UIBackgroundModes = remote-notification` tatsächlich genutzt wird; im gescannten Swift-Code wurde kein offensichtlicher Remote-Notification-Handling-Einstieg gefunden.
- [ ] Klären, ob `BrainMesh/GraphSession.swift` noch Architektur-relevant ist; im gescannten Projekt wurden keine In-Repo-Referenzen gefunden.
- [ ] Für `.bmgraph` Export/Import die Medien-Strategie explizit dokumentieren; aktuell werden Attachments in der gescannten Transfer-Pipeline nicht mit exportiert.
- [ ] Observability ausbauen: zusätzliche Logs / Metriken für Import, Hydration, Startup-Repair und Graph-Canvas-Loads.

## Open Questions
- **UNKNOWN**: Gibt es außerhalb des Repos eine explizite Schema-/Migrationsstrategie?
- **UNKNOWN**: Warum ist `UIBackgroundModes = remote-notification` aktiv, obwohl im gescannten Swift-Code kein klarer Push-Einstieg sichtbar war?
- **UNKNOWN**: Ist `BrainMesh/GraphSession.swift` bewusst für spätere Nutzung vorgesehen oder faktisch Altbestand?
- **UNKNOWN**: Sollen `.bmgraph`-Exporte Medien bewusst ausschließen oder ist das nur aktueller Scope?
- **UNKNOWN**: Welche realen Zielgrößen für Graphen, Attachments und Link-Dichten werden produktiv erwartet?
