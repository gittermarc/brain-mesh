# PROJECT_CONTEXT.md

## TL;DR

BrainMesh ist eine SwiftUI-iOS/iPadOS-App für graphbasiertes Wissens- und Entitätenmanagement. Die App modelliert mehrere Graphen mit Entitäten, Attributen, Links, Detailfeldern, Bildern und Anhängen. Mindestziel ist iOS 26.0, konfiguriert in `BrainMesh.xcodeproj/project.pbxproj`. Persistenz läuft über SwiftData mit CloudKit (`ModelConfiguration(schema:cloudKitDatabase: .automatic)`) in `BrainMesh/BrainMeshApp.swift`; Release-Builds fallen bei CloudKit-Containerfehlern auf lokalen SwiftData-Speicher zurück.

## Scan Snapshot

- Produktions-Swift: 591 Dateien, 106.220 Zeilen unter `BrainMesh/`.
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
- **Local Graph Search Index**: rekonstruierbarer, graph-scoped Suchindex unter `BrainMesh/Search/Index/`. Er liegt als eigene, vom Backup ausgeschlossene SQLite-Datei in Application Support, nutzt FTS5 mit indexiertem n-Gram-Fallback und gehört weder zum SwiftData-/CloudKit-Hauptschema noch zu GraphTransfer. `GraphSearchIndexer` hält ihn für lokale Mutation Events aktuell; ein deterministisches Source-Manifest und `GraphSearchIndexReconciler.ensureReady` heilen Änderungen, die den lokalen EventBus umgehen. `BrainMeshSearchService.shared` verwendet ihn nach erfolgreicher Readiness-Prüfung als primäre Candidate-Quelle und fällt bei unsicherem oder fehlerhaftem Index transparent auf die SwiftData-Provider zurück.
- **Graph Lock**: optionaler Schutz mit Biometrie und/oder Passwort über Security-Dateien in `BrainMesh/Security/` und Lock-Felder an Graph/Entity/Attribute.
- **Graph Transfer**: Export/Import für `.bmgraph` und `.bmbackup`, implementiert unter `BrainMesh/GraphTransfer/`.
- **Command Center**: globale Suche/Aktionen, UI unter `BrainMesh/Search/CommandCenter/`; `BrainMeshSearchService` orchestriert den indexbasierten `IndexedSearchCandidateProvider`, die unveränderte Ranking-Schicht und den transparenten Legacy-Fallback unter `BrainMesh/Search/Candidates/`.
- **GraphScope / Read Repositories**: `BrainMesh/DataAccess/` stellt eine nicht-optionale Graph-Grenze, zentrale Fetch-Descriptor-Factories und value-only DTO-Repositories für Graph-Snapshots, Node-Lookups und direkte Nachbarschaften bereit.
- **Graph Chat Domain**: `BrainMesh/GraphChat/` enthält die produktiven read-only Stufen 1 bis 3: promptfähige, begrenzte Schema-Snapshots ohne rohe UUIDs, appseitige Alias- und Multi-Turn-Referenzauflösung, strikt validierte Query-Pläne, eine deterministische Query Engine, sechs read-only Tools, revalidierte Evidence, einen flüchtigen strukturierten Conversation State sowie eine value-only Answer-Artifact-Domain mit sessionlokaler Registry. Kennzahlen, Ergebnislisten, Tabellen, Rankings, Gruppierungen, Vergleiche, Health Findings und Timelines werden ausschließlich aus revalidierten App-Daten erzeugt. Der Provider sieht nur opaque IDs aus aktuellen Tool-Aufrufen und darf Artifact-Payloads weder erzeugen noch verändern. Der Conversation State übernimmt ausschließlich appseitig validierte Query-Strukturen, revalidierte Tool-Ergebnisse, stabile Ergebnisreihenfolgen und technische Turn-Zusammenfassungen; ungeprüfter Assistant-Text wird nicht vertraut. Antwort, Klärung, No-Result und Unsupported sind eigene Domain-Zustände, die Sprache wird pro Nutzerfrage deterministisch Deutsch oder Englisch gewählt, und jeder Turn committed State und Artifacts erst nach finaler Evidence-Revalidierung atomar. `GraphChatAccessPolicy` und das unabhängige Execution Gate erzwingen aktiven Graph, exakten Scope, Lock, Pro, Modellverfügbarkeit, Index und Reconciliation. `GraphChatLaunchCoordinator`, `GraphChatSessionStore` und `GraphCopilotWorkspaceCoordinator` integrieren Root-Tab, Command Center, Details, Graph Canvas und Health Findings ohne zweiten Chat-, Canvas- oder Selection-State. Auf regulären iPads bleibt der produktive Canvas sichtbar, während derselbe Chat als adaptiver Inspector geöffnet wird; auf iPhone bleibt die vorhandene Tab-/Navigationsroute bestehen. Die bestehende Canvas-Auswahl wird als sichtbarer, explizit übernehmbarer Selection-Scope angeboten, sodass Auswahländerungen einen laufenden Turn-Snapshot nicht nachträglich verändern. Finale graphnative Antworten rendern registrierte Artifacts, Evidence Chips und Evidence Drawer; Source-, Ergebnis-, Filter-, Highlight-, Auswahl- und Vergleichsaktionen werden unmittelbar vor Ausführung gegen aktiven Graph, Scope und aktuelle Repository-Daten revalidiert. Canvas-Highlights sind flüchtige UI-Präsentation, große Aktionen bleiben zentral budgetiert, und Mutationen des aktiven Graphen lösen eine erneute Präsentationsvalidierung aus. Draft, Verlauf, Conversation State, Registry, Artifact-Payloads, Highlights und Workspace-Kommandos bleiben ausschließlich in Memory und werden bei den jeweiligen Lifecycle- und Security-Grenzen bereinigt. Attachment-Inhalte, Graph-Mutationen, Cloud-Provider, Query Plan v2 und Multi-Hop bleiben ausgeschlossen.
- **GraphMutationEventBus / GraphMutationCommitter**: actor-sicherer Multicast-Bus plus einzige Save-then-Publish-Grenze unter `BrainMesh/DataAccess/Mutations/`. Main-Actor-UI-Pfade und caller-isolierte GraphTransfer-Kontexte verwenden dieselbe Committer-Implementierung. Basis- und zusammengesetzte Mutationen, Graph-Lifecycle, Dedupe, Bootstrap-/Migrations-Reparaturen sowie Import/Replace publizieren ausschließlich technische graph-scoped Post-Commit-Batches. `GraphMutationCacheInvalidationCoordinator` invalidiert die vorhandenen Home- und Stats-Caches zentral und container-idempotent.

