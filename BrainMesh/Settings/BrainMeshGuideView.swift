//
//  BrainMeshGuideView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 02.03.26.
//

import SwiftUI

/// In-app user guide shown from Settings → Hilfe & Support.
///
/// Design goals:
/// - Readable, fast, and fully offline.
/// - Friendly tone, but with concrete steps.
/// - Simple navigation via a table of contents (ScrollViewReader).
struct BrainMeshGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero

                    tableOfContents { anchor in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }

                    sectionKurzstart
                    sectionBegriffe
                    sectionEntitaeten
                    sectionDetails
                    sectionLinks
                    sectionAnhaenge
                    sectionGraph
                    sectionStats
                    sectionSettings
                    sectionSync
                    sectionSicherheit
                    sectionTipps
                    sectionFAQ

                    footer { anchor in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Anleitung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Anchors

private enum GuideAnchor: String, CaseIterable, Hashable, Identifiable {
    case top
    case kurzstart
    case begriffe
    case entitaeten
    case details
    case links
    case anhaenge
    case graph
    case stats
    case settings
    case sync
    case sicherheit
    case tipps
    case faq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Nach oben"
        case .kurzstart: return "Kurzstart (5–10 Minuten)"
        case .begriffe: return "Die wichtigsten Begriffe"
        case .entitaeten: return "Tab „Entitäten“"
        case .details: return "Details-Felder (Mini-Datenbank)"
        case .links: return "Links & Verknüpfungen"
        case .anhaenge: return "Anhänge: Fotos, Videos, Dateien"
        case .graph: return "Tab „Graph“ (Canvas)"
        case .stats: return "Tab „Stats“"
        case .settings: return "Einstellungen"
        case .sync: return "Sync, Speicher & Backup"
        case .sicherheit: return "Graph schützen"
        case .tipps: return "Tipps & Workflows"
        case .faq: return "FAQ"
        }
    }

    var systemImage: String {
        switch self {
        case .top: return "arrow.up"
        case .kurzstart: return "bolt.fill"
        case .begriffe: return "square.grid.2x2"
        case .entitaeten: return "list.bullet.rectangle"
        case .details: return "slider.horizontal.3"
        case .links: return "link"
        case .anhaenge: return "paperclip"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .stats: return "chart.bar"
        case .settings: return "gear"
        case .sync: return "arrow.triangle.2.circlepath"
        case .sicherheit: return "lock"
        case .tipps: return "lightbulb"
        case .faq: return "questionmark.circle"
        }
    }
}

// MARK: - Sections

