# ARCHITECTURE_NOTES.md

## Scope dieser Notizen
Diese Notizen basieren auf dem tatsächlich gescannten Projektstand im ZIP, nicht auf Wunscharchitektur. Alles, was im Code nicht belastbar sichtbar war, ist als **UNKNOWN** markiert und unten gesammelt.

---

## Big Files List

Top 15 Swift-Dateien nach Zeilenanzahl im gescannten Stand.

1. **650 Zeilen** — `BrainMesh/Settings/BrainMeshGuideView.swift`
   - Zweck: umfangreiche In-App-Hilfe/Guide-UI.
   - Risiko: eher **Maintainer-/Merge-Risiko** als Runtime-Risiko; sehr viel statischer UI-/Textinhalt in einer Datei.

2. **410 Zeilen** — `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
   - Zweck: Bilder verwalten, auswählen, löschen, setzen.
   - Risiko: **mehrere Verantwortungen** in einem UI-Host; hoher Änderungsdruck bei Medienfunktionen.

3. **367 Zeilen** — `BrainMesh/Mainscreen/BulkLinkView.swift`
   - Zweck: Bulk-Link-Flow.
   - Risiko: kombinierter UI-/State-/Mutation-Flow; fehleranfällig bei Validierung und Listenänderungen.

4. **362 Zeilen** — `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
   - Zweck: Media-Gallery-UI in Detailansichten.
   - Risiko: Medien, Navigation, Preview und Zustandswechsel dicht beieinander.

5. **361 Zeilen** — `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift`
   - Zweck: Stats-Grundtypen, Revisionen, Prädikate, Caches.
   - Risiko: zentrale Rechen-/Abfragebasis; Änderungen wirken breit.

6. **341 Zeilen** — `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift`
   - Zweck: „Alle Verbindungen“-Ansicht.
   - Risiko: große Listen + Navigation + Richtungslogik; leichtes UI-/Performance-Risiko.

7. **335 Zeilen** — `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
   - Zweck: Graph-Import mit ID-Remap und Fortschritt.
   - Risiko: **Datenintegrität**; jeder Fehler trifft Import-Semantik direkt.

8. **331 Zeilen** — `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift`
   - Zweck: Markdown-Zubehör-/Editor-UI.
   - Risiko: komplexe Editorinteraktion, hoher UI-Zustand, potenziell schwer testbar.

9. **326 Zeilen** — `BrainMesh/Attachments/AttachmentImportPipeline.swift`
   - Zweck: Datei-/Video-/Galerie-Import.
   - Risiko: I/O, Security-Scoped URLs, Komprimierung, Größenlimits, Fehlerpfade in einer Stelle.

10. **322 Zeilen** — `BrainMesh/Pro/ProCenterView.swift`
    - Zweck: Pro-Center UI.
    - Risiko: eher Wartbarkeit/Review-Fläche als Kernlaufzeit.

11. **321 Zeilen** — `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
    - Zweck: Stats-Host, Ladeorchestrierung, Dashboard-UI.
    - Risiko: state-reicher Host; gute Split-Tendenz schon vorhanden, aber weiter sensibel.

12. **317 Zeilen** — `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
    - Zweck: Entitäten-Suche/Fetch/Link-Match-Auflösung.
    - Risiko: Hot Path bei Suche; Query-Kombinatorik wächst mit Datenmenge.

13. **314 Zeilen** — `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard/NodeDetailsValuesCard+Components.swift`
    - Zweck: Komponenten für Detailwerte-Karten.
    - Risiko: UI-Breite und Zustandsdichte; eher Wartbarkeits- als Architektur-Risiko.

14. **309 Zeilen** — `BrainMesh/Icons/IconPickerView.swift`
    - Zweck: Icon-Suche/-Auswahl.
    - Risiko: große UI-Datei, potenziell viele Filter-/Search-Zustände.

15. **308 Zeilen** — `BrainMesh/Onboarding/DetailsOnboardingSheetView.swift`
    - Zweck: Onboarding-Flow für Details.
    - Risiko: Flow- und Sheet-Komplexität, aber kein offensichtlicher zentraler Hot Path.

### Einordnung
- Die **größten Runtime-Risiken** liegen nicht zwingend in den längsten Dateien, sondern in Kombinationen aus:
  - Größe
  - Hot Path-Nähe
  - vielen Verantwortungen
  - Mutation/I/O/Concurrency in derselben Datei
- Kritischer als die Guide-/Pro-Dateien sind deshalb vor allem:
  - `GraphCanvas/...`
  - `EntitiesHomeLoader+Fetch.swift`
  - `NodeMediaPreviewLoader.swift`
  - `AttachmentImportPipeline.swift`
  - `GraphTransferService+Import.swift`

---

## Hot Path Analyse

### Rendering / Scrolling

#### 1) `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Trigger:
  - sichtbarer Graph-Screen
  - `simulationAllowed == true`
