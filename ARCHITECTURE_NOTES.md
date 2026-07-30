# BrainMesh – Architecture Notes

> Detaillierte statische Analyse des bereitgestellten Quellstands. Fakten sind mit konkreten Pfaden belegt; nicht aus dem Archiv ableitbare Punkte sind als **UNKNOWN** markiert.

## 1. Executive Assessment

BrainMesh besitzt bereits mehrere wichtige Schutzlinien:

- SwiftData ist die autoritative Quelle.
- Normale Graphmutationen werden über eine Save-then-publish-Grenze geführt.
- Der Suchindex ist rekonstruierbar und erkennt Sequenzlücken.
- Renderpfade des Canvas sind nach statischen und dynamischen Daten getrennt.
- Große Graph-Canvas-Loads sind mit Node-/Link-Caps begrenzt.
- Detail-Medien und Connections besitzen fetch-limitierte Loader.
- Importfehler werden mit persistenter Cleanup-Logik behandelt.
- Graph Chat ist read-only, graphgescoped und evidenzgebunden.
- Exakt erkannte Single-Node-Field-Fragen werden providerfrei ausgeführt und als autoritativer typisierter Single Fact vollständig appseitig gerendert.
- Der Foundational Fast Path ist über einen verlustfreien Adapter von einer allgemeinen versionierten Typed-Intent-Domain getrennt; beide vorhandenen Foundational Actions laufen durch denselben lokalen Execution Kernel.
- Entity- und Attribute-Nodes besitzen mit `GraphNodeProfile` jetzt ein vollständiges, value-only und unabhängig begrenztes autoritatives Read-Modell. `GetNodeTool` adaptiert dieses Modell, statt Details, Links und Attachments über ein gemeinsames Restbudget einzeln zusammenzusuchen.
- Erfolgreiche Node-Details-Turns besitzen mit `GraphChatAnswerArtifactNodeProfilePayload` ein eigenes verlustfreies Artifact. Ein gemeinsamer deutscher/englischer Präsentationswert speist deterministischen Antworttext und strukturierte UI; Copy übernimmt denselben finalisierten `GraphChatAnswer`.
- Freie Find-Nodes- und Entity-List-Formulierungen werden nach dem Foundational Fast Path durch einen toolfreien On-Device-Interpreter ausschließlich in einen begrenzten untrusted Semantic Draft klassifiziert. Identitäten, Scope, technische Action, Query, Limits, Evidence, Artifacts und sichtbare Antwort bleiben appseitig.
- Node Details, Compare Nodes und Inspect Graph State werden nach semantischer Klassifikation vollständig appseitig kompiliert und providerfrei über denselben lokalen Execution Kernel abgeschlossen. Node-IDs, Tools, Comparison-Art/-Features, Related-/Hub-Limits und Artifact-Struktur bleiben app-owned.
- Finalisierte lokale Typed-Intent-Interpretationen sind fachlich editierbar. Jede Korrektur wird an ursprünglichen Turn, Conversation, Scope, Checkpoints und Artifact-Session gebunden, gegen ein frisches vollständiges Schema revalidiert und als providerfreier lokaler Ersatzturn mit atomarem Conversation-/Artifact-Swap ausgeführt.
- INTENT-COMPILER-7 schließt Ausbaustufe 2 mit einer expliziten Cutover-Policy ab: Alle neun unterstützten Familien enden lokal oder in einer fachlichen Clarification. Freie Provider-Toolwahl, modellbestimmte Query-Pläne, Limits und finaler Fachtext sind in diesem Pfad nicht mehr erreichbar.
- Eine gemeinsame `GraphChatIntentLimitPolicy` besitzt die fachlich gleichen Grenzen. Der Interpreter verwendet ein begrenztes Standardprofil und ausschließlich bei Context-Window-Überlauf genau einen Compact-Retry; manipulierte oder schemawidrige Drafts scheitern ohne Tool-Repair oder Provider-Rettung.

Die höchsten Architektur-Risiken liegen trotzdem an drei Systemgrenzen:

1. **SwiftData/CloudKit-Schema und Store-Lifecycle**
   - kein `VersionedSchema`/`SchemaMigrationPlan`;
   - Release-Fallback auf einen lokalen Store;
   - optionale `graphID` und mehrere skalare Fremdschlüssel.
2. **Abgeleitete Vollgraph-Snapshots**
   - Search-Rebuild/Reconciliation, Home-Health und Stats laden bei Cache Miss große Datenmengen;
   - mehrere Schritte materialisieren und sortieren komplette Arrays im Speicher.
3. **Main-Actor- und Task-Lifecycle**
   - Canvas-Physics und Dictionary-Publikation laufen auf dem MainActor;
   - Graph-Chat-State ist komplex und stark taskgetrieben;
   - Event-Streams sind prozesslokal und standardmäßig unbounded.

## 2. Analyseumfang und Größenprofil

- Produktionscode: ca. 126.843 Swift-Zeilen.
- Tests: ca. 65.661 Swift-Zeilen.
- Größte Produktionsbereiche:
  - `BrainMesh/GraphChat/`: ca. 44.005 Zeilen in 139 Dateien;
  - `BrainMesh/Mainscreen/`: ca. 23.393 Zeilen in 162 Dateien;
  - `BrainMesh/GraphCanvas/`: ca. 11.207 Zeilen in 69 Dateien;
  - `BrainMesh/Search/`: ca. 11.179 Zeilen in 32 Dateien;
  - `BrainMesh/GraphTransfer/`: ca. 5.711 Zeilen in 45 Dateien;
  - `BrainMesh/Stats/`: ca. 5.492 Zeilen in 39 Dateien.
- Die Analyse ist statisch. Ein Xcode-Build und Instruments-Profiling waren in der Analyseumgebung nicht verfügbar.
- Reale P50/P95-Latenzen und produktive Datenmengen sind **UNKNOWN U7**.

## 3. Big Files List – Top 15 nach Zeilen

| Rang | Zeilen | Pfad | Grober Zweck | Warum riskant |
|---:|---:|---|---|---|
| 1 | 1.344 | `BrainMesh/Search/Index/GraphSearchIndexer.swift` | Vollaufbau, Eventkonsum, inkrementelle Mutation, Status | Mehrere Zustandsmaschinen in einem Actor; Full Build hält Source-Snapshot, Dokumente und Manifeste gleichzeitig; Fehler-/Gap-Matrix ist änderungssensitiv |
| 2 | 1.329 | `BrainMesh/Search/Index/GraphSearchIndexStore+Operations.swift` | SQLite-Suche, CRUD, Transaktionen, Row Mapping | SQL-, Encoding-, Query- und Recovery-Verantwortung gekoppelt; kleine Schemaänderung berührt viele Pfade; hohe Testmatrix |
| 3 | 1.078 | `BrainMesh/GraphChat/Provider/GraphChatModelToolRuntime.swift` | Ausführung aller sechs Chat-Tools, Budgets, Scope, Evidenz | Read-only-/Scope-Sicherheitsgrenze; Tool-spezifische Logik und Sessionbudget teilen Zustand; Fehler kann Evidenz oder Alias-Auflösung verfälschen |
| 4 | 935 | `BrainMesh/Search/Index/GraphSearchIndexStore+Schema.swift` | Pfad, Open, PRAGMAs, Schema, Backendwahl, Integritätsprüfung | DDL, Migration, Recovery und potenziell destruktiver Rebuild liegen zusammen; Fehler betrifft gesamten Index-Lifecycle |
| 5 | 880 | `BrainMesh/Search/Index/GraphSearchIndexReconciler.swift` | Foreground-/On-Demand-Abgleich, Manifest-Diff, Coalescing | Remote-Sync-Korrektheitsgrenze; Full-Snapshot-Kosten; Waiter/Throttle/Coalescing erhöhen Concurrency-Komplexität |
| 6 | 851 | `BrainMesh/GraphChat/Provider/FoundationModelsGraphChatProvider.swift` | FoundationModels-Schemas, Tool-Adapter, Sessions, Streaming | Framework-Verfügbarkeit, Session-Lifecycle, Cancellation und Error Mapping gekoppelt; Compiler-/OS-Fallbacks ändern viele Zweige |
| 7 | 834 | `BrainMesh/GraphChat/UI/GraphChatMessageActionController.swift` | Edit, Resend, Regenerate, Feedback, Checkpoints | Viele verzweigte User-Aktionen mit Task-Cancellation; Gefahr inkonsistenter Conversation-/UI-Zustände |
| 8 | 827 | `BrainMesh/GraphChat/UI/GraphChatViewModel.swift` | UI-State, Lifecycle, Composer, Generation, Navigation | `@MainActor`-State mit breiter Invalidierungsfläche; hohe Abhängigkeit zu Controllern/Coordinators |
| 9 | 813 | `BrainMesh/GraphChat/Artifacts/GraphChatAnswerArtifacts.swift` | Artifact-Domain, Payloads, Validierung | Viele Domänentypen in einer Datei; Change Amplification und lange Compile-/Review-Fläche |
| 10 | 812 | `BrainMesh/Search/Index/GraphSearchDocumentBuilder.swift` | Domainquellen → Suchdokumente, Ranking, Evidenz | Muss mit Model, Indexschema und Chat-Evidenz synchron bleiben; Full Build erzeugt viele Zwischenwerte |
| 11 | 777 | `BrainMesh/GraphChat/Query/GraphQueryPlanValidation.swift` | Query-Normalisierung und semantische Validierung | Korrektheits-/Sicherheitsgrenze für Typen, Operatoren und Scope; viele Kombinationen, schwer vollständig zu überblicken |
| 12 | 777 | `BrainMesh/GraphChat/Conversation/GraphChatConversationReferenceResolver.swift` | Multi-Turn-Referenzen und Alias-Revalidierung | Ambiguität, gelöschte Nodes und Graphwechsel erzeugen zeitabhängige Edge Cases |
| 13 | 773 | `BrainMesh/GraphChat/Conversation/GraphChatConversationContext.swift` | Kontext-Snapshot, Budgets, Formatierung | Token-/Größenbudgets und stale References gekoppelt; Änderungen beeinflussen Antwortqualität und Laufzeit |
| 14 | 762 | `BrainMesh/Search/Index/GraphSearchIndexStore+SourceManifest.swift` | Source-Manifeste, Hashes und Reconcile-Operationen | Atomizität zwischen Dokumenten und Manifesten; große Diff-Schleifen; Schema-/Hash-Drift |
| 15 | 745 | `BrainMesh/Search/Index/GraphSearchDocument.swift` | Dokument-/Metadatenschema, Hashing, Validierung | Zentrale Cross-Layer-Datenstruktur; Änderungen propagieren in Builder, Store, Queries und Chat |

### Bewertung der Dateigröße

- Größe allein ist kein Fehler.
- Die Search-Dateien sind riskant, weil sie Persistenz, Recovery und Konsistenz koordinieren.
- Die Graph-Chat-Dateien sind riskant, weil sie viele Zustandsübergänge und Sicherheitsgrenzen enthalten.
- Reine Aufteilung in weitere `Type+Concern.swift`-Extensions reduziert die fachliche Kopplung nicht.
- Bevorzugt werden neue, testbare Typen mit engem Input/Output und klarer Zustandsverantwortung.

## 4. Persistenz-, Sync- und Modellanalyse

### 4.1 Store-Erstellung

Pfad: `BrainMesh/BrainMeshApp.swift`

- Das Schema umfasst acht Typen.
- Primär wird `ModelConfiguration(schema:cloudKitDatabase: .automatic)` verwendet.
- CloudKit arbeitet über den privaten Container aus `BrainMesh/BrainMesh.entitlements`.
- Debug stoppt bei Containerfehlern sofort.
- Release erstellt bei Containerfehlern einen lokalen ModelContainer.
- `BrainMesh/Settings/SyncRuntime.swift` zeigt `.cloudKit` oder `.localOnly`.

#### Risiko: zwei mögliche Store-Lebenszyklen

Konkreter Grund:

- CloudKit- und lokaler Fallback werden als getrennte `ModelConfiguration`-Initialisierungen erstellt.
- Im Code existiert keine explizite Promotion-, Merge- oder Recovery-Operation zwischen beiden Modi.
- Ein Release-Start im local-only-Modus kann deshalb Daten erzeugen, deren späterer Übergang nicht fachlich definiert ist.

**UNKNOWN U2**: Ob SwiftData beim nächsten CloudKit-fähigen Start denselben Store übernimmt, einen separaten Store öffnet oder eine manuelle Überführung benötigt, ist im Projekt nicht spezifiziert.

Empfehlung:

- Store-Modus und persistente Store-URL explizit protokollieren.
- Local-only-Fallback als benannten Recovery-Zustand modellieren.
- Vor Einführung eine Gerätetestmatrix mit iCloud aus/an, App-Neustart und bereits vorhandenen Daten ausführen.
- Keine automatische Datenkopie implementieren, bevor die tatsächlichen Store-URLs und SwiftData-Semantik verifiziert sind.

### 4.2 Schema und Migration

Belegte Fakten:

- Kein `VersionedSchema`, `SchemaMigrationPlan` oder `MigrationStage` gefunden.
- Der App-Start baut direkt ein aktuelles `Schema`.
- App-level Backfills reparieren Daten nach Containeröffnung.
- `graphID` bleibt auf mehreren Typen optional.
- Keine `@Attribute(.unique)`-Deklaration gefunden.

Konkrete Risiken:

- Ein inkompatibler Modelwechsel kann vor App-level Backfills bereits beim Containeröffnen scheitern.
- CloudKit-kompatible Schemaänderungen sind enger als rein lokale SwiftData-Änderungen.
- App-level Reparaturen besitzen keine explizite Schema-Version als Voraussetzung.
- Backfills und CloudKit-Remote-Imports können zeitlich überlappen.
- Ohne Fixture eines alten Stores bleibt die reale Migrationsfähigkeit ungetestet.

**UNKNOWN U1**: Deployed CloudKit-Schema, Development-/Production-Status und Freigabeprozess.

**UNKNOWN U3**: Welche produktiven Vorgängerstores als Migrationsfixtures gelten müssen.

Empfohlene Reihenfolge:

1. Aktuellen Modelstand als `VersionedSchemaV1` einfrieren.
2. `SchemaMigrationPlan` einführen, selbst wenn die erste Migration leer ist.
3. Store-Fixtures aus jeder produktiv relevanten Version versionieren.
4. Backfills mit eigener idempotenter Repair-Version ausstatten.
5. Erst danach optionale Scopes verschärfen oder Relationships ändern.

### 4.3 Graph Scope und Referenzintegrität

Betroffene Modelle:

- `BrainMesh/Models/MetaEntity.swift`
- `BrainMesh/Models/MetaAttribute.swift`
- `BrainMesh/Models/MetaLink.swift`
- `BrainMesh/Models/DetailsModels.swift`
- `BrainMesh/Models/MetaDetailsTemplate.swift`
- `BrainMesh/Attachments/MetaAttachment.swift`

Beobachtung:

- `MetaGraph` besitzt keine Relationship-Sammlung seiner Inhalte.
- Membership läuft über optionale `graphID`.
- Link-Endpunkte, Attachment-Owner und mehrere Detailreferenzen sind skalare UUIDs.
- Integrität wird in `GraphScopedFetches`, Mutation Services und Cleanup-Services erzwungen.

Vorteile:

- CloudKit-freundliche, flache Records.
- Value-Snapshots können ohne tiefe Objektgraphen erzeugt werden.
- Import kann IDs explizit remappen.
- Links bleiben unabhängig von SwiftData-Relationship-Lazy-Loading.

Kosten:

- Cascades decken nicht alle Referenzen ab.
- Jede Fetch-/Route-Implementierung muss den Scope korrekt hinzufügen.
- Dedupe/Import muss Kollisionen aktiv verhindern.
- Denormalisierte Linklabels müssen bei Rename aktualisiert werden.
- Eine gelöschte Definition kann verwaiste skalare `fieldID`-Werte hinterlassen, falls Cleanup umgangen wird.

Konkreter Hotspot:

- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeRoutes.swift` löst ein Ziel über Entity-ID auf, ohne `graphID` in derselben Predicate zu prüfen.
- IDs sind nicht als unique markiert.
- Das ist eine Cross-Graph-Correctness-Lücke, auch wenn UUID-Kollisionen regulär selten sind.

Empfehlung:

- Einen `GraphScopedID<T>`-Value-Type für Routes und Services einführen.
- Ungescopte Fetch-Helper nicht öffentlich anbieten.
- Debug-Assertions in Mutation Services ergänzen: referenzierte Datensätze müssen denselben `graphID` besitzen.
- Importtests mit absichtlich kollidierenden UUIDs ergänzen.

### 4.3.1 Detaildaten-Integrity und Authority

Pfade:

- `BrainMesh/DataAccess/DetailDataIntegrityPolicy.swift`
- `BrainMesh/DataAccess/DetailDataIntegrityValidation.swift`
- `BrainMesh/Mainscreen/Details/DetailsValueEditorSheet/DetailValueMutationService.swift`
- `BrainMesh/DataAccess/GraphReadRepository+Fetch.swift`

Vertrag:

- Die Policy arbeitet ausschließlich auf `Sendable` Value-Snapshots. SwiftData-Modelle werden im besitzenden Context in Snapshots projiziert.
- Eine Field Definition benötigt einen vorhandenen Owner und exakt übereinstimmende `entityID`, `graphID`, Owner-ID und Owner-Graph-ID.
- Ein Value benötigt ein vorhandenes Attribute mit Entity-Owner, exakt übereinstimmende `attributeID`, eine vorhandene Field Definition derselben Entity und einen gemeinsamen Graphen für Value, Attribute, Entity und Definition.
- Der einzige Authority-Key für Detailwerte ist `(graphID, attributeID, fieldID)`.
- Typed Storage ist exakt: kein Slot ist leer; genau der zum Field-Typ passende Slot ist gültig; mehrere oder fremde Slots sind ungültig. `Double` muss endlich sein.

Deterministische Duplicate-Policy:

1. Keys und Records werden lexikographisch nach UUID sortiert.
2. Bei nur leeren Records bleibt die kleinste UUID.
3. Bei leer plus gefüllt bleibt ein gefüllter Record.
4. Bei mehreren gefüllten, äquivalenten typisierten Werten bleibt die kleinste UUID. Text und Choice werden nur für den Vergleich außen getrimmt und kanonisch Unicode-normalisiert; der persistierte Keeper wird nicht konvertiert.
5. Leere und äquivalente Duplikate sind sicher löschbar.
6. Unterschiedliche gefüllte Werte oder ungültige Typed-Storage-Records besitzen keine Authority. Sie werden nicht anhand einer geratenen zeitlichen Reihenfolge gelöscht.
7. Der Detail-Editor kann einen solchen Konflikt durch einen bewussten Save atomar auf genau einen gewählten typisierten Wert konsolidieren; der Save-then-publish-Committer rollt bei Fehler vollständig zurück.

Konsumenten:

- `DetailsFormatting`, vorberechnete Listen-/Canvas-Snapshots und der Value Editor verwenden dieselbe Authority.
- `GraphReadRepository` liefert pro Key höchstens ein autoritatives Value-DTO. Graph Chat und Search konsumieren diese gefilterten DTOs und geben Konflikte nicht als Fakten aus.
- Transfer-Import validiert den vollständigen Detailgraphen vor dem ersten Insert. Export schreibt nur autoritative Definitions und Values.
- Es gibt kein `@Attribute(.unique)`; die Lösung bleibt mit der bestehenden SwiftData-/CloudKit-Persistenz kompatibel.

### 4.4 Bootstrap und Legacy-Reparatur

Pfade:

- `BrainMesh/AppRoot/AppRootView+Startup.swift`
- `BrainMesh/Bootstrap/GraphBootstrap+Detection.swift`
- `BrainMesh/Bootstrap/GraphBootstrap+Repair.swift`
- `BrainMesh/Bootstrap/GraphBootstrap+Backfill.swift`
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`

