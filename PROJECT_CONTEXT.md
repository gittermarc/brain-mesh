# BrainMesh – Project Context

> Start Here für neue Entwickler:innen. Stand: GRAPH-CHAT-CORE-GROUNDING-1 nach INTENT-COMPILER-7, mit zentralem app-owned Mention Grounding, produktivem Typed-Planner-Cutover, gebündelter Limit-Policy, begrenzter Interpreter-Recovery und providerfreier lokaler Ausführung aller unterstützten Intent-Familien.

## TL;DR

BrainMesh ist eine native SwiftUI-App für iPhone und iPad, in der Nutzer:innen Wissen als mehrere Graphen aus Entities, Attributes, Links, Detailfeldern und Medien organisieren, visualisieren, durchsuchen, statistisch auswerten sowie per On-Device-Graph-Chat abfragen. Der App-Target läuft ab iOS 26.0, verwendet SwiftData als persistentes Modell und konfiguriert dessen privaten CloudKit-Sync automatisch. Ein lokaler SQLite-Suchindex, rekonstruierbare Bild-/Attachment-Caches und UserDefaults ergänzen den SwiftData-Store. Einstiegspunkte sind `BrainMesh/BrainMeshApp.swift`, `BrainMesh/AppRoot/AppRootView.swift` und `BrainMesh/ContentView.swift`.

## Priorisierte Lesereihenfolge

1. `BrainMesh/BrainMeshApp.swift` – Schema, ModelContainer, globale Abhängigkeiten.
2. `BrainMesh/AppRoot/AppRootView.swift` und `BrainMesh/AppRoot/AppRootView+Startup.swift` – Start, Migrationen, Lifecycle.
3. `BrainMesh/Models/` und `BrainMesh/Attachments/MetaAttachment.swift` – persistentes Domänenmodell.
4. `BrainMesh/DataAccess/Mutations/GraphMutationCommitter.swift` – zentrale Save-/Event-Grenze.
5. `BrainMesh/Search/Index/` – lokaler, rekonstruierbarer Suchindex.
6. `BrainMesh/ContentView.swift` – Tabs und globale Navigation.
7. `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift` – Graph-Hauptscreen.
8. `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift` – Entity-Hauptscreen.
9. `BrainMesh/GraphChat/` – On-Device-Chat und read-only Graph-Tools.
10. `BrainMeshTests/GraphMutationWritePathInventoryTests.swift` – dokumentierte Schreibpfade.

## Key Concepts / Domänenbegriffe

- **Graph**: Oberster Mandant/Workspace. Aktiver Graph wird über `GraphSession` und UserDefaults ausgewählt.
- **Entity**: Primärer Knoten, z. B. Person, Projekt oder Thema.
- **Attribute**: Untergeordneter Knoten einer Entity; besitzt eine SwiftData-Relationship zur Entity.
- **Link**: Gerichtete Verbindung zwischen zwei Knoten. Endpunkte sind als UUIDs/Kinds gespeichert.
- **Detail Field Definition**: Schemafeld einer Entity, das Werte für Attributes definiert.
- **Detail Field Value**: Typisierter Wert eines Attributes für ein Detailfeld.
- **Details Template**: Wiederverwendbares, JSON-kodiertes Set von Detailfeldern.
- **Attachment**: Datei, Video oder Gallery-Bild; Binärdaten sind autoritativ im Modell gespeichert.
- **Header Image**: Bilddaten direkt auf Entity/Attribute; `imagePath` ist nur lokaler Cache-Metadatenpfad.
- **Graph Scope**: `graphID` grenzt fast alle Datensätze auf einen Graphen ein.
- **Mutation Batch**: Datenminimaler Event nach erfolgreichem Save; invalidiert Index und Caches.
- **Search Index**: Pro App lokaler SQLite-/FTS-Index; aus SwiftData vollständig rekonstruierbar.
- **Graph Chat**: On-Device-LLM-Flow mit sechs read-only Tools und graphgebundener Evidenz.
- **Graph Mention Resolver**: Versionierte, value-only, `Hashable`- und `Sendable`-fähige appseitige Grounding-Schicht für Entity-, Node- und Feldanzeigenamen. Sie arbeitet ausschließlich auf dem vollständigen aktuellen `foundationalAliases`-Katalog des aktiven Graphen, berücksichtigt den Chat-/Owner-/Selection-/Conversation-Scope nur als Eingrenzung und liefert eine eindeutige Bindung, eine fachliche Mehrdeutigkeit oder einen geschlossenen technischen Fehler.
- **Typed Conversation Scope**: Appseitig revalidierte, an Graph, Chat-Scope und Conversation gebundene Auflösung von `CURRENT` und gleichwertigen Conversation-Referenzen; enthält eine konkrete Entity sowie die zulässigen Nodes und wird vor der Query-Ausführung erneut geprüft.
- **Presentation Firewall**: Turn-gebundene Trust Boundary, die interne Chat-Aliase und technische IDs vor Streaming, finaler UI-Ausgabe und Copy deterministisch auf validierte Anzeigenamen abbildet oder durch eine lokalisierte Ersatzantwort ersetzt.
- **Bounded Tool Repair**: Ausschließlich im echten offenen Legacy-Providerpfad verfügbare, request-gebundene Korrektur eines semantisch ungültigen Modell-Tool-Calls. Unterstützte Typed Intents erreichen diesen Pfad nie. Der Legacy-Provider erhält nur validierte Schema-/Scope-Hinweise und genau einen vollständigen Retry; Sicherheits-, Scope-, Repository-, Cancellation- und Budgetfehler bleiben harte Abbrüche.
- **Primary Result Ledger**: Request-lokale, value-only Erfassung validierter erfolgreicher Tool-Ergebnisse. Eine deterministische App-Policy wählt das autoritative primäre Ergebnis und übergibt dessen Evidence und Artifacts unabhängig von Modell-IDs an den Finalizer.
- **Deterministic Answer Fallback**: Lokalisierte, begrenzte Mindestantwort, die ausschließlich aus dem nach Live-Revalidierung verbliebenen primären Tool-Ergebnis gerendert wird. Sie ersetzt nur leeren, technischen, widersprüchlichen oder presentation-unsicheren Modelltext und behält dessen Evidence beziehungsweise Result-Artefakt.
- **Foundational Intent Compiler**: Schemaorientierte, providerfreie Trust Boundary für Fragen nach einem Detailfeld eines eindeutigen Attributes, nach der vollständigen Attributliste einer eindeutigen Entity und nach den vollständigen Details eines eindeutig genannten Nodes. Deutsche und englische Hüllen werden generisch erkannt; fachliche Textstellen bindet ausschließlich der zentrale Mention Resolver. App-Daten bestimmen Entity, Feld, Node-Scope, Query-Plan, Tool und Limit; nur `.notRecognized` erreicht die nachgelagerte semantische Interpreter-Stufe.
- **Semantic Intent Interpreter**: Nachgelagerte On-Device-Foundation-Models-Stufe für Find Nodes, Node Details, Compare Nodes und Inspect Graph State sowie fachliche Collection-, Filter-, Sortier-, Projektions-, Count-, Group- und Refinement-Bedeutung. Das Modell erhält weder Tools noch technische Identitäten und erzeugt nur einen begrenzten, untrusted und value-only Draft aus Anzeigenamen, fachlichen Relationen, Nutzerwerten, Graph-State-Aspekt und Conversation-Bezug.
- **Two-Stage Typed Planner**: Verbindliche Reihenfolge aus Foundational Fast Path und anschließendem toolfreien Semantic Interpreter. Nach der Draft-Validierung besitzt ausschließlich die App Identitäten, Scope, Tool, Query, Operator, typisierte Werte, Projektion, Aggregation, Sortierung, Limits, Evidence, Artifacts, Interpretation und finalen Fachtext.
- **Typed Planner Cutover Policy**: `GraphChatTypedPlannerCutoverPolicy` klassifiziert Find Nodes, Entity List, Filtered List, Count, Group Count, Refinement, Node Details, Compare Nodes und Inspect Graph State als vollständig lokale Familien. Ein teilweise akzeptierter Draft darf nie in freie Tool- oder Query-Improvisation fallen.
- **Intent Limit Policy**: `GraphChatIntentLimitPolicy` ist die gemeinsame appseitige Quelle für Search-/Query-/Collection-/Group-Limits, Filter, Projektion, Comparison, Related Items, Graph Hubs, Clarification, Interpreter-Strings/-Arrays sowie Standard- und Compact-Kontextprofile.
- **Bounded Interpreter Recovery**: Ein normaler begrenzter Interpreter-Request erhält ausschließlich bei `contextWindowExceeded` genau einen noch kompakteren Retry im selben Request-/Cancellation-Lifecycle. Nach einem gelieferten Draft gibt es keinen Retry. Schemawidrige oder manipulierte Drafts scheitern geschlossen; technische Nichtverfügbarkeit darf deterministisch den Legacy-Provider öffnen.
- **Query Intent Compiler**: Zentrale appseitige Trust Boundary nach der Draft-Validierung. Sie löst Entity und Felder gegen das vollständige aktive Schema auf, wählt ausschließlich typkompatible Operatoren, parst lokalisierte Werte deterministisch und erzeugt Scope, Projektion, Aggregation, Limits, Kardinalität und stabile Sortierung. Jeder Plan durchläuft anschließend erneut `GraphQueryPlanValidator` und `GraphChatScopeAuthorization`.
- **Advanced Intent Compiler**: Appseitige Trust Boundary für Node Details, Compare Nodes und Inspect Graph State. Sie löst und revalidiert Nodes aus Anzeigenamen, `CURRENT`, Ordinal, Last Node, Last Compared oder Clarification, bestimmt `GetNodeTool` beziehungsweise `GraphStatsTool`, Comparison-Art, Features, Selection Query, Limits, Artifact-Typ und Trusted Events. Das Modell kann keine Node-ID, Toolwahl, technische Comparison-Feature-ID oder Limits setzen.
- **Comparison Plan**: Zentraler value-only Vertrag für mindestens zwei revalidierte Nodes. `GraphChatComparisonPlan` bindet Graph, Chat-Scope, Request, Conversation und Turn sowie appseitig gewählte Comparison-Art, Features, Selection Query, gemeinsame Limits, Sprache und erwartete Kardinalität.
- **Typed-Intent-Domain**: Versionierter, value-only, `Hashable` und `Sendable` Vertrag für appseitig aufgelöste Absichten. Er unterscheidet Find Nodes, Entity Collection, Count/Group, Node Details, Narrow Result Set, Compare Nodes und Inspect Graph State und bindet Intent, Scope, Sprache, Request, Conversation, Turn, Resolution-Qualität, Kardinalität, Limits sowie validierte Identitäten.
- **Local Intent Execution Kernel**: Providerfreier Lifecycle für bereits appseitig kompilierte lokale Actions. Der Kernel revalidiert Bindings, Scope, Schemaidentitäten und Query-Plan, besitzt genau eine Conversation-, Evidence-, Presentation-, Artifact- und Ledger-Transaktion und führt Finalisierung, äußeren Turn-Commit, Rollback und Cleanup über einen gemeinsamen Pfad.
- **Intent Interpretation**: Value-only, request-/conversation-/turn-gebundene und presentation-sichere Ableitung des revalidierten Typed Intent und Execution Plans. Sie beschreibt fachlich kompakt Entity, Nodes, Felder, Filter, Sortierung, Gruppierung beziehungsweise Aggregation, Ergebnisumfang und Graph-State-Aspekt; Provider-Text, Semantic Drafts, Tool-Content und Query-Summary-Text sind keine Quelle.
- **Interpretation Correction**: Versionierter, an ursprüngliche User-/Assistant-Message, normalisierte Request-Frage, Request, Turn, Conversation, Graph-/Chat-Scope, Checkpoints, Intent-Domainversion und Artifact-Session gebundener Ersatzturn. Die UI-Auswahl ist nur Nutzerabsicht; ein frischer vollständiger `GraphSchemaContext` und der bestehende Query-/Advanced-Intent-Compiler revalidieren alle Identitäten vor der providerfreien lokalen Ausführung.
- **Authoritative Fact**: Nicht persistierter, value-only und `Sendable` Single-Fact-Vertrag aus genau einem revalidierten primären Query-Ergebnis, einem typisierten Table-Artifact und passender Live-Evidence. Er bindet Graph, Chat-Scope, Request/Turn, Artifact-Session und -Transaktion sowie Node, Entity, Feld, Typ, Wert und Einheit. Für kompilierte Single-Field-Turns rendert die App daraus den vollständigen sichtbaren Antworttext; Provider-Text ist keine Fachwertquelle.
- **Pro**: StoreKit-gesteuerte Berechtigung für kostenpflichtige Funktionen.

