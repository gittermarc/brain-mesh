# PROJECT_CONTEXT.md
## TL;DR
BrainMesh ist eine SwiftUI-basierte iPhone/iPad-App zum Aufbau graphbasierter Wissens- bzw. Metadatenmodelle. Kernobjekte sind Graphen, Entitäten, Attribute, Links, frei definierbare Detailfelder und Anhänge. Persistenz läuft über SwiftData; Cloud-Sync wird in `BrainMesh/BrainMeshApp.swift` über `ModelConfiguration(..., cloudKitDatabase: .automatic)` aktiviert, mit lokalem Release-Fallback bei CloudKit-Initialisierungsfehlern. Mindestziel ist iOS 26.0 laut `BrainMesh.xcodeproj/project.pbxproj`.
---
## Key Concepts / Domänenbegriffe
- **Graph**
  - Separater Wissensraum / Workspace.
  - Modell: `BrainMesh/Models/MetaGraph.swift`.
  - Umschaltung über `BrainMesh/GraphPickerSheet.swift`.
- **Entität**
  - Primärer Knoten im Wissensgraph.
  - Modell: `BrainMesh/Models/MetaEntity.swift`.
  - Hauptliste im Tab `Entitäten`.
- **Attribut**
  - Sekundärer Knoten, der einer Entität gehört.
  - Modell: `BrainMesh/Models/MetaAttribute.swift`.
  - Eigentümerbeziehung über `MetaAttribute.owner` und `MetaEntity.attributes`.
- **Link**
  - Kante zwischen zwei Knoten.
  - Modell: `BrainMesh/Models/MetaLink.swift`.
  - Endpunkte werden denormalisiert als `sourceKindRaw/sourceID` und `targetKindRaw/targetID` gespeichert.
- **Details-Schema / Detailwerte**
  - Frei definierbare Felddefinitionen pro Entität und Werte pro Attribut.
  - Modelle: `BrainMesh/Models/DetailsModels.swift`.
- **Anhänge / Galerie**
  - Dateien, Videos und Galerie-Bilder für Entitäten/Attribute.
  - Modell: `BrainMesh/Attachments/MetaAttachment.swift`.
  - Besitzer wird nicht als SwiftData-Relationship modelliert, sondern über `(ownerKindRaw, ownerID)`.
- **Graph Transfer**
  - Export/Import eines einzelnen Graphen als `.bmgraph` JSON-Datei.
  - Ordner: `BrainMesh/GraphTransfer/`.
- **Graph Lock**
  - Optionaler Schutz pro Graph per Biometrie und/oder Passwort.
  - Ordner: `BrainMesh/Security/`.
- **Display / Appearance Settings**
  - Persistierte Darstellungsoptionen und Presets.
  - Ordner: `BrainMesh/Settings/Appearance/` und `BrainMesh/Settings/Display/`.
---
## Architecture Map
### 1) App Entry / Runtime
- `BrainMesh/BrainMeshApp.swift`
  - Baut `Schema` und `ModelContainer`.
  - Aktiviert SwiftData + CloudKit.
  - Konfiguriert globale Stores/Coordinators via `@StateObject`.
  - Startet Loader-Konfiguration über `BrainMesh/Support/AppLoadersConfigurator.swift`.
- `BrainMesh/AppRoot/AppRootView.swift`
  - App-weite Hülle über `ContentView`.
  - Verantwortlich für Startup, ScenePhase-Reaktionen, Lock-Enforcement und Onboarding-Präsentation.
- `BrainMesh/ContentView.swift`
  - Root-`TabView` mit vier Hauptbereichen:
    - `EntitiesHomeView`
    - `GraphCanvasScreen`
    - `GraphStatsView`
    - `SettingsView`
### 2) Domain / Persistenz
- `BrainMesh/Models/`
  - SwiftData-Modelle für Graph, Entität, Attribut, Link, Details-Schema/-Werte, Template.
- `BrainMesh/Attachments/MetaAttachment.swift`
  - Eigenes SwiftData-Modell für Dateianhänge und Galerie-Bilder.
### 3) Feature Layer
- `BrainMesh/Mainscreen/`
  - Entitäten-Home, Entity-/Attribute-Detail, Node-Picker, Bulk-Linking, Details-UI.
- `BrainMesh/GraphCanvas/`
  - Graph-Tab, Datenlader, Rendering, Physik, Inspector, Overlays.