## Architecture Map

### App Shell

- `BrainMesh/BrainMeshApp.swift`
  - erstellt das SwiftData-Schema und den `ModelContainer`.
  - konfiguriert CloudKit oder lokalen Fallback.
  - erzeugt App-weite EnvironmentObjects: Appearance, Display, Onboarding, Graph Lock, Pro, Tabs, Jump, Command Center, Recent Nodes, EntitiesHome Routing sowie Graph-Chat-Launch-, Session- und Copilot-Workspace-Koordination.
  - ruft `AppLoadersConfigurator.configureAllLoaders(with:)` auf.
- `BrainMesh/AppRoot/AppRootView.swift`
  - hostet `ContentView`.
  - steuert Startup, Onboarding, Graph Lock, ScenePhase und Image-Hydration.
- `BrainMesh/ContentView.swift`
  - Root `TabView` mit fünf Tabs: Entitäten, Graph, Chat, Stats, Einstellungen.
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
- `BrainMesh/GraphChat/`
  - `Core/` definiert graph-scoped Chat-, Evidence- und Source-Modelle.
  - `Schema/` erzeugt kompakte, deterministisch aliasierte Schema-Snapshots aus `GraphReadRepository`; UUID-Mapping und Node-Zuordnung bleiben ausschließlich appseitig.
  - `Query/` enthält versionierte Alias-Pläne, Kalender-/Zeitzonenauflösung, die einzige Validierungsgrenze für `ValidatedGraphQueryPlan` sowie die deterministische typed-value Query Engine mit Filtern, stabiler Sortierung und Aggregationen.
  - `Evidence/` revalidiert jede zurückgegebene Source gegen SwiftData, aktiven Graph und Chat-Scope; stabile Evidence-IDs verknüpfen Result Rows und Navigation.
  - `Artifacts/` definiert vollständig value-only und `Sendable` typisierte Answer Artifacts, Werte, Evidence-Bindungen und graph-scoped Navigation Targets. Die actor-isolierte, rein flüchtige Registry trennt Graph und Chat-Session, staged Artifacts request-atomar, erzwingt Größen-/Anzahlbudgets und verwirft Inhalte bei neuem Chat, Scope-/Graph-Wechsel, Lock, Delete, Restore, Fehler oder Cancellation.
  - `Tools/` stellt ausschließlich read-only Tools für Schema, lokalen Index, Detailabfragen, Nodes, direkte Nachbarn und bestehende Graph-Stats bereit; zentrale Call-, Result-, Evidence- und Artifact-Budgets gelten pro Nutzeranfrage. Pro Tool-Ausführung kann höchstens ein primäres Artifact aus bereits revalidierten App-Daten entstehen; die modelllesbare Textzusammenfassung bleibt als kompatibler Fallback bestehen.
  - `Provider/` kapselt Availability, Sessions, Foundation-Models-Tool-Calling, Guided Generation und providerunabhängige Stream-Ereignisse. Der Provider erhält keinen rohen Verlauf, sondern ausschließlich den appseitig erzeugten `GraphChatConversationContextSnapshot`; Antwortsprache, Referenzvorschlag und Antwortzustand sind typisiert. `GraphChatModelContextProfile` begrenzt Schema, Conversation-Snapshot und Frage für Standard-, Compact- und Recovery-Läufe; Tool-Ausgaben besitzen ein separates zentrales Zeichenbudget. Die produktive Implementierung verwendet ausschließlich `SystemLanguageModel.default`; Tests verwenden einen vollständig deterministischen Fake-Provider.
  - `Conversation/` definiert den value-only, `Sendable`, graph-/scope-isolierten und zentral budgetierten Conversation State samt einzigem trusted Reducer und request-scoped Transaktion. `GraphChatConversationReferenceResolver` und der Repository-Revalidator lösen Referenzen ausschließlich appseitig auf und erkennen gelöschte Nodes, Graph-/Scope-/Entity-Konflikte sowie veraltete Query-Reihenfolgen und Gruppen. Die lokale Referenzerkennung arbeitet mit Wortgrenzen und expliziten Referenzphrasen; ein bloßes Demonstrativwort wie „diese“ erzwingt keinen Follow-up-State. Fehlt für eine plausible implizite Referenz lokaler Kontext, wird die aktuelle Frage regulär an den Provider weitergegeben statt vorzeitig mit einer Klärung abgebrochen. Ein nicht auflösbarer Missing-Context-Referenzvorschlag des Providers darf eine bereits nutzbare finale Antwort nicht nachträglich durch eine lokale Klärung ersetzen. Der State bleibt ausschließlich in Memory, übernimmt keine Assistant-Antworttexte und speichert eine Nutzerfrage nur begrenzt als nicht-faktische Fortsetzungsinformation einer offenen typisierten Klärung; diese Information wird nicht in den allgemeinen Provider-Snapshot formatiert.
  - `Orchestration/` initialisiert Schema, Provider, request-scoped Tool-Runner, Budget, Evidence-Registry, sessiongebundene Artifact-Registry und Conversation-State-Transaktion, verwirft Sessions, Artifacts und offene Klärungen bei Graph-/Scope-/Lifecycle-Wechsel, erlaubt höchstens eine laufende Generation und committed State- sowie Artifact-Kandidaten erst nach finaler Evidence- und ID-Revalidierung atomar. Lokale Referenzauflösung und Unsupported-Erkennung laufen vor der Modell-Session; eine gültige Klärungsauswahl setzt die ursprüngliche Operation mit dem revalidierten `CURRENT`-Alias fort. Ein Context-Window-Fehler erhält genau einen Recovery-Lauf mit neuer Provider-Session, neuem Tool-Budget, neuer Evidence-Registry, neuer Artifact-Transaktion, neuer Conversation-State-Transaktion und deutlich reduziertem Provider-Kontext.
  - `Security/` enthält `GraphChatAccessPolicy`, die gemeinsame Produktentscheidung aller Einstiege und des Composers, plus ein unabhängiges Execution Gate als Defense in Depth. `GraphChatSessionStore` beobachtet den Mutation Bus: graphweite Import-/Replace-/Delete-/Full-Rebuild-Ereignisse verwerfen betroffene Memory-Sessions; sonstige Mutationen des aktiven Graphen erhöhen eine Präsentationsrevision, damit sichtbare Evidence und Artifacts erneut gegen aktuelle Daten geprüft werden.
  - `Routing/` hält value-only Launch Requests und den optionalen Paywall-Draft ausschließlich im Speicher; Graphwechsel, Lock und Terminierung löschen ihn.
  - `Workspace/` koppelt den vorhandenen Canvas, dessen produktiven `GraphCanvasSelectionState` und denselben `GraphChatSessionStore` über graph-sichere, flüchtige Commands. Der Coordinator speichert weder Graphdaten noch Chatverläufe; persistiert werden nur die harmlose Inspector-Sichtbarkeit und bevorzugte Breite.
  - `Observability/` definiert ausschließlich inhaltsfreie technische Chatmetriken und schreibt sie über `BMLog.chat`.
  - `UI/` enthält die produktive, dependency-injizierte SwiftUI-Präsentationsschicht mit Main-Actor-ViewModel, Composer, Antwortzuständen, graphnativer Artifact-UI, Evidence Chips, Evidence Drawer und adaptivem Copilot-Workspace. Lazy-Container und zentrale Budgets begrenzen große Tabellen, Ergebnislisten und Canvas-Aktionen. Root-Tab, iPad-Inspector und alle kontextuellen Einstiege verwenden dieselbe Policy, denselben Session Store und dieselbe `GraphChatView`.

