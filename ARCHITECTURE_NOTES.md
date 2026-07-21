# ARCHITECTURE_NOTES.md

## Scan Scope

- Quelle: hochgeladenes ZIP, entpackt und statisch gescannt.
- Produktionscode unter `BrainMesh/`: 508 Swift-Dateien, 74.134 Zeilen.
- Tests: `BrainMeshTests/`, `BrainMeshUITests/` vorhanden; nicht als Produktions-Hotspots gewertet.
- Fokus gemäß Priorität:
  1. Sync/Storage/Model
  2. Entry Points + Navigation
  3. Große Views/Services
  4. Konventionen + typische Workflows

## Big Files List — Top 15 Produktionsdateien nach Zeilen

| Rang | Datei | Zeilen | Grober Zweck | Warum riskant |
|---:|---|---:|---|---|
| 1 | `BrainMesh/Settings/BrainMeshGuideView.swift` | 671 | In-App-Guide mit vielen Sections und Hilfskomponenten | Wartbarkeitsrisiko: Copy, Layout und Komponenten in einer Datei; nicht kritischer Hot Path, aber hohe Änderungsfläche |
| 2 | `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferComponents.swift` | 569 | Karten, Import/Export-Preview, Activity-Bridge, FileDocument | Transfer-Datenintegrität und UI-States gekoppelt; viele unabhängige Komponenten in einer Datei |
| 3 | `BrainMesh/GraphCanvas/GraphCanvasTypes.swift` | 508 | WorkMode, Lens, Render-Pläne, Derived State, Node/Edge-Typen | Zentrale Typen und Planer; Änderungen können Rendering, Physics, Inspector und Loader gleichzeitig beeinflussen |
| 4 | `BrainMesh/Search/BrainMeshSearchService.swift` | 275 | globaler graph-scoped Search Actor | Orchestriert Readiness, begrenzte Index-Candidates, unverändertes Ranking und transparenten SwiftData-Fallback; graphweite Scans verbleiben nur im Fehler-/Fallback-Pfad |
| 5 | `BrainMesh/GraphCanvas/GraphCanvasScreen/Overlays/GraphCanvasScreen+InspectorOverlay.swift` | 458 | Graph-Inspector mit Presets, Fokus, Toggles, Limits | Viele Bindings auf Canvas-State; Risiko für exzessive View-Invalidation und schwer testbare UI-Logik |
| 6 | `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` | 423 | Stats-Root-View und Dashboard-Orchestrierung | View enthält Ladezustände, Sections und Trigger; Risiko für unklare Reload-Invalidation |
| 7 | `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift` | 404 | Stats DTOs, Service-Basistypen, Caches | Viele zentrale Statistiktypen in einer Datei; Änderungen an Counts/Media/Health strahlen breit aus |
| 8 | `BrainMesh/Stats/GraphHealth/GraphHealthIssueEngine.swift` | 404 | Graph-Health-Regelengine | Regel- und Schwellenlogik konzentriert; Risiko für schwer nachvollziehbare False Positives/Negatives |
| 9 | `BrainMesh/Stats/GraphStatsLoader.swift` | 361 | Actor-Loader mit Dashboard-/Counts-Cache | Caching und Revisionslogik komplex; `@unchecked Sendable` DTOs müssen strikt value-only bleiben |
| 10 | `BrainMesh/Pro/ProCenterView.swift` | 360 | Pro-Status, StoreKit UI, Feature Cards | StoreKit-Zustand, Paywall-UI und Text eng gekoppelt; nicht primärer Performance-Hotspot |
| 11 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` | 352 | Highlight-Tiles, Mini-Thumbnails, Notes/Markdown, Owner Card | Detail-Screen-Hot-Path; Medien/Markdown/UI-Komponenten in einer Datei |
| 12 | `BrainMesh/GraphPicker/GraphPickerListView.swift` | 345 | Graph-Auswahlliste mit Counts/Badges/Status | Graph-Lifecycle zentral; Delete/Active-Graph-States können Sync und Navigation beeinflussen |
| 13 | `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` | 341 | Alle Verbindungen eines Nodes, Link-Note-Editing, Rows | Scroll-/Listen-Hotspot bei vielen Links; Row-Rendering und Edit-Flow gekoppelt |
| 14 | `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` | 331 | UIKit-Bridge für Markdown/Accessory mit Scroll/Fades | UIKit/SwiftUI-Interop; Größen-/Scroll-Bugs schwer zu reproduzieren |
| 15 | `BrainMesh/Attachments/AttachmentImportPipeline.swift` | 326 | File/Video/Gallery Import, Compression, Cache-Write | Storage-Hotspot: Security-scoped URLs, Video-Kompression, 25-MB-Limits, synced `fileData` |

## Entry Points + Navigation

### App Entry

- `BrainMesh/BrainMeshApp.swift`
  - `@main struct BrainMeshApp: App`.
  - Baut `Schema` mit allen SwiftData-Modellen.
  - Erstellt `ModelContainer` mit CloudKit `.automatic`.
  - Debug: CloudKit-Containerfehler ist fatal.
  - Release: CloudKit-Fehler → lokaler `ModelContainer`.
  - Startet `Task.detached(priority: .utility)` für `SyncRuntime.refreshAccountStatus()`.
  - Startet `AppLoadersConfigurator.configureAllLoaders(with:)` nicht-blockierend; `AppRootView+Startup.swift` wartet vor serviceabhängigen Startup-Schritten auf `waitUntilReady()`.

### Root Lifecycle

- `BrainMesh/AppRoot/AppRootView.swift`
  - hostet `ContentView`.
  - `runStartupIfNeeded()` in `.task`.
  - Onboarding als Sheet.
  - Graph Unlock als `fullScreenCover`.
  - reagiert auf `scenePhase` und `activeGraphIDString`.
- `BrainMesh/AppRoot/AppRootView+Startup.swift`
  - `GraphBootstrap.ensureAtLeastOneGraph`.
  - `GraphBootstrap.migrateLegacyRecordsIfNeeded`.
  - `GraphBootstrap.backfillFoldedNotesIfNeeded`.
  - `ImageHydrator.shared.hydrateIncremental(runOncePerLaunch: true)` max. einmal pro 24h.
- `BrainMesh/AppRoot/AppRootView+ScenePhase.swift`
  - Debounced Auto-Lock im Hintergrund.
  - Grace-Window für System-Picker, um Photos/Face-ID-Flows nicht zu unterbrechen.

### Tabs

- `BrainMesh/ContentView.swift`
  - `TabView(selection: $tabRouter.selection)`.
  - Tabs: `EntitiesHomeView`, `GraphCanvasScreen`, `GraphStatsView`, `SettingsView` in `NavigationStack`.
  - Command-Center-Sheet und Command-Center-Destination-Sheet.
- `BrainMesh/RootTabRouter.swift`
  - `RootTab`: `.entities`, `.graph`, `.stats`, `.settings`.
  - `@MainActor` Methoden für Tab-Wechsel.

### Cross-Screen Navigation

- `BrainMesh/GraphJumpCoordinator.swift`
  - speichert pending graph jump mit `graphID`, `NodeKey`, `centerOnArrival`.
  - Konsum in `GraphCanvasScreen`.
- `BrainMesh/Search/CommandCenter/CommandCenterDestinationSheet.swift`
  - Destinationen: Add Entity, Graph Transfer, Guide, Node Detail.
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeRoutes.swift`
  - Detail-Route per `@Query` auf `MetaEntity.id`.

### Navigation Hotspots

- `GraphCanvasScreen+Body.swift`
  - Mehrere `.sheet` Hosts: GraphPicker, FocusPicker, Inspector, EntityDetail, AttributeDetail, DetailsValueEditor, DetailsFocusEditor.
  - Viele `.onChange` Trigger recomputen Derived State oder laden Graph neu.
- `EntityDetailView+Sheets.swift` und `AttributeDetailView+Sheets.swift`
  - Viele Sheet- und Dialog-Zustände an den Host-Views.
  - Hohe Kopplung zwischen Detail UI, Medienimport, Link-Flows, Notes und Details-Schema.

## Data Model / Storage Deep Dive

### Graph Scope als zentrale Invariante