## Architecture Map

### Composition und Lifecycle

- `BrainMesh/BrainMeshApp.swift`
  - erstellt `Schema` und `ModelContainer`;
  - konfiguriert CloudKit oder den Release-Fallback auf lokalen Storage;
  - erstellt globale `ObservableObject`-Stores und Coordinators;
  - konfiguriert Loader über `AppLoadersConfigurator`.
- `BrainMesh/AppRoot/AppRootView.swift`
  - hostet `ContentView`;
  - bindet Startup, Scene-Phase, Graph-Wechsel, Locking und Pro-Status;
  - präsentiert Onboarding und Graph-Unlock.
- Abhängigkeit: App Composition → SwiftData/Services → Root View → Tabs/Flows.

### UI / Presentation

- `BrainMesh/ContentView.swift` besitzt den Root-`TabView`.
- Feature-Views liegen primär in `Mainscreen/`, `GraphCanvas/`, `GraphChat/`, `Stats/` und `Settings/`.
- Coordinators/Router transportieren Tab-, Sheet- und Deep-Link-Absichten.
- Views konsumieren `@EnvironmentObject`, SwiftData-Kontext und actor-basierte Loader.

### Domain und Persistenz

- SwiftData-Models liegen in `BrainMesh/Models/` und `BrainMesh/Attachments/MetaAttachment.swift`.
- `BrainMesh/DataAccess/Mutations/GraphMutationCommitter.swift` kapselt den normalen Save-then-publish-Pfad.
- `BrainMesh/Bootstrap/` repariert Legacy-Scopes und gefaltete Suchfelder.
- `BrainMesh/GraphTransfer/` importiert/exportiert Graphen und Vollbackups.

### Read Models, Index und Caches

- `BrainMesh/DataAccess/GraphReadRepository.swift` erzeugt graphweite Value-Snapshots.
- `BrainMesh/Search/Index/` verwaltet SQLite-Schema, Dokumente, Manifeste und Reconciliation.
- `BrainMesh/Mainscreen/EntitiesHome/` besitzt Loader und abgeleitete Home-Caches.
- `BrainMesh/Stats/` berechnet Graphstatistiken und Health-Ergebnisse.
- `BrainMesh/ImageStore.swift` und `BrainMesh/Attachments/AttachmentStore.swift` halten lokale Disk-Caches.

### Services

- `BrainMesh/GraphCanvas/GraphCanvasDataLoader/` lädt begrenzte Canvas-Snapshots.
- `BrainMesh/GraphChat/` kapselt Provider, Tools, Query-Plan, Conversation, turn-gebundene Presentation Registry/Firewall und UI.
- `BrainMesh/Security/` kapselt Graph-Lock, Biometrie und Passwort.
- `BrainMesh/Pro/` kapselt StoreKit-Entitlements.

### Abhängigkeitsrichtung