- `BrainMesh/Stats/`
  - Dashboard, per-Graph-Stats, Loader, Service-Layer.
- `BrainMesh/GraphTransfer/`
  - Export/Import, DTOs, ViewModel, Limits, Validierung.
- `BrainMesh/PhotoGallery/`
  - Galerie-Browser/Viewer für bildbasierte Anhänge.
- `BrainMesh/Settings/`
  - Einstellungs-Hub, Hilfen, Sync-Wartung, Darstellung, Import-Kompression.
- `BrainMesh/Pro/`
  - StoreKit-basierte Pro-Entitlements und Paywall.
- `BrainMesh/Security/`
  - Graph-Lock/Unlock-Flows.
### 4) Infrastructure / Support
- `BrainMesh/Support/AnyModelContainer.swift`
  - `@unchecked Sendable`-Wrapper für `ModelContainer` in Off-Main-Loadern.
- `BrainMesh/Support/AppLoadersConfigurator.swift`
  - Zentrale Registrierung aller Loader/Hydratoren.
- `BrainMesh/Observability/BMObservability.swift`
  - Dünne Logger-/Timing-Helfer.
### 5) Dependency Flow (Textform)
- UI-Hosts (`View`s) hängen an:
  - SwiftData `@Query` für kleine, UI-nahe Datenmengen,
  - Background-Loadern für teure Reads,
  - EnvironmentObjects für app-weite Stores/Coordinators.
- Loader hängen an:
  - `AnyModelContainer` → eigener kurzer `ModelContext` pro Job.
- Services hängen an:
  - `ModelContext` oder DTO-Mapping.
- Support-Layer ist bewusst dünn und wird breit verwendet.
---
## Folder Map
- `BrainMesh/AppRoot/`
  - Startup, ScenePhase, Onboarding-Entscheidung.
- `BrainMesh/Models/`
  - SwiftData-Kernmodelle.
- `BrainMesh/Mainscreen/`
  - Haupt-CRUD-Flows für Entitäten/Attribute/Links/Details.
- `BrainMesh/GraphCanvas/`
  - Graph-Visualisierung, Loader, Canvas-Physik, Overlays.
- `BrainMesh/Stats/`
  - Statistiken und Dashboard-Snapshots.
- `BrainMesh/Attachments/`
  - Dateianhänge, Cache-Dateien, Preview, Video-Import/Playback.
- `BrainMesh/PhotoGallery/`
  - Bildgalerie auf Basis von `MetaAttachment`.
- `BrainMesh/GraphTransfer/`
  - Dateiformat, Export/Import, ViewModel, Progress.
- `BrainMesh/Settings/`
  - Settings-Hub, Hilfe, Sync/Wartung, Darstellung, Import-Preferences.
- `BrainMesh/Settings/Appearance/`
  - Theme-/Appearance-Modelle und Vorschau.
- `BrainMesh/Settings/Display/`
  - Persistierte Screen-spezifische Anzeigeeinstellungen.
- `BrainMesh/Security/`
  - Graph-Lock-Krypto, Unlock-Sheets, Request-Snapshots.
- `BrainMesh/Pro/`
  - StoreKit-Integration und Paywall.
- `BrainMesh/Bootstrap/`
  - Legacy-Reparatur, Initialgraph, Backfills.
- `BrainMesh/Support/`
  - AppStorage-Keys, AsyncLimiter, UTType-Erweiterungen, Loader-Konfiguration.
- `BrainMesh/Observability/`
  - Logging-/Timing-Helfer.
- `BrainMeshTests/`
  - Unit Tests für Loader, Bootstrap, Transfer, Stats, Paging, Search.
- `BrainMeshUITests/`
  - Aktuell nur Template-/Launch-Tests.
---
## Data Model Map
### `MetaGraph`
- Datei: `BrainMesh/Models/MetaGraph.swift`
- Wichtige Felder:
  - `id: UUID`
  - `createdAt: Date`
  - `name`, `nameFolded`
  - Lock-Felder: `lockBiometricsEnabled`, `lockPasswordEnabled`, `passwordSaltB64`, `passwordHashB64`, `passwordIterations`
- Beziehungen:
  - Keine expliziten SwiftData-Relationships zu Kindobjekten.
  - Graph-Scope wird stattdessen in Kindobjekten über `graphID` gehalten.