- Fast alle user-nahen Modelle außer `MetaGraph` besitzen optionales `graphID`.
- `graphID == nil` wird in Kommentaren als sanfte Migration alter Daten beschrieben.
- `GraphBootstrap.migrateLegacyRecordsIfNeeded` ordnet Legacy-Daten einem Default-Graph zu.
- Risiko: Jede Query ohne `graphID`-Filter kann Daten aus anderen Graphen oder Legacy-Daten vermischen.
- Die neue Read-Schicht unter `BrainMesh/DataAccess/` erzwingt für ihre APIs einen nicht-optionalen `GraphScope` und stellt zentrale `GraphScopedFetches` bereit. Bestehende Feature-Loader werden in diesem Slice noch nicht vollständig migriert.

### Relationships vs. skalare Referenzen

- `MetaEntity` → `MetaAttribute` ist Cascade-Relationship.
- `MetaEntity` → `MetaDetailFieldDefinition` ist Cascade-Relationship.
- `MetaAttribute` → `MetaDetailFieldValue` ist Cascade-Relationship.
- `MetaLink` speichert Endpunkte skalar und wird nicht automatisch durch Relationship-Cascade gelöscht.
- `MetaAttachment` speichert Owner skalar und wird nicht automatisch durch Relationship-Cascade gelöscht.
- Konsequenz: Delete-Flows müssen Cleanup explizit aufrufen.

### Zentraler Node-Cleanup

- Alle produktiven Entity-/Attribute-Delete-Pfade in Detail, Home und Attributlisten delegieren an `GraphNodeDeletionService`.
- Der Service erfasst vor der ersten Mutation graph-scoped technische Referenzen für Links, Detailwerte, Detaildefinitionen, Attachments, Attribute und Entities.
- Einzel- und Mehrfachlöschungen verwenden genau einen Save und einen deterministisch geordneten Mutation-Batch pro Benutzeraktion.
- Lokale Attachment-/Header-Cachedateien werden erst nach erfolgreichem SwiftData-Commit entfernt; Save-Fehler publizieren nichts und lassen bestehende Dateien bestehen.
- Der graphweite `GraphDeletionService` bleibt als eigener Lifecycle-Pfad bestehen und gehört nicht zu dieser graph-lokalen Service-Grenze.

### Denormalisierte Labels

- `MetaLink` enthält `sourceLabel` und `targetLabel` für schnelles Rendering und Search.
- Rename-Pfad:
  - `NodeRenameService` führt Node-Änderung und alle tatsächlichen `sourceLabel`-/`targetLabel`-Relabels im selben Main-Actor-`ModelContext` aus.
  - Genau ein `GraphMutationCommitter`-Commit publiziert zuerst das Node-Update und danach die nach Link-ID sortierten Link-Updates.
  - Entity-Rename berücksichtigt Attribute, deren sichtbares `displayName` vom Owner-Namen abhängt.
- Risiko:
  - Neue Rename-Einstiegspunkte müssen weiterhin zentral über `NodeRenameService` laufen, sonst können denormalisierte Labels stale werden.
  - Entity-Rename lädt die graph-scoped Attribute für die Owner-Prüfung; bei sehr großen Graphen bleibt dies ein möglicher Optimierungspunkt.

### Details-System

- Schema: `MetaDetailFieldDefinition` pro Entity.
- Values: `MetaDetailFieldValue` pro Attribute und Field.
- Typisierung über mehrere optionale Value-Spalten.
- Choice-Optionen und Templates werden JSON-kodiert in String-Feldern gespeichert.
- Risiko:
  - Änderungen an `DetailFieldType` beeinflussen UI, Search, Stats, Backup/Transfer und Templates.
  - Keine sichtbare Versionierung der JSON-Struktur in `MetaDetailsTemplate.FieldDef`.

### Attachments und Medien

- `MetaAttachment.fileData` ist `.externalStorage`, aber trotzdem Teil der SwiftData/CloudKit-Persistenz.
- Import-Limit: 25 MB in `AttachmentsSection`, EntityDetail, AttributeDetail, NodeAttachmentsManage.
- `AttachmentImportPipeline` normalisiert Galerie-Bilder und komprimiert Videos, falls größer als Limit und Kompression aktiv ist.
- Lokale Cache-Dateien werden in Application Support gespeichert.
- `AttachmentMutationService` committed fachliche Create-/Update-/Delete-Operationen über den zentralen Committer. Neue vorbereitete Cache-Dateien werden bei Save-Fehler als Orphans entfernt; bestehende Dateien werden erst nach erfolgreichem Commit gelöscht oder ersetzt.
- `AttachmentCleanup` erstellt für Node-Delete graph-scoped, value-only Mutation- und Cache-Referenzen, mutiert aber nicht eigenständig die Save-Grenze.
- `AttachmentStore.ensurePreviewURL` rehydriert rekonstruierbare Preview-Dateien ohne `localPath`-Mutation, Save oder Domain-Event.
- Headerbilder bleiben Node-Mutationen (`entityUpdated`/`attributeUpdated`), Galerie-Bilder sind Attachment-Mutationen.
- Risiken:
  - Große Videos und Backups belasten CloudKit/Sync und Export/Import.
  - Materialisierung von Preview-URLs sollte nicht aus SwiftUI-`body` passieren.

### Header Images

- `imageData` ist CloudKit-synchronisiert und klein gehalten.
- `imagePath` ist lokaler Cache-Pfad.
- `ImageStore.loadUIImage(path:)` ist synchron und im Kommentar explizit nicht für SwiftUI-`body` empfohlen.
- `ImageHydrator` scannt Entities/Attributes mit `imageData != nil` und schreibt deterministische Dateien.
- Startup-Hydration läuft selten, aber scans können bei großen Stores spürbar sein.

### Migration

- Im Scan keine `SchemaMigrationPlan`, `VersionedSchema` oder `MigrationStage` gefunden.
- Bestehende Migration/Repair ist runtime-basiert:
  - Default Graph sicherstellen.
  - Legacy `graphID` reparieren.
  - `notesFolded` backfillen.
- Risiko:
  - Runtime-Migration im Startup läuft auf `modelContext` aus `AppRootView` und kann bei vielen Records UI-Startzeit belasten.
  - **UNKNOWN**: Strategie für zukünftige inkompatible SwiftData-Schemaänderungen.

## Hot Path Analyse

### Rendering / Scrolling — Graph Canvas

#### 30-FPS Physics Loop