### Graph Chat Stufe 1 bis 3 und verbleibende Grenzen

- Stufe 1 bis 3 sind produktiv abgeschlossen: read-only/on-device Query- und Tool-Pipeline, strukturierte Multi-Turn-Konversation, graphnative Artifact-/Evidence-UI sowie iPad-Copilot-Workspace mit Canvas- und Selection-Integration. Große Graphen werden über lokalen Index, Schema-Kompaktion, Registry-/Conversation-/Result-Budgets, Lazy-Rendering und begrenzte Workspace-Aktionen geschützt; ein vollständiger Graph wird nie in einen Modellprompt serialisiert.
- Der laufende Turn besitzt einen unveränderlichen Graph-/Scope-Snapshot. Canvas-Auswahländerungen werden nur als sichtbarer Vorschlag angeboten und wechseln den Chat-Scope erst nach expliziter Nutzeraktion; New Chat, Scope-/Graph-Wechsel, Lock, Entitlement-Verlust, Modell-/Index-Grenzen und Cancellation räumen die jeweils betroffenen flüchtigen Zustände deterministisch auf.
- Bewusst verschoben bleiben Query Plan v2, Multi-Hop-/Pfadabfragen, persistierte Threads, Graph-Mutationen beziehungsweise schreibende Chat-Tools, Attachment-Inhaltsanalyse, eine semantische Retrieval-Schicht und Cloud-Provider.
- Die Geräte- und Modellverfügbarkeit wird von iOS geliefert. Ein Pro-Entitlement garantiert nicht, dass Apple Intelligence oder Foundation Models auf jedem iOS-26-Gerät verfügbar sind.

