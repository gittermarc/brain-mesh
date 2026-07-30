//
//  GraphChatRelationshipPresentation.swift
//  BrainMesh
//
//  One deterministic presentation source for final answer, copy and UI.
//

import Foundation

nonisolated struct GraphChatRelationshipPresentation:
    Hashable,
    Sendable
{
    let payload:
        GraphChatAnswerArtifactRelationshipPayload

    var title: String {
        if payload.request
            == .linkNotesBetweenNodes,
           let counterpart =
                payload.counterpartNodeLabel {
            return payload.language == .german
                ? "Verbindung zwischen \(payload.centerLabel) und \(counterpart)"
                : "Connection between \(payload.centerLabel) and \(counterpart)"
        }
        return payload.language == .german
            ? "Direkte Verbindungen von \(payload.centerLabel)"
            : "Direct connections of \(payload.centerLabel)"
    }

    var rows:
        [GraphChatAnswerArtifactListRow]
    {
        payload.connections.map {
            connection in
            GraphChatAnswerArtifactListRow(
                id: connection.id,
                primaryText:
                    connection
                        .counterpartLabel,
                secondaryText:
                    secondaryText(
                        for: connection
                    ),
                navigationTargets:
                    connection
                        .navigationTargets,
                evidence:
                    connection.evidence
            )
        }
    }

    var plainText: String {
        let count =
            payload.resultMetadata
                .totalCount
            ?? payload.resultMetadata
                .returnedCount
        if payload.connections.isEmpty {
            return emptyText
                + truncationText
        }
        let lead: String
        if payload.request
            == .linkNotesBetweenNodes,
           let counterpart =
                payload.counterpartNodeLabel {
            lead = payload.language == .german
                ? "Zwischen \(payload.centerLabel) und \(counterpart) gibt es \(count) direkte \(count == 1 ? "Verbindung" : "Verbindungen"): "
                : "There \(count == 1 ? "is" : "are") \(count) direct \(count == 1 ? "connection" : "connections") between \(payload.centerLabel) and \(counterpart): "
        } else {
            lead = payload.language == .german
                ? "\(payload.centerLabel) hat \(count) passende direkte \(count == 1 ? "Verbindung" : "Verbindungen"): "
                : "\(payload.centerLabel) has \(count) matching direct \(count == 1 ? "connection" : "connections"): "
        }
        let items = payload.connections
            .enumerated()
            .map { index, connection in
                "\(index + 1)) \(connection.counterpartLabel) (\(secondaryText(for: connection)))"
            }
            .joined(separator: "; ")
        return lead + items + "."
            + truncationText
    }

    private var emptyText: String {
        if payload.resultMetadata
            .truncation.isTruncated {
            return payload.language == .german
                ? "Aus den aktuell revalidierten Quellen kann keine direkte Verbindung vollständig angezeigt werden."
                : "No direct connection can be shown completely from the currently revalidated sources."
        }
        if payload.request
            == .linkNotesBetweenNodes,
           let counterpart =
                payload.counterpartNodeLabel {
            return payload.language == .german
                ? "Zwischen \(payload.centerLabel) und \(counterpart) gibt es keine passende direkte Verbindung."
                : "There is no matching direct connection between \(payload.centerLabel) and \(counterpart)."
        }
        return payload.language == .german
            ? "Für \(payload.centerLabel) gibt es keine passende direkte Verbindung."
            : "There is no matching direct connection for \(payload.centerLabel)."
    }

    private var truncationText: String {
        guard payload.resultMetadata
                .truncation.isTruncated
        else {
            return ""
        }
        if let omitted =
                payload.resultMetadata
                    .truncation
                    .omittedCount,
           omitted > 0 {
            return payload.language == .german
                ? " \(omitted) weitere Verbindungen sind nicht enthalten."
                : " \(omitted) additional connections are not included."
        }
        return payload.language == .german
            ? " Die Ergebnismenge ist gekürzt; die Gesamtzahl ist nicht sicher bekannt."
            : " The result set is truncated; the total count is not known reliably."
    }

    private func secondaryText(
        for connection:
            GraphChatAnswerArtifactRelationshipConnection
    ) -> String {
        var parts = [
            directionText(
                connection.direction
            ),
        ]
        let authoritativeNote =
            connection.note ?? ""
        let noteHasContent =
            authoritativeNote
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty == false
        if noteHasContent == false {
            parts.append(
                payload.language == .german
                    ? "keine Link-Notiz"
                    : "no link note"
            )
        } else {
            parts.append(
                payload.language == .german
                    ? "Link-Notiz: \(authoritativeNote)"
                    : "Link note: \(authoritativeNote)"
            )
        }
        if connection.parallelCount > 1 {
            parts.append(
                payload.language == .german
                    ? "Verbindung \(connection.parallelOrdinal) von \(connection.parallelCount)"
                    : "connection \(connection.parallelOrdinal) of \(connection.parallelCount)"
            )
        }
        return parts.joined(separator: "; ")
    }

    private func directionText(
        _ direction:
            GraphChatRelationshipConnectionDirection
    ) -> String {
        switch (payload.language, direction) {
        case (.german, .incoming):
            return "eingehend"
        case (.german, .outgoing):
            return "ausgehend"
        case (.german, .selfLink):
            return "Self-Link"
        case (.english, .incoming):
            return "incoming"
        case (.english, .outgoing):
            return "outgoing"
        case (.english, .selfLink):
            return "self-link"
        }
    }
}