- Grund für Hotspot:
  - `Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true)`
  - paarweise Repulsion/Kollision über `simNodes` → **O(n²)**
  - häufige Mutation von `positions` und `velocities`
  - hohe Gefahr für **exzessive View invalidation**
- Positiv schon vorhanden:
  - Sleep/Idle-Mechanik
  - Spotlight-Subset (`physicsRelevant`)
  - Simulation-Stop bei Nicht-Sichtbarkeit

#### 2) `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`
- Trigger:
  - Graph-Wechsel
  - Auswahländerung
  - Hops-/Attribute-/Lens-Änderungen
  - Sheet-Präsentationen
- Grund für Hotspot:
  - viele `.task` und `.onChange`
  - state-reicher Orchestrator
  - MiniMap-Snapshot-Schleife aktualisiert regelmäßig Dictionary-Snapshots
  - Cross-Screen-Jump-Handling + Selection-Handling + Derived-State-Recompute in einem Host
- Risiko:
  - schwer vorhersagbare Lastspitzen
  - steigende Regression-Gefahr bei kleinen UI-Änderungen

#### 3) `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Rendering.swift`
- Trigger:
  - jeder Render-Frame des Graph Canvas
- Grund für Hotspot:
  - per Frame werden `screenPoints`, `labelOffsets` und Outgoing-Notes vorbereitet
  - viel Dictionary-Aufbau im Renderzyklus
- Positiv schon vorhanden:
  - keine SwiftData-Fetches im Renderpfad
  - Render-Caches werden schon vorgeladen (`GraphCanvasDataLoader+Caches.swift`)

#### 4) `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Neighborhood.swift`
- Trigger:
  - Focus Entity + Hop-Änderungen
- Grund für Hotspot:
  - BFS über Nachbarschaft
  - mehrere Fetches
  - zusätzliche Link-Fetches + In-Memory-Filterung
  - potenziell große Mengen an IDs in `contains(...)`-Prädikaten
- Konkrete Hotspot-Gründe:
  - **heavy sort / repeated fetches / in-memory filtering**
- Positiv:
  - läuft off-main
  - `maxNodes` / `maxLinks` begrenzen die Last

#### 5) `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
- Trigger:
  - Sucheingaben
  - Graph-Wechsel
  - Öffnen des Entities-Tabs
- Grund für Hotspot:
  - Suche kombiniert Entity-Namen, Entity-Notizen, Attribut-Label, Attribut-Notizen, Link-Notizen
  - Endpoint-Auflösung für Link-Treffer erzeugt Zusatzarbeit
  - graphweite Count-Berechnungen werden separat gehalten
- Konkrete Hotspot-Gründe:
  - **multi-source search**, **additional endpoint resolution**, **heavy sort**
- Positiv:
  - Loader läuft off-main
  - Count-Cache mit TTL vorhanden

#### 6) `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`
- Trigger:
  - Öffnen von Entity-/Attribute-Detailansichten
- Grund für Hotspot:
  - ist derzeit `@MainActor`
  - macht `fetchCount(...)` plus Preview-Fetches
  - stößt zusätzlich `AttachmentGraphIDMigration.migrateIfNeeded(...)` an
- Konkrete Hotspot-Gründe:
  - **Fetch auf MainActor**, **Migration im Anzeige-Flow**, **I/O-nahe Preview-Orchestrierung**