### `MetaEntity`
- Datei: `BrainMesh/Models/MetaEntity.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `name`, `nameFolded`
  - `notes`, `notesFolded`
  - `iconSymbolName`
  - `imageData`, `imagePath`
  - Lock-Felder analog zu `MetaGraph`
- Beziehungen:
  - `attributes: [MetaAttribute]?` mit Cascade, inverse `MetaAttribute.owner`
  - `detailFields: [MetaDetailFieldDefinition]?` mit Cascade, inverse `MetaDetailFieldDefinition.owner`
### `MetaAttribute`
- Datei: `BrainMesh/Models/MetaAttribute.swift`
- Wichtige Felder:
  - `id`, `graphID`
  - `name`, `nameFolded`
  - `notes`, `notesFolded`
  - `searchLabelFolded`
  - `iconSymbolName`
  - `imageData`, `imagePath`
  - Lock-Felder analog zu `MetaGraph`
- Beziehungen:
  - `owner: MetaEntity?`
  - `detailValues: [MetaDetailFieldValue]?` mit Cascade, inverse `MetaDetailFieldValue.attribute`
### `MetaLink`
- Datei: `BrainMesh/Models/MetaLink.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `note`, `noteFolded`
  - `sourceKindRaw`, `sourceID`, `sourceLabel`
  - `targetKindRaw`, `targetID`, `targetLabel`
- Beziehungen:
  - Keine SwiftData-Relationship zu Nodes; Endpunkte sind denormalisiert gespeichert.
### `MetaDetailFieldDefinition`
- Datei: `BrainMesh/Models/DetailsModels.swift`
- Wichtige Felder:
  - `id`, `graphID`, `entityID`
  - `name`, `nameFolded`
  - `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`
- Beziehungen:
  - `owner: MetaEntity?` (`deleteRule: .nullify`)
### `MetaDetailFieldValue`
- Datei: `BrainMesh/Models/DetailsModels.swift`
- Wichtige Felder:
  - `id`, `graphID`, `attributeID`, `fieldID`
  - `stringValue`, `intValue`, `doubleValue`, `dateValue`, `boolValue`
- Beziehungen:
  - `attribute: MetaAttribute?`