private extension BrainMeshGuideView {
    var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BrainMesh – Anleitung & FAQ")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Dein persönlicher Wissens‑Graph: Entitäten, Attribute, Links – und ein Canvas, der das Ganze sichtbar macht.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Label("Offline verfügbar", systemImage: "checkmark.seal")
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("Stand: März 2026")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .id(GuideAnchor.top)
    }

    func tableOfContents(onSelect: @escaping (GuideAnchor) -> Void) -> some View {
        let columnCount: Int = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)

        return GuideCard(title: "Inhaltsverzeichnis", systemImage: "list.bullet") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(GuideAnchor.allCases.filter { $0 != .top }) { anchor in
                    Button {
                        onSelect(anchor)
                    } label: {
                        Label(anchor.title, systemImage: anchor.systemImage)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    var sectionKurzstart: some View {
        GuideSection(anchor: .kurzstart, title: GuideAnchor.kurzstart.title) {
            Text("BrainMesh ist kein „Tippe‑hier‑und‑alles‑versteht‑sich“‑Tool. Aber: Nach diesen 8 Schritten läuft’s.")
                .fixedSize(horizontal: false, vertical: true)

            GuideSteps {
                GuideStep("Entitäten anlegen", detail: "Tab „Entitäten“ → + → Entität anlegen. Beispiele: Projekte, Personen, Bücher.")
                GuideStep("Attribute hinzufügen", detail: "Öffne eine Entität und lege Einträge an (z.B. Dune unter Bücher).")
                GuideStep("Notizen nutzen", detail: "In Entität oder Attribut gibt’s ein Notizfeld (Markdown‑fähig).")
                GuideStep("Links setzen", detail: "Verknüpfe Dinge (Projekt X ↔ Person Y) und nutze Link‑Notizen für den Kontext.")
                GuideStep("Details‑Felder definieren", detail: "Pro Entität ein Schema (Status, Datum, Zahl …), pro Attribut die Werte.")
                GuideStep("Graph ansehen", detail: "Tab „Graph“ → Node antippen → Action‑Chip unten nutzen (z.B. + für Expand).")
                GuideStep("Fokus setzen", detail: "Auf Entitäts‑Nodes kannst du Fokus aktivieren, um nur das Umfeld zu sehen.")
                GuideStep("Backup machen", detail: "Einstellungen → Export & Import → Graph als .bmgraph exportieren.")
            }

            GuideCallout(systemImage: "sparkles", title: "Kleiner Geheimtipp") {
                Text("Leg dir erst wenige Entitäten an (2–5). BrainMesh ist am Anfang wie ein leeres Notizbuch: schön – aber erst mit Inhalt wird’s magisch.")
            }
        }
    }

    var sectionBegriffe: some View {
        GuideSection(anchor: .begriffe, title: GuideAnchor.begriffe.title) {
            GuideGrid {
                GuideMiniCard(title: "Graph (Workspace)", detail: "Ein eigener Arbeitsbereich. Wenn du Privat und Job trennen willst: zwei Graphen.")
                GuideMiniCard(title: "Entität", detail: "Ein Thema/Container (z.B. Bücher, Projekte, Reisen).")
                GuideMiniCard(title: "Attribut", detail: "Ein konkreter Eintrag in einer Entität (z.B. Dune unter Bücher).")
                GuideMiniCard(title: "Link", detail: "Eine gerichtete Verbindung zwischen zwei Nodes. Optional mit Link‑Notiz.")
                GuideMiniCard(title: "Details‑Felder", detail: "Frei definierbare Felder pro Entität (Schema) und Werte pro Attribut.")
                GuideMiniCard(title: "Graph Canvas", detail: "Die visuelle Ansicht deines Wissens – zum Navigieren und Zusammenhänge sehen.")
            }
        }
    }

    var sectionEntitaeten: some View {
        GuideSection(anchor: .entitaeten, title: GuideAnchor.entitaeten.title) {
            Text("Hier baust du dein Fundament. Alles, was du später im Graph siehst, entsteht hier.")

            GuideCard(title: "Graph auswählen", systemImage: "square.stack.3d.up") {
                Text("Oben kannst du den aktuellen Graph wählen/wechseln. Wenn du Dinge sauber trennen willst: mehrere Graphen anlegen.")
            }

            GuideCard(title: "Entitäten anlegen", systemImage: "plus.circle") {
                Text("+ → Entität anlegen. Setze Name, Icon/Foto und Notizen. Das Foto ist optional – macht aber sofort „Premium‑Second‑Brain“‑Vibes. 😉")
            }

            GuideCard(title: "Ansicht & Sortierung", systemImage: "arrow.up.arrow.down") {
                Text("Du kannst Layout (Liste/Grid), Dichte und Sortierung anpassen. Wenn Listen dir zu „Excel“ sind: nimm Grid.")
            }

            GuideCallout(systemImage: "info.circle", title: "Warum Entität vs. Attribut?") {
                Text("Denk „Bücher“ (Entität) und „Dune“ (Attribut). Oder „Projekte“ (Entität) und „BrainMesh Launch“ (Attribut). So bleibt alles aufgeräumt, auch wenn’s wächst.")
            }
        }
    }

    var sectionDetails: some View {
        GuideSection(anchor: .details, title: GuideAnchor.details.title) {
            Text("Details‑Felder sind frei definierbare Felder pro Entität (z.B. Jahr, Status, Autor). Die Werte pflegst du pro Attribut.")

            GuideCallout(systemImage: "pin", title: "Merksatz") {
                Text("Entität = Schema · Attribut = Werte. Oder: Entität sagt „Welche Spalten gibt’s?“, Attribut füllt die Zeilen.")
            }

            GuideCard(title: "Details‑Felder anlegen", systemImage: "slider.horizontal.3") {
                GuideBullets {
                    GuideBullet("Entität öffnen (z.B. Bücher).")
                    GuideBullet("Unter Details‑Felder Felder anlegen (Text, Zahl, Datum, Auswahl …).")
                    GuideBullet("Wichtige Felder pinnen (werden oft prominenter gezeigt).")
                }
            }

            GuideCard(title: "Werte pflegen", systemImage: "square.and.pencil") {
                GuideBullets {
                    GuideBullet("Attribut öffnen (z.B. Dune).")
                    GuideBullet("In den Details‑Karten Werte setzen.")
                    GuideBullet("Im Graph gibt’s für gepinnte Felder oft Quick‑Actions.")
                }
            }

            GuideGrid {
                GuideMiniCard(title: "Beispiel: Bücher", detail: "Felder: Jahr, Status, Autor · Dune: Jahr 1965, Status Gelesen")
                GuideMiniCard(title: "Beispiel: Projekte", detail: "Felder: Status, Start, Deadline · BrainMesh Onboarding: Status In Arbeit")
            }
        }
    }

    var sectionLinks: some View {
        GuideSection(anchor: .links, title: GuideAnchor.links.title) {
            Text("Links sind das, was BrainMesh von „Notizen in Ordnern“ unterscheidet. Du verbindest Dinge so, wie dein Kopf sie verbindet.")

            GuideBullets {
                GuideBullet("Link anlegen: In Entität/Attribut → Link hinzufügen.")
                GuideBullet("Richtung zählt: Links sind gerichtet. Wenn du beides willst, lege beide Richtungen an.")
                GuideBullet("Link‑Notiz: Ideal für „warum sind die verbunden?“")
                GuideBullet("Bulk Links: Praktisch, wenn du viele Verbindungen auf einmal erstellen willst.")
            }

            GuideCallout(systemImage: "map", title: "Pro‑Tipp") {
                Text("Verlinke lieber wenige, aber aussagekräftige Links. Ein Graph ist wie ein Stadtplan: zu viele Straßen machen ihn nicht besser.")
            }
        }
    }

    var sectionAnhaenge: some View {
        GuideSection(anchor: .anhaenge, title: GuideAnchor.anhaenge.title) {
            Text("Du kannst Entitäten und Attribute mit Medien/Dateien anreichern: Screenshots, PDFs, Fotos von Whiteboards oder „das eine Bild, das ich sonst nie wieder finde“.")

            GuideBullets {
                GuideBullet("Fotos: importieren oder als Titelbild nutzen.")
                GuideBullet("Videos: können groß sein – bei vielen Videos kann Sync länger dauern.")
                GuideBullet("Dateien: PDFs und Dokumente als Anhang speichern und wieder öffnen.")
            }

            GuideCallout(systemImage: "icloud", title: "Wichtig") {
                Text("Anhänge können deinen iCloud‑Speicher beeinflussen. Viele große Videos bedeuten oft: langsamerer Sync.")
            }
        }
    }

    var sectionGraph: some View {
        GuideSection(anchor: .graph, title: GuideAnchor.graph.title) {
            Text("Hier wird dein Wissen sichtbar. Du kannst Nodes antippen, Nachbarn aufklappen und dich im Netzwerk bewegen.")

            GuideCard(title: "Grundsteuerung", systemImage: "hand.draw") {
                GuideBullets {
                    GuideBullet("Zoom: Pinch‑Geste")
                    GuideBullet("Verschieben: Drag")
                    GuideBullet("Node auswählen: Antippen → Action‑Chip erscheint")
                }
            }

            GuideCard(title: "Action‑Chip", systemImage: "capsule") {
                GuideBullets {
                    GuideBullet("+ Nachbarn aufklappen (Expand)")
                    GuideBullet("Zentrieren auf Auswahl")
                    GuideBullet("Fokus (bei Entitäten): Umfeld zeigen")
                    GuideBullet("Details öffnen")
                    GuideBullet("Pinnen: Node festhalten")
                }
            }

            GuideCard(title: "Inspector", systemImage: "slider.horizontal.3") {
                Text("Der Inspector ist dein Cockpit: Fokus/Hops, Lens, Kamera, Layout & Physics, Limits.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            GuideCallout(systemImage: "waveform.path.ecg", title: "Wenn der Graph „zittert“") {
                Text("Im Inspector unter Layout & Physics: „Layout stabilisieren“, wichtige Nodes pinnen oder Collisions etwas reduzieren.")
            }
        }
    }

    var sectionStats: some View {
        GuideSection(anchor: .stats, title: GuideAnchor.stats.title) {
            Text("Hier bekommst du Überblick: wie groß ist dein Graph, wie verteilt sich Inhalt, und was passiert über Zeit.")
            GuideBullets {
                GuideBullet("Dashboard: Überblick für den aktiven Graph")
                GuideBullet("Vergleiche pro Graph")
                GuideBullet("Medien & Struktur: Anhänge, Links, Counts")
            }
        }
    }

    var sectionSettings: some View {
        GuideSection(anchor: .settings, title: GuideAnchor.settings.title) {
            Text("Die Einstellungen sind dein Hub: Darstellung, Import, Sync/Wartung, Export/Import und Hilfe.")

            GuideGrid {
                GuideMiniCard(title: "Anzeige", detail: "Layouts, Dichte, Counts und Darstellung.")
                GuideMiniCard(title: "Export & Import", detail: "Graph als .bmgraph sichern und später wieder importieren.")
                GuideMiniCard(title: "Import", detail: "Optionen zur Bild-/Video‑Kompression beim Import.")
                GuideMiniCard(title: "Sync & Wartung", detail: "iCloud‑Status und lokale Caches.")
            }
        }
    }

    var sectionSync: some View {
        GuideSection(anchor: .sync, title: GuideAnchor.sync.title) {
            Text("Wenn iCloud aktiv ist, synchronisiert BrainMesh deine Daten über dein iCloud‑Konto. Den Status findest du unter Einstellungen → Sync & Wartung.")
                .fixedSize(horizontal: false, vertical: true)

            GuideCard(title: "Lokale Caches", systemImage: "bolt.horizontal") {
                Text("Bilder/Anhänge werden lokal zwischengespeichert, damit alles flott bleibt. Wenn Vorschaubilder spinnen: Cache neu aufbauen oder bereinigen.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            GuideCallout(systemImage: "externaldrive", title: "Reality‑Check") {
                Text("Sync ist super – aber kein Ersatz für Backups. Wenn dir dein Wissen wichtig ist (Spoiler: ist es), exportiere ab und zu.")
            }
        }
    }

    var sectionSicherheit: some View {
        GuideSection(anchor: .sicherheit, title: GuideAnchor.sicherheit.title) {
            Text("Für sensible Graphen kannst du Schutz aktivieren: Systemschutz (Face ID/Touch ID) oder Passwort.")
            GuideBullets {
                GuideBullet("Systemschutz: Entsperren über Face ID/Touch ID")
                GuideBullet("Passwort: eigener Code pro Graph")
            }
            GuideCallout(systemImage: "lock.shield", title: "Wichtig") {
                Text("Merke dir dein Passwort. „Ich hab’s irgendwo notiert“ ist in BrainMesh ein Lifestyle – aber bitte nicht bei Passwörtern. 😉")
            }
        }
    }

    var sectionTipps: some View {
        GuideSection(anchor: .tipps, title: GuideAnchor.tipps.title) {
            GuideCard(title: "Starte klein", systemImage: "leaf") {
                Text("Guter Start: ein Graph mit 3 Entitäten: Projekte, Personen, Ideen. Dann 5–10 Attribute pro Entität.")
            }
            GuideCard(title: "Links sind Kontext – Notizen sind Bedeutung", systemImage: "text.quote") {
                Text("Ein Link sagt „hängt zusammen“. Eine Link‑Notiz sagt „warum“. Wenn du nur eine Sache konsequent machst: Link‑Notizen.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            GuideCard(title: "Fokus + Hops", systemImage: "scope") {
                Text("Wenn dein Graph groß wird: Fokus setzen und in 1–2 Hops arbeiten. Das ist wie „Zoom auf ein Stadtviertel“ statt ganz München.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var sectionFAQ: some View {
        GuideSection(anchor: .faq, title: GuideAnchor.faq.title) {
            VStack(alignment: .leading, spacing: 10) {
                GuideDisclosure(title: "Wo sind meine Daten gespeichert?") {
                    Text("BrainMesh speichert lokal auf deinem Gerät und synchronisiert (wenn aktiv) über iCloud. Den Sync‑Status findest du in Einstellungen → Sync & Wartung.")
                }
                GuideDisclosure(title: "Warum sehe ich auf iPad andere Daten als auf iPhone?") {
                    Text("Meistens: unterschiedliche Apple‑IDs oder iCloud ist auf einem Gerät deaktiviert. Prüfe iOS‑Einstellungen und in BrainMesh den Sync‑Status.")
                }
                GuideDisclosure(title: "Der Graph wirkt unruhig – was kann ich tun?") {
                    Text("Im Inspector: Layout stabilisieren, wichtige Nodes pinnen oder Collisions etwas reduzieren.")
                }
                GuideDisclosure(title: "Ich finde etwas nicht wieder – gibt’s Suche?") {
                    Text("Ja: Im Tab Entitäten kannst du suchen. Tipp: Suchbegriffe dürfen auch in Notizen vorkommen. Prüfe außerdem, ob du im richtigen Graph bist.")
                }
                GuideDisclosure(title: "Kann ich BrainMesh als Backup exportieren?") {
                    Text("Ja: Einstellungen → Export & Import. Export als .bmgraph sichern und später wieder importieren.")
                }
                GuideDisclosure(title: "Beim Import fehlen Bilder/Thumbnails – ist etwas kaputt?") {
                    Text("Oft ist nur der lokale Cache „hinterher“. In Sync & Wartung kannst du den Bildcache neu aufbauen oder den Anhänge‑Cache bereinigen.")
                }
                GuideDisclosure(title: "Warum dauert Sync länger?") {
                    Text("Viele große Anhänge (besonders Videos) können Sync bremsen. Wenn du Speicher sparen willst: nutze Kompressions‑Optionen beim Import.")
                }
                GuideDisclosure(title: "Wie kann ich einen Graph schützen?") {
                    Text("Im Graph‑Picker pro Graph Schutz aktivieren (Face ID/Touch ID oder Passwort).")
                }
                GuideDisclosure(title: "Verlinkt BrainMesh Graphen untereinander?") {
                    Text("Nein. Links sind bewusst auf den aktiven Graph begrenzt, damit du keine zwei Welten aus Versehen zusammenklebst.")
                }
                GuideDisclosure(title: "Gibt’s das Onboarding nochmal?") {
                    Text("Ja: Einstellungen → Hilfe & Support → Onboarding anzeigen.")
                }
            }
        }
    }

    func footer(onSelect: @escaping (GuideAnchor) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onSelect(.top)
            } label: {
                Label("Zurück nach oben", systemImage: "arrow.up")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)

            Text("Wenn dir etwas fehlt (oder dich etwas nervt): Du findest in „Hilfe & Support“ auch den Link zur Website‑Hilfe. Feedback hilft BrainMesh zu wachsen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }
}

// MARK: - Components

private struct GuideSection<Content: View>: View {
    let anchor: GuideAnchor
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)

            content
        }
        .id(anchor)
    }
}

private struct GuideCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .groupBoxStyle(.automatic)
    }
}

private struct GuideCallout<Content: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                content
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GuideBullets<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GuideBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GuideSteps<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GuideStep: View {
    let title: String
    let detail: String

    init(_ title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct GuideGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: Content

    var body: some View {
        let columnCount: Int = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            content
        }
    }
}

private struct GuideMiniCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct GuideDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @State private var isExpanded: Bool = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        } label: {
            Text(title)
                .font(.headline)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        BrainMeshGuideView()
    }
}
