# ARCHITECTURE_NOTES.md

## Scope

Diese Notizen basieren auf dem tatsächlich im ZIP enthaltenen Stand. Aussagen sind an konkrete Dateien gebunden. Alles, was sich aus dem Code nicht belastbar ableiten lässt, ist als **UNKNOWN** markiert und unten gesammelt.

---

## Big Files List

Hinweis: Die Liste fokussiert auf **app-relevante Swift-Quelldateien** in `BrainMesh/` nach Zeilenzahl. Große Datenassets wie `BrainMesh/Icons/IconCatalogData.json` sowie Testdateien sind bewusst nicht im Kernranking, weil sie architektonisch andere Risiken haben.

1. **650 Zeilen** — `BrainMesh/Settings/BrainMeshGuideView.swift`
   - Zweck: In-App-Anleitung.
   - Risiko: Niedriges Runtime-Risiko, aber hohe Merge-Konflikt- und Pflegekosten; sehr viel statischer UI-Content in einer Datei.

2. **437 Zeilen** — `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
   - Zweck: Graph-Import inkl. Phase-Orchestrierung, ID-Remap, Batch-Save, Progress.
   - Risiko: Hohe Zustandsdichte, viele Mutable Maps, Fehler-/Abbruchpfade, Speicher- und Datenkonsistenzrisiko.

3. **384 Zeilen** — `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift`
   - Zweck: Stats-Domänenmodelle, Revisionen, Predicates, Shared Service-Helfer.
   - Risiko: Hohe fachliche Zentralität; Änderungen schlagen breit durch.

4. **348 Zeilen** — `BrainMesh/Stats/GraphStatsLoader.swift`
   - Zweck: Off-Main-Dashboard-Load, Cache-State, Revisionsvergleich, per-Graph Counts.
   - Risiko: Orchestrierungsdichte, Cache-Invalidation-Komplexität, Concurrency-Hotspot.

5. **344 Zeilen** — `BrainMesh/GraphCanvas/GraphCanvasTypes.swift`
   - Zweck: Graph-Canvas-Werttypen, Lens-/Derived-State-Berechnung.
   - Risiko: Hohe Kopplung an Renderlogik; Änderungen beeinflussen Graph-Verhalten breit.

6. **341 Zeilen** — `BrainMesh/Mainscreen/NodeDetailShared/NodeDetailShared+Connections/NodeDetailShared+Connections.AllView.swift`
   - Zweck: UI für vollständige Verbindungsansichten.
   - Risiko: Große UI-Datei im Shared-Detail-Bereich; wahrscheinlich hoher Pflege- und Review-Aufwand.

7. **331 Zeilen** — `BrainMesh/Mainscreen/NodeDetailShared/MarkdownAccessoryView.swift`
   - Zweck: Markdown-bezogene UI / Accessory.
   - Risiko: Große komponentenlastige UI-Datei; vermutlich schwer testbar.

8. **326 Zeilen** — `BrainMesh/Attachments/AttachmentImportPipeline.swift`
   - Zweck: Datei-/Bild-/Video-Import, Recompression, Cache-Write, Limits.
   - Risiko: I/O + Datenmenge + Medienformate + Fehlerpfade in einer Datei.

9. **322 Zeilen** — `BrainMesh/Pro/ProCenterView.swift`
   - Zweck: Pro Center / Subscription-UI.
   - Risiko: Vor allem UI-Pflege; fachlich weniger kritisch als Storage/Graph.

10. **321 Zeilen** — `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
    - Zweck: Dashboard-Host, Reload-Steuerung, Tokens, Lazy-Detail-Laden.
    - Risiko: UI- und Ladeorchestrierung gemischt; Regressionen im Stats-Tab wahrscheinlich.