### `MetaDetailsTemplate`
- Datei: `BrainMesh/Models/MetaDetailsTemplate.swift`
- Zweck:
  - Gespeicherte Details-Schema-Vorlagen pro Graph.
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`, `name`, `nameFolded`, `fieldsJSON`
### `MetaAttachment`
- Datei: `BrainMesh/Attachments/MetaAttachment.swift`
- Wichtige Felder:
  - `id`, `createdAt`, `graphID`
  - `ownerKindRaw`, `ownerID`
  - `contentKindRaw`
  - `title`, `originalFilename`, `contentTypeIdentifier`, `fileExtension`, `byteCount`
  - `fileData` mit `@Attribute(.externalStorage)`
  - `localPath`
- Beziehungen:
  - Keine SwiftData-Relationship zum Owner; Besitzer wird indirekt modelliert.
### Relationship Summary
- `MetaGraph` → keine echten Child-Relationships; Scope läuft über `graphID` in Kindobjekten.
- `MetaEntity` → viele `MetaAttribute`, viele `MetaDetailFieldDefinition`.
- `MetaAttribute` → optional ein Owner `MetaEntity`, viele `MetaDetailFieldValue`.
- `MetaLink` → referenziert beliebige Nodes per `(kind,id)` statt Relationship.
- `MetaAttachment` → referenziert beliebige Nodes per `(ownerKindRaw, ownerID)` statt Relationship.
---
## Sync / Storage
### Persistenz-Stack
- SwiftData ist der einzige verifizierte Persistenz-Stack.
- Initialisierung in `BrainMesh/BrainMeshApp.swift`.
- Keine `VersionedSchema` oder `SchemaMigrationPlan` gefunden.
### CloudKit
- Aktiviert über `ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)` in `BrainMesh/BrainMeshApp.swift`.
- Entitlements in `BrainMesh/BrainMesh.entitlements` enthalten:
  - CloudKit-Service
  - Container `iCloud.de.marcfechner.BrainMesh`
- `BrainMesh/Settings/SyncRuntime.swift` spiegelt Storage-Modus und iCloud-Accountstatus im UI.
### Fallback-Verhalten
- DEBUG:
  - CloudKit-Containerfehler führen zu `fatalError`.
- RELEASE:
  - Fallback auf lokales SwiftData ohne CloudKit.
  - `SyncRuntime` schaltet auf `.localOnly`.
### Lokale Caches
- Bilder:
  - `BrainMesh/ImageStore.swift`
  - Speicherort: `Application Support/BrainMeshImages`
  - Cache für `imageData` → deterministische JPEG-Datei
- Anhänge:
  - `BrainMesh/Attachments/AttachmentStore.swift`
  - Speicherort: `Application Support/BrainMeshAttachments`
  - Cache für `MetaAttachment.fileData`
### Hydration / Rebuild
- `BrainMesh/ImageHydrator.swift`
  - Hydriert `imageData` progressiv in lokale JPEG-Dateien.
- `BrainMesh/Attachments/AttachmentHydrator.swift`
  - Hydriert `fileData` bei Bedarf in lokale Cache-Dateien.
### Migration / Repair
- `BrainMesh/Bootstrap/GraphBootstrap+Repair.swift`
  - Weist Legacy-Datensätzen fehlende `graphID` zu.
- `BrainMesh/Bootstrap/GraphBootstrap+Backfill.swift`
  - Backfill für `notesFolded`.
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - Migriert Legacy-Anhänge graph-spezifisch.
- `BrainMesh/Settings/Display/DisplaySettingsStore.swift`
  - Migriert alte `@AppStorage`-Schlüssel in neues Display-Settings-Modell.
### Offline-Verhalten
- Lokal gespeicherte Daten bleiben durch SwiftData verfügbar.
- Sync-Reconciliation, Konfliktstrategie und Merge-Semantik über mehrere Geräte sind im Code nicht explizit dokumentiert.
- **UNKNOWN:** Konkrete Konfliktauflösung für gleichzeitige Edits auf mehreren Geräten.
---
## UI Map
### Root Tabs
- `BrainMesh/ContentView.swift`
  - `Entitäten`
  - `Graph`
  - `Stats`
  - `Einstellungen`
### Entitäten-Tab
- Host: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
- Navigation:
  - `NavigationStack`
  - Suche via `.searchable`
  - Route zu `EntityDetailRouteView` → `EntityDetailView`
- Wichtige Nebenflüsse:
  - `AddEntityView` als Sheet
  - `GraphPickerSheet` als Sheet
  - `EntitiesHomeDisplaySheet` als Sheet
### Entity Detail
- Host: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- Unterflüsse:
  - Attribut anlegen
  - Link anlegen / Bulk-Link
  - Galerie-Browser / Viewer
  - Attachments-Manager / Preview / Video-Playback
  - Notiz-Editor
  - Rename / Customize / Delete
### Attribute Detail
- Ordner: `BrainMesh/Mainscreen/AttributeDetail/`
- Paralleler Aufbau zu Entity Detail, plus Details-Schema-/Wert-Editoren.
### Graph-Tab
- Host: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
- Navigation/Overlays:
  - `GraphPickerSheet`
  - Fokus-Picker (`NodePickerView`)
  - Inspector-Sheet
  - Entity-/Attribute-Detail als Sheet
  - Details-Wert-Editor als Sheet
- Cross-screen Jump:
  - `BrainMesh/GraphJumpCoordinator.swift`
### Stats-Tab
- Host: `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
- Inhalte:
  - Gesamtzahlen
  - Legacy-/per-Graph-Karten
  - Media-/Struktur-/Trend-Snapshots
  - Lazy per-Graph Counts
### Einstellungen
- Host: `BrainMesh/Settings/SettingsView.swift`
- Hub-Ziele:
  - Pro Center
  - Darstellung
  - Graph Transfer
  - Import Settings
  - Sync & Wartung
  - Hilfe & Support