- UI → Loader/Services/Mutation Services → SwiftData.
- SwiftData-Save → `GraphMutationEventBus` → Suchindex- und Cache-Invalidierung.
- Suchindex → SwiftData nur für Rebuild/Reconciliation; nie als autoritative Quelle.
- Lokale Medien-Caches → autoritative SwiftData-Binärdaten; Caches dürfen verworfen werden.
- Graph Chat → read-only Tool Runtime → Search/Repositories; kein Chat-Tool schreibt Graphdaten.
- Validiertes Request-Preflight → vollständiger appseitiger `GraphSchemaContext` → Foundational Intent Compiler. Eindeutige Intents oder fachliche Clarifications werden vor jedem Modellaufruf lokal behandelt; `.notRecognized` erreicht erst den begrenzten semantischen Interpreter.
- Erfolgreicher Foundational Fast Path → verlustfreier `GraphChatFoundationalIntentAdapter` → versionierter `GraphChatTypedIntent` plus bereits kompilierte `GraphChatLocalIntentAction` → gemeinsamer `GraphChatLocalIntentExecutionKernel`. Der Compiler bleibt auf drei enge Erkennungsfälle begrenzt: Single Field, Entity Collection und vollständige Details eines eindeutig genannten Nodes. Der Kernel interpretiert weder freie Sprache noch wählt er Tools oder Query-Semantik.
- Foundational-, Query- und Advanced-Binding sowie Interpretation Corrections verwenden denselben `GraphMentionResolver`. Promptgrenzen wie `maximumEntities` und `maximumFieldsPerEntity` begrenzen nur den Interpreter-Request, nie die appseitige Bindung oder Revalidation. App-owned fachliche Aliasse und lokalisierte Feldsynonyme liegen versioniert in `GraphMentionAliases.json`; Matching-Code enthält keine Graph-Domänennamen.
- Semantischer Interpreter → value-only Request mit normalisierter Frage, Antwortsprache, begrenzten nutzersichtbaren Schemaanzeigenamen, sicheren Conversation-Beschreibungen und fachlicher Scope-Beschreibung → strikt validierter untrusted Draft. UUIDs, interne Aliasse, Tool-/Query-/Evidence-/Artifact-Details, technische Limits und freier Antworttext sind im Vertrag ausgeschlossen oder werden appseitig abgelehnt.
- Akzeptierter Find-Nodes-Draft → vollständige appseitige Auflösung gegen `schemaContext.foundationalAliases`, aktuellen Graph-, Entity-, Node- und Selection-Scope → feste lokale `SearchGraphTool`-Action mit zentralem Search-Limit, stabiler Reihenfolge, Treffer- und Evidence-Revalidierung, Search-Result-Artifact und atomarem Conversation-Commit. Treffer belegen nur Existenz, Anzeigename und Navigation; Search-Snippets bleiben als Detailwertquelle unzulässig.
- Akzeptierter Entity-List-Draft → vollständige appseitige Entity-Auflösung und Ambiguitätsbehandlung → feste lokale Query-Action ohne erfundene Filter, mit Node Identity, stabiler Namenssortierung, deterministischem Tie-Breaker und zentraler Default-/Maximum-Limit-Policy. `ResultWindow` und Truncation werden bis in Artifact und lokale Antwort erhalten.
- Akzeptierter Query-Draft → `GraphChatQueryIntentCompiler` → appseitig aufgelöste Entity-/Feld-IDs und -Aliasse, typisierter Filterwert, Sortierung, Node-Identity-Projektion plus explizite Felder, `.count` oder `.groupCount(field)`, evidence-gebundenes Limit und validierter Local-Action-Vertrag. Mehrdeutige gleichnamige Felder erzeugen eine fachliche Pending Clarification ohne technische IDs.
- Akzeptiertes Refinement → ausschließlich frisch revalidierter `GraphChatResolvedConversationScope` mit konkreter Entity und konkreten Attribute-Nodes → exakter Node-/Selection-Scope, geerbte Quellfilter plus neue AND-Filter und nur bei expliziter Absicht ersetzte Sortierung. Ein Refinement kann weder zuvor ausgeschlossene noch graphfremde Nodes zurückholen.
- Akzeptierter Node-Details-Draft → genau ein erneut autorisierter `NodeRefKey` → feste `GetNodeTool`-Action mit appseitigem Related-Limit `20` → Metadaten-only Attachments, Evidence, Node-Detail-Artifact, `nodeResolved`, Result-/`CURRENT`-Bindung und lokaler Abschluss. Gleichnamige Nodes werden geklärt; ein Node außerhalb des Chat-Scopes wird nicht geladen.
- Akzeptierter Comparison-Draft → `GraphChatComparisonPlan` mit höchstens `8` Nodes und `8` Features. Gleichartige Attributes derselben Entity verwenden eine Selection Query mit Node Identity und expliziten oder deterministischen Defaultfeldern. Andere Node-Kombinationen verwenden ausschließlich gemeinsame Strukturmerkmale; Notizinhalte werden nicht in Output oder Evidence transportiert und nicht semantisch analysiert, Attachment-Inhalte werden gar nicht geladen.
- Akzeptierter Graph-State-Draft → appseitig gewählter Aspekt `overview`, `counts`, `structure` oder `health` → feste `GraphStatsTool`-Action mit Hub-Limit `10` und erlaubter Metric-/Ranking-/Health-Finding-Auswahl. Der Pfad ist nur bei exakt `.entireGraph` zulässig und erweitert Entity-, Node- oder Selection-Chats niemals.
- Erfolgreiche semantische Find-/Query-/Node-/Comparison-/Graph-State-Turns verwenden den gemeinsamen Local Intent Execution Kernel, lokale Tools, Evidence Registry, Artifact Factory, Primary Result Ledger, deterministischen Answer Fallback, Presentation Firewall und Conversation Reducer. Es entsteht weder eine freie Answer-Provider-Session noch ein zweiter Modellaufruf.
- Nach erfolgreicher lokaler Revalidation rekonstruiert der Finalizer eine `GraphChatIntentInterpretation` aus dem Typed Intent und dem validierten Query-Plan beziehungsweise dem revalidierten Search-/Node-/Comparison-/Stats-Execution-Nachweis. Der lokalisierte Titel wird unmittelbar oberhalb des direkten Antworttexts gezeigt; eine Interpretation ohne kompilierten Intent wird nicht erfunden.
- Tap auf eine editierbare Interpretation → aktueller value-only Schema-/Scope-Snapshot und Live-Prüfung der gebundenen Artifact-Session → intent-spezifischer fachlicher Sheet-Editor. Apply lädt Schema und Conversation-Checkpoint erneut, kompiliert die Korrektur direkt appseitig und führt die neue Action über den Local Intent Execution Kernel aus; Semantic Interpreter und freier Answer Provider werden nicht aufgerufen.
- Erfolgreicher Correction-Rerun → Compare-and-set gegen den unveränderten aktuellen Conversation State → Kandidat aus dem Checkpoint vor dem ursprünglichen Turn plus neuem Turn → Entfernung des alten Assistant-Turns und aller nachfolgenden Turns nach derselben Suffix-Policy wie Edit-and-Resend → Feedback-, Evidence-Presentation- und Artifact-Cleanup → neuer finalisierter Answer und neues `CURRENT`. Failure oder Cancellation lassen den alten erfolgreichen Transcript- und Runtime-Zustand autoritativ.
- Nur explizite `.unrecognized`-/`.openEnded`-Drafts oder eine eindeutig technische Interpreter-Nichtverfügbarkeit nach höchstens einem Compact-Retry erreichen die unveränderte freie Provider-Pipeline. Ein erkannter, aber nicht sicher auflösbarer, schemawidriger oder manipulierter Draft wird geklärt oder abgelehnt und niemals als freie Tool-Improvisation fortgesetzt.
- Foundational Single-Field → exakt ein graph-/chat-gescopter Attribute-Node, Node Identity plus exakt ein validiertes Feld, appseitiges Limit `1`, erneute Query-Plan-/Scope-Validierung und Ausführung über die bestehende Query Engine. Der Erfolg wird als typisierte einzeilige Table-Artefaktprojektion transportiert. Ein Suchtreffer allein ist nie Detailwert-Autorität.
- Foundational Entity Collection → unveränderter autorisierter Entity-/Node-/Selection-Scope, Node-Identity-Projektion, stabile Namenssortierung und `GraphQueryPlanLimits.maximumResultLimit`. „Alle“ bedeutet alle autorisierten Ergebnisse bis zu diesem gemeinsamen Sicherheitslimit; Truncation bleibt im Result-Artefakt und in der lokalisierten Mindestantwort sichtbar.
- Foundational Node Details → exakt ein durch den Mention Resolver gebundener und autorisierter Node, fester Node-Scope und die bestehende lokale `GetNodeTool`-Action mit appseitigem Related-Limit. Der Turn läuft ohne Interpreter und Answer Provider durch denselben Typed-Intent-, Kernel-, Evidence-, Artifact-, Finalizer- und Commit-Lifecycle.
- Mehrdeutiger Foundational Intent → bestehende graph-/session-/turngebundene Pending Clarification mit ausschließlich fachlichen Anzeigenamen. Die Auswahl setzt dieselbe Originalfrage fort und wird gegen Schema, Scope und Quell-Turn erneut validiert.
- Modell-Tool-Call → typisierte Conversation-Scope-Auflösung → Query-Plan-Validierung; ein Modell-Entity-Alias ist bei einer homogenen revalidierten Conversation-Referenz nur ein untrusted Hint.
- Semantisch repair-fähiger Tool-Call → strukturiertes validiertes Repair-Ergebnis → höchstens ein vollständiger erneuter Tool-Call → unveränderte Validatoren und Tool-Budgets.
- Erfolgreicher Tool-Call → request-/graph-/session-/turn-/transaktionsgebundenes Execution Ledger → deterministische Primary-Result-Auswahl → erneute Evidence-/Artifact-Revalidierung im Finalizer.
- Kompilierter Single-Field-Turn → eindeutige Cardinality-/Conflict-Prüfung → `GraphChatAuthoritativeFactExtractor` → lokalisierter `GraphChatAuthoritativeFactRenderer` → Presentation Firewall → typisierter Answer-State → identischer Text in UI und Copy. Provider-Sections und Follow-ups werden für diesen Turn verworfen.
- Andere Modellantwort → `GraphChatPresentationFirewall` → Konsistenzprüfung gegen das revalidierte Primärergebnis → gegebenenfalls deterministischer Answer Fallback → typisierter Answer-State → UI/Copy.
- Erfolgreiche normale `.answer` → nicht leerer presentation-sicherer Text plus mindestens validierte Evidence oder ein Result-Artefakt. Clarification, No Results, Unsupported und Failure bleiben eigene typisierte Zustände.
- Öffentlicher Fehlercode → lokalisierter, codebasierter UI-Text; rohe Tool-, Resolver-, Provider-, Repository- und Validierungsdetails bleiben außerhalb von UI und Copy.