- Das ist einer der klarsten P0-Kandidaten.

#### 7) `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` + `BrainMesh/Stats/GraphStatsLoader.swift`
- Trigger:
  - Öffnen des Stats-Tabs
  - Pull-to-refresh
  - Expand „Pro Graph"
- Grund für Hotspot:
  - mehrere Revision-/Snapshot-Pässe
  - lazy per-graph loads zusätzlich
  - Snapshot-Teile werden in getrennten Tasks erzeugt
- Positiv:
  - Loader-Cache vorhanden
  - Dashboard und Per-Graph sind schon getrennt

---

### Sync / Storage

#### 1) `BrainMesh/BrainMeshApp.swift`
- Relevanz:
  - zentraler Storage-Bootstrap
- Beobachtung:
  - CloudKit-Init entscheidet hart über Betriebsmodus
  - Release-Fallback lokal-only ist produktrelevant
- Risiko:
  - Container-/Entitlement-Fehler führen zu komplett anderem Betriebsmodus

#### 2) `BrainMesh/AppRootView.swift`
- Relevanz:
  - Startup führt graphische Datenreparatur, Lock-Prüfung und Bildhydration aus
- Konkrete Risiken:
  - **Startup latency** bei großen Stores
  - mehrere Verantwortungen in einem App-Lifecycle-Host
  - Foreground/Background-Verhalten ist sensibel wegen System-Pickern und Locking

#### 3) `BrainMesh/GraphBootstrap.swift`
- Relevanz:
  - Laufzeitmigrationen
- Konkrete Risiken:
  - läuft auf MainActor
  - scannt bei Bedarf Legacy-Daten und fehlende Search-Indizes
  - potenziell wachsender Startkostenblock

#### 4) `BrainMesh/ImageHydrator.swift`
- Relevanz:
  - baut lokale Bilddateien aus `imageData`
- Konkrete Risiken:
  - kompletter Scan aller Records mit `imageData != nil`
  - Dateisystem-I/O + SwiftData-Änderungen
- Positiv:
  - serialized via `AsyncLimiter(maxConcurrent: 1)`
  - run-once-per-launch Guard vorhanden

#### 5) `BrainMesh/Attachments/AttachmentHydrator.swift`
- Relevanz:
  - materialisiert lokale Preview-Dateien aus `fileData`
- Konkrete Risiken:
  - Blob-Fetch + Disk-Write
  - sichtbarkeitsnahe Nutzung bei UI-Zellen
- Positiv:
  - Dedupe per attachment ID
  - globales Throttling (`maxConcurrent: 2`)

#### 6) `BrainMesh/Attachments/AttachmentImportPipeline.swift`
- Relevanz:
  - Eintrittspunkt für Datei-/Video-/Bildimport
- Konkrete Risiken:
  - **I/O + Transcoding + Security-Scoped URLs + Größenlimits**
  - hohe Komplexität der Fehlerpfade
  - stark unterschiedliches Verhalten je Quelltyp

#### 7) `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
- Relevanz:
  - graphweite Datenaufnahme
- Konkrete Risiken:
  - ID-Remap, Batch-Saves, Progress, Cancellation
  - Fehler bedeuten inkonsistenten Import oder Datenverlust im importierten Graph
- Positiv:
  - Batch-Save und Yield/Cancellation-Strides vorhanden

#### 8) `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
- Relevanz:
  - zählt Daten über den gesamten Store/Graphen
- Konkrete Risiken:
  - Attachment-Aggregat nutzt `context.fetch(FetchDescriptor<MetaAttachment>...)` und summiert dann im Speicher
  - auf großen Stores unnötig teuer

---

### Concurrency

#### Positive Muster
- Viele Loader sind bewusst als `actor` gebaut:
  - `EntitiesHomeLoader`
  - `GraphCanvasDataLoader`
  - `GraphStatsLoader`
  - `AttachmentHydrator`
  - `ImageHydrator`
  - `GraphTransferService`
- UI-Hosts nutzen häufig:
  - `loadTask?.cancel()`
  - Token-Guards (`currentLoadToken`)
  - `Task.checkCancellation()`

