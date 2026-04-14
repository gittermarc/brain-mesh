# ARCHITECTURE_NOTES.md

## Scope / Reading Notes
- Basis: gescannter Quellcode des hochgeladenen Projektstands.
- Fokus gemäß Vorgabe:
  1. Sync / Storage / Model
  2. Entry Points + Navigation
  3. Große Views / Services
  4. Konventionen + Workflows
- Alles, was im Code nicht sauber belegbar war, ist als **UNKNOWN** markiert.

## Entry Points + Navigation
### Composition Root
Pfad: `BrainMesh/BrainMeshApp.swift`
- Erzeugt den einzigen `ModelContainer`.
- Registriert Schema mit acht SwiftData-Modellen.
- Baut alle globalen Stores / Coordinators als `@StateObject`:
  - `AppearanceStore`
  - `DisplaySettingsStore`
  - `OnboardingCoordinator`
  - `GraphLockCoordinator`
  - `SystemModalCoordinator`
  - `ProEntitlementStore`
  - `RootTabRouter`
  - `GraphJumpCoordinator`
- Konfiguriert App-weite Loader/Hydrators über `AppLoadersConfigurator.configureAllLoaders(...)`.
- Triggert CloudKit/iCloud-Statusprüfung via `SyncRuntime`.

### App Shell
Pfad: `BrainMesh/AppRootView.swift`
- Wrappt `ContentView`.
- Führt Startup-Sequenz aus:
  - Graph-Existenz sicherstellen
  - `activeGraphID` initialisieren
  - Legacy-Daten migrieren/backfillen
  - Onboarding ggf. anzeigen
  - aktiven Graph-Lock durchsetzen
  - Bild-Hydrator autostarten
- Reagiert auf `scenePhase` für Auto-Lock und Grace-Handling bei System-Modalen.
- Präsentiert globale Modals:
  - Onboarding-Sheet
  - Fullscreen Graph-Unlock-Flow

### Root Navigation
Pfad: `BrainMesh/ContentView.swift`
- `TabView` mit 4 Root-Tabs:
  - Entitäten
  - Graph
  - Stats
  - Einstellungen
- Programmatic Tab Switching läuft über `RootTabRouter`.

### Screen-Navigation im Überblick
- `EntitiesHomeView`
  - eigener `NavigationStack`
  - Suche, Toolbar, AddEntity-Sheet, GraphPicker-Sheet, Display-Sheet
- `GraphCanvasScreen`
  - eigener `NavigationStack`
  - GraphPicker, Focus-Picker, Inspector, Entity-/Attribute-Details, Detailwert-Editor
  - Cross-tab Jump via `GraphJumpCoordinator`
- `GraphStatsView`
  - eigener `NavigationStack`
  - Scroll-basiertes Dashboard ohne tiefe Navigation im Host
- `SettingsView`
  - läuft innerhalb des Settings-Tabs bereits in einem `NavigationStack`
  - navigiert in Subscreens über `NavigationLink`

## Sync / Storage / Model
### Storage Stack
Pfad: `BrainMesh/BrainMeshApp.swift`
- Primärspeicher: SwiftData.
- Container-Konfiguration:
  - CloudKit-fähig via `ModelConfiguration(... cloudKitDatabase: .automatic)`
  - Private Database, keine sichtbare Shared/Public-DB-Konfiguration
- Release-Fallback:
  - falls CloudKit-Container fehlschlägt, lokaler SwiftData-Container ohne CloudKit
- Debug-Verhalten:
  - `fatalError` statt Fallback

### Observed Sync Runtime
Pfad: `BrainMesh/Settings/SyncRuntime.swift`
- Kapselt nur zwei Dinge:
  - Storage Mode `cloudKit` vs. `localOnly`
  - iCloud Account Status via `CKContainer.accountStatus()`
- Wichtig:
  - Das ist Diagnostik, nicht eigentliche Sync-Steuerung.
  - Es gibt keine sichtbare tiefe Metrik für Import-/Export-Latenzen, Konflikte, Pull-/Push-Status.

### App-seitige Migrations-/Repair-Pfade
#### Graph Bootstrap
Pfad: `BrainMesh/GraphBootstrap.swift`
- stellt sicher, dass mindestens ein Graph existiert
- migriert Legacy-Datensätze ohne `graphID`
- backfillt gefaltete Notiz-Indizes
- arbeitet auf dem MainActor im Startpfad