### Storage / Sync / Caches

- `BrainMesh/Settings/SyncRuntime.swift`
  - Runtime-Status für CloudKit vs. lokal, plus iCloud-Konto-Status.
- `BrainMesh/ImageStore.swift`, `BrainMesh/ImageHydrator.swift`
  - lokaler Header-Image-Cache und Rehydration aus `imageData`.
- `BrainMesh/Attachments/AttachmentStore.swift`, `BrainMesh/Attachments/AttachmentHydrator.swift`
  - lokaler Attachment-Cache, Preview-URL-Materialisierung und Hintergrund-Hydration.
- `BrainMesh/Search/Index/`
  - separater actor-isolierter SQLite-Store für versionierte, value-only `GraphSearchDocument`-Werte. Der Store ist transaktional, graph-scoped, bei inkompatibler Version oder Beschädigung sicher rekonstruierbar und speichert bei Attachments ausschließlich Metadaten.
- `BrainMesh/GraphTransfer/`
  - Export/Import/Backup und Transfer-Limits. Interne Import-Checkpoint-Saves bleiben eventfrei; erst der erfolgreiche Abschluss publiziert einen Import- beziehungsweise Replace-Batch. Fehler und Cancellation bereinigen persistierte Teilgraphen, bevor lokale Cache-Dateien entfernt werden.

