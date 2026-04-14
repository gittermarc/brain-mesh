# ARCHITECTURE_NOTES.md

## Scope / Reading Notes
- Analysebasis: aktueller Projektstand aus dem bereitgestellten ZIP.
- Fokus priorisiert nach Vorgabe:
  1. Sync / Storage / Model
  2. Entry Points + Navigation
  3. Große Views / Services
  4. Konventionen / typische Workflows
- Alles, was nicht klar aus Code / Projektdateien ableitbar war, ist als **UNKNOWN** markiert.

## Big Files List — Top 15 nach Zeilen
1. `BrainMesh/Settings/BrainMeshGuideView.swift` — **650 Zeilen**
   - Zweck: In-App-Guide / Hilfe.
   - Risiko: kein primärer Runtime-Hotspot, aber hoher Compile-, Review- und Merge-Aufwand.
2. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift` — **362 Zeilen**
   - Zweck: Gallery-/Media-Shared-UI für Detail-Screens.
   - Risiko: viele Zustände und Medienflüsse in einer Datei, fehleranfällig bei Erweiterungen.
3. `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift` — **361 Zeilen**
   - Zweck: zentrale Stats-Domainlogik.
   - Risiko: breites Verantwortungsprofil, zählt / aggregiert / definiert Revisionen.
4. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — **341 Zeilen**
   - Zweck: vollständige Connections-Ansicht.
   - Risiko: viele UI-Zweige, Sort-/Segment-/Routing-Logik dicht beieinander.
5. `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` — **335 Zeilen**
   - Zweck: Import, Remap, Batching, Save-Zyklen.
   - Risiko: Datenintegrität, Performance, Cancel-/Progress-Verhalten.
6. `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — **331 Zeilen**
   - Zweck: UIKit-Accessory-View für Markdown-Eingabe.
   - Risiko: UIKit/SwiftUI-Interop, Fokus-/Layout-/Keyboard-Ränder.
7. `BrainMesh/Attachments/AttachmentImportPipeline.swift` — **326 Zeilen**
   - Zweck: Dateien, Videos, Gallery-Bilder importieren und normalisieren.
   - Risiko: I/O, Dateigrößen, Recompression, Security-scoped URLs.
8. `BrainMesh/Pro/ProCenterView.swift` — **322 Zeilen**
   - Zweck: Pro-Info / Upgrade-UI.
   - Risiko: eher Wartbarkeit / Merge, geringer Architektur-Hotspot.
9. `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` — **321 Zeilen**
   - Zweck: Stats-Host, Ladeorchestrierung, Refresh, Detailzustände.
   - Risiko: UI-State + Loader-State + Caching-Interaktion.
10. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift` — **317 Zeilen**
    - Zweck: Suchlogik über Entitäten, Attribute und Link-Notizen.
    - Risiko: Multi-Fetch + In-Memory-Dedupe/Sort + Cancel-Handling.
11. `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard/NodeDetailsValuesCard+Components.swift` — **314 Zeilen**
    - Zweck: Rendering vieler Detailwert-Komponenten.
    - Risiko: UI-Verzweigung, potenziell viel invalidierbarer Code.
12. `BrainMesh/Icons/IconPickerView.swift` — **309 Zeilen**
    - Zweck: Such- und Auswahl-UI für SF Symbols.
    - Risiko: eher UI-Wartbarkeit als Storage-/Sync-Risiko.
13. `BrainMesh/Onboarding/DetailsOnboardingSheetView.swift` — **308 Zeilen**
    - Zweck: geführter Details-Onboarding-Flow.
    - Risiko: Sheet-Orchestrierung und Abhängigkeit auf Live-Daten.
14. `BrainMesh/Stats/GraphStatsLoader.swift` — **305 Zeilen**
    - Zweck: Stats-Snapshots, Revisionscache, detached work.
    - Risiko: Cache-Kohärenz, Stale Results, mehrfacher `ModelContext`-Zugriff.
15. `BrainMesh/Settings/Display/DisplaySettingsStore.swift` — **305 Zeilen**
    - Zweck: UI-Settings, Persistenz, Migrationshilfen.
    - Risiko: breite Zuständigkeit, AppStorage-/Migration-Komplexität.

## Entry Points + Navigation
### App Entry
- `BrainMesh/BrainMeshApp.swift`
  - Baut den SwiftData-Schema-Container.
  - Setzt CloudKit als Standard.
  - Fällt im Release auf lokal-only zurück.
  - Startet `SyncRuntime.refreshAccountStatus()` detached.
  - Konfiguriert in `AppLoadersConfigurator.configureAllLoaders(with:)` appweite Loader/Hydratoren.

### Root Orchestrierung
- `BrainMesh/AppRoot/AppRootView.swift`
  - Umschließt `ContentView()`.
  - Reagiert auf `scenePhase`.
  - Zeigt Onboarding-Sheet.
  - Zeigt Fullscreen-Unlock bei geschützten Graphen.
- `BrainMesh/AppRoot/AppRootView+Startup.swift`
  - Startup-Sequenz:
    - Graph bootstrap
    - Lock enforcement
    - image hydration
    - onboarding presentation
- `BrainMesh/AppRoot/AppRootView+ScenePhase.swift`
  - Debounced background lock.
  - Schutz vor ungewolltem Locking bei Systemmodals / Face ID / Picker.

### Root Tabs
- `BrainMesh/ContentView.swift`
  - `EntitiesHomeView`
  - `GraphCanvasScreen`
  - `GraphStatsView`
  - `SettingsView`

### Programmatic Routing
- `BrainMesh/RootTabRouter.swift`
  - Kleine `ObservableObject`-Router-Schicht.
- `BrainMesh/GraphJumpCoordinator.swift`
  - Staged Jump in den Graph-Tab mit Zielknoten und optionalem Centering.

## Hot Path Analyse

## Rendering / Scrolling
### 1) Graph Physics Loop
- Datei: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Grund:
  - **30 FPS Timer** via `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)`.
  - **O(n²) pair loop** über `simNodes` für Repulsion + Collision.
  - zusätzliche Spring-Loops über `physicsEdges`.
  - jede Tick-Runde schreibt `positions` und `velocities` zurück in `@State`.
- Konkretes Risiko:
  - exzessive View invalidation
  - CPU-Last bei vielen Nodes
  - Energieverbrauch auf iPhone/iPad
- Bereits vorhandene Gegenmaßnahmen:
  - `simulationAllowed` Gate in `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+LoadScheduling.swift`
  - Idle/Sleep-Mechanik
  - Spotlight-/Relevant-Nodes-Begrenzung
  - minimap snapshot throttling

### 2) Graph-Neighborhood Load
- Datei: `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Neighborhood.swift`
- Grund:
  - BFS über Hops
  - batch fetch pro Hop
  - zusätzliche Kanten-Fetches auf sichtbare IDs
  - In-Memory-Dedupe über `unique()`
- Konkretes Risiko:
  - heavy sort / heavy fetch
  - große `visibleIDs`-Mengen
  - Snapshot-Build kann bei Graphwechsel / Hops / Fokus spürbar sein
- Positiv:
  - läuft bereits off-main im DataLoader-Kontext
  - `maxNodes`, `maxLinks`, `degreeCap` begrenzen Auslastung

### 3) Entities Home Search
- Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
- Grund:
  - Search fächert über Entitäten, Attribute und Link-Notizen auf.
  - Owner-Resolution und Link-Endpunkt-Auflösung passieren zusätzlich.
  - stabile Sortierung + Notizen-only-Markierung am Ende.
- Konkretes Risiko:
  - multi-fetch
  - in-memory dedupe
  - bei sehr großen Datenbeständen spürbarer Reload trotz Debounce
- Positiv:
  - läuft im Loader, nicht im SwiftUI-`body`

### 4) Entities Home Count Derivation
- Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Counts.swift`
- Grund:
  - lädt **alle** Attribute eines Graphen bzw. **alle** Links eines Graphen und aggregiert dann in-memory.