#### Konkrete Risiken

##### 1) MainActor contention
- `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`
  - Preview-Load inklusive Migration auf MainActor
- `BrainMesh/GraphBootstrap.swift`
  - Datenreparaturen auf MainActor beim Startup
- `BrainMesh/AppRootView.swift`
  - Lifecycle-Orchestrierung + Locking + Hydration-Trigger in einer Stelle

##### 2) Detached Tasks mit eigenem `ModelContext`
- mehrfach genutzt, z. B.:
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
- Das ist grundsätzlich sauber, verlangt aber Disziplin:
  - keine `@Model`-Objekte über Actor-Grenzen tragen
  - Stale-Resultate abfangen

##### 3) Task lifetime / cancellation
- Gute Ansätze existieren, aber Muster sind nicht vollständig vereinheitlicht.
- Besonders GraphCanvas und Stats haben ähnliche Orchestrierungslogik in eigener Variante.
- Potenzieller Refactor-Hebel: gemeinsames Pattern für `LoadKey + Task + Token + forceReload`.

##### 4) System modal / lock race
- `BrainMesh/Support/SystemModalCoordinator.swift`
- `BrainMesh/AppRootView.swift`
- Positiv: Debounce + Grace Window gegen Face-ID-/Picker-Rennen sind explizit eingebaut.
- Risiko: Lifecycle-Code ist fragil und schwer manuell reproduzierbar.

##### 5) Legacy parallel state
- `BrainMesh/GraphSession.swift` beobachtet `UserDefaults.didChangeNotification` für `activeGraphID`.
- Gleichzeitig wird der aktive Graph breit direkt via `@AppStorage(BMAppStorageKeys.activeGraphID)` gelesen.
- Ob `GraphSession` noch notwendig ist, ist **UNKNOWN**.

---

## Refactor Map

### Konkrete Splits

#### A) `NodeMediaPreviewLoader` in echtes Loader-/DTO-Muster überführen
- Heute:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`
  - MainActor, FetchCount, Preview-Fetch, Migration in einer Funktion
- Ziel:
  - `NodeMediaPreviewLoader.swift` als Actor oder Service mit eigenem Background-Context
  - `NodeMediaPreviewQueries.swift` für Query-Bausteine
  - optional `NodeMediaPreviewRevision.swift` für kleine Invalidation-Signatur
- Nutzen:
  - Detailscreen öffnet weicher
  - weniger UI-Stalls

#### B) GraphCanvas-Host weiter schneiden
- Heute:
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`
- Ziel:
  - `GraphCanvasScreen+LoadPipeline.swift`
  - `GraphCanvasScreen+JumpHandling.swift`
  - `GraphCanvasScreen+MiniMap.swift`
  - `GraphCanvasScreen+Selection.swift`
- Nutzen:
  - weniger Änderungsrisiko pro PR
  - leichter testbare Verantwortungskerne

#### C) `AttachmentImportPipeline.swift` nach Medientyp splitten
- Heute:
  - File-, Gallery- und Video-Pfade in einer Datei
- Ziel:
  - `AttachmentImportPipeline+File.swift`
  - `AttachmentImportPipeline+GalleryImage.swift`
  - `AttachmentImportPipeline+Video.swift`
- Nutzen:
  - Fehlerpfade kleiner
  - Limits/Policy leichter prüfbar

#### D) `GraphStatsService.swift` weiter zerlegen
- Heute:
  - Grundtypen, Revisionsmodell, Prädikate und Caches in einer Datei
- Ziel:
  - `GraphStatsService+Predicates.swift`
  - `GraphStatsService+Revision.swift`
  - `GraphStatsService+Media.swift`
  - `GraphStatsService+Structure.swift`
  - `GraphStatsService+Trends.swift`
- Nutzen:
  - schnellere Orientierung
  - geringere Nebenwirkungen bei Stats-Änderungen