### Feature UI

- `BrainMesh/Mainscreen/`
  - Entitätenliste, Entity/Attribute-Details, Node-Details-Shared-Komponenten, Bulk-Link, Details-Schema.
- `BrainMesh/GraphCanvas/`
  - Graph-Rendering, Physics, Lens, Inspector, Focus, View Presets, GraphCanvas-Loader sowie der adaptive iPad-Copilot-Inspector. Der Workspace verwendet dieselbe Canvas-Instanz und denselben `GraphCanvasSelectionState`; Highlighting ist flüchtig und keine Graphmutation.
- `BrainMesh/Stats/`
  - Stats-Dashboard, Counts, Media, Trends, Health.
- `BrainMesh/Settings/`
  - Einstellungen, Sync & Wartung, Appearance, Display, Import.
- `BrainMesh/Search/`
  - globaler Search-Orchestrator, indexbasierter Primary Provider, SwiftData-Fallback-Provider, unverändertes Ranking, Command Center und lokaler Search-Index-Store.
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
  - `BrainMesh/Search/Index/GraphSearchIndexStore.swift` mit lokaler SQLite-Persistenz, FTS5-/Fallback-Suche und ausschließlich value-only Dokumenten
  - `BrainMesh/DataAccess/GraphReadRepository.swift` für vollständige graph-scoped Source-Snapshots
  - `BrainMesh/DataAccess/NodeRepository.swift` für graph-scoped Node-Lookups und direkte Nachbarschaften
  - `BrainMesh/GraphChat/Schema/GraphSchemaService.swift` für kompakte, graph-scoped Schema-Snapshots mit deterministischen Entity-/Field-Aliasen und separatem appseitigem Resolution-Kontext
  - `BrainMesh/DataAccess/Mutations/GraphMutationEventBus.swift` und `GraphMutationCommitter.swift` für actor-sichere Multicast-Ereignisse und die einzige Save-then-Publish-Grenze; produktiv angebunden sind lokale Basis-/Composite-Mutationen, Graph-Lifecycle, Dedupe, Bootstrap-/Migrations-Reparaturen sowie Struktur-/Vollbackup-Import und Replace
  - `BrainMesh/Mainscreen/Deletion/GraphNodeDeletionService.swift` für graph-scoped Einzel-/Batch-Löschungen von Entities und Attributen mit deterministischem Link-, Detail-, Attachment- und Dateicache-Cleanup nach genau einem erfolgreichen Commit
  - `BrainMesh/Mainscreen/LinkCleanup.swift` mit `NodeRenameService`, der Node-Änderung und alle tatsächlichen Link-Relabels im selben `ModelContext` vorbereitet und gemeinsam committed
  - `BrainMesh/Attachments/AttachmentMutationService.swift` für Attachment-Create/Update/Delete mit Save-gebundenen lokalen Datei-Seiteneffekten
  - `BrainMesh/DataAccess/Mutations/GraphMutationCacheInvalidationCoordinator.swift` für genau eine unbounded Subscription, die `EntitiesHomeLoader` und `GraphStatsLoader` graph-scoped invalidiert