- Konkretes Risiko:
  - avoidable full scans
  - keine echte Aggregation im Store
- Hinweis:
  - bei überschaubaren Datenmengen okay, aber Skalierung begrenzt.

### 5) Detail Media Preview Query
- Datei: `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader+Query.swift`
- Grund:
  - für graph-scoped Owner werden zwei Query-Sets gefahren:
    - aktueller Graph
    - `graphID == nil` Legacy-Scope
  - Counts und PreviewRecords werden separat geholt und dann gemerged.
- Konkretes Risiko:
  - doppelte Queries pro Preview-Typ
  - repeated legacy/current merge logic
- Begründung ist nachvollziehbar, aber die Logik ist verteilt und wiederholt.

### 6) Stats Dashboard Rendering + Load Coupling
- Dateien:
  - `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
- Grund:
  - View orchestriert Refresh, Dashboard-Snapshot, Lazy-Per-Graph-Loads.
- Konkretes Risiko:
  - stale-result handling
  - cache invalidation complexity
  - UI-State und Daten-State eng gekoppelt

## Sync / Storage
### 1) SwiftData + CloudKit Setup
- Datei: `BrainMesh/BrainMeshApp.swift`
- Positiv:
  - klare zentrale Container-Erzeugung
  - Release-Fallback auf lokal-only ist sauber explizit
- Risiko:
  - DEBUG-fatalError ist für frühe Fehlersichtbarkeit gut, kann aber lokale Arbeit blockieren, wenn Signing/Container wackelt
- **UNKNOWN**:
  - ob mehrere Stores / zukünftige Store-Splitting-Pläne vorgesehen sind

### 2) Startup Repairs auf dem MainActor
- Dateien:
  - `BrainMesh/AppRoot/AppRootView+Startup.swift`
  - `BrainMesh/Bootstrap/GraphBootstrap.swift`
  - `BrainMesh/Bootstrap/GraphBootstrap+Repair.swift`
  - `BrainMesh/Bootstrap/GraphBootstrap+Backfill.swift`
- Grund:
  - Default-Graph sichern
  - Legacy-Records migrieren
  - `notesFolded` backfillen
- Konkretes Risiko:
  - launch-time work
  - MainActor contention
  - Startzeit hängt von Datenmenge ab
- Einschätzung:
  - aktuell wahrscheinlich okay für moderate Datenmengen, aber schlecht skalierend

### 3) Attachment Aggregation lädt vollständige Rows
- Datei: `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
- Grund:
  - `totalAttachmentAggregate()` lädt `FetchDescriptor<MetaAttachment>()`
  - `attachmentAggregate(for:)` lädt alle Attachments für einen Graphen
  - Bytes werden dann per Schleife aufsummiert
- Konkretes Risiko:
  - full fetch for aggregate
  - unnötige Objektmaterialisierung
  - besonders teuer, wenn viele / große externe Assets existieren
- Das ist einer der klarsten Storage-Hebel im Projekt.

### 4) Medienimport / Hydration
- Dateien:
  - `BrainMesh/Attachments/AttachmentImportPipeline.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - `BrainMesh/Images/ImageHydrator.swift`
  - `BrainMesh/Images/ImageStore.swift`
  - `BrainMesh/Attachments/AttachmentStore.swift`
- Positiv:
  - Pipelines sind klar getrennt von UI.
  - lokale Caches sind deterministisch.
  - Gallery-Bilder werden normalisiert, um Größenkontrolle zu behalten.
- Konkrete Risiken:
  - heavy I/O
  - decode/recompress cost
  - Background- und Foreground-Arbeit kann zeitweise konkurrieren
  - möglicher Disk-Waste, wenn Invalidierungsstrategie nicht sauber mitwächst

### 5) GraphTransfer exportiert aktuell keine Attachments
- Dateien:
  - `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Export.swift`
  - `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