#### Attachment GraphID Migration
Pfad: `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- sehr wichtige Schutzmaßnahme gegen teure OR-Predicates
- Kommentar im Code benennt das Risiko explizit:
  - in-memory filtering auf `externalStorage`-Blobs
- nutzt gezielte owner-scoped Migrationen, um später einfache `a.graphID == gid`-Predicates zu erlauben

### Data Model Deep Notes
#### Graph als eigentliche Security- und Scope-Grenze
- `MetaGraph` trägt die aktiv genutzten Lock-Konfigurationen (`BrainMesh/Models/MetaGraph.swift`, `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`).
- `activeGraphID` ist zentraler Routing- und Filter-Schlüssel über viele Screens.
- Viele Loader nehmen `graphID` explizit als Input.

#### Link-Modell ist denormalisiert
Pfad: `BrainMesh/Models/MetaLink.swift`
- statt Relationships werden nur Endpunkt-UUIDs und Kind-Raws gespeichert.
- Vorteil:
  - sehr flexible Verbindung Entity↔Entity, Entity↔Attribute, Attribute↔Attribute
- Nachteil:
  - Lookup-Kosten steigen, wenn Labels oder Gegenknoten für große Mengen rekonstruiert werden müssen
  - Konsistenz muss aktiv gepflegt werden, z. B. bei Rename via `NodeRenameService`

#### Detail-Felder: Schema und Werte getrennt
Pfad: `BrainMesh/Models/DetailsModels.swift`
- saubere Trennung von Felddefinition und Wertinstanz
- geeignet für dynamische Form-/Detail-UI
- Risiken:
  - kein sichtbarer zentraler Schema-/Referential-Integrity-Service
  - Logik kann leicht in UI-Hosts zerstreut werden, wenn nicht diszipliniert gehalten

#### Attachment-Modell ist Blob-kritisch
Pfad: `BrainMesh/Attachments/MetaAttachment.swift`
- `@Attribute(.externalStorage)` ist richtig für große Daten
- Owner ist nicht als Relationship modelliert
- Folge:
  - Queries und Cleanup laufen über OwnerKind/OwnerID/GraphID
  - gute Performance hängt stark an sauberem `graphID`-Scoping und lokalen Cachepfaden

### File-/Image-Cache Layer
#### Image Store / Hydrator
Pfade:
- `BrainMesh/ImageStore.swift`
- `BrainMesh/ImageHydrator.swift`
- Muster:
  - NSCache + persistente Dateiablage
  - deduplizierte In-Flight-Loads
  - Auto-Hydration einmal pro Tag / on demand
- Nutzen:
  - verhindert Disk- oder Blob-Zugriffe im heißen UI-Pfad

#### Attachment Store / Thumbnailing / Hydration
Pfade:
- `BrainMesh/Attachments/AttachmentStore.swift`
- `BrainMesh/Attachments/AttachmentThumbnailStore.swift`
- `BrainMesh/Attachments/AttachmentHydrator.swift`
- Muster:
  - Lokale Materialisierung von Dateiinhalten
  - Vorschauthumbnails
  - begrenzte Parallelität über `AsyncLimiter`
- Architekturell gut:
  - trennt UI-Zugriff von SwiftData-Blob-Zugriff

### Import / Export
#### Export
Pfad: `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Export.swift`
- lädt alle graph-scoped Datensätze eines Graphen
- mappt sie in DTOs
- schreibt `.bmgraph` JSON in temporäre Datei
- Optionen für Notes/Icons/Images beeinflussen Exportumfang

#### Import
Pfad: `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
- Datei wird gelesen, dekodiert, validiert
- Importmodus im gescannten Stand: `.asNewGraphRemap`
- positive Punkte:
  - `Task.checkCancellation()` eingebaut
  - `Task.yield()` eingebaut
  - Batch-Saves eingebaut
  - Fortschrittsphasen vorhanden
- Restrisiken:
  - große Imports bleiben speicher- und IO-lastig
  - Teilstände bei Fehlern sind möglich, weil nicht als eine explizite transaktionale Unit sichtbar kapsuliert