### Support / Observability

- `BrainMesh/Support/AnyModelContainer.swift`: `@unchecked Sendable` Wrapper für `ModelContainer`.
- `BrainMesh/Support/AsyncLimiter.swift`: kleiner Actor-Semaphore für Hydration/Thumbnails.
- `BrainMesh/Observability/BMObservability.swift`: `BMLog` Kategorien `load`, `expand`, `physics`, `search`, `mutation-events` plus `BMDuration`.

## Folder Map

| Ordner | Zweck | Auffälligkeit |
|---|---:|---|
| `BrainMesh/Mainscreen/` | Home, Entity/Attribute-Details, Node-Shared, Details, Bulk-Link | größtes Modul, viele UI-Flows und SwiftData-Interaktionen |
| `BrainMesh/GraphCanvas/` | Graph Canvas, Physics, Rendering, Inspector, Loader | wichtigster Render-Hot-Path |
| `BrainMesh/GraphTransfer/` | `.bmgraph` und `.bmbackup` Import/Export | Datenintegrität, große DTOs, FileDocument/Activity |
| `BrainMesh/Stats/` | Stats, Graph Health, Media/Trend/Structure Snapshots | viele aggregierende Fetches |
| `BrainMesh/Settings/` | Settings, Sync, Appearance, Display, Guide | Sync-Diagnose und große Guide-View |
| `BrainMesh/Attachments/` | Attachment-Modell, Store, Hydrator, Import, Thumbnails | CloudKit-Assets, lokale Cache-Dateien, 25-MB-Limit |
| `BrainMesh/Search/` | Search-Orchestrator, Candidate Provider, Ranking, Command Center, lokaler SQLite-Index-Store | Der lokale Index ist nach `ensureReady` die primäre Candidate-Quelle; konkrete Graphen bleiben isoliert, globale Suchen verwenden den Index nur bei vollständiger Readiness aller relevanten Graphen, andernfalls die bestehende Provider-Pipeline |
| `BrainMesh/DataAccess/` | Graph-scoped Fetch-Factories, Read-Repositories, value-only DTOs und Mutation-Infrastruktur | nicht-optionaler `GraphScope`; actor-sicherer Event-Bus; zentraler Main-Actor-Committer; keine SwiftData-Modelle, Attachment-Binärdaten oder Nutzdaten über Actor-Grenzen |
| `BrainMesh/GraphChat/` | Chat-Kernmodelle, kompakter Schema-Snapshot, Query-Validierung/-Engine, read-only Tools, Evidence, Foundation-Models-Provider, Streaming-Orchestrator, zentrale Access Policy, technische Observability, Routing und SwiftUI-Präsentation | Root- und Kontext-Einstiege sowie Composer teilen dieselbe Policy und denselben Session Store; aktiver/existierender Graph, Lock, Entitlement, Modell, Index, Reconciliation und Generation werden deterministisch bewertet; Quellen/Filter sichtbar; Draft und Verlauf nur in Memory; keine Attachment-Inhalte, Cloud-Verarbeitung oder Writes |
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
- Lokaler Search Index:
  - `GraphSearchIndexStore` speichert rekonstruierbare Dokumente in `Application Support/BrainMesh/Search/Index/GraphSearchIndex.sqlite` und markiert den Bereich als vom Backup ausgeschlossen.
  - Das Indexschema ist separat versioniert und nicht Teil des SwiftData-/CloudKit-Schemas, GraphTransfer oder App-Backups.
  - FTS5 wird zur Laufzeit bevorzugt; ein eigener indexierter n-Gram-Pfad erhält Unicode-, Umlaut-, Case- und Infix-Suche auch ohne FTS5.
  - Attachment-Dokumente enthalten nur Titel, Original-Dateiname, Dateiendung, Content-Type-Identifier, Byte-Anzahl und Content-Kind; Binärdaten, extrahierter Inhalt und OCR-Text sind ausgeschlossen.
  - `GraphSearchDocumentBuilder` erzeugt aus den value-only Read-DTOs deterministische Dokument-IDs und SHA-256-Content-Hashes für alle unterstützten Source-Arten.
  - `GraphSearchIndexer` führt graph-scoped atomare Full Rebuilds aus, coalesced parallele Anforderungen und hält den Index über genau einen zentral gestarteten `GraphMutationEventBus`-Consumer für lokale Mutationen inkrementell aktuell.
  - Der value-only Indexstatus unterscheidet nicht initialisiert, Aufbau, bereit, veraltet und fehlgeschlagen einschließlich sinnvoller Fortschrittswerte.
  - `GraphSearchSourceManifest` vergleicht pro Graph Source-Art, Source-ID, Dokumentanzahl und stabile Dokument-/Content-Hashes. `GraphSearchIndexReconciler` coalesced `ensureReady`-Aufrufe, repariert externe Änderungen und Löschungen inkrementell, erzwingt bei inkompatiblen oder beschädigten Zuständen einen atomaren Full Rebuild und drosselt den leichtgewichtigen Foreground-Trigger pro Graph.
  - `BrainMeshSearchService.shared` ruft vor der ersten Indexsuche `ensureReady` auf und verwendet `IndexedSearchCandidateProvider` als primäre value-only Candidate-Quelle. Konkrete Graphsuchen sind strikt graph-scoped; `graphID == nil` nutzt den Index nur bei vollständiger Readiness des gesamten ermittelten Scopes. Jeder unsichere Indexzustand oder Queryfehler fällt für die gesamte Anfrage transparent auf die bisherigen SwiftData-Provider zurück.

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
- `RootTab.chat`: `GraphChatTabView()`.
- `RootTab.stats`: `GraphStatsView()`.
- `RootTab.settings`: `NavigationStack { SettingsView(showDoneButton: false) }`.
- Command Center:
  - `.sheet(isPresented: $commandCenter.isPresented)` → `CommandCenterView`; Quick Action „Frag deinen Graphen“ startet den Whole-Graph-Scope des aktiven Graphen.
  - `.sheet(item: $commandCenter.destination)` → `CommandCenterDestinationSheet`, einschließlich graph-validierter Graph-Chat-Evidence-Ziele.

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
- Rekonstruierbare Search-Hilfsdaten bleiben im separaten SQLite-Index unter `BrainMesh/Search/Index/`; sie dürfen nicht in das SwiftData-/CloudKit-Hauptschema, GraphTransfer oder Backups aufgenommen werden. Attachment-Indexdokumente dürfen keine Datei-Bytes, extrahierten Inhalte oder OCR-Texte enthalten.
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
  - Falls suchbar: folded Index oder expliziten Search-Pfad ergänzen; rekonstruierbare Suchdokumente über den separaten lokalen Index modellieren, nicht als SwiftData-`@Model`.
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
3. Die Entities-Home-Suche nur dann auf die bestehende Index-Candidate-Schicht migrieren, wenn Scope, Routing und UX ohne parallele Sonderlogik vollständig kompatibel bleiben; der globale Command-Center-Cutover ist abgeschlossen.
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