- Datei: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`.
- Mechanik:
  - `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)`.
  - `stepSimulation()` läuft bei aktivem Screen und erlaubter Simulation.
  - Pairwise Repulsion/Collision: verschachtelte Schleife über `simNodes` mit `i < j`.
  - Edge Springs: Schleife über `physicsEdges`.
  - Am Ende werden `positions = pos` und `velocities = vel` gesetzt.
- Hotspot-Grund:
  - O(n²) pro Tick für Repulsion/Collision.
  - Jede Positions-Assignment invalidiert SwiftUI-Views, Canvas und abhängige Overlays.
  - Bei `maxNodes = 140` kann der Pair-Loop rund 9.730 Paare pro Tick erreichen, bevor Edge-Arbeit dazukommt.
- Bereits vorhandene Mitigation:
  - `simulationAllowed` gate-t nach Screen-Sichtbarkeit, ScenePhase und Sheets.
  - Idle Sleep nach ca. 90 ruhigen Ticks.
  - `physicsRelevant` begrenzt Simulation im Spotlight/Focus.
  - MiniMap wird auf 5 FPS gedrosselt.
- Refactor-Hebel:
  - Spatial Grid/Bucket für Repulsion/Collision.
  - Pure `GraphPhysicsEngine` außerhalb der View.
  - Positions-Diffing oder batched updates nur bei sichtbaren Änderungen.

#### Frame Cache pro Render

- Datei: `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift`.
- Mechanik:
  - `renderCanvas` baut pro Frame `FrameCache`.
  - Dictionaries: `screenPoints`, `labelOffsets`, `keyByIdentifier`.
  - Edges und Nodes werden in Canvas gezeichnet.
- Hotspot-Grund:
  - Pro Frame Dictionary-Allokationen und Loops über Nodes/Edges.
  - Positions ändern bei Physics mit 30 FPS.
- Bereits vorhandene Mitigation:
  - `GraphCanvasScreen` cached `drawEdges`, `lens`, `detailsFocusRenderPlan`.
  - Thumbnail-Load läuft asynchron.
- Refactor-Hebel:
  - `FrameCacheBuilder` mit wiederverwendbaren Buffern.
  - Label offsets einmal pro NodeKey cachen statt pro Frame neu ableiten.
  - Rendering-Daten in immutable Render Snapshot konsolidieren.

#### Derived State Fan-out

- Datei: `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`.
- Mechanik:
  - `.onChange` für `edges`, `nodes`, `labelCache`, `showAllLinksForSelection`, `lensEnabled`, `lensHideNonRelevant`, `lensDepth`, `detailsFocusState`, `detailsFocusPreparedState`.
  - Jede Änderung ruft `recomputeDerivedState()`.
- Hotspot-Grund:
  - Breite Trigger-Matrix kann bei Load, Fokuswechsel, Inspector-Aktionen und Details-Fokus mehrere Recomputes hintereinander auslösen.
- Bereits vorhandene Mitigation:
  - Derived State wurde aus `body` herausgezogen und gecacht.
- Refactor-Hebel:
  - Eine `GraphCanvasViewModel`/Reducer-Schicht, die Inputs zusammenführt und recomputes coalesced.

### Rendering / Scrolling — Entities Home

#### Debounced Home Loader

- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Body.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
- Mechanik:
  - `.task(id: taskToken)` mit 250-ms-Debounce.
  - Loader fetches Entities, Attribute-Matches und Link-Note-Matches.
- Hotspot-Grund:
  - `contains`-Predicates auf folded Strings sind bei großen Stores teuer.
  - Suchpfad kombiniert Entity-, Attribute- und Link-Treffer und resolved Link-Endpunkte.
  - Link-Note-Pfad kann viele Endpunkte sammeln und nachladen.
- Bereits vorhandene Mitigation:
  - Debounce.
  - Background `ModelContext`.
  - DTO-Zeilen statt `@Query` für Entity-Liste.
- Refactor-Hebel:
  - Search-Index pro Graph.
  - Tokenisierte Index-Tabelle oder lokaler Suchindex.
  - Einheitliche Suchlogik mit `BrainMeshSearchService`.

#### Counts Cache

- Datei: `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Counts.swift`.
- Mechanik:
  - Counts für Attributes und Links werden graphweit geladen und in Memory reduziert.
  - Cache-TTL: 8 Sekunden.
- Hotspot-Grund:
  - Vollständiger Fetch aller Attributes bzw. Links eines Graphen bei Cache-Miss.
  - Attribute Counts dereferenzieren `attribute.owner`.
- Bereits vorhandene Mitigation:
  - TTL vermeidet wiederholte Scans beim Tippen.
- Refactor-Hebel:
  - Event-/Revision-basierte Invalidation.
  - Count-Aggregate pro Entity pflegen.
  - SwiftData `fetchCount` je sichtbare Entity ist nur bei kleinen sichtbaren Listen sinnvoll; für große Listen besser Aggregat.

#### Cockpit Loader

- Datei: `BrainMesh/Mainscreen/EntitiesHome/Cockpit/EntitiesHomeCockpitLoader.swift`.
- Mechanik:
  - Lädt `entities`, `attributes`, `links`, `detailFields`, `attachments` für den Graph.
  - Baut `GraphHealthSummary` und Recent Nodes.
- Hotspot-Grund:
  - Vollständiger graphweiter Snapshot bei Cockpit-Triggern.
  - Bei großen Graphen parallel zur Home-Liste spürbar.
- Refactor-Hebel:
  - Cockpit-Snapshot cachen mit Revision.
  - HealthSummary inkrementell aktualisieren.
  - Recent Nodes getrennt und lightweight laden.

### Rendering / Scrolling — Detail Screens

- Dateien:
  - `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`
- Mechanik:
  - Link-Preview nutzt `fetchCount` und `fetchLimit`.
  - Media Preview läuft über eigene Loader unter `NodeDetailShared`/Attachments.
- Hotspot-Grund:
  - Detail-Views haben viele Sheet-States und `.onChange` Reloads nach Link-/Bulk-Link-Sheets.
  - MainActor `NodeLinksQueryBuilder.load` nutzt `modelContext`; durch `fetchLimit` entschärft, aber bei langsamen Stores trotzdem UI-relevant.
- Bereits vorhandene Mitigation:
  - Kommentare markieren bewusst kein full-load `@Query`.
  - Preview-Limit standardmäßig 12.
- Refactor-Hebel:
  - Link preview komplett in `NodeConnectionsLoader`/Actor ziehen.
  - Sheet-State in `NodeDetailSheetCoordinator` auslagern.

### Rendering / Scrolling — Stats

- Dateien:
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Media.swift`
- Mechanik:
  - Counts nutzen teilweise `fetchCount`, gut für Basiscounts.
  - Media-Snapshots fetch-en Attachments, Header-Image-Owners und größte Attachments.
  - Dashboard Cache basiert auf Revisions.
- Hotspot-Grund:
  - Media/Health/Structure können graphweite Objektmengen laden.
  - Cache-Invalidation ist komplex und muss mit Mutationspfaden synchron bleiben.
- Refactor-Hebel:
  - Stats-Snapshots in einzelne Loader splitten.
  - Mutations-Events für gezielte Invalidation.
  - Health Rules separat testbar machen.

### Global Search

- Dateien:
  - `BrainMesh/Search/BrainMeshSearchService.swift` als Actor-Orchestrator für Readiness, Primary-/Fallback-Quellen, Cancellation, Ranking und Snapshot-Erzeugung.
  - `BrainMesh/Search/Candidates/` mit `IndexedSearchCandidateProvider` als primärer value-only Quelle sowie den bestehenden SwiftData-Providern für Entity, Attribute, Link, Details und Attachments als transparentem Legacy-Fallback.
  - `BrainMesh/Search/Index/` mit dem separaten lokalen SQLite-Store, value-only `GraphSearchDocument`-Typen, dem deterministischen `GraphSearchDocumentBuilder`, dem `GraphSearchIndexer`-Actor und graph-scoped Statuswerten.
- Mechanik:
  - Der normale Indexpfad arbeitet ausschließlich mit value-only SQLite-Dokumenten. Nur der Legacy-Fallback erzeugt in `Task.detached` genau einen read-only Background-`ModelContext` pro Suche.
  - Ein gemeinsamer Request trägt optionalen Graph-Scope, bereits gefaltete Query, Context und Cancellation-Check.
  - Alle Quellen liefern ausschließlich `[BrainMeshSearchCandidate]`; SwiftData-Modelle überschreiten keine Actor-Grenzen. Der Index-Provider gruppiert Source-/Notes-Dokumente wieder zu genau einem bestehenden Result und rekonstruiert IDs, Titel, Untertitel, Icons, Owner-, Node- und Routing-Referenzen.
  - `BrainMeshSearchRanking` bleibt die finale fachliche Ranking- und Tie-Breaker-Schicht. Das öffentliche Limit wird nach dem gemeinsamen Ranking angewendet; der Index-Store begrenzt bereits vorher die technische Dokument-Candidate-Menge.
- Hotspot-Gründe:
  - Der normale Command-Center-Pfad liest eine begrenzte Candidate-Menge aus dem lokalen Index. `LinkSearchCandidateProvider`, `DetailSearchCandidateProvider` und `AttachmentSearchCandidateProvider` führen ihre bisherigen graphweiten SwiftData-Scans nur noch aus, wenn der Index nicht vollständig nutzbar ist. `fileData` wird weiterhin nie ausgewertet.
- Bereits vorhandene Mitigation:
  - Background Context und value-only Rückgaben.
  - Cancellation vor, zwischen und innerhalb der Provider-Phasen.
  - `safeLimit` auf maximal 100 Ergebnisse.
  - Quellspezifische Provider-Grenze für einen späteren Index.
  - Der lokale, versionierte `GraphSearchIndexStore` wird aus graph-scoped Read-Snapshots atomar aufgebaut und für lokale Mutation-Events inkrementell gepflegt. `BrainMeshSearchService.shared` liest ihn nach erfolgreichem `ensureReady` als primäre Candidate-Quelle.