### Onboarding
- `BrainMesh/Onboarding/OnboardingSheetView.swift`
- App-weite Präsentation über `AppRootView.sheet(isPresented:)`.
### Unlock Flow
- `BrainMesh/Security/GraphUnlock/GraphUnlockView.swift`
- App-weite Präsentation über `AppRootView.fullScreenCover(item:)`.
---
## Build & Configuration
### Targets
- `BrainMesh` (App)
- `BrainMeshTests` (Unit Tests)
- `BrainMeshUITests` (UI Tests)
Quelle: `BrainMesh.xcodeproj/project.pbxproj`.
### Plattform / Deployment
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`
- `TARGETED_DEVICE_FAMILY = 1,2`
- Projekt angelegt mit Xcode 26.0-Metadaten.
### Projektstruktur
- Xcode-Dateigruppen verwenden `fileSystemSynchronizedGroups`.
- Neue Dateien im Dateisystem sollen dadurch automatisch sichtbar werden.
### Info.plist / Entitlements
- `BrainMesh/Info.plist`
  - Pro-Produkt-IDs: `BM_PRO_SUBSCRIPTION_ID_01`, `BM_PRO_SUBSCRIPTION_ID_02`
  - Exportierter UTType für `.bmgraph`
  - `UIBackgroundModes = remote-notification`
- `BrainMesh/BrainMesh.entitlements`
  - `aps-environment = development`
  - CloudKit-Container-ID
### Packages / Dependencies
- Keine SPM-Abhängigkeiten in `BrainMesh.xcodeproj/project.pbxproj` gefunden.
- Genutzte Apple-Frameworks im Code:
  - SwiftUI
  - SwiftData
  - CloudKit
  - StoreKit
  - LocalAuthentication
  - PhotosUI
  - AVFoundation/QuickLook indirekt in Medienbereichen
### StoreKit / Monetization
- StoreKit-Konfigurationsdatei vorhanden:
  - `BrainMesh/BrainMesh Pro.storekit`
- Runtime-Store:
  - `BrainMesh/Pro/ProEntitlementStore.swift`
### xcconfig / Secrets Handling
- Keine `.xcconfig`-Dateien gefunden.
- Keine separate Secrets-Abstraktion gefunden.
- Bundle-/Cloud-/Subscription-Werte liegen in `project.pbxproj`, `Info.plist` und Entitlements.
- **UNKNOWN:** Ob zusätzlich Xcode Scheme- oder CI-seitige Secrets außerhalb des ZIP genutzt werden.
---
## Conventions
### Benennungen / Struktur
- Große Views werden häufig in Host + thematische `+`-Dateien gesplittet.
  - Beispiele:
    - `BrainMesh/AppRoot/AppRootView+Startup.swift`
    - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`
    - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Loading.swift`
- Loader/Service-Splits folgen demselben Muster.
### Concurrency
- Projekt arbeitet sichtbar gegen strikte Actor-Isolation-Probleme.
- Pattern:
  - UI bleibt `@MainActor`-nah.
  - Teure Fetches laufen in Actor-Loadern mit eigenem `ModelContext`.
  - `@Model`-Objekte werden nicht bewusst über Concurrency-Grenzen getragen; stattdessen Snapshots/IDs.
### Search / Derived Fields
- Suchfelder werden vor-normalisiert gespeichert:
  - `nameFolded`
  - `notesFolded`
  - `searchLabelFolded`
  - `noteFolded`
- Suchnormalisierung über `BrainMesh/Models/BMSearch.swift`.
### Graph Scope
- Multi-Graph-Scope wird fast überall über optionales `graphID` modelliert.
- Legacy-Datensätze mit `graphID == nil` werden an mehreren Stellen noch berücksichtigt.
### Presentation Stability
- Item-driven Sheets werden explizit eingesetzt, um leere/race-anfällige Präsentationen zu vermeiden.
- Beispiel: `BrainMesh/GraphPickerSheet.swift`.
### Do
- Neue persistierte UI-Keys in `BrainMesh/Support/BMAppStorageKeys.swift` zentralisieren.
- Für teure Listen/Statistiken Loader mit Snapshot-DTOs verwenden.
- Bei neuen graph-scoped Modellen an Bootstrap/Migration denken.
- Tests für Loader-/Store-Logik ergänzen.
### Don’t
- Keine SwiftData-Fetches in häufig invalidierten Renderpfaden platzieren.
- Keine `@Model`-Instanzen quer über Actor-Grenzen schleusen.
- Keine zweite inverse Relationship definieren, wenn bestehender Code bewusst nur eine Seite setzt.
---
## How to work on this project
### Setup Steps
- [ ] `BrainMesh.xcodeproj` in Xcode öffnen.
- [ ] Team/Signing für `BrainMesh` prüfen.
- [ ] iCloud/CloudKit Capability aktiv und zum Container `iCloud.de.marcfechner.BrainMesh` passend halten.
- [ ] Optional StoreKit-Konfiguration für lokale Käufe aktivieren.
- [ ] App einmal frisch starten, um Container-Bootstrap und Initialgraph zu prüfen.
### Womit neue Devs anfangen sollten
- Zuerst lesen:
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/AppRoot/AppRootView.swift`
  - `BrainMesh/Support/AppLoadersConfigurator.swift`
  - `BrainMesh/Models/*.swift`
