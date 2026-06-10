# ARCHITECTURE_NOTES.md

## Scope

Diese Notizen basieren auf dem tatsächlichen Projektstand im ZIP. Schwerpunkte wurden strikt nach Priorität bewertet:

1. Sync / Storage / Model
2. Entry Points + Navigation
3. Große Views / Services
4. Konventionen + Workflows

Alle unklaren Punkte sind als **UNKNOWN** markiert und unten gesammelt.

## Entry Points + Navigation

### App Entry

- `BrainMesh/BrainMeshApp.swift`
  - erstellt das SwiftData-Schema
  - konfiguriert CloudKit oder lokalen Fallback
  - initialisiert globale Stores/Koordinatoren
  - konfiguriert alle Loader/Hydrators über `AppLoadersConfigurator`

### App Root

- `BrainMesh/AppRoot/AppRootView.swift`
- `BrainMesh/AppRoot/AppRootView+Startup.swift`
- `BrainMesh/AppRoot/AppRootView+ScenePhase.swift`
- `BrainMesh/AppRoot/AppRootView+Onboarding.swift`

Verantwortung:
- Cold-start Bootstrap
- Active-Graph-Validierung
- Legacy-Migration/Backfills
- Autohydration für Bilder
- Auto-Lock bei Background
- Onboarding-Autopräsentation

### Root Tabs

- `BrainMesh/ContentView.swift`
  - `EntitiesHomeView`
  - `GraphCanvasScreen`
  - `GraphStatsView`
  - `SettingsView`

### Programmatic Routing

- `BrainMesh/RootTabRouter.swift`
  - programmatic tab switching
- `BrainMesh/GraphJumpCoordinator.swift`
  - cross-screen jump in den Graph-Tab mit staged selection/centering

### Wichtige Navigationsknoten

- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Body.swift`
  - Home-Suche, Add Entity, Graph-Picker, Layout-Optionen
- `BrainMesh/GraphCanvas/GraphCanvasScreen/*`
  - Canvas, Inspector, Focus-Picker, Node-Detail-Sheets
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
  - detail-lastige Hosts mit Medien-, Link-, Notes- und Details-Flows
- `BrainMesh/GraphPicker/GraphPickerSheet.swift`
  - graph switching, rename, delete, security, paywall-gate
- `BrainMesh/GraphTransfer/GraphTransferView/*`
  - import/export flows

## Sync / Storage / Model

### Was faktisch vorhanden ist

- SwiftData als Primärpersistenz (`BrainMesh/BrainMeshApp.swift`)
- CloudKit private DB via `.automatic`
- Release-Fallback auf lokalen Store
- iCloud-Statusoberfläche über `BrainMesh/Settings/SyncRuntime.swift`
- Legacy-/Backfill-Bootstrap beim Start
- zusätzliche lokale Medien-Caches
- kein offensichtlicher externer Backend-Layer

### Storage-Entscheidungen

#### 1) Multi-Graph über `graphID` statt tiefer Graph-Relationships

Betroffene Dateien:
- `BrainMesh/Models/MetaEntity.swift`
- `BrainMesh/Models/MetaAttribute.swift`
- `BrainMesh/Models/MetaLink.swift`
- `BrainMesh/Models/DetailsModels.swift`
- `BrainMesh/Attachments/MetaAttachment.swift`

Vorteile:
- sanfte Migration alter Daten
- einfache graph-scoped Queries
- weniger Relationship-Komplexität zwischen Graph und Child-Modellen

Kosten:
- jeder neue Query-Pfad muss Graph-Scoping bewusst setzen
- Legacy-Daten mit `graphID == nil` brauchen Sonderlogik
- Inkonsistenzen sind möglich, wenn owner und `graphID` auseinanderlaufen

#### 2) Medien doppelt: Sync-Blob plus lokaler Cache

Betroffene Dateien:
- `BrainMesh/Models/MetaEntity.swift`
- `BrainMesh/Models/MetaAttribute.swift`
- `BrainMesh/Attachments/MetaAttachment.swift`
- `BrainMesh/ImageHydrator.swift`
- `BrainMesh/Attachments/AttachmentHydrator.swift`

Vorteile:
- UI liest überwiegend lokale Dateien
- neue Geräte können Cache-Dateien nachhydratisieren
- Application-Support kann repariert werden

Kosten:
- Blob-Druck in SwiftData/CloudKit bleibt real
- Cache-Lifecycle muss robust bleiben
- Queries gegen Attachments mit `externalStorage` sind teuer, wenn Predicates unsauber werden

#### 3) Import/Export deckt nur einen Teil der Daten ab

Betroffene Dateien:
- `BrainMesh/GraphTransfer/GraphExportFileV1.swift`
- `BrainMesh/GraphTransfer/GraphTransferDTOs.swift`
- `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Export.swift`
- `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`

Fakt:
- Entities/Attributes können `imageData` mitnehmen
- `MetaAttachment` ist nicht Teil des Formats

Konsequenz:
- Ein `.bmgraph` ist kein vollständiges Backup aller Medien
- Nutzererwartung kann hiervon abweichen, wenn das UI das nicht klar kommuniziert

### Migration / Evolvierbarkeit

Vorhanden:
- Bootstrap-Migrationen für fehlende Graph-Zuordnung und Suchfelder
- Attachment-GraphID-Migration, um store-translatable AND-Predicates zu ermöglichen

Nicht gefunden:
- **UNKNOWN:** `SchemaMigrationPlan`
- **UNKNOWN:** `VersionedSchema`
- **UNKNOWN:** explizite Merge-/Konfliktstrategie

### Offline / Multi-Device Risiken

- Release-Fallback auf lokal kann Sync-Probleme funktional maskieren
- Debug und Release nutzen unterschiedliche CloudKit-Umgebungen im praktischen Betrieb, was beim Testen leicht verwirrt (`BrainMesh/Settings/SettingsView+SyncSection.swift`)
- Legacy-Daten mit `graphID == nil` können noch Folgekosten erzeugen, wenn ein neuer Query-Pfad sie nicht sauber behandelt

## Big Files List

Top 15 App-Dateien nach Zeilenanzahl im aktuellen Stand:

1. `BrainMesh/Settings/BrainMeshGuideView.swift` — 650 Zeilen  
   Zweck: umfangreiche In-App-Hilfe  
   Risiko: hoher UI-Text- und Section-Umfang, schwer reviewbar, leichte Layout-Regressionen

2. `BrainMesh/GraphCanvas/GraphDetailsFocus.swift` — 579 Zeilen  
   Zweck: Details-Fokus-Modell, Vergleiche, Prepared-State, Matching  
   Risiko: Fachlogik, Renderlogik und Datentransformationen liegen dicht beieinander

3. `BrainMesh/GraphCanvas/GraphCanvasTypes.swift` — 463 Zeilen  
   Zweck: zentrale Canvas-Typen und Hilfen  
   Risiko: hoher “god-types”-Charakter, Änderungen haben große Streuung

4. `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift` — 437 Zeilen  
   Zweck: Importpipeline  
   Risiko: lange Methode, Fortschritt, Batching, Mapping und Fehlerpfade in engem Verbund

5. `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift` — 384 Zeilen  
   Zweck: Predicates, Revisionen, gemeinsame Stats-Helfer  
   Risiko: Service-Basis ist dicht und zentral für mehrere Teilmodule

6. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Highlights.swift` — 352 Zeilen  
   Zweck: Highlight-/Shared-Detail-UI  
   Risiko: UI-Logikballung, wiederverwendete Sektionen schwer isolierbar

7. `BrainMesh/Stats/GraphStatsLoader.swift` — 348 Zeilen  
   Zweck: Dashboard-/Counts-Loader mit Cache  
   Risiko: Revision-, Cache- und Background-Logik in einer Datei

8. `BrainMesh/GraphPicker/GraphPickerListView.swift` — 344 Zeilen  
   Zweck: Graph-Liste und Verwaltungs-UI  
   Risiko: viele Zustände/Varianten in einer View

9. `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift` — 341 Zeilen  
   Zweck: große Connections-Ansicht  
   Risiko: list-heavy UI, potenziell viele Zustände/Filter

10. `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Neighborhood.swift` — 335 Zeilen  
    Zweck: BFS- und Neighborhood-Laden  
    Risiko: echter Hot Path, Query- und Mapping-Kosten wachsen mit Graphgröße

11. `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift` — 331 Zeilen  
    Zweck: Markdown-Zubehör/Preview  
    Risiko: Rendering-/UI-Helfer sehr groß; potenziell schwer sauber zu ändern

12. `BrainMesh/Attachments/AttachmentImportPipeline.swift` — 326 Zeilen  
    Zweck: Datei-/Video-/Bild-Import  
    Risiko: viele Format- und Fehlerpfade, I/O-lastig

13. `BrainMesh/Pro/ProCenterView.swift` — 322 Zeilen  
    Zweck: Pro-Center UI  
    Risiko: mittel; hauptsächlich UI-Komplexität

14. `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift` — 321 Zeilen  
    Zweck: Stats-Dashboard UI  
    Risiko: Orchestrierung, viele State-Wechsel, lazy loading

15. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift` — 317 Zeilen  
    Zweck: Home-Suche und Match-Auflösung  
    Risiko: mehrfacher Fetch je Suche, Link-/Attribute-Match-Pfade

## Hot Path Analyse

### Rendering / Scrolling

#### Positiv auffällig

- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - hält mehrere Derived-State-Caches wie `drawEdgesCache`, `lensCache`, `physicsRelevantCache`, `detailsFocusSummaryCache`, `detailsFocusRenderPlanCache`
  - Grund: vermeidet Wiederberechnung bei Physics-Ticks und Pan/Zoom-Re-Renders

- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Loading.swift`
  - stale-result guard via `currentLoadToken`
  - cancellable load task
  - Commit der Snapshot-Daten in einem Schritt

- `BrainMesh/Support/AppLoadersConfigurator.swift`
  - zentrale Off-main-Konfiguration vieler Loader
  - reduziert das Risiko von “Fetch im body”

#### Hotspot 1: Graph Neighborhood Load

Datei:
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Neighborhood.swift`

Konkrete Gründe:
- BFS über Hops mit wiederholten Link-Fetches pro Frontier
- `frontierIDs.contains(...)` und später `visibleIDs.contains(...)` in Predicates; store translation ist hier sensibel
- Oversampling bei Zusatzlinks (`fetchLimit = remaining * 4`)
- in-memory Sort pro Entity für Attribute
- Aufbau von Render-Caches und prepared detail focus state pro Load
- Kosten wachsen mit `hops`, `includeAttributes`, `maxNodes`, `maxLinks`

Symptomklasse:
- Canvas-Wechsel, Fokuswechsel und große Graphen sind teuer
- keine offensichtliche Wiederverwendung gleicher Neighborhood-Snapshots zwischen nah beieinanderliegenden UI-Zuständen

#### Hotspot 2: Entities Home Search

Dateien:
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`

Konkrete Gründe:
- Suchpfad macht mehrere Fetches:
  - Entity-Name/Notes
  - Attribute-DisplayName/Notes
  - Link-Note-Matches
- danach Owner-/Endpoint-Auflösung und Merge
- `contains(term)` auf folded Strings ist praktisch, aber potentiell scan-lastig
- Link-Matches ziehen zusätzliche Entity-/Attribute-Auflösung nach
- Counts-Cache basiert nur auf graph-scope TTL, nicht auf Query-Revisionen

Symptomklasse:
- schnelle Eingabe oder häufiges Wechseln der Graphen kann viele ähnliche Abfragen erzeugen
- technisch off-main, aber weiterhin teuer

#### Hotspot 3: Stats Dashboard / Counts

Dateien:
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Media.swift`
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Structure.swift`
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Trends.swift`
- `BrainMesh/Stats/GraphStatsLoader.swift`

Konkrete Gründe:
- viele einzelne `fetchCount`-Aufrufe
- `attachmentAggregate` lädt komplette `[MetaAttachment]`, um `byteCount` zu summieren
- Media-/Structure-/Trends-Snapshots fetch-en volle Modellmengen und sortieren/reduzieren in-memory
- Revision-Cache ist gut, aber der erste Lauf und Force-Reloads bleiben teuer

Symptomklasse:
- Dashboard ist sauber ausgelagert, aber große Medienbestände werden spürbar

#### Hotspot 4: Detail Hosts

Dateien:
- `BrainMesh/Mainscreen/EntityDetail/EntityDetailView.swift`
- `BrainMesh/Mainscreen/AttributeDetail/AttributeDetailView.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/*`

Konkrete Gründe:
- viele lokale States, viele Sheets, mehrere `.task(id:)`
- hohe Orchestrierungsdichte
- UI ist zwar schon gesplittet, aber ein einzelner Host-Reload kann viele Untersektionen invalidieren

Symptomklasse:
- kein klassischer Datenbank-Hotspot im `body`, aber hoher Wartungs- und Invalidierungsdruck

### Sync / Storage

#### Hotspot 5: Attachment Queries auf externen Blobs

Dateien:
- `BrainMesh/Attachments/MetaAttachment.swift`
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader+Query.swift`

Konkrete Gründe:
- `MetaAttachment.fileData` nutzt `externalStorage`
- unsaubere Predicates mit OR/Legacy-Fallback wären hier besonders teuer
- es existiert bereits spezieller Migrationscode, was das Problem bestätigt

Positiv:
- `AttachmentGraphIDMigration` zieht Legacy-Fälle gezielt nach
- `NodeMediaPreviewLoader` trennt graph scopes und merged Preview-IDs bewusst

#### Hotspot 6: Image/Attachment Hydration

Dateien:
- `BrainMesh/ImageHydrator.swift`
- `BrainMesh/Attachments/AttachmentHydrator.swift`

Konkrete Gründe:
- echte I/O-Arbeit: Blob lesen, Datei schreiben
- potentiell viele Records auf neuem Gerät
- streng limitiert und dedupliziert, aber weiterhin spürbar als Hintergrundlast

Positiv:
- `AsyncLimiter`
- run-once-per-launch Schutz
- visible-item-orientierte Attachment-Hydration

#### Hotspot 7: Import

Dateien:
- `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
- `BrainMesh/Attachments/AttachmentImportPipeline.swift`

Konkrete Gründe:
- große Datenmengen, Batching, Mapping, Save-Punkte
- Kompression und Datei-I/O bei Medienimport
- Abbruch/Teilimport muss sauber gedacht werden

### Concurrency

#### Vorhandene gute Muster

- Actor-basierte Loader mit eigenen `ModelContext`s
- `AnyModelContainer` als minimaler Wrapper für Concurrency-Grenzen
- DTO/Snapshot-Rückgaben statt `@Model`-Transport
- Cancel-/stale guards im Canvas

#### Konkrete Risiken

- `RootTabRouter` und `GraphJumpCoordinator` vermeiden bewusst class-weites `@MainActor`, um `ObservableObject`-Probleme zu umgehen. Das ist vernünftig, aber man muss bei Erweiterungen diszipliniert nur `@MainActor`-Mutationen hinzufügen.
- View-Hosts mit vielen `.task`/`.onChange`-Kombinationen bleiben anfällig für Task-Lifetime-Drift, wenn künftig weitere Trigger hinzukommen.
- `GraphTransferService+Import.swift` und Import-nahe Pipelines sollten Abbruchpfade weiter klarer strukturieren.
- **UNKNOWN:** Eine systematische, projektweite Policy für Cancellation-Protokolle und Task-Ownership wurde als Dokumentation nicht gefunden.

## Refactor Map

### Konkrete Splits

#### 1) `GraphTransferService+Import.swift` weiter in Phasen schneiden

Ziel-Dateien:
- `GraphTransferService+Import.Validation.swift`
- `GraphTransferService+Import.Graph.swift`
- `GraphTransferService+Import.Entities.swift`
- `GraphTransferService+Import.Details.swift`
- `GraphTransferService+Import.Attributes.swift`
- `GraphTransferService+Import.Links.swift`

Nutzen:
- klare Testpunkte pro Phase
- Fehleranalyse einfacher
- weniger Risiko bei zukünftigen Importformat-Erweiterungen

#### 2) `GraphDetailsFocus.swift` fachlich trennen

Ziel-Dateien:
- `GraphDetailsFocus+Comparisons.swift`
- `GraphDetailsFocus+PreparedState.swift`
- `GraphDetailsFocus+Matching.swift`
- `GraphDetailsFocus+RenderPlan.swift`

Nutzen:
- Matching-Logik getrennt von Datenrepräsentation
- bessere Tests für Vergleichsoperatoren und Renderplanung
- weniger “one-file-to-break-them-all”

#### 3) `BrainMeshGuideView.swift` rein UI-seitig modularisieren

Ziel-Dateien:
- `BrainMeshGuideView+Overview.swift`
- `BrainMeshGuideView+Concepts.swift`
- `BrainMeshGuideView+Workflows.swift`
- `BrainMeshGuideView+Troubleshooting.swift`

Nutzen:
- niedrigeres Review-Risiko
- bessere Lokalisierbarkeit/Pflege
- kein fachlicher Einfluss

#### 4) `GraphPickerListView.swift` in Card-/Footer-/List-SubViews schneiden

Ziel-Dateien:
- `GraphPickerRow.swift`
- `GraphPickerUsageCard.swift`
- `GraphPickerDuplicateNotice.swift`
- `GraphPickerEmptyState.swift`

Nutzen:
- klarere Zustandsräume
- weniger Layout-Regressionsrisiko

### Cache- / Index-Ideen

#### A) Neighborhood Snapshot Cache

Für:
- `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Neighborhood.swift`

Cache-Key:
- `graphID`
- `centerID`
- `hops`
- `includeAttributes`
- `maxNodes`
- `maxLinks`

Invalidation:
- Graph-revision aus Entities/Attributes/Links/DetailValues ableiten
- Fokuswechsel ohne Datenänderung sollte Cache nutzen können

Erwarteter Nutzen:
- spürbar weniger Last beim wiederholten Wechsel zwischen ähnlichen Fokuszuständen

#### B) Stats Attachment Aggregate Cache auf Byte-Summe ohne Vollfetch vorbereiten

Für:
- `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`

Idee:
- wenigstens graph-scoped `byteCount`-Summen separat cachen
- mittelfristig eine inkrementelle Aggregatpflege prüfen

Erwarteter Nutzen:
- weniger Vollmaterialisierung von `MetaAttachment`

#### C) Search Snapshot Cache für Entities Home

Für:
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`

Cache-Key:
- `graphID`
- `foldedSearch`
- sichtbare optionale Count-Flags

Invalidation:
- graph-spezifisch bei Entity/Attribute/Link-Revisionsänderung
- nicht nur TTL

Erwarteter Nutzen:
- tippen/schnelle Tab-Wechsel günstiger

### Vereinheitlichungen

- Einheitliche Revision-Strategie für Loader statt gemischtem TTL-, Manual- und Force-Reload-Mix
- Gemeinsame Graph-scope Predicate Helpers projektweit zentralisieren
- Wiederkehrende “Host + Loading + Sheets + Sections”-Muster der Detailscreens stärker standardisieren
- Observability-Events für Import, Stats und Hydration konsistenter machen

## Risiken & Edge Cases

- **Datenvollständigkeit:** `.bmgraph` exportiert keine `MetaAttachment`
- **Legacy-Daten:** `graphID == nil` bleibt ein Sonderfall in vielen Query-Pfaden
- **Duplicate Graph IDs:** Projekt enthält Dedupe- und Delete-Logik für multiple `MetaGraph`-Records mit gleicher UUID (`BrainMesh/GraphPicker/GraphPickerSheet.swift`, `BrainMesh/GraphPicker/GraphDeletionService.swift`)
- **Blob-Druck:** `imageData` und `fileData` erhöhen Storage-/Sync-Kosten
- **Local-only Fallback:** Release kann Sync-Fehler still in “funktioniert lokal” verwandeln
- **Import-Abbruch:** Teilweise importierte Datensätze sind ein realistischer Zustand, wenn der Prozess mittendrin endet
- **Mixed Environments:** Debug vs. Release/TestFlight kann bei CloudKit-Tests zu scheinbar “fehlenden Daten” führen
- **Locking vs. System Picker:** Bereits entschärft durch debounce/grace window im Scene-Phase-Handling (`BrainMesh/AppRoot/AppRootView+ScenePhase.swift`)
- **UNKNOWN:** Es ist nicht eindeutig, ob `remote-notification` aktiv benötigt wird oder nur vorbereitet wurde
- **UNKNOWN:** Keine klare Dokumentation zu Konfliktfällen bei gleichzeitigen Multi-Device-Edits gefunden

## Observability / Debuggability

### Bereits vorhanden

- `BrainMesh/Observability/BMObservability.swift`
  - `BMLog.load`
  - `BMLog.expand`
  - `BMLog.physics`
  - `BMDuration`

- `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Loading.swift`
  - loggt Load-Erfolg/Fehler mit Modus, Fokus, Hops, Node-/Edge-Zahl, Dauer

- `BrainMesh/Settings/SyncRuntime.swift`
  - iCloud-Account-Status
  - Storage-Mode

- `BrainMesh/Settings/SettingsView+SyncSection.swift`
  - Debug-Hinweis zu CloudKit Development vs Release

- `BrainMesh/ImportProgress/*`
  - wiederverwendbarer Fortschrittszustand für Import-/Medienflows

### Was noch fehlt

- strukturierte Metriken für Loader-Cache-Hits außerhalb einzelner Actors
- Stats-spezifische Laufzeitmetriken
- Import-Telemetrie pro Phase
- reproduzierbare Debug-Hilfen für Merge-/Sync-Konflikte

### Reproduktionshinweise für Problemklassen

- Graph-Load-Probleme:
  - Canvas öffnen
  - Fokus wechseln
  - `BMLog.load` in Console beobachten

- Sync-Probleme:
  - Storage-Mode und iCloud-Status in Settings prüfen
  - Build-Konfiguration der Geräte vergleichen

- Medien-/Cache-Probleme:
  - Wartungsansicht öffnen
  - Cache-Rebuild/Hydration testen
  - neues Gerät oder leeren Cache als Repro nutzen

## Open Questions

- **UNKNOWN:** Gibt es bewusst keinen `SchemaMigrationPlan`, oder liegt er außerhalb des ZIPs?
- **UNKNOWN:** Wie sollen Konflikte bei gleichzeitigen Edits desselben Graphen, Attributs oder Detail-Werts auf mehreren Geräten fachlich aufgelöst werden?
- **UNKNOWN:** Ist `UIBackgroundModes = remote-notification` aktuell aktiv genutzt?
- **UNKNOWN:** Sollen Entity-/Attribute-Lock-Felder langfristig eine eigene UX bekommen oder sind sie historisch/experimentell?
- **UNKNOWN:** Ist der Ausschluss von `MetaAttachment` aus `.bmgraph` ein bewusstes Produktlimit oder nur der aktuelle Stand?
- **UNKNOWN:** Gibt es Obergrenzen/Policy für Gesamtmenge an Blob-Daten pro Graph oder Gerät?
- **UNKNOWN:** Existiert außerhalb des Projekts zusätzliche Observability, z. B. Crash-Reporting oder Analytics?

## First 3 Refactors I would do

### P0.1 — Neighborhood-Loading stabiler und wiederverwendbar machen

- **Ziel**  
  Wiederholte Graph-Fokus-Ladevorgänge billiger machen, ohne das sichtbare Verhalten zu ändern.

- **Betroffene Dateien**  
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Neighborhood.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader.swift`
  - ggf. neue Cache-Datei unter `BrainMesh/GraphCanvas/GraphCanvasDataLoader/`

- **Risiko**  
  Mittel. Falsche Invalidierung würde stale Graph-Snapshots zeigen.

- **Erwarteter Nutzen**  
  Spürbar bessere Reaktionszeit im Canvas bei Fokuswechseln, weniger wiederholte BFS- und Zusatzlink-Abfragen.

### P0.2 — Stats-Aggregate von Vollfetches entkoppeln

- **Ziel**  
  Attachment- und Snapshot-Kosten im Stats-Bereich reduzieren.

- **Betroffene Dateien**  
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Media.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`

- **Risiko**  
  Niedrig bis mittel. Zahlen müssen exakt gleich bleiben.

- **Erwarteter Nutzen**  
  Schnellere Stats-Ansicht auf größeren Datensätzen, weniger Speicherlast beim Dashboard-Laden.

### P0.3 — Import-Service phasenweise aufteilen

- **Ziel**  
  Die Importpipeline testbarer, reviewbarer und erweiterbarer machen.

- **Betroffene Dateien**  
  - `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
  - neue Split-Dateien im gleichen Ordner

- **Risiko**  
  Mittel. Import ist zustands- und fortschrittsreich; sauberes Move-only-Refactoring nötig.

- **Erwarteter Nutzen**  
  Weniger Fehler bei künftigen Formatänderungen, klarere Tests, geringere Einstiegshürde für Wartung.