- Verbleibender Refactor-Hebel:
  - Entities-Home nur bei vollständiger Scope-, UX- und Routing-Parität auf dieselbe Candidate-Schicht migrieren; keine zweite Indexintegration aufbauen.

## Sync / Storage Hot Path Analyse

### CloudKit Container Init

- Datei: `BrainMesh/BrainMeshApp.swift`.
- Hotspot-Grund:
  - Container-Initialisierung entscheidet zwischen CloudKit und local-only.
  - Release-Fallback ist nutzerrelevant: Sync wirkt deaktiviert, Daten bleiben lokal.
- Risiko:
  - **UNKNOWN**: Nutzerführung für späteren Wechsel local-only → CloudKit.
  - **UNKNOWN**: Ob lokale Daten in Fallback-Store bei später erfolgreicher CloudKit-Initialisierung automatisch migrieren.
- Hebel:
  - SyncMaintenance um Fallback-Reason, Store-Mode-Historie und Export-Hinweis erweitern.
  - Expliziter Recovery-Flow oder Backup-Aufforderung bei local-only.

### SwiftData Automatic CloudKit

- Dateien:
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/Settings/SyncRuntime.swift`
  - `BrainMesh/BrainMesh.entitlements`
- Hotspot-Grund:
  - Automatic Sync ist Black Box für Konflikte, Merge-Reihenfolge und Push-Verzögerung.
  - App nutzt keine sichtbare eigene CKOperation-Pipeline.
- Risiko:
  - Multi-Device Rename/Delete kann Denormalisierungen stale machen, wenn Reihenfolge ungünstig ist.
  - Große `fileData` Assets können Sync verzögern oder Fehler provozieren.
- Hebel:
  - Reconciliation-Pass für Link Labels und orphaned Attachments/Links.
  - Debug-Screen mit letzten lokalen Revisions/Counts und Cache-Status.

### Local Image Hydration

- Dateien:
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/ImageStore.swift`
  - `BrainMesh/AppRoot/AppRootView+Startup.swift`
- Hotspot-Grund:
  - Hydration scannt Entities/Attributes mit `imageData != nil`.
  - Läuft max. einmal pro 24h, aber im Foreground-/Startup-Pfad.
- Hebel:
  - Persistente Hydration-Revision pro Graph.
  - Nur Records mit `imagePath == nil` oder fehlender Datei laden.
  - UI für letzte Hydration und Fehler.

### Attachment Hydration

- Dateien:
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
  - `BrainMesh/Attachments/AttachmentStore.swift`
- Hotspot-Grund:
  - Fetch von `fileData` plus Disk-Write kann teuer sein.
  - Externe Daten können groß sein.
- Bereits vorhandene Mitigation:
  - Dedupe über `inFlight`.
  - `AsyncLimiter(maxConcurrent: 2)`.
  - Background `ModelContext`.
- Hebel:
  - Backpressure pro graph/owner.
  - Cancellation, wenn Zelle nicht mehr sichtbar ist.
  - Fehlerpersistenz für SyncMaintenance.

### GraphTransfer / Backup

- Dateien:
  - `BrainMesh/GraphTransfer/GraphTransferService/`
  - `BrainMesh/GraphTransfer/Backup/`
  - `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferComponents.swift`
- Hotspot-Grund:
  - Import/Export bewegt potenziell alle Graphdaten und Attachment-Assets.
  - ByteCount-Validierung existiert in Backup-Attachment-Pfaden.
  - Free-Limit `ProLimits.freeGraphLimit = 3` beeinflusst Import-Entscheidung.
- Save-/Event-Grenzen:
  - Interne Checkpoint-Saves bleiben eventfrei. Nach dem vollständig erfolgreichen Abschluss publiziert der zentrale Committer genau einen graph-scoped Import- oder Replace-Batch.
  - Jeder Fehler oder Abbruch führt über einen expliziten Cleanup-Save zur Entfernung des sichtbaren Teilgraphen; lokale Attachment-Cachedateien werden erst nach erfolgreichem Cleanup entfernt.
  - Replace behält die realen getrennten Grenzen bei: zuerst Graph-Delete-Commit, danach erfolgreicher Replacement-Import-Commit.
- Verbleibende Risiken:
  - Sehr große Imports bleiben durch Checkpoint-Saves nicht als eine einzige SwiftData-Transaktion atomar; die explizite Cleanup-Grenze stellt jedoch sicher, dass ein fehlgeschlagener Gesamtimport keinen sichtbaren Teilgraphen zurücklässt.
- Hebel:
  - Import-Transaktionslog oder Dry-Run-Manifest.
  - Konsistenzcheck nach Import: orphaned links, orphaned attachments, duplicate graph IDs.

## Concurrency Analyse

### Positive Patterns

- Viele schwere Loader sind Actors:
  - `EntitiesHomeLoader`
  - `EntitiesHomeCockpitLoader`
  - `GraphCanvasDataLoader`
  - `GraphStatsLoader`
  - `BrainMeshSearchService`
  - `AttachmentHydrator`
  - `ImageHydrator`
- Background-Kontexte mit `autosaveEnabled = false` für read-only Snapshot-Erzeugung.
- DTO-Kommentare betonen value-only Übergabe.
- `Task.checkCancellation()` in vielen langen Loops.
- `AsyncLimiter` begrenzt Hydration/Thumbnail-Arbeit.

### Risiken

#### Awaitable Loader Configuration

- Datei: `BrainMesh/Support/AppLoadersConfigurator.swift`.
- Mechanik:
  - `configureAllLoaders(with:)` bleibt aus `BrainMeshApp.init()` nicht-blockierend startbar.
  - Eine Main-Actor-isolierte Zustandsmaschine hält genau eine laufende Konfiguration und behandelt denselben Container idempotent.
  - `waitUntilReady()` gibt parallele Waiter gemeinsam frei und liefert für nicht gestartete, abgebrochene oder fehlgeschlagene Konfiguration klar testbare Zustände.
  - `AppRootView+Startup.swift` wartet vor Bootstrap, Lock- und Hydration-Schritten auf Readiness; appweit konfigurierte Loader warten bei einem frühen Zugriff ebenfalls auf die Barriere.
- Restrisiko:
  - Die nicht-werfenden Legacy-Loader-APIs behalten bei Readiness-Fehlern ihre bisherigen leeren beziehungsweise `nil`-Fallbacks. Der App-Root startet in diesem Zustand nicht weiter.

#### `@unchecked Sendable`