Startup:

- wartet auf Loader-Konfiguration;
- stellt mindestens einen Graphen sicher;
- migriert Legacy-Scopes für Entity, Attribute, Link, Template, Detail Field Definition und Detail Field Value;
- klassifiziert Detailrecords vor der ersten Mutation owner-basiert, repariert eindeutige skalare Owner-IDs, bereinigt nur sichere Duplikate und markiert betroffene Graphen für Full Rebuild;
- lässt Cross-Graph-, verwaiste und mehrdeutige Detailrecords unverändert, statt sie dem Default-Graphen zuzuordnen;
- füllt gefaltete Notes-Felder;
- startet begrenzte Bildhydration;
- reconciled den Suchindex.

Attachment-Sonderfall:

- `AttachmentGraphIDMigration` repariert nur Attachments eines konkreten Owners.
- Aufrufe erfolgen u. a. beim Media-All-Load und in Gallery-Aktionen.
- Vorteil: kleine, owner-lokale Reparatur statt globaler Startblockade.
- Risiko: ungeöffnete Owner können länger Legacy-Records ohne Scope behalten.

**UNKNOWN U11**: Ob graphweite Export-, Delete-, Stats- und Backup-Pfade ungeöffnete Legacy-Attachments vollständig erfassen.

Refactor-Hebel:

- Einmalige, versionierte Attachment-Scope-Reconciliation als backgroundfähigen, paginierten Job ergänzen.
- Jobfortschritt pro Migration-Version persistieren.
- Owner-lokale Reparatur als Defensive Fallback behalten.
- Vollständigkeit mit orphaned/missing-owner Fixtures testen.

### 4.5 Mutation Boundary

Pfade:

- `BrainMesh/DataAccess/Mutations/GraphMutationCommitter.swift`
- `BrainMesh/DataAccess/Mutations/GraphMutationEventBus.swift`
- `BrainMeshTests/GraphMutationWritePathInventoryTests.swift`

Stärken:

- Save erfolgt vor Eventpublikation.
- Save-Fehler rollt den Kontext zurück.
- Cancellation unmittelbar vor Save wird respektiert.
- Nach erfolgreichem Save wird das Invalidierungsereignis publiziert.
- Batches enthalten keine Nutzinhalte.
- Ein Testinventar klassifiziert bekannte produktive Schreibpfade.

Bewusste Ausnahmen:

- rekonstruierbares `imagePath`;
- Security-Metadaten;
- lokale Canvas-Presets;
- Import-Checkpoint-Saves mit finalem Full-Rebuild-Event.

Risiken:

- Die Vollständigkeit des Inventars ist manuell.
- Ein neuer direkter `context.save()` kompiliert ohne Mutation Event.
- Der Event Bus ist in-memory; Prozessabbruch zwischen Save und Event kann den Event verlieren.
- CloudKit-Imports erzeugen keine lokalen Events.

Gegenmaßnahmen:

- Reconciliation bleibt die letzte Konsistenzinstanz.
- CI-Scan für `save()`-Aufrufe außerhalb erlaubter Dateien.
- Persistente graphweite `mutationRevision` oder Source-Manifest-Version prüfen.
- Bei Appstart einen billigen Manifest-Header-Vergleich vor vollständigem Reconcile nutzen.

### 4.6 Search Index

Pfade:

- `BrainMesh/Search/Index/GraphSearchIndexStore+Schema.swift`
- `BrainMesh/Search/Index/GraphSearchIndexStore+Operations.swift`
- `BrainMesh/Search/Index/GraphSearchIndexer.swift`
- `BrainMesh/Search/Index/GraphSearchIndexReconciler.swift`
- `BrainMesh/Search/Index/GraphSearchDocumentBuilder.swift`
- `BrainMesh/DataAccess/GraphReadRepository.swift`

Speicher:

- SQLite unter `Application Support/BrainMesh/Search/Index/GraphSearchIndex.sqlite`.
- WAL, Foreign Keys, Busy Timeout, `synchronous=NORMAL`.
- Indexverzeichnis ist vom Geräte-Backup ausgeschlossen.
- Schema-/Integritätsfehler lösen Rebuild aus.
- FTS5 wird genutzt, wenn verfügbar; sonst indexed fallback.

Eventpfad:

1. Fachlicher Save wird committed.
2. Mutation Batch wird in `GraphMutationEventBus` publiziert.
3. `GraphSearchIndexer` plant präzise Mutation oder Full Rebuild.
4. Source-Dokumente und Manifeste werden atomar aktualisiert.
5. Sequenzlücke führt zu Rebuild.

Remote-Pfad:

1. CloudKit importiert SwiftData-Daten.
2. Kein lokaler Mutation Batch entsteht.
3. `GraphSearchIndexReconciler` erzeugt Source-Snapshot und Manifestvergleich.
4. Viele Änderungen führen zu Full Rebuild; wenige zu atomarem Reconcile.

Hotspot-Grund:

- `GraphReadRepository` lädt graphweit Entities, Attributes, Links, Definitions, Values und Attachment-Metadaten.
- Für Detailwerte gruppiert das Repository nach dem zentralen Authority-Key und erzeugt nur bei konfliktfreier Authority ein DTO; dadurch verwenden Search Index und Graph Chat dieselbe Faktengrundlage wie die Detail-UI.
- Der Indexer baut Dokumente/Manifeste als komplette Collections und sortiert sie.
- `sourceBatchSize` steuert Yield/Progress, streamt aber nicht den Source-Snapshot durch SQLite.
- Dadurch steigen Peak Memory und Latenz mit der gesamten Graphgröße.

Refactor:

- Staging-Tabellen pro Rebuild verwenden.
- Sources paginiert laden.
- Dokumente chunkweise bauen und in einer Staging-Transaktion schreiben.
- Manifest-Root/Generation erst nach erfolgreichem Abschluss atomar umschalten.
- Abbruch verwirft Staging-Generation.

### 4.7 Medien

Headerbilder:

- `BrainMesh/ImageStore.swift` hält `NSCache` mit `countLimit = 120`.
- Diskpfad: `Application Support/BrainMeshImages`.
- Async Load de-dupliziert In-flight-Requests und lädt off-main.
- `BrainMesh/ImageHydrator.swift` scannt Entities und Attributes mit `imageData != nil`.
- Hydration ist pro Launch begrenzt und über einen Limiter serialisiert.

Attachments:

- `MetaAttachment.fileData` nutzt SwiftData External Storage.
- `BrainMesh/Attachments/AttachmentStore.swift` hält Previewdateien im Application Support.
- `BrainMesh/Attachments/AttachmentHydrator.swift` materialisiert bei Bedarf.
- `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift` lädt Count plus kleine Previewsets off-main.
- Media-All besitzt Paging.

Risiken:

- Image-Hydration fetcht alle Records mit Bilddaten in zwei unpaginierten Arrays.
- In den Recordschleifen fehlen explizite Cancellation-Checks.
- Fehler werden weitgehend ignoriert; der Nutzer sieht nur indirekt fehlende Caches.
- Bild- und Attachment-Cacheverzeichnisse setzen keine `isExcludedFromBackup`.
- External Storage plus CloudKit kann bei großen Dateien Sync-Latenz und Quota belasten.

**UNKNOWN U9**: Ob Cachedateien absichtlich Teil des Gerätebackups sind.

**UNKNOWN U7**: Reale maximale Attachmentanzahl, Einzeldateigröße und CloudKit-Transferbudgets.

## 5. Entry Points und Navigation

### 5.1 App Entry

`BrainMesh/BrainMeshApp.swift`:

- `@main` App-Struct;
- ModelContainer;
- Appearance/Display/Onboarding/Security/Pro/Router/Chat-Coordinators;
- iCloud-Accountstatus-Refresh;
- Loader-Konfiguration.

Architekturhinweis:

- Die Composition Root ist klar sichtbar.
- Gleichzeitig entstehen viele globale `StateObject`-Abhängigkeiten.
- Ein neuer globaler Coordinator erweitert App-Init, Environment und Root-Tests.

Refactor-Option:

- `AppEnvironment` in fachliche Gruppen teilen:
  - `AppNavigationEnvironment`;
  - `AppSecurityEnvironment`;
  - `AppChatEnvironment`;
  - `AppPersistenceEnvironment`.
- SwiftUI-Environment-Einträge gezielt pro Subtree injizieren.

### 5.2 Root Lifecycle

`BrainMesh/AppRoot/AppRootView.swift` und `BrainMesh/AppRoot/AppRootView+Startup.swift`:

- Startup Task;
- aktive Graphänderung;
- Scene-Phase;
- Entitlementänderung;
- Onboarding Sheet;
- Unlock Full-screen Cover.

Risiko:

- Startup, Locking, Hydration und Search-Reconcile teilen Root-Lebensdauer.
- Reihenfolgefehler können sensible Chatdaten, graphfremde Navigation oder veralteten Index sichtbar lassen.

Schutz:

- Chat-sensitive State wird bei Background/Lock verworfen.
- Lock besitzt Debounce und Graph-Picker-Grace.
- Startup wartet auf konfigurierte Loader.

Empfehlung:

- Root-Lifecycle als explizite `AppLifecycleCoordinator`-State Machine testen:
  - launching;
  - awaitingServices;
  - bootstrapping;
  - ready;
  - backgroundLocked;
  - graphSwitching.

### 5.3 Tab- und Stack-Struktur

`BrainMesh/ContentView.swift`:

- Root `TabView` mit `RootTabRouter`.
- Tabs: Entities, Graph, Chat, Stats, Settings.
- Jeder große Featurebereich besitzt seinen eigenen `NavigationStack` oder wird in einen gesetzt.
- Command Center ist global.

Navigationseigentum:

| Flow | Owner |
|---|---|
| Tabwechsel | `RootTabRouter` |
| Global Search/Command Center | `CommandCenterCoordinator` |
| Entity Home Routes | `EntitiesHomeRoutingCoordinator` |
| Graph-Jump/Fokus | `GraphJumpCoordinator` |
| Graph Chat Launch | `GraphChatLaunchCoordinator` |
| Graph Copilot Inspector | `GraphCopilotWorkspaceCoordinator` |
| Lock/Unlock | `GraphLockCoordinator` |
| Systemmodale Zustände | `SystemModalCoordinator` |

Risiko:

- Ein Use Case kann Tabrouter, Feature-Coordinator und Sheet-State gleichzeitig berühren.
- Stale Route nach Graphwechsel ist ohne graphgescopten Routetyp möglich.

Empfehlung:

- Jede Route trägt `graphID`.
- Coordinator APIs liefern eine vollständige Navigation-Intent-Struktur.
- Graphwechsel invalidiert alle featurelokalen Pfade atomar.
- Navigationstests decken Graphwechsel bei offenem Detail/Sheet ab.

### 5.4 Wichtige Sheets und Flows

- App Root:
  - Onboarding;
  - Graph Unlock.
- Entities:
  - Graph Picker;
  - Add Entity;
  - Display Settings;
  - Entity-/Attribute-Details.
- Graph:
  - Graph Picker;
  - Focus Node Picker;
  - Inspector;
  - Entity-/Attribute-Detail;
  - Details-Editor;
  - Result Set;
  - iPad Copilot Inspector.
- Chat:
  - Free Preview;
  - Paywall;
  - Tool-/Index-Verfügbarkeitsstatus.
- Stats:
  - Health Issue Detail.
- Settings:
  - Display;
  - Pro;
  - Transfer;
  - Sync/Wartung;
  - Guide/Support;
  - Import Settings.

## 6. Hot Path Analyse

## 6.1 Rendering und Scrolling

### P0/P1: Graph Canvas Physics

Pfade:

- `BrainMesh/GraphCanvas/Physics/GraphPhysicsRuntime.swift`
- `BrainMesh/GraphCanvas/Physics/GraphPhysicsWorkspace.swift`
- `BrainMesh/GraphCanvas/GraphCanvasDynamicFrameBuilder.swift`
- `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`

Konkreter Grund:

- `GraphPhysicsRuntime` ist `@MainActor`.
- Ein `Timer` taktet adaptiv mit 30/20/12 FPS.
- Physics-Step, Maximum-Delta-Scan und Publish-Koordination liegen im Main-Actor-Runtimepfad.
- Publish kopiert vollständige Positions- und Velocity-Dictionaries.
- Der Commit aktualisiert beide Dictionaries in einer Main-Actor-Transaktion.
- Der Dynamic Frame Builder iteriert Nodes und Edges und baut Screen-Point-Dictionaries neu.
- Jede veröffentlichte Physics-Änderung kann die SwiftUI-/Canvas-Darstellung invalidieren.

Vorhandene Begrenzung:

- Global Load: maximal 140 Nodes und 800 Links.
- Adaptive Cadence.
- Sleep bei stabiler Simulation.
- Publish-Epsilon und maximale Ticks ohne Commit.
- statische Renderdaten werden separat gecacht.
- Minimap-Snapshot ist gedrosselt.

Bewertung:

- Kein ungebremster Graph-Render.
- Trotzdem ist der MainActor bei aktiver Simulation der dominante Frame-Budget-Kandidat.
- Instruments muss Tickzeit, Dictionary-Allokationen und Canvas-Body getrennt messen.

Optimierungshebel:

- Physics-Step in einen Actor/Worker mit Value-Workspace verlagern.
- Nur coalesced Positions-Snapshots zum MainActor publizieren.
- Velocities nur publizieren, wenn UI/Interaktion sie wirklich benötigt.
- Stable Node Index statt Dictionary-Rebuild im inneren Loop evaluieren.
- `ContinuousClock`/display-synchronen Scheduler gegen `Timer` benchmarken.
- Bestehende Caps als Produktinvariante dokumentieren und testen.

Risiko des Refactors:

- Hoch: Dragging, Wake/Sleep, Fokus und externe Positionsänderungen sind zeitkritisch.
- Vorher Golden-/Determinismus-Tests und Frame-Signposts ausbauen.

### P1: Entities Home

Pfade:

- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Body.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Loading.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Counts.swift`
- `BrainMesh/Mainscreen/EntitiesHome/Cockpit/EntitiesHomeHealthSummaryProvider.swift`

Konkreter Grund:

- Leere Suche lädt alle Entities des aktiven Graphen ohne Paging.
- Count Cache Miss lädt Attributes und Links und aggregiert im Speicher.
- Health Cache Miss lädt Entities, Attributes, Links, Fields und Attachment-Metadaten.
- Query ist zwar 250 ms debounced, breite Indexresultate können aber auf SwiftData-Fallback wechseln.
- Maximal 500 Indexdokumente werden zurückgegeben; unvollständige Treffer können mehrere SwiftData-Contains-Fetches auslösen.

Vorhandener Schutz:

- Search Debounce.
- Actor-/Background-Loader.
- Count-TTL und Mutation-Invalidierung.
- Lazy SwiftUI-Container.
- separate Recent-/Health-Komponenten.

Optimierungshebel:

- Cursor-/Offset-Paging für leere Suche.
- Zentrale `GraphHomeSnapshot`-Berechnung statt unabhängiger Vollfetches.
- Incremental Aggregate Cache aus Mutation Batches.
- Begrenzte initiale Health-Zusammenfassung, Details erst on demand.
- UI-State nach graphgescopter Revision identifizieren.

### P2: Detail- und Medienlisten

Pfade:

- `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`
- `BrainMesh/Mainscreen/NodeDetailShared/NodeConnectionsLoader.swift`
- `BrainMesh/Attachments/MediaAllLoader.swift`
- `BrainMesh/PhotoGallery/`

Beobachtung:

- Preview-Loader sind fetch-limitiert und materialisieren kleine Sets.
- Media-All ist paginiert.
- Connection Preview ist limitiert.

Resthotspots:

- Thumbnail-/Video-Metadaten können bei schnellem Scroll viele Tasks erzeugen.
- Cache Miss materialisiert External-Storage-Daten.
- Full Gallery und große Attachments benötigen Device-Profiling.

Maßnahmen:

- sichtbarkeitsgebundene Cancellation für Thumbnail-/Duration-Tasks;
- NSCache-Cost-Limits statt nur Count;
- Dekompression/Thumbnailgröße an tatsächliche Zellgröße koppeln;
- Prefetch-Fenster begrenzen.

## 6.2 Sync und Storage

### CloudKit-Containerstart

Hotspot-Grund:

- Containererstellung liegt synchron im App-`init`.
- Debug stoppt hart; Release wechselt Storemodus.
- Der Modus beeinflusst die gesamte Datenwahrheit der Session.

Maßnahmen:

- Startdauer signposten.
- Store-URL, Modus und Fehlerklasse content-free loggen.
- UI für local-only als Recovery-Zustand, nicht nur Statuslabel.

### Foreground Search Reconciliation

Hotspot-Grund:

- Alle 15 Minuten bzw. on demand kann ein graphweiter Source-Snapshot entstehen.
- Selbst bei unverändertem Graphen werden Daten gelesen und Manifeste berechnet.
- Viele Änderungen führen ab `max(128, sourceCount / 2)` zum Full Rebuild.

Maßnahmen:

- persistente graphweite Source-Revision;
- billiger Headervergleich vor Source-Materialisierung;
- paginiertes Hashing;
- adaptive Reconciliation abhängig von letzter CloudKit-Importzeit;
- Work bei Background/Low Power verschieben oder abbrechen.

### Image Hydration

Hotspot-Grund:

- zwei Vollfetches für alle Entity-/Attribute-Bilddaten;
- potenziell große Binary-Felder;
- keine Pagination/Cancellation in Recordschleifen;
- direkte `context.save()`-Ausnahme für `imagePath`.

Maßnahmen:

- nur IDs/Pfade selektieren, soweit SwiftData dies effizient ermöglicht;
- Batches mit `fetchLimit`/Offset;
- `Task.checkCancellation()` je Batch;
- Fortschritt und Fehleranzahl loggen;
- `imagePath` langfristig vollständig aus dem synchronisierten Modell lösen.

### Transfer Import/Export

Pfade:

- `BrainMesh/GraphTransfer/GraphTransferService/`
- `BrainMesh/GraphTransfer/Backup/`
- `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferImportCoordinator+Cleanup.swift`

Hotspot-Grund:

- Vollbackup verarbeitet Binärdaten und Prüfsummen.
- Import remappt mehrere ID-Tabellen.
- Checkpoint-Saves alle 500 Datensätze erzeugen einen partiell persistenten Zustand.
- Fehler-Cleanup muss jeden bereits gespeicherten Typ und lokale Caches entfernen.

Vorhandener Schutz:

- Manifest-/SHA-256-Prüfung;
- temp package;
- ID-Remapping;
- Cancellation/Yield-Strides;
- Cleanup bei Fehler;
- finaler Full-Rebuild-Event.

Maßnahmen:

- Operation-ID über Export, Import, Save und Cleanup propagieren.
- Vorab-Disk-Space- und Paketgrößenprüfung.
- Import-State persistent markieren, damit Crash-Recovery beim nächsten Start möglich ist.
- Fault-Injection-Tests nach jedem Checkpoint.

## 6.3 Concurrency

### Default MainActor Isolation

Projektsetting:

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- Actor-Loader erstellen kurzlebige `ModelContext`-Instanzen.
- DTOs sind häufig `Sendable`.
- `AnyModelContainer` ist `@unchecked Sendable`.

Stärke:

- UI-/Modelzugriffe sind standardmäßig konservativ.
- Backgroundarbeit ist meist explizit.

Risiko:

- Neue Helper erben MainActor unbemerkt.
- `Task.detached` plus `@unchecked Sendable` kann Modelobjekte versehentlich über Grenzen tragen.
- Laufzeitkosten landen leicht wieder auf dem MainActor.

Regel:

- Über Actor-Grenzen nur IDs, primitive Werte und explizite DTOs.
- `ModelContext` dort erzeugen, wo er benutzt wird.
- Persistente Modelinstanzen nicht zurück aus Detached Tasks geben.

### Mutation Event Bus

Konkreter Grund:

- Prozesslokale AsyncStreams sind standardmäßig unbounded.
- Langsame Consumer können Backlog und Speicherwachstum verursachen.
- Ein Prozessabbruch verliert nicht konsumierte Events.

Option:

- Bounded Buffer mit explizitem Overflow-Signal.
- Overflow bedeutet nicht „Event still verwerfen“, sondern „Graph invalidieren und Full Rebuild anfordern“.
- Consumer-Ack ist nicht nötig, wenn Reconciliation die dauerhafte Wahrheit bleibt.

### Graph Chat Tasks

Pfade:

- `BrainMesh/GraphChat/UI/GraphChatViewModel.swift`
- `BrainMesh/GraphChat/UI/GraphChatGenerationController.swift`
- `BrainMesh/GraphChat/UI/GraphChatMessageActionController.swift`
- `BrainMesh/GraphChat/Provider/FoundationModelsGraphChatProvider.swift`

Konkreter Grund:

- Streaming, Provider Session, Tools, Conversation State, Edit/Retry und Feedback haben getrennte Lifetimes.
- Cancellation muss Provider, Stream und UI-State in definierter Reihenfolge stoppen.
- Scope-/Lock-/Entitlement-Wechsel invalidieren sensible Sessiondaten.
- Provider-Cancellation nutzt bewusst einen separaten Task, um vor Streamende anzukommen.

Risiko:

- Doppelte Completion;
- alte Generation überschreibt neue UI;
- Session-Ressourcen bleiben nach Scopewechsel;
- Feedback verweist auf ersetzte Nachricht;
- Lock löscht nicht alle abgeleiteten Artefakte.

Maßnahmen:

- Generation durch `GenerationID`/State Machine serialisieren.
- Jede Callback-Publikation prüft aktuelle Generation und Graph Scope.
- Structured Concurrency bevorzugen; unstrukturierte Tasks in einem Registry-Typ besitzen.
- Race-Tests für cancel/edit/regenerate/lock/graph-switch.

### Graph Chat Foundational Intent Compiler

Pfade:

- `BrainMesh/GraphChat/Foundational/GraphChatFoundationalIntent.swift`
- `BrainMesh/GraphChat/Foundational/GraphChatFoundationalIntentCompiler.swift`
- `BrainMesh/GraphChat/Foundational/GraphChatFoundationalIntentCoordinator.swift`
- `BrainMesh/GraphChat/Foundational/GraphChatFoundationalIntentExecutor.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatRequestPipeline.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatAnswerFinalizer.swift`

Trust Boundary:

- Der Compiler läuft nach `GraphChatRequestPreflight`, also erst nach Validierung von aktivem Graph und Chat-Scope, und erhält einen vollständigen appseitigen `GraphSchemaContext`.
- `GraphSchemaContext.foundationalAliases` hält dafür den vollständigen graph-gescopten App-Katalog getrennt von der weiterhin begrenzten providerseitigen Alias-/Prompt-Sicht. Nicht erkannte Fragen verändern dadurch weder akzeptierte Provider-Aliase noch den bestehenden Promptvertrag.
- Er läuft vor semantischer Interpretation, Provider-Session-Erzeugung, freier Provider-Generierung und modellbestimmter Tool-Auswahl. `.compiled` und `.clarification` bleiben vollständig lokal; ausschließlich `.notRecognized` erreicht den nachgelagerten Semantic Coordinator. Scope-, Schema- oder Clarification-Integritätsverletzungen sind harte Ablehnungen.
- Entity-, Feld- und Node-Identitäten stammen ausschließlich aus graph-gescopten Schema-/Repository-Daten. Provider-Aliase oder modellgenerierte IDs sind keine Eingabe des Compilers.

Unterstützte Intents:

- `singleNodeFieldValue`: sichere deutsche oder englische Fragehülle sowie ein durch den zentralen Mention Resolver gebundener Attribute-Anzeigename und ein gebundenes Feld derselben Entity. Nach Entfernen der beiden fachlichen Spannen dürfen nur die ausdrücklich unterstützten Hüllenwörter verbleiben.
- `entityAttributeCollection`: sichere deutsche oder englische Listenhülle und eine durch den zentralen Mention Resolver eindeutig gebundene Entity. Filter, Aggregationen, freie Semantik und analytische Zusätze werden nicht kompiliert.
- `nodeDetails`: sichere deutsche oder englische Detailhülle und genau ein eindeutig gebundener, im bestehenden Chat-Scope autorisierter Node. Der Adapter erzeugt die vorhandene Typed-Intent-Payload `.nodeDetails` und die vorhandene lokale `GetNodeTool`-Action; deren Ergebnis wird durch denselben generischen `.nodeProfile`-Artifact- und Finalizerpfad präsentiert wie semantisch kompilierte Node Details.
- Der Single-Field-Plan projiziert Node Identity und exakt das validierte Feld, bindet den Scope auf genau den validierten Node und setzt `limit = 1`.
- Der Collection-Plan projiziert Node Identity, verwendet keine erfundenen Filter, sortiert stabil nach Node-Anzeigename mit dem bestehenden deterministischen Tie-Breaker und setzt das Limit auf `GraphQueryPlanLimits.maximumResultLimit`.
- Der Node-Details-Plan bindet den Query-Scope auf genau den validierten Node und verwendet den appseitigen kompatiblen Per-Bereich-Cap, aus dem die zentrale Policy vier unabhängige Profilgrenzen ableitet. Alle drei Foundational-Familien laufen über den bestehenden Typed-Intent- und Local-Kernel-Lifecycle.

Ausführung und Fortsetzung:

- Jeder kompilierte Plan durchläuft erneut `GraphQueryPlanValidator`, `GraphChatScopeAuthorization`, `GraphChatQueryEngine`, die zentrale Detaildaten-Authority, Evidence-Registrierung, Artifact-Staging, Primary-Result-Ledger, Live-Revalidation, Presentation Firewall und atomaren Conversation-/Artifact-Commit. Collections verwenden weiterhin den deterministischen Fallback; Single-Field-Erfolge verwenden den strengeren Authoritative-Fact-Renderer.
- Der Foundational-Pfad hängt nicht von der Readiness des Search-Indexes ab und verwendet `SearchGraph` auch bei einem Single-Field-Intent nicht als Wertquelle. Nicht erkannte Fragen durchlaufen anschließend die begrenzte semantische Find-/List-Stufe; nur deren explizite Open-Ended-/Unrecognized-Fälle behalten die vorhandene Provider-, Search- und Repository-Fallback-Architektur.
- Ein Single-Field-Erfolg verlangt den tatsächlich transportierten, typisierten Feldwert. Fehlender oder aufgrund eines Detaildaten-Integritätskonflikts nicht autoritativer Wert wird zu einem typisierten No-Results-Pfad; ein `SearchGraph`-Treffer kann diesen Pfad nicht abschließen.
- Mehrdeutige Entities, Nodes oder Felder verwenden die bestehende `GraphChatPendingClarification`. Kandidatenauswahlen bleiben intern graph-, chat-, conversation-, request- und turngebunden, werden vor der Fortsetzung erneut validiert und lösen bis zur Auswahl keine Query aus.
- Lokal kompilierte Resultsets werden über denselben Conversation Reducer gespeichert und sind damit für die bestehende typisierte `CURRENT`-Auflösung verfügbar. Cancellation vor Commit verwirft Evidence, Ledger und gestagte Artifacts; der Stream behält genau ein Terminal Event.

Limit-Policy:

- `GraphQueryPlanLimits.maximumResultLimit` ist die einzige Quelle für vollständige Foundational Collections. „Alle“ bleibt auf den autorisierten Chat-Scope und dieses Sicherheitslimit begrenzt.
- `GraphChatResultWindow` transportiert `totalCount`, `returnedCount`, Limitquelle und Truncation. Das Result-Artefakt übernimmt diese Metadaten; der deterministische deutsche oder englische Fallback nennt eine erreichte Begrenzung sichtbar.
- Collection-Artefakte vermeiden innerhalb des bestehenden Artifact-Bytebudgets redundante globale Evidence-Bindings und behalten pro Zeile einen sicheren Navigation Target. Das vollständige revalidierte Evidence-Set bleibt im Primary Result und finalen Answer gebunden.

### Graph Chat Core Grounding (GRAPH-CHAT-CORE-GROUNDING-1)

Pfade:

- `BrainMesh/GraphChat/Grounding/GraphMentionResolver.swift`
- `BrainMesh/GraphChat/Grounding/GraphMentionShellExtractor.swift`
- `BrainMesh/GraphChat/Grounding/GraphMentionLexiconResource.swift`
- `BrainMesh/GraphChat/Grounding/GraphMentionAliases.json`
- `BrainMesh/GraphChat/Foundational/GraphChatFoundationalIntentCompiler.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatSemanticIntentResolver.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatQueryIntentCompiler.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatAdvancedIntentCompiler.swift`
- `BrainMesh/GraphChat/Interpretation/GraphChatInterpretationCorrectionCompiler.swift`

Resolver-Vertrag:

- `GraphMentionResolver` und seine expliziten Input-, Candidate-, Catalog-, Constraint-, Resolution-, Alternative-, Quality- und Failure-Typen sind value-only, `Hashable` und `Sendable`; Resolver-Version und Alias-Katalog besitzen jeweils die Version `1`.
- Ein `GraphMentionCatalog` entsteht ausschließlich aus `GraphSchemaContext.foundationalAliases`. Katalog und jeder Kandidat tragen den Graph-Scope; ein abweichender Katalog-, Kandidaten- oder Chat-Scope wird vor jeder Textauflösung geschlossen abgelehnt. Die promptseitigen `aliases`, `maximumEntities` und `maximumFieldsPerEntity` sind keine Grounding-Grenze.
- Die feste Stufenfolge ist: getrimmtes exaktes Display-/Alias-Matching; Unicode-kanonisches, case-insensitives und interpunktionsbereinigtes Matching; ä/ö/ü/ß-äquivalente Schreibweise; begrenzte deutsche beziehungsweise englische Singular-/Plural-/Flexionswurzel; konservative Levenshtein-Abweichung. Fuzzy Binding verlangt Mindestlänge, längenabhängige Maximaldistanz, höchstens 18 Prozent Abweichung und mindestens zwei Edit-Schritte Abstand zum zweitbesten Kandidaten.
- Die erste nicht leere Stufe gewinnt. Mehrere Kandidaten derselben besten Stufe oder ein zu kleiner Fuzzy-Abstand liefern ausschließlich eine fachliche Clarification; schwächere Stufen dürfen eine stärkere Mehrdeutigkeit nicht überstimmen. Candidate- und Clarification-Reihenfolge besitzen stabile fachliche beziehungsweise technische Tie-Breaker.
- Chat-Scope, Entity-Owner, ausgewählte Entity/Nodes/Felder und revalidierter Conversation-Kontext dürfen die Kandidatenmenge nur verkleinern. Ein Treffer außerhalb dieser Menge wird als Scope-, Owner- oder stale-Selection-Verletzung klassifiziert und niemals als Cross-Graph-Zugriff zugelassen.
- App-owned Aliasse und lokalisierte Feldsynonyme sind versionierte Daten in `GraphMentionAliases.json`. Der generische Loader erweitert passende Displayphrasen aus diesen Gruppen; Resolver und sprachliche Fast-Path-Hüllen enthalten keine Entity-, Node-, Feld- oder Linknamen.

Integration und Diagnose:

- Foundational Single Field, Entity Collection und Node Details, semantische Find-/Query-/Advanced-Bindings sowie die über den Semantic Resolver erneut kompilierten Interpretation Corrections verwenden dieselbe Resolver-Instanzarchitektur. Es existiert kein paralleler Exact-Match-Resolver.
- Die providerfreien Basishüllen erkennen in Deutsch und Englisch ausschließlich Listen einer genannten Entity beziehungsweise vollständige Details eines genannten Nodes. Die extrahierte fachliche Spanne wird an den Resolver übergeben; erfolgreiche Ausführung bleibt im bestehenden Typed-Intent-, Local-Kernel-, Evidence-, Artifact-, Finalizer-, Presentation- und atomaren Commit-Lifecycle.
- Gewöhnliche Binding-Fehler verwenden `GraphChatErrorCode.groundingFailure` plus eine content-free `GraphChatBindingDiagnosticReason`: `entityNotBound`, `nodeNotBound`, `fieldNotBound`, `multiplePlausibleCandidates` oder `invalidDraftCombination`. Observability loggt nur diese Enum-Kategorie. Echte Mehrdeutigkeit erzeugt weiterhin eine request-/turn-/conversation-/graph-/scopegebundene Pending Clarification.
- Scope-Verletzungen, stale oder manipulierte Selections, technische Identifier, Schema-/Draft-Vertragsverletzungen außerhalb einer gewöhnlichen ungültigen Kombination und Cross-Graph-Mismatches bleiben geschlossene Fehler. Sie öffnen weder Legacy-Provider noch Bounded Tool Repair.
- Die bestehende Typed-Intent-Domainversion bleibt `v1`; `ResolutionSource`, `ResolutionOrigin` und `ResolutionQuality` wurden nicht erweitert. Exaktes beziehungsweise kanonisches Display-Matching bleibt `.exact`; App-Alias, Umlaut-/Flexionsvariante und konservativer Tippfehler werden bewusst auf `.constrainedSynonym` abgebildet, Clarification-/Conversation-Revalidation auf die bestehenden Qualitätsfälle.

Bewusste Grenze:

- Nicht hinzugekommen sind Relationship-Intent, Multi-Hop-Traversal, `GraphFactBundle` oder modellgestützte Grounded-Answer-Planung. Graph Chat bleibt read-only.

### Graph Chat Node Profile Domain (GRAPH-CHAT-NODE-PROFILE-DOMAIN-1)

Pfade:

- `BrainMesh/DataAccess/GraphNodeProfile.swift`
- `BrainMesh/DataAccess/GraphReadRepository+NodeProfile.swift`
- `BrainMesh/GraphChat/Tools/GetNodeTool.swift`
- `BrainMesh/GraphChat/Core/GraphSourceReference.swift`
- `BrainMesh/GraphChat/Evidence/GraphEvidence.swift`
- `BrainMesh/GraphChat/Evidence/GraphEvidenceValidator.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatIntentLimitPolicy.swift`

Read-Vertrag und Authority:

- `GraphNodeProfileReading` akzeptiert ausschließlich `GraphScope`, `NodeRefKey` und appseitige `GraphNodeProfileLimits`. Die produktive `GraphReadRepository`-Implementierung erzeugt einen eigenen read-only `ModelContext`; kein SwiftData-Modell verlässt diesen Context.
- `GraphNodeProfile` und alle enthaltenen Owner-, Field-, Endpoint-, Connection-, Window- und Limitwerte sind value-only, `Hashable` und `Sendable`. Entity und Attribute tragen eigenen sichtbaren Namen und qualifizierten Anzeigenamen; Attributes führen ihren aktuell graphgescopten Owner separat.
- Detailwerte werden ausnahmslos über `fetchDetailValueAuthority` und damit die bestehende `DetailDataIntegrityPolicy` geladen. Cross-Graph-, verwaiste, typwidrige und konfliktbehaftete Records liefern keinen Profilfakt. Die stabile Reihenfolge folgt Feld-`sortIndex`, normalisiertem Feldnamen, Feld-ID und Value-ID.
- Links werden getrennt nach incoming und outgoing geladen. Nur Links mit beiden im aktuellen Graphen auflösbaren Endpunkten gelangen in das Profil. Jeder Eintrag trägt Link-ID, Created-At-Tie-Breaker, Richtung, Quell- und Zielendpoint, Gegenknoten, Owner-Anzeige und den exakten optionalen Notizwert. Sortierung ist Created-At absteigend, danach Link-ID und Endpoint-Tie-Breaker.
- Attachments verwenden ausschließlich `GraphAttachmentMetadataDTO`. `fileData`, `localPath`, Previewdaten und Dateiinhalte werden weder gelesen noch in Profil, Evidence oder Conversation State transportiert.

Unabhängige Limits und Adapter:

- `GraphChatIntentLimitPolicy` besitzt vier getrennte Profilgrenzen für autoritative Detailwerte, eingehende Verbindungen, ausgehende Verbindungen und Attachments. Der Repository-Eingang lehnt Werte oberhalb dieser zentralen Policy ab.
- Jeder Bereich besitzt ein eigenes `GraphNodeProfileResultWindow` mit exaktem `totalCount`, `returnedCount`, `limit`, `limitReached` und der Limitquelle `.appPolicy`. Ein großer Bereich kann keinen anderen verdrängen; kleine Bereiche innerhalb ihrer Grenze sind vollständig.
- Der bestehende `GetNodeInput.relatedLimit` bleibt nur als kompatibler appseitiger Per-Bereich-Cap erhalten. Der echte Foundation-Models-Toolvertrag exponiert kein Limit mehr, und der Legacy-Tool-Runtime ersetzt alte modellseitige Werte durch `GraphChatIntentLimitPolicy.nodeDetailRelatedItemCount`.
- Das unveränderte Tool-Call-Budget zählt das bounded Profil als ein Root-Ergebnis. Die Bereichsgrößen werden ausschließlich durch die vier Profilgrenzen beschränkt; das bestehende Evidence-Budget bleibt eine zusätzliche unabhängige Sicherheitsgrenze.
- `GetNodeOutput` erhält sichtbaren und qualifizierten Namen, separate Notiz-Evidence sowie getrennte Detail-, Incoming-, Outgoing- und Attachment-Windows. Counts stammen vom vollständigen Profil; sichtbare Items und Evidence stammen aus demselben Profil-Snapshot. Die Artifact Factory projiziert diesen Output verlustfrei in `.nodeProfile`; es existiert keine zweite Node-Details-Datenautorität.

Link-Notiz-Evidence:

- `GraphSourceLinkBinding` bindet Graph Source Reference und Evidence an Link-ID, Quellnode, Zielnode, Richtung relativ zum beschriebenen Node und den exakt verwendeten optionalen Notizwert. Diese Werte fließen in die stabile Evidence-ID ein.
- `GraphEvidenceSourceValidator` löst den Link erneut im aktuellen Graphen auf, verlangt beide aktuellen Endpunkte und vergleicht die vollständige Binding-Struktur sowie den Notizwert. Änderung, Entfernung oder Löschen der Notiz beziehungsweise des Links invalidieren die alte Evidence; ein Link ohne Notiz kann keinen früheren Text belegen.
- Gleichlautende Link-IDs in anderen Graphen werden weiterhin durch Graph-Scope und die vollständige Binding-Revalidation abgelehnt. `GetNodeTool`, `GetNeighborsTool` und Link-Suchergebnisse erzeugen die neue Produktionsbindung.

Lifecycle:

- Cancellation wird vor und zwischen Identität, Detailauthority, outgoing Links, incoming Links, Endpointauflösung, Attachments und finaler Profilpublikation geprüft. Ein Abbruch liefert kein Teilprofil.
- Der bestehende Local-Intent-Kernel, Evidence-/Artifact-Commit, Ledger, Presentation Firewall, Conversation-Compare-and-set und Single-Terminal-Vertrag bleiben unverändert maßgeblich.

### Graph Chat Node Profile Presentation (GRAPH-CHAT-NODE-PROFILE-PRESENTATION-1)

Pfade:

- `BrainMesh/GraphChat/Artifacts/GraphChatNodeProfileAnswerArtifact.swift`
- `BrainMesh/GraphChat/Artifacts/GraphChatNodeProfilePresentation.swift`
- `BrainMesh/GraphChat/Artifacts/GraphChatAnswerArtifactFactory+NodeNeighbors.swift`
- `BrainMesh/GraphChat/Artifacts/GraphChatAnswerArtifactRevalidator.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatDeterministicAnswerFallbackRenderer.swift`
- `BrainMesh/GraphChat/UI/Artifacts/GraphChatNodeProfileArtifactView.swift`
- `BrainMesh/GraphChat/UI/Artifacts/GraphChatFinalAnswerView.swift`
- `BrainMesh/GraphChat/UI/GraphChatMessageActions.swift`

Artifact- und Präsentationsvertrag:

- `.nodeProfile` ist ein eigener `GraphChatAnswerArtifactPayload` und keine künstliche Detailtabelle. Der Payload erhält sichtbaren und qualifizierten Node-Namen, Owner, optionale Notizen, typisierte Detailwerte mit Einheit, getrennte incoming/outgoing Connections mit beiden Anzeigenamen, Gegenknoten und Link-Notiz sowie metadata-only Attachments einschließlich des unveränderten Content-Type-Werts.
- Detailwerte, incoming Connections, outgoing Connections und Attachments tragen vier unabhängige `GraphChatAnswerArtifactResultMetadata`. Factory-Budgets wirken je Bereich separat. Vollständige kleine Bereiche bleiben vollständig; eine Kürzung erzeugt pro betroffenem Bereich einen konkreten deutschen oder englischen Hinweis. Leere Bereiche werden ausgelassen, ohne die gültige Node-Identity in einen No-Results-Fall umzudeuten.
- `GraphChatNodeProfilePresentation` ist die gemeinsame lokalisierte Projektion. Der deterministische Fallback verwendet exakt deren `plainText`; `GraphChatNodeProfileArtifactView` verwendet dieselben Titel, Zeilentexte und Begrenzungsangaben. `GraphChatCopyContentBuilder` liest ausschließlich den finalisierten `GraphChatAnswer`; es existieren weder ein zweiter Profilformatter für Copy noch eine facts-reduzierte Kurzantwort.
- Die sichtbare Attachment-Präsentation enthält fachliche Art, Titel, Dateiname, Format und Größe. Das Artifact erhält den Content-Type-Identifier verlustfrei für Authority/Revalidation, zeigt ihn aber nicht als technischen UTI. UUIDs, interne Entity-/Field-Aliasse, `CURRENT` und technische Runtime-Begriffe werden nicht aus dem Payload gerendert.

Evidence und partielle Live-Revalidierung:

- `GraphEvidence.nodeProfileArea` kennzeichnet ausschließlich produktive Profil-Evidence für Identity, Notizen, Detailwert, Connection oder Attachment. Der Source Validator vergleicht Node-Namen, Owner und Notizen, typisierten Feldwert und Einheit, aktuelle Link-Endpunktanzeigen, Richtung und exakte Link-Notiz sowie alle Attachment-Metadaten mit dem aktuellen graphgescopten Repository-Wert.
- `GraphChatNodeProfileArtifactEvidenceProjector` verlangt die gültige Identity, entfernt aber ungültige Notizen, einzelne Detailwerte, einzelne incoming/outgoing Connections und Attachments unabhängig. Nur das betroffene Window erhält zusätzlich `.sourceLimited`; ein weiterhin gültiger Rest bleibt deterministisch finalisierbar.
- Der Finalizer projiziert auch den im Primary Result Ledger liegenden ursprünglichen Profil-Payload gegen die nach der letzten Live-Revalidierung tatsächlich im `GraphChatAnswer` verbliebenen Evidence-IDs. Damit kann der deterministische Antworttext keine bereits aus dem Registry-Artifact entfernten Fakten wieder einführen.
- Profilnavigation besteht ausschließlich aus `openNode`/`focusNodeInGraph`-Zielen im aktiven `GraphScope`. Identity-, Owner- und Gegenknoten-Ziele werden live gegen das Repository geprüft; invalidierte Ziele werden nicht publiziert. Attachments besitzen keine Navigation, und Link-Metadaten öffnen weder Dateien noch graphfremde Endpunkte.

Ausführung und Lifecycle:

- Foundational Node Details und semantisch kompilierte Node Details rufen unverändert dieselbe `GetNodeTool`-Action im `GraphChatLocalIntentExecutionKernel` auf, erzeugen denselben `.nodeProfile`-Payload und laufen durch denselben Finalizer. Beide Pfade erzeugen keine Answer-Provider-Session.
- Interpretation, Interpretation Correction, Checkpoints, `CURRENT`, Primary Result Ledger, Conversation-/Artifact-Transaktionen, Deferred Swap, Rollback und Cancellation bleiben unverändert. Der Profiltyp führt keinen zweiten Commit- oder Terminalpfad ein; Erfolg, Fehler, Clarification und Cancellation behalten jeweils genau ein Terminal Event.

### Graph Chat Semantic Intent Interpreter

Pfade:

- `BrainMesh/GraphChat/SemanticIntent/GraphChatIntentInterpreter.swift`
- `BrainMesh/GraphChat/SemanticIntent/FoundationModelsGraphChatIntentInterpreter.swift`
- `BrainMesh/GraphChat/SemanticIntent/FakeGraphChatIntentInterpreter.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatIntentInterpreterRequestBuilder.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatSemanticIntentCoordinator.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatSemanticIntentResolver.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatQueryIntentCompiler.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatAdvancedIntentCompiler.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatQueryIntentValueParser.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatSemanticIntentExecutor.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatSemanticIntentLimitPolicy.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatAdvancedIntentPlans.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatLocalIntentSearchExecutionSupport.swift`
- `BrainMesh/GraphChat/Artifacts/GraphChatAnswerArtifactFactory+AdvancedIntents.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatRequestPipeline.swift`

Zweistufige Trust Boundary:

- `GraphChatIntentInterpreting` ist vom freien `GraphChatModelProvider` getrennt. Seine Foundation-Models-Implementierung besitzt keine Tools und liefert keine Nutzerantwort, sondern ausschließlich einen value-only, `Sendable` und untrusted `GraphChatSemanticIntentDraft`.
- Der Interpreter-Request enthält nur die normalisierte Frage, Antwortsprache, begrenzte nutzersichtbare Entity-/Feldanzeigenamen, appseitig erzeugte sichere Conversation-Beschreibungen und eine nutzersichtbare fachliche Scope-Beschreibung. UUIDs, interne Aliasse und der vollständige App-Katalog werden nicht übertragen.
- Der Draft kann nur Intent-Familie, fachliche Entity-/Feld-/Node-Anzeigenamen, fachliche Filterrelationen, wörtliche Nutzerwerte, Sortier-/Projektions-/Gruppierungsbedeutung, einen der vier Graph-State-Aspekte, eine revalidierbare Conversation-Auswahl und Antwortsprache ausdrücken. Aliasse, IDs, Toolnamen, Comparison-Feature-IDs, Limits und Query-Pläne sind nicht Teil des Vertrags. `GraphChatSemanticIntentDraftValidator` lehnt technische Identifikatoren und Aliasse, Tool-/Query-/Evidence-/Artifact-Sprache, überlange beziehungsweise zu viele Werte sowie ungültige Familienkombinationen ab.
- Der Draft ist niemals eine validierte Identität. `GraphChatSemanticIntentResolver`, `GraphChatQueryIntentCompiler` und `GraphChatAdvancedIntentCompiler` delegieren Entity-, Node- und Feldanzeigenamen an den zentralen `GraphMentionResolver`, der ausschließlich gegen den vollständigen appseitigen `GraphSchemaContext.foundationalAliases` bindet und den Graph-/Chat-/Owner-/Selection-Scope erneut autorisiert. Mehrdeutige fachliche Begriffe erzeugen eine bestehende graph-/conversation-/turngebundene Pending Clarification; nicht sicher bindbare unterstützte Intents werden nicht geraten.
- Erst nach erfolgreicher Auflösung legt die App die technische Action fest: `SearchGraphTool` für Find Nodes, `GetNodeTool` für Node Details und strukturelle Comparisons, `GraphStatsTool` für Graph State beziehungsweise einen durch `GraphChatQueryIntentCompiler` oder `GraphChatAdvancedIntentCompiler` erzeugten `GraphQueryPlan` für Collections, Count, Group Count, Refinement und Same-Entity-Comparison. Die App besitzt Entity-/Field-/Node-Identitäten, Operator, typisierten Wert, Scope, Sortierung, Tie-Breaker, Projektion, Aggregation, Comparison-Art/-Features, Kardinalität, Limits, Evidence-Revalidierung, Artifact-Typ und Conversation-State-Commit.

Pipeline- und Fallback-Reihenfolge:

- `GraphChatRequestPreflight` läuft zuerst. Danach erhält der providerfreie Foundational Compiler den vollständigen Schema-Kontext. `.compiled` und `.clarification` werden sofort lokal abgeschlossen und rufen den semantischen Interpreter nicht auf.
- Nur `.notRecognized` erreicht den Semantic Coordinator. Akzeptierte Find-, Query-, Node-Details-, Comparison- und Graph-State-Drafts werden über den gemeinsamen `GraphChatLocalIntentExecutionKernel` lokal ausgeführt und mit Primary Result, Evidence, zulässigen Result-Artefakten, deterministischem Answer Fallback und Presentation Firewall gerendert; eine freie Answer-Provider-Session entsteht nicht.
- Ausschließlich explizite Drafts der Familien `.unrecognized` oder `.openEnded` fallen auf die unveränderte Provider-Pipeline zurück. Validierungs-, Binding-, Scope-, Query- und Search-Fehler eines bereits erkannten unterstützten Intents sind harte Clarification-/Failure-Pfade und kein impliziter Provider-Fallback.
- Cancellation wird unmittelbar weitergereicht. Vor dem atomaren äußeren Commit werden Conversation-, Evidence-, Presentation-, Artifact- und Ledger-Zustände vollständig zurückgerollt; jeder Stream behält genau ein terminales Event.

Find Nodes:

- Unterstützt werden freie Suchformulierungen wie „Finde Projekt Atlas“, „Suche Einträge zu New York“, „Find Project Atlas“ und „Show me entries about migration“.
- Der Resolver unterscheidet nur die fachlichen Ziele beliebige Nodes, nur Entities, nur Attributes und Attributes einer eindeutig aufgelösten Entity. Revalidierte Suchtreffer werden anschließend graph-, entity-, node-, selection- und kind-gescopt; der Chat-Scope wird nie erweitert.
- `GraphChatSemanticIntentLimitPolicy` bestimmt das technische Search-Limit zentral. Das Result-Artefakt enthält nur revalidierte Treffer. Vor Artifact-, Ledger- und Conversation-Bindung projiziert die lokale Search-Ausführung Evidence auf Source Reference, Anzeigename und Navigation; Subtitle-/Match-Snippets und Feldwerte werden verworfen. Search-Evidence darf damit niemals einen konkreten Detailfeldwert oder einen Search-Snippet als Fakt belegen.

Entity List:

- Freie Listenformulierungen werden gegen den vollständigen appseitigen Entity-Katalog aufgelöst. Der Plan projiziert immer Node Identity, erfindet keine Filter, sortiert stabil nach Anzeigename und verwendet den bestehenden UUID-Tie-Breaker der Query Engine.
- Die zentrale Policy verwendet `GraphQueryPlanLimits.defaultResultLimit` für eine Standardliste. Die fachliche Angabe „alle“ wird auf `GraphQueryPlanLimits.maximumResultLimit` begrenzt. `GraphChatResultWindow`, `totalCount`, `returnedCount` und Truncation bleiben in Primary Result, Artifact und lokaler Antwort sichtbar.
- Erfolgreiche Find- und List-Ergebnisse werden durch den bestehenden Conversation Reducer committed und stehen dadurch als typisierte `CURRENT`-Referenz für Folgeturns zur Verfügung.

Query-Compiler-Policy:

- Unterstützte Feldtypen sind `singleLineText`, `multiLineText`, `numberInt`, `numberDouble`, `date`, `toggle` und `singleChoice`. Die App wählt ausschließlich folgende kompatible Operatoren: Text `contains`, `equals`, `startsWith`, `isPresent`, `isMissing`; Zahlen `equals`, vier Vergleiche, `between`, Presence; Datum `equals`, `before`, `after`, `between`, `inYear`, `inMonth`, `isOverdue`, Presence; Toggle `equals`, Presence; Choice `equals`, `oneOf`, Presence.
- Text bleibt getrimmt und nicht leer. Integer und Double verwenden eine feste deutsche beziehungsweise englische Zahlenkonvention; deutsches Dezimalkomma und englischer Dezimalpunkt sind erlaubt, Gruppierung muss zur Sprache passen, Integer-Overflow und nicht-endliche Double-Werte werden abgelehnt. Booleans verwenden eine begrenzte deutsche/englische Wertemenge. Choice-Werte werden ausschließlich exakt oder eindeutig normalisiert gegen die vollständigen aktuellen Feldoptionen gebunden.
- Explizite Datumswerte verwenden feste deutsche beziehungsweise englische Reihenfolgen sowie ISO, vierstellige Jahre und den appseitig konfigurierten Gregorianischen Kalender. Relative Tage beziehen sich auf das appseitige Reference Date; dieses Datum wird an die kompilierte Local Action gebunden und bei der Kernel-Revalidierung wiederverwendet. `equals` wird als lokaler Kalendertag `[Tagesbeginn, nächster Tagesbeginn)` validiert; `between` besitzt eine inklusive fachliche Obergrenze und wird technisch halb-offen. `inYear`, `inMonth` und `isOverdue` werden ausschließlich durch `GraphChatDateInterpreter` in Grenzen übersetzt. Ein Zeitzonenwechsel darf keinen Datumstext still auf einen anderen fachlichen Kalendertag umdeuten; nicht verlustfrei rekonstruierbare Quellfilter werden als stale abgelehnt. Ein bereits validierter Overdue-Quellfilter übernimmt beim Refinement dieselbe feste exklusive Obergrenze, statt sie anhand eines späteren Tages neu zu interpretieren.
- Node Identity ist immer erste Projektion. Nur explizit verlangte Felder werden zusätzlich projiziert; Sortier- und Filterfelder bleiben lediglich validierte Referenzen. Die maximale Feldprojektion ist `GraphChatAnswerArtifactFactoryBudget.maximumColumns - 1`, sodass Query-Projektion und Artifact-Spalten dasselbe Budget besitzen. Technische IDs werden nie als sichtbare Spalte projiziert.
- Sortierung erlaubt Node Name oder ein Feld derselben Entity. Ohne explizite Collection-Sortierung gilt Node Name aufsteigend. Die Query Engine verwendet weiterhin den stabilen Node-UUID-Tie-Breaker. Refinements erben die validierte Quellsortierung und ersetzen sie nur bei einer expliziten neuen Sortierabsicht.
- Collection-Limits stammen aus `GraphChatSemanticIntentLimitPolicy`, werden auf `GraphQueryPlanLimits.maximumResultLimit` begrenzt und zusätzlich so reduziert, dass die konservative Evidence-Schätzung das gemeinsame Query-Engine-Budget nicht überschreitet. `GraphChatResultWindow` und Truncation bleiben unverändert erhalten. Count zählt die vollständige gefilterte Basis ohne Ergebniszeilen; sein Plan verwendet `.count`. Group Count verwendet `.groupCount(field)`, begrenzt Gruppen und erzeugt vollständige appseitige Gruppenmitgliedschaften bei weiterhin begrenzter Evidence.

Refinement-Policy:

- Scope-Quelle ist ausschließlich ein frisch revalidierter `GraphChatResolvedConversationScope`; die semantische Modellreferenz wählt keinen Scope. Quell-Result-ID/-Alias, Turn und Completion-Zeit, Source-Reference-Count, `lastValidatedQueryPlan`, Result-Revalidation, Entity und konkrete Nodes werden im Compiler und unmittelbar vor der Kernel-Ausführung erneut verglichen.
- Der technische Query-Scope ist exakt der einzelne Quell-Node oder die konkrete Quell-Selection. Entity- und Graph-Scope sind für Refinement verboten. Vorhandene Filter werden typgerecht rekonstruiert und neue Filter als zusätzliche AND-Bedingungen angehängt. Dadurch ist das Ergebnis immer eine Schnittmenge der vorherigen Ergebnismenge.
- Stale, gelöschte, gemischte oder scope-fremde Quellen werden nicht technisch repariert und erreichen keinen freien Provider. Gemischte Entities verwenden die bestehende fachliche Clarification; ein leeres `CURRENT` bleibt der bestehende No-Results-Pfad. Group References übernehmen die deterministisch berechneten Member Nodes innerhalb der bestehenden Conversation-Budgets und werden vor „diese Gruppe“-Fortsetzungen durch die ursprüngliche Group Query erneut geprüft.
- Erfolgreiche Count- und Group-Turns verwenden Metric- beziehungsweise Group-Artefakte. Collection und Refinement verwenden List/Table/Timeline gemäß bestehender Query Artifact Factory. Alle erfolgreichen Pfade laufen durch Evidence Registry, Primary Result Ledger, Conversation Reducer, Presentation Firewall und deterministischen Answer Fallback.

Advanced-Intent-Policy:

- `GraphChatAdvancedIntentPolicy.default` ist die zentrale Kompatibilitätssicht auf die technischen Grenzen: höchstens `8` Comparison-Nodes, höchstens `8` Comparison-Features, `6` Defaultfeatures, Node-Details-Per-Bereich-Cap `20`, Structural-Cap `0`, Graph-Hub-Limit `10`, maximal `96` Evidence-Einträge und `4` Artifacts. Die zugrunde liegende `GraphChatIntentLimitPolicy` besitzt zusätzlich die vier unabhängigen Node-Profilgrenzen. Interpreter und Modell können keinen dieser Werte setzen.
- Node Details akzeptiert genau einen nach aktueller Schema-/Repositorysicht revalidierten Node aus explizitem Anzeigenamen, `CURRENT`, Ordinal, Last Node oder einer bestehenden Clarification. Der erzeugte Query-Scope ist exakt dieser Node; `GraphChatScopeAuthorization` verhindert jeden Zugriff außerhalb des bestehenden Chat-Scopes. `GetNodeTool` lädt das autoritative Profil mit getrennten Bereichen und Attachment-Metadaten, aber nie Attachment-Binärinhalte.
- `GraphChatComparisonPlan` ist value-only und bindet Graph, Chat-Scope, Request, Conversation, Turn, mindestens zwei eindeutige revalidierte Nodes, Comparison-Art, Features, optionale Selection Query, gemeinsames Related-Limit, Sprache, erwartete Cardinality und die zentrale Policy. Gemischte Graphen, stale Nodes/Comparisons, doppelte Subjects sowie übergroße Node-/Featuremengen werden abgelehnt.
- Attributes derselben Entity werden fachlich verglichen. Die Selection Query projiziert immer Node Identity und die ausdrücklich verlangten Felder. Ohne Feldangabe sortiert die App das vollständige aktuelle Entity-Schema zuerst nach `isPinned` absteigend, dann `sortIndex`, normalisiertem Anzeigenamen und zuletzt ausschließlich intern nach Feld-UUID; sie verwendet höchstens sechs Felder. Query-Zellen transportieren fehlende autoritative Values als `.missing`; Integrity-Konflikte und Values ohne revalidierte Evidence werden entfernt.
- Entity-Nodes, gemischte Node-Arten und Nodes unterschiedlicher Entities verwenden keine gemeinsame Detailfeldprojektion. Die feste strukturelle Featuremenge besteht aus Node-Art, Owner-Anzeigename sofern vorhanden, Anzahl direkter Links, Anzahl Attachment-Metadaten, Notiz-Vorhandensein und Anzahl autoritativer Detailwerte. Die strukturelle `GetNodeTool`-Action verwendet `includeNotes: false` und Related-Limit `0`; Notiz-, Linknotiz- und Attachment-Inhalte gelangen damit nicht in Output oder Evidence.
- Die Comparison Artifact Factory erhält Subjects und Features in Planreihenfolge, erzeugt typisierte Values mit Evidence-Bindung pro Wert, graphgescopte Navigation Targets und explizite Truncation-Metadaten. Ein Artifact mit weniger als zwei belegten Subjects oder ohne belegtes Feature wird nicht gestaged oder committed. Sichtbare Labels stammen ausschließlich aus revalidierten Anzeigenamen beziehungsweise lokalisierten festen Labels; UUIDs und interne Aliasse dienen nur als unsichtbare stabile Keys/Tie-Breaker.
- Erfolgreiche Comparisons erzeugen `comparisonResultResolved`, einen Result Context der Art `.comparison`, `lastComparison`, `lastCompared` und eine plural/ordinal `CURRENT`-Bindung. Jede Fortsetzung revalidiert die konkreten Nodes erneut; ein stale Comparison-Bezug wird nicht auf Entity- oder Graph-Scope erweitert.
- Graph State kennt `overview`, `counts`, `structure` und `health`. `GraphStatsTool` akzeptiert ausschließlich den exakten `.entireGraph`-Chat-Scope desselben Graphen. Overview darf Metric, Ranking und Health Finding liefern; Counts nur Metric; Structure Metric plus Ranking; Health Metric plus Health Finding. Entity-, Node- und Selection-Chats werden weder im Compiler noch im Tool auf den gesamten Graphen erweitert.
- Nach erfolgreicher Compilation bleiben Node Details, Comparison und Graph State vollständig lokal: Toolausführung, Primary Result, Evidence/Artifact-Staging, deterministischer deutscher oder englischer Fallback, Presentation Firewall und Conversation Commit laufen ohne freien Answer Provider. Cancellation oder ein Commit-Fehler verwenden denselben vollständigen Rollback- und Single-Terminal-Event-Pfad wie die vorhandenen lokalen Intents.

Observability:

- Content-free Events unterscheiden Interpreter-Start, Draft akzeptiert/abgelehnt, Find/List/Filtered Collection/Count/Group/Refinement/Node Details kompiliert, Same-Entity- und Structural Comparison, Comparison-Ablehnung, Graph Overview, Graph Health, Typkonflikt, abgelehntes Value Parsing, verhinderte Scope-Erweiterung, verworfenen stale Node, abgelehntes stale Resultset, Clarification, Legacy-Provider-Fallback und Cancellation.
- Request-Metriken zählen Interpreter- und Answer-Provider-Aufrufe getrennt. Fragen, Draftwerte, Anzeigenamen, Aliasse, IDs, Suchbegriffe und Antworttext werden nicht protokolliert.

### Graph Chat Typed Planner Cutover (INTENT-COMPILER-7)

Pfade:

- `BrainMesh/GraphChat/TypedIntent/GraphChatIntentLimitPolicy.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatTypedPlannerCutoverPolicy.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatIntentInterpreterRequestBuilder.swift`
- `BrainMesh/GraphChat/SemanticIntent/GraphChatSemanticIntentCoordinator.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatRequestPipeline.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatOrchestrator.swift`
- `BrainMesh/GraphChat/Observability/GraphChatObservability.swift`
- `BrainMeshTests/GraphChatTypedIntentPlannerAcceptanceTests.swift`

Verbindliche Planner-Reihenfolge:

1. `GraphChatRequestPreflight` normalisiert und validiert Graph-/Chat-/Conversation-Bindung und behandelt Unsupported beziehungsweise bestehende Clarifications.
2. `GraphChatFoundationalIntentCoordinator` prüft die exakten providerfreien Fast-Path-Familien.
3. Nur `.notRecognized` startet `GraphChatIntentInterpreting`; der Interpreter besitzt keine Tools und antwortet nicht fachlich.
4. `GraphChatSemanticDraftValidator` prüft den untrusted Draft vollständig, bevor irgendeine Identität aufgelöst oder lokal ausgeführt wird.
5. Conversation Reference Resolver, Semantic Resolver, Query Intent Compiler und Advanced Intent Compiler binden ausschließlich gegen frisches vollständiges App-Schema und aktuellen Scope.
6. Mehrdeutigkeit erzeugt eine fachliche Clarification; andernfalls entsteht ein versionierter `GraphChatTypedIntent` mit einer vollständig bestimmten lokalen Action.
7. `GraphChatLocalIntentExecutionKernel` revalidiert und führt Query, Search, Get Node oder Graph Stats lokal aus; Finalizer, Presentation Firewall, Evidence, Artifact, Ledger und Conversation Commit bleiben app-owned.
8. Erst ein Draft der Familie `.unrecognized`/`.openEnded` oder die eindeutig technische Nichtverfügbarkeit des Interpreters öffnet die vorhandene Legacy-Provider-Pipeline.

Harte Cutover-Regel:

- `GraphChatTypedPlannerCutoverPolicy.supportedFamilies` enthält exakt Find Nodes, Entity List, Filtered Collection, Count, Group Count, Refinement, Node Details, Compare Nodes und Inspect Graph State.
- Für diese Familien kann `legacyFallbackReason(for:)` keinen Grund liefern. Ein Resolver-Rückfall aus einer unterstützten Familie ist ein `invalidRequest` und kein Übergang zur Provider-Toolwahl.
- Ein teilweise valider Draft wird nicht „best effort“ ausgeführt: UUID, technischer Alias, graphfremde Auswahl, inkompatibles Feld, falscher Operator, stale `CURRENT` oder Scope-Konflikt führen zu Clarification oder harter Ablehnung.
- Nach einem akzeptierten Draft gibt es weder Interpreter-Retry noch Tool-Repair noch Answer Provider. Eine erfolgreiche freie unterstützte Frage besitzt höchstens einen Interpreter-Aufruf; der Foundational Fast Path besitzt null Modellaufrufe.
- Der Legacy-Provider und seine sechs Tools bleiben für echte offene read-only Fragen vorhanden. Legacy Tool Repair und Provider Context Retry gelten ausschließlich in diesem offenen Pfad.

Interpreter-Recovery:

- `GraphChatIntentInterpreterContextLimits.default` wird aus dem Standardprofil der gemeinsamen Limit-Policy abgeleitet. Entitäten, Felder, Conversation-Beschreibungen, References, Selection Labels und sichtbare Stringlängen sind vor dem Prompt begrenzt; der vollständige App-Katalog bleibt ausschließlich beim Resolver.
- Nur `GraphChatIntentInterpreterErrorCode.contextWindowExceeded` löst genau einen Request mit `.compactRetry` aus. Das Compact-Profil reduziert alle promptwirksamen Schema-/Conversation-Budgets deterministisch.
- Beide Aufrufe leben im selben strukturierten Request-Task und Cancellation-Budget. Es gibt keine Repair-Schleife und keinen dritten Aufruf.
- `.unavailable` beziehungsweise ein erneutes Context-Window-Problem nach dem Compact-Retry gelten als technische Nichtverfügbarkeit. `invalidOutput`, Guardrail-/Sprachfehler, unerwartete Fehler sowie jede Draft- oder Resolver-Ablehnung fallen geschlossen aus.

Gemeinsame Limit-Policy:

- `GraphChatIntentLimitPolicy` besitzt Default/Maximum für Search, Query Results und vollständige Collections, Group Count, Filter, Projection Fields, Comparison Nodes/Features, Node Related Items, Neighbors, Graph Hubs, Clarification Options und Expiry, Interpreter-Strings/-Arrays, Evidence und Artifact-Anzahl.
- `GraphQueryPlanLimits`, `GraphChatSemanticIntentLimitPolicy`, `GraphChatAdvancedIntentPolicy`, Tool-Inputs/-Maxima, Query Engine, Artifact Factory und Foundation-Models-Guides leiten fachlich gleiche Grenzen von dieser Policy ab. Die Modelldrafts transportieren weiterhin keine technischen Limits.
- `ResultWindow` transportiert jede Begrenzung und Truncation bis in App-Text und Artifact. Vollständige Collection bedeutet vollständig nur innerhalb des autorisierten Scopes und des appseitigen Maximums.

Lifecycle und Präsentation:

- Pipeline-Stages erfassen Preflight, Fast Path, Interpreter, lokale Ausführung, Provider-Ressourcen, Finalisierung und Commit. Cancellation wird content-free der aktiven Stage zugeordnet.
- `GraphChatRequestStreamController`, Generation State Machine und Compare-and-set-Commit verhindern verspätete lokale beziehungsweise Interpreter-Ergebnisse und garantieren genau ein Terminal Event. Graph-/Scope-/Lock-Wechsel, Regenerate, Edit-and-Resend und Correction invalidieren alte Bindings.
- Failure/Cancellation reinigen Conversation-Transaction, Evidence-/Presentation-Registry, Artifact-Staging/Session und Primary-Result-Ledger. Pending Clarifications verwenden die zentrale Expiry- und Optionsgrenze.
- Jeder erfolgreiche Typed Intent besitzt sicheren nicht leeren lokalen Fachtext, appseitig rekonstruierte Interpretation und Evidence oder Result-Artefakt. UI und Copy lesen denselben finalisierten Text; UUID, Alias, Drafttext und rohe Tool-/Query-/Resolver-/Repository-/Integrity-Fehler werden nicht gerendert.

Bewusst offene Frageformen:

- allgemeine Erklärungen, Synthesen, Bewertungen und Begründungen ohne eine unterstützte lokale Familie;
- Multi-Hop- und freie Zusammenhangsanalyse;
- Minimum, Maximum und nicht definierte Aggregationen;
- semantische Analyse von Attachment-Inhalten;
- Schreib-, Änderungs- und Mutationswünsche, da Graph Chat read-only bleibt.

### Graph Chat Typed-Intent- und Local-Execution-Trust-Boundary

Pfade:

- `BrainMesh/GraphChat/TypedIntent/GraphChatTypedIntent.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatAdvancedIntentPlans.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatLocalIntentAction.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatLocalIntentExecutionKernel.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatLocalIntentQueryExecutionSupport.swift`
- `BrainMesh/GraphChat/Foundational/GraphChatFoundationalIntentAdapter.swift`
- `BrainMesh/GraphChat/Foundational/GraphChatFoundationalIntentExecutor.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatRequestPipeline.swift`

Domainvertrag:

- `GraphChatTypedIntent` ist versioniert, value-only, `Hashable` und `Sendable`; SwiftData-Modelle, Provider-Sessions und Modelltext sind ausgeschlossen.
- Die Payload unterscheidet typseitig Find Nodes, Entity Collection, Count/Group, Node Details, Narrow Result Set, Compare Nodes und Inspect Graph State. Ausführbare Local Actions existieren für alle diese Familien; Compare Nodes trägt zusätzlich den zentral validierten `GraphChatComparisonPlan`.
- Gemeinsame Bindings enthalten Graph-, Chat- und Query-Scope, Sprache, Request, Conversation, aktuellen Turn, optionalen Quell-Turn und Clarification, Resolution Source/Origin/Quality, erwartete Kardinalität, Fact-Erwartung, Ergebnis-/Sicherheitslimits sowie validierte Entity-, Field- und Node-Identitäten.
- Der Foundational Adapter bildet `singleNodeFieldValue` verlustfrei auf `.nodeDetails` mit `.authoritativeSingleField`, `entityAttributeCollection` auf `.entityCollection` und Foundational `nodeDetails` auf `.nodeDetails` mit der bestehenden lokalen Node-Action ab. Der Semantic Resolver erzeugt nach separater Draft-Validierung und vollständiger appseitiger Bindung `.findNodes`, `.entityCollection`, `.countOrGroup`, `.nodeDetails`, `.narrowResultSet`, `.compareNodes` oder `.inspectGraphState` mit fester lokaler Action.

Execution-Kernel:

- `GraphChatLocalIntentExecutionKernel` akzeptiert ausschließlich einen bereits appseitig kompilierten `GraphChatTypedIntentAdaptation`-Vertrag. Er trifft keine freie Tool-, Query- oder Semantikentscheidung.
- Vor jedem Repositoryzugriff werden Request, Conversation, Turn, Graph, Chat-Scope, Artifact-Session, Quell-Turn, Schemaidentitäten, Query-Plan und Scope-Autorisierung erneut geprüft.
- Pro lokaler Ausführung existieren genau eine Conversation-State-Transaktion, Evidence Registry, Presentation Registry, Artifact-Transaktion und ein Primary-Result-Ledger. `GraphChatFoundationalIntentExecutor` besitzt keinen zweiten Lifecycle mehr und delegiert nach der Adaption vollständig an den Kernel.
- Der Kernel führt Query beziehungsweise `SearchGraphTool`, `GetNodeTool` oder `GraphStatsTool`, Result-Normalisierung, Trusted Event, Artifact-Staging, Ledger-Bindung, Finalisierung und den äußeren atomaren Turn-Commit über einen Pfad aus. Er liefert genau einen finalisierten Turn oder wirft genau einen Fehler an den bestehenden Stream-Controller.
- Fehler und Cancellation entfernen Evidence, Presentation, Ledger-Einträge und gestagte Artifacts und setzen die Conversation-Transaktion auf ihren Base-State zurück. Scheitert der äußere Commit nach erfolgreichem Artifact-Commit, entfernt der Kernel die bereits committed wirkenden Session-Artefakte.
- Erfolgreicher Commit behält ausschließlich die finalen Session-Artefakte; temporäre Evidence-, Presentation-, Ledger-, Staging- und Conversation-Transaktionszustände werden anschließend bereinigt.
- Single Field behält Node Identity plus exakt ein Feld, Limit `1`, denselben Authoritative-Fact-Extractor und vollständig appseitiges Rendering. Collections behalten das vollständige `GraphChatResultWindow`, Truncation und das bestehende Result-Artefakt.
- Node Details behalten den exakten Node-Scope und die vier zentralen Profilgrenzen; Same-Entity-Comparisons verwenden ausschließlich die validierte Selection Query; Structural Comparisons verwenden ausschließlich `GetNodeTool`-Strukturdaten; Graph State verlangt den exakten Entire-Graph-Scope.
- Explizit semantisch `.unrecognized` beziehungsweise `.openEnded` klassifizierte Fragen erreichen unverändert die Provider-Pipeline; lokale Execution erzeugt weder Answer-Provider-Session noch modellbestimmten Tool Call oder Modelltext.

Bewusste Grenze:

- Graph-Writes, gespeicherte Interpretationspräferenzen, allgemeine Undo-History, neue Intent-Familien, Multi-Hop-Analyse, Attachment-Inhaltsanalyse und eine allgemeine semantische Wahrheitsprüfung offener Providerantworten bleiben außerhalb dieses Stands. Minimum/Maximum werden weiterhin nicht durch den Semantic Query Compiler erzeugt.

### Graph Chat Intent Interpretation Presentation

Pfade:

- `BrainMesh/GraphChat/Interpretation/GraphChatIntentInterpretation.swift`
- `BrainMesh/GraphChat/Interpretation/GraphChatIntentInterpretationBuilder.swift`
- `BrainMesh/GraphChat/Interpretation/GraphChatIntentInterpretationRenderer.swift`
- `BrainMesh/GraphChat/Interpretation/GraphChatLocalIntentPreparedExecution+Interpretation.swift`
- `BrainMesh/GraphChat/Core/GraphChatModels.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatAnswerFinalizer.swift`
- `BrainMesh/GraphChat/Presentation/GraphChatPresentationFirewall.swift`
- `BrainMesh/GraphChat/UI/Artifacts/GraphChatFinalAnswerView.swift`

Domain und Ableitung:

- `GraphChatIntentInterpretation` ist versioniert, value-only, `Hashable` und `Sendable`. Der Vertrag bindet Intent-Art, Graph-, Chat- und Query-Scope, Request, Conversation, Turn und optionalen Quell-Turn sowie Sprache, Entity-, Node- und Feldidentitäten, typisierte Filter, Sortierung, Gruppierung beziehungsweise Aggregation, Ergebnisumfang, Graph-State-Aspekt, Resolution Source/Origin/Quality und die für diese Intent-Art editierbaren Bestandteile.
- IDs bleiben ausschließlich für Konsistenzprüfung und Revalidation im Wert gebunden. Der Renderer greift nur auf revalidierte Anzeigenamen, typisierte Fachwerte und feste lokalisierte Labels zu.
- Der Finalizer erzeugt die Interpretation nur für einen erfolgreich vorbereiteten lokalen Intent. Query-basierte Familien verwenden den im Conversation-Transaction-State gehaltenen `ValidatedGraphQueryPlan`. Search, direkte Node Details, Structural Comparison und Graph State benötigen zusätzlich einen passenden revalidierten Result Context, Primary-Result-Tooltyp und bei Comparisons die exakt gebundene Node-Menge.
- Semantic Draft, Provider-Text, Tool-Content-Strings, technische Aliasse und `GraphChatAnswerArtifactQuerySummary` sind keine Ableitungs- oder Fallbackquelle. Ein Legacy-Provider-Turn ohne lokalen Typed Intent behält `interpretation == nil`.

Presentation und Retention:

- `GraphChatIntentInterpretationRenderer` erzeugt ausschließlich fachlich kompakte deutsche oder englische Titel. Technische Query-Zusammenfassungen, Toolnamen, Operator-Rohwerte, Scope-Namen, Limits, Aliasse und IDs werden nicht formatiert.
- Die Presentation Firewall prüft zusätzlich Label und Titel sowie alle verwendeten Entity-, Node-, Feld-, Einheiten-, Filterwert-, Sortier- und Gruppierungsanzeigen. Bei einem Verstoß wird nur die optionale Interpretation entfernt; die ansonsten sichere validierte Antwort bleibt erhalten.
- `GraphChatAnswer` trägt die optionale Interpretation rückwärtskompatibel. Message-State-Normalisierung, Artifact-Retention, Finalizer-Fallbacks, Regenerate, Edit-and-Resend und Transcript Checkpoints behalten den Wert, solange der zugehörige Answer erhalten bleibt; die UI revalidiert ihn unmittelbar vor der Darstellung erneut.
- `GraphChatFinalAnswerView` zeigt die Interpretation direkt oberhalb des direkten Antworttexts als kompakte Materialdarstellung. Nur eine Interpretation mit konsistentem verborgenem Correction-Origin wird als Button präsentiert; Legacy- und Provider-Antworten bleiben passiv. Dynamic Type besitzt kein Zeilenlimit; VoiceOver erhält ein lokalisiertes Label und einen verständlichen Editor-Hinweis ohne technische Werte.
- Standard-Copy bleibt auf den finalisierten autoritativen Antworttext und die bisherige Answer-Struktur begrenzt. Die Interpretation wird nicht ungefragt in den kopierten Fachwert aufgenommen.
- Content-free Observability unterscheidet `created`, `displayed`, `discardedPresentationViolation` sowie die Correction-Lifecycle-Events; Titel, Anzeigenamen, Werte, IDs und Antworttext werden nicht protokolliert.

Bewusste Grenze:

- Die Correction erweitert keine Intent-Familie und besitzt keinen Graph-Write-Pfad. Eine Interpretation ohne lokalen finalisierten Typed Intent und gültigen Correction-Origin wird nicht nachträglich editierbar gemacht.

### Graph Chat Interpretation Correction

Pfade:

- `BrainMesh/GraphChat/Interpretation/GraphChatInterpretationCorrectionDomain.swift`
- `BrainMesh/GraphChat/Interpretation/GraphChatInterpretationCorrectionSchema.swift`
- `BrainMesh/GraphChat/Interpretation/GraphChatInterpretationCorrectionCompiler.swift`
- `BrainMesh/GraphChat/UI/Correction/GraphChatInterpretationCorrectionPlanner.swift`
- `BrainMesh/GraphChat/UI/Correction/GraphChatInterpretationCorrectionEditorSession.swift`
- `BrainMesh/GraphChat/UI/Correction/GraphChatInterpretationCorrectionEditorView.swift`
- `BrainMesh/GraphChat/UI/Correction/GraphChatInterpretationCorrectionFiltersEditor.swift`
- `BrainMesh/GraphChat/UI/GraphChatMessageActionController.swift`
- `BrainMesh/GraphChat/UI/GraphChatViewModel.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatOrchestrator.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatRequestPipeline.swift`
- `BrainMesh/GraphChat/TypedIntent/GraphChatLocalIntentExecutionKernel.swift`

Correction Binding:

- `GraphChatInterpretationCorrectionOrigin` ist ein verborgener, nicht gerenderter Ausführungsnachweis im finalisierten Answer. Er bindet die vollständige validierte `GraphChatTypedIntentAdaptation`, die normalisierte ursprüngliche Request-Frage und die aktuelle Artifact-Session. Dadurch bleiben unter anderem Find-Suchbegriff und Refinement-Quelle verfügbar, ohne sie aus sichtbarem Text zurückzuinterpretieren oder einen nachträglich veränderten Transcript-Text als ursprünglichen Request zu akzeptieren.
- `GraphChatInterpretationCorrectionBinding` bindet die ursprüngliche User- und Assistant-Message, den ursprünglichen Request und Turn, Conversation ID, Graph- und Chat-Scope, Intent-Domainversion, vollständige ursprüngliche Interpretation, Artifact-Session, Checkpoint vor dem ursprünglichen Turn, erwarteten aktuellen Checkpoint sowie die zu ersetzenden Artifact-IDs. Ein Binding wird nur aus einem finalisierten Assistant unmittelbar nach seiner User-Frage geplant.
- Die editierbare Selection enthält Entity, Nodes beziehungsweise Auswahl, Felder, typisierte Filter samt Operator und Wert, Sortierung, Gruppierungsfeld, Ergebnisumfang, Find-Begriff/-Ziel und Graph-State-Aspekt. Diese IDs sind ausschließlich eine Nutzerabsicht und keine Ausführungsberechtigung.

Schemaorientierter Editor und Revalidation:

- Beim Öffnen lädt das ViewModel einen frischen vollständigen `GraphSchemaContext` mit `foundationalAliases` und prüft die gebundene Artifact-Session über die aktuelle Presentation-Auflösung. Das value-only Editor-Snapshot enthält ausschließlich autorisierte Entity-, Node-, Field-, Choice-, Operator- und feste Aspektoptionen mit revalidierten Anzeigenamen.
- Sichtbar sind nur die zur Intent-Art passenden Controls: Find-Begriff/-Ziel, Collection-Entity/Filter/Sortierung/Umfang, Count-Filter, Group-Feld, Node Details, Refinement-Filter/-Sortierung, Comparison-Nodes/-Felder oder der Entire-Graph-Aspekt. Choice und Boolean verwenden Picker, Zahl und Datum lokalisierte Eingaben; UUIDs, Aliasse, Toolnamen und Operator-Rohwerte werden nie gerendert.
- Apply lädt Schema, Artifact-Session und Transcript-Branch erneut. `GraphChatInterpretationCorrectionCompiler` prüft Binding, Graph-/Chat-/Query-Scope, Conversation, Domainversion, Entity-/Field-Zugehörigkeit, Node-Autorisierung, Operator-Kompatibilität und alle Werte. Entity-Wechsel bleiben im Chat-Scope; Node-/Selection-Scope wird nicht erweitert; Refinement bleibt eine Schnittmenge der revalidierten ursprünglichen Quell-Nodes; Graph State verlangt exakt Entire Graph.
- Der Compiler baut einen neuen fachlichen Semantic Draft aus den ausgewählten value-only Werten, führt ihn erneut durch `GraphChatSemanticDraftValidator` und direkt durch den appseitigen `GraphChatSemanticIntentResolver`. Query-Familien laufen damit unverändert durch `GraphChatQueryIntentCompiler` und `GraphQueryPlanValidator`; es existiert kein UI-eigener Query Builder. Semantic Interpreter und freier Answer Provider sind in diesem Pfad nicht erreichbar.

Rewind, Replacement und Artifact Cleanup:

- Apply bricht eine aktive Generation zunächst kontrolliert ab. Der bisherige vollständige Conversation State, Transcript, Feedback und die committed Artifacts bleiben während Compilation und lokaler Ausführung autoritativ; der Rerun arbeitet spekulativ auf dem Checkpoint unmittelbar vor dem ursprünglichen Turn.
- Der lokale Kernel erzeugt daraus einen Kandidaten mit exakt einem neuen Turn und einer frisch aus dem neuen Typed Intent rekonstruierten Interpretation. Der äußere Conversation-Commit ist ein Compare-and-set gegen den beim Öffnen beziehungsweise Anwenden erneut bestätigten vollständigen aktuellen State. Ein Graph-/Scope-/Lock-/Conversation-/Schema-/Node-/Field- oder Artifact-Session-Wechsel macht die Correction stale.
- Der Branch-Plan behält die ursprüngliche Nutzerfrage und den Prefix bis einschließlich dieser Frage. Der alte Assistant sowie alle nachfolgenden Turns werden nach derselben Suffix-Policy wie Edit-and-Resend entfernt. Deren Feedbackzuordnungen und History-Einträge werden erst nach erfolgreichem Runtime-Commit ersetzt.
- Artifact-Staging verwendet einen deferred Replacement-Commit: Vor dem Conversation-Compare-and-set werden neue Artifacts vollständig revalidiert und versiegelt, aber nicht veröffentlicht; alte Artifacts bleiben erreichbar. Nach erfolgreichem Compare-and-set entfernt die Registry in einer actor-isolierten, nicht fehlschlagenden Transition exakt die gebundenen Suffix-Artifacts, veröffentlicht die neuen und wendet das Session-Budget einmal an. Dadurch bleiben Prefix-Artifacts erhalten und `CURRENT` verweist ausschließlich auf das neue Resultset.
- Failure oder Cancellation vor dem Compare-and-set rollt Conversation-Transaktion, Evidence, Presentation, Ledger und deferred Artifacts zurück und lässt den alten erfolgreichen Answer unverändert. Nach einem erfolgreichen Compare-and-set wird die nicht fehlschlagende Artifact-/Cleanup-Sequenz unabhängig von später Cancellation abgeschlossen. Der Stream-Controller emittiert genau ein terminales Event.
- Content-free Observability umfasst `correctionEditorOpened`, `correctionCancelled`, `correctionValidated`, `correctionStale`, `localCorrectionRerunStarted`, `localCorrectionRerunCommitted` und `localCorrectionRerunRolledBack`.

### Graph Chat Authoritative Fact Trust Boundary

Pfade:

- `BrainMesh/GraphChat/AuthoritativeFacts/GraphChatAuthoritativeFact.swift`
- `BrainMesh/GraphChat/AuthoritativeFacts/GraphChatAuthoritativeFactExtractor.swift`
- `BrainMesh/GraphChat/AuthoritativeFacts/GraphChatAuthoritativeFactRenderer.swift`
- `BrainMesh/GraphChat/Foundational/GraphChatFoundationalIntentExecutor.swift`
- `BrainMesh/GraphChat/Query/GraphChatQuerySource.swift`
- `BrainMesh/GraphChat/Query/GraphChatQueryEngine.swift`
- `BrainMesh/GraphChat/Evidence/GraphEvidenceValidator.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatAnswerFinalizer.swift`

Fact-Vertrag:

- `GraphChatAuthoritativeFact` und seine Bindings sind ausschließlich value-only, `Hashable` und `Sendable`. Sie enthalten keine SwiftData-Modelle, Provider-Aliasse oder aus Modelltext extrahierte IDs.
- Der Fact bindet Graph und Chat-Scope, Request/Turn, Artifact-Session und -Transaktion, den erwarteten Node samt Anzeigename, Entity und Feld samt Anzeigenamen, `DetailFieldType`, den typisierten `GraphChatAnswerArtifactValue`, eine optionale Einheit, Evidence-/Artifact-IDs und die Kardinalität `.exactlyOne`.
- Die Erwartung entsteht ausschließlich für einen bereits kompilierten `singleNodeFieldValue`-Intent. Entity, Feld, Node und Namen stammen aus dem vollständigen appseitigen Schema-/Repository-Kontext.
- Der Query-Read-Snapshot führt konfliktbehaftete `(graphID, attributeID, fieldID)`-Keys separat weiter. Widersprüchliche oder ungültige Duplicate-Gruppen liefern weiterhin keinen Wert, können im Finalizer aber ausdrücklich als Integrity-Konflikt statt als zufällige Leermenge abgelehnt werden.

Extraktionsregeln:

- Akzeptiert wird nur das aktuell revalidierte primäre `.query`-Ergebnis desselben Graphs, Chat-Scopes, Requests/Turns, derselben Artifact-Session und -Transaktion.
- Das Query-Summary muss genau die erwartete Entity, Node Identity, genau ein projiziertes Feld, keine Filter, Gruppierung oder Aggregation und `limit = 1` beschreiben.
- Das Result-Artefakt muss eine nicht abgeschnittene Table mit genau einer Zeile, genau einer Primary-Spalte und genau einer Feldspalte enthalten. Row-ID und Navigation Target müssen auf den erwarteten Node zeigen; der Wert darf nicht `.missing` sein und muss dem erwarteten `DetailFieldType` entsprechen.
- Genau eine gebundene `.detailValue`-Evidence muss denselben Graph, Node, Entity-Owner, dasselbe Feld, dieselbe Einheit und denselben typisierten Wert belegen. `GraphEvidenceSourceValidator` vergleicht transportierte Detailwerte bei der Live-Revalidierung zusätzlich mit dem aktuellen Repository-Wert.
- Mehrere Nodes, mehrere projizierte Felder, mehrere passende Evidence-Werte, fehlende Werte, Truncation, Binding-Mismatches, stale Artifacts oder ungelöste Integrity-Konflikte erzeugen keinen Fact.
- `SearchGraph` darf weiterhin Trefferexistenz, sicheren Anzeigenamen und Navigation belegen. Ohne transportierten Feldwert kann Search niemals ein Datum, Text, Zahl, Boolean oder Choice für einen Single-Field-Intent begründen. Es gibt keine globale Regex-Sperre für Zahlen oder Datumsangaben in anderen Antwortarten.

Rendering und Finalisierung:

- Für einen erfolgreichen kompilierten Single-Field-Turn ersetzt der Finalizer den gesamten fachlichen Modelltext immer durch `GraphChatAuthoritativeFactRenderer`; die lokale Ausführung benötigt dafür keine Provider-Session. Modellgenerierte Sections und Follow-ups werden verworfen, Primary Evidence, Artifact-ID, Navigation, Query-/Conversation-State und `CURRENT`-Referenz bleiben erhalten.
- Datum wird ohne Uhrzeit mit expliziter gregorianischer Calendar-, Locale- und TimeZone-Konfiguration ausgegeben. Integer und Decimal bleiben typgetreu; Decimal läuft nicht über einen zusätzlichen `Double`-Roundtrip. Boolean wird deutsch als `Ja/Nein`, englisch als `Yes/No` gerendert. Choice zeigt das fachliche Label, Text wird Unicode-normalisiert und nur strukturell bei Zeilenenden/Whitespace bereinigt.
- Leerer, technischer, richtiger oder fachlich falscher Provider-Text kann den Fact nicht verändern. Schlägt die Fact-Revalidierung fehl, wird der Modellwert verworfen und ein typisierter lokalisierter Insufficient-Evidence-/No-Results-Pfad ausgeliefert.
- Unmittelbar vor Extraktion und Rendering prüft der Finalizer Cancellation. Nur der finalisierte Answer erreicht den terminalen Message-State; UI und Copy lesen denselben `GraphChatAnswer`. Regenerate und Edit-and-Resend starten wieder denselben Orchestrator-/Finalizer-Pfad.

Bewusste Grenze:

- Diese Policy ist keine allgemeine semantische Wahrheitsprüfung. Listen, Gruppierungen, Vergleiche, Aggregationen und offene Erklärungen behalten die bestehende Primary-Result-, Fallback- und Presentation-Policy.
- Der Foundational Intent Compiler wird in diesem Stand nicht um freie Statistik-, Vergleichs- oder beliebige sprachliche Feldfragen erweitert.

### Graph Chat Presentation Trust Boundary

Pfade:

- `BrainMesh/GraphChat/Presentation/GraphChatPresentationRegistry.swift`
- `BrainMesh/GraphChat/Presentation/GraphChatPresentationFirewall.swift`
- `BrainMesh/GraphChat/Provider/GraphChatModelToolRuntime.swift`
- `BrainMesh/GraphChat/Provider/GraphChatProviderExecutor.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatAnswerFinalizer.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatDeterministicAnswerFallbackPolicy.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatDeterministicAnswerFallbackRenderer.swift`
- `BrainMesh/GraphChat/UI/GraphChatMessageActions.swift`

Vertrag:

- Jede Provider-Session besitzt eine turn-gebundene `GraphChatPresentationRegistry`.
- Initiale Einträge stammen aus dem validierten Schema- und Conversation-Kontext.
- Der Tool-Runtime ergänzt ausschließlich validierte Node-, Evidence- und Artifact-Präsentationen.
- Partials werden als kumulative Foundation-Models-Snapshots vollständig erneut geprüft. Unvollständige Suffixe technischer Tokens werden gepuffert, sodass auch ein über mehrere Chunks verteiltes Alias nie kurzzeitig im UI erscheint.
- Öffentliche Failure-Texte werden ausschließlich aus dem typisierten `GraphChatErrorCode` lokalisiert. Modell-, Tool-, Resolver-, Provider-, Repository- und Validierungsdetails werden nicht in UI-State oder Copy übernommen.
- Der Finalizer prüft direkte Antwort, Sections, Filter, Follow-ups und Clarifications gemeinsam. Die optionale Intent-Interpretation wird einschließlich ihrer Anzeigenamen, Werte und Sortier-/Gruppierungslabels separat geprüft; ein Verstoß entfernt nur sie. Bei einem erfolgreichen Primärergebnis führen Verstöße im eigentlichen Antwortinhalt weiterhin zum deterministischen Result-Fallback. Ohne erfolgreiches Primärergebnis bleiben die bestehenden typisierten Zustände und sicheren lokalisierten Ersatztexte maßgeblich.
- `GraphChatAnswer` trägt den geprüften turn-bezogenen Presentation-Kontext bis zum Copy-Pfad. Copy verwendet dieselbe Firewall; der frühere separate UUID-Redactor existiert nicht mehr.
- Die Xcode-Gruppen sind filesystem-synchronisiert; neue Dateien unter `BrainMesh/` und `BrainMeshTests/` werden automatisch den jeweiligen Targets zugeordnet.

Bewusste Grenze:

- Die Firewall löst `CURRENT` nicht fachlich neu auf. Sie präsentiert `CURRENT` nur, wenn der Conversation-Resolver bereits eine validierte Darstellung in den Turn-Kontext aufgenommen hat.
- Für `queryDetailValues` wird ein decodierter Conversation-Alias vor der Query-Plan-Erzeugung zentral in einen `GraphChatResolvedConversationScope` überführt. Dieser Value-Type bindet Graph, Chat-Scope, Conversation, optionalen Quell-Turn, Result-Revision beziehungsweise validierten Query-Plan, konkrete Entity und revalidierte Nodes.
- Bei homogenen Referenzen stammt die Query-Entity aus diesem App-Scope; der Modell-Entity-Alias bleibt ein untrusted Hint. Vor der eigentlichen Query werden Result-Gültigkeit, Nodes, Entity und aktiver Scope erneut validiert.
- Gemischte Entity-Mengen werden im Preflight in eine typisierte, lokalisierte Pending Clarification mit Anzeigenamen und Mengen aufgeteilt. Erst die ausgewählte, erneut revalidierte Entity-Teilmenge darf als `CURRENT` in einen Provider-Turn gelangen.
- Prompt-Anweisungen bleiben unterstützend, sind aber nicht die Sicherheitsgrenze.

### Request-gebundener Tool-Repair

Pfade:

- `BrainMesh/GraphChat/Provider/GraphChatToolRepair.swift`
- `BrainMesh/GraphChat/Provider/GraphChatModelToolRuntime.swift`
- `BrainMesh/GraphChat/Provider/GraphChatProviderContextRetry.swift`
- `BrainMesh/GraphChat/Provider/GraphChatProviderSessionFactory.swift`
- `BrainMesh/GraphChat/Observability/GraphChatObservability.swift`

Vertrag:

- Repair-fähig sind ausschließlich klassifizierte semantische Schemafehler wie unbekannte Entity-/Feldnamen, Field-Entity-Mismatches, typinkompatible Operatoren und Konflikte mit einer revalidierten typisierten Conversation-Referenz.
- Nicht repair-fähige Fehler besitzen eine eigene Taxonomie für Graph-/Scope-Verletzungen, Repository-/Storage-Fehler, Cancellation, Session-/Turn-Mismatch, manipulierte technische IDs, stale Conversation-Referenzen und Sicherheits-/Tool-Budgets.
- Ein `GraphChatProviderRecoveryCoordinator` gehört zum Nutzerturn und wird bei einem Context-Window-Recovery in die neue Provider-Session übernommen. Er erlaubt höchstens einen Context-Retry und einen Tool-Repair-Versuch innerhalb eines gemeinsamen begrenzten Recovery-Zustands.
- Führt der Context-Retry einen bereits angebotenen Repair fort, behält die Recovery-Session die ursprünglichen per-Tool Ergebnis- und Evidence-Grenzen bei, damit ein zuvor gültiger vollständiger Tool-Call nicht allein durch den Sessionwechsel scheitert. Der engere Recovery-Call-Cap bleibt erhalten; ohne Pending Repair gilt weiterhin das vollständig komprimierte Recovery-Budget.
- Das Repair-Ergebnis enthält nur Argumentpfad, erwartete Kategorie beziehungsweise Datentyp, validierte Entity-/Feldkandidaten, typkompatible Operatoren und gegebenenfalls eine ID-freie Darstellung des revalidierten `CURRENT`.
- Kandidaten stammen ausschließlich aus dem aktuellen `GraphSchemaContext` und werden bei Feldhinweisen auf die ausgewählte beziehungsweise typisiert revalidierte Entity begrenzt. Ähnlichkeit erzeugt nur Hinweise und niemals eine appseitige automatische Auswahl.
- Der korrigierte Tool-Call durchläuft erneut die vollständige Plan-, Scope-, Repository-, Evidence- und Budgetvalidierung. Ein zweiter semantischer Fehler liefert einen sicheren terminalen Repair-Status; ein weiterer Repair wird nicht angeboten.
- Repair-Observability protokolliert nur Outcome, Tooltyp, Fehlerklasse und Context-Retry-Zähler; Fragen, Werte, Namen und technische IDs werden nicht geloggt.

### Deterministische Primary-Result-Retention

Pfade:

- `BrainMesh/GraphChat/Provider/GraphChatPrimaryResultLedger.swift`
- `BrainMesh/GraphChat/Provider/GraphChatProviderSessionFactory.swift`
- `BrainMesh/GraphChat/Provider/GraphChatProviderSessionResources.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatRequestPipeline.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatAnswerFinalizer.swift`

Vertrag:

- Jeder Provider-Request erhält ein actor-isoliertes, nicht persistiertes Execution Ledger. Es enthält ausschließlich value-only Evidence-/Artifact-Snapshots und Bindungen an Graph, Chat-Scope, Artifact-Session, Request und Artifact-Transaktion.
- Ein Wrapper um den kontrollierten Tool Runner erfasst nur vollständig zurückgekehrte Tool-Responses. Failed- oder Cancellation-Pfade erzeugen keinen Eintrag; ein fehlgeschlagener Context-Retry-Versuch verwirft seine Transaktion vor dem neuen Versuch.
- Primär sind ausschließlich revalidierte `.success`-Ergebnisse mit Evidence beziehungsweise Artifact sowie typisierte `.noResults`-Ergebnisse antworttragender Read-Tools.
- Die stabile Tool-Priorität lautet `queryDetailValues` vor `getNode`, `getNeighbors`, `searchGraph`, `graphStats` und `describeGraphSchema`. Innerhalb desselben Tooltyps steht ein verifiziertes datenhaltiges Success-Ergebnis vor einem leeren No-Results-Ergebnis; bei gleichem Status gewinnt die später vollständig abgeschlossene Ausführung.
- Der Finalizer vereinigt autoritative primäre Referenzen zuerst mit zusätzlich modellseitig genannten, aktuell registrierten Referenzen. Anschließend laufen unverändert Live-Evidence-, Artifact-, Scope-, Session- und Transaktionsvalidierung.
- Ein primäres No-Results-Ergebnis setzt den typisierten Antwortzustand appseitig. Ein primäres Success-Ergebnis kann durch modellseitiges `unsupported`, `clarification` oder fehlerhafte IDs nicht entfernt werden.
- Die Presentation Firewall bleibt die letzte Textgrenze. Eine normale erfolgreiche `.answer` wird nur ausgeliefert, wenn nach Live-Revalidierung mindestens primäre Evidence oder ein primäres Result-Artefakt erhalten ist.

### Deterministischer Answer Fallback

Pfade:

- `BrainMesh/GraphChat/Orchestration/GraphChatDeterministicAnswerFallbackPolicy.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatDeterministicAnswerFallbackRenderer.swift`
- `BrainMesh/GraphChat/Orchestration/GraphChatAnswerFinalizer.swift`
- `BrainMesh/GraphChat/Core/GraphChatResponseLanguage.swift`
- `BrainMesh/GraphChat/UI/GraphChatPresentationModels.swift`

Vertrag:

- Der Renderer akzeptiert ausschließlich Evidence und Artifacts, die zugleich zum appseitig gewählten Primärergebnis gehören und die abschließende Live-Revalidierung überstanden haben. Modell-IDs, Modelltext und nicht primäre Tool-Ergebnisse sind keine Renderquelle.
- Unterstützte Artefaktformen werden typisiert und begrenzt zusammengefasst: Listen und Tabellen, Node-Details, Count/Metric, Gruppierungen, Vergleiche, Graph-Health-Befunde, Rankings sowie Timelines und Datumsintervalle. Pro Antwort werden höchstens drei Artefakte und je Artefakt höchstens drei Beispiele dargestellt.
- Anzeigenamen, bereits typisierte Fachwerte, Einheiten und lokalisierte Datums-/Zahlenformate sind die einzigen sichtbaren Daten. Aliase, UUIDs, technische Enum-Rohwerte und Debug-Beschreibungen werden nicht gerendert.
- Fallback-Auslöser sind leerer oder Whitespace-only Modelltext, technische Fehlertexte, ein Widerspruch zwischen behaupteter Leermenge beziehungsweise Anzahl und Primärergebnis sowie jede Ablehnung durch die Presentation Firewall. Eine sichere, konsistente Modellantwort bleibt unverändert.
- Der Fallback behält die revalidierten primären Evidence-/Artifact-Referenzen, entfernt aber modellgenerierte Sections, Follow-ups und Filterdarstellungen. So kann untrusted Zusatztext nicht neben der sicheren Mindestantwort verbleiben.
- Clarification, No Results, Unsupported und Failure werden nicht zu `.answer` konvertiert. Eine normale `.answer` ist dagegen immer nicht leer, presentation-sicher, mit dem erfolgreichen Primärergebnis vereinbar und mit Evidence oder Result-Artefakt verbunden.
- Unmittelbar vor der Fallback-Erzeugung wird Cancellation erneut geprüft. Der bestehende Generation-/Terminal-State-Vertrag verhindert verspätete Fallbacks und doppelte Completion.
- `GraphChatAssistantMessageState` normalisiert auch alternative oder Test-Producer defensiv: leere sichtbare Texte erhalten einen zustandsspezifischen lokalisierten Text, Failure-Texte werden aus dem Fehlercode neu aufgebaut, und Copy liest exakt denselben finalen Answer-State wie die UI.

### Nicht gehaltene Utility Tasks

Beispiel:

- `BrainMesh/Settings/SyncMaintenanceView.swift` startet Cachegrößenarbeit detached.

Risiko:

- View kann verschwinden, bevor Ergebnis zurückkehrt.
- Stale Result überschreibt neuere Messung.

Maßnahme:

- Task Handle oder `.task(id:)`;
- Generation Token;
- Cancellation vor UI-Publikation prüfen.

## 7. Refactor Map

## 7.1 Konkrete Dateisplits

### Search Indexer

Aus:

- `BrainMesh/Search/Index/GraphSearchIndexer.swift`

Nach:

- `GraphSearchIndexCoordinator.swift`
  - öffentlicher Status, Start/Stop, Eventstream-Lifecycle.
- `GraphSearchFullRebuildWorker.swift`
  - paginierter Snapshot → Staging-Generation.
- `GraphSearchMutationPlanner.swift`
  - `GraphMutationBatch` → präzise Source-Operationen.
- `GraphSearchMutationExecutor.swift`
  - lädt betroffene Sources und schreibt atomar.
- `GraphSearchIndexGapRecovery.swift`
  - Sequenzlücken und Overflow → Rebuild.

Nicht nur Extensions:

- Worker erhalten immutable Dependencies.
- Planner bleibt pure/`nonisolated`.
- Coordinator besitzt als Einziger mutable Lifecycle-State.

### Search Store

Aus:

- `GraphSearchIndexStore+Schema.swift`
- `GraphSearchIndexStore+Operations.swift`
- `GraphSearchIndexStore+SourceManifest.swift`

Nach:

- `GraphSearchDatabaseLifecycle.swift`
  - URL, Open, PRAGMAs, Quick Check.
- `GraphSearchSchemaMigrator.swift`
  - Application ID, Schema-Version, DDL.
- `GraphSearchRecoveryPolicy.swift`
  - Rebuild-Entscheidung und Quarantäne.
- `GraphSearchDocumentRepository.swift`
  - Document CRUD.
- `GraphSearchQueryRepository.swift`
  - FTS/Fallback-Queries.
- `GraphSearchManifestRepository.swift`
  - Source-Manifeste.
- `GraphSearchRowCodec.swift`
  - bind/decode ohne DB-Lifecycle.

### Graph Chat Tool Runtime

Aus:

- `BrainMesh/GraphChat/Provider/GraphChatModelToolRuntime.swift`

Nach:

- `GraphChatToolSession.swift`
  - Scope, Gesamtbudget, Aliasregistry.
- `DescribeGraphSchemaToolHandler.swift`
- `SearchGraphToolHandler.swift`
- `QueryDetailValuesToolHandler.swift`
- `GetNodeToolHandler.swift`
- `GetNeighborsToolHandler.swift`
- `GraphStatsToolHandler.swift`
- `GraphChatEvidenceAssembler.swift`
- `GraphChatArtifactAssembler.swift`

Invariante:

- Jeder Handler erhält unveränderlichen `GraphChatToolContext`.
- Scopeprüfung sitzt vor jedem Repositoryzugriff.
- Gemeinsames Budget wird nur im Sessiontyp mutiert.

### FoundationModels Provider

Aus:

- `BrainMesh/GraphChat/Provider/FoundationModelsGraphChatProvider.swift`

Nach:

- `FoundationModelsAvailability.swift`
- `FoundationModelsGenerableContracts.swift`
- `FoundationModelsToolAdapters.swift`
- `FoundationModelsSessionActor.swift`
- `FoundationModelsStreamAdapter.swift`
- `FoundationModelsErrorMapper.swift`

### Chat UI

Aus:

- `BrainMesh/GraphChat/UI/GraphChatViewModel.swift`
- `BrainMesh/GraphChat/UI/GraphChatMessageActionController.swift`

Nach:

- `GraphChatPresentationState.swift`
- `GraphChatLifecycleController.swift`
- `GraphChatComposerController.swift`
- `GraphChatGenerationStateMachine.swift`
- `GraphChatEditController.swift`
- `GraphChatRetryController.swift`
- `GraphChatFeedbackController.swift`

### Canvas Physics

Aus:

- `BrainMesh/GraphCanvas/Physics/GraphPhysicsRuntime.swift`

Nach:

- `GraphPhysicsSimulationActor.swift`
  - Step und Workspace off-main.
- `GraphPhysicsCadenceScheduler.swift`
  - Zeitplanung/Lifecycle.
- `GraphPhysicsSnapshotPublisher.swift`
  - Coalescing und MainActor Commit.
- `GraphPhysicsExternalStateReconciler.swift`
  - Drag-/Scope-/Input-Resync.

Voraussetzung:

- Messbare Frame-/Determinismus-Baseline.

## 7.2 Cache- und Index-Ideen

| Cache | Key | Value | Invalidation |
|---|---|---|---|
| Home Entity Page | `(graphID, query, sort, cursor, pageSize, revision)` | Entity Summary DTOs | Entity create/update/delete; Graph delete |
| Home Counts | `(graphID, aggregateRevision)` | Counts pro Entity | Attribute/Link/Entity-Mutation |
| Health Summary | `(graphID, healthRulesVersion, revision)` | Issues + Scores | Jede healthrelevante Mutation |
| Media Preview | `(graphID, ownerKind, ownerID, limits, mediaRevision)` | IDs + Counts | Attachment create/update/delete |
| Detail Schema | `(graphID, entityID, schemaRevision)` | Field Definition DTOs | Detail schema mutation |
| Canvas Static Snapshot | `(graphID, topologyRevision, focusPlan)` | Labels, Endpoint Map, Draw Edges | Node/Link/Focus-Mutation |
| Search Manifest Root | `(graphID, sourceRevision)` | Generation + Root Hash | committed Mutation oder Remote-Reconcile |
| Chat Schema Snapshot | `(graphID, schemaRevision)` | read-only Schema DTO | Detail schema/entity mutation |

Designregeln:

- Cachewerte sind `Sendable`-DTOs, keine SwiftData-Models.
- Revision gehört in den Key; keine zeitbasierte Korrektheit.
- TTL ist nur Speicherpolitik, nicht Konsistenzmechanismus.
- Bei Event-Overflow wird eine ganze Graphrevision invalidiert.
- Remote CloudKit-Änderungen aktualisieren Revision über Reconciliation.

## 7.3 Vereinheitlichungen

### Repositories und Stores

- Schreibzugriff:
  - Mutation Service plant fachliche Änderung;
  - `GraphMutationCommitter` speichert;
  - post-commit Side Effects reagieren auf Batch.
- Lesezugriff:
  - `GraphReadRepository` für graphweite Snapshots;
  - kleine, fachliche Repositories für Detailabfragen;
  - keine UI-eigenen ungescopten Fetchdeskriptoren.

### Dependency Injection

- Shared Singletons nur an Composition Root verwenden.
- Services über Protokolle und immutable Dependencies konstruieren.
- Feature-Subtrees erhalten einen kleinen Environment-Container.
- Test doubles pro Boundary, nicht pro konkrete Datei.

### Scope-Typen

- `GraphScopedID<EntityKind>`.
- `GraphMutationScope`.
- `GraphRoute`.
- `GraphSourceID`.

Ziel:

- Ein Aufruf ohne Graph Scope soll möglichst nicht typisieren.

### Fehlerklassen

- `StorageBootstrapError`
- `GraphScopeIntegrityError`
- `SearchIndexError`
- `TransferIntegrityError`
- `CloudSyncDiagnostic`

Logging darf Fehlerklasse und Operation-ID enthalten, aber keine Nutzinhalte.

## 8. Risiken und Edge Cases

### Datenverlust / Store

- Release-local-only-Fallback erzeugt potenziell einen nicht synchronisierten Datenzweig.
- Fehlende Schema-Migrationsfixtures können Containerstart nach Update verhindern.
- App-level Backfill hilft nicht, wenn der Container vorher nicht geöffnet werden kann.
- Direkte Saves ohne Mutation Event können abgeleitete Zustände stale lassen.
- Import-Crash nach Checkpoint kann einen partiellen Graph hinterlassen, wenn Startup-Cleanup fehlt.

### Multi-Device / CloudKit

- Prozesslokale Events sehen Remote-Änderungen nicht.
- Foreground-Reconcile ist eventual, nicht sofort.
- Gleichzeitige Renames müssen Linklabels/Index auf den finalen Zustand reconciliieren.
- Delete versus Update kann skalare, verwaiste Referenzen erzeugen.
- Exakte fachliche Konfliktsemantik ist **UNKNOWN U10**.
- Kein CKShare-/Collaboration-Code gefunden; der aktuelle Entwurf ist private-DB-zentriert.

### Graph Scope

- Optionale `graphID` erlaubt Legacyzustände in normalen Fetches.
- ID-only Route kann falschen Graphdatensatz auflösen.
- Attachment-Migration ist lazy.
- Import/Dedupe muss ID-Kollisionen und Scopekonsistenz gemeinsam prüfen.

### Medien

- Große `imageData`/`fileData` erhöhen Store-/CloudKit-Last.
- Local Cache kann fehlen und muss rehydriert werden.
- Cachedatei kann vorhanden, autoritatives Binary aber defekt oder nil sein.
- Cache in Gerätebackup kann Backupgröße unnötig erhöhen.
- Video-Kompression kann bei Background/Low Storage abbrechen.

### Search

- Eventverlust oder -overflow macht Index stale bis Reconcile.
- Vollrebuild kann bei großem Graph Peak Memory erzeugen.
- FTS5-Fallback muss semantisch ausreichend ähnlich bleiben.
- Builder-/Manifest-Schema-Drift kann falsche „unverändert“-Entscheidung erzeugen.
- Breite Home-Suche kann nach Index-Cap auf SwiftData-Fallback wechseln.

### Canvas

- MainActor-Physics kann Gesten und Animationen blockieren.
- Scopewechsel während Simulation kann alte Positionen publizieren.
- Fokus-/Lens-Filter und defensive Endpoint-Fallbacks können Edge-Rendering abweichen lassen.
- Node-/Link-Caps bedeuten unvollständige Visualisierung großer Graphen; UI muss dies klar kommunizieren.

### Graph Chat

- Generierte Antwort darf keine nicht belegten Node-Referenzen als Fakten präsentieren.
- Toolbudget kann Teilantworten erzeugen.
- Alias kann nach Delete/Rename stale sein; die turn-gebundene Registry verhindert Roh-Ausgabe, ersetzt aber keine fachliche Revalidierung.
- Comparison-Subjects und -Values können zwischen Compilation und Live-Revalidierung verschwinden. Die lokale Factory/Revalidation entfernt unbelegte Values und verwirft das gesamte Artifact, sobald weniger als zwei Subjects oder kein Feature verbleibt.
- Graph-State-Fragen in Entity-, Node- oder Selection-Chats werden bewusst abgelehnt; ein automatisches Hochstufen auf den Entire-Graph-Scope wäre ein Datenzugriffsfehler.
- Eine unbekannte technische Referenz führt bewusst zur vollständigen lokalisierten Ersatzantwort statt zu einer partiellen Ausgabe.
- Lock/Background muss History, Artifacts und Provider Session vollständig invalidieren.
- Indexunverfügbarkeit darf nicht als „keine Daten“ interpretiert werden.
- Die Authoritative-Fact-Policy schützt nur sicher kompilierte Single-Node-Field-Turns. Nicht erkannte freie Fachfragen und offene Erklärungen bleiben außerhalb einer allgemeinen semantischen Wahrheitsprüfung.

### Security

- Graph-Sicherheitsfelder liegen teils auf Graph und Nodes.
- Security-Saves sind bewusst vom Graph-Content-Event Bus ausgenommen.
- Änderungen dürfen trotzdem Chat-/Navigation-State sofort invalidieren.
- Passwortparameter und Migrationspfad müssen bei künftiger Änderung kompatibel bleiben.

### Repository Hygiene

- Außerhalb des App-Ordners existiert `Mainscreen/EntitiesHome/Cockpit/EntitiesHomeRecentNodesLoader.swift`.
- Die Datei ist byte-identisch zu `BrainMesh/Mainscreen/EntitiesHome/Cockpit/EntitiesHomeRecentNodesLoader.swift`.
- Sie liegt nicht in der synchronisierten App-Gruppe.
- `BrainMeshTests/GraphMutationWritePathInventoryTests.swift` markiert drei produktive Dateien als unreferenziertes Legacy:
  - `BrainMesh/NotesAndPhotoSection.swift`;
  - `BrainMesh/Mainscreen/NodeLinksSectionView.swift`;
  - `BrainMesh/GraphPicker/GraphPickerRenameSheet.swift`.
- **UNKNOWN U8**: Ob diese Dateien bewusst als historische Referenz behalten werden.

## 9. Observability und Debuggability

### Vorhanden

Pfad: `BrainMesh/Observability/BMObservability.swift`

- `Logger`-Kategorien für Load, Expand, Physics, Canvas-Derived-State, Canvas-Static-Render, Search, Mutation Events, Detail-Integrity und Chat.
- Detail-Integrity loggt ausschließlich technische Zähler beziehungsweise Fehlerklassen: migrierte Definitions/Values, reparierte Owner-IDs, sichere Duplikatlöschungen, Konfliktgruppen, Cross-Graph-Ablehnungen und verwaiste/mehrdeutige Records. Namen, Notizen und Detailwerte werden nicht geloggt.
- Dauerhelfer.
- Debug-Signposts für Connections-/Media-Preview-Pfade.
- Search loggt Open/Rebuild/Reconcile mit Mengen und Dauer.
- Canvas loggt Physics-/Derived-/Static-Metriken.
- Graph Chat loggt content-free technische Metriken:
  - Dauer;
  - Toolkategorien;
  - Evidence Count;
  - Outcome/Error;
  - Authoritative Fact erkannt/gerendert;
  - Modelltext ersetzt beziehungsweise Search-only-Behauptung blockiert;
  - Fact wegen fehlendem Wert, Mehrdeutigkeit, Integrity-Konflikt oder Revalidation verworfen.
- Lokale Typed-Intent-Observability protokolliert ausschließlich Intent-Art und Lifecycle-Outcome: Foundational-Adaption, Start, Commit, Rollback, Revalidation-Ablehnung, verhinderte Scope-Erweiterung, verworfenen stale Node und Cancellation vor Commit. Fragen, Anzeigenamen, Werte, Aliasse, IDs und Antworttexte sind ausgeschlossen.
- Semantic-Intent-Observability protokolliert ausschließlich Interpreter-Start, Draft akzeptiert/abgelehnt, Find/List/Query/Node Details kompiliert, Same-Entity-/Structural-Comparison, Comparison-Ablehnung, Graph Overview/Health, Scope-/Stale-Ablehnung, Clarification, Legacy-Provider-Fallback und Cancellation sowie getrennte Interpreter-/Answer-Provider-Aufrufzähler. Draftinhalt, Fragen, Suchbegriffe, Anzeigenamen, Aliasse, IDs und Antworttexte sind ausgeschlossen.
- Typed-Planner-Observability protokolliert ausschließlich Foundational Fast Path, Semantic Interpreter, Draft Outcome, lokale Intent-Familie, Legacy-Fallback-Grund, Compact-Retry, Clarification, Correction Rerun, Terminal Outcome und Cancellation Stage. Associated Values sind nur geschlossene Enum-Kategorien; Fragen, Namen, Filter-/Fachwerte, Aliasse und IDs sind im Vertrag nicht darstellbar.
- Binding-Observability protokolliert ausschließlich `entityNotBound`, `nodeNotBound`, `fieldNotBound`, `multiplePlausibleCandidates` oder `invalidDraftCombination`. Der Metrikvertrag kann keine Frage, Erwähnung, Anzeigenamen, Notiz, Feldwerte, Aliasse oder IDs aufnehmen.
- Authoritative-Fact-Metriken enthalten ausschließlich die technische Outcome-Kategorie. Fragen, Antworten, Namen, Fachwerte, Aliasse und IDs werden nicht protokolliert.
- Settings zeigt Storage-Modus, iCloud-Accountstatus und Cachegrößen.

### Fehlende Signale

- kein expliziter „last successful CloudKit import/export“-Zeitstempel;
- keine CloudKit-Fehlerhistorie in der App;
- kein sichtbarer Search-Index-Generation-/Reconcile-Status;
- keine durchgängige Operation-ID für Transfer;
- kein Support-Diagnostics-Bundle;
- keine P50/P95-Metrikbasis für reale große Graphen;
- kein persistenter Hinweis auf partiellen Import nach Crash.

### Empfohlene technische Events

#### Storage

- `storage.container_open`
  - mode, duration, result, errorClass, storeIdentityHash.
- `storage.fallback_entered`
  - previousMode, reasonClass.
- `storage.migration`
  - fromVersion, toVersion, duration, itemCounts, result.

#### CloudKit

- `sync.account_status`
- `sync.remote_change_observed`
- `sync.reconciliation_scheduled`
- `sync.reconciliation_completed`
- Keine Graphnamen, Notes oder Dateinamen loggen.

#### Search

- current generation;
- source count;
- document count;
- manifest diff count;
- rebuild reason;
- peak batch size;
- time to first result.

#### Canvas

- Tick P50/P95/max;
- Publish P50/P95;
- Dictionary copy time;
- Canvas dynamic-frame time;
- skipped/fallback edge count;
- visible node/link count.

#### Transfer

- Operation-ID;
- Paketversion;
- Record-/Attachmentanzahl;
- Byteanzahl;
- Checkpointnummer;
- Cleanup Result;
- Fehlerklasse.

### Reproduktionsmatrix

#### Sync

- Gerät A online → Änderung → Gerät B online.
- Gerät B offline → parallele Änderung → beide online.
- Appstart ohne iCloud → lokale Änderung → iCloud wieder an.
- Delete auf A, Rename auf B.
- großes Attachment parallel ändern/löschen.

#### Migration

- leerer Store;
- Store aus jeder produktiven Vorversion;
- Legacy-Daten mit `graphID == nil`;
- orphaned Attachment Owner;
- unterbrochener Backfill;
- CloudKit-Import während Reconcile.

#### Performance

- 1.000/10.000/100.000 Domainrecords im Store;
- Canvas jeweils am Cap 140/800;
- Home leerer Query mit großer Entitymenge;
- Search Full Rebuild;
- 500+ Attachments pro Owner;
- mehrere große External-Storage-Dateien.

Die realistischen Obergrenzen sind **UNKNOWN U7** und müssen produktseitig festgelegt werden.

## 10. Teststrategie

### Bereits stark abgedeckte Bereiche

- Mutation Write Path Inventory.
- Search Index Store, Indexer, Reconciliation und Dokumentbildung.
- Graph Transfer, Import und Cleanup.
- Detaildaten-Authority mit In-Memory-`ModelContainer`, Bootstrap, UI-Formatierung, Repository, Graph Chat und Search-Reconciliation.
- Graph Canvas Physics/Derived State.
- Graph Chat Provider, Query, Conversation, Tools und UI-Controller.
- Foundational Intent Compiler, Authoritative-Fact-Extraktion/-Rendering, Finalizer-Ersatzpfade, UI-/Copy-Vertrag und gebündelte Foundational-Accuracy-Akzeptanzszenarien.
- Typed-Intent-Domainverträge, verlustfreie Foundational-Adaption, Kernel-Cleanup bei Artifact-Staging- und äußerem Commit-Fehler sowie End-to-End-Parität für Geburtstagsfrage und vollständige Reisenliste.
- Semantic-Draft-/Validator-/Resolver-Verträge, begrenzter nutzersichtbarer Interpreter-Kontext, technische-Identifier-Ablehnung, Scope-Erhalt, zentrale Find-/List-Limits, Search-Evidence-Grenze und content-free Observability.
- Zentrales Mention Grounding mit Medizin-, Bibliotheks- und IT-Operations-Fixtures: deutsche/englische Flexion, Interpunktion, Unicode, Umlaute/ß, konservative Tippfehler und Fuzzy-Abstandsregel, gleichnamige Nodes/Felder, Promptgrenzen, Entity-/Node-/Selection-Scope, Cross-Graph-Kollisionen, content-free Binding-Diagnosen und providerfreie Entity-List-/Node-Details-Basispfade.
- In-Memory-End-to-End-Pfade für natürliche Node-Suche und freie Entity-Liste einschließlich Artifact, `CURRENT`, Truncation, Clarification, Cancellation, atomarem Rollback und Legacy-Provider-Fallback.
- Appseitige Query-Intent-Compilation für alle sieben Feldtypen, deutsche/englische Zahlen-, Boolean- und Datumswerte, Operator-Matrix, Choice-Bindung, Field-Entity-Mismatch, gleichnamige Feld-Clarification, Node-Identity-Projektion, Sortierung, Count-/Group-Artefakte, vollständige Group References und evidence-gebundene Limits.
- In-Memory-End-to-End-Pfade für offene Projekte nach Fälligkeitsdatum, Count, Group Count, sichere Gruppenfortsetzung und überfälliges Refinement als exakte Schnittmenge; ausgeschlossene und graphfremde Nodes bleiben ausgeschlossen, erfolgreiche Compilation startet keinen freien Provider und Cancellation committed nichts.
- In-Memory-End-to-End-Pfade für eindeutige und mehrdeutige Node Details, Clarification-Auswahl, Last Node, Ordinal, Cross-Graph-Ablehnung, appseitiges Related-Limit und ausgeschlossene Attachment-Inhalte.
- Repository-Profile für Entity und Attribute aus Medizin, Bibliothek und IT-Operations: vollständige kleine Bereiche, getrennte Detail-/Incoming-/Outgoing-/Attachment-Windows, Konkurrenzfreiheit der Bereiche, korrekte Gegenknoten und Richtungen, stabile Tie-Breaker, leere Bereiche, Detail-Integrity, Metadaten ohne Binärinhalt und Cancellation während des mehrteiligen Loads.
- Link-Notiz-Authority für den Wert „3× täglich“ einschließlich Endpoint-/Richtungsbindung, Änderung, Entfernung, Link-Löschung und identischer Link-ID in einem anderen Graphen.
- Node-Profile-Artifact-Domain und Factory für vollständige, Notiz-only, Link-only und Attachment-only Profile; deutsche und englische gemeinsame Präsentation, identischer UI-/Copy-Link-Notiztext, getrennte konkrete Truncation-Hinweise, keine UUIDs/Aliasse/UTIs, bereichsweise Evidence-Projektion und echte Live-Revalidierung mit erhaltenem gültigem Rest.
- Medizinische Vollantwort für Patient A mit allen Detailwerten, Node-Notiz, Medikament 3, „3× täglich“ und Attachment-Metadaten sowie bibliothekarische Autorin- und technische Service-Fixtures über dieselbe generische Factory. Foundational Fast Path und semantisch kompilierter Pfad liefern denselben Payload und Antworttext ohne Answer Provider.
- Same-Entity-Comparison mit expliziten Feldern, gepinnter/default-sortierter Featureauswahl, autoritativen typisierten Values, `.missing`, Integrity-/Evidence-Ausschluss, graphgescopter Navigation, `lastComparison`, `lastCompared` und Comparison-`CURRENT`.
- Structural Comparison über gemischte Node-Arten ausschließlich aus Node-Art, Owner, direkten Links, Attachment-Metadatenzahl, Notiz-Vorhandensein und autoritativer Detailwertzahl; Notiz-/Attachment-Inhalte bleiben ausgeschlossen.
- Graph-State-Artifact-Auswahl für Overview, Counts, Structure und Health sowie End-to-End-Graph-Health mit Metric/Health Finding, appseitigem Hub-Limit und verhindertem Scope-Widening.
- Zentrale Comparison-Plan-Limits für Nodes und Features sowie providerfreie lokale Finalisierung und genau ein terminales Event in den Advanced-Intent-End-to-End-Szenarien.
- Interpretation-Correction-Verträge, intent-spezifische Editorfelder, vollständige Schema-/Scope-/Session-Revalidation, typisierte Choice-/Toggle-/Zahl-/Datum-Filter, Operator-Kompatibilität, Entity-/Node-/Comparison-/Refinement-/Graph-State-Sicherheitsgrenzen, Doppelbestätigungs-Latch, Checkpoint-/Suffix-/Feedback-Replacement, deferred Artifact-Swap, Cancellation-/Commit-Rollback und Single-Terminal-Vertrag. Der End-to-End-Pfad ersetzt „Offene Projekte, sortiert nach Name“ durch die lokal ausgeführte Fälligkeitsdatum-Sortierung; Interpreter bleibt bei einem Aufruf, Answer Provider bei null und `CURRENT` enthält nur das neue Resultset.
- `GraphChatTypedIntentPlannerAcceptanceTests` bündelt 18 benannte In-Memory-Akzeptanzszenarien: Foundational Single Fact, Natural Find/List, Filter/Sort, Count, Group, Refinement, Node Details, Comparison, Graph State, Clarification, Interpretation/Copy, Correction, Draft-Manipulation, Open-Ended-Fallback, Sicherheitsbindungen, Cancellation und große Schemas mit Standard-/Compact-Recovery. Zusätzliche End-to-End-Tests belegen genau zwei Interpreter-Aufrufe beim Compact-Retry, keinen Retry nach Draft, keinen Provider bei Draft-Manipulation sowie keinen verspäteten Comparison-Commit.

### Ergänzungen

- echte SwiftData-Migrationstests mit alten Storedateien;
- CloudKit-Container-Startmatrix auf Gerät;
- Release-local-only → CloudKit-Recovery;
- graphgescopte Navigation bei kollidierenden IDs;
- Lazy Attachment Migration vor Export/Delete/Stats;
- Event-Bus-Overflow → Full-Rebuild;
- Crash nach jedem Import-Checkpoint;
- MainActor Frame-Budget mit XCTest Metrics/OSSignposter;
- Cache-Backup-Exclusion-Test;
- Graphwechsel während Chatstream und Physics-Publish.
- Die vollständige iOS-26-Xcode-Suite einschließlich Swift-6-/Concurrency-Diagnostics muss in einer macOS-/Xcode-Umgebung laufen; die bereitgestellte Analyseumgebung besitzt weder `xcodebuild` noch `swiftc`.

### CI Guards

- Neue `ModelContext.save()`-Stellen müssen im Inventar klassifiziert sein.
- Ungescopte Fetches nach `id` in Route-/Service-Dateien melden.
- Jede neue `@Model`-Property verlangt Migration-/Export-/Search-Checklist.
- Top-Dateigrößen und Compile-Zeit als Trend reporten, nicht hart blocken.
- `.xcconfig`/Entitlement-/Container-Identifier-Konsistenz testen.

## 11. Typische Feature-Workflows

### A. Neues indexiertes Feld

- [ ] Model und Migration ergänzen.
- [ ] Normalisierung/Folded-Semantik definieren.
- [ ] Mutation Kind für Create/Update/Delete wählen.
- [ ] Document Builder aktualisieren.
- [ ] Source Manifest Hash aktualisieren.
- [ ] Query/Ranking/Evidence prüfen.
- [ ] Reconcile eines alten Indexes testen.
- [ ] Graph Transfer und Backupformat prüfen.
- [ ] Graph Chat Schema/Tools prüfen.

### B. Neue Graphmutation

- [ ] Graph Scope am API-Eingang verlangen.
- [ ] Fachliche Invarianten vor Mutation prüfen.
- [ ] Betroffene SwiftData-Records in einem Kontext ändern.
- [ ] Minimalen `GraphMutationBatch` bauen.
- [ ] Über Committer speichern.
- [ ] Post-commit Cache-/Dateisystem-Side-Effects planen.
- [ ] Save-Fehler und Cancellation testen.
- [ ] Mutation Inventory ergänzen.

### C. Neuer Loader

- [ ] Konfiguration über `AppLoadersConfigurator`.
- [ ] `ModelContext` im ausführenden Actor/Task erstellen.
- [ ] Nur Value-DTOs zurückgeben.
- [ ] `fetchLimit`/Paging definieren.
- [ ] Sortierung und Aggregation nicht im SwiftUI-Renderpfad.
- [ ] Cancellation je Batch prüfen.
- [ ] Graph Scope und stale-result Token prüfen.
- [ ] Dauer und Result Count loggen.

### D. Neuer Screen oder Flow

- [ ] besitzenden `NavigationStack` festlegen;
- [ ] Route enthält `graphID`;
- [ ] Sheet-/Push-Lifecycle definieren;
- [ ] Graphwechsel und Lock behandeln;
- [ ] Task-Handles an View-/Coordinator-Lifetime binden;
- [ ] Pro-Entitlement und iPad-Layout prüfen;
- [ ] UI-Test für Einstieg, Abbruch und Rücknavigation.

## 12. Open Questions

- **UNKNOWN U1 – CloudKit Schema**
  - Welche Development- und Production-Schemas sind deployed?
  - Wer genehmigt additive/kompatible Änderungen?
  - Gibt es ein Rollback-/Recovery-Runbook?
- **UNKNOWN U2 – Local-only Recovery**
  - Welche Store-URL öffnet SwiftData je Modus?
  - Wie werden local-only Änderungen später mit CloudKit zusammengeführt?
  - Muss der Nutzer explizit exportieren/importieren?
- **UNKNOWN U3 – Migrationsbasis**
  - Welche Appversionen sind produktiv?
  - Gibt es anonymisierte oder synthetische Store-Fixtures?
- **UNKNOWN U4 – APNs Distribution**
  - Welche `aps-environment` steht nach Signing im finalen Archiv?
- **UNKNOWN U5 – StoreKit Scheme**
  - Wird `BrainMesh/BrainMesh Pro.storekit` manuell oder in CI aktiviert?
- **UNKNOWN U6 – Setup/CI**
  - Development Team, CloudKit Dashboard, Testaccounts, CI-Schritte und Secret-Injection.
- **UNKNOWN U7 – Daten- und Performancebudgets**
  - maximale Entities/Attributes/Links;
  - maximale Attachmentanzahl/-größe;
  - Zielgeräte und P95-Latenzen.
- **UNKNOWN U8 – Legacy-Dateien**
  - externes exaktes Duplikat und drei im Testinventar als unreferenziert markierte Dateien.
- **UNKNOWN U9 – Backup Policy**
  - Sollen `BrainMeshImages` und `BrainMeshAttachments` in Gerätebackups enthalten sein?
- **UNKNOWN U10 – Konfliktsemantik**
  - erwartetes Verhalten für Update/Update, Update/Delete und Rename/Linklabel auf mehreren Geräten.
- **UNKNOWN U11 – Attachment Migration**
  - Decken Export, Delete, Stats, Search und Backup ungeöffnete Legacy-Attachments mit `graphID == nil` ab?

## 13. First 3 Refactors I would do

### P0.1 – Versionierte Persistenz- und Migrationsgrenze

**Ziel**

- Aktuellen Store als `VersionedSchemaV1` einfrieren.
- `SchemaMigrationPlan` einführen.
- Produktive Vorgängerstores als Fixtures testen.
- `graphID`-Bereinigung versionieren und später kontrolliert verschärfen.
- Local-only-Fallback als expliziten Recovery-Zustand dokumentieren und instrumentieren.

**Betroffene Dateien**

- `BrainMesh/BrainMeshApp.swift`
- `BrainMesh/Models/MetaGraph.swift`
- `BrainMesh/Models/MetaEntity.swift`
- `BrainMesh/Models/MetaAttribute.swift`
- `BrainMesh/Models/MetaLink.swift`
- `BrainMesh/Models/DetailsModels.swift`
- `BrainMesh/Models/MetaDetailsTemplate.swift`
- `BrainMesh/Attachments/MetaAttachment.swift`
- `BrainMesh/Bootstrap/`
- neue Migration-Fixtures unter `BrainMeshTests/`

**Risiko**

- Hoch: SwiftData-/CloudKit-Schemaänderungen können bestehende Stores unlesbar machen.
- Deshalb zuerst aktuelle Version abbilden und reale Fixtures testen; keine vorschnelle Non-null-/Relationship-Änderung.

**Erwarteter Nutzen**

- Schutz vor Update-bedingtem Datenverlust.
- Reproduzierbare Migrationen.
- Klare Freigabegrenze für Modeländerungen.
- Grundlage für spätere Scope-Härtung.

### P0.2 – Streaming Search Rebuild und kleinere Index-Komponenten

**Ziel**

- Full Rebuild nicht mehr als vollständige Source-/Document-/Manifest-Collections im Speicher halten.
- Sources paginiert in Staging-Tabellen schreiben und Generation atomar umschalten.
- Lifecycle, Planner, Executor, Schema und Row Mapping in testbare Typen trennen.

**Betroffene Dateien**

- `BrainMesh/Search/Index/GraphSearchIndexer.swift`
- `BrainMesh/Search/Index/GraphSearchIndexStore+Operations.swift`
- `BrainMesh/Search/Index/GraphSearchIndexStore+Schema.swift`
- `BrainMesh/Search/Index/GraphSearchIndexStore+SourceManifest.swift`
- `BrainMesh/Search/Index/GraphSearchIndexReconciler.swift`
- `BrainMesh/Search/Index/GraphSearchDocumentBuilder.swift`
- `BrainMesh/DataAccess/GraphReadRepository.swift`
- zugehörige Search-Tests in `BrainMeshTests/`

**Risiko**

- Mittel bis hoch: Atomizität, Cancellation und Recovery dürfen keinen halbfertigen Index sichtbar machen.
- Der bestehende Index ist gut getestet; Refactor muss verhaltensgleich in kleinen Schritten erfolgen.

**Erwarteter Nutzen**

- Niedrigerer Peak Memory.
- Kürzere Foreground-Blockade bei großen Graphen.
- Besser isolierbare SQL-/Rebuild-Fehler.
- Kleinere Review- und Testflächen.

### P0.3 – Strikt graphgescopte Identität und Mutation Boundary

**Ziel**

- Routes, Fetches und Services typseitig auf `graphID + id` verpflichten.
- Direkte Saves/ungescopte Fetches per CI-Guard verhindern.
- Lazy Attachment-Scope-Migration durch einen versionierten, vollständigen Hintergrundjob ergänzen.

**Betroffene Dateien**

- `BrainMesh/DataAccess/GraphScopedFetches.swift`
- `BrainMesh/DataAccess/Mutations/GraphMutationCommitter.swift`
- `BrainMesh/DataAccess/Mutations/GraphMutationEventBus.swift`
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeRoutes.swift`
- weitere Link-/Detail-Routen unter `BrainMesh/Mainscreen/`
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift`
- `BrainMesh/GraphTransfer/`
- `BrainMesh/GraphPicker/`
- `BrainMeshTests/GraphMutationWritePathInventoryTests.swift`

**Risiko**

- Mittel: Legacyrecords, Import-ID-Remapping und vorhandene Deep Links können betroffen sein.
- Migration muss idempotent sein und graphübergreifende Fehlzuordnung sichtbar machen statt still zu raten.

**Erwarteter Nutzen**

- Verhindert Cross-Graph-Datenauflösung.
- Reduziert verwaiste Referenzen und Cache-/Index-Drift.
- Macht neue Features sicherer, weil fehlender Scope früher auffällt.
- Vereinfacht spätere CloudKit- und Import-Diagnose.