- Fakt aus Code:
  - Export umfasst Graph, Entities, Attributes, DetailFieldDefinitions, DetailFieldValues, Links.
  - `MetaAttachment` taucht in der Transfer-Pipeline nicht auf.
- Risiko:
  - Nutzer könnte vollständigen Graph-Export erwarten, bekommt aber ohne Medien nur einen Teil.
- **UNKNOWN**:
  - ob das Produkt-Intent ist oder nur aktueller Scope.

### 6) Keine explizite Versioned Migration gefunden
- Relevante Pfade durchsucht:
  - `BrainMesh/Models/*`
  - `BrainMesh/BrainMeshApp.swift`
  - Projektweit nach `VersionedSchema`, `SchemaMigrationPlan`
- Ergebnis:
  - keine explizite Versionierung im gescannten Repo gefunden.
- Risiko:
  - wachsender Druck auf ad-hoc Backfills / Repairs
  - weniger klarer Upgrade-Pfad für zukünftige Modeländerungen

## Concurrency
### 1) Viele Loader arbeiten richtig off-main, aber Context-Erzeugung ist breit verteilt
- Beispiele:
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/*`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/*`
- Positiv:
  - UI wird entlastet.
  - Snapshot-Pattern reduziert `@Model`-Leakage über Threads.
- Risiko:
  - Wiederholte `ModelContext(container.container)`-Erzeugung an vielen Stellen.
  - inkonsistente Cache-/Revision-Muster zwischen Features.

### 2) Detached Tasks mit eigener Lebenszeit
- Beispiele:
  - `BrainMesh/BrainMeshApp.swift` → `Task.detached` für `SyncRuntime.refreshAccountStatus()`
  - `BrainMesh/Stats/GraphStatsLoader.swift` → `Task.detached(priority: .utility)`
  - `BrainMesh/Settings/SyncMaintenanceView.swift` → `Task.detached` für Cache-Größen
- Risiko:
  - Task lifetime nicht immer eng an UI-Lebenszyklus gebunden
  - Debugging von Race Conditions erschwert
- Einschätzung:
  - in mehreren Fällen vertretbar, aber nicht durchgängig vereinheitlicht

### 3) MainActor-Grenzen sind sichtbar designt, aber fragil
- Dateien:
  - `BrainMesh/RootTabRouter.swift`
  - `BrainMesh/GraphJumpCoordinator.swift`
- Positiv:
  - Typen sind bewusst **nicht** als Ganzes `@MainActor` markiert, um `ObservableObject`-Conformance-Probleme zu vermeiden.
- Risiko:
  - strikte Swift-6-Isolation bleibt sensibel; Methodengrenzen müssen dauerhaft sauber gehalten werden.

### 4) Unbounded / repeated work vermeiden bereits mehrere Files aktiv
- Beispiele:
  - `GraphCanvasScreen` verwendet cancellable load task + token guard.
  - `EntitiesHomeView` debounced Reload.
  - Physics kann schlafen.
- Positiv:
  - es gibt ein klares Bewusstsein für Task-Lifetime und UI-Überlappung.

## Refactor Map

## Konkrete Splits
### A) `GraphStatsService.swift` weiter in fachliche Teilbereiche schneiden
- Aktueller Zustand:
  - Service + Counts + Revisionen + Media/Structure/Trends-Kontext liegen nahe beieinander.
- Sinnvoller Split:
  - `GraphStatsService+Counts.swift`
  - `GraphStatsService+Media.swift`
  - `GraphStatsService+Structure.swift`
  - `GraphStatsService+Trends.swift`
  - `GraphStatsService+Revision.swift`
- Nutzen:
  - kleinere Verantwortungen
  - weniger Merge-Konflikte
  - gezieltere Tests pro Teilbereich

### B) `AttachmentImportPipeline.swift` in drei Spezialpfade zerlegen
- Ziel-Dateien:
  - `AttachmentImportPipeline+Files.swift`
  - `AttachmentImportPipeline+GalleryImages.swift`
  - `AttachmentImportPipeline+Videos.swift`
- Nutzen:
  - Policies klarer
  - weniger Verzweigungen
  - geringeres Fehlerrisiko bei Änderungen an Video-/Bildimport

### C) `GraphTransferService+Import.swift` in Phasen-Splits aufteilen
- Ziel-Dateien:
  - `GraphTransferService+Import.Inspect.swift`
  - `GraphTransferService+Import.Entities.swift`
  - `GraphTransferService+Import.AttributesAndFields.swift`
  - `GraphTransferService+Import.ValuesAndLinks.swift`
- Nutzen:
  - Mapping-/Remap-Logik wird reviewbarer
  - Progress-/Save-Batching klarer

### D) `BrainMeshGuideView.swift` datengetrieben machen
- Aktueller Zustand:
  - sehr große UI-Datei
- Ziel:
  - Inhalte als Datenmodell oder Abschnittsarrays kapseln
  - Rendering-Komponenten klein halten
- Nutzen:
  - geringe funktionale Gefahr, hoher Wartbarkeitsgewinn

## Cache- / Index-Ideen
### 1) Attachment Aggregate Cache
- Betroffene Dateien:
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - Attachment-Mutationspfade in `BrainMesh/Attachments/*` und Detail-Management-Flows
- Idee:
  - pro Graph `attachmentCount` + `attachmentBytes` inkrementell mitführen oder in einer separaten kleinen Aggregatstruktur cachen
- Invalidation:
  - Insert / Delete / Replace / ContentKind-Änderung / GraphID-Migration
- Nutzen:
  - Vollfetch vermeiden

### 2) Spatial Partitioning für Graph Physics
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Idee:
  - Bucket Grid / Spatial Hash für Repulsion- und Collision-Nachbarschaft
- Invalidation:
  - pro Tick neu oder inkrementell aus Positionen rebuilt
- Nutzen:
  - reduziert O(n²)-Anteil auf näherungsweise lokale Nachbarschaften

### 3) Vereinheitlichte Graph-Scope-Predicate-Factory
- Betroffene Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader+Query.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryQuery.swift`
  - `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
  - `BrainMesh/Stats/GraphStatsService/*`
  - `BrainMesh/Mainscreen/MediaAllLoader.swift`
- Idee:
  - zentrale Helper für `exact graph`, `legacy nil`, `all scopes`
- Nutzen:
  - weniger Predicate-Duplikate
  - geringere Gefahr inkonsistenter Legacy-Behandlung

### 4) Search Index Evolution bewusst modellieren
- Betroffene Dateien:
  - `BrainMesh/Models/*`
  - `BrainMesh/Bootstrap/GraphBootstrap+Backfill.swift`
- Idee:
  - jede neue Suchspalte nur mit klarer Policy:
    - write-time update
    - explicit backfill
    - test coverage
- Nutzen:
  - bessere Vorhersagbarkeit bei Model-Änderungen

## Vereinheitlichungen
### 1) Loader-Pattern standardisieren
- Beobachtung:
  - Mehrere Loader nutzen bereits ähnliche Muster:
    - configure with container
    - new `ModelContext`
    - value-only snapshots
    - local cache / revision cache
- Vorschlag:
  - kleines gemeinsames Pattern-Dokument oder Basiskonvention statt Framework/Inheritance
- Nutzen:
  - weniger Spezialfälle
  - neue Feature-Loader werden konsistenter

### 2) Startup / Repair / Maintenance stärker trennen
- Aktueller Zustand:
  - `AppRootView+Startup.swift` mischt Initialisierung, Repair, Hydration, Locking, Onboarding-Trigger.
- Vorschlag:
  - separate Startup-Planung:
    - boot-critical
    - repair-after-boot
    - maintenance-when-active
- Nutzen:
  - weniger MainActor-Druck
  - bessere Messbarkeit

### 3) Graph-scoped Data Access als erstes Architekturprinzip dokumentieren
- Beobachtung:
  - `graphID` ist durchgängig zentral, aber die Regeln sind über viele Dateien verstreut.
- Vorschlag:
  - kurze technische Policy dokumentieren:
    - wann `graphID == nil` noch unterstützt wird
    - wann Legacy-Migration greift
    - wann UI current+legacy merged anzeigt
- Nutzen:
  - weniger spätere Scope-Bugs

## Risiken & Edge Cases
### Datenverlust / Konsistenz
- `GraphTransfer` importiert ohne Medien; Nutzer könnte Vollständigkeit annehmen.
- Startup-Migrationen und GraphID-Reparaturen ändern Bestandsdaten beim App-Start.
- Link-Labels sind denormalisiert (`sourceLabel`, `targetLabel`); Rename-Pfade müssen sauber mitziehen.

### Migrationen
- Kein expliziter `VersionedSchema` gefunden.
- Backfills kompensieren aktuell einen Teil der Evolution, sind aber kein Ersatz für klare Schema-Versionierung.

### Offline / Multi-Device
- Release-Fallback auf lokal-only kann funktional korrekt sein, aber zu unterschiedlichen Erwartungsbildern führen.
- **UNKNOWN**:
  - Wie Konflikte bei parallelen Änderungen auf mehreren Geräten konkret behandelt werden.

### Media / Storage Pressure
- `MetaAttachment.fileData` nutzt `externalStorage`, aber Count-/Byte-Aggregation materialisiert trotzdem Zeilen.
- Gallery- und Video-Import können CPU- und Disk-lastig werden.
- Lokale Cache-Größe wächst; manuelle Wartung ist vorhanden, aber keine sichtbare automatische Policy für Shrinking gefunden.

### UX / Lifecycle
- Locking rund um Systemmodals ist bewusst kompliziert, um Picker/FaceID nicht abzuschießen.
- Änderungen in diesem Bereich bergen hohe UX-Regressionsgefahr.

## Observability / Debuggability
### Bereits vorhanden
- `BrainMesh/Observability/BMObservability.swift`
  - Logger-Kategorien:
    - `load`
    - `expand`
    - `physics`
  - Timing-Helper: `BMDuration`
- `GraphCanvasView+Physics.swift`
  - periodisches Physics-Logging mit avg/max ms
- `SyncMaintenanceView.swift`
  - sichtbare Cache-Größen für Bilder und Attachments
- `SyncRuntime.swift`
  - sichtbarer iCloud-Status und Storage-Mode

### Fehlende / schwache Stellen
- Kein zentrales Dashboard für Startup-Repairs / Last-run / Dauer.
- Keine klar sichtbare Telemetrie für Importdauer, Hydrator-Läufe, Attachment-Aggregation, GraphTransfer-Kosten.
- Kein klarer Entwicklerpfad sichtbar, um festzustellen, **warum** ein bestimmter Graph / Attachment noch legacy-scoped ist.

### Sinnvolle Ergänzungen
- letzte Laufzeit / Dauer für:
  - bootstrap repair
  - image hydration
  - attachment hydration
  - graph import/export
- Debug counters für:
  - current-scope vs legacy-scope attachment hits
  - GraphCanvas node/link truncation wegen `maxNodes` / `maxLinks`
  - Stats cache hits / misses pro Screen-Session

## Testlage / Auffälligkeiten
### Gute Abdeckung vorhanden für
- `BrainMeshTests/GraphBootstrapTests.swift`
- `BrainMeshTests/GraphStatsLoaderTests.swift`
- `BrainMeshTests/GraphStatsServiceCountsTests.swift`
- `BrainMeshTests/GraphTransferRoundtripTests.swift`
- `BrainMeshTests/EntitiesHomeLoaderSearchTests.swift`
- `BrainMeshTests/MediaAllLoaderTests.swift`
- `BrainMeshTests/NodeMediaPreviewLoaderTests.swift`
- `BrainMeshTests/NodeImagesManageLogicTests.swift`

### Lücken / sinnvolle Ergänzungen
- Test für dokumentierte Erwartung, dass `.bmgraph` **keine Attachments** enthält oder künftig enthält.
- Test für Startup-Repair-Skalierung / idempotentes Verhalten über große Legacy-Mengen.
- Test für Graph-scoped Attachment-Merge-Logik zentral, statt nur featureweise.

## Open Questions
- **UNKNOWN**: Soll `UIBackgroundModes = remote-notification` aktiv bleiben oder ist das Altbestand?
- **UNKNOWN**: Gibt es außerhalb des Repos eine CI-/Build-Konfiguration über `.xcconfig` oder Secrets-Management?
- **UNKNOWN**: Ist `BrainMesh/GraphSession.swift` bewusst vorbereitet oder ungenutzt? Im gescannten Projekt wurden keine In-Repo-Referenzen gefunden.
- **UNKNOWN**: Wie groß dürfen produktive Graphen realistisch werden? Ohne Zielgröße sind viele Performance-Entscheidungen nur eingeschränkt priorisierbar.
- **UNKNOWN**: Ist das Ausschließen von Attachments aus `GraphTransfer` Produktentscheidung oder Zwischenstand?
- **UNKNOWN**: Gibt es Sync-/Konflikt-Policies jenseits der SwiftData-/CloudKit-Defaults?

## First 3 Refactors I would do
### P0.1 — Attachment-Aggregation aus Vollfetchs herausziehen
- Ziel
  - Stats-Counts für Attachments und Bytes ohne vollständiges Laden aller `MetaAttachment`-Rows berechnen.
- Betroffene Dateien
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - Mutation-Pfade in `BrainMesh/Attachments/*` und Detail-Media-Management
- Risiko
  - Mittel: Invalidation muss bei Insert/Delete/Migration/Kind-Wechsel sauber sein.
- Erwarteter Nutzen
  - Deutlich geringere Kosten im Stats-Pfad.
  - Besser skalierende Storage-Auswertung.
  - Weniger unnötige Objektmaterialisierung.

### P0.2 — GraphCanvas-Physics auf räumliche Partitionierung umstellen
- Ziel
  - O(n²)-Pair-Loop in `GraphCanvasView+Physics.swift` entschärfen.
- Betroffene Dateien
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - ggf. kleine Hilfsdatei `GraphCanvasView+SpatialIndex.swift`
- Risiko
  - Mittel bis hoch: sichtbares Layout-/Bewegungsverhalten kann sich ändern.
- Erwarteter Nutzen
  - Bessere Skalierung bei dichten Graphen.
  - Weniger CPU / Akku-Last.
  - Mehr Luft für höhere Node-Zahlen ohne zähe UI.

### P0.3 — Explizite Schema-Versionierung und Repair-Entkopplung einführen
- Ziel
  - Ad-hoc-Reparaturen und Backfills aus der Startup-Orchestrierung herauslösen und auf eine klarere Migrations-/Maintenance-Schiene stellen.
- Betroffene Dateien
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/AppRoot/AppRootView+Startup.swift`
  - `BrainMesh/Bootstrap/*`
  - `BrainMesh/Models/*`
- Risiko
  - Mittel: Persistenzänderungen verlangen sehr saubere Tests und Migrationsstrategie.
- Erwarteter Nutzen
  - Besserer langfristiger Upgrade-Pfad.
  - Kürzerer, planbarerer App-Start.
  - Weniger implizite Reparaturarbeit im MainActor-Startup.