### Offline / Multi-Device / Conflict Notes
- Offline-Benutzbarkeit lokal ist durch SwiftData + lokale Caches klar angelegt.
- Multi-Device-Sync hängt vollständig an SwiftData/CloudKit-Standardverhalten plus appseitigen Repair-Pfaden.
- Dedizierte Konfliktstrategie, Merge-Telemetrie oder Retry-Orchestrierung ist **UNKNOWN**.
- Doppelte `MetaGraph`-Records mit gleicher UUID werden bereits als reales Problem behandelt (`BrainMesh/GraphPicker/GraphDedupeService.swift`, `BrainMesh/GraphPicker/GraphDeletionService.swift`).
- Das ist ein deutliches Signal, dass Sync/Merge-Kantenfälle praktisch relevant sind.

## Big Files List
Top 15 Swift-Dateien nach Zeilen im gescannten Stand.

1. `BrainMesh/Settings/BrainMeshGuideView.swift` — 650 Zeilen
   - Zweck: In-App Guide / Hilfeoberfläche.
   - Risiko: große UI-Datei, hoher Änderungsradius, vermutlich geringe fachliche Kritikalität, aber schlechte Reviewbarkeit.

2. `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift` — 427 Zeilen
   - Zweck: Import/Export-State-Machine der Transfer-UI.
   - Risiko: viele Zustände, Alerts, Limits, Importmodi, Fehlerpfade in einer Datei.

3. `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift` — 409 Zeilen
   - Zweck: Bild-/Medienverwaltung für Nodes.
   - Risiko: UI, Dateizugriff, Delete-/Viewer-/Sheet-Flow eng gekoppelt.

4. `BrainMesh/Mainscreen/BulkLinkView.swift` — 367 Zeilen
   - Zweck: Massenverlinkung.
   - Risiko: viel lokaler Zustand, Duplikatlogik, potenziell große Datenmengen.

5. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — 362 Zeilen
   - Zweck: gemeinsame Mediengalerie in Node-Details.
   - Risiko: Gallery-/Attachment-/Preview-Logik in einem UI-Segment.

6. `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift` — 345 Zeilen
   - Zweck: Host für Entity-Detail-Screen.
   - Risiko: Screen-Host für viele Subflows; schnell zum God-View-Kandidaten.

7. `BrainMesh/PhotoGallery/PhotoGallerySection.swift` — 344 Zeilen
   - Zweck: Galerie-Sektion / Grid / Selektion.
   - Risiko: Scroll-/Thumbnail-/State-Kopplung.

8. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — 341 Zeilen
   - Zweck: vollständige Verbindungsansicht eines Knotens.
   - Risiko: große Listen, potenziell teure Link-Auflösung.

9. `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` — 335 Zeilen
   - Zweck: Kernimport von `.bmgraph`.
   - Risiko: Datenintegrität, Performance, Cancel/Resume-Verhalten.

10. `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — 331 Zeilen
   - Zweck: Markdown-/Text-Zubehör UI.
   - Risiko: imperative UIKit/SwiftUI-Kopplung, oft schwer zu testen.

11. `BrainMesh/Attachments/AttachmentImportPipeline.swift` — 326 Zeilen
   - Zweck: Datei-/Bild-/Video-Import, Größenkontrolle, Kompression.
   - Risiko: IO, Medienkodierung, Fehlerszenarien, Speicherverbrauch.

12. `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift` — 324 Zeilen
   - Zweck: Viewer für Galerie-Inhalte.
   - Risiko: Speicher-/Gesture-/Präsentationskomplexität.

13. `BrainMesh/Pro/ProCenterView.swift` — 322 Zeilen
   - Zweck: Pro-Oberfläche / Upsell.
   - Risiko: vor allem UI-Komplexität, weniger Kernarchitektur-Risiko.

14. `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift` — 318 Zeilen
   - Zweck: Browser-Navigation für Galerie.
   - Risiko: Paging-/Selektion-/Viewer-Kopplung.

15. `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` — 317 Zeilen
   - Zweck: Dashboard-Host, Ladeorchestrierung, Refresh/Token-Guards.
   - Risiko: asynchroner Host-State, leicht anfällig für Zustandsdrift.

## Hot Path Analyse

### Rendering / Scrolling
#### 1) Graph Canvas Physics + Re-Rendering
Pfade:
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`

Konkrete Hotspot-Gründe:
- `positions` und `velocities` ändern sich auf einem 30-FPS-Timer.
- Jede Mutation invalidiert den View-State des Canvas-Hosts.
- Physics enthält O(n²)-Paarloop für Repulsion/Kollisionen.
- Große Graphen werden nur über `maxNodes` / `maxLinks` begrenzt, nicht algorithmisch skaliert.