- Dateien:
  - `BrainMesh/Support/AnyModelContainer.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
- Risiko:
  - Compiler garantiert nicht, dass alle enthaltenen Typen wirklich sendbar sind.
  - Aktuell durch value-only DTO-Konvention entschärft.
- Hebel:
  - DTOs explizit `Sendable` machen.
  - SwiftData `@Model` nie in DTOs halten.
  - ModelActor-Pattern prüfen.

#### MainActor Fetches

- Datei: `BrainMesh/Mainscreen/NodeLinksQueryBuilder.swift`.
- Mechanik:
  - `@MainActor` statische `load` nutzt `modelContext` für `fetchCount` und fetch-limited preview.
- Risiko:
  - Für Detail-Screens wahrscheinlich okay, aber bei langsamem Store und vielen Links UI-relevant.
- Hebel:
  - LinkPreview actorized, analog zu `NodeConnectionsLoader`.

#### Unbounded/Long-Lived Tasks

- `GraphCanvasScreen+Body.swift` MiniMap-Task läuft in while-loop, solange `simulationAllowed` true ist.
  - Mitigation: `.task(id: simulationAllowed)` cancelt bei false; Sleep 200 ms.
- `AppRootView+ScenePhase.swift` background lock task ist bounded durch debounce und 6s Grace.
- `ImageHydrator` incremental run ist throttled durch `runOncePerLaunch` und 24h AppStorage.
- Kein eindeutig unbounded Sync-Polling gefunden.

## Refactor Map

### Konkrete Splits

#### `BrainMesh/GraphCanvas/GraphCanvasTypes.swift`

Ziel: zentrale Typen und Planer entkoppeln.

- Neu: `GraphCanvas/Core/GraphIdentifiers.swift`
  - `NodeKey`, `GraphNode`, `GraphEdge`, `GraphEdgeType`, `DirectedEdgeKey`.
- Neu: `GraphCanvas/Core/GraphCanvasModePolicy.swift`
  - `WorkMode`, `GraphCanvasModePolicy`.
- Neu: `GraphCanvas/Rendering/GraphDetailsRenderPlan.swift`
  - `GraphDetailsRenderPlan`, `GraphDetailsRenderPlanner`.
- Neu: `GraphCanvas/Rendering/GraphCanvasDerivedState.swift`
  - `GraphCanvasDerivedStateSnapshot`, `GraphCanvasDerivedStateBuilder`, cache mutation.
- Neu: `GraphCanvas/Lens/GraphCanvasLensConfiguration.swift`
  - `LensContext`, `GraphCanvasLensConfiguration`.
- Risiko: mittel, weil viele Imports/References betroffen.
- Nutzen: bessere Testbarkeit der Derived-State- und Render-Plan-Logik.

#### `BrainMesh/Search/BrainMeshSearchService.swift` — Provider-Split umgesetzt

- `BrainMeshSearchService` bleibt der öffentliche Actor-Orchestrator mit unveränderter `search(graphID:foldedQuery:limit:)`-API. Produktiv orchestriert er Readiness, den indexbasierten Primary Provider, den transparenten Legacy-Fallback, Cancellation und das gemeinsame Ranking.
- `Search/Candidates/BrainMeshSearchCandidateProvider.swift` definiert den gemeinsamen Request-Context mit operationslokalem `ModelContext`, optionalem `graphID`, bereits gefalteter Query und Cancellation-Prüfung.
- Quellspezifische Provider:
  - `EntitySearchCandidateProvider.swift`.
  - `AttributeSearchCandidateProvider.swift`.
  - `LinkSearchCandidateProvider.swift`.
  - `DetailSearchCandidateProvider.swift` für Definitionen und typisierte Werte.
  - `AttachmentSearchCandidateProvider.swift` ausschließlich für Metadaten.
- `BrainMeshSearchDetailValueFormatter.swift` kapselt value-only Datum-, Bool- und Detailwert-Formatierung.
- Provider geben ausschließlich `[BrainMeshSearchCandidate]` zurück; SwiftData-Modelle verbleiben im operationslokalen Context.
- Der Provider-Split selbst führte keinen Index ein; der inzwischen ergänzte `IndexedSearchCandidateProvider` verwendet ausschließlich den separat versionierten, rekonstruierbaren `GraphSearchIndexStore` und ändert das SwiftData-/CloudKit-Hauptschema weiterhin nicht.
- Providerbezogene Tests liegen in `BrainMeshTests/BrainMeshSearchCandidateProviderTests.swift`.
- Nutzen: Der produktive Index-Cutover konnte ohne Änderungen an Ranking, Result-DTOs, Routing oder Command Center erfolgen; dieselbe Grenze hält den SwiftData-Pfad als sicheren Fallback verfügbar.

#### `BrainMesh/Settings/BrainMeshGuideView.swift`

Ziel: reine Wartbarkeit.

- Neu: `Settings/Guide/BrainMeshGuideView.swift` als Host.
- Neu: `Settings/Guide/GuideSections.swift`.
- Neu: `Settings/Guide/GuideComponents.swift`.
- Neu: `Settings/Guide/GuideAnchors.swift`.
- Risiko: niedrig.
- Nutzen: Copy-/Layout-Änderungen ohne 671-Zeilen-Datei.

#### `BrainMesh/GraphTransfer/GraphTransferView/GraphTransferComponents.swift`

Ziel: Import/Export-Komponenten separieren.

- Neu: `GraphTransferView/Components/GraphTransferCards.swift`.
- Neu: `GraphTransferView/Components/GraphTransferExportComponents.swift`.
- Neu: `GraphTransferView/Components/GraphTransferImportComponents.swift`.
- Neu: `GraphTransferView/Components/GraphTransferActivityBridge.swift`.
- Neu: `GraphTransferView/Components/BMGraphFileDocument.swift`.
- Risiko: niedrig bis mittel wegen FileDocument und UIActivityItemSource.
- Nutzen: geringere Merge-Konflikte, klarere Transfer-Flows.

#### `BrainMesh/GraphCanvas/GraphCanvasScreen/Overlays/GraphCanvasScreen+InspectorOverlay.swift`

Ziel: Inspector-State und UI-Aktionen testbarer machen.

- Neu: `GraphCanvasScreen/Inspector/GraphCanvasInspectorSheet.swift`.
- Neu: `GraphCanvasScreen/Inspector/GraphCanvasInspectorViewModel.swift`.
- Neu: `GraphCanvasScreen/Inspector/GraphCanvasInspectorSections.swift`.
- Neu: `GraphCanvasScreen/Inspector/GraphCanvasPresetControls.swift`.
- Risiko: mittel, weil viele Bindings auf Canvas-State existieren.
- Nutzen: weniger Re-render-Kopplung und einfachere Preset-Tests.

#### `BrainMesh/Attachments/AttachmentImportPipeline.swift`

Ziel: Storage- und Medienpfade entkoppeln.

- Neu: `AttachmentImport/AttachmentImportMetadataResolver.swift`.
- Neu: `AttachmentImport/GalleryImageImportPreparer.swift`.
- Neu: `AttachmentImport/FileAttachmentImportPreparer.swift`.
- Neu: `AttachmentImport/VideoAttachmentImportPreparer.swift`.
- Neu: `AttachmentImport/AttachmentImportValidator.swift`.
- Risiko: mittel, weil Security-scoped URLs und Cache-Cleanup korrekt bleiben müssen.
- Nutzen: gezielte Tests für Bild, Video, Datei und Fehlerfälle.

### Cache-/Index-Ideen

#### SearchDocument Index

- Umgesetzt unter `BrainMesh/Search/Index/`:
  - `GraphSearchDocument` ist value-only, `Codable`, `Hashable` und `Sendable` und trägt deterministische Dokument-ID, Graph-/Source-/Owner-/Node-/Field-Referenzen, Ranking-, Navigation-, Presentation- und Evidence-Metadaten, Content-Hash und Index-Schemaversion. Schema v3 persistiert die für Search-Result-Parität benötigten Präsentationswerte wie benutzerdefinierte SF-Symbol-Namen.
  - Dokumentarten decken Entity, Attribute, Link, deren Notes, Detailfeld-Definition, einzelnen Detailwert und Attachment-Metadaten ab. Ein Detailwert bleibt als eigenes Fact-Dokument exakt über Source-ID und Field-ID referenzierbar.
  - Attachment-Dokumente erzwingen Metadaten-only-Suchtext aus Titel, Original-Dateiname, Dateiendung, Content-Type-Identifier, Byte-Anzahl und Content-Kind. `fileData`, lokaler Pfad, extrahierter Dateiinhalt und OCR-Text sind nicht darstellbar beziehungsweise werden bei der Dokumentvalidierung abgewiesen.
  - `GraphSearchDocumentBuilder` erzeugt aus den value-only Read-DTOs stabile Dokument-IDs und persistierbare SHA-256-Content-Hashes ausschließlich aus indexrelevanten Werten.
  - `GraphSearchIndexStore` ist ein eigener Actor mit separater SQLite-Datei in Application Support. Batch-Upsert, Source-Delete, Graph-Replace und Graph-Delete sind transaktional; explizite Einzel-/Mehrgraph-Suche, Test-Reads, Counts, Manifest, Clear und physischer Rebuild sind vorhanden. FTS-/n-Gram-Abfragen begrenzen Kandidaten vor der Dokumentdekodierung und laden die Treffer in einem gebündelten SQLite-Read statt per N+1-Abfrage.
  - `GraphSearchIndexer` ist ein Actor für coalesced `ensureIndexed`-Aufrufe, atomare graph-scoped Full Rebuilds in begrenzten Source-Batches und präzise Source-Replacements nach lokalen Mutation-Events. Import, Replace, Repair und andere grobe Events führen zu einem Full Rebuild; Graph-Delete entfernt den Index vollständig.
  - `GraphSearchSourceManifest` speichert pro Graph stabile Source-Hashes, Source-Art-Zähler und Dokument-Fingerprints. Dokumentänderungen und Manifest werden in derselben SQLite-Transaktion veröffentlicht; semantisch abweichende Dokument-Fingerprints werden beim Lesen erkannt.
  - `GraphSearchIndexReconciler` coalesced parallele `ensureReady`-Aufrufe pro Graph, hält verschiedene Graphen unabhängig, unterstützt waiter-spezifische Cancellation und kann einen zuvor gültigen Index während einer Reparatur beziehungsweise nach einem fehlgeschlagenen Rebuild weiterhin als technisch nutzbar ausweisen.
  - Rename-Folgen aktualisieren denormalisierte Attribute-, Detail- und Link-Labels. Detail-Schema-Events ersetzen Definitionen und synchronisieren alle betroffenen Detailwert-Dokumente einschließlich Löschungen.
  - Der UI-unabhängige, value-only Indexstatus bildet nicht initialisiert, Aufbau mit Fortschritt, bereit, veraltet und fehlgeschlagen ab. Fehler und Cancellation lassen einen vorherigen vollständigen Index bestehen.
  - `AppLoadersConfigurator` startet nach der Service-Konfiguration genau einen idempotenten Mutation-Event-Consumer. Indexfehler blockieren weder App-Start noch Hauptdaten.
  - Das Schema bevorzugt FTS5 mit Trigram-Tokenizer, fällt auf `unicode61` und schließlich auf einen eigenen indexierten 1-/2-/3-Gram-Store zurück. Alle Pfade verwenden `BMSearch.fold`, vorbereitete Statements und gebundene Werte.
  - Inkompatible Versionen, fehlende Schemaobjekte und beschädigte beziehungsweise logisch ungültige Indexdaten führen zu einem sicheren Index-Rebuild. Der Haupt-SwiftData-Store wird nicht geöffnet oder verändert.
  - Der Index ist vom Backup ausgeschlossen und weder Teil des CloudKit-Hauptschemas noch von GraphTransfer.
- Produktiver Search-Pfad:
  - `IndexedSearchCandidateProvider` mappt ausschließlich value-only Indexdokumente auf die bestehenden Search-Candidates und gruppiert Source-/Notes-Dokumente ohne doppelte Results. `BrainMeshSearchRanking` bleibt für Match-Reason, Score, Sortierung und Limit maßgeblich.
  - Konkrete Graphsuchen verwenden ausschließlich diesen Graphen. Globale Suchen ermitteln alle relevanten Graphen und verwenden den Index nur, wenn jeder Graph als nutzbar bestätigt ist; andernfalls läuft die gesamte Anfrage ohne Hybrid-Mischung über die Legacy-Provider.
  - Nicht initialisierte, beschädigte oder fehlgeschlagene Indexzustände sowie Queryfehler bleiben für das Command Center transparent. Queryfehler invalidieren die betroffenen Graphen technisch für den nächsten Reconciliation-Pass.
- Nutzen:
  - Der rekonstruierbare Index bleibt bei lokalen Mutationen und später erkannten externen Änderungen graph-scoped konsistent und reduziert im Normalpfad graphweite SwiftData-Scans. Damit ist Stufe 0 abgeschlossen.

#### Graph Counts Cache

- Ziel:
  - Attribute counts pro Entity.
  - Link counts pro Entity/Attribute.
  - Attachment counts/bytes pro Owner.
- Key-Struktur:
  - `GraphCountsCacheKey(graphID, revisionKind)`.
  - `NodeCountsKey(graphID, nodeKindRaw, nodeID)`.
- Invalidation:
  - Add/Delete Attribute.
  - Add/Delete Link.
  - Add/Delete Attachment.
  - Import/Restore.
- Nutzen:
  - Entlastet `EntitiesHomeLoader+Counts`, Stats und Cockpit.

#### GraphCanvas Spatial Index

- Ziel:
  - Repulsion/Collision nur für nahe Nodes berechnen.
- Key-Struktur:
  - Cell coordinate `(Int(x / cellSize), Int(y / cellSize))`.
  - Map Cell → `[NodeKey]`.
- Invalidation:
  - Pro Physics Tick aus aktuellen Positionen neu bauen oder inkrementell aktualisieren.
- Nutzen:
  - O(n²) reduziert sich praktisch auf O(n * lokale Nachbarn).

#### Hydration State

- Ziel:
  - Header Image und Attachment Hydration gezielt debuggen.
- Persistente Felder oder lokaler Status:
  - `lastHydratedAt`
  - `lastHydrationError`
  - `cacheFileExists`
- Nutzen:
  - SyncMaintenance wird diagnostisch brauchbarer.

### Vereinheitlichungen

#### Repository/Store Layer

- Umgesetzt unter `BrainMesh/DataAccess/`:
  - `GraphScope` als nicht-optionaler, `Hashable` und `Sendable` Graph-Schlüssel.
  - `GraphScopedFetches` für Graph, Entity, Attribute, Link, Attachment, Detaildefinition und Detailwert mit graph- und ID-scoped Predicates.
  - `GraphReadRepository` für Graph-Metadaten, alle Source-DTOs und einen vollständigen indexierbaren Graph-Snapshot.
  - `NodeRepository` für Entity-/Attribute-Lookups, Node-Summaries sowie eingehende und ausgehende direkte Nachbarschaften.
  - DTOs sind value-only und `Sendable`; Attachment-DTOs enthalten weder `fileData` noch lokalen Dateipfad.
  - `GraphMutationCommitter` bildet die einzige Save-then-Publish-Grenze für lokale und graphweite Mutationen. Main-Actor-Kontexte und caller-isolierte GraphTransfer-Kontexte verwenden dieselbe Implementierung.
  - `NodeRenameService`, `NodeNotesPersistence`, `GraphNodeDeletionService`, `BulkLinkExecutor` und `AttachmentMutationService` bauen auf derselben Commit-Grenze auf; es gibt keinen parallelen zweiten Save-then-Publish-Mechanismus.
- Weiterhin offen:
  - Bestehende Feature-Loader bauen teilweise eigene `FetchDescriptor`-Predicates und können schrittweise auf die Read-Schicht migriert werden.
  - Persistente Event-History und GraphCanvas-Reload-Scheduling. Der produktive Search-Cutover auf den lokalen Index ist abgeschlossen.

#### Mutation Events

- Umgesetzt unter `BrainMesh/DataAccess/Mutations/`:
  - `GraphMutationEvent` und `GraphMutationBatch` sind graph-scoped, value-only, `Hashable` und `Sendable`; sie enthalten ausschließlich IDs, technische Referenzen, Mutation-Art und Zeitpunkte.
  - `GraphMutationEventBus` ist ein actor-sicherer Multicast-Bus mit unabhängigen `AsyncStream`-Subscriptions, deterministischen Sequenznummern und expliziter Buffering-Policy.
  - Die Publisher-API heißt bewusst `publishCommitted(_:)`. `GraphMutationCommitter` ist die einzige Save-then-Publish-Abstraktion: Er prüft Cancellation vor der irreversiblen Commit-Phase, führt `ModelContext.save()` aus und publiziert erst danach genau einen bereits vollständig aus technischen IDs gebauten Batch. Bei Save-Fehlern wird nichts publiziert; Publish-Diagnosen aus dem Receipt machen einen erfolgreichen Save nicht rückwirkend fehlerhaft. Eine Pre-Commit-Publish-API existiert nicht.
  - `GraphMutationBatchFactory` klassifiziert sämtliche integrierten Mutationen ausschließlich aus technischen IDs. Definiert sind unter anderem stabile Reihenfolgen für bidirektionale/Bulk-Links, Rename-Relabels, Detailfeld-/Node-Cleanup, Graph-Lifecycle, Repair sowie Import/Replace.
  - Der Default-Buffer ist unbounded, da noch keine persistente Event-History existiert. Bounded Policies melden Drops im technischen Publish-Receipt; Subscriber erkennen Lücken über monotone Delivery-Sequenzen und sichern den Suchindex über den graph-scoped Reconciliation-/Rebuild-Pfad ab.
  - Streams werden bei Cancellation entfernt; der Bus kann beendet und für isolierte Tests deterministisch zurückgesetzt werden.
- Produktiv integriert:
  - Entity- und Attribute-Erstellung.
  - Einzelne Link-Erstellung einschließlich eines deterministischen bidirektionalen Batches, Link-Notiz-Updates sowie graph-lokale Einzel-/Mehrfachlöschungen.
  - Detail-Schema-Anlegen, -Ändern, -Umsortieren und -Löschen sowie Detailwert-Anlegen, -Ändern und -Löschen. Feld-Cleanup publiziert deterministisch zuerst Detailwert-Löschungen und danach ein Schema-Event.
  - Wiederverwendbare Detail-Templates verändern kein aktives Entity-Schema, publizieren aber für ihre graphgebundene Persistenz ein technisches `detailTemplateCreated`-Event. Graph-Löschung und Legacy-Scoping berücksichtigen Templates ebenfalls.
  - Entity-/Attribute-Rename inklusive aller tatsächlich relabelten Links als eine Transaktion und ein deterministischer Batch.
  - Node-Notes als expliziter Abschluss-Commit ohne Save pro Tastendruck.
  - Zentrale Einzel-/Batch-Node-Löschung mit Link-, Detail-, Attachment- und lokalen Cache-Seiteneffekten nach der Save-Grenze.
  - Bulk-Link als ein final geplanter Save und Batch.
  - Headerbilder als Node-Update sowie Galerie/Attachments als Attachment-Create/Update/Delete; reine Cache-Rehydration bleibt eventfrei.
  - Graph-Erstellung, Rename und vollständige Löschung einschließlich post-commit Datei-/Lock-Seiteneffekten.
- Graphweite Integration:
  - Dedupe, Bootstrap-Reparaturen, folded-Notes-Backfill und Attachment-GraphID-Migration als geschlossene `integrityRepair`-Batches.
  - Struktur- und Vollbackup-Import mit eventfreien Checkpoint-Saves, genau einem finalen Import-/Replace-Batch und persistenter Teilgraph-Bereinigung bei Fehler oder Cancellation.
  - Seltene atomare Multi-Graph-Wartung publiziert nach einem Save einen deterministisch nach Graph-ID geordneten Batch pro Graph; ein Mixed-Graph-Batch bleibt unzulässig.
  - `GraphMutationCacheInvalidationCoordinator` startet zentral und container-idempotent genau eine unbounded Subscription. `EntitiesHomeLoader` invalidiert nur Graph-Counts des betroffenen Graphen; `GraphStatsLoader` invalidiert graphbezogene Counts und das Total-Aggregat. Dashboard-Snapshots werden breiter verworfen, weil sie das graphübergreifende Total einbetten.
  - `GraphSearchIndexer` startet nach vollständiger Service-Konfiguration zentral und idempotent genau eine weitere unbounded Subscription. Präzise Events ersetzen vollständige Sources; Import, Replace, Repair und Sequenzlücken erzwingen graph-scoped Full Rebuilds.
  - `EntitiesHomeCockpitLoader` und `BrainMeshSearchService` besitzen aktuell keinen langlebigen Cache und erhalten deshalb keinen No-op-Subscriber.
- Noch nicht integriert:
  - Persistente Event-History und GraphCanvas-Reload-Scheduling.
  - Entities-Home nur bei nachgewiesener UX-/Routing-Parität auf dieselbe Index-Candidate-Schicht migrieren.
- Nutzen:
  - Schafft eine getestete Post-Commit-Grenze für sämtliche aktiven lokalen Graphdaten-Mutationen und hält die vorhandenen Home-/Stats-Caches graph-scoped konsistent, ohne SwiftData-Modelle oder Nutzdaten über Actor-Grenzen zu transportieren.

#### Sheet Coordinators

- Vorschlag:
  - `NodeDetailSheetCoordinator` für Entity/Attribute Detail.
  - `GraphCanvasSheetCoordinator` für GraphCanvas.
- Nutzen:
  - Host Views werden kleiner.
  - Sheet-Routing wird testbar.
  - Weniger gegenseitige `@State`-Abhängigkeiten.

## Risiken & Edge Cases

### Datenverlust / Datenintegrität

- Entity- und Attribute-Löschungen laufen zentral über `GraphNodeDeletionService`; der Service erfasst Kind-Attribute und alle technischen Cleanup-Referenzen vor dem Cascade-Delete und committed genau einen Batch.
- Link-Labels sind denormalisiert; `NodeRenameService` aktualisiert sie gemeinsam mit dem Node-Rename in derselben Transaktion.
- Graph Delete behandelt Duplicate `MetaGraph` Records mit gleicher UUID defensiv; gut, aber zeigt, dass Duplikate real einkalkuliert sind.
- Fachliche lokale und graphweite Save-Pfade verwenden den zentralen Committer beziehungsweise den bewusst eventfreien Import-Cleanup. Verbleibende `try?`-Risiken betreffen rekonstruierbare Cache-Metadaten, unreferenzierte Legacy-Dateien oder nichtmutierende Loader-Fetches.
  - `GraphCanvasDataLoader+Neighborhood.swift` nutzt `try? context.fetch` an mehreren nichtmutierenden Read-Pfaden.
- Risiko bei CloudKit:
  - Reihenfolge von Delete/Rename/Attachment-Sync über Geräte kann Denormalisierungen und skalare Owner-Referenzen sichtbar machen.

### Migration

- Runtime-Migration ist vorhanden, aber kein formaler SwiftData MigrationPlan im Scan.
- `createdAt` defaulted teilweise auf `.distantPast`, um migrierte Records nicht neu wirken zu lassen.
- Optionales `graphID` vereinfacht Migration, erhöht aber Query-Risiko.
- JSON-Felder (`optionsJSON`, `fieldsJSON`) haben keine sichtbare Versionierung.

### Offline / Multi-Device

- Release-Fallback auf local-only schützt lokale Nutzung, kann aber Multi-Device-Erwartungen brechen.
- `SyncRuntime` zeigt Account-Status, aber nicht tatsächlichen Sync-Fortschritt.
- Large Attachments können Upload/Download verzögern.
- **UNKNOWN**: Konfliktauflösung bei gleichzeitigen Änderungen auf mehreren Geräten.

### Share / Collab

- GraphTransfer und Full Backup sind vorhanden.
- CloudKit Sharing/Collaboration APIs wurden im Scan nicht gesehen.
- **UNKNOWN**: Ob kollaborative Graphen geplant sind; aktuelles Model wirkt auf private DB und Export/Import ausgelegt.

### Performance Edge Cases

- GraphCanvas bei vielen Nodes/Links:
  - O(n²) Physics.
  - 30-FPS State Updates.
  - Per-frame Dictionaries.
- Search bei vielen DetailValues/Attachments/Links:
  - der normale Command-Center-Pfad verwendet begrenzte SQLite-Candidates; graphweite SwiftData-Scans und In-Memory-Candidate-Builds verbleiben als transparenter Fehler-/Readiness-Fallback.
- EntitiesHome Cockpit bei großen Graphen:
  - lädt mehrere Tabellen vollständig.
- Stats bei vielen Medien:
  - Media-Snapshot lädt Attachment- und Header-Image-Datenpfade.
- Startup nach Schema-/Data-Upgrade:
  - Legacy migration/backfill und Image hydration im Root-Lifecycle.

## Observability / Debuggability

### Vorhanden

- `BrainMesh/Observability/BMObservability.swift`
  - `BMLog.load`, `BMLog.expand`, `BMLog.physics`, `BMLog.search`, `BMLog.mutationEvents`.
  - `BMDuration` für Timing.
- `GraphSearchIndexStore`
  - loggt ausschließlich technische Versionen, Backend, Counts, Dauer und Fehlercodes für Open, Rebuild, Writes, Deletes und Queries.
- `GraphCanvasView+Physics.swift`
  - rollierendes Physics-Timing alle 60 Ticks.
- Loader verwenden teilweise `Logger(subsystem: "BrainMesh", category: ...)`.
- `SyncMaintenanceView` zeigt:
  - Storage Mode.
  - iCloud Account Status.
  - Cache-Größen.
  - Cache-Wartungsaktionen.

### Lücken

- Kein zentrales Debug-Dashboard für Loader-Latenzen.
- Viele `try?`-Pfade verlieren Fehlerkontext.
- SyncRuntime kennt Account-Status, aber nicht tatsächlichen letzten Sync-Erfolg.
- Keine sichtbaren Metriken für:
  - Entity/Attribute/Link counts pro Graph im UI-Debug.
  - Search candidate count pro Provider.
  - GraphCanvas load summary Historie.
  - Hydration failures.
  - Attachment cache misses.

### Vorschläge

- `BMLog.storage`, `BMLog.sync` und `BMLog.attachments` ergänzen.
- Für Hot Path Loader `BMDuration` und Result Counts loggen:
  - `EntitiesHomeLoader`: entity hits, attr hits, link hits, counts cache hit.
  - `BrainMeshSearchService`: candidate counts pro Provider.
  - `GraphCanvasDataLoader`: fetch durations, nodes, edges, dropped edges due cap.
  - `GraphStatsLoader`: cache hits, revision changes.
- Debug-only `DiagnosticsView` unter Settings:
  - Storage mode + fallback reason.
  - Cache sizes + hydration last run.
  - Loader cache status.
  - Orphaned link/attachment check.
- Repro-Checklisten in Debug UI:
  - Create large graph.
  - Rename entity with many attributes.
  - Delete attribute from Attribute Detail.
  - Import/export full backup with attachments.
  - Toggle CloudKit availability and observe fallback.

## Open Questions / UNKNOWN

- **UNKNOWN**: Release-CloudKit-Environment und ob `aps-environment = development` in der hochgeladenen Entitlements-Datei beim Release anders ersetzt wird.
- **UNKNOWN**: Ob local-only Fallback-Daten später in CloudKit migriert werden oder in getrennten Stores bleiben.
- **UNKNOWN**: Custom CloudKit Conflict Resolution wurde nicht gefunden.
- **KNOWN**: GraphTransfer verwendet bewusst eventfreie Checkpoint-Saves statt vollständiger Ein-Save-Atomarität; Fehler und Cancellation werden durch persistentes Teilgraph-Cleanup kompensiert, bevor ein Erfolgs-Batch entstehen kann.
- **UNKNOWN**: CI/CD, Fastlane, Build-Skripte oder Release-Pipeline sind im ZIP nicht ersichtlich.
- **UNKNOWN**: App Store Connect StoreKit-Produktkonfiguration außerhalb der IDs in `Info.plist`.
- **UNKNOWN**: Geplante Datenobergrenzen für Graphen, Nodes, Links, DetailValues und Attachments.
- **UNKNOWN**: Ob CloudKit Sharing/Collaboration geplant ist; aktueller Code zeigt private DB plus Export/Import.
- **UNKNOWN**: Exakte Testabdeckung je Hotspot; Tests wurden nicht vollständig inhaltlich bewertet.
- **UNKNOWN**: Ob alle `try?`-Fehler bewusst nicht-user-facing sind oder nur historisch gewachsen.

## First 3 Refactors I would do (P0)

### 1) Entity-/Attribute-Delete Cleanup vereinheitlichen — umgesetzt

- Umsetzung:
  - `BrainMesh/Mainscreen/Deletion/GraphNodeDeletionService.swift` ist der zentrale Main-Actor-Löschpfad für einzelne und mehrere Attribute sowie Entities mit Kind-Attributen.
  - Cleanup-Pläne für `MetaLink` und `MetaAttachment` sind throwing, graph-scoped und werden vor der ersten Mutation vorbereitet.
  - Der Service entfernt skalare Referenzen, löscht anschließend das Zielmodell und committed genau einmal; Attachment- und Header-Cachedateien werden erst nach erfolgreichem Commit entfernt.
  - Entity-Delete erfasst alle Kind-Attribut-IDs vor dem Cascade-Delete, damit auch deren Links und Attachments entfernt werden.
  - Detail-, Home- und Attributlisten-Pfade zeigen Fehler an und dismissen beziehungsweise entfernen UI-Einträge erst nach erfolgreichem Commit.
- Tests:
  - `BrainMeshTests/GraphNodeDeletionServiceTests.swift` und `GraphNodeDeletionMutationTests.swift` decken Cleanup, Graph-Isolation, Batch-Verhalten, stabile Event-Reihenfolge, Save-Fehler ohne Datei-Löschung, Result-Zähler und fehlende Ziele beziehungsweise Abhängigkeiten ab.
- Verbleibende Grenze:
  - Der graphweite `GraphDeletionService` behält seine eigene atomare Graph-Transaktion, verwendet aber dieselben throwing Attachment-Cleanup-Pläne.

### 2) Search/Counts Indexierung vorbereiten — lokaler Search Indexer umgesetzt

- Ziel:
  - Graphweite Scans in `BrainMeshSearchService` und `EntitiesHomeLoader+Fetch` reduzieren.
- Betroffene Dateien:
  - `BrainMesh/Search/BrainMeshSearchService.swift`
  - `BrainMesh/Search/Candidates/`
  - `BrainMesh/Search/Index/`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Counts.swift`
  - `BrainMesh/Mainscreen/LinkCleanup.swift`