### Graph Chat Ausbaustufe 2 – produktiver Cutover

Die produktive Routing-Reihenfolge ist fest und darf nicht durch einen Adapter oder Repair-Pfad umgangen werden:

1. Request Preflight;
2. Unsupported- und bestehende Clarification-Prüfung;
3. Foundational Fast Path;
4. toolfreier Semantic Intent Interpreter;
5. Draft Validation;
6. appseitige Schema-, Scope- und Conversation-Auflösung;
7. fachliche Clarification oder vollständig gebundener Compiled Intent;
8. lokale Tool-/Query-Ausführung, Evidence-/Artifact-Commit und Finalisierung;
9. Legacy Provider ausschließlich für `unrecognized`, `openEnded` oder eindeutige technische Interpreter-Nichtverfügbarkeit.

Für Find Nodes, Entity List, Filtered List, Count, Group Count, Node Details, Refinement, Compare Nodes und Inspect Graph State gilt damit: höchstens ein Semantic-Interpreter-Kontakt, kein Answer Provider, kein modellbestimmter Tool Call oder `GraphQueryPlan`, keine technischen Modell-Aliasse, kein modellbestimmtes Ergebnislimit und kein modellgenerierter finaler Fachtext. Der Foundational Fast Path besitzt null Modellkontakte. Interpretation Correction kompiliert aus der vertrauenswürdigen gebundenen Interpretation neu und verwendet weder Interpreter noch Provider.

Jeder erfolgreiche Typed-Intent-Turn besitzt nicht leeren lokalisierten App-Text, eine sichere appseitig rekonstruierte „Verstanden als“-Interpretation und validierte Evidence oder mindestens ein Result-Artefakt. Derselbe finalisierte `GraphChatAnswer.directAnswer` ist die Quelle für UI und Copy. UUIDs, interne Aliasse, Drafttext und rohe Tool-, Query-, Resolver-, Repository- oder Integrity-Fehler sind presentation-seitig verboten.

Cancellation, Graph-/Scope-/Lock-Wechsel, Regenerate, Edit-and-Resend und Correction werden über Generation, Request, Conversation, Turn und Artifact-Session revalidiert. Ein Request erzeugt genau ein Terminal Event; verspätete Interpreter-, Query-, Comparison- oder Correction-Ergebnisse können weder Conversation noch Artifact Session, Ledger oder UI committen. Pending Clarifications laufen nach der zentralen Policy ab.

Content-free Planner-Observability unterscheidet Foundational Fast Path, Semantic Interpreter, Draft Outcome, lokale Intent-Familie, Legacy-Fallback-Grund, Compact-Retry, Clarification, Correction Rerun, Terminal Outcome und Cancellation Stage. Zusätzlich unterscheidet die Binding-Diagnose ausschließlich die geschlossenen Kategorien Entity/Node/Feld nicht gebunden, mehrere plausible Kandidaten und ungültige Draft-Kombination. Es werden keine Fragen, Namen, Filter- oder Fachwerte, Aliasse oder IDs erfasst.

Bewusst frei beziehungsweise nicht als Typed Intent unterstützt bleiben allgemeine Erklärungen, Synthesen und Bewertungen, Multi-Hop-Analysen, Minimum/Maximum und andere nicht definierte Aggregationen, Attachment-Inhaltsanalyse sowie Schreib- oder Mutationswünsche. Echte offene read-only Fragen dürfen weiterhin die bestehende evidenz- und presentation-gesicherte Legacy-Pipeline verwenden; Graph-Writes bleiben grundsätzlich ausgeschlossen.

Die gebündelte `GraphChatTypedIntentPlannerAcceptanceTests`-Suite verknüpft 18 reale In-Memory-Szenarien für alle Familien, Fast Path, Clarification, Interpretation, Correction, Draft-Manipulation, Legacy-Fallback, Sicherheitsbindungen, Cancellation und große Schemas/Compact-Retry. Ergänzende Grounding-Suites verwenden fachlich getrennte Medizin-, Bibliotheks- und IT-Operations-Fixtures und prüfen Deutsch/Englisch, Unicode, Umlaute/ß, Flexion, konservative Tippfehler, Mehrdeutigkeit, vollständige Kataloge jenseits der Promptgrenzen sowie Entity-/Node-/Selection- und Cross-Graph-Scope. Die filesystem-synchronisierten Xcode-Gruppen ordnen neue Produktions-, Ressourcen- und Testdateien automatisch dem korrekten Target zu.

## Folder Map