11. **317 Zeilen** — `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
    - Zweck: Entity-/Attribute-/Link-Search und Matching.
    - Risiko: Sehr zentral für Search-Performance; mehrere Abfragen und In-Memory-Merges.

12. **314 Zeilen** — `BrainMesh/Mainscreen/Details/NodeDetailsValuesCard/NodeDetailsValuesCard+Components.swift`
    - Zweck: Rendering/Edit-Komponenten für Detailwerte.
    - Risiko: Große UI-Komponente; Pflege- und Kombinatorikrisiko.

13. **309 Zeilen** — `BrainMesh/Icons/IconPickerView.swift`
    - Zweck: SF-Symbol-Auswahl.
    - Risiko: Große UI-Datei; eher UX-/Pflege-Risiko als Datenrisiko.

14. **308 Zeilen** — `BrainMesh/Onboarding/DetailsOnboardingSheetView.swift`
    - Zweck: Details-Onboarding, Picker, Routen, Queries.
    - Risiko: Mehrere Verantwortungen und direkte Fetches im Flow.

15. **305 Zeilen** — `BrainMesh/Settings/Display/DisplaySettingsStore.swift`
    - Zweck: Persistenz, Migrationslogik und Mutation API für Display Settings.
    - Risiko: Fachlich klein, aber state-/migration-sensitiv; Fehler wirken quer durch viele Screens.

Zusatz:
- `BrainMesh/Icons/IconCatalogData.json` hat **527 Zeilen** und ist ein großer Datenasset, aber kein Architektur-Hotspot im engeren Sinn.

---

## Hot Path Analyse

### Rendering / Scrolling

#### 1) Graph-Physik ist der heißeste Renderpfad
- Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasView/GraphCanvasView+Physics.swift`
- Konkreter Grund:
  - 30-FPS-`Timer` (`Timer.scheduledTimer(withTimeInterval: 1.0/30.0, ...)`).
  - Pro Tick werden `positions` und `velocities` mutiert.
  - Diese `@State`-Strukturen invalidieren SwiftUI häufig und sind groß genug, um teuer zu werden.
- Bereits vorhandene Gegenmaßnahmen:
  - `simulationAllowed`-Gate.
  - Sleep-Modus nach Idle.
  - Relevanzfilter `physicsRelevant`.
- Restrisiko:
  - Bei großen Graphen bleibt das der CPU-/Battery-Hotspot Nummer 1.

#### 2) GraphCanvasScreen ist renderseitig stark orchestriert
- Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+Body.swift`
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen+DerivedState.swift`
- Konkreter Grund:
  - Viele `.onChange`-Hooks, Overlays, staged jumps, Sheet-State, Derived-State-Caches.
  - Hohe View-Invalidationsgefahr, weil sehr viele Zustände an einem Host zusammenlaufen.
- Positiv:
  - Derived-State ist bereits gecacht und nicht mehr vollständig im `body`.
- Restrisiko:
  - Host bleibt schwer mental modellierbar und regressionsanfällig.

#### 3) Neighborhood-Load im Graph-Tab skaliert mit Link-/Node-Menge
- Datei: `BrainMesh/GraphCanvas/GraphCanvasDataLoader/GraphCanvasDataLoader+Neighborhood.swift`
- Konkreter Grund:
  - Batch-BFS über `MetaLink`.
  - Mehrere große `Set`-/Array-Strukturen (`visitedEntities`, `frontier`, `seenEntityLinkIDs`, `visibleIDs`).
  - Zusätzliche Oversampling-Abfrage für sichtbare Links.
- Hotspot-Art:
  - Heavy fetch + in-memory graph traversal.

#### 4) EntitiesHome-Suche ist bewusst off-main, aber fachlich breit
- Dateien:
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView+Loading.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
- Konkreter Grund:
  - Suche läuft gegen Entitäten, Attribute und Link-Notizen.
  - Danach In-Memory-Dedupe und Sortierung.
  - Trigger bei Sucheingabe trotz 250-ms-Debounce.
- Positiv:
  - Off-main Loader, TTL-Caches für Counts.
- Restrisiko:
  - Große Datasets + häufiges Tippen erzeugen trotzdem spürbare Last.