- Danach je nach Ziel-Feature den Host-Screen plus Loader lesen.
### Typischer Workflow für ein neues Feature
- [ ] Prüfen, ob das Feature graph-scoped ist → `graphID` nötig?
- [ ] Falls neues Modell: SwiftData-Schema anpassen und Backfill-/Migrationseinfluss bewerten.
- [ ] UI-Host klein halten; neue Verantwortungen in `+`-Dateien oder Subviews auslagern.
- [ ] Für schwere Reads einen Loader/Service mit eigenem `ModelContext` anlegen.
- [ ] Wenn Medien beteiligt sind: lokaler Cache + Hydrator + Import-Limits prüfen.
- [ ] Unit Tests für Loader/Service ergänzen.
### Gute Startpunkte nach Themengebiet
- Datenmodell / Sync:
  - `BrainMesh/Models/`
  - `BrainMesh/Bootstrap/`
  - `BrainMesh/Settings/SyncRuntime.swift`
- Entitäten / CRUD:
  - `BrainMesh/Mainscreen/`
- Graph / Performance:
  - `BrainMesh/GraphCanvas/`
- Stats:
  - `BrainMesh/Stats/`
- Import / Export:
  - `BrainMesh/GraphTransfer/`
---
## Quick Wins
1. **Expliziten SwiftData-Migrationsplan einführen**
   - Grund: Es gibt aktuell nur Bootstraps/Backfills, aber keine `VersionedSchema`-/`MigrationPlan`-Struktur.
2. **`UIBackgroundModes = remote-notification` verifizieren oder entfernen**
   - In `BrainMesh/Info.plist` vorhanden, aber kein klarer Push-Einstiegspunkt gefunden.
3. **`BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` weiter splitten**
   - Der Import-Koordinator ist groß und zustandslastig.
4. **Stats-Byteaggregation optimieren**
   - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift` lädt für Byte-Summen alle `MetaAttachment`-Objekte.
5. **`GraphStatsLoader.swift` in Cache-/Snapshot-/Reload-Teile aufspalten**
   - Aktuell mischt die Datei Caching, Revisionen und Orchestrierung.
6. **Unbenutzte / veraltete Dateien bereinigen**
   - `BrainMesh/Onboarding/Untitled.swift` ist laut Dateikommentar löschbar.
   - `BrainMesh/GraphSession.swift` hat im Codebestand keine Treffer außerhalb der Datei selbst.
7. **UI Tests von Template auf echte Smoke Tests anheben**
   - `BrainMeshUITests/` enthält derzeit nur Standard-Launch-Beispiele.
8. **CloudKit-Konstanten an einer Stelle bündeln**
   - Container-ID liegt sowohl in Entitlements als auch in `BrainMesh/Settings/SyncRuntime.swift`.
9. **Owner-/Graph-Scoping in Query-Buildern weiter vereinheitlichen**
   - Mehrere Loader bauen sehr ähnliche `FetchDescriptor`-/Predicate-Strukturen.
10. **Developer-Diagnostics sichtbarer machen**
   - Logging ist vorhanden (`BrainMesh/Observability/BMObservability.swift`), aber UI-seitig nur teilweise surfaced.
---
## Open Questions
- **UNKNOWN:** Welche Konfliktauflösung wird bei gleichzeitigen Multi-Device-Edits fachlich erwartet?
- **UNKNOWN:** Ob `UIBackgroundModes = remote-notification` noch aktiv genutzt wird oder Altlast ist.
- **UNKNOWN:** Ob außerhalb des ZIP zusätzliche Build-/Signing-/Secrets-Konfiguration existiert.
- **UNKNOWN:** Ob `GraphSession.swift` absichtlich als zukünftige Session-Abstraktion liegen bleibt oder Dead Code ist.