| Ordner/Pfad | Zweck |
|---|---|
| `BrainMesh/AppRoot/` | Root-Host, Startup und Scene-Lifecycle |
| `BrainMesh/Models/` | SwiftData-Modelle und Detailtypen |
| `BrainMesh/DataAccess/` | Read Repository, scoped Fetches, Mutation Committer/Event Bus |
| `BrainMesh/Bootstrap/` | Default-Graph, Legacy-Scopes, Folded-Field-Backfills |
| `BrainMesh/Mainscreen/` | Home, Detailansichten, Editoren und zentrale CRUD-Flows |
| `BrainMesh/GraphCanvas/` | Canvas, Layout/Physics, Loader, Interaktion und Inspector |
| `BrainMesh/GraphChat/` | On-Device-Chat, Tools, Query, Conversation, Artifacts und UI |
| `BrainMesh/Search/` | Command Center und lokaler Suchindex |
| `BrainMesh/Attachments/` | Attachment-Modell, Import, Cache, Hydration und Preview |
| `BrainMesh/PhotoGallery/` | Gallery-Flows und Bildaktionen |
| `BrainMesh/GraphTransfer/` | `.bmgraph`-/`.bmbackup`-Import und -Export |
| `BrainMesh/GraphPicker/` | Graphauswahl, Anlage, Rename, Dedupe und Delete |
| `BrainMesh/Stats/` | Statistiken, Health Checks und Stats-UI |
| `BrainMesh/Settings/` | Einstellungen, Sync-/Cache-Wartung und Support |
| `BrainMesh/Security/` | Locking, Biometrie und Passwortschutz |
| `BrainMesh/Pro/` | StoreKit-Produkte und Entitlement-State |
| `BrainMesh/Onboarding/` | Onboarding und Fortschritt |
| `BrainMesh/Observability/` | Logger, Dauer- und Signpost-Helfer |
| `BrainMeshTests/` | Swift-Testing-Suites und Architektur-Inventare |
| `BrainMeshUITests/` | XCUITest-Einstieg |

## Data Model Map

### `MetaGraph`

Pfad: `BrainMesh/Models/MetaGraph.swift`

- Schlüssel: `id: UUID`, `createdAt`.
- Anzeige/Suche: `name`, `nameFolded`.
- Sicherheit: Biometrie-/Passwort-Flags, Salt, Hash, Iterationen.
- Keine SwiftData-Relationship-Arrays zu Graph-Inhalten.
- Graph-Inhalte referenzieren den Graph über skalare `graphID`.

### `MetaEntity`

Pfad: `BrainMesh/Models/MetaEntity.swift`

- Schlüssel/Scope: `id`, `createdAt`, optionale `graphID`.
- Inhalt: `name`, `nameFolded`, `notes`, `notesFolded`, Icon.
- Medien: autoritatives `imageData`, lokales `imagePath`.
- Sicherheit: eigene Lock-/Passwortfelder.
- Relationships:
  - `attributes` → `MetaAttribute`, Cascade, inverse `owner`;
  - `detailFields` → `MetaDetailFieldDefinition`, Cascade, inverse `owner`.

### `MetaAttribute`

Pfad: `BrainMesh/Models/MetaAttribute.swift`

- Schlüssel/Scope: `id`, optionale `graphID`.
- Inhalt: Name/Notes jeweils plus gefaltetes Suchfeld, Icon.
- Medien/Sicherheit analog zur Entity.
- Relationship `owner` → `MetaEntity`.
- Relationship `detailValues` → `MetaDetailFieldValue`, Cascade.
- `searchLabelFolded` ist ein denormalisiertes Suchlabel.

### `MetaLink`

Pfad: `BrainMesh/Models/MetaLink.swift`

- Schlüssel/Scope: `id`, `createdAt`, optionale `graphID`.
- Endpunkte: Source-/Target-ID und -Kind als skalare Werte.
- Denormalisierte Source-/Target-Labels.
- Inhalt: `kindRaw`, `note`, `noteFolded`.
- Keine SwiftData-Relationship zu den Endknoten.

### `MetaDetailFieldDefinition`

Pfad: `BrainMesh/Models/DetailsModels.swift`

- Schlüssel/Scope: `id`, optionale `graphID`, skalare `entityID`.
- Relationship `owner` → `MetaEntity`.
- Schema: Name/Folded, `typeRaw`, `sortIndex`, `isPinned`, `unit`, `optionsJSON`.

### `MetaDetailFieldValue`

Pfad: `BrainMesh/Models/DetailsModels.swift`

- Schlüssel/Scope: `id`, optionale `graphID`.
- Referenzen: skalare `attributeID`, `fieldID`.
- Relationship `attribute` → `MetaAttribute`.
- Typisierte optionale Slots für String, Int, Double, Date und Bool.
- Keine SwiftData-Relationship zur Field Definition.

### `MetaDetailsTemplate`

Pfad: `BrainMesh/Models/MetaDetailsTemplate.swift`

- Schlüssel/Scope: `id`, `createdAt`, optionale `graphID`.
- Name/Folded.
- `fieldsJSON` speichert Feldtyp, Einheit, Optionen und Pinning.

### `MetaAttachment`

Pfad: `BrainMesh/Attachments/MetaAttachment.swift`

- Schlüssel/Scope: `id`, `createdAt`, optionale `graphID`.
- Owner: `ownerKindRaw` und `ownerID` als skalare Referenz.
- Inhaltstyp: Datei, Video oder Gallery-Bild.
- Metadaten: Titel, Dateiname, UTI, Erweiterung, Byteanzahl.
- `fileData` nutzt `@Attribute(.externalStorage)` und ist autoritativ.
- `localPath` zeigt nur auf einen rekonstruierbaren Cache.
- Keine SwiftData-Relationship zum Owner.

### Modell-Invarianten

- Scope- und Referenzintegrität ist teilweise Service-Verantwortung, nicht Relationship-Verantwortung.
- `graphID` ist auf Legacy-kompatiblen Datensätzen optional.
- Im Quellstand existiert kein `@Attribute(.unique)`.
- IDs müssen deshalb zusammen mit `graphID` aufgelöst werden.
- Cascades decken Entity → Attributes/Definitions und Attribute → Values ab.
- Links, Attachments und skalare Field-Referenzen benötigen explizite Cleanup-Services.

### Detaildaten-Integrität und Authority

Die zentrale, value-only Policy liegt in `BrainMesh/DataAccess/DetailDataIntegrityPolicy.swift`; SwiftData-facing Write-Validierung und datenschutzneutrale Diagnose liegen in `BrainMesh/DataAccess/DetailDataIntegrityValidation.swift`. UI, `GraphReadRepository`, Chat-Query-Quellen, Transfer und Search dürfen Detailwerte nicht unabhängig per Fetch-Reihenfolge auswählen.

Invarianten:

- Eine `MetaDetailFieldDefinition` ist nur gültig, wenn `owner` vorhanden ist, `entityID == owner.id` gilt und `graphID == owner.graphID` nicht nil ist.
- Ein `MetaDetailFieldValue` ist nur gültig, wenn `attribute` samt Entity-Owner vorhanden ist, `attributeID == attribute.id` gilt und Value, Attribute, Entity sowie referenzierte Field Definition denselben nicht-nil Graphen besitzen.
- Die Field Definition muss zur Entity des Attributes gehören.
- Der Authority-Key ist `(graphID, attributeID, fieldID)`.
- Genau der zum Field-Typ gehörende Storage-Slot darf belegt sein. Kein Slot bedeutet fachlich leer; mehrere Slots, ein falscher Slot oder ein nicht-endlicher Double-Wert sind ungültig.
- Authority-Auswertungen und Actor-Grenzen verwenden ausschließlich `Sendable` Value-Snapshots/DTOs; SwiftData-Modelle verlassen ihren Context/Executor nicht.

Duplicate-Resolution:

- Records und Keys werden stabil nach der lexikographischen UUID-Darstellung sortiert; der kleinste passende Record ist der Keeper.
- Bei ausschließlich leeren Records bleibt ein leerer Keeper.
- Bei leer plus gefüllt gewinnt der gefüllte Record.
- Gleich typisierte Werte werden nur für den Vergleich normalisiert: Text/Choice werden außen getrimmt und kanonisch Unicode-normalisiert, Zahlen, Datum und Bool anhand ihres exakten typisierten Werts verglichen. Der gespeicherte Keeper-Wert selbst wird nicht umgeschrieben.
- Leere und nach dieser Regel identische Duplikate dürfen gelöscht werden.
- Unterschiedliche gefüllte Werte sowie ungültige Typed-Storage-Records liefern keine Authority. Sie bleiben erhalten; UI zeigt einen neutralen Konfliktzustand, Repository, Chat und Search liefern daraus keinen Fakt.
- Der Query-Source-Snapshot transportiert konfliktbehaftete Authority-Keys separat von den autoritativen Werten. So bleibt ein ungelöster Konflikt bis zur Single-Fact-Entscheidung sichtbar, obwohl kein willkürlich gewählter Wert in den Query-Zeilen erscheint.
- Ein bewusster Save im Detail-Editor setzt den gewählten typisierten Wert und konsolidiert alle reparierbaren Records desselben Keys in derselben SwiftData-Transaktion auf einen Record. Ein Save-Fehler rollt die gesamte Konsolidierung zurück.
- Es wird bewusst kein CloudKit-problematisches `@Attribute(.unique)` verwendet.

## Sync / Storage

### Autoritativer Store

- `BrainMesh/BrainMeshApp.swift` erstellt ein SwiftData-`Schema` aus acht Modeltypen.
- Primärkonfiguration: `ModelConfiguration(schema:cloudKitDatabase: .automatic)`.
- Entitlement: privater Container `iCloud.de.marcfechner.BrainMesh`.
- Debug: Container-Initialisierungsfehler führt zu `fatalError`.
- Release: CloudKit-Fehler führt zu neuem lokalen `ModelConfiguration`-Fallback.
- `BrainMesh/Settings/SyncRuntime.swift` zeigt Storage-Modus und iCloud-Accountstatus.
- Der Accountstatus ist kein Beleg für erfolgreichen Datenabgleich.

### Save- und Invalidierungsfluss

- Normale Graphmutationen gehen über `BrainMesh/DataAccess/Mutations/GraphMutationCommitter.swift`.
- Reihenfolge: Batch validieren → `ModelContext.save()` → Mutation Event publizieren.
- Bei Save-Fehler wird zurückgerollt; nach erfolgreichem Save wird der Event nicht durch Cancellation unterdrückt.
- `BrainMesh/DataAccess/Mutations/GraphMutationEventBus.swift` liefert prozesslokale Events.
- Suchindex, Home-Caches und Stats/Health reagieren auf diese Events.
- Remote CloudKit-Änderungen umgehen den prozesslokalen Event Bus.
- `BrainMesh/Search/Index/GraphSearchIndexReconciler.swift` gleicht deshalb beim Foreground und bei Bedarf erneut ab.

### Migration und Backfill

- Kein `VersionedSchema` und kein `SchemaMigrationPlan` im Quellstand.
- `BrainMesh/Bootstrap/GraphBootstrap+Repair.swift`:
  - legt bei Bedarf einen Default-Graph an;
  - füllt fehlende `graphID` für Entities, Attributes, Links und Templates;
  - klassifiziert vor der ersten Mutation alle Field Definitions und Detail Values;
  - migriert Details ausschließlich über ihre tatsächlichen Owner-Relationships, repariert eindeutige skalare Owner-IDs und bereinigt nur sichere Duplikate;
  - übernimmt Cross-Graph-, verwaiste oder mehrdeutige Detailrecords nicht in den Default-Graph;
  - committed die gesamte Reparatur über `GraphMutationCommitter` und markiert betroffene Graphen per Integrity-Rebuild-Event.
- `BrainMesh/Bootstrap/GraphBootstrap+Backfill.swift` füllt gefaltete Notes-Felder.
- `BrainMesh/Attachments/AttachmentGraphIDMigration.swift` repariert Legacy-Attachments owner-lokal.
- Attachment-Reparatur wird u. a. aus `BrainMesh/Attachments/MediaAllLoader.swift` und `BrainMesh/PhotoGallery/PhotoGalleryActions.swift` angestoßen.
- **UNKNOWN U11**: Ob damit jedes ungeöffnete Legacy-Attachment vor Export, Suche oder Löschung sicher repariert wird.

### Lokaler Suchindex

- `BrainMesh/Search/Index/GraphSearchIndexStore+Schema.swift` öffnet SQLite in Application Support.
- Laufzeitpfad: `Application Support/BrainMesh/Search/Index/GraphSearchIndex.sqlite`.
- WAL, `synchronous=NORMAL`, Foreign Keys und Busy Timeout sind gesetzt.
- Backend: FTS5 mit Trigram/Unicode, sonst indizierter Fallback.
- Integritäts-/Versionsfehler lösen einen rekonstruierenden Rebuild aus.
- Das Indexverzeichnis wird explizit vom Geräte-Backup ausgeschlossen.
- Der Index ist abgeleitet, nicht autoritativ.
- Detailwert-Dokumente entstehen ausschließlich aus der Authority-gefilterten `GraphReadRepository`-Quelle; konflikthafte oder ungültige Detailwerte werden nicht indexiert.

### Medien-Caches

- Bilder: Memory + Disk in `Application Support/BrainMeshImages`.
- Attachments: Disk in `Application Support/BrainMeshAttachments`.
- `imageData` bzw. `fileData` bleiben autoritativ.
- Hydratoren materialisieren fehlende Dateien lokal.
- Settings kann Cachegrößen anzeigen und Reparaturen anstoßen.
- Im Cache-Code ist keine Backup-Exclusion für diese beiden Verzeichnisse gesetzt.
- **UNKNOWN U9**: Ob die Aufnahme dieser rekonstruierbaren Caches in Gerätebackups beabsichtigt ist.

### Sonstiger lokaler Zustand

- Aktiver Graph, Appearance, Display, Recents, Onboarding, Importoptionen und Canvas-Presets liegen in UserDefaults.
- Graph-Chat-History und Chat-Artefakte sind sessiongebunden/in-memory; das Primary-Result-Ledger lebt nur für den aktuellen Request. Provider- und lokale Typed-Intent-Pfade bereinigen Evidence, Presentation und Ledger nach Failure, Cancellation oder erfolgreichem Commit; lokale Artifact-Transaktionen werden bei Fehler zurückgerollt und bereits committed wirkende Session-Artefakte nach einem äußeren Commit-Fehler entfernt. Interpretation Corrections behalten alte committed Artifacts bis zum erfolgreichen Conversation-Compare-and-set und veröffentlichen den Ersatz erst danach; eine stale Artifact-Session kann keinen Rerun autorisieren.
- `.bmgraph` exportiert Struktur als JSON, ohne Attachments.
- `.bmbackup` exportiert Struktur und Attachments mit Manifest und SHA-256-Prüfsummen.
- Import nutzt Checkpoint-Saves; Fehlerbereinigung entfernt partielle Graphdaten und Cachedateien.

### Offline- und Multi-Device-Verhalten

- SwiftData kann lokal arbeiten, während CloudKit später abgleicht.
- Release kann bei Containerfehlern vollständig auf local-only starten.
- Es gibt keine anwendungseigene Konfliktauflösungs- oder Sharing-Schicht.
- Foreground-Reconciliation repariert den lokalen Suchindex nach externen Änderungen.
- **UNKNOWN U2**: Wie ein local-only gestarteter Store später kontrolliert in den CloudKit-Store überführt wird.
- **UNKNOWN U10**: Welche fachliche Konfliktsemantik bei gleichzeitigen Änderungen auf mehreren Geräten erwartet wird.

## UI Map

### Root