Bereits vorhandene Gegenmaßnahmen:
- `simulationAllowed` gate via Sichtbarkeit + `scenePhase` + Sheet-Präsenz.
- Schlafmodus nach Idle-Zeit.
- Spotlight-Physics über `physicsRelevant`.
- vorgerechnete Caches (`drawEdgesCache`, `lensCache`, `detailsPeekChips`, `entityFieldsPeekItems`).
- MiniMap-Snapshot wird bewusst auf 5 FPS gedrosselt.

Bewertung:
- Gut entschärft, aber weiterhin klarer P0-Hotspot der App.

#### 2) Entities Home Suche
Pfade:
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Body.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Counts.swift`

Konkrete Hotspot-Gründe:
- Suche läuft zwar off-main, aber über mehrere Fetches über Entities, Attributes und Links.
- Link-Notiz-Treffer lösen Gegenknoten teils per Einzel-Fetch auf.
- Attribut- und Link-Counts werden als Vollscan über den Graphen berechnet.

Bereits vorhandene Gegenmaßnahmen:
- Debounce im Screen (`Task.sleep`).
- Off-main Loader mit eigenem `ModelContext`.
- Kurze TTL-Caches für Counts (8 Sekunden).
- Suchindizes über gefaltete String-Felder.

Bewertung:
- Für normale Datenmengen solide.
- Für große Graphen wird Link-Notiz-Suche der erste echte Skalierungshebel sein.

#### 3) Node Detail Media / Photo Gallery
Pfade:
- `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
- `BrainMesh/PhotoGallery/PhotoGallerySection.swift`
- `BrainMesh/PhotoGallery/PhotoGalleryViewerView.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`

Konkrete Hotspot-Gründe:
- viele Thumbnails, Viewer-Zustände und Medienaktionen in UI-nahen Hosts
- potenziell hohe Speicherlast bei Galerie-/Viewer-Wechseln
- Medienzugriffe sind naturgemäß IO-lastig

Bereits vorhandene Gegenmaßnahmen:
- lokaler Cache-Layer
- Preview-/All-Loader statt direkter Blob-Zugriffe im Renderpfad
- Thumbnail Stores

Bewertung:
- Hotspot vor allem in UX-Flows und Speicherverhalten, weniger in roher Query-Architektur.

### Sync / Storage
#### 4) Attachment Queries auf Blob-lastigen Daten
Pfade:
- `BrainMesh/Attachments/MetaAttachment.swift`
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- `BrainMesh/Attachments/AttachmentStore.swift`

Konkrete Hotspot-Gründe:
- `externalStorage`-Blobs sind teuer, wenn SwiftData in-memory filtern muss.
- Owner ist nicht als Relationship modelliert.
- falsche Predicates können IO und Speicher massiv aufblasen.

Architekturreaktion im Code:
- explizite Migration von `graphID == nil`
- insistiert auf store-translatable Predicates

Bewertung:
- Einer der wichtigsten Speicher-/Performance-Hotspots des Projekts.
- Der Code behandelt das bereits richtig defensiv.

#### 5) Graph Transfer Import
Pfad: `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`

Konkrete Hotspot-Gründe:
- große Datei einlesen
- viele DTO→Model-Objekte erzeugen
- ID-Remapping-Dictionaries halten
- Batch-Saves und Kontext-Mutationen

Bereits vorhandene Gegenmaßnahmen:
- Batch-Save
- Yield/Cancellation-Strides
- Fortschrittsphasen

Risiken:
- große Imports bleiben langlaufend
- Fehler im mittleren Verlauf können Teilstände erzeugen
- kein sichtbarer Resume-/Rollback-Mechanismus

#### 6) Stats Aggregation
Pfade:
- `BrainMesh/Stats/GraphStatsLoader.swift`
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Media.swift`
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Structure.swift`

Konkrete Hotspot-Gründe:
- Vollfetch von Attachments zum Summieren von `byteCount`
- Vollfetch aller Attachments für Media-Breakdown
- Vollfetch aller Entities/Attributes/Links für Struktur-Breakdown
- jede Dashboard-Neuberechnung hängt an diesen Scans

Bereits vorhandene Gegenmaßnahmen:
- Loader läuft detached/off-main
- per-graph Counts werden lazy geladen
- Dashboard-Snapshot ist in Wertobjekte ausgelagert