#### 5) Medienvorschau pro Node macht mehrere Scoped-Queries
- Dateien:
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader+Query.swift`
- Konkreter Grund:
  - Für Galerie und Anhänge werden Count und Preview-IDs separat geladen.
  - Bei gesetztem `graphID` werden `.exact(graphID)` und `.legacyNil` kombiniert.
  - Anschließend Materialisierung der kleinen Vorschau im Main-Context.
- Hotspot-Art:
  - Mehrere Counts + sortierte Preview-Fetches pro Detail-Reload.

#### 6) Galerie-Browser ist owner-scoped, aber potenziell ungebremst
- Dateien:
  - `BrainMesh/PhotoGallery/PhotoGalleryBrowserView.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryQuery.swift`
- Konkreter Grund:
  - `@Query` lädt alle Galerie-Bilder eines Owners absteigend nach `createdAt`.
  - Kein Paging gefunden.
- Restrisiko:
  - Bei sehr vielen Bildern pro Node wachsen Speicher- und Renderkosten.

### Sync / Storage

#### 7) Stats-Byteaggregation lädt komplette Attachment-Mengen
- Datei: `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
- Konkreter Grund:
  - `attachmentAggregateItems(for:)` fetcht alle `MetaAttachment`-Objekte für Scope/Total.
  - Byte-Summen werden anschließend in-memory über `reduce` berechnet.
- Hotspot-Art:
  - Heavy fetch statt Count/Projection.
- Bewertung:
  - Für kleine Datenmengen okay, bei wachsendem Attachment-Bestand unnötig teuer.

#### 8) CloudKit-Startup ist klar, aber Migrationsstrategie bleibt implizit
- Dateien:
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/Bootstrap/GraphBootstrap+Repair.swift`
  - `BrainMesh/Bootstrap/GraphBootstrap+Backfill.swift`
- Konkreter Grund:
  - Es gibt Repair-/Backfill-Code, aber keinen expliziten SwiftData-Migrationsplan.
  - Das ist kurzfristig pragmatisch, langfristig riskant bei Modellentwicklung.
- Risiko:
  - Model-Evolution wird zunehmend „Code + Bootstraps“ statt „Schema + Plan“.

#### 9) Bild-/Attachment-Hydratoren scannen breitere Datenmengen
- Dateien:
  - `BrainMesh/ImageHydrator.swift`
  - `BrainMesh/Attachments/AttachmentHydrator.swift`
- Konkreter Grund:
  - Hydration basiert auf Datei-Existenz + SwiftData-Fetches.
  - `ImageHydrator` scannt alle Datensätze mit `imageData != nil`.
  - `AttachmentHydrator` fetcht `fileData` on demand pro Attachment-ID.
- Positiv:
  - Serialisierung/Limitierung vorhanden.
- Restrisiko:
  - Repair- oder Erst-Device-Szenarien können noch spürbar I/O-lastig werden.

#### 10) Graph Transfer Import ist ein Storage-Hotspot
- Datei: `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
- Konkreter Grund:
  - Große Mengen Inserts mit eigener Batch-Save-Logik.
  - Mehrere Mapping-Tabellen und referenzielle Abhängigkeiten.
  - Ein Fehler im Remap-/Save-Pfad beschädigt direkt Importkonsistenz.
- Positiv:
  - Batch-Save, Cancellation-Strides, Yield-Strides vorhanden.

### Concurrency

#### 11) Default Actor Isolation scheint MainActor-zentriert zu sein
- Indizien:
  - Mehrfacher Kommentar im Code, z. B. `GraphStatsService.swift`, `RootTabRouter.swift`, `GraphJumpCoordinator.swift`.
- Konkrete Auswirkung:
  - Viele Typen/Methoden sind bewusst `nonisolated` oder nur selektiv `@MainActor`, um Swift-6-/strict-concurrency-Probleme zu vermeiden.
- Risiko:
  - Falsche Isolation schlägt schnell in Warnungen oder inkorrektes Threading um.

#### 12) Viele Loader erzeugen eigene `ModelContext`-Instanzen
- Dateien:
  - `BrainMesh/Support/AppLoadersConfigurator.swift`
  - alle Loader in `BrainMesh/GraphCanvas/`, `BrainMesh/Stats/`, `BrainMesh/Mainscreen/...Loader`
- Konkreter Grund:
  - Gutes Muster für Off-main-Fetches, aber hoher Wiederholungsgrad.
  - Jeder Loader kocht sein eigenes Setup, Cancellation-Handling und Fehlerdomäne.
- Risiko:
  - Pattern-Drift und inkonsistente Invalidationsstrategien.