- `BrainMesh/AppRoot/AppRootView.swift`
  - Inhalt: `ContentView`;
  - Sheet: Onboarding;
  - Full-screen Cover: Graph Unlock;
  - Lifecycle: Startup, Background-Lock, Foreground-Reconciliation.

### Root Tabs

`BrainMesh/ContentView.swift` verwendet `TabView` und `RootTabRouter`.

1. **Entities**
   - `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeView.swift`
   - eigener `NavigationStack`;
   - Graph Picker, Add Entity, Display Settings als Sheets;
   - Navigation zu Entity/Attribute-Details.
2. **Graph**
   - `BrainMesh/GraphCanvas/GraphCanvasScreen/GraphCanvasScreen.swift`
   - eigener `NavigationStack`;
   - Graph Picker, Focus Picker, Inspector, Detail- und Editor-Sheets;
   - iPad: Graph Copilot als Inspector.
3. **Chat**
   - `BrainMesh/GraphChat/UI/GraphChatTabView.swift`
   - eigener `NavigationStack`;
   - Free Preview/Paywall und Verfügbarkeitsprüfung.
4. **Stats**
   - `BrainMesh/Stats/GraphStatsView/GraphStatsView.swift`
   - eigener `NavigationStack`;
   - Health-Issue-Sheet.
5. **Settings**
   - `BrainMesh/Settings/SettingsView.swift`
   - vom Root in einen `NavigationStack` gesetzt;
   - Links zu Anzeige, Pro, Transfer, Sync/Wartung, Guide und Support.

### Globale Flows

- Command Center wird aus `BrainMesh/ContentView.swift` global präsentiert.
- Graphwechsel läuft über `BrainMesh/GraphPicker/`.
- Graph-Security läuft über `BrainMesh/Security/`.
- Entity-/Attribute-Details hosten Rename, Notes, Gallery, Attachments und Details-Editoren.
- Transfer-Flow liegt unter Settings und `BrainMesh/GraphTransfer/`.

### Navigation-Invariante

- Zielauflösung muss `graphID + nodeID` verwenden.
- `BrainMesh/Mainscreen/EntitiesHome/EntitiesHomeRoutes.swift` löst Entity-Ziele aktuell nur über `id` auf.
- Das ist bei nicht eindeutigen IDs oder defekten Imports eine Cross-Graph-Härtungslücke.

## Build & Configuration

- Projekt: `BrainMesh.xcodeproj`.
- Shared Scheme: `BrainMesh.xcodeproj/xcshareddata/xcschemes/BrainMesh.xcscheme`.
- Targets: `BrainMesh`, `BrainMeshTests`, `BrainMeshUITests`.
- Plattform: iPhone und iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).
- Deployment Target: iOS 26.0.
- Swift Language Mode: Swift 5.0.
- Default Actor Isolation: `MainActor`.
- Approachable Concurrency und Member Import Visibility sind aktiviert.
- Bundle ID: `de.marcfechner.BrainMesh`.
- Marketing Version: 1.08; Build: 3.
- `BrainMesh/Info.plist` enthält Background Mode `remote-notification`.
- `BrainMesh/BrainMesh.entitlements` enthält APNs und CloudKit-Container.
- StoreKit-Produkte stehen in `BrainMesh/Info.plist`.
- Lokale StoreKit-Konfiguration: `BrainMesh/BrainMesh Pro.storekit`.
- Keine SPM-Package-Referenzen im Projekt gefunden.
- Keine `.xcconfig`-Dateien gefunden.
- Keine API-Keys oder klassischen Secrets im Quellscan gefunden.
- **UNKNOWN U5**: Ob die `.storekit`-Datei in lokalen Schemes manuell aktiviert wird.
- **UNKNOWN U4**: Welche APNs-Umgebung nach Distribution-Signing effektiv im finalen Archiv steht.

### Setup Steps

- [ ] Repository/Archiv lokal öffnen und `BrainMesh.xcodeproj` in aktuellem Xcode laden.
- [ ] Passendes Development Team und Bundle-/CloudKit-Berechtigungen prüfen.
- [ ] iCloud-Container `iCloud.de.marcfechner.BrainMesh` für das Team freigeben.
- [ ] StoreKit-Testkonfiguration bei Bedarf im Scheme auswählen.
- [ ] App auf einem iOS-26-Simulator ohne iCloud starten.
- [ ] App auf einem physischen iOS-26-Gerät mit iCloud starten.
- [ ] `BrainMeshTests` ausführen.
- [ ] `GraphChatTypedIntentPlannerAcceptanceTests` sowie `GraphChatFoundationalAccuracyAcceptanceTests` separat ausführen und auf null neue Swift-/Concurrency-Warnungen prüfen.
- [ ] `BrainMeshUITests` für die kritischen Root-Flows ausführen.
- [ ] `.bmgraph`- und `.bmbackup`-Roundtrip mit Testdaten prüfen.
- [ ] Multi-Device-Sync mit separaten Änderungen und Offline-Phasen prüfen.

**UNKNOWN U6**: Konkrete Team-, CI-, Testaccount- und CloudKit-Dashboard-Schritte sind nicht im Archiv dokumentiert.

## Conventions

### Naming und Struktur

- Views enden auf `View`, Screens häufig auf `Screen`.
- Actor-basierte Datenquellen enden auf `Loader`, `Store`, `Repository` oder `Service`.
- Große Features sind über `Type+Concern.swift`-Dateien aufgeteilt.
- Persistente Modelle beginnen mit `Meta`.
- Graph-scoped DTOs und Operationen tragen `graphID`.
- Folded-Felder werden für diakritik-/case-insensitive Suche gespeichert.

### Do

- Graphabfragen immer mit `graphID` und fachlicher ID scopen.
- UI nur mit Value-Snapshots oder kleinen, gezielt materialisierten Modelmengen versorgen.
- Graphmutationen über `GraphMutationCommitter` oder einen inventarisierten Mutation Service speichern.
- Mutation Batch erst nach erfolgreichem Save publizieren.
- Neue indexrelevante Felder in Document Builder, Manifest und Reconciliation ergänzen.
- Task-Handles bei UI-Lebensdauer behalten und bei Scope-/View-Wechsel abbrechen.
- Medien-Cache als verwerfbar behandeln; autoritative Binärdaten im Modell erhalten.
- Migrationen idempotent und mit Store-Fixtures testen.
- Detailfeld- und Detailwert-Zuordnungen vor jeder Mutation mit der zentralen Integrity-Policy prüfen.
- Single-Fact-Antworten ausschließlich aus dem revalidierten Primary Result, einem typisierten Result-Artefakt und wertgleicher Detail-Value-Evidence erzeugen.
- Sichtbare Intent-Interpretationen ausschließlich aus dem revalidierten Typed Intent und Execution-Nachweis erzeugen und vor UI beziehungsweise erweiterter Copy-Nutzung erneut durch die Presentation Firewall führen.
- Interpretation Corrections ausschließlich aus einem vertrauenswürdigen `correctionOrigin`, dem Transcript-Branch-Plan und frischen vollständigen Schema-/Scope-/Conversation-Snapshots kompilieren; UI-IDs niemals direkt ausführen.
- Neue lokale Intent-Familien zuerst als validierten Typed-Intent- und Local-Action-Vertrag modellieren; freie Semantik darf nicht in den Execution Kernel wandern.
- Semantische Query-Drafts nur über `GraphChatQueryIntentCompiler` in technische Query-Werte überführen; lokalisierte Werte, Operatoren, Feldzugehörigkeit, Scope und Limits niemals aus Modellargumenten übernehmen.
- Node-Details-, Comparison- und Graph-State-Drafts nur über `GraphChatAdvancedIntentCompiler` und `GraphChatAdvancedIntentPolicy` in technische Actions überführen.
- Same-Entity-Comparisons nur aus autoritativen Query-Zellen mit Evidence pro Wert bauen; fehlende Werte bleiben `.missing`, Integrity-Konflikte und Werte ohne Evidence werden entfernt.
- Default-Comparison-Felder zuerst nach `isPinned`, dann `sortIndex`, normalisiertem Anzeigenamen und ausschließlich internem UUID-Tie-Breaker sortieren; maximal sechs Defaultfelder verwenden.