#### E) Medien-UI in Detailscreens weiter modulieren
- Kandidaten:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeImagesManageView.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+MediaGallery.swift`
- Ziel:
  - separater Import-Action-Block
  - separater Gallery-Grid-Block
  - separater Delete/SetAsMain-Flow
- Nutzen:
  - weniger UI-Monolith im Detailbereich

---

### Cache- / Index-Ideen

#### 1) Attachment-Aggregat-Cache pro Graph
- Problem:
  - `GraphStatsService+Counts.swift` lädt Attachments vollständig, um Bytes zu summieren
- Idee:
  - kleiner Cache keyed by `graphID` + Revision
  - Revision kann aus Count + newestAttachmentCreatedAt kommen
- Invalidierung:
  - bei Attachment-Anlage/Löschung/Import

#### 2) Link adjacency / degree cache für GraphCanvas + Stats
- Problem:
  - Degree-/Hub-/Neighborhood-Arbeit wird an mehreren Stellen neu aufgebaut
- Idee:
  - loaderinterner GraphIndex pro Snapshot / GraphRevision
  - enthält Nachbarschaft, Degree, Endpoint-Mappings
- Invalidierung:
  - wenn `MetaLink`/`MetaEntity`/`MetaAttribute` Revision sich ändert

#### 3) Media Preview cache pro Owner
- Problem:
  - Detailscreen lädt Counts/Preview immer wieder neu
- Idee:
  - `NodeMediaPreview` cache keyed by `(ownerKind, ownerID, graphID)`
  - optional mit kleiner Revision aus `attachmentCount + newestAttachmentCreatedAt + hasMainImage`

#### 4) Search revision cache für Entities Home
- Problem:
  - Suche skaliert mit mehreren Datenquellen
- Idee:
  - kleinen graphweiten `SearchRevision` ableiten
  - bei gleicher Revision Suchresultate für kurze Zeit cachen
- Vorsicht:
  - nur Suchresultate, nicht graphweite Counts, vermischen

#### 5) Startup maintenance timing cache / metric
- Problem:
  - Launch-Kosten sind derzeit nicht gut sichtbar
- Idee:
  - timings für `GraphBootstrap` und `ImageHydrator` loggen
  - keine Funktionsänderung, nur Messbarkeit

---

### Vereinheitlichungen

#### 1) Gemeinsames Loader-Orchestrierungs-Muster
Heute mehrfach ähnlich, aber nicht einheitlich:
- `GraphStatsView.swift`
- `GraphCanvasScreen+Body.swift`
- `EntitiesHomeView.swift`

Vorschlag:
- ein kleines internes Pattern oder Helper für:
  - `LoadKey`
  - `currentToken`
  - `activeTask`
  - `forceReload`
  - stale-result guard

#### 2) Zentrale Graph-Scope-Helfer
Heute verteilt über viele Dateien:
- `GraphStatsService.swift`
- `GraphCanvasDataLoader+Global.swift`
- `GraphCanvasDataLoader+Neighborhood.swift`
- `NodeConnectionsLoader.swift`
- `EntitiesHomeLoader+Fetch.swift`

Vorschlag:
- kleine Query-/Predicate-Helfer pro Modelltyp, damit Scope-Handling konsistenter bleibt.

#### 3) Migrations-/Backfill-Registry
Heute verteilt:
- `GraphBootstrap.swift`
- `AttachmentGraphIDMigration.swift`
- ad-hoc Migration beim Detailpreview

Vorschlag:
- explizite Sammlung von Runtime-Repairs, damit klar ist:
  - was beim Launch läuft
  - was lazy läuft
  - was nur bei Anzeige eines Screens läuft

#### 4) Modellierte Ownership-Strategie dokumentieren
- Links und Attachments nutzen scalar ownership.
- Das sollte als explizite Projektregel dokumentiert bleiben.
- Sonst kommt bei späteren Änderungen schnell jemand auf die Idee, hier „einfach Relationships dazuzubauen“ und zerlegt die Stabilitätsannahmen.

---

## Risiken & Edge Cases

### Datenverlust / Datenintegrität
- `GraphTransferService+Import.swift`
  - Import remappt IDs und ignoriert verwaiste Attribute/Werte defensiv.
  - Das ist sinnvoll, aber jede Änderung dort ist heikel.
- `GraphPickerSheet.swift` + Delete-Flow
  - Graph-Löschung ist fachlich zentral; Dedupe-/Delete-Logik sauber halten.
- Laufzeit-Migrationen in `GraphBootstrap.swift`
  - reparieren Daten beim App-Start; Fehler hier wirken sofort auf Bestandsdaten.

### Migration / Legacy
- `graphID` ist in mehreren Modellen optional als Soft-Migrationsstrategie.
- Solange Legacy-Datenpfade existieren, bleibt zusätzlicher Query-/Repair-Aufwand.
- `AttachmentGraphIDMigration.swift` zeigt, dass alte `graphID == nil`-Datensätze real einkalkuliert sind.

### Offline / Multi-Device
- Lokale Fallback-Strategie ist vorhanden.
- CloudKit-Konfliktlösung über Standardverhalten hinaus ist **UNKNOWN**.
- Auch die erwartete Konsistenz bei gleichzeitigen Edits auf zwei Geräten ist **UNKNOWN**.

### Security / Locking
- Locking ist auf Graph-Ebene gut sichtbar integriert.
- Hintergrund-/Foreground-Rennen mit System-Pickern sind schon speziell behandelt.
- Ob modellseitige Lock-Felder auf Entity/Attribute noch geplant, legacy oder tot sind, ist **UNKNOWN**.

### Performance bei großen Datenmengen
- größte Risiken:
  - Graph Physics
  - Entities-Search
  - Stats Attachment Aggregates
  - Media Preview Load auf MainActor
  - Launch-Reparaturen/Hydrationen
- Maximale Ziel-Datensätze / Benchmarks sind **UNKNOWN**.

### Share / Collaboration
- Im gescannten Code keine Hinweise auf CloudKit Sharing oder gemeinsame Datenbanken.
- Geplante Kollaboration ist **UNKNOWN**.

---

## Observability / Debuggability

### Bereits vorhanden
- `BrainMesh/Observability/BMObservability.swift`
  - `BMLog.load`
  - `BMLog.expand`
  - `BMLog.physics`
  - `BMDuration`
- `BrainMesh/Settings/SyncMaintenanceView.swift`
  - zeigt Cache-Größen und Maintenance-Aktionen
- `BrainMesh/Settings/SettingsView+SyncSection.swift`
  - zeigt Storage Mode und iCloud-Status
- `BrainMesh/Stats/GraphStatsLoader.swift`
  - Cache-Hit-Zähler für Tests

### Testbarkeit
- In-Memory-SwiftData-Testsetup:
  - `BrainMeshTests/TestSupport/BrainMeshTestContainer.swift`
  - `BrainMeshTests/TestSupport/BrainMeshFixtureBuilder.swift`
- Gute vorhandene Testabdeckung für:
  - EntitiesHome-Suche
  - Stats Loader/Counts
  - GraphTransfer Roundtrip/ViewModel
  - MediaAllLoader
  - PhotoGallerySelectionState

### Was noch fehlt
- strukturierte Startup-Timings für `GraphBootstrap` / `ImageHydrator`
- reproduzierbare Logs für Graph-Lock-Lifecycle-Rennen
- sichtbare Metrik für GraphCanvas-Snapshot-Ladezeiten
- Sichtbarkeit, wie oft `NodeMediaPreviewLoader` MainActor-Fetches ausführt

### Repro-Hinweise für problematische Bereiche
- GraphCanvas:
  - großen Graph wählen
  - Focus/Hops mehrfach ändern
  - Lens/ShowAttributes umschalten
  - Selection schnell wechseln
- Detail-Media:
  - Cache löschen über `SyncMaintenanceView`
  - dann Entity/Attribute mit vielen Anhängen öffnen
- Startup:
  - Gerät mit großem Store und leerem Image-Cache starten
- Graph Lock:
  - Hintergrundwechsel während Photos-/Hidden-Album-/Face-ID-Flow testen

---

## Open Questions

1. **UNKNOWN**: Wofür `UIBackgroundModes = remote-notification` in `BrainMesh/Info.plist` aktuell konkret genutzt wird. Im gescannten Swift-Code wurde keine App-/Scene-/Push-Handling-Implementierung gefunden.
2. **UNKNOWN**: Ob es eine bewusste Konfliktauflösung über das Standardverhalten von SwiftData/CloudKit hinaus gibt.
3. **UNKNOWN**: Ob `MetaEntity`- und `MetaAttribute`-Lock-Felder aktiv genutzt werden sollen oder nur Graph-Level-Schutz übrig geblieben ist.
4. **UNKNOWN**: Ob `BrainMesh/GraphSession.swift` noch produktiv relevant ist oder nur ein Legacy-/Kompatibilitätsartefakt neben `@AppStorage(BMAppStorageKeys.activeGraphID)`.
5. **UNKNOWN**: Ob für Release-Builds das committed `aps-environment = development` in `BrainMesh/BrainMesh.entitlements` bewusst ist oder buildseitig überschrieben wird.
6. **UNKNOWN**: Ob eine formale Migrationsstrategie außerhalb der sichtbaren Laufzeit-Reparaturen existiert.
7. **UNKNOWN**: Welche Datengrößen/Performance-Budgets das Produkt real targetet.
8. **UNKNOWN**: Ob kollaborative/shared Graphen geplant sind.
9. **UNKNOWN**: Wie Release-/CI-Secrets und Signing außerhalb des Xcode-Projekts organisiert sind.
10. **UNKNOWN**: Ob `BrainMesh/Models/Models.swift` und `BrainMesh/Onboarding/Untitled.swift` bewusst als Navigations-/Kompatibilitätsstubs erhalten bleiben sollen oder entfernt werden können.

---

## First 3 Refactors I would do

### P0.1 — Media Preview aus dem MainActor holen
- **Ziel**
  - Detailansichten für Entity/Attribute dürfen beim Öffnen nicht erst Counts + Attachment-Preview + Legacy-Migration auf dem MainActor machen.
- **Betroffene Dateien**
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`
  - voraussichtlich neue Split-Dateien wie `NodeMediaPreviewLoader+Queries.swift`, `NodeMediaPreviewLoader+Snapshot.swift`
  - Call-Sites in `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
  - Call-Sites in `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- **Risiko**
  - mittel
  - wichtig ist, keine `@Model`-Objekte über falsche Actor-Grenzen zu ziehen