Bewertung:
- Kein UI-Blocker, aber klar teurer Hintergrundpfad.
- Gute Kandidaten für sekundäre Aggregations-/Indexdaten.

### Concurrency
#### 7) MainActor Contention im Startup
Pfade:
- `BrainMesh/AppRootView.swift`
- `BrainMesh/GraphBootstrap.swift`
- `BrainMesh/Security/GraphLock/GraphLockCoordinator.swift`

Konkrete Hotspot-Gründe:
- Startpfad macht mehrere MainActor-Aktivitäten nacheinander
- beinhaltet potenzielle Saves/Migrationen
- kombiniert Startup-Work mit UI-Präsentation

Bewertung:
- aktuell wahrscheinlich akzeptabel, aber sensibel bei weiter wachsender Startup-Logik.

#### 8) Late-arriving Task Results / State Drift
Pfade:
- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+LoadScheduling.swift`
- `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Body.swift`

Positiv:
- Token-basierte Guards gegen stale async results sind vorhanden.
- Cancellation wird ernst genommen.

Restrisiko:
- Muster ist verteilt über mehrere Features.
- Kein einheitlicher Loader-Orchestrierungsstandard.

#### 9) Shared ModelContainer Configuration as Fire-and-Forget
Pfad: `BrainMesh/Support/AppLoadersConfigurator.swift`
- Konfiguration läuft absichtlich fire-and-forget.
- Vorteil: Start bleibt leicht.
- Risiko: erste Screens können theoretisch vor vollständiger Loader-Konfiguration starten.
- Im Stats-Host ist das teilweise bereits mitigiert durch ein initiales `Task.yield()` vor dem ersten Load.

## Große Views / Services: Wartbarkeit und Performance
### Positiv auffällige Muster
- Feature-Hosts werden häufig in Screen + Extension-Partials gesplittet.
- Off-main Loader/Services sind schon stark etabliert.
- Snapshots/DTOs reduzieren direkte `@Model`-Kopplung in der UI.
- Globale Stores für Appearance/Display verhindern `UserDefaults`-Chaos.

### Wartbarkeits-Hotspots
#### GraphTransferViewModel
Pfad: `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift`
- UI-State, Import/Export-Flow, Pro-Limits, Alerts und Dateifluss wirken eng gekoppelt.
- Vorschlag:
  - `GraphTransferExportController`
  - `GraphTransferImportController`
  - `GraphTransferReplaceController`
  - separater `GraphTransferAlertsState`

#### EntityDetailView + NodeDetailShared*
Pfade:
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/*`
- Der Detailbereich ist funktional stark, aber verteilt über viele große UI-Dateien.
- Risiko:
  - Media, Connections, Markdown, Details Values, Images und Actions laufen nah beieinander.
- Vorschlag:
  - noch klarere Trennung zwischen Screen-Host, Read-Only Sections und Edit/Action-Flows.

#### GraphCanvasScreen
Pfade:
- `BrainMesh/GraphCanvas/GraphCanvasScreen/*`
- Schon gesplittet, aber weiterhin großer State-Host.
- Risiko:
  - viele `@State`-Variablen
  - viele Reaktionsketten in `.onChange` / `.task`
- Vorschlag:
  - dedizierte `GraphCanvasScreenState`-Struktur oder intern gekapselte view-state controllerartige Bausteine.

## Refactor Map
### Konkrete Splits
#### 1) GraphTransferViewModel weiter zerlegen
- Aktuell: `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift`
- Ziel-Dateien:
  - `GraphTransferViewModel+Export.swift`
  - `GraphTransferViewModel+Import.swift`
  - `GraphTransferViewModel+Replace.swift`
  - `GraphTransferViewModel+Alerts.swift`
- Nutzen:
  - kleinere PRs
  - weniger State-Verzahnung
  - klarere Testbarkeit

#### 2) Entity Detail Host vs. Sections sauber trennen
- Aktuell: `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- Ziel:
  - Host-Datei nur für Navigation/Sheets/Actions
  - Sections in kleine, domainbezogene Files
  - Media-/Connections-/Details-Editoren konsequent auslagern

#### 3) Stats Host von Snapshot-Compose stärker trennen
- Aktuell:
  - `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - `BrainMesh/Stats/GraphStatsService/*`
- Ziel:
  - dedizierte Snapshot-Composer mit klaren Cache-Invalidation-Hooks
  - UI-Host bleibt reiner State/Presentation-Container