#### 13) AppRoot mischt Startup, Locking, Foreground-Reaktion und Onboarding
- Dateien:
  - `BrainMesh/AppRoot/AppRootView.swift`
  - `BrainMesh/AppRoot/AppRootView+Startup.swift`
  - `BrainMesh/AppRoot/AppRootView+ScenePhase.swift`
  - `BrainMesh/AppRoot/AppRootView+Onboarding.swift`
- Konkreter Grund:
  - Mehrere app-weite Seiteneffekte laufen an einem Ort.
  - Debounced background lock + modal guards + onboarding decision + startup repair.
- Risiko:
  - Lebenszyklusregressionen und schwer reproduzierbare Wechselwirkungen.

---

## Refactor Map

### A) Konkrete Splits

#### 1) Import-Koordinator weiter zerlegen
- Heute:
  - `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
- Ziel-Schnitt:
  - `...+ImportCoordinator.swift`
  - `...+ImportEntities.swift`
  - `...+ImportFields.swift`
  - `...+ImportAttributes.swift`
  - `...+ImportLinks.swift`
  - `...+ImportProgress.swift`
- Nutzen:
  - Kleinere Review-Flächen, besser testbare Phasen, klarere Fehlerlokalisierung.

#### 2) Stats-Loader in Cache-State und Load-Pipeline trennen
- Heute:
  - `BrainMesh/Stats/GraphStatsLoader.swift`
- Ziel-Schnitt:
  - `GraphStatsLoader+Dashboard.swift`
  - `GraphStatsLoader+PerGraphCounts.swift`
  - `GraphStatsLoader+Cache.swift`
  - `GraphStatsLoader+Invalidation.swift`
- Nutzen:
  - Cache-Invarianten und Ladepfade werden separat prüfbar.

#### 3) GraphCanvasScreen Host weiter entlasten
- Heute:
  - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
  - `...+Body.swift`
- Ziel-Schnitt:
  - `...+PresentationState.swift`
  - `...+Navigation.swift`
  - `...+Selection.swift`
  - `...+OverlaysState.swift`
- Nutzen:
  - Weniger State-Ballung pro Datei, klarere Verantwortlichkeiten.

#### 4) BrainMeshGuideView in Abschnittsdateien zerlegen
- Heute:
  - `BrainMesh/Settings/BrainMeshGuideView.swift`
- Ziel-Schnitt:
  - `BrainMeshGuideView+Sections*.swift`
- Nutzen:
  - Niedriges technisches, aber hohes Pflege-/Merge-Problem wird entschärft.

### B) Cache- / Index-Ideen

#### 1) Stats: Byte-/Attachment-Aggregat cachen oder projektieren
- Betroffene Dateien:
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
- Idee:
  - Attachment-Byte-Summen nicht immer via Vollfetch berechnen.
  - Mögliche Wege:
    - persistierte Aggregat-Tabelle,
    - revision-basiertes Cache-Objekt,
    - leichterer Projection-Fetch, falls SwiftData das sauber zulässt.
- Invalidierung:
  - Bei Attachment-Insert/Delete/ByteCount-Änderung.

#### 2) Unified GraphScope Query Helpers
- Betroffene Dateien:
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader+Query.swift`
  - `BrainMesh/PhotoGallery/PhotoGalleryQuery.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/EntitiesHomeLoader+Fetch.swift`
- Idee:
  - Gemeinsame QueryBuilder für `graphID == gid`, `graphID == nil`, Legacy-Merge.
- Nutzen:
  - Weniger Drift in Predicates und Legacy-Behandlung.

#### 3) Search-Index-Ausbau nur bei echtem Bedarf
- Aktuell vorhanden:
  - `nameFolded`, `notesFolded`, `searchLabelFolded`, `noteFolded`
- Nächster sinnvoller Schritt:
  - Nur falls Search weiter wächst: separate Search-Snapshot-/Index-Schicht.
- Bewertung:
  - Noch nicht zwingend, aber mittelfristig relevant.

### C) Vereinheitlichungen

#### 1) Loader-Basisprotokoll oder Shared Helper
- Problem:
  - Viele Loader replizieren Container-Guard, Context-Erzeugung, Cancellation, Error-Domains.