### Don’t

- Kein `ModelContext.save()` in neuen Graph-Schreibpfaden ohne Event-/Cache-Plan.
- Keine SwiftData-Fetches, Sorts oder synchrone Disk-I/O in SwiftUI-`body`.
- Keine persistenten Modelobjekte über Actor-Grenzen reichen.
- IDs nicht graphübergreifend ohne Scope auflösen.
- Detailwerte nicht per `first(where:)` oder Fetch-Reihenfolge auswählen; Authority immer über den gemeinsamen `(graphID, attributeID, fieldID)`-Vertrag bestimmen.
- Keine konkreten Detailwerte aus `SearchGraph`-Snippets, Provider-Text, Aliassen oder technischen IDs ableiten. Search belegt ohne transportierten Feldwert nur Trefferexistenz, Anzeigename und validierte Navigation.
- Keine Interpretation aus Semantic Draft, Provider-Text, Tool-Content-Strings oder `GraphChatAnswerArtifactQuerySummary.displayText` rekonstruieren.
- Keine textuell editierte Interpretation übernehmen und keinen parallelen UI-Query-Builder einführen; jede Korrektur muss den bestehenden Semantic-Draft-Validator, Query-/Advanced-Intent-Resolver, `GraphQueryPlanValidator`, Scope-Authorization und Local Intent Execution Kernel erneut durchlaufen.
- `CURRENT` oder andere Conversation-Aliase nicht als String bis in Query-Plan oder Repository weiterreichen; zuerst in einen `GraphChatResolvedConversationScope` überführen.
- Ein Refinement niemals aus einem Modellverweis oder stale Resultset rekonstruieren und niemals auf den Entity-/Graph-Scope zurückfallen; die revalidierten Quell-Nodes sind die maximale Ergebnismenge.
- Für gemischte Node-Arten oder unterschiedliche Entities keine gemeinsamen Detailfelder erfinden; nur appseitig belegte Strukturmerkmale vergleichen.
- `GraphStatsTool` niemals außerhalb des exakten Entire-Graph-Chat-Scopes ausführen.
- Notiz- oder Attachment-Inhalte niemals für strukturelle Vergleiche analysieren.
- `imagePath`/`localPath` nicht als autoritative Daten behandeln.
- Keine unbegrenzten UI-Listen oder graphweiten Snapshots ohne bewusstes Limit einführen.
- CloudKit-Accountstatus nicht als Sync-Health interpretieren.

## How to work on this project

### Neues CRUD-Feature hinzufügen

1. Fachliche Invariante und Graph-Scope definieren.
2. Falls nötig Modeländerung samt Migrationsstrategie entwerfen.
3. Fetch/Write als Service oder actor-basierten Loader implementieren.
4. Save über `GraphMutationCommitter` führen.
5. Passende `GraphMutationKind` und Invalidierung ergänzen.
6. Suchdokument/Manifest anpassen, falls Such- oder Chat-Evidenz betroffen ist.
7. View klein halten; komplexe Zustände in ViewModel/Coordinator/Loader auslagern.
8. Unit-Tests für Scope, Save-Fehler, Cancellation und Cache-Invalidierung ergänzen.
9. Multi-Device-/Offline-Verhalten manuell verifizieren.

### Neues Modelfeld hinzufügen

1. Besitzer und Autorität des Felds festlegen.
2. CloudKit-Kompatibilität prüfen.
3. `VersionedSchema`/Migration ergänzen; derzeitige Lücke nicht vergrößern.
4. Folded-/denormalisierte Ableitungen definieren.
5. Import/Export und Backupformat prüfen.
6. Search Document/Manifest/Chat-Schema prüfen.
7. Migrationsfixture eines vorherigen Stores testen.

### Neuen Screen hinzufügen

1. Besitzenden Tab/`NavigationStack` bestimmen.
2. Route mit `graphID` und stabiler ID modellieren.
3. Sheet versus Push anhand des bestehenden Feature-Flows wählen.
4. Loader mit Limit/Paging und Cancellation verwenden.
5. Root-Level-Coordinator nur für tabübergreifende Navigation einsetzen.
6. Locked-Graph- und Pro-Entitlement-Verhalten testen.

### Sync-/Index-Bug untersuchen

1. `SyncRuntime.storageMode` und iCloud-Accountstatus prüfen.
2. Autoritative SwiftData-Daten gegen Search-Index-Ergebnis vergleichen.
3. Mutation-Batch-Publikation nach dem Save verifizieren.
4. Index-Reconciliation bzw. Full Rebuild auslösen.
5. App in Background/Foreground bewegen und erneut prüfen.
6. Dasselbe Szenario offline sowie auf zwei Geräten reproduzieren.

## Quick Wins

1. `VersionedSchema` plus `SchemaMigrationPlan` und Store-Fixture-Tests einführen.
2. Entity-/Link-Routen strikt mit `graphID + id` auflösen.
3. Den exakten Dateiduplikat-Pfad `Mainscreen/EntitiesHome/Cockpit/EntitiesHomeRecentNodesLoader.swift` außerhalb des App-Ordners entfernen, falls **UNKNOWN U8** bestätigt ist.
4. Die drei im Mutation-Inventar als unreferenziert markierten Legacy-Dateien nach Buildprüfung entfernen.
5. `BrainMeshImages` und `BrainMeshAttachments` explizit vom Geräte-Backup ausschließen, falls **UNKNOWN U9** bestätigt ist.
6. Entities Home für die leere Suche paginieren oder begrenzen.
7. `ImageHydrator` mit Cancellation-Checks und Batch-Verarbeitung härten.
8. Indexstatus, letzten Reconcile-Fehler und manuellen Rebuild in Settings sichtbar machen.
9. CloudKit-Import-/Sync-Telemetrie mit Zeitstempel und Fehlerklasse ergänzen.
10. Einen CI-Guard für direkte `save()`-Aufrufe und ungescopte ID-Fetches ergänzen.

## Open Questions

- **UNKNOWN U1**: Welche CloudKit-Schemas und Umgebungen sind deployed, und wie wird deren Änderung freigegeben?
- **UNKNOWN U2**: Wie wird ein Release-local-only-Store später in den CloudKit-Store überführt oder zusammengeführt?
- **UNKNOWN U3**: Welche produktiven Vorgängerstores müssen bei künftigen Modeländerungen garantiert migrieren?
- **UNKNOWN U4**: Welche APNs-Umgebung enthält das signierte Distributionsarchiv effektiv?
- **UNKNOWN U5**: Wird `BrainMesh/BrainMesh Pro.storekit` in einem lokalen oder CI-Scheme aktiviert?
- **UNKNOWN U6**: Welche Development-Team-, CI-, Testaccount- und CloudKit-Dashboard-Schritte gelten?
- **UNKNOWN U7**: Welche realen Maximalgrößen und Performance-Budgets gelten für Graphen und Attachments?
- **UNKNOWN U8**: Sind das externe Dateiduplikat und die drei als unreferenziert inventarisierten Dateien absichtlich noch vorhanden?
- **UNKNOWN U9**: Sollen rekonstruierbare Bild-/Attachment-Caches in Gerätebackups enthalten sein?
- **UNKNOWN U10**: Welche fachliche Konfliktsemantik wird bei parallelen Multi-Device-Änderungen erwartet?
- **UNKNOWN U11**: Erfasst die lazy Attachment-`graphID`-Migration alle Legacy-Daten vor graphweiten Operationen?

Für Risiken, Hot Paths und konkrete Refactor-Schnitte siehe `ARCHITECTURE_NOTES.md`.