### Cache- / Index-Ideen
#### 1) Link Endpoint Resolution Cache
Betroffene Dateien:
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift`

Idee:
- kleine owner-/node-ID-basierte Lookup-Map für Batch-Auflösungen im Loader-Kontext
- statt Einzel-Fetch pro EntityID/AttributeID bei Link-Notiz-Treffern

Invalidation:
- pro Loader-Lauf neu oder graph-scoped TTL

#### 2) Stats Aggregation Cache
Betroffene Dateien:
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Media.swift`
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Structure.swift`

Idee:
- graph-scoped Snapshot-Cache mit Zeitstempel oder Mutationsversion
- Attachment-Bytes, Media-Toplists, Hub-Rankings nicht bei jedem Öffnen vollständig neu berechnen

Invalidation:
- bei Attachment-/Entity-/Attribute-/Link-Mutationen des betreffenden Graphen

#### 3) Import Sidecar Summary
Betroffene Dateien:
- `BrainMesh/GraphTransfer/GraphTransferService/*`
- `BrainMesh/Stats/*`

Idee:
- während Import bereits leichtgewichtige Summary-Daten sammeln
- teure Post-Import-Scans für Stats reduzieren

### Vereinheitlichungen
#### 1) Loader Host Pattern standardisieren
Aktuell verteilt in:
- `EntitiesHomeView`
- `GraphStatsView`
- `GraphCanvasScreen`

Vorschlag:
- ein konsistentes Muster für:
  - `loadTask`
  - token guard
  - `isRefreshing`
  - error state
  - stale result handling
- nicht als großes Framework, sondern als kleines internes Pattern-Template.

#### 2) Graph Scope als klarer Architekturvertrag
- Neue Datenmodelle sollten `graphID` immer explizit tragen, wenn sie graphbezogen sind.
- Owner-only Scoping wie bei Attachments bleibt fehleranfälliger.
- Wenn neue Modelle blob-/dateinah sind, sollte `graphID` von Start an Pflicht sein.

#### 3) Sync/Repair-Pfade dokumentieren
- `GraphBootstrap`, `AttachmentGraphIDMigration`, `GraphDedupeService` und `GraphDeletionService` bilden faktisch bereits eine Repair-Schicht.
- Diese sollte architektonisch explizit benannt werden.
- Sonst werden in künftigen PRs schnell widersprüchliche Reparaturpfade hinzugefügt.

## Risiken & Edge Cases
### Datenverlust / Inkonsistenz
- Import ist batch-save-basiert und nicht sichtbar vollständig rollback-fähig.
- Duplicate Graph IDs sind bereits als reales Problem adressiert.
- Attachment-Cleanup hängt an OwnerKind/OwnerID/GraphID, nicht an starken Relationships.

### Migrationen
- Kein sichtbarer expliziter SwiftData-Migrationsplan.
- App-seitige Migrationspfade funktionieren nur für die Fälle, die aktiv bedacht wurden.
- Neue graph-scoped Modelle ohne Migrationsstrategie wären risikoreich.

### Offline / Sync
- Release-Fallback auf local-only kann zu „es speichert, aber sync’t nicht“-Situationen führen.
- `SyncRuntime` macht das sichtbar, aber nicht tiefer diagnostizierbar.

### Multi-Device / Concurrency
- Doppelte Graph-UUID-Records deuten auf Merge-/Sync-Kantenfälle.
- Rename/Link-Label-Denormalisierung erfordert Disziplin, sonst driften Labels.

### Security
- Graph-Lock ist klar implementiert.
- Ob Entity-/Attribute-Lock-Felder produktiv genutzt werden sollen oder Altlast sind, ist **UNKNOWN**.
- Falls diese Felder nicht genutzt werden, erhöhen sie mentale Komplexität ohne Produktnutzen.

### Background / Push
- `remote-notification` ist in `BrainMesh/Info.plist` aktiviert.
- Ein klarer App-seitiger Push-Handling-Pfad wurde im gescannten Stand nicht gefunden.
- Ob dies für zukünftige Features reserviert ist oder Altlast ist, ist **UNKNOWN**.

## Observability / Debuggability
### Bereits vorhanden
- `BrainMesh/Observability/BMObservability.swift`
  - `BMLog.load`
  - `BMLog.expand`
  - `BMLog.physics`
  - `BMDuration`
- Physics loggt Rolling-Window-Durchschnitt und Maximum je 60 Ticks (`BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`).
- Sync-Mode und iCloud-Accountstatus sind in Settings sichtbar (`BrainMesh/Settings/SyncRuntime.swift`).

### Was fehlt oder nur schwach sichtbar ist
- zentrale Mutations-/Sync-Metriken pro Graph
- Import-/Export-Dauerhistorie
- dedizierte Cache-Hit/Miss-Telemetrie für Bild-/Attachment-Layer
- reproduzierbare Diagnoseansicht für Duplicate-Graph-/Migration-/Repair-Ereignisse

### Praktische Repro-Hebel
- Graph Canvas Performance:
  - große Graphen laden
  - Fokus/Neighborhood vs. Global vergleichen
  - Physik-Logs beobachten
- Stats Hotspots:
  - viele Attachments mit hoher Bytezahl
  - Dashboard öffnen und Refresh triggern
- Attachment-Query-Risiken:
  - Legacy-Attachments ohne `graphID` simulieren
  - prüfen, ob Migration anspringt und Queries sauber bleiben
- Sync-Kantenfälle:
  - Multi-Device-Szenarien mit Graph-Anlage/Löschung/Rename
  - Duplicate-Graph-Reparaturpfad validieren

## Open Questions
1. **UNKNOWN**: Gibt es einen absichtlich nicht im Scan sichtbaren Push-/Remote-Notification-Verarbeitungsweg trotz `UIBackgroundModes = remote-notification`?
2. **UNKNOWN**: Sind die Lock-Felder auf `MetaEntity` und `MetaAttribute` geplante Zukunftslogik oder Altlasten?
3. **UNKNOWN**: Gibt es außerhalb des gescannten Projekts eine dokumentierte Konflikt-/Merge-Strategie für SwiftData/CloudKit?
4. **UNKNOWN**: Ist `GraphSession.swift` bewusst vorbereitet oder faktisch ungenutzt?
5. **UNKNOWN**: Werden `MetaDetailsTemplate`-Flows vollständig produktiv genutzt oder ist das Modul noch teilweise vorbereitet?
6. **UNKNOWN**: Gibt es eine bewusste Entscheidung gegen einen expliziten `SchemaMigrationPlan`, oder fehlt er schlicht noch?
7. **UNKNOWN**: Wie sollen Teilimporte nach Fehlern oder User-Abbruch fachlich behandelt werden? Aktuell ist nur technische Cancellation sichtbar.
8. **UNKNOWN**: Gibt es Last-/Mengenannahmen für maximale Graphgröße, Attachmentzahl und Importgröße?

## First 3 Refactors I would do (P0)
### 1) EntitiesHome Link-Note Search batchfähig machen
- Ziel:
  - N+1-artige Endpoint-Auflösung bei Link-Notiz-Suche reduzieren.
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
  - ggf. kleine Helper-Datei im gleichen Loader-Ordner
- Risiko:
  - gering bis mittel
  - Gefahr liegt primär in veränderten Suchtreffer-Mengen bei unsauberer Batch-Logik
- Erwarteter Nutzen:
  - schnelleres Suchen in großen Graphen
  - weniger SwiftData-Fetches pro Suchlauf
  - robusteres Skalierungsverhalten ohne UI-Umbau

### 2) Stats Aggregation graph-scoped cachen
- Ziel:
  - teure Vollscans für Dashboard-Stats reduzieren.
- Betroffene Dateien:
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Media.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Structure.swift`
- Risiko:
  - mittel
  - Invalidation muss sauber sein, sonst stale Stats
- Erwarteter Nutzen:
  - spürbar billigere Stats-Öffnung/Refreshes
  - bessere Akkulaufzeit
  - weniger Hintergrundlast auf großen Datensätzen

### 3) GraphTransferViewModel in Zustandsbereiche zerlegen
- Ziel:
  - UI-State-Machine des Import/Export-Features reviewbarer und testbarer machen.
- Betroffene Dateien:
  - `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferViewModel.swift`
  - neue Partials oder kleine Controller-Dateien im gleichen Ordner
- Risiko:
  - mittel
  - kein Fachrisiko, aber viele UI-gebundene Zustände müssen sauber umgezogen werden
- Erwarteter Nutzen:
  - deutlich niedrigere Änderungsangst in künftigen PRs
  - klarere Trennung von Export, Import, Replace und Alert-Handling
  - bessere Grundlage für zusätzliche Importmodi oder stärkere Fehlerdiagnostik