- Betroffene Dateien:
  - `BrainMesh/GraphCanvas/GraphCanvasDataLoader/*`
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeLoader/*`
  - `BrainMesh/Mainscreen/NodeDetailShared/NodeMediaPreviewLoader*.swift`
- Ziel:
  - Shared `LoaderRuntime` / `BackgroundModelContextFactory`.

#### 2) App-weite Constants konsolidieren
- Problem:
  - CloudKit-Container-ID und ähnliche Konfigurationen liegen verteilt.
- Betroffene Dateien:
  - `BrainMesh/BrainMesh.entitlements`
  - `BrainMesh/Settings/SyncRuntime.swift`
  - `BrainMesh/Info.plist`
- Ziel:
  - Weniger Konfigurationsdrift.

#### 3) Dead-Code-/Deprecated-Bereinigung
- Kandidaten:
  - `BrainMesh/Onboarding/Untitled.swift`
  - `BrainMesh/GraphSession.swift` (im Codebestand keine Verwendungen gefunden)
  - `BrainMesh/Mainscreen/Details/DetailsSchema/DetailsSchemaValidation.swift` als deprecated Wrapper
- Nutzen:
  - Weniger Navigationsrauschen, klarere Codebasis.

---

## Risiken & Edge Cases

### Datenverlust / Inkonsistenz
- `GraphTransferService+Import.swift`
  - Batch-Save-Importe sind fehleranfällig bei teilweisem Abbruch.
  - Positiv: eigener Import-Context, dadurch nicht direkt UI-Context.
  - **UNKNOWN:** Gewünschte Rollback-Strategie bei Mid-Import-Fehlern.

### Migration
- Keine explizite `VersionedSchema`-/`MigrationPlan`-Struktur gefunden.
- Aktuelles Modell verlässt sich auf:
  - SwiftData-Automatik
  - App-seitige Backfills/Repair-Schritte
- Risiko steigt mit jeder zusätzlichen Model-Änderung.

### Offline / Multi-Device
- CloudKit ist eingeschaltet, aber Konfliktbehandlung ist nicht fachlich dokumentiert.
- Legacy-Handling (`graphID == nil`) existiert an vielen Stellen; das ist robust, aber erhöht Komplexität.

### Medien / Speichergröße
- `MetaAttachment.fileData` und `imageData` werden synchronisiert; große Datensätze sind deshalb kritisch.
- Das Projekt hat Limits/Compression, aber Storage-Druck bleibt ein Architekturthema.

### Security / Locking
- `AppRootView+ScenePhase.swift` behandelt transient `.background` beim Systempicker per Debounce und Grace Window.
- Das ist pragmatisch und wahrscheinlich nötig, aber klassisch regressionsanfällig.

### UIBackgroundModes / Push
- `remote-notification` ist in `Info.plist` gesetzt.
- Kein AppDelegate-/Push-Entry-Point gefunden.
- Risiko:
  - tote Capability oder unvollständig migrierte Infrastruktur.

---

## Observability / Debuggability

### Vorhanden
- `BrainMesh/Observability/BMObservability.swift`
  - `BMLog.load`
  - `BMLog.expand`
  - `BMLog.physics`
  - `BMDuration`
- `GraphCanvas` loggt Ladezeiten und Physics-Metriken.
- `SyncRuntime` zeigt Storage-Modus und iCloud-Accountstatus im Settings-Bereich.

### Gut reproduzierbare Problemzonen
- Graph-Performance:
  - großer Graph, viele Nodes/Links, Fokuswechsel, Attribute ein/aus.
- Search-Performance:
  - schneller Wechsel von Suchbegriffen im Entitäten-Tab.
- Medien:
  - frisches Gerät / gelöschter Cache / viele Bilder oder Videos.
- Locking:
  - Graph-Passwort + Photos Hidden Album + App-Hintergrundwechsel.
- Import:
  - großer Graph mit vielen Detailwerten und Links.

### Was fehlt oder schwach ist
- Keine sichtbare zentrale Debug-Konsole im App-UI gefunden.
- Keine CI-/Automation-Spuren gefunden.
- UI Tests sind faktisch noch Template-Level.

---

## Testbild / Absicherung

### Positiv
- Gute Unit-Test-Abdeckung für mehrere kritische Bereiche vorhanden:
  - `BrainMeshTests/GraphTransferRoundtripTests.swift`
  - `BrainMeshTests/GraphStatsLoaderTests.swift`
  - `BrainMeshTests/GraphStatsServiceCountsTests.swift`
  - `BrainMeshTests/EntitiesHomeLoaderSearchTests.swift`
  - `BrainMeshTests/EntitiesHomeLoaderCountsTests.swift`
  - `BrainMeshTests/NodeMediaPreviewLoaderTests.swift`
  - `BrainMeshTests/MediaAllLoaderTests.swift`
  - `BrainMeshTests/GraphCanvasDerivedStateTests.swift`

### Schwach
- `BrainMeshUITests/` enthält nur Standard-Launch-Tests.
- Kritische Flows wie Import, Locking, Graph-Picker, Search-Smoke und Gallery-Smoke sind UI-seitig nicht abgesichert.

---

## Open Questions

1. **UNKNOWN:** Gibt es außerhalb des ZIP eine explizite fachliche Regel für CloudKit-Konflikte und Multi-Device-Merge?
2. **UNKNOWN:** Soll `UIBackgroundModes = remote-notification` aktiv genutzt werden oder ist das Altbestand?
3. **UNKNOWN:** Ist `GraphSession.swift` bewusst als zukünftige Abstraktion liegen geblieben oder faktisch Dead Code?
4. **UNKNOWN:** Soll ein fehlgeschlagener Graph-Import vollständig rollbacken oder ist „partiell angelegt, aber Fehler anzeigen“ akzeptiert?
5. **UNKNOWN:** Gibt es externe Build-/Signing-/Secrets-Konfiguration, die im ZIP nicht enthalten ist?
6. **UNKNOWN:** Ist für sehr große Galerien/PDF-/Video-Sammlungen pro Node Paging vorgesehen oder gewünscht?

---

## First 3 Refactors I would do (P0)

### P0.1 — Stats-Pfad entlasten und entwirren
- **Ziel**
  - Den Stats-Tab günstiger und wartbarer machen, insbesondere Attachment-Aggregation und Loader-Caching.
- **Betroffene Dateien**
  - `BrainMesh/Stats/GraphStatsLoader.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService.swift`
  - `BrainMesh/Stats/GraphStatsService/GraphStatsService+Counts.swift`
  - ggf. `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
- **Risiko**
  - Mittel. Stats sind isolierter als Core-CRUD, aber fachlich breit sichtbar.
- **Erwarteter Nutzen**
  - Weniger Vollfetches, klarere Cache-Invarianten, einfachere Fehlersuche bei Stats-Regressionen.

### P0.2 — GraphTransfer-Import in echte Phasenmodule zerlegen
- **Ziel**
  - Den Importpfad aus `GraphTransferService+Import.swift` in testbare, klar getrennte Einheiten schneiden.
- **Betroffene Dateien**
  - `BrainMesh/GraphTransfer/GraphTransferService/GraphTransferService+Import.swift`
  - neue Teil-Dateien für Coordinator/Phase/Save/Progress/Remap
- **Risiko**
  - Mittel bis hoch. Import ist sensibel für Referenzintegrität.
- **Erwarteter Nutzen**
  - Weniger PR-Risiko, bessere Lesbarkeit, gezieltere Tests pro Importphase.

### P0.3 — Explizite SwiftData-Migrationsstrategie einziehen
- **Ziel**
  - Weg von impliziten Reparaturen allein hin zu einer belastbaren Schema-Evolutionsstrategie.
- **Betroffene Dateien**
  - `BrainMesh/BrainMeshApp.swift`
  - `BrainMesh/Models/*.swift`
  - `BrainMesh/Bootstrap/*`
  - neue Schema-/Migration-Dateien
- **Risiko**
  - Mittel. Sauber machbar, aber modellübergreifend.
- **Erwarteter Nutzen**
  - Weniger zukünftige Migrationsangst, klarere Verantwortung zwischen Schema-Migration und inhaltlichem Backfill.