- Umsetzung:
  - Der verhaltenskompatible Provider-Split und der produktive Cutover sind abgeschlossen; `BrainMeshSearchService` orchestriert Readiness, indexbasierte Candidates, transparenten Legacy-Fallback und die unveränderte deterministische Ranking-Pipeline.
  - Der lokale, vollständig rekonstruierbare `GraphSearchIndexStore` ist als separate SQLite-/FTS5-Schicht umgesetzt. `GraphSearchDocumentBuilder` und `GraphSearchIndexer` befüllen ihn atomar aus graph-scoped Read-Snapshots und halten ihn für lokale Mutation-Events inkrementell aktuell.
  - `GraphSearchIndexReconciler` vergleicht einen value-only Source-Manifest-Snapshot mit dem lokal gespeicherten Manifest, upsertet oder löscht kleine Abweichungen atomar und löst bei inkompatiblen, beschädigten oder breiten Inkonsistenzen einen Full Rebuild aus. Der Foreground-Trigger ist graph-scoped, nicht blockierend und zeitlich gedrosselt.
  - Der Indexer verändert weder das SwiftData-/CloudKit-Hauptschema noch GraphTransfer. Der Index ist an die produktive globale Suche angebunden; globale Mehrgraph-Suchen bleiben all-or-nothing und fallen bei unvollständiger Readiness vollständig auf die Legacy-Provider zurück.