- **Erwarteter Nutzen**
  - spürbar weniger UI-Stalls beim Öffnen von Details
  - klarere Trennung zwischen Anzeige und Datenvorbereitung

### P0.2 — Stats Attachment Aggregate billiger machen
- **Ziel**
  - Attachment-Bytes/-Counts in Stats nicht mehr über Vollfetch aller `MetaAttachment` berechnen.
- **Betroffene Dateien**
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift`
  - ggf. `BrainMesh/Stats/GraphStatsLoader.swift`
- **Risiko**
  - niedrig bis mittel
  - fachlich simpel, aber man muss die Cache-/Revision-Semantik sauber halten
- **Erwarteter Nutzen**
  - bessere Stats-Skalierung bei vielen Attachments
  - weniger unnötige Blob-nahe Arbeit

### P0.3 — GraphCanvas-Host weiter entwirren
- **Ziel**
  - `GraphCanvasScreen` soll weniger „alles auf einmal“ orchestrieren: Load-Pipeline, Cross-Screen-Jumps, MiniMap-Throttling, Selection-Derivates und Toolbar-/Sheet-Flow entkoppeln.
- **Betroffene Dateien**
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`
  - neue Split-Dateien wie `GraphCanvasScreen+LoadPipeline.swift`, `GraphCanvasScreen+JumpHandling.swift`, `GraphCanvasScreen+MiniMap.swift`, `GraphCanvasScreen+Selection.swift`
- **Risiko**
  - mittel
  - GraphCanvas ist state-heavy; refactor muss mechanisch und testorientiert sein
- **Erwarteter Nutzen**
  - kleinere PRs möglich
  - geringeres Regressionsrisiko im heißesten Screen der App
  - bessere Lesbarkeit des tatsächlichen Steuerflusses