- Nächste Schritte:
  - Entities-Home unverändert lassen, bis dieselbe Candidate-Schicht ohne Scope-, UX- oder Routing-Risiken direkt wiederverwendet werden kann.
- Risiko:
  - Mittel.
  - Lokale Mutationen, Import/Replace und Repair werden durch Event-Consumer und Full Rebuilds abgedeckt; Änderungen außerhalb des lokalen EventBus werden beim nächsten `ensureReady`- beziehungsweise Foreground-Pass über das Source-Manifest reconciled.
- Erwarteter Nutzen:
  - Schnellere Suche bei großen Graphen.
  - Weniger Akku-/CPU-Last beim Tippen.
  - Basis für bessere Ranking-Tests und Diagnostik.

### 3) GraphCanvas Physics aus View extrahieren und Spatial Grid einführen

- Ziel:
  - Render-Hot-Path entlasten und O(n²)-Physics reduzieren.
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasTypes.swift`
  - Tests unter `BrainMeshTests/GraphCanvas...`
- Änderung:
  - Pure `GraphPhysicsEngine` mit Input Snapshot und Output Positions/Velocities.
  - Spatial Grid/Bucket für Repulsion/Collision.
  - View hält nur Timer/Task und committed Engine-Ergebnis.
  - Optional: adaptive tick rate oder stop threshold je Node-Anzahl.
- Risiko:
  - Mittel bis hoch.
  - Layout-Verhalten ist sichtbar und subjektiv; Regressions können UX betreffen.
- Erwarteter Nutzen:
  - Glatterer Graph bei vielen Nodes.
  - Weniger SwiftUI-Invalidation und CPU-Last.
  - Physics wird isoliert benchmark- und testbar.
